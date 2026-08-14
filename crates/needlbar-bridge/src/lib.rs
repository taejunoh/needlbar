mod envelope;

use std::{
    ffi::CString,
    os::raw::c_char,
    panic::{catch_unwind, UnwindSafe},
};

use envelope::{BridgeError, Envelope};
use serde::Serialize;

fn internal_error_json() -> String {
    serde_json::to_string(&Envelope::<serde_json::Value>::failure(BridgeError {
        provider: None,
        code: "internalError".to_owned(),
        message: "The Needlbar bridge encountered an internal error".to_owned(),
    }))
    .unwrap_or_else(|_| {
        "{\"schemaVersion\":\"needlbar.v1\",\"ok\":false,\"generatedAt\":\"1970-01-01T00:00:00Z\",\"data\":null,\"errors\":[{\"code\":\"internalError\",\"message\":\"The Needlbar bridge encountered an internal error\"}]}".to_owned()
    })
}

fn fallback_pointer() -> *const c_char {
    CString::new(internal_error_json())
        .unwrap_or_default()
        .into_raw()
}

fn ffi_json<T: Serialize + UnwindSafe>(f: impl FnOnce() -> T + UnwindSafe) -> *const c_char {
    match catch_unwind(|| {
        let json = serde_json::to_string(&Envelope::success(f()))
            .unwrap_or_else(|_| internal_error_json());
        CString::new(json).unwrap_or_default().into_raw()
    }) {
        Ok(pointer) => pointer,
        Err(_) => match catch_unwind(fallback_pointer) {
            Ok(pointer) => pointer,
            Err(_) => std::ptr::null(),
        },
    }
}

#[no_mangle]
pub unsafe extern "C" fn needlbar_usage_snapshot_json() -> *const c_char {
    ffi_json(|| serde_json::json!({}))
}

#[no_mangle]
pub unsafe extern "C" fn needlbar_quota_snapshot_json() -> *const c_char {
    ffi_json(|| serde_json::json!({}))
}

#[no_mangle]
pub unsafe extern "C" fn needlbar_diagnostics_json() -> *const c_char {
    ffi_json(|| serde_json::json!({}))
}

#[no_mangle]
pub unsafe extern "C" fn needlbar_free_string(ptr: *const c_char) {
    let _ = catch_unwind(|| {
        if !ptr.is_null() {
            // SAFETY: The C ABI requires callers to pass a non-null pointer returned by
            // this bridge exactly once. The null case is handled above.
            unsafe { drop(CString::from_raw(ptr.cast_mut())) };
        }
    });
}

#[cfg(test)]
mod tests {
    use std::ffi::CStr;

    use super::*;

    #[test]
    fn ffi_json_contains_panics_in_an_error_envelope() {
        let ptr = ffi_json(|| -> serde_json::Value { panic!("boom") });
        let text = unsafe { CStr::from_ptr(ptr) }
            .to_string_lossy()
            .into_owned();
        let value: serde_json::Value = serde_json::from_str(&text).unwrap();

        assert_eq!(value["ok"], false);
        assert_eq!(value["errors"][0]["code"], "internalError");

        unsafe { needlbar_free_string(ptr) };
    }
}
