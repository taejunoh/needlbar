use chrono::{DateTime, Utc};
use needlbar_project_analytics::{
    build_analytics_payload, GitOutput, GitRequest, GitRequestKind, GitRunner, GitRunnerError,
};
use serde::Deserialize;
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use tokscale_core::{
    CostCoverage, TokenBreakdown, WorkspaceSessionFragment, WorkspaceSessionModel,
    WorkspaceSessionReport,
};

#[derive(Deserialize)]
struct Fixture {
    generated_at: DateTime<Utc>,
    git_stderr_canary: String,
    privacy_canaries: Vec<String>,
    fragments: Vec<FixtureFragment>,
    report: FixtureReport,
}
#[derive(Deserialize)]
struct FixtureFragment {
    client: String,
    workspace_key: Option<String>,
    session_id: String,
    first_seen_ms: i64,
    last_seen_ms: i64,
    active_time_ms: i64,
    timing_coverage_partial: bool,
    tokens: TokenBreakdown,
    message_count: i64,
    estimated_cost_usd: f64,
    models: Vec<FixtureModel>,
}
#[derive(Deserialize)]
struct FixtureModel {
    model: String,
    provider: String,
    tokens: TokenBreakdown,
    message_count: i64,
    estimated_cost_usd: f64,
    timed_duration_ms: i64,
    timed_tokens: i64,
    timed_sample_count: i32,
    cost_coverage: String,
}
#[derive(Deserialize)]
struct FixtureReport {
    processing_time_ms: u32,
    record_limit_reached: bool,
    timing_coverage_partial: bool,
    overflowed_fragment_observations: u64,
    overflowed_timing_observations: u64,
    overflowed_model_observations: u64,
}

struct FixtureGit {
    replies: Mutex<VecDeque<Result<GitOutput, GitRunnerError>>>,
    kinds: Arc<Mutex<Vec<GitRequestKind>>>,
}
impl GitRunner for FixtureGit {
    fn run(&self, request: GitRequest) -> Result<GitOutput, GitRunnerError> {
        self.kinds.lock().unwrap().push(request.kind());
        self.replies.lock().unwrap().pop_front().unwrap()
    }
}

fn fixture() -> Fixture {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../Fixtures/analytics/workspace-session-fixture.json");
    serde_json::from_slice(&std::fs::read(root).unwrap()).unwrap()
}

fn report(fixture: &Fixture) -> WorkspaceSessionReport {
    WorkspaceSessionReport {
        fragments: fixture
            .fragments
            .iter()
            .map(|fragment| WorkspaceSessionFragment {
                client: fragment.client.clone(),
                workspace_key: fragment.workspace_key.clone(),
                session_id: fragment.session_id.clone(),
                first_seen_ms: fragment.first_seen_ms,
                last_seen_ms: fragment.last_seen_ms,
                active_time_ms: fragment.active_time_ms,
                timing_coverage_partial: fragment.timing_coverage_partial,
                tokens: fragment.tokens.clone(),
                message_count: fragment.message_count,
                estimated_cost_usd: fragment.estimated_cost_usd,
                models: fragment
                    .models
                    .iter()
                    .map(|model| WorkspaceSessionModel {
                        model: model.model.clone(),
                        provider: model.provider.clone(),
                        tokens: model.tokens.clone(),
                        message_count: model.message_count,
                        estimated_cost_usd: model.estimated_cost_usd,
                        timed_duration_ms: model.timed_duration_ms,
                        timed_tokens: model.timed_tokens,
                        timed_sample_count: model.timed_sample_count,
                        cost_coverage: match model.cost_coverage.as_str() {
                            "complete" => CostCoverage::Complete,
                            "partial" => CostCoverage::Partial,
                            "none" => CostCoverage::None,
                            other => panic!("unknown fixture coverage {other}"),
                        },
                    })
                    .collect(),
            })
            .collect(),
        processing_time_ms: fixture.report.processing_time_ms,
        record_limit_reached: fixture.report.record_limit_reached,
        timing_coverage_partial: fixture.report.timing_coverage_partial,
        overflowed_fragment_observations: fixture.report.overflowed_fragment_observations,
        overflowed_timing_observations: fixture.report.overflowed_timing_observations,
        overflowed_model_observations: fixture.report.overflowed_model_observations,
    }
}

