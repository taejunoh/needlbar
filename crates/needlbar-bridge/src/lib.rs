mod envelope;
pub mod usage;

use std::{
    ffi::CString,
    os::raw::c_char,
    panic::{catch_unwind, UnwindSafe},
};

use chrono::{SecondsFormat, Utc};
use envelope::{BridgeError, Envelope, SCHEMA_VERSION};
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

fn ffi_envelope<T: Serialize + UnwindSafe>(
    f: impl FnOnce() -> Envelope<T> + UnwindSafe,
) -> *const c_char {
    match catch_unwind(|| {
        let json = serde_json::to_string(&f()).unwrap_or_else(|_| internal_error_json());
        CString::new(json).unwrap_or_default().into_raw()
    }) {
        Ok(pointer) => pointer,
        Err(_) => match catch_unwind(fallback_pointer) {
            Ok(pointer) => pointer,
            Err(_) => std::ptr::null(),
        },
    }
}

fn ffi_json<T: Serialize + UnwindSafe>(f: impl FnOnce() -> T + UnwindSafe) -> *const c_char {
    ffi_envelope(|| Envelope::success(f()))
}

fn usage_envelope() -> Envelope<usage::UsagePayload> {
    match usage::collect_usage_with_cursor_sync() {
        Ok(collection) => {
            let mut envelope = usage_envelope_from_providers(collection.providers);
            envelope.errors.extend(collection.warnings);
            envelope
        }
        Err(error) => Envelope::failure(error),
    }
}

fn usage_envelope_from_providers(
    providers: Vec<usage::UsageProviderSnapshot>,
) -> Envelope<usage::UsagePayload> {
    let errors: Vec<BridgeError> = ["claude", "codex", "cursor"]
        .into_iter()
        .filter(|provider| {
            !providers
                .iter()
                .any(|snapshot| snapshot.provider == *provider)
        })
        .map(|provider| BridgeError {
            provider: Some(provider.to_owned()),
            code: "noUsageData".to_owned(),
            message: "No local usage data is available".to_owned(),
        })
        .collect();
    let has_provider_data = !providers.is_empty();
    Envelope {
        schema_version: SCHEMA_VERSION,
        ok: has_provider_data,
        generated_at: Utc::now().to_rfc3339_opts(SecondsFormat::Secs, true),
        data: has_provider_data.then_some(usage::UsagePayload { providers }),
        errors,
    }
}

#[no_mangle]
pub unsafe extern "C" fn needlbar_usage_snapshot_json() -> *const c_char {
    ffi_envelope(usage_envelope)
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

    #[test]
    fn usage_envelope_keeps_available_provider_when_other_has_no_usage_data() {
        let envelope = usage_envelope_from_providers(vec![usage::UsageProviderSnapshot {
            provider: "claude".to_owned(),
            all_time_split: usage::UsagePeriod::default(),
            today: usage::UsagePeriod::default(),
            last_7_days: usage::UsagePeriod::default(),
            last_30_days: usage::UsagePeriod::default(),
        }]);

        assert!(envelope.ok);
        assert_eq!(envelope.data.expect("partial data").providers.len(), 1);
        assert_eq!(envelope.errors.len(), 2);
        assert_eq!(envelope.errors[0].provider.as_deref(), Some("codex"));
        assert_eq!(envelope.errors[0].code, "noUsageData");
    }
}
