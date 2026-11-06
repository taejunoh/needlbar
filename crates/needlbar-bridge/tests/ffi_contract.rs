use std::ffi::CStr;
use std::{fs, path::Path};

#[test]
fn provider_verification_exports_are_declared_in_the_public_c_header() {
    // This catches a Rust-only export that Swift cannot call through CNeedlbar.
    let header = fs::read_to_string(
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../Sources/CNeedlbar/include/needlbar.h"),
    )
    .expect("public C header");

    assert!(header.contains("needlbar_codex_quota_snapshot_json(void)"));
    assert!(header.contains(
        "const char *needlbar_claude_usage_report_quota_snapshot_json(uint64_t run_id);"
    ));
    assert!(header.contains("void needlbar_claude_usage_report_cancel_through(uint64_t run_id);"));
    let usage_report: unsafe extern "C" fn(u64) -> *const std::os::raw::c_char =
        needlbar_bridge::needlbar_claude_usage_report_quota_snapshot_json;
    let cancel_usage_report: extern "C" fn(u64) =
        needlbar_bridge::needlbar_claude_usage_report_cancel_through;
    let _ = (usage_report, cancel_usage_report);
    assert!(header.contains("const char *needlbar_analytics_snapshot_json(void);"));

    let usage: unsafe extern "C" fn() -> *const std::os::raw::c_char =
        needlbar_bridge::needlbar_usage_snapshot_json;
    let quota: unsafe extern "C" fn() -> *const std::os::raw::c_char =
        needlbar_bridge::needlbar_quota_snapshot_json;
    let codex: unsafe extern "C" fn() -> *const std::os::raw::c_char =
        needlbar_bridge::needlbar_codex_quota_snapshot_json;
    let diagnostics: unsafe extern "C" fn() -> *const std::os::raw::c_char =
        needlbar_bridge::needlbar_diagnostics_json;
    let analytics: unsafe extern "C" fn() -> *const std::os::raw::c_char =
        needlbar_bridge::needlbar_analytics_snapshot_json;
    assert!(!header.contains("needlbar_claude_user_initiated"));
    assert!(!header.contains("needlbar_claude_preflight"));
    let _ = (usage, quota, codex, diagnostics, analytics);
}

#[test]
fn diagnostics_returns_v1_envelope_and_can_be_freed() {
    let ptr = unsafe { needlbar_bridge::needlbar_diagnostics_json() };
    assert!(!ptr.is_null());
    let text = unsafe { CStr::from_ptr(ptr) }
        .to_string_lossy()
        .into_owned();
    let value: serde_json::Value = serde_json::from_str(&text).unwrap();
    assert_eq!(value["schemaVersion"], "needlbar.v1");
    assert_eq!(value["ok"], true);
    unsafe { needlbar_bridge::needlbar_free_string(ptr) };
}

#[test]
fn free_accepts_null() {
    unsafe { needlbar_bridge::needlbar_free_string(std::ptr::null()) };
}
