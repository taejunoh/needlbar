use std::{fs, path::Path};

use needlbar_bridge::usage::collect_usage_from_home;
use tempfile::TempDir;

#[test]
fn fixture_home_aggregates_exact_claude_and_codex_totals() {
    let home = TempDir::new().expect("fixture home");
    let fixtures = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../Fixtures/usage");
    copy_tree(&fixtures.join("claude"), home.path());
    copy_tree(&fixtures.join("codex"), home.path());

    let snapshots = collect_usage_from_home(home.path()).expect("fixture usage collects");

    assert_eq!(snapshots.len(), 2);
    let claude = snapshots
        .iter()
        .find(|snapshot| snapshot.provider == "claude")
        .expect("Claude snapshot");
    assert_eq!(claude.all_time_split.input_tokens, 1_000);
    assert_eq!(claude.all_time_split.output_tokens, 250);
    assert_eq!(claude.all_time_split.cache_read_tokens, 400);
    assert_eq!(claude.all_time_split.cache_write_tokens, 100);
    assert_eq!(claude.all_time_split.total_tokens, 1_750);

    let codex = snapshots
        .iter()
        .find(|snapshot| snapshot.provider == "codex")
        .expect("Codex snapshot");
    assert_eq!(codex.all_time_split.input_tokens, 800);
    assert_eq!(codex.all_time_split.output_tokens, 200);
    assert_eq!(codex.all_time_split.cache_read_tokens, 300);
    assert_eq!(codex.all_time_split.cache_write_tokens, 0);
    assert_eq!(codex.all_time_split.total_tokens, 1_300);

    let wire = serde_json::to_value(claude).expect("usage snapshot JSON");
    assert_eq!(wire["inputTokens"], 1_000);
    assert!(wire.get("allTimeSplit").is_none());
    assert!(wire.get("today").is_some());
    assert!(wire.get("last7Days").is_some());
    let daily = wire["last7DaysDaily"]
        .as_array()
        .expect("daily 7-day series");
    assert_eq!(daily.len(), 7);
    assert!(daily.windows(2).all(|points| {
        points[0]["date"].as_str().expect("first date")
            < points[1]["date"].as_str().expect("second date")
    }));
    assert!(wire.get("last30Days").is_some());
}

fn copy_tree(source: &Path, destination: &Path) {
    for entry in fs::read_dir(source).expect("fixture directory") {
        let entry = entry.expect("fixture entry");
        let destination_path = destination.join(entry.file_name());
        let file_type = entry.file_type().expect("fixture file type");
        if file_type.is_dir() {
            fs::create_dir_all(&destination_path).expect("fixture destination directory");
            copy_tree(&entry.path(), &destination_path);
        } else {
            fs::copy(entry.path(), destination_path).expect("fixture copy");
        }
    }
}
