//! Runs `/usage` under fixed limits and returns its stdout bytes or a typed
//! failure. It knows nothing about the report format.

use std::{
    ffi::OsString,
    fs::{self, DirBuilder},
    io::ErrorKind,
    os::unix::fs::DirBuilderExt,
    path::{Path, PathBuf},
    process::{ExitStatus, Stdio},
    sync::{Arc, LazyLock, Mutex},
    time::Duration,
};

use tokio::{
    io::AsyncReadExt,
    process::{Child, ChildStdout, Command},
    sync::Notify,
    time::{sleep, sleep_until, timeout, Instant},
};

pub const USAGE_PROBE_ARGUMENTS: [&str; 9] = [
    "-p",
    "/usage",
    "--no-session-persistence",
    "--strict-mcp-config",
    "--settings",
    r#"{"disableAllHooks":true}"#,
    "--output-format",
    "stream-json",
    "--verbose",
];

/// The one folder every run works in, under `TMPDIR`. The CLI keeps records per
/// working directory, so a new folder per run could grow without limit.
const WORKING_DIRECTORY_NAME: &str = "needlbar-claude-usage";
const USAGE_PROBE_PATH: &str = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
const TERMINATION_GRACE: Duration = Duration::from_millis(500);
/// A descendant can keep the stdout pipe open after `claude` itself exits.
const PIPE_DRAIN_GRACE: Duration = Duration::from_millis(250);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct UsageProbeLimits {
    pub deadline: Duration,
    pub max_stdout_bytes: usize,
}

