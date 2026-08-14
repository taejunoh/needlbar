use std::{
    collections::VecDeque,
    fs,
    path::Path,
    sync::{Arc, Mutex},
};

use async_trait::async_trait;
use needlbar_source_sync::{
    sync_cursor_cache_with_transport_in_home, write_cursor_session_in_home, CursorUsageTransport,
    SourceSyncError,
};
use tempfile::TempDir;

const TWO_ROW_CSV: &str = "Date,Kind,Model,Max Mode,Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,Output Tokens,Total Tokens,Cost\n\"2026-08-01T12:00:00.000Z\",\"Included\",\"composer-2\",\"No\",\"100\",\"75\",\"25\",\"50\",\"150\",\"0.00\"\n\"2026-08-02T12:00:00.000Z\",\"On-Demand\",\"gpt-5-codex\",\"No\",\"20\",\"20\",\"5\",\"15\",\"40\",\"0.10\"\n";
const V1_CSV: &str = "Date,Model,Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,Output Tokens,Total Tokens,Cost,Cost to you\n2026-08-01,gpt-4o,100,75,25,50,150,$0.10,$0.10\n";

#[derive(Clone)]
struct FakeTransport {
    responses: Arc<Mutex<VecDeque<Result<String, SourceSyncError>>>>,
    calls: Arc<Mutex<usize>>,
}

impl FakeTransport {
    fn new(responses: impl IntoIterator<Item = Result<String, SourceSyncError>>) -> Self {
        Self {
            responses: Arc::new(Mutex::new(responses.into_iter().collect())),
            calls: Arc::new(Mutex::new(0)),
        }
    }

    fn calls(&self) -> usize {
        *self.calls.lock().expect("call lock")
    }
}

#[async_trait]
impl CursorUsageTransport for FakeTransport {
    async fn export_usage_csv(&self, _session_token: &str) -> Result<String, SourceSyncError> {
        *self.calls.lock().expect("call lock") += 1;
        self.responses
            .lock()
            .expect("response lock")
            .pop_front()
            .expect("configured fake response")
    }
}

#[test]
fn freshness_force_and_failed_refresh_preserve_the_last_complete_cache() {
    let home = TempDir::new().expect("fixture home");
    write_cursor_session_in_home(home.path(), "test-session-token").expect("write session");
    let transport = FakeTransport::new([
        Ok(TWO_ROW_CSV.to_owned()),
        Ok(TWO_ROW_CSV.to_owned()),
        Err(SourceSyncError::Transport("simulated outage".to_owned())),
    ]);

    let first = sync_cursor_cache_with_transport_in_home(home.path(), false, &transport)
        .expect("first sync outcome");
    assert!(first.synced);
    assert_eq!(first.rows, 2);
    assert_eq!(transport.calls(), 1);

    let cache = cache_path(home.path());
    let first_bytes = fs::read(&cache).expect("first cache bytes");
    assert_eq!(first_bytes, TWO_ROW_CSV.as_bytes());

    let fresh = sync_cursor_cache_with_transport_in_home(home.path(), false, &transport)
        .expect("freshness outcome");
    assert!(!fresh.synced);
    assert!(fresh.error.is_none());
    assert_eq!(transport.calls(), 1, "fresh cache must not call Cursor");

    let forced = sync_cursor_cache_with_transport_in_home(home.path(), true, &transport)
        .expect("forced sync outcome");
    assert!(forced.synced);
    assert_eq!(transport.calls(), 2, "force bypasses the freshness gate");

    let failed = sync_cursor_cache_with_transport_in_home(home.path(), true, &transport)
        .expect("failed refresh outcome");
    assert!(!failed.synced);
    assert!(failed.error.is_some());
    assert_eq!(transport.calls(), 3);
    assert_eq!(
        fs::read(cache).expect("cache remains readable"),
        first_bytes,
        "a failed refresh must not replace the previous complete cache"
    );
}

#[test]
fn malformed_export_does_not_replace_a_previous_tokscale_compatible_cache() {
    let home = TempDir::new().expect("fixture home");
    write_cursor_session_in_home(home.path(), "test-session-token").expect("write session");
    let transport = FakeTransport::new([
        Ok(TWO_ROW_CSV.to_owned()),
        Ok("Date,Model\nnot-a-valid-cursor-event\n".to_owned()),
    ]);

    let first = sync_cursor_cache_with_transport_in_home(home.path(), false, &transport)
        .expect("first sync outcome");
    assert!(first.synced);
    let cache = cache_path(home.path());
    let previous = fs::read(&cache).expect("previous cache");

    let malformed = sync_cursor_cache_with_transport_in_home(home.path(), true, &transport)
        .expect("malformed sync outcome");
    assert!(!malformed.synced);
    assert!(matches!(malformed.error, Some(SourceSyncError::InvalidCsv)));
    assert_eq!(fs::read(cache).expect("preserved cache"), previous);
}

#[test]
fn pinned_parser_supported_v1_export_syncs_with_an_accurate_row_count() {
    let home = TempDir::new().expect("fixture home");
    write_cursor_session_in_home(home.path(), "test-session-token").expect("write session");
    let transport = FakeTransport::new([Ok(V1_CSV.to_owned())]);

    let outcome = sync_cursor_cache_with_transport_in_home(home.path(), true, &transport)
        .expect("v1 sync outcome");
    assert!(outcome.synced);
    assert_eq!(outcome.rows, 1);
    assert_eq!(
        fs::read(cache_path(home.path())).expect("v1 cache"),
        V1_CSV.as_bytes()
    );
}

