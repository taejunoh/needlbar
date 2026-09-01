use std::io::Read;
use std::path::PathBuf;
use std::process::{Command, Stdio as ProcessStdio};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Mutex,
};
use std::thread;
use std::time::{Duration, Instant};
use thiserror::Error;

pub const MAX_STDOUT_BYTES: usize = 1024 * 1024;
pub const MAX_STDERR_BYTES: usize = 8 * 1024;
pub const PROCESS_TIMEOUT: Duration = Duration::from_secs(2);
pub const TOTAL_GIT_BUDGET: Duration = Duration::from_secs(10);

#[derive(Debug, Clone)]
pub struct GitRequest {
    kind: GitRequestKind,
    path: PathBuf,
}
#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum GitRequestKind {
    DiscoverRepository,
    ReadCommits,
}
impl GitRequest {
    pub fn kind(&self) -> GitRequestKind {
        self.kind
    }
    pub(crate) fn discover(path: PathBuf) -> Self {
        Self {
            kind: GitRequestKind::DiscoverRepository,
            path,
        }
    }
    pub(crate) fn commits(path: PathBuf) -> Self {
        Self {
            kind: GitRequestKind::ReadCommits,
            path,
        }
    }
}
#[derive(Debug, Clone)]
pub struct GitOutput {
    pub(crate) stdout: Vec<u8>,
    pub(crate) stderr: Vec<u8>,
}
impl GitOutput {
    pub fn new(stdout: Vec<u8>, stderr: Vec<u8>) -> Self {
        Self { stdout, stderr }
    }
}
pub trait GitRunner: Send + Sync {
    fn run(&self, request: GitRequest) -> Result<GitOutput, GitRunnerError>;
}
#[derive(Debug, Clone, Error)]
pub enum GitRunnerError {
    #[error("not a repository")]
    NotRepository,
    #[error("git unavailable")]
    Unavailable,
    #[error("git timed out")]
    TimedOut,
    #[error("git output limit reached")]
    OutputLimitReached,
    #[error("git record limit reached")]
    RecordLimitReached,
    #[error("git child cleanup failed")]
    CleanupFailed,
}

