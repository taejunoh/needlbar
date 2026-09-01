use needlbar_project_analytics::{BoundedGitRunner, GitRequest, GitRunner};
use std::path::PathBuf;
use std::process::Command;
#[test]
fn bounded_runner_rejects_missing_workspace_without_a_shell() {
    let runner = BoundedGitRunner::default();
    let result = runner.run(GitRequest::DiscoverRepository {
        workspace: PathBuf::from("/definitely/not/a/repository"),
    });
    assert!(result.is_err());
}

#[test]
fn bounded_runner_reads_only_a_disposable_local_repository() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path();
    assert!(Command::new("/usr/bin/git")
        .args(["init", "--quiet"])
        .current_dir(root)
        .status()
        .unwrap()
        .success());
    assert!(Command::new("/usr/bin/git")
        .args([
            "-c",
            "user.name=Test",
            "-c",
            "user.email=test@example.invalid",
            "commit",
            "--quiet",
            "--allow-empty",
            "-m",
            "PR #7",
        ])
        .current_dir(root)
        .status()
        .unwrap()
        .success());
    let runner = BoundedGitRunner::default();
    let discovered = runner
        .run(GitRequest::DiscoverRepository {
            workspace: root.into(),
        })
        .unwrap();
    assert!(String::from_utf8(discovered.stdout)
        .unwrap()
        .contains(root.to_str().unwrap()));
    let log = runner
        .run(GitRequest::ReadCommits {
            repository: root.into(),
        })
        .unwrap();
    assert!(log.stdout.split(|byte| *byte == 0).count() >= 3);
}
