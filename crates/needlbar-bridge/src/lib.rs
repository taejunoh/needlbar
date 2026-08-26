pub mod cursor_credential_cleanup;
pub mod diagnostics;
mod envelope;
pub mod quota;
#[cfg(feature = "bridge-test-runtime")]
#[doc(hidden)]
pub mod test_runtime;
pub mod usage;

use std::{
    ffi::CString,
    future::Future,
    os::raw::c_char,
    panic::{catch_unwind, UnwindSafe},
    pin::Pin,
    thread,
};

#[cfg(feature = "bridge-test-runtime")]
use std::sync::LazyLock;
#[cfg(feature = "bridge-test-runtime")]
use std::sync::Mutex;

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
    ffi_string_pointer(internal_error_json())
}

fn ffi_string_pointer(json: String) -> *const c_char {
    let pointer = CString::new(json).unwrap_or_default().into_raw();
    #[cfg(feature = "bridge-test-runtime")]
    {
        FFI_ALLOCATION_COUNTS
            .lock()
            .expect("ffi allocation counts")
            .0 += 1;
    }
    pointer
}

fn ffi_envelope<T: Serialize + UnwindSafe>(
    f: impl FnOnce() -> Envelope<T> + UnwindSafe,
) -> *const c_char {
    match catch_unwind(|| {
        let json = serde_json::to_string(&f()).unwrap_or_else(|_| internal_error_json());
        ffi_string_pointer(json)
    }) {
        Ok(pointer) => pointer,
        Err(_) => match catch_unwind(fallback_pointer) {
            Ok(pointer) => pointer,
            Err(_) => std::ptr::null(),
        },
    }
}

#[cfg(test)]
fn ffi_json<T: Serialize + UnwindSafe>(f: impl FnOnce() -> T + UnwindSafe) -> *const c_char {
    ffi_envelope(|| Envelope::success(f()))
}