#[derive(Default)]
pub struct BoundedGitRunner {
    budget_started: Mutex<Option<Instant>>,
    poisoned: AtomicBool,
    #[cfg(test)]
    test_executable: Option<PathBuf>,
}
impl BoundedGitRunner {
    #[cfg(test)]
    fn with_test_executable(executable: PathBuf) -> Self {
        Self {
            budget_started: Mutex::new(None),
            poisoned: AtomicBool::new(false),
            test_executable: Some(executable),
        }
    }
    fn remaining_budget(&self) -> Result<Duration, GitRunnerError> {
        let mut started = self
            .budget_started
            .lock()
            .map_err(|_| GitRunnerError::Unavailable)?;
        let now = Instant::now();
        let since = started.get_or_insert(now);
        TOTAL_GIT_BUDGET
            .checked_sub(now.saturating_duration_since(*since))
            .ok_or(GitRunnerError::TimedOut)
    }
}
impl GitRunner for BoundedGitRunner {
    fn run(&self, request: GitRequest) -> Result<GitOutput, GitRunnerError> {
        if self.poisoned.load(Ordering::Acquire) {
            return Err(GitRunnerError::CleanupFailed);
        }
        let remaining = self.remaining_budget()?;
        let discovery = request.kind == GitRequestKind::DiscoverRepository;
        let (directory, arguments): (PathBuf, Vec<String>) = match request.kind {
            GitRequestKind::DiscoverRepository => (
                request.path,
                vec![
                    "rev-parse".into(),
                    "--path-format=absolute".into(),
                    "--show-toplevel".into(),
                ],
            ),
            GitRequestKind::ReadCommits => (
                request.path,
                vec![
                    "log".into(),
                    "--no-ext-diff".into(),
                    "--no-color".into(),
                    "--no-decorate".into(),
                    "--no-show-signature".into(),
                    "--format=%H%x00%cI%x00%s".into(),
                    "-z".into(),
                    "--max-count=501".into(),
                ],
            ),
        };
        let canonical =
            std::fs::canonicalize(directory).map_err(|_| GitRunnerError::Unavailable)?;
        let executable = {
            #[cfg(test)]
            {
                self.test_executable
                    .as_deref()
                    .unwrap_or_else(|| std::path::Path::new("/usr/bin/git"))
            }
            #[cfg(not(test))]
            std::path::Path::new("/usr/bin/git")
        };
        let mut command = Command::new(executable);
        command
            .arg("-C")
            .arg(canonical)
            .args(arguments)
            .stdin(ProcessStdio::null())
            .stdout(ProcessStdio::piped())
            .stderr(ProcessStdio::piped())
            .env_clear()
            .env("GIT_TERMINAL_PROMPT", "0")
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .env("GIT_CONFIG_GLOBAL", "/dev/null")
            .env("GIT_OPTIONAL_LOCKS", "0")
            .env("GIT_PAGER", "cat")
            .env("GIT_CONFIG_COUNT", "1")
            .env("GIT_CONFIG_KEY_0", "core.hooksPath")
            .env("GIT_CONFIG_VALUE_0", "/dev/null");
        let mut child = command.spawn().map_err(|_| GitRunnerError::Unavailable)?;
        let Some(out) = child.stdout.take() else {
            return self.cleanup_failure(&mut child, None, None);
        };
        let Some(err) = child.stderr.take() else {
            return self.cleanup_failure(&mut child, None, None);
        };
        let stdout = spawn_reader(out, MAX_STDOUT_BYTES);
        let stderr = spawn_reader(err, MAX_STDERR_BYTES);
        let deadline = Instant::now() + PROCESS_TIMEOUT.min(remaining);
        let status = loop {
            match child.try_wait() {
                Ok(Some(status)) => break status,
                Ok(None) => {}
                Err(_) => return self.cleanup_failure(&mut child, Some(stdout), Some(stderr)),
            }
            if Instant::now() >= deadline {
                let cleaned = self.cleanup_failure(&mut child, Some(stdout), Some(stderr));
                return if matches!(cleaned, Err(GitRunnerError::CleanupFailed)) {
                    cleaned
                } else {
                    Err(GitRunnerError::TimedOut)
                };
            }
            thread::sleep(Duration::from_millis(5));
        };
        let (stdout, out_over) = stdout.join().map_err(|_| GitRunnerError::Unavailable)?;
        let (stderr, err_over) = stderr.join().map_err(|_| GitRunnerError::Unavailable)?;
        if out_over || err_over {
            return Err(GitRunnerError::OutputLimitReached);
        }
        if !status.success() {
            return Err(if discovery {
                GitRunnerError::NotRepository
            } else {
                GitRunnerError::Unavailable
            });
        }
        Ok(GitOutput { stdout, stderr })
    }
}
impl BoundedGitRunner {
    fn cleanup_failure(
        &self,
        child: &mut std::process::Child,
        stdout: Option<thread::JoinHandle<(Vec<u8>, bool)>>,
        stderr: Option<thread::JoinHandle<(Vec<u8>, bool)>>,
    ) -> Result<GitOutput, GitRunnerError> {
        let killed = child.kill().is_ok();
        let waited = child.wait().is_ok();
        let drained = stdout.map(|thread| thread.join().is_ok()).unwrap_or(true)
            && stderr.map(|thread| thread.join().is_ok()).unwrap_or(true);
        self.cleanup_with(|| killed, || waited, || drained)?;
        Err(GitRunnerError::Unavailable)
    }

