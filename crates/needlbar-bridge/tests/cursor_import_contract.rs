use std::ffi::{CStr, CString};

fn response_text(pointer: *const std::os::raw::c_char) -> String {
    assert!(!pointer.is_null());
    let text = unsafe { CStr::from_ptr(pointer) }
        .to_string_lossy()
        .into_owned();
    unsafe { needlbar_bridge::needlbar_free_string(pointer) };
    text
}

#[test]
fn cursor_import_rejects_null_and_invalid_tokens_without_echoing_them() {
    let null_response = response_text(unsafe {
        needlbar_bridge::needlbar_cursor_import_session_json(std::ptr::null())
    });
    let invalid_token = CString::new("cursor secret token").unwrap();
    let invalid_response = response_text(unsafe {
        needlbar_bridge::needlbar_cursor_import_session_json(invalid_token.as_ptr())
    });
    let invalid_utf8 = CString::from_vec_with_nul(vec![0xff, 0]).unwrap();
    let invalid_utf8_response = response_text(unsafe {
        needlbar_bridge::needlbar_cursor_import_session_json(invalid_utf8.as_ptr())
    });

    for response in [null_response, invalid_response, invalid_utf8_response] {
        let value: serde_json::Value = serde_json::from_str(&response).unwrap();
        assert_eq!(value["schemaVersion"], "needlbar.v1");
        assert_eq!(value["ok"], false);
        assert_eq!(value["errors"][0]["code"], "requiresAuthentication");
        assert!(!response.contains("cursor secret token"));
    }
}
