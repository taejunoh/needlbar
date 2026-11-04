use std::{
    ffi::OsString,
    fs,
    os::unix::fs::{symlink, PermissionsExt},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::Arc,
    time::{Duration, Instant},
};

use needlbar_quota::{
    run_usage_probe, ClaudeCliLocator, UsageProbeControl, UsageProbeEnvironment, UsageProbeFailure,
    UsageProbeLimits, USAGE_PROBE_ARGUMENTS,
};
use tempfile::TempDir;

const PREWARM: &str = "--needlbar-prewarm";

/// Writes an executable fake `claude`. macOS can hold the first exec of a new
/// file for about 3 s, so it runs once here, outside the timed path.
fn fake_claude(directory: &Path, body: &str) -> PathBuf {
    let path = directory.join("claude");
    fs::write(
        &path,
        format!("#!/bin/sh\nif [ \"${{1:-}}\" = '{PREWARM}' ]; then exit 0; fi\n{body}\n"),
    )
    .unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o700)).unwrap();
    assert!(Command::new(&path)
        .arg(PREWARM)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .unwrap()
        .success());
    path
}

fn environment() -> UsageProbeEnvironment {
    UsageProbeEnvironment::from_lookup(|name| match name {
        "HOME" => Some(OsString::from("/tmp/needlbar-fake-home")),
        "USER" => Some(OsString::from("fake-user")),
        "LOGNAME" => Some(OsString::from("fake-login")),
        "TMPDIR" => Some(OsString::from("/tmp")),
        "ANTHROPIC_API_KEY" | "CLAUDE_CODE_OAUTH_TOKEN" | "OTHER" => Some(OsString::from("LEAK")),
        _ => None,
    })
}

fn limits(deadline_ms: u64) -> UsageProbeLimits {
    UsageProbeLimits {
        deadline: Duration::from_millis(deadline_ms),
        ..UsageProbeLimits::default()
    }
}

