use chrono::{DateTime, Utc};
use needlbar_project_analytics::{
    build_analytics_payload, BoundedGitRunner, GitOutput, GitRequestKind,
};
use std::process::Command;
use tokscale_core::{
    CostCoverage, TokenBreakdown, WorkspaceSessionFragment, WorkspaceSessionModel,
    WorkspaceSessionReport,
};

#[test]
fn public_git_boundary_exposes_kind_and_fake_output_without_paths_or_raw_getters() {
    let output = GitOutput::new(b"fixture".to_vec(), b"stderr".to_vec());
    assert!(!format!("{output:?}").contains("/private"));
    assert_eq!(
        GitRequestKind::DiscoverRepository,
        GitRequestKind::DiscoverRepository
    );
}

fn at(value: &str) -> DateTime<Utc> {
    value.parse().unwrap()
}
fn report(workspace: &std::path::Path) -> WorkspaceSessionReport {
    let when = at("2026-09-01T10:00:00Z");
    WorkspaceSessionReport {
        fragments: vec![WorkspaceSessionFragment {
            client: "codex".into(),
            workspace_key: Some(workspace.display().to_string()),
            session_id: "private-session".into(),
            first_seen_ms: when.timestamp_millis(),
            last_seen_ms: when.timestamp_millis(),
            active_time_ms: 0,
            timing_coverage_partial: false,
            tokens: TokenBreakdown {
                input: 10,
                ..Default::default()
            },
            message_count: 1,
            estimated_cost_usd: 1.0,
            models: vec![WorkspaceSessionModel {
                model: "gpt-5".into(),
                provider: "codex".into(),
                tokens: TokenBreakdown {
                    input: 10,
                    ..Default::default()
                },
                message_count: 1,
                estimated_cost_usd: 1.0,
                timed_duration_ms: 0,
                timed_tokens: 0,
                timed_sample_count: 0,
                cost_coverage: CostCoverage::Complete,
            }],
        }],
        processing_time_ms: 0,
        record_limit_reached: false,
        timing_coverage_partial: false,
        overflowed_fragment_observations: 0,
        overflowed_timing_observations: 0,
        overflowed_model_observations: 0,
    }
}
fn git(root: &std::path::Path, args: &[&str]) {
    assert!(Command::new("/usr/bin/git")
        .args(args)
        .current_dir(root)
        .status()
        .unwrap()
        .success());
}

#[test]
fn observed_symlink_dotdot_and_linked_worktree_resolve_to_local_repositories_without_path_leakage()
{
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().join("repo");
    std::fs::create_dir(&root).unwrap();
    git(&root, &["init", "--quiet"]);
    git(
        &root,
        &[
            "-c",
            "user.name=Test",
            "-c",
            "user.email=test@example.invalid",
            "commit",
            "--quiet",
            "--allow-empty",
            "-m",
            "init",
        ],
    );
    let link = temp.path().join("observed-link");
    std::os::unix::fs::symlink(&root, &link).unwrap();
    std::fs::create_dir(temp.path().join("x")).unwrap();
    let worktree = temp.path().join("linked");
    git(
        &root,
        &[
            "worktree",
            "add",
            "--quiet",
            "-b",
            "linked-branch",
            worktree.to_str().unwrap(),
        ],
    );
    for observed in [link, temp.path().join("x/../repo"), worktree] {
        let payload = build_analytics_payload(
            report(&observed),
            at("2026-09-01T20:00:00Z"),
            &BoundedGitRunner::default(),
        );
        assert_eq!(
            payload.repositories.len(),
            1,
            "{}",
            serde_json::to_string(&payload).unwrap()
        );
        assert!(!serde_json::to_string(&payload)
            .unwrap()
            .contains(&observed.display().to_string()));
    }
}
