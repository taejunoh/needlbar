use std::{
    ffi::CStr,
    fs,
    os::raw::c_char,
    path::{Path, PathBuf},
};

use needlbar_bridge::{
    needlbar_diagnostics_json, needlbar_free_string, needlbar_quota_snapshot_json,
    needlbar_usage_snapshot_json, test_runtime,
};
use tempfile::TempDir;

const CLAUDE_CANARY: &str = "CLAUDE-CANARY-SECRET";
const CODEX_CANARY: &str = "CODEX-CANARY-SECRET";
const CURSOR_CANARY: &str = "CURSOR-CANARY-SECRET";
const RAW_PATH: &str = "/Users/alice/.config/needlbar/raw-token.json";
const EMAIL: &str = "alice@example.com";

#[test]
fn provider_credential_canaries_never_cross_real_bridge_envelopes() {
    let home = fixture_home();
    let claude_failure = format!("credential {CLAUDE_CANARY} at {RAW_PATH} for {EMAIL}");
    let codex_failure = format!("credential {CODEX_CANARY} at {RAW_PATH} for {EMAIL}");
    let cursor_failure = format!("cookie {CURSOR_CANARY} at {RAW_PATH} for {EMAIL}");
    assert!(test_runtime::install_redaction_fixture(
        home.path().to_path_buf(),
        claude_failure,
        codex_failure,
        cursor_failure,
    ));
    let _clear = RuntimeCleanup;

    // Each call crosses the actual exported ABI, reads Rust-owned bytes, and
    // releases the allocation through the actual exported free function.
    let usage = ffi_json(needlbar_usage_snapshot_json);
    let quota = ffi_json(needlbar_quota_snapshot_json);
    let diagnostics = ffi_json(needlbar_diagnostics_json);
    let error = test_runtime::error_envelope_json(format!(
        "response {CLAUDE_CANARY} {CODEX_CANARY} {CURSOR_CANARY} {RAW_PATH} {EMAIL}"
    ));

    assert_safe_output(&usage);
    assert_safe_output(&quota);
    assert_safe_output(&diagnostics);
    assert_safe_output(&error);

    let usage_value: serde_json::Value = serde_json::from_str(&usage).expect("usage JSON");
    assert_eq!(usage_value["schemaVersion"], "needlbar.v1");
    assert_eq!(
        usage_value["data"]["providers"].as_array().map(Vec::len),
        Some(3)
    );
    assert_error_shape(&usage_value["errors"], "providerUnavailable");

    let quota_value: serde_json::Value = serde_json::from_str(&quota).expect("quota JSON");
    assert_eq!(quota_value["schemaVersion"], "needlbar.v1");
    assert_eq!(
        quota_value["data"]["providers"].as_array().map(Vec::len),
        Some(0)
    );
    assert_error_shape(&quota_value["errors"], "requiresAuthentication");
    assert_eq!(quota_value["errors"][1]["code"], "networkUnavailable");
    assert_eq!(quota_value["errors"][2]["provider"], "cursor");
    assert_eq!(quota_value["errors"][2]["action"], "connectCursor");

    let diagnostics_value: serde_json::Value =
        serde_json::from_str(&diagnostics).expect("diagnostics JSON");
    assert_eq!(diagnostics_value["schemaVersion"], "needlbar.v1");
    assert_eq!(
        diagnostics_value["data"]["providers"]
            .as_array()
            .map(Vec::len),
        Some(3)
    );
    assert_eq!(
        diagnostics_value["data"]["providers"][0]["quotaErrorCode"],
        "requiresAuthentication"
    );
    assert!(diagnostics_value["data"]["providers"]
        .as_array()
        .expect("diagnostic providers")
        .iter()
        .all(|provider| provider.get("message").is_none()));

    let error_value: serde_json::Value = serde_json::from_str(&error).expect("error JSON");
    assert_eq!(error_value["schemaVersion"], "needlbar.v1");
    assert_error_shape(&error_value["errors"], "providerUnavailable");
}

fn ffi_json(call: unsafe extern "C" fn() -> *const c_char) -> String {
    let pointer = unsafe { call() };
    assert!(
        !pointer.is_null(),
        "bridge returned a non-null JSON pointer"
    );
    let json = unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .expect("bridge emits UTF-8")
        .to_owned();
    unsafe { needlbar_free_string(pointer) };
    json
}

fn assert_safe_output(json: &str) {
    for forbidden in [CLAUDE_CANARY, CODEX_CANARY, CURSOR_CANARY, RAW_PATH, EMAIL] {
        assert!(
            !json.contains(forbidden),
            "unsafe upstream value crossed the bridge boundary: {forbidden}"
        );
    }
}

fn assert_error_shape(errors: &serde_json::Value, code: &str) {
    let error = errors
        .as_array()
        .expect("errors array")
        .first()
        .expect("at least one error");
    assert_eq!(error["provider"], "claude");
    assert_eq!(error["code"], code);
    assert!(error["message"]
        .as_str()
        .is_some_and(|message| !message.is_empty()));
    assert!(error.get("action").is_none());
}

struct RuntimeCleanup;

impl Drop for RuntimeCleanup {
    fn drop(&mut self) {
        test_runtime::needlbar_test_clear_runtime();
    }
}

fn fixture_home() -> TempDir {
    let home = TempDir::new().expect("fixture home");
    let fixtures = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../Fixtures/usage");
    copy_tree(&fixtures.join("claude"), home.path());
    copy_tree(&fixtures.join("codex"), home.path());
    let cursor_cache = home.path().join(".config/tokscale/cursor-cache");
    fs::create_dir_all(&cursor_cache).expect("cursor cache directory");
    fs::copy(
        fixtures.join("cursor/usage.csv"),
        cursor_cache.join("usage.csv"),
    )
    .expect("cursor fixture");
    home
}

fn copy_tree(source: &Path, destination: &Path) {
    for entry in fs::read_dir(source).expect("fixture directory") {
        let entry = entry.expect("fixture entry");
        let target: PathBuf = destination.join(entry.file_name());
        if entry.file_type().expect("fixture type").is_dir() {
            fs::create_dir_all(&target).expect("fixture destination directory");
            copy_tree(&entry.path(), &target);
        } else {
            fs::copy(entry.path(), target).expect("fixture copy");
        }
    }
}
