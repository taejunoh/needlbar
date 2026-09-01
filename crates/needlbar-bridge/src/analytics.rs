use chrono::{DateTime, Duration, Utc};
use needlbar_project_analytics::{build_analytics_payload, AnalyticsPayload, BoundedGitRunner};
use tokscale_core::ReportOptions;

const ANALYTICS_CLIENTS: [&str; 3] = ["claude", "codex", "cursor"];

fn analytics_time_window(generated_at: DateTime<Utc>) -> (DateTime<Utc>, DateTime<Utc>) {
    (generated_at - Duration::days(30), generated_at)
}

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
    let (start, end) = analytics_time_window(generated_at);
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
        .block_on(
            tokscale_core::get_workspace_session_report_cached_pricing_instant_range(
                options, start, end,
            ),
        )
        .map_err(|_| "usageReportUnavailable")?;
    let payload = build_analytics_payload(report, generated_at, &BoundedGitRunner::default());
    Ok((generated_at, payload))
}

#[cfg(test)]
mod tests {
    use chrono::{TimeZone, Timelike, Utc};

    use super::analytics_time_window;

    #[test]
    fn analytics_time_window_uses_one_captured_instant_for_both_exact_boundaries() {
        let generated_at = Utc
            .with_ymd_and_hms(2026, 9, 1, 12, 0, 0)
            .unwrap()
            .with_nanosecond(123_000_000)
            .unwrap();

        let (start, end) = analytics_time_window(generated_at);

        assert_eq!(start.to_rfc3339(), "2026-08-02T12:00:00.123+00:00");
        assert_eq!(end, generated_at);
    }
}
