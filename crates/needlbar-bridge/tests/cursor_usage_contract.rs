use std::{fs, path::Path};

use needlbar_bridge::usage::collect_usage_from_home;
use tempfile::TempDir;

#[test]
fn pinned_core_discovers_cursor_usage_from_the_tokscale_cache_layout() {
    let home = TempDir::new().expect("fixture home");
    let fixture =
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../Fixtures/usage/cursor/usage.csv");
    let cache = home.path().join(".config/tokscale/cursor-cache/usage.csv");
    fs::create_dir_all(cache.parent().expect("cache parent")).expect("cache directory");
    fs::copy(fixture, cache).expect("cursor fixture cache");

    let snapshots = collect_usage_from_home(home.path()).expect("fixture usage collects");
    let cursor = snapshots
        .iter()
        .find(|snapshot| snapshot.provider == "cursor")
        .expect("Cursor snapshot");

    assert_eq!(cursor.provider, "cursor");
    assert!(cursor.all_time_split.total_tokens > 0);
}
