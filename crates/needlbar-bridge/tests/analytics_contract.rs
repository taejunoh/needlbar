use std::ffi::CStr;
use std::fs;
use std::os::raw::c_char;
use std::path::Path;

use needlbar_bridge::{
    needlbar_analytics_snapshot_json, needlbar_free_string, test_analytics_interior_nul_pointer,
    test_runtime,
};
use needlbar_project_analytics::{
    AnalysisRange, AnalyticsCoverage, AnalyticsPayload, AttributionBucket, CommitAnalytics,
    RepositoryAnalytics, RepositoryCoverage, RepositoryState, UsageAggregate,
};
use tempfile::TempDir;

struct Fixture {
    _serial: std::sync::MutexGuard<'static, ()>,
    _home: TempDir,
    session: u64,
}

impl Drop for Fixture {
    fn drop(&mut self) {
        assert_eq!(self.session, 0);
        test_runtime::clear_runtime_for_rust_tests();
    }
}

fn fixture() -> Fixture {
    let serial = test_runtime::serial_guard();
    let home = TempDir::new().expect("fixture home");
    assert!(test_runtime::install_redaction_fixture(
        home.path().to_path_buf(),
        "credential-canary /private/repo author@example.com".to_owned(),
        "account-canary raw-remote.example".to_owned(),
        "source-canary stdout-canary stderr-canary".to_owned(),
    ));
    assert!(test_runtime::install_analytics_fixture(
        chrono::DateTime::parse_from_rfc3339("2026-09-01T12:00:00.000Z")
            .expect("fixed analytics time")
            .with_timezone(&chrono::Utc),
    ));
    Fixture {
        _serial: serial,
        _home: home,
        session: 0,
    }
}

#[test]
fn analytics_symbol_is_declared_and_emits_dedicated_envelope() {
    let _fixture = fixture();
    let header = fs::read_to_string(
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../Sources/CNeedlbar/include/needlbar.h"),
    )
    .expect("public C header");
    let prototype = "const char *needlbar_analytics_snapshot_json(void);";
    assert_eq!(header.matches(prototype).count(), 1);

    let call: unsafe extern "C" fn() -> *const c_char = needlbar_analytics_snapshot_json;
    let pointer = unsafe { call() };
    assert!(!pointer.is_null());
    let json = unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .expect("analytics bridge emits UTF-8")
        .to_owned();
    unsafe { needlbar_free_string(pointer) };

    let value: serde_json::Value = serde_json::from_str(&json).expect("analytics JSON");
    assert_eq!(value["schemaVersion"], "needlbar.analytics.v1");
    assert_eq!(value["ok"], true);
    assert!(value["data"].is_object());
    assert_eq!(value["errors"], serde_json::json!([]));
    assert!(value["generatedAt"].is_string());
    assert!(value["errors"].is_array());
    assert!(json.len() <= 256 * 1024);
}

#[test]
fn analytics_fixture_uses_one_exact_millisecond_capture_for_range() {
    let _fixture = fixture();
    let pointer = unsafe { needlbar_analytics_snapshot_json() };
    let json = unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .expect("analytics bridge emits UTF-8")
        .to_owned();
    unsafe { needlbar_free_string(pointer) };
    let value: serde_json::Value = serde_json::from_str(&json).expect("analytics JSON");
    assert_eq!(value["generatedAt"], "2026-09-01T12:00:00.000Z");
    assert_eq!(value["data"]["analysisRange"]["end"], value["generatedAt"]);
    assert_eq!(
        value["data"]["analysisRange"]["start"],
        "2026-08-02T12:00:00.000Z"
    );
    assert!(value["data"]["repositories"].is_array());
    assert!(value["data"]["unattributed"].is_object());
    assert!(value["data"]["coverage"].is_object());
}

#[test]
fn maximum_row_payload_uses_record_limit_partial_success_within_the_abi_cap() {
    let _fixture = fixture();
    let generated_at = chrono::DateTime::parse_from_rfc3339("2026-09-01T12:00:00.000Z")
        .expect("fixed analytics time")
        .with_timezone(&chrono::Utc);
    assert!(test_runtime::install_analytics_payload_fixture(
        generated_at,
        maximum_row_payload(generated_at),
    ));

    let pointer = unsafe { needlbar_analytics_snapshot_json() };
    let json = unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .expect("analytics bridge emits UTF-8")
        .to_owned();
    unsafe { needlbar_free_string(pointer) };

    assert!(json.len() <= 256 * 1024);
    let value: serde_json::Value = serde_json::from_str(&json).expect("analytics JSON");
    assert_eq!(value["ok"], true);
    assert_eq!(
        value["data"]["repositories"].as_array().map(Vec::len),
        Some(64)
    );
    assert!(value["data"]["repositories"]
        .as_array()
        .expect("repositories")
        .iter()
        .any(|repository| repository["commits"].as_array().map_or(0, Vec::len) < 200));
    assert!(value["data"]["coverage"]["reasons"]["recordLimitReached"]
        .as_u64()
        .is_some_and(|count| count > 0));
    assert!(value["data"]["errors"]
        .as_array()
        .expect("errors")
        .iter()
        .any(|error| { error["scope"] == "analytics" && error["code"] == "recordLimitReached" }));
}

