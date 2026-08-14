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

fn cache_path(home: &Path) -> std::path::PathBuf {
    home.join(".config/tokscale/cursor-cache/usage.csv")
}