    fn cleanup_with<K, W, D>(&self, kill: K, wait: W, drain: D) -> Result<(), GitRunnerError>
    where
        K: FnOnce() -> bool,
        W: FnOnce() -> bool,
        D: FnOnce() -> bool,
    {
        let killed = kill();
        let waited = wait();
        let drained = drain();
        if !killed || !waited || !drained {
            self.poisoned.store(true, Ordering::Release);
            return Err(GitRunnerError::CleanupFailed);
        }
        Ok(())
    }
}
fn spawn_reader<R: Read + Send + 'static>(
    mut reader: R,
    limit: usize,
) -> thread::JoinHandle<(Vec<u8>, bool)> {
    thread::spawn(move || {
        let mut bytes = Vec::new();
        let mut buffer = [0_u8; 8192];
        let mut over = false;
        loop {
            match reader.read(&mut buffer) {
                Ok(0) | Err(_) => break,
                Ok(count) => {
                    if bytes.len().saturating_add(count) > limit {
                        over = true;
                    } else {
                        bytes.extend_from_slice(&buffer[..count]);
                    }
                }
            }
        }
        (bytes, over)
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::os::unix::fs::PermissionsExt;
    use std::process::Command as TestCommand;

    #[test]
    fn byte_caps_and_time_budgets_are_exact_constants() {
        assert_eq!(MAX_STDOUT_BYTES, 1024 * 1024);
        assert_eq!(MAX_STDERR_BYTES, 8 * 1024);
        assert_eq!(PROCESS_TIMEOUT, Duration::from_secs(2));
        assert_eq!(TOTAL_GIT_BUDGET, Duration::from_secs(10));
    }

    #[test]
    fn cumulative_budget_refuses_a_new_process_after_ten_seconds() {
        let runner = BoundedGitRunner {
            budget_started: Mutex::new(Some(Instant::now() - TOTAL_GIT_BUDGET)),
            poisoned: AtomicBool::new(false),
            test_executable: None,
        };
        assert!(matches!(
            runner.remaining_budget(),
            Err(GitRunnerError::TimedOut)
        ));
    }

    #[test]
    fn capped_reader_drops_excess_bytes_without_panicking() {
        let reader = spawn_reader(std::io::Cursor::new(vec![b'x'; 9]), 8);
        let (bytes, exceeded) = reader.join().unwrap();
        assert!(exceeded);
        assert!(bytes.len() <= 8);
    }

    #[test]
    fn lifecycle_faults_attempt_kill_wait_and_poison_before_any_second_spawn() {
        for (kill_ok, wait_ok) in [(true, true), (false, true), (true, false)] {
            let runner =
                BoundedGitRunner::with_test_executable(PathBuf::from("/definitely/not-run"));
            let attempts = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
            let one = attempts.clone();
            let two = attempts.clone();
            let three = attempts.clone();
            let result = runner.cleanup_with(
                || {
                    one.lock().unwrap().push("kill");
                    kill_ok
                },
                || {
                    two.lock().unwrap().push("wait");
                    wait_ok
                },
                || {
                    three.lock().unwrap().push("drain");
                    true
                },
            );
            if kill_ok && wait_ok {
                assert!(result.is_ok());
            } else {
                assert!(matches!(result, Err(GitRunnerError::CleanupFailed)));
            }
            assert_eq!(*attempts.lock().unwrap(), vec!["kill", "wait", "drain"]);
            if !kill_ok || !wait_ok {
                assert!(matches!(
                    runner.run(GitRequest::discover(std::env::temp_dir())),
                    Err(GitRunnerError::CleanupFailed)
                ));
            }
        }
    }

    fn executable(script: &str) -> (tempfile::TempDir, PathBuf) {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("fixture-command");
        fs::write(&path, script).unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o700)).unwrap();
        (directory, path)
    }

    #[test]
    fn test_only_executable_observes_closed_arguments_and_allowlisted_environment() {
        let output = tempfile::NamedTempFile::new().unwrap();
        let script = format!(
            "#!/bin/sh\nprintf '%s\\n' \"$@\" > '{}'\nprintf 'terminal=%s\\n' \"$GIT_TERMINAL_PROMPT\" >> '{}'\nprintf 'nosystem=%s\\n' \"$GIT_CONFIG_NOSYSTEM\" >> '{}'\nprintf 'global=%s\\n' \"$GIT_CONFIG_GLOBAL\" >> '{}'\nprintf 'locks=%s\\n' \"$GIT_OPTIONAL_LOCKS\" >> '{}'\nprintf 'sensitive=%s\\n' \"$SENSITIVE_INHERITED_CANARY\" >> '{}'\n",
            output.path().display(), output.path().display(), output.path().display(), output.path().display(), output.path().display(), output.path().display()
        );
        let (_directory, path) = executable(&script);
        std::env::set_var("SENSITIVE_INHERITED_CANARY", "not-allowed");
        let runner = BoundedGitRunner::with_test_executable(path);
        runner
            .run(GitRequest::discover(std::env::temp_dir()))
            .unwrap();
        std::env::remove_var("SENSITIVE_INHERITED_CANARY");
        let lines = fs::read_to_string(output.path()).unwrap();
        assert_eq!(lines, format!("-C\n{}\nrev-parse\n--path-format=absolute\n--show-toplevel\nterminal=0\nnosystem=1\nglobal=/dev/null\nlocks=0\nsensitive=\n", std::fs::canonicalize(std::env::temp_dir()).unwrap().display()));
        runner
            .run(GitRequest::commits(std::env::temp_dir()))
            .unwrap();
        assert!(fs::read_to_string(output.path()).unwrap().contains("log\n--no-ext-diff\n--no-color\n--no-decorate\n--no-show-signature\n--format=%H%x00%cI%x00%s\n-z\n--max-count=501\n"));
    }

    #[test]
    fn timeout_kills_and_reaps_the_exact_spawned_child() {
        let pid = tempfile::NamedTempFile::new().unwrap();
        let script = format!(
            "#!/bin/sh\necho $$ > '{}'\nexec /bin/sleep 30\n",
            pid.path().display()
        );
        let (_directory, path) = executable(&script);
        let runner = BoundedGitRunner::with_test_executable(path);
        let started = Instant::now();
        let result = runner.run(GitRequest::discover(std::env::temp_dir()));
        assert!(matches!(result, Err(GitRunnerError::TimedOut)));
        assert!(started.elapsed() >= PROCESS_TIMEOUT);
        let child = fs::read_to_string(pid.path()).unwrap();
        assert!(!TestCommand::new("/bin/kill")
            .args(["-0", child.trim()])
            .status()
            .unwrap()
            .success());
    }
}
