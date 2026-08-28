use std::{
    fs,
    path::{Path, PathBuf},
};

use needlbar_bridge::cursor_credential_cleanup::cleanup_obsolete_cursor_session_in_home;
use tempfile::TempDir;

const SESSION_CANARY: &str = "CURSOR-SESSION-CANARY";

fn session_path(home: &Path) -> PathBuf {
    home.join("Library/Application Support/Needlbar/cursor-session.json")
}

fn create_session_file(home: &Path) -> PathBuf {
    let session = session_path(home);
    fs::create_dir_all(session.parent().expect("session parent")).expect("session directory");
    fs::write(&session, SESSION_CANARY).expect("synthetic session");
    session
}

#[test]
fn regular_obsolete_session_is_removed_without_exposing_its_contents() {
    // A cleanup implementation that reads or returns the credential rather
    // than unlinking the regular file directly violates the bridge boundary.
    let home = TempDir::new().expect("temporary home");
    let session = create_session_file(home.path());

    cleanup_obsolete_cursor_session_in_home(home.path()).expect("cleanup succeeds");
    assert!(!session.exists());
}

#[test]
fn repeated_cleanup_succeeds_without_creating_missing_parent_directories() {
    // This catches cleanup that uses create_dir_all or otherwise turns a
    // missing legacy path into a persistent filesystem side effect.
    let home = TempDir::new().expect("temporary home");

    cleanup_obsolete_cursor_session_in_home(home.path()).expect("first cleanup succeeds");
    cleanup_obsolete_cursor_session_in_home(home.path()).expect("second cleanup succeeds");

    assert!(!home.path().join("Library").exists());
}

#[cfg(unix)]
#[test]
fn symlink_session_leaf_is_rejected_and_target_bytes_are_preserved() {
    // This catches path-following unlink/read behavior that could affect a
    // target outside Needlbar's legacy session directory.
    let home = TempDir::new().expect("temporary home");
    let target = home.path().join("outside-session-target");
    fs::write(&target, SESSION_CANARY).expect("outside target");
    let session = session_path(home.path());
    fs::create_dir_all(session.parent().expect("session parent")).expect("session directory");
    std::os::unix::fs::symlink(&target, &session).expect("session symlink");

    assert!(cleanup_obsolete_cursor_session_in_home(home.path()).is_err());
    assert!(fs::symlink_metadata(&session)
        .expect("session link remains")
        .file_type()
        .is_symlink());
    assert_eq!(
        fs::read_to_string(target).expect("target remains readable"),
        SESSION_CANARY
    );
}

#[test]
fn cleanup_preserves_the_local_cursor_usage_cache() {
    // This catches broad legacy-directory deletion that would erase the
    // local-only usage input owned by tokscale-core.
    let home = TempDir::new().expect("temporary home");
    let cache = home.path().join(".config/tokscale/cursor-cache/usage.csv");
    fs::create_dir_all(cache.parent().expect("cache parent")).expect("cache directory");
    fs::write(&cache, "date,model,tokens\n").expect("usage cache");
    create_session_file(home.path());

    cleanup_obsolete_cursor_session_in_home(home.path()).expect("cleanup succeeds");

    assert_eq!(
        fs::read_to_string(cache).expect("usage cache remains"),
        "date,model,tokens\n"
    );
}