impl Default for UsageProbeLimits {
    /// The deadline is 60 seconds (30 before 2026-11-12). `/usage` scans the
    /// recent session transcripts, so a run takes longer as they grow, and a run
    /// stopped at the deadline has paid its whole cost and returns nothing.
    fn default() -> Self {
        Self {
            deadline: Duration::from_secs(60),
            max_stdout_bytes: 1024 * 1024,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UsageProbeFailure {
    LaunchFailed,
    ExitedUnsuccessfully,
    TimedOut,
    OutputTooLarge,
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UsageProbeEnvironment {
    values: Vec<(&'static str, OsString)>,
}

impl UsageProbeEnvironment {
    pub fn from_lookup(lookup: impl Fn(&str) -> Option<OsString>) -> Self {
        let mut values = Vec::new();
        for name in ["HOME", "USER", "LOGNAME", "TMPDIR"] {
            if let Some(value) = lookup(name) {
                values.push((name, value));
            }
        }
        values.push(("PATH", OsString::from(USAGE_PROBE_PATH)));
        if let Some(value) = lookup("CLAUDE_CONFIG_DIR").filter(|value| !value.is_empty()) {
            values.push(("CLAUDE_CONFIG_DIR", value));
        }
        Self { values }
    }

    pub fn from_process() -> Self {
        Self::from_lookup(|name| std::env::var_os(name))
    }

    /// `<TMPDIR>/needlbar-claude-usage`. `TMPDIR` comes from this environment,
    /// which the app copies from its own, and falls back to the system temporary
    /// directory (which itself reads `TMPDIR`, then uses `/tmp`).
    pub fn working_directory(&self) -> PathBuf {
        let base = self
            .values
            .iter()
            .find(|(name, value)| *name == "TMPDIR" && !value.is_empty())
            .map_or_else(std::env::temp_dir, |(_, value)| PathBuf::from(value));
        base.join(WORKING_DIRECTORY_NAME)
    }

    pub fn pairs(&self) -> &[(&'static str, OsString)] {
        &self.values
    }
}

#[derive(Default)]
struct ControlState {
    cancelled_through: u64,
    active: Option<(u64, i32)>,
}

/// Cancels runs by ID. A cancel that arrives before a run registers still
/// applies, because the run checks the same state, and later runs have larger
/// IDs and are unaffected. `cancel_through` signals synchronously, so a run does
/// not outlive an app that exits right after asking.
#[derive(Default)]
pub struct UsageProbeControl {
    state: Mutex<ControlState>,
    changed: Notify,
}

static SHARED_CONTROL: LazyLock<Arc<UsageProbeControl>> =
    LazyLock::new(|| Arc::new(UsageProbeControl::new()));

impl UsageProbeControl {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn shared() -> Arc<Self> {
        Arc::clone(&SHARED_CONTROL)
    }

    pub fn cancel_through(&self, run_id: u64) {
        {
            let mut state = self.lock();
            state.cancelled_through = state.cancelled_through.max(run_id);
            if let Some((active_run, process_group)) = state.active {
                if active_run <= run_id {
                    signal_group(process_group, libc::SIGTERM);
                }
            }
        }
        self.changed.notify_waiters();
    }

    pub fn is_cancelled(&self, run_id: u64) -> bool {
        self.lock().cancelled_through >= run_id
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, ControlState> {
        self.state
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn register(&self, run_id: u64, process_group: i32) -> bool {
        let mut state = self.lock();
        if state.cancelled_through >= run_id {
            return false;
        }
        state.active = Some((run_id, process_group));
        true
    }

    fn unregister(&self, run_id: u64) {
        let mut state = self.lock();
        if matches!(state.active, Some((active_run, _)) if active_run == run_id) {
            state.active = None;
        }
    }

    async fn cancelled(&self, run_id: u64) {
        loop {
            // A `Notified` receives `notify_waiters` from the moment it exists.
            let notified = self.changed.notified();
            if self.is_cancelled(run_id) {
                return;
            }
            notified.await;
        }
    }
}

fn signal_group(process_group: i32, signal: i32) {
    // SAFETY: `kill` takes no pointers; a negative ID addresses the group this
    // module created with `process_group(0)`.
    unsafe {
        libc::kill(-process_group, signal);
    }
}

enum Stop {
    Exited(ExitStatus),
    WaitFailed,
    TimedOut,
    OutputTooLarge,
    Cancelled,
}

pub async fn run_usage_probe(
    executable: &Path,
    environment: &UsageProbeEnvironment,
    limits: UsageProbeLimits,
    control: &UsageProbeControl,
    run_id: u64,
) -> Result<Vec<u8>, UsageProbeFailure> {
    if control.is_cancelled(run_id) {
        return Err(UsageProbeFailure::Cancelled);
    }
    let working_directory = prepare_working_directory(&environment.working_directory())?;
    let deadline = Instant::now() + limits.deadline;
    let mut command = Command::new(executable);
    command
        .args(USAGE_PROBE_ARGUMENTS)
        .current_dir(&working_directory)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .env_clear()
        .envs(
            environment
                .pairs()
                .iter()
                .map(|(name, value)| (*name, value)),
        )
        .process_group(0)
        .kill_on_drop(true);
    let mut child = command
        .spawn()
        .map_err(|_| UsageProbeFailure::LaunchFailed)?;
    let process_group = child
        .id()
        .and_then(|id| i32::try_from(id).ok())
        .ok_or(UsageProbeFailure::LaunchFailed)?;
    let stdout = child.stdout.take().ok_or(UsageProbeFailure::LaunchFailed)?;
    let mut stderr = child.stderr.take().ok_or(UsageProbeFailure::LaunchFailed)?;
    if !control.register(run_id, process_group) {
        terminate_group(&mut child, process_group).await;
        return Err(UsageProbeFailure::Cancelled);
    }
    let stderr_drain = tokio::spawn(async move {
        let _ = tokio::io::copy(&mut stderr, &mut tokio::io::sink()).await;
    });

    let mut output = Vec::new();
    let stop = tokio::select! {
        biased;
        () = control.cancelled(run_id) => Stop::Cancelled,
        () = sleep_until(deadline) => Stop::TimedOut,
        stop = read_until_exit(&mut child, stdout, limits.max_stdout_bytes, &mut output) => stop,
    };
    if matches!(stop, Stop::Exited(_)) {
        // `claude` is reaped, but a descendant can outlive it. This job repeats
        // every few minutes, so nothing may stay behind. ESRCH (an empty group)
        // is the normal outcome and does not affect the result.
        signal_group(process_group, libc::SIGKILL);
    } else {
        terminate_group(&mut child, process_group).await;
    }
    control.unregister(run_id);
    stderr_drain.abort();
    let _ = stderr_drain.await;

    match stop {
        Stop::Exited(status) if status.success() => Ok(output),
        Stop::Exited(_) | Stop::WaitFailed => Err(UsageProbeFailure::ExitedUnsuccessfully),
        Stop::TimedOut => Err(UsageProbeFailure::TimedOut),
        Stop::OutputTooLarge => Err(UsageProbeFailure::OutputTooLarge),
        Stop::Cancelled => Err(UsageProbeFailure::Cancelled),
    }
}

/// Creates the folder with mode 0700 if it is absent, refuses anything that is
/// not a real directory (a symlink or a file), and empties it. Only one run
/// happens at a time, so nothing else is using it.
fn prepare_working_directory(path: &Path) -> Result<PathBuf, UsageProbeFailure> {
    match DirBuilder::new().mode(0o700).create(path) {
        Ok(()) => {}
        Err(error) if error.kind() == ErrorKind::AlreadyExists => {}
        Err(_) => return Err(UsageProbeFailure::LaunchFailed),
    }
    // `symlink_metadata` does not follow a link, so a link is not a directory.
    let metadata = fs::symlink_metadata(path).map_err(|_| UsageProbeFailure::LaunchFailed)?;
    if !metadata.file_type().is_dir() {
        return Err(UsageProbeFailure::LaunchFailed);
    }
    let entries = fs::read_dir(path).map_err(|_| UsageProbeFailure::LaunchFailed)?;
    for entry in entries {
        let entry = entry.map_err(|_| UsageProbeFailure::LaunchFailed)?;
        let file_type = entry
            .file_type()
            .map_err(|_| UsageProbeFailure::LaunchFailed)?;
        // A link is removed, never followed.
        let removed = if file_type.is_dir() {
            fs::remove_dir_all(entry.path())
        } else {
            fs::remove_file(entry.path())
        };
        removed.map_err(|_| UsageProbeFailure::LaunchFailed)?;
    }
    Ok(path.to_path_buf())
}

async fn read_until_exit(
    child: &mut Child,
    mut stdout: ChildStdout,
    limit: usize,
    output: &mut Vec<u8>,
) -> Stop {
    let mut buffer = [0_u8; 8192];
    let mut stdout_open = true;
    let mut status = None;
    loop {
        tokio::select! {
            read = stdout.read(&mut buffer), if stdout_open => match read {
                Ok(0) | Err(_) => stdout_open = false,
                Ok(count) => {
                    if output.len().saturating_add(count) > limit {
                        return Stop::OutputTooLarge;
                    }
                    output.extend_from_slice(&buffer[..count]);
                }
            },
            exited = child.wait(), if status.is_none() => match exited {
                Ok(exit_status) => status = Some(exit_status),
                Err(_) => return Stop::WaitFailed,
            },
            () = sleep(PIPE_DRAIN_GRACE), if status.is_some() && stdout_open => stdout_open = false,
        }
        if let (Some(exit_status), false) = (status, stdout_open) {
            return Stop::Exited(exit_status);
        }
    }
}

async fn terminate_group(child: &mut Child, process_group: i32) {
    signal_group(process_group, libc::SIGTERM);
    let _ = timeout(TERMINATION_GRACE, child.wait()).await;
    // Also reaches a descendant that ignored SIGTERM after its parent exited.
    signal_group(process_group, libc::SIGKILL);
    let _ = timeout(TERMINATION_GRACE, child.wait()).await;
}