async fn assert_pid_gone(pid_file: &Path) {
    let text = fs::read_to_string(pid_file).unwrap();
    let pid = text.trim();
    assert!(
        !pid.is_empty() && pid.bytes().all(|byte| byte.is_ascii_digit()),
        "{text:?}"
    );
    let deadline = Instant::now() + Duration::from_secs(5);
    while Instant::now() < deadline {
        let alive = Command::new("kill")
            .args(["-0", pid])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .unwrap()
            .success();
        if !alive {
            return;
        }
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
    panic!("process {pid} was still running");
}

#[test]
fn locator_takes_the_first_executable_regular_file_in_order() {
    let temp = TempDir::new().unwrap();
    let first = temp.path().join("first");
    let second = temp.path().join("second");
    let third = temp.path().join("third");
    fs::write(&first, "not executable").unwrap();
    fs::set_permissions(&first, fs::Permissions::from_mode(0o600)).unwrap();
    fs::write(&second, "#!/bin/sh\n").unwrap();
    fs::set_permissions(&second, fs::Permissions::from_mode(0o700)).unwrap();
    fs::write(&third, "#!/bin/sh\n").unwrap();
    fs::set_permissions(&third, fs::Permissions::from_mode(0o700)).unwrap();
    let locator = ClaudeCliLocator::with_candidates(vec![
        temp.path().join("missing"),
        first,
        second.clone(),
        third,
    ]);
    assert_eq!(locator.locate(), Some(fs::canonicalize(second).unwrap()));
}

#[test]
fn locator_resolves_symlinks_and_rejects_directories_and_dangling_links() {
    let temp = TempDir::new().unwrap();
    let target = temp.path().join("versions/1.0/claude");
    fs::create_dir_all(target.parent().unwrap()).unwrap();
    fs::write(&target, "#!/bin/sh\n").unwrap();
    fs::set_permissions(&target, fs::Permissions::from_mode(0o700)).unwrap();
    let link = temp.path().join("claude");
    symlink(&target, &link).unwrap();
    let dangling = temp.path().join("dangling");
    symlink(temp.path().join("nowhere"), &dangling).unwrap();
    let directory = temp.path().join("directory");
    fs::create_dir(&directory).unwrap();

    assert_eq!(
        ClaudeCliLocator::with_candidates(vec![dangling.clone(), directory.clone(), link]).locate(),
        Some(fs::canonicalize(&target).unwrap())
    );
    assert_eq!(
        ClaudeCliLocator::with_candidates(vec![dangling, directory]).locate(),
        None
    );
}

#[test]
fn locator_checks_the_fixed_locations_in_the_specified_order() {
    let candidates = ClaudeCliLocator::for_home(Path::new("/Users/fake"))
        .candidates()
        .to_vec();
    assert_eq!(
        candidates,
        [
            PathBuf::from("/Users/fake/.local/bin/claude"),
            PathBuf::from("/opt/homebrew/bin/claude"),
            PathBuf::from("/usr/local/bin/claude"),
        ]
    );
}

#[test]
fn environment_is_an_allowlist_with_a_fixed_path() {
    let names: Vec<_> = environment()
        .pairs()
        .iter()
        .map(|(name, _)| *name)
        .collect();
    assert_eq!(names, ["HOME", "USER", "LOGNAME", "TMPDIR", "PATH"]);
    let with_config = UsageProbeEnvironment::from_lookup(|name| {
        (name == "CLAUDE_CONFIG_DIR").then(|| OsString::from("/tmp/config"))
    });
    assert!(with_config
        .pairs()
        .iter()
        .any(|(name, value)| *name == "CLAUDE_CONFIG_DIR" && value == "/tmp/config"));
    let empty_config = UsageProbeEnvironment::from_lookup(|name| {
        (name == "CLAUDE_CONFIG_DIR").then(OsString::new)
    });
    assert!(empty_config
        .pairs()
        .iter()
        .all(|(name, _)| *name != "CLAUDE_CONFIG_DIR"));
}

#[tokio::test]
async fn runs_with_the_exact_argv_environment_stdin_and_a_fresh_directory_it_deletes() {
    let temp = TempDir::new().unwrap();
    let record = temp.path().join("record");
    fs::create_dir(&record).unwrap();
    let record_text = record.display();
    let script = fake_claude(
        temp.path(),
        &format!(
            r#"for argument in "$@"; do printf '%s\n' "$argument"; done > '{record_text}/argv'
/usr/bin/env > '{record_text}/env'
pwd > '{record_text}/cwd'
/bin/ls -A > '{record_text}/entries'
/bin/cat > '{record_text}/stdin'
printf 'report-bytes'"#
        ),
    );

    let output = run_usage_probe(
        &script,
        &environment(),
        limits(10_000),
        &UsageProbeControl::new(),
        1,
    )
    .await
    .unwrap();

    assert_eq!(output, b"report-bytes");
    let argv = fs::read_to_string(record.join("argv")).unwrap();
    assert_eq!(argv.lines().collect::<Vec<_>>(), USAGE_PROBE_ARGUMENTS);
    assert_eq!(
        USAGE_PROBE_ARGUMENTS,
        [
            "-p",
            "/usage",
            "--no-session-persistence",
            "--strict-mcp-config",
            "--settings",
            r#"{"disableAllHooks":true}"#,
            "--output-format",
            "stream-json",
            "--verbose",
        ]
    );
    let env = fs::read_to_string(record.join("env")).unwrap();
    let names: Vec<_> = env
        .lines()
        .filter_map(|line| line.split('=').next())
        .collect();
    for name in names {
        // /bin/sh and macOS add the last five; the rest must come from the allowlist.
        assert!(
            [
                "HOME",
                "USER",
                "LOGNAME",
                "TMPDIR",
                "PATH",
                "PWD",
                "OLDPWD",
                "SHLVL",
                "_",
                "__CF_USER_TEXT_ENCODING",
            ]
            .contains(&name),
            "unexpected variable {name}"
        );
    }
    assert!(!env.contains("LEAK"));
    assert!(env.contains("PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin\n"));
    assert_eq!(fs::read_to_string(record.join("entries")).unwrap(), "");
    assert_eq!(fs::read_to_string(record.join("stdin")).unwrap(), "");
    let cwd = fs::read_to_string(record.join("cwd")).unwrap();
    assert!(
        !Path::new(cwd.trim()).exists(),
        "working directory was not deleted"
    );
}

#[tokio::test]
async fn non_zero_exit_is_a_process_failure_even_with_valid_output() {
    let temp = TempDir::new().unwrap();
    let script = fake_claude(temp.path(), "printf 'report'\nexit 3");
    let result = run_usage_probe(
        &script,
        &environment(),
        limits(10_000),
        &UsageProbeControl::new(),
        1,
    )
    .await;
    assert_eq!(result, Err(UsageProbeFailure::ExitedUnsuccessfully));
}

#[tokio::test]
async fn a_missing_executable_is_a_launch_failure() {
    let temp = TempDir::new().unwrap();
    let result = run_usage_probe(
        &temp.path().join("absent"),
        &environment(),
        limits(1_000),
        &UsageProbeControl::new(),
        1,
    )
    .await;
    assert_eq!(result, Err(UsageProbeFailure::LaunchFailed));
}

#[tokio::test]
async fn the_deadline_terminates_the_whole_process_group() {
    let temp = TempDir::new().unwrap();
    let parent = temp.path().join("parent.pid");
    let child = temp.path().join("child.pid");
    let script = fake_claude(
        temp.path(),
        &format!(
            "printf '%s\\n' \"$$\" > '{}'\n/bin/sleep 30 &\nprintf '%s\\n' \"$!\" > '{}'\nwait",
            parent.display(),
            child.display()
        ),
    );
    let started = Instant::now();
    let result = run_usage_probe(
        &script,
        &environment(),
        limits(3_000),
        &UsageProbeControl::new(),
        1,
    )
    .await;
    assert_eq!(result, Err(UsageProbeFailure::TimedOut));
    assert!(started.elapsed() < Duration::from_secs(10));
    assert_pid_gone(&parent).await;
    assert_pid_gone(&child).await;
}

#[tokio::test]
async fn oversized_stdout_terminates_the_run() {
    let temp = TempDir::new().unwrap();
    let script = fake_claude(temp.path(), "/usr/bin/yes report");
    let result = run_usage_probe(
        &script,
        &environment(),
        UsageProbeLimits {
            deadline: Duration::from_secs(20),
            max_stdout_bytes: 64 * 1024,
        },
        &UsageProbeControl::new(),
        1,
    )
    .await;
    assert_eq!(result, Err(UsageProbeFailure::OutputTooLarge));
}

#[tokio::test]
async fn stderr_is_drained_without_counting_or_blocking() {
    let temp = TempDir::new().unwrap();
    let script = fake_claude(
        temp.path(),
        "/usr/bin/head -c 2097152 /dev/zero >&2\nprintf 'report'",
    );
    let output = run_usage_probe(
        &script,
        &environment(),
        limits(20_000),
        &UsageProbeControl::new(),
        1,
    )
    .await
    .unwrap();
    assert_eq!(output, b"report");
}

#[tokio::test]
async fn a_descendant_holding_stdout_after_exit_cannot_stall_the_run() {
    let temp = TempDir::new().unwrap();
    let held = temp.path().join("held.pid");
    let script = fake_claude(
        temp.path(),
        &format!(
            "printf 'report'\n/bin/sleep 30 &\nprintf '%s\\n' \"$!\" > '{}'",
            held.display()
        ),
    );
    let started = Instant::now();
    let output = run_usage_probe(
        &script,
        &environment(),
        limits(20_000),
        &UsageProbeControl::new(),
        1,
    )
    .await
    .unwrap();
    assert_eq!(output, b"report");
    assert!(started.elapsed() < Duration::from_secs(10));
    assert_pid_gone(&held).await;
}

#[tokio::test]
async fn a_successful_run_leaves_no_process_in_the_group() {
    let temp = TempDir::new().unwrap();
    let left = temp.path().join("left.pid");
    let script = fake_claude(
        temp.path(),
        &format!(
            "/bin/sleep 30 >/dev/null 2>&1 </dev/null &\nprintf '%s\\n' \"$!\" > '{}'\nprintf 'report'",
            left.display()
        ),
    );
    let output = run_usage_probe(
        &script,
        &environment(),
        limits(20_000),
        &UsageProbeControl::new(),
        1,
    )
    .await
    .unwrap();
    assert_eq!(output, b"report");
    assert_pid_gone(&left).await;
}

#[tokio::test]
async fn a_failed_exit_also_leaves_no_process_in_the_group() {
    let temp = TempDir::new().unwrap();
    let left = temp.path().join("left.pid");
    let script = fake_claude(
        temp.path(),
        &format!(
            "/bin/sleep 30 >/dev/null 2>&1 </dev/null &\nprintf '%s\\n' \"$!\" > '{}'\nexit 3",
            left.display()
        ),
    );
    let result = run_usage_probe(
        &script,
        &environment(),
        limits(20_000),
        &UsageProbeControl::new(),
        1,
    )
    .await;
    assert_eq!(result, Err(UsageProbeFailure::ExitedUnsuccessfully));
    assert_pid_gone(&left).await;
}

#[tokio::test]
async fn cancelling_stops_the_process_and_an_already_cancelled_run_never_spawns() {
    let temp = TempDir::new().unwrap();
    let started_marker = temp.path().join("started");
    let pid_file = temp.path().join("run.pid");
    let script = fake_claude(
        temp.path(),
        &format!(
            "printf '%s\\n' \"$$\" > '{}'\n: > '{}'\n/bin/sleep 30",
            pid_file.display(),
            started_marker.display()
        ),
    );
    let control = Arc::new(UsageProbeControl::new());
    let run = {
        let (script, control) = (script.clone(), Arc::clone(&control));
        tokio::spawn(async move {
            run_usage_probe(&script, &environment(), limits(25_000), &control, 5).await
        })
    };
    let wait_deadline = Instant::now() + Duration::from_secs(10);
    while !started_marker.exists() {
        assert!(
            Instant::now() < wait_deadline,
            "the fake claude never started"
        );
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    control.cancel_through(5);
    assert_eq!(run.await.unwrap(), Err(UsageProbeFailure::Cancelled));
    assert_pid_gone(&pid_file).await;

    fs::remove_file(&started_marker).unwrap();
    let older = run_usage_probe(&script, &environment(), limits(25_000), &control, 4).await;
    assert_eq!(older, Err(UsageProbeFailure::Cancelled));
    assert!(!started_marker.exists(), "a cancelled run must not spawn");
    assert!(!control.is_cancelled(6), "a later run is not cancelled");
}
