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

#[test]
fn ambiguous_workspace_mapping_is_partial_without_discarding_other_repository() {
    let git = FakeGitRunner::new(vec![
        output("/repos/a\n/repos/also-a\n"),
        output("/repos/b\n"),
        output(""),
    ]);
    let mut report = report(fragment("/repos/a", "2026-09-01T10:00:00Z"));
    report
        .fragments
        .push(fragment("/repos/b", "2026-09-01T10:00:00Z"));
    let payload = build_analytics_payload(report, time("2026-09-01T16:00:00Z"), &git);
    assert_eq!(payload.repositories.len(), 1);
    assert_eq!(payload.coverage.reasons["ambiguousRepository"], 1);
}

fn commit(oid: &str, when: &str, message: &str) -> String {
    format!("{oid}\x00{when}\x00{message}\x00")
}

#[test]
fn multiple_fragments_correlate_once_each_to_the_same_commit_with_exact_totals() {
    let git = FakeGitRunner::new(vec![
        output("/repos/a\n"),
        output("/repos/a\n"),
        output(&commit(
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "2026-09-01T12:00:00Z",
            "",
        )),
    ]);
    let mut source = report(fragment("/repos/a", "2026-09-01T10:00:00Z"));
    source
        .fragments
        .push(fragment("/repos/a", "2026-09-01T11:00:00Z"));
    let payload = build_analytics_payload(source, time("2026-09-01T20:00:00Z"), &git);
    assert_eq!(payload.repositories[0].coverage.assigned_fragments, 2);
    assert_eq!(payload.repositories[0].commits.len(), 1);
    assert_eq!(
        payload.repositories[0].commits[0]
            .correlated_usage
            .estimated_cost_usd,
        "2.5"
    );
}

#[test]
fn local_pr_markers_require_exactly_one_standalone_valid_candidate() {
    for (message, expected) in [
        ("fix (#42)", Some(42)),
        ("fix PR #7", Some(7)),
        ("fix (#0)", None),
        ("fix PR #2147483648", None),
        ("fix (#7", None),
        ("fix abcPR #7", None),
        ("fix (#7) PR #8", None),
    ] {
        let git = FakeGitRunner::new(vec![
            output("/repos/a\n"),
            output(&commit(
                "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "2026-09-01T12:00:00Z",
                message,
            )),
        ]);
        let payload = build_analytics_payload(
            report(fragment("/repos/a", "2026-09-01T10:00:00Z")),
            time("2026-09-01T20:00:00Z"),
            &git,
        );
        assert_eq!(
            payload.repositories[0].commits[0].pull_request_number, expected,
            "{message}"
        );
    }
}

#[test]
fn output_and_record_caps_are_fixed_partial_results() {
    let large = vec![b'x'; 1024 * 1024 + 1];
    let git = FakeGitRunner::new(vec![Ok(GitOutput {
        stdout: large,
        stderr: vec![],
    })]);
    let payload = build_analytics_payload(
        report(fragment("/repos/a", "2026-09-01T10:00:00Z")),
        time("2026-09-01T20:00:00Z"),
        &git,
    );
    assert_eq!(payload.coverage.reasons["gitOutputLimitReached"], 1);

    let git = FakeGitRunner::new(vec![
        output("/repos/a\n"),
        Ok(GitOutput {
            stdout: vec![],
            stderr: vec![b'x'; 8 * 1024 + 1],
        }),
    ]);
    let payload = build_analytics_payload(
        report(fragment("/repos/a", "2026-09-01T10:00:00Z")),
        time("2026-09-01T20:00:00Z"),
        &git,
    );
    assert_eq!(
        payload.repositories[0].coverage.reasons["gitOutputLimitReached"],
        1
    );
}

#[test]
fn repository_cap_is_deterministic_and_overflow_is_unattributed() {
    let mut source = report(fragment("/repos/00", "2026-09-01T10:00:00Z"));
    for index in 1..65 {
        source.fragments.push(fragment(
            &format!("/repos/{index:02}"),
            "2026-09-01T10:00:00Z",
        ));
    }
    let mut responses = Vec::new();
    for index in 0..65 {
        responses.push(output(&format!("/repos/{index:02}\n")));
    }
    for _ in 0..64 {
        responses.push(output(""));
    }
    let payload = build_analytics_payload(
        source,
        time("2026-09-01T20:00:00Z"),
        &FakeGitRunner::new(responses),
    );
    assert_eq!(payload.repositories.len(), 64);
    assert_eq!(payload.unattributed.reasons["recordLimitReached"], 1);
    assert!(payload
        .repositories
        .windows(2)
        .all(|pair| pair[0].repository_id <= pair[1].repository_id));
}

