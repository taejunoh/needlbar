use chrono::{DateTime, Duration, Utc};
use needlbar_project_analytics::{build_analytics_payload, AnalyticsPayload, BoundedGitRunner};
use tokscale_core::ReportOptions;

const ANALYTICS_CLIENTS: [&str; 3] = ["claude", "codex", "cursor"];

/// The analytics report deliberately uses the engine's cached-pricing API.
/// This keeps the bridge path local-only and reuses the same streaming scan
/// and deduplication implementation as the existing usage report.
pub fn collect_analytics() -> Result<(DateTime<Utc>, AnalyticsPayload), &'static str> {
    #[cfg(feature = "bridge-test-runtime")]
    if let Some(fixture) = crate::test_runtime::analytics_fixture() {
        return match fixture {
            crate::test_runtime::AnalyticsFixture::Success {
                generated_at,
                payload,
            } => Ok((generated_at, *payload)),
            crate::test_runtime::AnalyticsFixture::Fatal { .. } => {
                unreachable!("fatal fixture is handled by the bridge envelope")
            }
            crate::test_runtime::AnalyticsFixture::Panic => panic!("analytics fixture panic"),
        };
    }
    let generated_at = Utc::now();
    let start = generated_at - Duration::days(30);
    #[cfg(feature = "bridge-test-runtime")]
    let fixture_home = crate::test_runtime::analytics_home();
    #[cfg(not(feature = "bridge-test-runtime"))]
    let fixture_home: Option<std::path::PathBuf> = None;
    let options = ReportOptions {
        home_dir: fixture_home
            .as_ref()
            .map(|path| path.to_string_lossy().into_owned()),
        use_env_roots: fixture_home.is_none(),
        clients: Some(ANALYTICS_CLIENTS.iter().map(ToString::to_string).collect()),
        since: Some(start.date_naive().to_string()),
        until: Some(generated_at.date_naive().to_string()),
        ..Default::default()
    };
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|_| "runtimeUnavailable")?;
    let report = runtime
        .block_on(tokscale_core::get_workspace_session_report_cached_pricing(
            options,
        ))
        .map_err(|_| "usageReportUnavailable")?;
    let payload = build_analytics_payload(report, generated_at, &BoundedGitRunner::default());
    Ok((generated_at, payload))
}