fn usage_envelope() -> Envelope<usage::UsagePayload> {
    match usage::collect_usage() {
        Ok(providers) => usage_envelope_from_providers(providers),
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

/// # Safety
///
/// The returned non-null pointer is Rust-owned and must be passed exactly once
/// to [`needlbar_free_string`]. Callers must not mutate the returned bytes.
#[no_mangle]
pub unsafe extern "C" fn needlbar_usage_snapshot_json() -> *const c_char {
    cursor_credential_cleanup::schedule_obsolete_cursor_session_cleanup();
    ffi_envelope(|| {
        let envelope = ffi_usage_envelope();
        diagnostics::record_usage(&envelope);
        envelope
    })
}

/// # Safety
///
/// The returned non-null pointer is Rust-owned and must be passed exactly once
/// to [`needlbar_free_string`]. Callers must not mutate the returned bytes.
#[no_mangle]
pub unsafe extern "C" fn needlbar_quota_snapshot_json() -> *const c_char {
    cursor_credential_cleanup::schedule_obsolete_cursor_session_cleanup();
    ffi_envelope(|| {
        let envelope = ffi_quota_envelope();
        diagnostics::record_quota(&envelope);
        envelope
    })
}

/// # Safety
///
/// The returned non-null pointer is Rust-owned and must be passed exactly once
/// to [`needlbar_free_string`]. Callers must not mutate the returned bytes.
#[no_mangle]
pub unsafe extern "C" fn needlbar_claude_user_initiated_quota_snapshot_json() -> *const c_char {
    cursor_credential_cleanup::schedule_obsolete_cursor_session_cleanup();
    ffi_envelope(|| {
        let envelope = ffi_claude_user_initiated_quota_envelope();
        diagnostics::record_partial_quota(&envelope);
        envelope
    })
}

/// # Safety
///
/// The returned non-null pointer is Rust-owned and must be passed exactly once
/// to [`needlbar_free_string`]. Callers must not mutate the returned bytes.
#[no_mangle]
pub unsafe extern "C" fn needlbar_codex_quota_snapshot_json() -> *const c_char {
    cursor_credential_cleanup::schedule_obsolete_cursor_session_cleanup();
    ffi_envelope(|| {
        let envelope = ffi_codex_quota_envelope();
        diagnostics::record_partial_quota(&envelope);
        envelope
    })
}

fn ffi_usage_envelope() -> Envelope<usage::UsagePayload> {
    #[cfg(feature = "bridge-test-runtime")]
    if let Some(envelope) = test_runtime::usage_envelope() {
        return envelope;
    }
    usage_envelope()
}

fn ffi_quota_envelope() -> Envelope<quota::QuotaPayload> {
    quota_envelope()
}

fn ffi_claude_user_initiated_quota_envelope() -> Envelope<quota::QuotaPayload> {
    claude_user_initiated_quota_envelope()
}

fn ffi_codex_quota_envelope() -> Envelope<quota::QuotaPayload> {
    codex_quota_envelope()
}

/// # Safety
///
/// The returned non-null pointer is Rust-owned and must be passed exactly once
/// to [`needlbar_free_string`]. Callers must not mutate the returned bytes.
#[no_mangle]
pub unsafe extern "C" fn needlbar_diagnostics_json() -> *const c_char {
    cursor_credential_cleanup::schedule_obsolete_cursor_session_cleanup();
    ffi_envelope(|| Envelope::success(diagnostics::DiagnosticsSnapshot::from_recorded_outcomes()))
}

/// # Safety
///
/// A non-null pointer must have been returned by this bridge, must not have
/// been mutated, and must be freed exactly once. Null is accepted as a no-op.
#[no_mangle]
pub unsafe extern "C" fn needlbar_free_string(ptr: *const c_char) {
    let _ = catch_unwind(|| {
        if !ptr.is_null() {
            #[cfg(feature = "bridge-test-runtime")]
            {
                FFI_ALLOCATION_COUNTS
                    .lock()
                    .expect("ffi allocation counts")
                    .1 += 1;
            }
            // SAFETY: The C ABI requires callers to pass a non-null pointer returned by
            // this bridge exactly once. The null case is handled above.
            unsafe { drop(CString::from_raw(ptr.cast_mut())) };
        }
    });
}

#[cfg(feature = "bridge-test-runtime")]
static FFI_ALLOCATION_COUNTS: LazyLock<Mutex<(usize, usize, usize)>> =
    LazyLock::new(|| Mutex::new((0, 0, 0)));

#[cfg(feature = "bridge-test-runtime")]
pub(crate) fn reset_ffi_allocation_counts() {
    *FFI_ALLOCATION_COUNTS.lock().expect("ffi allocation counts") = (0, 0, 0);
}

#[cfg(feature = "bridge-test-runtime")]
pub(crate) fn ffi_allocation_counts() -> (usize, usize, usize) {
    *FFI_ALLOCATION_COUNTS.lock().expect("ffi allocation counts")
}

fn quota_envelope() -> Envelope<quota::QuotaPayload> {
    match collect_quota_on_bridge_thread(|| Box::pin(quota::collect_quota())) {
        Ok(collection) => quota::envelope_from_collection(collection),
        Err(error) => Envelope::failure(error),
    }
}

fn claude_user_initiated_quota_envelope() -> Envelope<quota::QuotaPayload> {
    match collect_quota_on_bridge_thread(|| Box::pin(quota::collect_claude_user_initiated())) {
        Ok(collection) => quota::envelope_from_collection(collection),
        Err(error) => Envelope::failure(error),
    }
}

fn codex_quota_envelope() -> Envelope<quota::QuotaPayload> {
    match collect_quota_on_bridge_thread(|| Box::pin(quota::collect_codex_only())) {
        Ok(collection) => quota::envelope_from_collection(collection),
        Err(error) => Envelope::failure(error),
    }
}

/// A C caller may invoke this bridge while a Tokio runtime is already active
/// in the embedding process. A dedicated thread prevents nested-runtime
/// panics while keeping the owned runtime scoped to this bridge refresh.
fn collect_quota_on_bridge_thread(
    collect: impl FnOnce() -> Pin<Box<dyn Future<Output = quota::QuotaCollection> + Send>>
        + Send
        + 'static,
) -> Result<quota::QuotaCollection, BridgeError> {
    let worker = thread::Builder::new()
        .name("needlbar-quota-collect".to_owned())
        .spawn(|| {
            let runtime = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .map_err(|_| bridge_internal_error())?;
            Ok(runtime.block_on(collect()))
        })
        .map_err(|_| bridge_internal_error())?;
    worker.join().map_err(|_| bridge_internal_error())?
}

fn bridge_internal_error() -> BridgeError {
    BridgeError {
        provider: None,
        code: "internalError".to_owned(),
        message: "The Needlbar bridge encountered an internal error".to_owned(),
    }
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
            last_7_days_daily: Vec::new(),
            last_30_days: usage::UsagePeriod::default(),
        }]);

        assert!(envelope.ok);
        assert_eq!(envelope.data.expect("partial data").providers.len(), 1);
        assert_eq!(envelope.errors.len(), 2);
        assert_eq!(envelope.errors[0].provider.as_deref(), Some("codex"));
        assert_eq!(envelope.errors[0].code, "noUsageData");
    }

    #[test]
    fn diagnostics_envelope_maps_bounded_outcomes_without_serializing_raw_errors() {
        let usage = Envelope::success(usage::UsagePayload {
            providers: vec![usage::UsageProviderSnapshot {
                provider: "claude".to_owned(),
                all_time_split: usage::UsagePeriod::default(),
                today: usage::UsagePeriod::default(),
                last_7_days: usage::UsagePeriod::default(),
                last_7_days_daily: Vec::new(),
                last_30_days: usage::UsagePeriod::default(),
            }],
        });
        let quota = Envelope {
            schema_version: SCHEMA_VERSION,
            ok: true,
            generated_at: "2026-08-14T12:00:00Z".to_owned(),
            data: Some(quota::QuotaPayload {
                providers: Vec::new(),
            }),
            errors: vec![
                BridgeError {
                    provider: Some("codex".to_owned()),
                    code: "requiresAuthentication".to_owned(),
                    message: "CODEX-CANARY-SECRET /Users/private/auth.json".to_owned(),
                },
                BridgeError {
                    provider: Some("cursor".to_owned()),
                    code: "networkUnavailable".to_owned(),
                    message: "CURSOR-CANARY-SECRET".to_owned(),
                },
            ],
        };

        diagnostics::record_usage(&usage);
        diagnostics::record_quota(&quota);
        let envelope =
            Envelope::success(diagnostics::DiagnosticsSnapshot::from_recorded_outcomes());
        let json = serde_json::to_string(&envelope).expect("diagnostics JSON");
        let value: serde_json::Value = serde_json::from_str(&json).expect("diagnostics value");
        let providers = &value["data"]["providers"];

        assert_eq!(providers[0]["provider"], "claude");
        assert_eq!(providers[0]["usageStatus"], "available");
        assert!(providers[0]["lastUsageAt"].is_string());
        assert_eq!(providers[1]["provider"], "codex");
        assert_eq!(providers[1]["quotaStatus"], "requiresAuthentication");
        assert_eq!(providers[1]["quotaErrorCode"], "requiresAuthentication");
        assert_eq!(providers[2]["provider"], "cursor");
        assert_eq!(providers[2]["quotaStatus"], "error");
        assert_eq!(providers[2]["quotaErrorCode"], "networkUnavailable");
        assert!(!json.contains("CODEX-CANARY-SECRET"));
        assert!(!json.contains("CURSOR-CANARY-SECRET"));
        assert!(!json.contains("/Users/private/auth.json"));
    }
}