fn git_fixture() -> Vec<u8> {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../Fixtures/analytics/git-log-fixture.nul");
    let text = std::fs::read(path).unwrap();
    let text = text.strip_suffix(b"\n").unwrap_or(&text);
    let mut decoded = Vec::with_capacity(text.len());
    let mut index = 0;
    while index < text.len() {
        if index + 1 < text.len() && text[index] == b'\\' && text[index + 1] == b'0' {
            decoded.push(0);
            index += 2;
        } else {
            decoded.push(text[index]);
            index += 1;
        }
    }
    decoded
}

#[test]
fn analytics_acceptance_fixture_exactly_matches_sanitized_golden() {
    let fixture = fixture();
    assert!(fixture.privacy_canaries.len() >= 13);
    let git_log = git_fixture();
    let raw_session = format!("{:?}", report(&fixture));
    let raw_git = format!(
        "{}{}",
        String::from_utf8_lossy(&git_log),
        fixture.git_stderr_canary
    );
    for canary in &fixture.privacy_canaries {
        assert!(
            raw_session.contains(canary) || raw_git.contains(canary),
            "fixture canary must enter raw session or fake Git input: {canary}"
        );
    }
    let kinds = Arc::new(Mutex::new(Vec::new()));
    let git = FixtureGit {
        replies: Mutex::new(
            [
                Ok(GitOutput::new(
                    b"/synthetic/needlbar-fixture/repo\n".to_vec(),
                    fixture.git_stderr_canary.as_bytes().to_vec(),
                )),
                Ok(GitOutput::new(
                    b"/synthetic/needlbar-fixture/repo\n".to_vec(),
                    vec![],
                )),
                Ok(GitOutput::new(
                    b"/synthetic/needlbar-fixture/repo\n".to_vec(),
                    vec![],
                )),
                Err(GitRunnerError::NotRepository),
                Ok(GitOutput::new(git_log, vec![])),
            ]
            .into(),
        ),
        kinds: kinds.clone(),
    };
    let payload = build_analytics_payload(report(&fixture), fixture.generated_at, &git);
    let json = serde_json::to_string_pretty(&payload).unwrap();
    assert_eq!(
        kinds.lock().unwrap().as_slice(),
        &[
            GitRequestKind::DiscoverRepository,
            GitRequestKind::DiscoverRepository,
            GitRequestKind::DiscoverRepository,
            GitRequestKind::DiscoverRepository,
            GitRequestKind::ReadCommits,
        ]
    );
    let golden = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../Fixtures/analytics/expected-payload.json");
    let expected = std::fs::read_to_string(golden).expect("acceptance golden must exist");
    assert_eq!(json, expected.trim_end());
    let value: serde_json::Value = serde_json::from_str(&json).unwrap();
    assert_eq!(value["repositories"][0]["coverage"]["assignedFragments"], 1);
    assert_eq!(
        value["repositories"][0]["coverage"]["reasons"]["pendingCommitWindow"],
        1
    );
    assert_eq!(
        value["repositories"][0]["coverage"]["reasons"]["noEligibleCommit"],
        1
    );
    assert_eq!(
        value["repositories"][0]["commits"][0]["commitId"],
        "aaaaaaaaaaaa"
    );
    assert_eq!(
        value["repositories"][0]["commits"][0]["pullRequestNumber"],
        42
    );
    assert_eq!(json.matches("pullRequestNumber").count(), 1);
    let debug = format!("{payload:?}");
    let errors = serde_json::to_string(&value["errors"]).unwrap();
    for canary in &fixture.privacy_canaries {
        assert!(!json.contains(canary), "serialized canary leaked: {canary}");
        assert!(!debug.contains(canary), "debug canary leaked: {canary}");
        assert!(!errors.contains(canary), "error canary leaked: {canary}");
    }
    assert!(!json.contains("session-") && !json.contains("synthetic boundary"));
}
