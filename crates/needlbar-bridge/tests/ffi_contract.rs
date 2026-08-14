use std::ffi::CStr;

#[test]
fn diagnostics_returns_v1_envelope_and_can_be_freed() {
    let ptr = unsafe { needlbar_bridge::needlbar_diagnostics_json() };
    assert!(!ptr.is_null());
    let text = unsafe { CStr::from_ptr(ptr) }.to_string_lossy().into_owned();
    let value: serde_json::Value = serde_json::from_str(&text).unwrap();
    assert_eq!(value["schemaVersion"], "needlbar.v1");
    assert_eq!(value["ok"], true);
    unsafe { needlbar_bridge::needlbar_free_string(ptr) };
}

#[test]
fn free_accepts_null() {
    unsafe { needlbar_bridge::needlbar_free_string(std::ptr::null()) };
}
