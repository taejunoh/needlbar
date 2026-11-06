use std::{
    ffi::OsString,
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::Arc,
    time::Duration,
};

use needlbar_quota::{
    ClaudeCliLocator, ClaudeQuotaFailureOrigin, ClaudeUsageReportProvider, ClaudeUsageReportRun,
    ClaudeUsageRowKind, ProviderId, QuotaErrorCode, UsageProbeControl, UsageProbeEnvironment,
    UsageProbeLimits,
};
use tempfile::TempDir;

const ALL_ROWS: &str = include_str!("../../../Fixtures/quota/claude/usage-report-all-rows.jsonl");
const WEEKLY_ONLY: &str =
    include_str!("../../../Fixtures/quota/claude/usage-report-weekly-only.jsonl");
const PREWARM: &str = "--needlbar-prewarm";

fn fake(directory: &Path, body: &str) -> PathBuf {
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

fn provider(candidates: Vec<PathBuf>, limits: UsageProbeLimits) -> ClaudeUsageReportProvider {
    ClaudeUsageReportProvider::with_parts(
        ClaudeCliLocator::with_candidates(candidates),
        UsageProbeEnvironment::from_lookup(|_| None::<OsString>),
        limits,
        Arc::new(UsageProbeControl::new()),
        1,
    )
}

async fn run_script(body: &str) -> ClaudeUsageReportRun {
    let temp = TempDir::new().unwrap();
    let script = fake(temp.path(), body);
    provider(vec![script], UsageProbeLimits::default())
        .run()
        .await
}

async fn run_output(output: &str) -> ClaudeUsageReportRun {
    let temp = TempDir::new().unwrap();
    let source = temp.path().join("output.jsonl");
    fs::write(&source, output).unwrap();
    let script = fake(temp.path(), &format!("/bin/cat '{}'", source.display()));
    provider(vec![script], UsageProbeLimits::default())
        .run()
        .await
}

fn assert_failure(
    run: &ClaudeUsageReportRun,
    code: QuotaErrorCode,
    origin: ClaudeQuotaFailureOrigin,
) {
    let error = run.result.as_ref().expect_err("expected a failure");
    assert_eq!(error.code, code);
    assert_eq!(error.provider, Some(ProviderId::Claude));
    assert_eq!(error.claude_failure_origin(), Some(origin));
}

#[tokio::test]
async fn a_full_report_becomes_a_claude_snapshot_with_a_summary() {
    let run = run_output(ALL_ROWS).await;
    let snapshot = run.result.expect("snapshot");
    assert_eq!(snapshot.provider, ProviderId::Claude);
    assert_eq!(snapshot.windows.len(), 3);
    let summary = run.summary.expect("summary");
    assert_eq!(
        summary.row_kinds,
        [
            ClaudeUsageRowKind::Session,
            ClaudeUsageRowKind::WeeklyAll,
            ClaudeUsageRowKind::WeeklyScoped
        ]
    );
    assert_eq!(summary.unknown_row_count, 0);
}

#[tokio::test]
async fn weekly_only_report_has_no_session_window() {
    let snapshot = run_output(WEEKLY_ONLY).await.result.expect("snapshot");
    assert!(snapshot
        .windows
        .iter()
        .all(|window| window.id() != "claude.session"));
    assert_eq!(snapshot.windows.len(), 2);
}

#[tokio::test]
async fn a_missing_cli_is_not_installed() {
    let temp = TempDir::new().unwrap();
    let run = provider(
        vec![temp.path().join("absent")],
        UsageProbeLimits::default(),
    )
    .run()
    .await;
    assert_failure(
        &run,
        QuotaErrorCode::NotInstalled,
        ClaudeQuotaFailureOrigin::ClaudeCliNotFound,
    );
    assert!(run.summary.is_some());
}

#[tokio::test]
async fn no_usage_is_a_check_failure_not_a_sign_in_request() {
    // The CLI also reports null or empty limits while its own usage fetch is
    // failing (offline, 429, 5xx), so these shapes must not ask a signed-in user
    // to sign in.
    for output in [
        r#"{"type":"assistant","usage_report":{"rate_limits":null}}"#,
        r#"{"type":"assistant","usage_report":{"rate_limits":{"limits":null}}}"#,
        r#"{"type":"assistant","usage_report":{"rate_limits":{"limits":[]}}}"#,
    ] {
        let run = run_output(output).await;
        assert_failure(
            &run,
            QuotaErrorCode::ProviderUnavailable,
            ClaudeQuotaFailureOrigin::UsageReportNoUsage,
        );
    }
}

#[tokio::test]
async fn no_report_is_format_changed() {
    let run = run_output(r#"{"type":"result","subtype":"success","result":"text"}"#).await;
    assert_failure(
        &run,
        QuotaErrorCode::SchemaChanged,
        ClaudeQuotaFailureOrigin::UsageReportFormatChanged,
    );
}

#[tokio::test]
async fn a_rate_limit_error_without_a_report_is_rate_limited() {
    let run = run_output(r#"{"type":"assistant","error":"rate_limit"}"#).await;
    assert_failure(
        &run,
        QuotaErrorCode::RateLimited,
        ClaudeQuotaFailureOrigin::UsageReportRateLimited,
    );
}

#[tokio::test]
async fn non_zero_exit_is_a_process_failure_even_with_a_report_in_its_output() {
    let run = run_script(
        "printf '%s\\n' '{\"type\":\"assistant\",\"usage_report\":{\"rate_limits\":null}}'\nexit 1",
    )
    .await;
    assert_failure(
        &run,
        QuotaErrorCode::ProviderUnavailable,
        ClaudeQuotaFailureOrigin::UsageProbeFailed,
    );
}

#[tokio::test]
async fn timeout_and_oversized_output_are_typed_process_failures() {
    let temp = TempDir::new().unwrap();
    let slow = fake(temp.path(), "/bin/sleep 30");
    let run = provider(
        vec![slow],
        UsageProbeLimits {
            deadline: Duration::from_secs(1),
            ..UsageProbeLimits::default()
        },
    )
    .run()
    .await;
    assert_failure(
        &run,
        QuotaErrorCode::ProviderUnavailable,
        ClaudeQuotaFailureOrigin::UsageProbeTimedOut,
    );

    let large_directory = TempDir::new().unwrap();
    let large = fake(large_directory.path(), "/usr/bin/yes report");
    let run = provider(
        vec![large],
        UsageProbeLimits {
            deadline: Duration::from_secs(20),
            max_stdout_bytes: 64 * 1024,
        },
    )
    .run()
    .await;
    assert_failure(
        &run,
        QuotaErrorCode::ProviderUnavailable,
        ClaudeQuotaFailureOrigin::UsageProbeOutputTooLarge,
    );
}

#[tokio::test]
async fn a_cancelled_run_is_marked_and_describes_no_attempt() {
    let temp = TempDir::new().unwrap();
    let script = fake(temp.path(), "printf 'never'");
    let control = Arc::new(UsageProbeControl::new());
    control.cancel_through(7);
    let run = ClaudeUsageReportProvider::with_parts(
        ClaudeCliLocator::with_candidates(vec![script]),
        UsageProbeEnvironment::from_lookup(|_| None::<OsString>),
        UsageProbeLimits::default(),
        control,
        7,
    )
    .run()
    .await;
    let error = run.result.expect_err("cancelled");
    assert!(error.is_claude_usage_report_cancelled());
    assert_eq!(error.claude_failure_origin(), None);
    assert!(run.summary.is_none());
}

#[tokio::test]
async fn no_output_text_or_canary_reaches_any_surface() {
    let run = run_output(ALL_ROWS).await;
    let surfaces = format!(
        "{:?}{}{}",
        run.result,
        serde_json::to_string(run.result.as_ref().unwrap()).unwrap(),
        serde_json::to_string(run.summary.as_ref().unwrap()).unwrap()
    );
    for canary in [
        "SESSION-CANARY",
        "PATH-CANARY",
        "TEXT-CANARY",
        "RESULT-CANARY",
        "alice@example.com",
    ] {
        assert!(!surfaces.contains(canary), "{canary}");
    }
    let failed = run_output("{\"type\":\"result\",\"result\":\"TEXT-CANARY\"}").await;
    let error = failed.result.expect_err("format changed");
    assert!(!format!("{error:?}").contains("TEXT-CANARY"));
    assert!(!serde_json::to_string(&error)
        .unwrap()
        .contains("TEXT-CANARY"));
}
