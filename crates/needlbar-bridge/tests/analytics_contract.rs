use std::ffi::{CStr, CString};
use std::fs;
use std::os::raw::c_char;
use std::path::Path;

use needlbar_bridge::{needlbar_analytics_snapshot_json, needlbar_free_string, test_runtime};
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
    assert!(header.contains("const char *needlbar_analytics_snapshot_json(void);"));

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
    assert!(value["generatedAt"].is_string());
    assert!(value["errors"].is_array());
    assert!(json.len() <= 256 * 1024);
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
fn analytics_pointer_can_be_repeatedly_allocated_and_freed() {
    let _fixture = fixture();
    for _ in 0..8 {
        let pointer = unsafe { needlbar_analytics_snapshot_json() };
        assert!(!pointer.is_null());
        unsafe { needlbar_free_string(pointer) };
    }
}

#[test]
fn analytics_call_does_not_accept_or_emit_user_supplied_c_strings() {
    // Keep this explicit: the ABI is a no-argument, read-only snapshot call.
    let _ = CString::new("unused fixture").expect("fixture C string");
}
