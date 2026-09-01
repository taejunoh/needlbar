use chrono::{DateTime, Utc};
use needlbar_project_analytics::{
    build_analytics_payload, GitOutput, GitRequest, GitRunner, GitRunnerError,
};
use std::collections::VecDeque;
use std::sync::Mutex;
use tokscale_core::{
    TokenBreakdown, WorkspaceSessionFragment, WorkspaceSessionModel, WorkspaceSessionReport,
};

struct FakeGitRunner {
    replies: Mutex<VecDeque<Result<GitOutput, GitRunnerError>>>,
}
impl FakeGitRunner {
    fn new(replies: Vec<Result<GitOutput, GitRunnerError>>) -> Self {
        Self {
            replies: Mutex::new(replies.into()),
        }
    }
}
impl GitRunner for FakeGitRunner {
    fn run(&self, _: GitRequest) -> Result<GitOutput, GitRunnerError> {
        self.replies.lock().unwrap().pop_front().unwrap()
    }
}
fn time(value: &str) -> DateTime<Utc> {
    value.parse().unwrap()
}
fn fragment(path: &str, end: &str) -> WorkspaceSessionFragment {
    WorkspaceSessionFragment {
        client: "codex".into(),
        workspace_key: Some(path.into()),
        session_id: "session-canary".into(),
        first_seen_ms: time(end).timestamp_millis(),
        last_seen_ms: time(end).timestamp_millis(),
        active_time_ms: 3_000,
        timing_coverage_partial: false,
        tokens: TokenBreakdown {
            input: 10,
            ..Default::default()
        },
        message_count: 1,
        estimated_cost_usd: 1.25,
        models: vec![WorkspaceSessionModel {
            model: "gpt-5".into(),
            provider: "codex".into(),
            tokens: TokenBreakdown {
                input: 10,
                ..Default::default()
            },
            message_count: 1,
            estimated_cost_usd: 1.25,
            timed_duration_ms: 100,
            timed_tokens: 10,
            timed_sample_count: 1,
            cost_coverage: tokscale_core::CostCoverage::Complete,
        }],
    }
}
fn report(fragment: WorkspaceSessionFragment) -> WorkspaceSessionReport {
    WorkspaceSessionReport {
        fragments: vec![fragment],
        processing_time_ms: 0,
        record_limit_reached: false,
        timing_coverage_partial: false,
        overflowed_fragment_observations: 0,
        overflowed_timing_observations: 0,
        overflowed_model_observations: 0,
    }
}
fn output(value: &str) -> Result<GitOutput, GitRunnerError> {
    Ok(GitOutput {
        stdout: value.as_bytes().to_vec(),
        stderr: vec![],
    })
}
#[test]
fn earliest_same_repository_commit_in_inclusive_four_hour_window_gets_one_fragment() {
    let git = FakeGitRunner::new(vec![output("/repos/a\n"), output("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\x002026-09-01T12:00:00Z\0x\0aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\x002026-09-01T12:00:00Z\0x\0")]);
    let payload = build_analytics_payload(
        report(fragment("/repos/a", "2026-09-01T10:00:00Z")),
        time("2026-09-01T16:00:00Z"),
        &git,
    );
    assert_eq!(payload.repositories[0].commits[0].commit_id, "aaaaaaaaaaaa");
    assert_eq!(payload.repositories[0].coverage.assigned_fragments, 1);
}
#[test]
fn exact_four_hour_boundary_matches_but_one_second_later_does_not() {
    let matching = FakeGitRunner::new(vec![
        output("/repos/a\n"),
        output("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\x002026-09-01T14:00:00Z\0x\0"),
    ]);
    let matched = build_analytics_payload(
        report(fragment("/repos/a", "2026-09-01T10:00:00Z")),
        time("2026-09-01T20:00:00Z"),
        &matching,
    );
    assert_eq!(matched.repositories[0].coverage.assigned_fragments, 1);
    let late = FakeGitRunner::new(vec![
        output("/repos/a\n"),
        output("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\x002026-09-01T14:00:01Z\0x\0"),
    ]);
    let unmatched = build_analytics_payload(
        report(fragment("/repos/a", "2026-09-01T10:00:00Z")),
        time("2026-09-01T20:00:00Z"),
        &late,
    );
    assert_eq!(unmatched.unattributed.reasons["noEligibleCommit"], 1);
}
#[test]
fn fragment_inside_open_window_is_pending_not_no_eligible_commit() {
    let git = FakeGitRunner::new(vec![output("/repos/a\n"), output("")]);
    let payload = build_analytics_payload(
        report(fragment("/repos/a", "2026-09-01T11:00:01Z")),
        time("2026-09-01T12:00:00Z"),
        &git,
    );
    assert_eq!(payload.unattributed.reasons["pendingCommitWindow"], 1);
}
