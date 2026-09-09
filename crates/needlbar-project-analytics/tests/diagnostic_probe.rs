#![cfg(feature = "analytics-diagnostic-probe")]

use chrono::{DateTime, Utc};
use needlbar_project_analytics::{
    build_analytics_diagnostic_probe, build_analytics_payload, GitOutput, GitRequest,
    GitRequestKind, GitRunner, GitRunnerError,
};
use std::collections::VecDeque;
use std::sync::Mutex;
use tokscale_core::{
    TokenBreakdown, WorkspaceSessionFragment, WorkspaceSessionModel, WorkspaceSessionReport,
};

struct FakeGitRunner {
    replies: Mutex<VecDeque<Result<GitOutput, GitRunnerError>>>,
    requests: Mutex<Vec<GitRequestKind>>,
}

impl FakeGitRunner {
    fn new(replies: Vec<Result<GitOutput, GitRunnerError>>) -> Self {
        Self {
            replies: Mutex::new(replies.into()),
            requests: Mutex::new(Vec::new()),
        }
    }

    fn requests(&self) -> Vec<GitRequestKind> {
        self.requests.lock().expect("fake requests lock").clone()
    }

    fn is_exhausted(&self) -> bool {
        self.replies.lock().expect("fake replies lock").is_empty()
    }
}

impl GitRunner for FakeGitRunner {
    fn run(&self, request: GitRequest) -> Result<GitOutput, GitRunnerError> {
        self.requests
            .lock()
            .expect("fake requests lock")
            .push(request.kind());
        self.replies
            .lock()
            .expect("fake replies lock")
            .pop_front()
            .expect("one fake reply per existing correlation request")
    }
}

fn output(value: &str) -> Result<GitOutput, GitRunnerError> {
    Ok(GitOutput::new(value.as_bytes().to_vec(), Vec::new()))
}

fn time(value: &str) -> DateTime<Utc> {
    value.parse().expect("fixed timestamp")
}

fn fragment(last_seen_ms: i64) -> WorkspaceSessionFragment {
    WorkspaceSessionFragment {
        client: "codex".into(),
        workspace_key: Some("/private/probe-path-canary".into()),
        session_id: "session-probe-canary".into(),
        first_seen_ms: last_seen_ms,
        last_seen_ms,
        active_time_ms: 0,
        timing_coverage_partial: false,
        tokens: TokenBreakdown::default(),
        message_count: 0,
        estimated_cost_usd: 0.0,
        models: vec![WorkspaceSessionModel {
            model: String::new(),
            provider: "codex".into(),
            tokens: TokenBreakdown::default(),
            message_count: 0,
            estimated_cost_usd: 0.0,
            timed_duration_ms: 0,
            timed_tokens: 0,
            timed_sample_count: 0,
            cost_coverage: tokscale_core::CostCoverage::Complete,
        }],
    }
}

#[test]
fn probe_reports_only_aggregate_missing_timestamp_cleanup_and_engine_caps() {
    let generated_at = time("2026-09-01T16:00:00Z");
    let report = WorkspaceSessionReport {
        fragments: vec![
            fragment(0),
            fragment((generated_at - chrono::Duration::seconds(60)).timestamp_millis()),
        ],
        processing_time_ms: 0,
        record_limit_reached: true,
        timing_coverage_partial: true,
        overflowed_fragment_observations: 3,
        overflowed_timing_observations: 7,
        overflowed_model_observations: 2,
    };

    let probe = build_analytics_diagnostic_probe(
        report,
        generated_at,
        &FakeGitRunner::new(vec![Err(GitRunnerError::CleanupFailed)]),
    );

    assert_eq!(probe.timestamp_unavailable_after_normalization.fragments, 1);
    assert_eq!(probe.discovery.cleanup_failures, 1);
    assert_eq!(probe.caps.overflowed_timing_observations, 7);
    assert_eq!(probe.caps.overflowed_fragment_observations, 3);
    assert_eq!(probe.caps.overflowed_model_observations, 2);
    assert_eq!(probe.caps.record_limit_flag, 1);
    assert_eq!(
        probe.by_provider["codex"].timestamp_unavailable_after_normalization,
        1
    );
}