fn maximum_row_payload(generated_at: chrono::DateTime<chrono::Utc>) -> AnalyticsPayload {
    let usage = UsageAggregate {
        input_tokens: "1".into(),
        output_tokens: "0".into(),
        cache_read_tokens: "0".into(),
        cache_write_tokens: "0".into(),
        reasoning_tokens: "0".into(),
        total_tokens: "1".into(),
        estimated_cost_usd: "1".into(),
    };
    let repositories = (0..64)
        .map(|repository| RepositoryAnalytics {
            repository_id: format!("r{repository:08x}"),
            label: format!("repository-{repository:02}"),
            state: RepositoryState::Available,
            usage: usage.clone(),
            observed_active_time_seconds: "0".into(),
            provider_models: Vec::new(),
            commits: (0..200)
                .map(|commit| CommitAnalytics {
                    commit_id: format!("{repository:04x}{commit:08x}"),
                    committed_at: generated_at,
                    correlated_usage: usage.clone(),
                    pull_request_number: None,
                    coverage: "correlated".into(),
                })
                .collect(),
            coverage: RepositoryCoverage::default(),
        })
        .collect();
    AnalyticsPayload {
        analysis_range: AnalysisRange {
            start: generated_at - chrono::Duration::days(30),
            end: generated_at,
        },
        repositories,
        unattributed: AttributionBucket::default(),
        coverage: AnalyticsCoverage::default(),
        errors: Vec::new(),
    }
}

#[test]
fn analytics_envelope_has_only_the_canonical_top_level_fields() {
    let _fixture = fixture();
    let pointer = unsafe { needlbar_analytics_snapshot_json() };
    let json = unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .expect("analytics bridge emits UTF-8")
        .to_owned();
    unsafe { needlbar_free_string(pointer) };
    let value: serde_json::Value = serde_json::from_str(&json).expect("analytics JSON");
    let keys = value
        .as_object()
        .expect("analytics envelope object")
        .keys()
        .cloned()
        .collect::<Vec<_>>();
    assert_eq!(
        keys,
        vec![
            "data".to_owned(),
            "errors".to_owned(),
            "generatedAt".to_owned(),
            "ok".to_owned(),
            "schemaVersion".to_owned(),
        ]
    );
}

#[test]
fn analytics_output_has_no_raw_privacy_fields() {
    let _fixture = fixture();
    let pointer = unsafe { needlbar_analytics_snapshot_json() };
    assert!(!pointer.is_null());
    let json = unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .expect("analytics bridge emits UTF-8")
        .to_owned();
    unsafe { needlbar_free_string(pointer) };

    for canary in [
        "/private/repo",
        "raw-remote.example",
        "feature/canary",
        "author@example.com",
        "message-canary",
        "session-canary",
        "prompt-canary",
        "response-canary",
        "source-canary",
        "credential-canary",
        "account-canary",
        "stdout-canary",
        "stderr-canary",
    ] {
        assert!(
            !json.contains(canary),
            "privacy canary crossed bridge: {canary}"
        );
    }
}

#[test]
fn analytics_panic_fixture_returns_small_fatal_analytics_envelope() {
    let _fixture = fixture();
    assert!(test_runtime::install_analytics_panic_fixture());
    let pointer = unsafe { needlbar_analytics_snapshot_json() };
    let json = unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .expect("analytics fallback emits UTF-8")
        .to_owned();
    unsafe { needlbar_free_string(pointer) };
    assert!(json.len() < 1024);
    let value: serde_json::Value = serde_json::from_str(&json).expect("analytics fallback JSON");
    assert_eq!(value["schemaVersion"], "needlbar.analytics.v1");
    assert_eq!(value["ok"], false);
    assert!(value["data"].is_null());
    assert_eq!(value["errors"][0]["scope"], "analytics");
    assert_eq!(value["errors"][0]["code"], "internalError");
}

#[test]
fn analytics_fatal_fixture_is_fixed_and_does_not_enter_collection() {
    let _fixture = fixture();
    assert!(test_runtime::install_analytics_fatal_fixture(
        chrono::DateTime::parse_from_rfc3339("2026-09-01T12:00:00.000Z")
            .expect("fixed analytics time")
            .with_timezone(&chrono::Utc),
        "usage",
        "usageReportUnavailable",
    ));
    let pointer = unsafe { needlbar_analytics_snapshot_json() };
    let json = unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .expect("analytics fallback emits UTF-8")
        .to_owned();
    unsafe { needlbar_free_string(pointer) };
    let value: serde_json::Value = serde_json::from_str(&json).expect("analytics fallback JSON");
    assert_eq!(value["schemaVersion"], "needlbar.analytics.v1");
    assert_eq!(value["generatedAt"], "2026-09-01T12:00:00.000Z");
    assert_eq!(value["ok"], false);
    assert!(value["data"].is_null());
    assert_eq!(value["errors"][0]["scope"], "usage");
    assert_eq!(value["errors"][0]["code"], "usageReportUnavailable");
}

#[test]
fn analytics_interior_nul_uses_small_fatal_analytics_envelope() {
    let pointer = test_analytics_interior_nul_pointer();
    let json = unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .expect("analytics fallback emits UTF-8")
        .to_owned();
    unsafe { needlbar_free_string(pointer) };
    assert!(json.len() < 1024);
    let value: serde_json::Value = serde_json::from_str(&json).expect("analytics fallback JSON");
    assert_eq!(value["schemaVersion"], "needlbar.analytics.v1");
    assert_eq!(value["ok"], false);
    assert!(value["data"].is_null());
    assert_eq!(value["errors"][0]["scope"], "analytics");
    assert_eq!(value["errors"][0]["code"], "internalError");
}

#[test]
fn analytics_pointer_can_be_repeatedly_allocated_and_freed() {
    let _fixture = fixture();
    test_runtime::reset_ffi_allocation_counts();
    for _ in 0..8 {
        let pointer = unsafe { needlbar_analytics_snapshot_json() };
        assert!(!pointer.is_null());
        unsafe { needlbar_free_string(pointer) };
    }
    let counts = test_runtime::ffi_allocation_counts();
    assert_eq!(counts.0, 8);
    assert_eq!(counts.1, 8);
}