#[cfg(unix)]
#[test]
fn symlinked_private_session_and_cache_directories_are_rejected_without_following_them() {
    use std::os::unix::fs::symlink;

    let session_home = TempDir::new().expect("session home");
    let outside = TempDir::new().expect("outside directory");
    let session_parent = session_home.path().join("Library/Application Support");
    fs::create_dir_all(&session_parent).expect("session parent");
    symlink(outside.path(), session_parent.join("Needlbar")).expect("session symlink");

    assert!(write_cursor_session_in_home(session_home.path(), "test-session-token").is_err());
    assert!(
        !outside.path().join("cursor-session.json").exists(),
        "session write must not follow a Needlbar directory symlink"
    );

    let cache_home = TempDir::new().expect("cache home");
    write_cursor_session_in_home(cache_home.path(), "test-session-token").expect("write session");
    fs::create_dir_all(cache_home.path().join(".config")).expect("config parent");
    symlink(outside.path(), cache_home.path().join(".config/tokscale")).expect("cache symlink");
    let transport = FakeTransport::new([Ok(TWO_ROW_CSV.to_owned())]);

    assert!(sync_cursor_cache_with_transport_in_home(cache_home.path(), true, &transport).is_err());
    assert_eq!(transport.calls(), 0);
    assert!(
        !outside.path().join("cursor-cache/usage.csv").exists(),
        "cache write must not follow a tokscale directory symlink"
    );
}

#[cfg(unix)]
#[test]
fn symlinked_session_cache_and_marker_files_are_rejected_without_modifying_their_targets() {
    use std::os::unix::fs::symlink;

    let outside = TempDir::new().expect("outside directory");
    let session_target = outside.path().join("session-target");
    fs::write(&session_target, "do not overwrite").expect("session target");
    let session_home = TempDir::new().expect("session home");
    write_cursor_session_in_home(session_home.path(), "test-session-token").expect("write session");
    let session = session_home
        .path()
        .join("Library/Application Support/Needlbar/cursor-session.json");
    fs::remove_file(&session).expect("remove session");
    symlink(&session_target, &session).expect("session symlink");
    let session_transport = FakeTransport::new([Ok(TWO_ROW_CSV.to_owned())]);

    let session_outcome =
        sync_cursor_cache_with_transport_in_home(session_home.path(), true, &session_transport)
            .expect("session outcome");
    assert!(matches!(
        session_outcome.error,
        Some(SourceSyncError::UnsafePath(_))
    ));
    assert_eq!(session_transport.calls(), 0);
    assert_eq!(
        fs::read_to_string(&session_target).expect("session target"),
        "do not overwrite"
    );

    let cache_home = TempDir::new().expect("cache home");
    write_cursor_session_in_home(cache_home.path(), "test-session-token").expect("write session");
    let cache_dir = cache_home.path().join(".config/tokscale/cursor-cache");
    fs::create_dir_all(&cache_dir).expect("cache directory");
    let cache_target = outside.path().join("cache-target");
    fs::write(&cache_target, "do not overwrite").expect("cache target");
    symlink(&cache_target, cache_dir.join("usage.csv")).expect("cache symlink");
    let cache_transport = FakeTransport::new([Ok(TWO_ROW_CSV.to_owned())]);

    let cache_outcome =
        sync_cursor_cache_with_transport_in_home(cache_home.path(), true, &cache_transport)
            .expect("cache outcome");
    assert!(matches!(
        cache_outcome.error,
        Some(SourceSyncError::UnsafePath(_))
    ));
    assert_eq!(
        fs::read_to_string(&cache_target).expect("cache target"),
        "do not overwrite"
    );

    let marker_home = TempDir::new().expect("marker home");
    write_cursor_session_in_home(marker_home.path(), "test-session-token").expect("write session");
    let marker_transport =
        FakeTransport::new([Ok(TWO_ROW_CSV.to_owned()), Ok(TWO_ROW_CSV.to_owned())]);
    assert!(
        sync_cursor_cache_with_transport_in_home(marker_home.path(), true, &marker_transport)
            .expect("initial marker sync")
            .synced
    );
    let marker = marker_home
        .path()
        .join(".config/tokscale/cursor-cache/usage.last-sync-attempt");
    fs::remove_file(&marker).expect("remove marker");
    let marker_target = outside.path().join("marker-target");
    fs::write(&marker_target, "do not overwrite").expect("marker target");
    symlink(&marker_target, &marker).expect("marker symlink");

    let marker_outcome =
        sync_cursor_cache_with_transport_in_home(marker_home.path(), true, &marker_transport)
            .expect("marker outcome");
    assert!(matches!(
        marker_outcome.error,
        Some(SourceSyncError::UnsafePath(_))
    ));
    assert_eq!(
        fs::read_to_string(&marker_target).expect("marker target"),
        "do not overwrite"
    );
}

fn cache_path(home: &Path) -> std::path::PathBuf {
    home.join(".config/tokscale/cursor-cache/usage.csv")
}
