use std::io::Read;
use std::path::PathBuf;
use std::process::{Command, Stdio as ProcessStdio};
use std::sync::Mutex;
use std::thread;
use std::time::{Duration, Instant};
use thiserror::Error;

pub const MAX_STDOUT_BYTES: usize = 1024 * 1024;
pub const MAX_STDERR_BYTES: usize = 8 * 1024;
pub const PROCESS_TIMEOUT: Duration = Duration::from_secs(2);
pub const TOTAL_GIT_BUDGET: Duration = Duration::from_secs(10);

#[derive(Debug, Clone)]
pub enum GitRequest {
    DiscoverRepository { workspace: PathBuf },
    ReadCommits { repository: PathBuf },
}
#[derive(Debug, Clone)]
pub struct GitOutput {
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
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
}

#[derive(Default)]
pub struct BoundedGitRunner {
    budget_started: Mutex<Option<Instant>>,
}
impl BoundedGitRunner {
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
        let remaining = self.remaining_budget()?;
        let discovery = matches!(&request, GitRequest::DiscoverRepository { .. });
        let (directory, arguments): (PathBuf, Vec<String>) = match request {
            GitRequest::DiscoverRepository { workspace } => (
                workspace,
                vec![
                    "rev-parse".into(),
                    "--path-format=absolute".into(),
                    "--show-toplevel".into(),
                ],
            ),
            GitRequest::ReadCommits { repository } => (
                repository,
                vec![
                    "log".into(),
                    "--no-ext-diff".into(),
                    "--no-color".into(),
                    "--no-decorate".into(),
                    "--no-show-signature".into(),
                    "--format=%H%x00%cI%x00%B".into(),
                    "-z".into(),
                    "--max-count=500".into(),
                ],
            ),
        };
        let canonical =
            std::fs::canonicalize(directory).map_err(|_| GitRunnerError::Unavailable)?;
        let mut command = Command::new("/usr/bin/git");
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
        let out = child.stdout.take().ok_or(GitRunnerError::Unavailable)?;
        let err = child.stderr.take().ok_or(GitRunnerError::Unavailable)?;
        let stdout = spawn_reader(out, MAX_STDOUT_BYTES);
        let stderr = spawn_reader(err, MAX_STDERR_BYTES);
        let deadline = Instant::now() + PROCESS_TIMEOUT.min(remaining);
        let status = loop {
            if let Some(status) = child.try_wait().map_err(|_| GitRunnerError::Unavailable)? {
                break status;
            }
            if Instant::now() >= deadline {
                let _ = child.kill();
                let _ = child.wait();
                let _ = stdout.join();
                let _ = stderr.join();
                return Err(GitRunnerError::TimedOut);
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
}
