use chrono::{DateTime, Utc};
use needlbar_project_analytics::{
    build_analytics_payload, GitOutput, GitRequest, GitRunner, GitRunnerError,
};
use std::sync::Mutex;
use tokscale_core::{
    TokenBreakdown, WorkspaceSessionFragment, WorkspaceSessionModel, WorkspaceSessionReport,
};
struct Fake(Mutex<u8>);
impl GitRunner for Fake {
    fn run(&self, _: GitRequest) -> Result<GitOutput, GitRunnerError> {
        let mut n = self.0.lock().unwrap();
        *n += 1;
        Ok(if *n == 1 {
            GitOutput::new(
                b"/private/repo\n".to_vec(),
                b"https://forge.invalid".to_vec(),
            )
        } else {
            GitOutput::new(b"abcdefabcdefabcdefabcdefabcdefabcdefabcd\x002026-09-01T11:00:00Z\0commit secret PR #7 Ada <ada@example.invalid> secret-branch\0".to_vec(), vec![])
        })
    }
}
fn time(s: &str) -> DateTime<Utc> {
    s.parse().unwrap()
}
#[test]
fn output_never_contains_private_source_canaries() {
    let f = WorkspaceSessionFragment {
        client: "codex".into(),
        workspace_key: Some("/private/repo".into()),
        session_id: "session-canary".into(),
        first_seen_ms: time("2026-09-01T10:00:00Z").timestamp_millis(),
        last_seen_ms: time("2026-09-01T10:00:00Z").timestamp_millis(),
        active_time_ms: 0,
        timing_coverage_partial: false,
        tokens: TokenBreakdown {
            input: 1,
            ..Default::default()
        },
        message_count: 1,
        estimated_cost_usd: 0.1,
        models: vec![WorkspaceSessionModel {
            model: "gpt-5".into(),
            provider: "codex".into(),
            tokens: TokenBreakdown {
                input: 1,
                ..Default::default()
            },
            message_count: 1,
            estimated_cost_usd: 0.1,
            timed_duration_ms: 0,
            timed_tokens: 0,
            timed_sample_count: 0,
            cost_coverage: tokscale_core::CostCoverage::Complete,
        }],
    };
    let report = WorkspaceSessionReport {
        fragments: vec![f],
        processing_time_ms: 0,
        record_limit_reached: false,
        timing_coverage_partial: false,
        overflowed_fragment_observations: 0,
        overflowed_timing_observations: 0,
        overflowed_model_observations: 0,
    };
    let json = serde_json::to_string(&build_analytics_payload(
        report,
        time("2026-09-01T16:00:00Z"),
        &Fake(Mutex::new(0)),
    ))
    .unwrap();
    for forbidden in [
        "/private/repo",
        "https://forge.invalid",
        "secret-branch",
        "Ada <ada@example.invalid>",
        "commit secret",
        "session-canary",
        "prompt-canary",
        "source-canary",
        "credential-canary",
        "account-canary",
        "stderr-canary",
        "abcdefabcdefabcdefabcdefabcdefabcdefabcd",
    ] {
        assert!(!json.contains(forbidden), "{forbidden}");
    }
    assert!(json.contains("\"pullRequestNumber\":7"));
    let error = GitRunnerError::Unavailable;
    let debug = format!("{error:?}");
    let display = error.to_string();
    for forbidden in ["/private/repo", "stderr-canary", "credential-canary"] {
        assert!(!debug.contains(forbidden));
        assert!(!display.contains(forbidden));
    }
}

#[test]
fn analytics_json_uses_the_exact_canonical_usd_and_1k_field_names() {
    let fragment = WorkspaceSessionFragment {
        client: "codex".into(),
        workspace_key: Some("/private/repo".into()),
        session_id: "session".into(),
        first_seen_ms: time("2026-09-01T10:00:00Z").timestamp_millis(),
        last_seen_ms: time("2026-09-01T10:00:00Z").timestamp_millis(),
        active_time_ms: 3_600_000,
        timing_coverage_partial: false,
        tokens: TokenBreakdown {
            input: 1_000,
            ..Default::default()
        },
        message_count: 1,
        estimated_cost_usd: 0.1,
        models: vec![WorkspaceSessionModel {
            model: "gpt-5".into(),
            provider: "codex".into(),
            tokens: TokenBreakdown {
                input: 1_000,
                ..Default::default()
            },
            message_count: 1,
            estimated_cost_usd: 0.1,
            timed_duration_ms: 1_000,
            timed_tokens: 1_000,
            timed_sample_count: 1,
            cost_coverage: tokscale_core::CostCoverage::Complete,
        }],
    };
    let report = WorkspaceSessionReport {
        fragments: vec![fragment],
        processing_time_ms: 0,
        record_limit_reached: false,
        timing_coverage_partial: false,
        overflowed_fragment_observations: 0,
        overflowed_timing_observations: 0,
        overflowed_model_observations: 0,
    };
    let payload =
        build_analytics_payload(report, time("2026-09-01T16:00:00Z"), &Fake(Mutex::new(0)));
    let wire = serde_json::to_value(payload).expect("analytics payload JSON");
    let usage = &wire["repositories"][0]["usage"];
    let model = &wire["repositories"][0]["providerModels"][0];

    assert!(usage.get("estimatedCostUSD").is_some());
    assert!(usage.get("estimatedCostUsd").is_none());
    assert!(model.get("costPer1KTokens").is_some());
    assert!(model.get("costPer1kTokens").is_none());
    assert!(model.get("millisecondsPer1KTokens").is_some());
    assert!(model.get("millisecondsPer1kTokens").is_none());
}