#[test]
fn parsed_commit_cap_and_returned_commit_cap_are_bounded() {
    let mut log = String::new();
    for index in 0..501 {
        log.push_str(&commit(
            &format!("{index:040x}"),
            &format!("2026-09-01T12:{:02}:00Z", index % 60),
            "",
        ));
    }
    let git = FakeGitRunner::new(vec![output("/repos/a\n"), output(&log)]);
    let payload = build_analytics_payload(
        report(fragment("/repos/a", "2026-09-01T10:00:00Z")),
        time("2026-09-01T20:00:00Z"),
        &git,
    );
    assert_eq!(
        payload.repositories[0].coverage.reasons["recordLimitReached"],
        1
    );

    let mut source = WorkspaceSessionReport {
        fragments: Vec::new(),
        processing_time_ms: 0,
        record_limit_reached: false,
        timing_coverage_partial: false,
        overflowed_fragment_observations: 0,
        overflowed_timing_observations: 0,
        overflowed_model_observations: 0,
    };
    let mut log = String::new();
    let mut replies = Vec::new();
    for index in 0..201 {
        let stamp = format!("2026-09-01T10:{:02}:{:02}Z", index / 60, index % 60);
        source.fragments.push(fragment("/repos/a", &stamp));
        replies.push(output("/repos/a\n"));
        log.push_str(&commit(&format!("{index:040x}"), &stamp, ""));
    }
    replies.push(output(&log));
    let payload = build_analytics_payload(
        source,
        time("2026-09-01T20:00:00Z"),
        &FakeGitRunner::new(replies),
    );
    assert_eq!(payload.repositories[0].coverage.assigned_fragments, 201);
    assert_eq!(payload.repositories[0].commits.len(), 200);
}

#[test]
fn missing_workspace_and_unavailable_git_are_separate_partial_reasons() {
    let mut source = report(fragment("/repos/a", "2026-09-01T10:00:00Z"));
    source.fragments.push(WorkspaceSessionFragment {
        workspace_key: None,
        ..fragment("/ignored", "2026-09-01T10:00:00Z")
    });
    let unavailable =
        FakeGitRunner::new(vec![output("/repos/a\n"), Err(GitRunnerError::Unavailable)]);
    let payload = build_analytics_payload(source, time("2026-09-01T20:00:00Z"), &unavailable);
    assert_eq!(payload.unattributed.reasons["missingWorkspace"], 1);
    assert_eq!(
        payload.repositories[0].coverage.reasons["repositoryUnavailable"],
        1
    );
}

#[test]
fn duplicate_or_invalid_labels_are_replaced_with_bounded_generic_labels() {
    let git = FakeGitRunner::new(vec![
        output("/alpha/project\n"),
        output("/beta/project\n"),
        output(""),
        output(""),
    ]);
    let mut source = report(fragment("/alpha/project", "2026-09-01T10:00:00Z"));
    source
        .fragments
        .push(fragment("/beta/project", "2026-09-01T10:00:00Z"));
    let payload = build_analytics_payload(source, time("2026-09-01T20:00:00Z"), &git);
    assert!(payload
        .repositories
        .iter()
        .all(|repository| repository.label.starts_with("Repository r")));
    assert!(payload
        .repositories
        .iter()
        .all(|repository| repository.label.len() <= 80));
}

#[test]
fn invalid_numbers_models_and_task_one_partial_flags_are_folded_safely() {
    let mut source = report(fragment("/repos/a", "2026-09-01T10:00:00Z"));
    source.fragments[0].tokens.input = -5;
    source.fragments[0].estimated_cost_usd = 1.230_000;
    source.fragments[0].models[0].model = "model\ncanary".into();
    source.record_limit_reached = true;
    source.timing_coverage_partial = true;
    source.fragments.push(WorkspaceSessionFragment {
        workspace_key: None,
        estimated_cost_usd: f64::NAN,
        ..fragment("/ignored", "2026-09-01T10:00:00Z")
    });
    let git = FakeGitRunner::new(vec![
        output("/repos/a\n"),
        output(&commit(
            "ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD",
            "2026-09-01T12:00:00Z",
            "",
        )),
    ]);
    let payload = build_analytics_payload(source, time("2026-09-01T20:00:00Z"), &git);
    assert_eq!(payload.repositories[0].usage.input_tokens, "0");
    assert_eq!(payload.repositories[0].usage.estimated_cost_usd, "1.23");
    assert_eq!(
        payload.repositories[0].provider_models[0].model,
        "Other model"
    );
    assert_eq!(payload.repositories[0].commits[0].commit_id, "abcdefabcdef");
    assert_eq!(payload.coverage.reasons["recordLimitReached"], 1);
    assert_eq!(payload.coverage.reasons["missingDuration"], 1);
    assert_eq!(payload.unattributed.reasons["missingWorkspace"], 1);
}
