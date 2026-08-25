use std::{
    ffi::CStr,
    fs,
    os::raw::c_char,
    path::{Path, PathBuf},
};

use needlbar_bridge::{
    needlbar_claude_user_initiated_quota_snapshot_json, needlbar_codex_quota_snapshot_json,
    needlbar_diagnostics_json, needlbar_free_string, needlbar_quota_snapshot_json,
    needlbar_usage_snapshot_json, test_runtime,
};
use needlbar_quota::ProviderId;
use tempfile::TempDir;

const CLAUDE_CANARY: &str = "CLAUDE-CANARY-SECRET";
const CODEX_CANARY: &str = "CODEX-CANARY-SECRET";
const CURSOR_CANARY: &str = "CURSOR-CANARY-SECRET";
const RAW_PATH: &str = "/Users/alice/.config/needlbar/raw-token.json";
const EMAIL: &str = "alice@example.com";

#[test]
fn provider_credential_canaries_never_cross_real_bridge_envelopes() {
    let _serial = test_runtime::serial_guard();
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

#[test]
fn provider_verification_exports_are_isolated_redacted_panic_contained_and_freed() {
    // This catches FFI exports that construct production providers under the
    // fixture hook, fan out to another provider, leak Keychain detail, or let
    // a provider panic escape over C.
    let _serial = test_runtime::serial_guard();
    let canary = "CLAUDE-KEYCHAIN-CANARY";
    let fixture = test_runtime::install_provider_verification_fixture(
        Ok(test_runtime::fixture_snapshot(
            ProviderId::Claude,
            "claude.session",
            20.0,
        )),
        Ok(test_runtime::fixture_snapshot(
            ProviderId::Codex,
            "codex.primary",
            50.0,
        )),
    );
    let _clear = RuntimeCleanup;

    let claude = ffi_json(needlbar_claude_user_initiated_quota_snapshot_json);
    let codex = ffi_json(needlbar_codex_quota_snapshot_json);
    let claude_value: serde_json::Value = serde_json::from_str(&claude).expect("Claude JSON");
    let codex_value: serde_json::Value = serde_json::from_str(&codex).expect("Codex JSON");
    assert_eq!(
        claude_value["data"]["providers"].as_array().map(Vec::len),
        Some(1)
    );
    assert_eq!(claude_value["data"]["providers"][0]["provider"], "claude");
    assert_eq!(
        codex_value["data"]["providers"].as_array().map(Vec::len),
        Some(1)
    );
    assert_eq!(codex_value["data"]["providers"][0]["provider"], "codex");
    assert_eq!(fixture.claude_accesses(), vec!["userInitiatedAllowUI"]);
    assert_eq!(fixture.codex_fetches(), 1);
    assert_eq!(fixture.claude_creations(), 1);
    assert_eq!(fixture.codex_creations(), 1);
    assert_eq!(fixture.cursor_creations(), 0);

    let denied = test_runtime::install_provider_verification_fixture(
        Err(test_runtime::fixture_permission_denied(canary)),
        Ok(test_runtime::fixture_snapshot(
            ProviderId::Codex,
            "codex.primary",
            50.0,
        )),
    );
    let denied_json = ffi_json(needlbar_claude_user_initiated_quota_snapshot_json);
    let diagnostics = ffi_json(needlbar_diagnostics_json);
    let denied_value: serde_json::Value = serde_json::from_str(&denied_json).expect("denied JSON");
    assert_eq!(denied_value["data"]["providers"], serde_json::json!([]));
    assert_eq!(denied_value["errors"][0]["provider"], "claude");
    assert_eq!(denied_value["errors"][0]["code"], "permissionDenied");
    assert_eq!(
        denied_value["errors"][0]["message"],
        "Provider credential access was denied."
    );
    assert!(!denied_json.contains(canary));
    assert!(!diagnostics.contains(canary));
    assert_eq!(denied.claude_accesses(), vec!["userInitiatedAllowUI"]);

    test_runtime::install_provider_verification_panic_fixture();
    for export in [
        needlbar_claude_user_initiated_quota_snapshot_json,
        needlbar_codex_quota_snapshot_json,
    ] {
        let json = ffi_json(export);
        let value: serde_json::Value = serde_json::from_str(&json).expect("panic JSON");
        assert_eq!(value["ok"], false);
        assert_eq!(value["errors"][0]["code"], "internalError");
    }
}

#[test]
fn provider_verification_preserves_unrelated_diagnostics_and_records_permission_denied() {
    // This catches provider-only verification overwriting the most recent
    // diagnostics for omitted providers, or dropping permissionDenied as an
    // unknown diagnostics code.
    let _serial = test_runtime::serial_guard();
    let fixture = test_runtime::install_provider_verification_fixture(
        Ok(test_runtime::fixture_snapshot(
            ProviderId::Claude,
            "claude.session",
            20.0,
        )),
        Ok(test_runtime::fixture_snapshot(
            ProviderId::Codex,
            "codex.primary",
            50.0,
        )),
    );
    let _clear = RuntimeCleanup;

    let _ = ffi_json(needlbar_quota_snapshot_json);
    let baseline = diagnostics_by_provider(&ffi_json(needlbar_diagnostics_json));
    let _ = ffi_json(needlbar_claude_user_initiated_quota_snapshot_json);
    let after_claude = diagnostics_by_provider(&ffi_json(needlbar_diagnostics_json));
    assert_eq!(after_claude["codex"], baseline["codex"]);
    assert_eq!(after_claude["cursor"], baseline["cursor"]);

    let _ = ffi_json(needlbar_codex_quota_snapshot_json);
    let after_codex = diagnostics_by_provider(&ffi_json(needlbar_diagnostics_json));
    assert_eq!(after_codex["claude"], after_claude["claude"]);
    assert_eq!(after_codex["cursor"], baseline["cursor"]);

    let denied = test_runtime::install_provider_verification_fixture(
        Err(test_runtime::fixture_permission_denied(
            "CLAUDE-KEYCHAIN-CANARY",
        )),
        Ok(test_runtime::fixture_snapshot(
            ProviderId::Codex,
            "codex.primary",
            50.0,
        )),
    );
    let _ = ffi_json(needlbar_claude_user_initiated_quota_snapshot_json);
    let diagnostics = diagnostics_by_provider(&ffi_json(needlbar_diagnostics_json));
    assert_eq!(diagnostics["claude"]["quotaErrorCode"], "permissionDenied");
    assert_eq!(denied.claude_accesses(), vec!["userInitiatedAllowUI"]);
    assert_eq!(fixture.cursor_creations(), 1);
}

#[test]
fn provider_verification_fixture_is_scoped_through_worker_and_tracks_real_ffi_allocation() {
    // This catches a fixture clear racing an already-started exported call,
    // which would otherwise fall through to production Keychain/network, and
    // verifies allocation/release bookkeeping on the bridge's real C string
    // ownership path.
    let scope = test_runtime::provider_verification_scope();
    let fixture = scope.install(
        Ok(test_runtime::fixture_snapshot(
            ProviderId::Claude,
            "claude.session",
            20.0,
        )),
        Ok(test_runtime::fixture_snapshot(
            ProviderId::Codex,
            "codex.primary",
            50.0,
        )),
    );
    test_runtime::reset_ffi_allocation_counts();

    let pointer = unsafe { needlbar_claude_user_initiated_quota_snapshot_json() };
    assert!(!pointer.is_null());
    assert_eq!(test_runtime::ffi_allocation_counts(), (1, 0, 0));
    unsafe { needlbar_free_string(pointer) };
    assert_eq!(test_runtime::ffi_allocation_counts(), (1, 1, 0));
    assert_eq!(fixture.claude_accesses(), vec!["userInitiatedAllowUI"]);

    let worker_fixture = scope.install_blocking_claude_fixture();
    let call = std::thread::spawn(|| ffi_json(needlbar_claude_user_initiated_quota_snapshot_json));
    worker_fixture.wait_until_fetch_started();
    scope.clear();
    worker_fixture.allow_fetch_to_finish();
    let json = call.join().expect("worker export joins");
    let value: serde_json::Value = serde_json::from_str(&json).expect("worker JSON");
    assert_eq!(value["data"]["providers"][0]["provider"], "claude");
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

fn diagnostics_by_provider(json: &str) -> std::collections::BTreeMap<String, serde_json::Value> {
    let value: serde_json::Value = serde_json::from_str(json).expect("diagnostics JSON");
    value["data"]["providers"]
        .as_array()
        .expect("diagnostic providers")
        .iter()
        .map(|provider| {
            (
                provider["provider"]
                    .as_str()
                    .expect("provider name")
                    .to_owned(),
                provider.clone(),
            )
        })
        .collect()
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