#[test]
fn probe_uses_the_existing_correlation_call_order_without_exposing_source_canaries() {
    let generated_at = time("2026-09-01T16:00:00Z");
    let good_time = (generated_at - chrono::Duration::seconds(60)).timestamp_millis();
    let mut report = WorkspaceSessionReport {
        fragments: vec![fragment(0), fragment(good_time)],
        processing_time_ms: 0,
        record_limit_reached: false,
        timing_coverage_partial: false,
        overflowed_fragment_observations: 0,
        overflowed_timing_observations: 0,
        overflowed_model_observations: 0,
    };
    report.fragments[1].workspace_key = Some("/private/raw-git-canary".into());
    report.fragments[1].session_id = "session-raw-git-canary".into();
    let commit = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\x002026-09-01T15:00:00Z\x00commit raw-git-canary\x00";
    let normal_git = FakeGitRunner::new(vec![output("/private/raw-git-canary\n"), output(commit)]);
    let normal = build_analytics_payload(report.clone(), generated_at, &normal_git);
    let probe_git = FakeGitRunner::new(vec![output("/private/raw-git-canary\n"), output(commit)]);
    let probe = build_analytics_diagnostic_probe(report, generated_at, &probe_git);

    assert_eq!(normal.repositories.len(), 1);
    assert_eq!(
        normal_git.requests(),
        vec![
            GitRequestKind::DiscoverRepository,
            GitRequestKind::ReadCommits
        ]
    );
    assert_eq!(probe_git.requests(), normal_git.requests());
    assert!(normal_git.is_exhausted());
    assert!(probe_git.is_exhausted());
    assert_eq!(probe.mapping.mapped_fragments, 1);
    assert_eq!(probe.mapping.unmapped_fragments, 1);

    let json = serde_json::to_string(&probe).expect("aggregate probe JSON");
    let debug = format!("{probe:?}");
    for forbidden in [
        "/private/raw-git-canary",
        "session-raw-git-canary",
        "commit raw-git-canary",
        "probe-path-canary",
    ] {
        assert!(!json.contains(forbidden), "JSON leaked {forbidden}");
        assert!(!debug.contains(forbidden), "Debug leaked {forbidden}");
    }
}

#[test]
fn probe_classifies_discovery_stages_and_sanitizes_unknown_provider_keys() {
    let generated_at = time("2026-09-01T16:00:00Z");
    let observed_at = (generated_at - chrono::Duration::seconds(60)).timestamp_millis();
    let mut report = WorkspaceSessionReport {
        fragments: (0..7).map(|_| fragment(observed_at)).collect(),
        processing_time_ms: 0,
        record_limit_reached: false,
        timing_coverage_partial: false,
        overflowed_fragment_observations: 0,
        overflowed_timing_observations: 0,
        overflowed_model_observations: 0,
    };
    report.fragments[0].client = "claude".into();
    report.fragments[1].client = "codex".into();
    report.fragments[2].client = "cursor".into();
    for fragment in &mut report.fragments[3..] {
        fragment.client = "provider-key-canary".into();
    }
    report.fragments[6].workspace_key = Some("bad\0workspace".into());

    let probe = build_analytics_diagnostic_probe(
        report,
        generated_at,
        &FakeGitRunner::new(vec![
            Err(GitRunnerError::NotRepository),
            Err(GitRunnerError::CleanupFailed),
            Err(GitRunnerError::Unavailable),
            Err(GitRunnerError::TimedOut),
            Err(GitRunnerError::OutputLimitReached),
            Err(GitRunnerError::RecordLimitReached),
            Err(GitRunnerError::Unavailable),
        ]),
    );

    assert_eq!(probe.discovery.non_repository, 1);
    assert_eq!(probe.discovery.cleanup_failures, 1);
    assert_eq!(probe.discovery.unavailable_stage_unknown, 2);
    assert_eq!(probe.discovery.timed_out, 1);
    assert_eq!(probe.discovery.output_limited, 1);
    assert_eq!(probe.discovery.record_limited, 1);
    assert_eq!(probe.mapping.unmapped_fragments, 7);
    assert_eq!(probe.canonicalization.path_absent, 6);
    assert_eq!(probe.canonicalization.path_malformed, 1);
    assert_eq!(
        probe.by_provider.keys().cloned().collect::<Vec<_>>(),
        vec!["claude", "codex", "cursor", "other"]
    );
    assert_eq!(probe.by_provider["other"].unmapped_fragments, 4);
    let json = serde_json::to_string(&probe).expect("aggregate probe JSON");
    assert!(!json.contains("provider-key-canary"));
    assert!(!json.contains("bad\\u0000workspace"));
}
