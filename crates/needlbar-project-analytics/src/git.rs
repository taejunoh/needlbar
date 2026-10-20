use std::io::Read;
use std::os::unix::io::AsRawFd;
#[cfg(unix)]
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Command, Stdio as ProcessStdio};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex,
};
use std::thread;
use std::time::{Duration, Instant};
use thiserror::Error;

pub const MAX_STDOUT_BYTES: usize = 1024 * 1024;
pub const MAX_STDERR_BYTES: usize = 8 * 1024;
pub const PROCESS_TIMEOUT: Duration = Duration::from_secs(2);
pub const TOTAL_GIT_BUDGET: Duration = Duration::from_secs(10);

#[derive(Clone)]
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
impl std::fmt::Debug for GitRequest {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("GitRequest")
            .field("kind", &self.kind)
            .finish()
    }
}
#[derive(Clone)]
pub struct GitOutput {
    pub(crate) stdout: Vec<u8>,
    pub(crate) stderr: Vec<u8>,
}
impl GitOutput {
    pub fn new(stdout: Vec<u8>, stderr: Vec<u8>) -> Self {
        Self { stdout, stderr }
    }
}
impl std::fmt::Debug for GitOutput {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("GitOutput")
            .field("stdoutBytes", &self.stdout.len())
            .field("stderrBytes", &self.stderr.len())
            .finish()
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
    lifecycle: Mutex<()>,
    poisoned: AtomicBool,
    #[cfg(test)]
    test_executable: Option<PathBuf>,
}
impl BoundedGitRunner {
    #[cfg(test)]
    fn with_test_executable(executable: PathBuf) -> Self {
        Self {
            budget_started: Mutex::new(None),
            lifecycle: Mutex::new(()),
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
        let _lifecycle = self
            .lifecycle
            .lock()
            .map_err(|_| GitRunnerError::CleanupFailed)?;
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
        #[cfg(unix)]
        command.process_group(0);
        let mut child = command.spawn().map_err(|_| GitRunnerError::Unavailable)?;
        let process_group = child.id() as i32;
        let Some(out) = child.stdout.take() else {
            return self.cleanup_failure(&mut child, None, None);
        };
        let Some(err) = child.stderr.take() else {
            return self.cleanup_failure(&mut child, None, None);
        };
        // Set before joining readers that have not both finished on their own.
        let stop_readers = Arc::new(AtomicBool::new(false));
        let stdout = spawn_reader(out, MAX_STDOUT_BYTES, stop_readers.clone());
        let stderr = spawn_reader(err, MAX_STDERR_BYTES, stop_readers.clone());
        let deadline = Instant::now() + PROCESS_TIMEOUT.min(remaining);
        let status = loop {
            match child.try_wait() {
                Ok(Some(status)) => break status,
                Ok(None) => {}
                Err(_) => {
                    stop_readers.store(true, Ordering::Release);
                    return self.cleanup_failure(&mut child, Some(stdout), Some(stderr));
                }
            }
            if Instant::now() >= deadline {
                #[cfg(unix)]
                unsafe {
                    libc::kill(-process_group, libc::SIGKILL);
                }
                stop_readers.store(true, Ordering::Release);
                let cleaned = self.cleanup_failure(&mut child, Some(stdout), Some(stderr));
                return if matches!(cleaned, Err(GitRunnerError::CleanupFailed)) {
                    cleaned
                } else {
                    Err(GitRunnerError::TimedOut)
                };
            }
            thread::sleep(Duration::from_millis(5));
        };
        while !stdout.is_finished() || !stderr.is_finished() {
            if Instant::now() >= deadline {
                #[cfg(unix)]
                unsafe {
                    libc::kill(-process_group, libc::SIGKILL);
                }
                stop_readers.store(true, Ordering::Release);
                let waited = child.wait().is_ok();
                let drained = stdout.join().is_ok() && stderr.join().is_ok();
                if waited && drained {
                    return Err(GitRunnerError::TimedOut);
                }
                self.poisoned.store(true, Ordering::Release);
                return Err(GitRunnerError::CleanupFailed);
            }
            thread::sleep(Duration::from_millis(5));
        }
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
        let killed = child.kill().is_ok() || child.try_wait().ok().flatten().is_some();
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
// The longest a reader waits before re-checking its stop flag.
const READER_POLL_INTERVAL_MILLISECONDS: libc::c_int = 10;

// The group SIGKILL cannot reach a descendant that left the process group
// (setsid/setpgid, e.g. a daemonizing helper) while still holding the write
// end of a pipe, so a blocking read() would wait for that descendant rather
// than for the runner's deadline. Each reader therefore owns its read end and
// only read()s once poll() reports it ready; a ready pipe read never blocks.
// Once `stop` is set, the reader returns within one poll interval and drops,
// i.e. closes, its read end, which keeps every join bounded.
fn spawn_reader<R: Read + AsRawFd + Send + 'static>(
    mut reader: R,
    limit: usize,
    stop: Arc<AtomicBool>,
) -> thread::JoinHandle<(Vec<u8>, bool)> {
    thread::spawn(move || {
        let mut bytes = Vec::new();
        let mut buffer = [0_u8; 8192];
        let mut over = false;
        let mut ready = libc::pollfd {
            fd: reader.as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        };
        while !stop.load(Ordering::Acquire) {
            match unsafe { libc::poll(&mut ready, 1, READER_POLL_INTERVAL_MILLISECONDS) } {
                0 => continue,
                count if count < 0 => {
                    if std::io::Error::last_os_error().kind() == std::io::ErrorKind::Interrupted {
                        continue;
                    }
                    break;
                }
                _ => {}
            }
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
    use std::sync::{Mutex as TestMutex, MutexGuard, OnceLock};

    // The runner's process deadline is deliberately tight. Keep independent
    // shell fixtures out of libtest's parallel scheduler while preserving the
    // lifecycle test's two concurrent calls below. The guard only serializes;
    // it protects no data, so a panicking holder leaves nothing inconsistent.
    // Recover from poisoning so one failing fixture test reports alone instead
    // of failing every later fixture test with a PoisonError.
    static PROCESS_FIXTURE_GUARD: OnceLock<TestMutex<()>> = OnceLock::new();

    fn process_fixture_guard() -> MutexGuard<'static, ()> {
        PROCESS_FIXTURE_GUARD
            .get_or_init(|| TestMutex::new(()))
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    #[test]
    fn byte_caps_and_time_budgets_are_exact_constants() {
        assert_eq!(MAX_STDOUT_BYTES, 1024 * 1024);
        assert_eq!(MAX_STDERR_BYTES, 8 * 1024);
        assert_eq!(PROCESS_TIMEOUT, Duration::from_secs(2));
        assert_eq!(TOTAL_GIT_BUDGET, Duration::from_secs(10));
    }

    #[test]
    fn debug_output_never_exposes_request_paths_or_raw_command_bytes() {
        let request = GitRequest::discover(PathBuf::from("/private/debug-path-canary"));
        let output = GitOutput::new(
            b"stdout-debug-canary".to_vec(),
            b"stderr-debug-canary".to_vec(),
        );
        for text in [
            format!("{request:?}"),
            format!("{output:?}"),
            format!("{:?}", GitRunnerError::Unavailable),
            GitRunnerError::Unavailable.to_string(),
        ] {
            for forbidden in [
                "/private/debug-path-canary",
                "stdout-debug-canary",
                "stderr-debug-canary",
            ] {
                assert!(!text.contains(forbidden), "{text}");
            }
        }
    }

    #[test]
    fn cumulative_budget_refuses_a_new_process_after_ten_seconds() {
        let runner = BoundedGitRunner {
            budget_started: Mutex::new(Some(Instant::now() - TOTAL_GIT_BUDGET)),
            lifecycle: Mutex::new(()),
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
        let (read_end, mut write_end) = std::io::pipe().unwrap();
        std::io::Write::write_all(&mut write_end, &[b'x'; 9]).unwrap();
        drop(write_end);
        let reader = spawn_reader(read_end, 8, Arc::new(AtomicBool::new(false)));
        let (bytes, exceeded) = reader.join().unwrap();
        assert!(exceeded);
        assert!(bytes.len() <= 8);
    }

    #[test]
    fn stopped_reader_returns_and_closes_its_pipe_while_a_writer_still_holds_it() {
        let (read_end, mut write_end) = std::io::pipe().unwrap();
        let stop = Arc::new(AtomicBool::new(false));
        let reader = spawn_reader(read_end, 8, stop.clone());
        // Nothing is written, so only the bounded poll can return the reader
        // to its stop check; give it time to start waiting first.
        thread::sleep(Duration::from_millis(50));
        stop.store(true, Ordering::Release);
        let stopped = Instant::now();
        while !reader.is_finished() {
            assert!(
                stopped.elapsed() < Duration::from_secs(1),
                "a stopped reader must not wait for the writer to close"
            );
            thread::sleep(Duration::from_millis(5));
        }
        reader.join().unwrap();
        let error = std::io::Write::write_all(&mut write_end, b"x")
            .expect_err("the stopped reader closed its read end");
        assert_eq!(error.kind(), std::io::ErrorKind::BrokenPipe);
    }

    #[test]
    fn lifecycle_faults_attempt_kill_wait_and_poison_before_any_second_spawn() {
        let _fixture_guard = process_fixture_guard();
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

    const PREWARM_ARGUMENT: &str = "--needlbar-fixture-prewarm";

    // macOS can hold the first exec of a newly written executable for up to
    // ~3 s after spawn() has returned (exec policy assessment), which is longer
    // than the runner's 2 s PROCESS_TIMEOUT. Pay that one-time cost here,
    // outside the runner, so the timed run starts the fixture promptly and the
    // fixture reaches its intended state before the deadline. The file is
    // never modified after this exec.
    fn executable(script: &str) -> (tempfile::TempDir, PathBuf) {
        let body = script
            .strip_prefix("#!/bin/sh\n")
            .expect("fixture scripts start with #!/bin/sh");
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("fixture-command");
        fs::write(
            &path,
            format!("#!/bin/sh\nif [ \"$1\" = '{PREWARM_ARGUMENT}' ]; then exit 0; fi\n{body}"),
        )
        .unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o700)).unwrap();
        assert!(
            TestCommand::new(&path)
                .arg(PREWARM_ARGUMENT)
                .status()
                .unwrap()
                .success(),
            "fixture prewarm exec must succeed"
        );
        (directory, path)
    }

    // A fixture writes its pid with `echo ... > file`; the file can exist
    // (pre-created or truncated) before the line is written. Only a complete
    // newline-terminated pid proves the fixture reached that point.
    fn complete_pid(path: &std::path::Path) -> Option<libc::pid_t> {
        let text = fs::read_to_string(path).ok()?;
        let line = text.strip_suffix('\n')?;
        line.trim()
            .parse()
            .ok()
            .filter(|pid: &libc::pid_t| *pid > 0)
    }

    // A SIGKILLed descendant is reparented to launchd and remains a zombie
    // (kill(pid, 0) still succeeds on macOS) until reaped. Wait for that
    // explicit condition; the bound is only a safety net and stays far below
    // the fixtures' 30 s sleep, so a surviving descendant still fails.
    fn process_is_gone_within(pid: libc::pid_t, bound: Duration) -> bool {
        let deadline = Instant::now() + bound;
        loop {
            if unsafe { libc::kill(pid, 0) } != 0
                && std::io::Error::last_os_error().raw_os_error() == Some(libc::ESRCH)
            {
                return true;
            }
            if Instant::now() >= deadline {
                return false;
            }
            thread::sleep(Duration::from_millis(10));
        }
    }

    const REAP_SAFETY_BOUND: Duration = Duration::from_secs(5);

    #[test]
    fn test_only_executable_observes_closed_arguments_and_allowlisted_environment() {
        let _fixture_guard = process_fixture_guard();
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
        let _fixture_guard = process_fixture_guard();
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
        let child =
            complete_pid(pid.path()).expect("fixture recorded its pid before the runner deadline");
        assert!(process_is_gone_within(child, REAP_SAFETY_BOUND));
    }

    #[test]
    fn descendant_holding_pipes_is_killed_with_its_process_group_before_deadline_escape() {
        let _fixture_guard = process_fixture_guard();
        let child = tempfile::NamedTempFile::new().unwrap();
        let script = format!(
            "#!/bin/sh\n/bin/sleep 30 &\necho $! > '{}'\nwait\n",
            child.path().display()
        );
        let (_directory, path) = executable(&script);
        let runner = BoundedGitRunner::with_test_executable(path);
        let started = Instant::now();
        assert!(matches!(
            runner.run(GitRequest::discover(std::env::temp_dir())),
            Err(GitRunnerError::TimedOut)
        ));
        assert!(started.elapsed() < Duration::from_secs(3));
        let pid = complete_pid(child.path())
            .expect("fixture recorded the descendant pid before the runner deadline");
        assert!(process_is_gone_within(pid, REAP_SAFETY_BOUND));
    }

    #[test]
    fn exited_parent_pipe_cleanup_returns_timeout_and_runner_is_reusable() {
        let _fixture_guard = process_fixture_guard();
        let directory = tempfile::tempdir().unwrap();
        let marker = directory.path().join("already-ran");
        let child = directory.path().join("descendant-pid");
        // `: >` instead of `touch` keeps the descendant's fork as the only
        // process creation before the parent exits, well before the deadline.
        let script = format!(
            "#!/bin/sh\nif [ -e '{}' ]; then\n  exit 0\nfi\n: > '{}'\n/bin/sleep 30 &\necho $! > '{}'\nexit 0\n",
            marker.display(),
            marker.display(),
            child.display(),
        );
        let (_fixture_directory, path) = executable(&script);
        let runner = BoundedGitRunner::with_test_executable(path);
        let started = Instant::now();
        assert!(matches!(
            runner.run(GitRequest::discover(std::env::temp_dir())),
            Err(GitRunnerError::TimedOut)
        ));
        assert!(started.elapsed() < Duration::from_secs(3));
        // The pid line is the fixture's last act before `exit 0`; without it the
        // runner timed out a still-running parent and this test's exited-parent
        // precondition was never reached.
        let pid = complete_pid(&child)
            .expect("fixture parent exited (descendant pid recorded) before the runner deadline");
        assert!(process_is_gone_within(pid, REAP_SAFETY_BOUND));
        assert!(runner
            .run(GitRequest::discover(std::env::temp_dir()))
            .is_ok());
    }

    // A descendant that leaves the runner's process group with setsid(), as a
    // daemonizing helper would, while keeping the inherited stdout/stderr
    // pipes; the group SIGKILL cannot reach it. It records its pid only after
    // setsid() succeeded and never writes a byte, so nothing wakes a reader.
    // Every 20 ms it probes both pipes with a zero-length write, which on macOS
    // succeeds while a read end is open and fails with EPIPE (SIGPIPE ignored)
    // once it is closed. When both probes fail it records `closed` and exits;
    // otherwise it gives up after about 30 s.
    fn escaping_descendant(pid: &std::path::Path, closed: &std::path::Path) -> String {
        format!(
            "/usr/bin/perl -e 'use POSIX (); defined(POSIX::setsid()) or exit 1; \
             $SIG{{PIPE}} = \"IGNORE\"; \
             open(my $p, \">\", $ARGV[0]) or exit 1; print $p \"$$\\n\"; close($p) or exit 1; \
             my ($o, $e) = (1, 1); \
             for (1 .. 1500) {{ select(undef, undef, undef, 0.02); \
             $o &&= defined(syswrite(STDOUT, \"\")); $e &&= defined(syswrite(STDERR, \"\")); \
             next if $o || $e; \
             open(my $c, \">\", $ARGV[1]) or exit 1; print $c \"closed\\n\"; close($c); exit 0 }} \
             exit 2' '{}' '{}' &\n",
            pid.display(),
            closed.display(),
        )
    }

    // Kills the escaped descendant if its test ends, or panics, while it is
    // still alive. It only signals a pid that still leads its own process
    // group, as the escaped descendant does.
    struct EscapedDescendantGuard(PathBuf);

    impl Drop for EscapedDescendantGuard {
        fn drop(&mut self) {
            if let Some(pid) = complete_pid(&self.0) {
                unsafe {
                    if libc::getpgid(pid) == pid {
                        libc::kill(pid, libc::SIGKILL);
                    }
                }
            }
        }
    }

    // The descendant can only write `closed` if it survived the group SIGKILL
    // (it escaped) and then saw EPIPE on both pipes (the runner released its
    // read ends instead of leaving reader threads blocked on them).
    fn assert_escaped_descendant_saw_both_pipes_closed(
        pid: &std::path::Path,
        closed: &std::path::Path,
    ) {
        let pid = complete_pid(pid)
            .expect("descendant left the runner's process group before the deadline");
        assert!(
            process_is_gone_within(pid, REAP_SAFETY_BOUND),
            "escaped descendant still holds an open runner pipe"
        );
        assert_eq!(
            fs::read_to_string(closed).ok().as_deref(),
            Some("closed\n"),
            "escaped descendant must exit only after the runner closed both read ends"
        );
    }

    #[test]
    fn descendant_escaping_the_process_group_cannot_hold_a_live_child_past_the_deadline() {
        let _fixture_guard = process_fixture_guard();
        let directory = tempfile::tempdir().unwrap();
        let descendant = directory.path().join("escaped-pid");
        let closed = directory.path().join("pipes-closed");
        let _escaped = EscapedDescendantGuard(descendant.clone());
        let script = format!(
            "#!/bin/sh\n{}exec /bin/sleep 30\n",
            escaping_descendant(&descendant, &closed)
        );
        let (_fixture_directory, path) = executable(&script);
        let runner = BoundedGitRunner::with_test_executable(path);
        let started = Instant::now();
        let result = runner.run(GitRequest::discover(std::env::temp_dir()));
        let elapsed = started.elapsed();
        assert!(
            matches!(result, Err(GitRunnerError::TimedOut)),
            "{result:?}"
        );
        assert!(
            elapsed < Duration::from_secs(3),
            "run returned after {elapsed:?}"
        );
        assert_escaped_descendant_saw_both_pipes_closed(&descendant, &closed);
    }

    #[test]
    fn descendant_escaping_the_process_group_cannot_hold_an_exited_child_past_the_deadline() {
        let _fixture_guard = process_fixture_guard();
        let directory = tempfile::tempdir().unwrap();
        let marker = directory.path().join("already-ran");
        let descendant = directory.path().join("escaped-pid");
        let closed = directory.path().join("pipes-closed");
        let _escaped = EscapedDescendantGuard(descendant.clone());
        let script = format!(
            "#!/bin/sh\nif [ -e '{}' ]; then\n  exit 0\nfi\n: > '{}'\n{}exit 0\n",
            marker.display(),
            marker.display(),
            escaping_descendant(&descendant, &closed),
        );
        let (_fixture_directory, path) = executable(&script);
        let runner = BoundedGitRunner::with_test_executable(path);
        let started = Instant::now();
        let result = runner.run(GitRequest::discover(std::env::temp_dir()));
        let elapsed = started.elapsed();
        assert!(
            matches!(result, Err(GitRunnerError::TimedOut)),
            "{result:?}"
        );
        assert!(
            elapsed < Duration::from_secs(3),
            "run returned after {elapsed:?}"
        );
        assert_escaped_descendant_saw_both_pipes_closed(&descendant, &closed);
        assert!(runner
            .run(GitRequest::discover(std::env::temp_dir()))
            .is_ok());
    }

    #[test]
    fn lifecycle_mutex_serializes_two_runs() {
        let _fixture_guard = process_fixture_guard();
        let count = tempfile::NamedTempFile::new().unwrap();
        let script = format!(
            "#!/bin/sh\necho x >> '{}'\n/bin/sleep 0.1\n",
            count.path().display()
        );
        let (_directory, path) = executable(&script);
        let runner = std::sync::Arc::new(BoundedGitRunner::with_test_executable(path));
        let left = runner.clone();
        let right = runner.clone();
        let a = thread::spawn(move || left.run(GitRequest::discover(std::env::temp_dir())).is_ok());
        let b = thread::spawn(move || {
            right
                .run(GitRequest::discover(std::env::temp_dir()))
                .is_ok()
        });
        assert!(a.join().unwrap() && b.join().unwrap());
        assert_eq!(fs::read_to_string(count.path()).unwrap().lines().count(), 2);
    }
}
