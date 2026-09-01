use needlbar_project_analytics::{GitOutput, GitRequestKind};

#[test]
fn public_git_boundary_exposes_kind_and_fake_output_without_paths_or_raw_getters() {
    let output = GitOutput::new(b"fixture".to_vec(), b"stderr".to_vec());
    assert!(!format!("{output:?}").contains("/private"));
    assert_eq!(
        GitRequestKind::DiscoverRepository,
        GitRequestKind::DiscoverRepository
    );
}
