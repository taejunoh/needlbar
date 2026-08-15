mod envelope;
pub mod quota;
pub mod usage;

use std::{
    ffi::{CStr, CString},
    os::raw::c_char,
    panic::{catch_unwind, UnwindSafe},
    thread,
};

#[cfg(test)]
use std::{
    path::{Path, PathBuf},
    sync::{Arc, Mutex, MutexGuard},
};

use chrono::{SecondsFormat, Utc};
use envelope::{BridgeError, Envelope, SCHEMA_VERSION};
use needlbar_quota::{CursorQuotaProvider, QuotaError, QuotaErrorCode};
use needlbar_source_sync::{CursorSession, CursorSessionStore};
use serde::Serialize;

fn internal_error_json() -> String {
    serde_json::to_string(&Envelope::<serde_json::Value>::failure(BridgeError {
        provider: None,
        code: "internalError".to_owned(),
        message: "The Needlbar bridge encountered an internal error".to_owned(),
        action: None,
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

fn usage_envelope(force_cursor_sync: bool) -> Envelope<usage::UsagePayload> {
    match usage::collect_usage_with_cursor_sync_force(force_cursor_sync) {
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
            action: None,
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
    ffi_envelope(|| usage_envelope(false))
}

/// # Safety
///
/// The returned non-null pointer is Rust-owned and must be passed exactly once
/// to [`needlbar_free_string`]. Callers must not mutate the returned bytes.
#[no_mangle]
pub unsafe extern "C" fn needlbar_forced_usage_snapshot_json() -> *const c_char {
    ffi_envelope(|| usage_envelope(true))
}

/// # Safety
///
/// The returned non-null pointer is Rust-owned and must be passed exactly once
/// to [`needlbar_free_string`]. Callers must not mutate the returned bytes.
#[no_mangle]
pub unsafe extern "C" fn needlbar_quota_snapshot_json() -> *const c_char {
    ffi_envelope(quota_envelope)
}

/// # Safety
///
/// The returned non-null pointer is Rust-owned and must be passed exactly once
/// to [`needlbar_free_string`]. Callers must not mutate the returned bytes.
#[no_mangle]
pub unsafe extern "C" fn needlbar_diagnostics_json() -> *const c_char {
    ffi_json(|| serde_json::json!({}))
}

/// # Safety
///
/// `session_token` must be null or a valid NUL-terminated UTF-8 string. The
/// returned non-null pointer is Rust-owned and must be passed exactly once to
/// [`needlbar_free_string`]. Callers must not mutate the returned bytes.
#[no_mangle]
pub unsafe extern "C" fn needlbar_cursor_import_session_json(
    session_token: *const c_char,
) -> *const c_char {
    ffi_envelope(|| cursor_import_envelope(session_token))
}

/// # Safety
///
/// The returned non-null pointer is Rust-owned and must be passed exactly once
/// to [`needlbar_free_string`]. Callers must not mutate the returned bytes.
#[no_mangle]
pub unsafe extern "C" fn needlbar_cursor_clear_session_json() -> *const c_char {
    ffi_envelope(cursor_disconnect_envelope)
}

/// # Safety
///
/// A non-null pointer must have been returned by this bridge, must not have
/// been mutated, and must be freed exactly once. Null is accepted as a no-op.
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

#[derive(Serialize)]
struct CursorImportPayload {
    connected: bool,
}

#[derive(Serialize)]
struct CursorDisconnectPayload {
    disconnected: bool,
}

fn cursor_import_envelope(session_token: *const c_char) -> Envelope<CursorImportPayload> {
    let token = match unsafe { cursor_session_token_from_ffi(session_token) } {
        Ok(token) => token,
        Err(error) => return Envelope::failure(error),
    };
    let store = match cursor_import_store() {
        Ok(store) => store,
        Err(_) => return Envelope::failure(cursor_connect_error()),
    };
    match import_cursor_session_with_verifier(&token, store, verify_cursor_session_token) {
        Ok(payload) => Envelope::success(payload),
        Err(error) => Envelope::failure(error),
    }
}

fn cursor_disconnect_envelope() -> Envelope<CursorDisconnectPayload> {
    let store = match cursor_import_store() {
        Ok(store) => store,
        Err(_) => return Envelope::failure(cursor_disconnect_error()),
    };
    match store.clear() {
        Ok(()) => Envelope::success(CursorDisconnectPayload { disconnected: true }),
        Err(_) => Envelope::failure(cursor_disconnect_error()),
    }
}

fn cursor_import_store() -> Result<CursorSessionStore, needlbar_source_sync::SourceSyncError> {
    #[cfg(test)]
    if let Some(store) = TEST_CURSOR_IMPORT_RUNTIME
        .lock()
        .expect("test Cursor import runtime lock")
        .as_ref()
        .map(|runtime| CursorSessionStore::in_home(&runtime.home))
    {
        return Ok(store);
    }
    CursorSessionStore::new()
}

/// The C caller must provide either null or a valid NUL-terminated UTF-8
/// pointer. Rust can safely reject null and invalid UTF-8, but cannot make an
/// arbitrary non-null invalid address safe to dereference.
unsafe fn cursor_session_token_from_ffi(
    session_token: *const c_char,
) -> Result<String, BridgeError> {
    if session_token.is_null() {
        return Err(cursor_connect_error());
    }
    let token = unsafe { CStr::from_ptr(session_token) }
        .to_str()
        .map_err(|_| cursor_connect_error())?;
    if token.is_empty()
        || token
            .chars()
            .any(|character| character.is_whitespace() || character.is_control())
    {
        return Err(cursor_connect_error());
    }
    Ok(token.to_owned())
}

fn import_cursor_session_with_verifier(
    session_token: &str,
    store: CursorSessionStore,
    verifier: impl FnOnce(&str) -> Result<(), BridgeError>,
) -> Result<CursorImportPayload, BridgeError> {
    let session = CursorSession::new(session_token).map_err(|_| cursor_connect_error())?;
    verifier(session.session_token())?;
    store.save(&session).map_err(|_| cursor_connect_error())?;
    Ok(CursorImportPayload { connected: true })
}

fn verify_cursor_session_token(session_token: &str) -> Result<(), BridgeError> {
    #[cfg(test)]
    if let Some(verifier) = TEST_CURSOR_IMPORT_RUNTIME
        .lock()
        .expect("test Cursor import runtime lock")
        .as_ref()
        .map(|runtime| Arc::clone(&runtime.verifier))
    {
        return verifier(session_token);
    }

    let session_token = session_token.to_owned();
    let verification = thread::Builder::new()
        .name("needlbar-cursor-verify".to_owned())
        .spawn(move || {
            let runtime = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .map_err(|_| cursor_connect_error())?;
            runtime
                .block_on(CursorQuotaProvider::new().verify_session_token(&session_token))
                .map_err(bridge_error_from_quota)
        })
        .map_err(|_| cursor_connect_error())?;
    verification.join().map_err(|_| cursor_connect_error())?
}

fn quota_envelope() -> Envelope<quota::QuotaPayload> {
    match collect_quota_on_bridge_thread() {
        Ok(collection) => quota::envelope_from_collection(collection),
        Err(error) => Envelope::failure(error),
    }
}

/// A C caller may invoke this bridge while a Tokio runtime is already active
/// in the embedding process. A dedicated thread prevents nested-runtime
/// panics while keeping the owned runtime scoped to this bridge refresh.
fn collect_quota_on_bridge_thread() -> Result<quota::QuotaCollection, BridgeError> {
    let worker = thread::Builder::new()
        .name("needlbar-quota-collect".to_owned())
        .spawn(|| {
            let runtime = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .map_err(|_| bridge_internal_error())?;
            Ok(runtime.block_on(quota::collect_quota()))
        })
        .map_err(|_| bridge_internal_error())?;
    worker.join().map_err(|_| bridge_internal_error())?
}

fn bridge_internal_error() -> BridgeError {
    BridgeError {
        provider: None,
        code: "internalError".to_owned(),
        message: "The Needlbar bridge encountered an internal error".to_owned(),
        action: None,
    }
}

fn bridge_error_from_quota(error: QuotaError) -> BridgeError {
    let code = match error.code {
        QuotaErrorCode::NotInstalled => "notInstalled",
        QuotaErrorCode::RequiresAuthentication => "requiresAuthentication",
        QuotaErrorCode::AuthenticationExpired => "authenticationExpired",
        QuotaErrorCode::RateLimited => "rateLimited",
        QuotaErrorCode::NetworkUnavailable => "networkUnavailable",
        QuotaErrorCode::ServiceUnavailable | QuotaErrorCode::ProviderUnavailable => {
            "providerUnavailable"
        }
        QuotaErrorCode::SchemaChanged => "schemaChanged",
    };
    BridgeError {
        provider: Some("cursor".to_owned()),
        code: code.to_owned(),
        message: error.message.to_owned(),
        action: error.action.map(|action| match action {
            needlbar_quota::QuotaAction::ConnectCursor => "connectCursor".to_owned(),
        }),
    }
}

fn cursor_connect_error() -> BridgeError {
    BridgeError {
        provider: Some("cursor".to_owned()),
        code: "requiresAuthentication".to_owned(),
        message: "Cursor authentication was not available.".to_owned(),
        action: Some("connectCursor".to_owned()),
    }
}

fn cursor_disconnect_error() -> BridgeError {
    BridgeError {
        provider: Some("cursor".to_owned()),
        code: "providerUnavailable".to_owned(),
        message: "Cursor session could not be cleared.".to_owned(),
        action: None,
    }
}

#[cfg(test)]
type TestCursorImportVerifier = Arc<dyn Fn(&str) -> Result<(), BridgeError> + Send + Sync>;

#[cfg(test)]
struct TestCursorImportRuntime {
    home: PathBuf,
    verifier: TestCursorImportVerifier,
}

#[cfg(test)]
static TEST_CURSOR_IMPORT_RUNTIME: Mutex<Option<TestCursorImportRuntime>> = Mutex::new(None);
#[cfg(test)]
static TEST_CURSOR_IMPORT_SERIAL: Mutex<()> = Mutex::new(());

#[cfg(test)]
struct TestCursorImportRuntimeGuard {
    _serial: MutexGuard<'static, ()>,
    captured_logs: Arc<Mutex<Vec<String>>>,
}

#[cfg(test)]
impl TestCursorImportRuntimeGuard {
    fn install(
        home: &Path,
        verifier: impl Fn(&str) -> Result<(), BridgeError> + Send + Sync + 'static,
    ) -> Self {
        let serial = TEST_CURSOR_IMPORT_SERIAL
            .lock()
            .expect("test Cursor import serial lock");
        let captured_logs = Arc::new(Mutex::new(Vec::new()));
        *TEST_CURSOR_IMPORT_RUNTIME
            .lock()
            .expect("test Cursor import runtime lock") = Some(TestCursorImportRuntime {
            home: home.to_path_buf(),
            verifier: Arc::new(verifier),
        });
        Self {
            _serial: serial,
            captured_logs,
        }
    }

    fn captured_logs(&self) -> Vec<String> {
        self.captured_logs
            .lock()
            .expect("test Cursor import log lock")
            .clone()
    }
}

#[cfg(test)]
impl Drop for TestCursorImportRuntimeGuard {
    fn drop(&mut self) {
        *TEST_CURSOR_IMPORT_RUNTIME
            .lock()
            .expect("test Cursor import runtime lock") = None;
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
    fn exported_cursor_import_verifies_and_redacts_the_successful_session_canary() {
        let home = tempfile::TempDir::new().unwrap();
        let token = "cursor-secret-test-token";
        let runtime = TestCursorImportRuntimeGuard::install(home.path(), |_| Ok(()));
        let input = CString::new(token).unwrap();
        let pointer = unsafe { needlbar_cursor_import_session_json(input.as_ptr()) };
        let json = unsafe { CStr::from_ptr(pointer) }
            .to_string_lossy()
            .into_owned();
        unsafe { needlbar_free_string(pointer) };
        let value: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(value["data"], serde_json::json!({ "connected": true }));
        assert_eq!(value["errors"], serde_json::json!([]));
        assert!(!json.contains(token));
        assert!(!format!("{value:?}").contains(token));
        assert!(runtime.captured_logs().is_empty());
        assert_eq!(
            CursorSessionStore::in_home(home.path())
                .load()
                .unwrap()
                .session_token(),
            token
        );
    }

    #[test]
    fn exported_cursor_import_does_not_persist_a_session_when_verification_fails() {
        let home = tempfile::TempDir::new().unwrap();
        let token = "cursor-secret-test-token";
        let runtime =
            TestCursorImportRuntimeGuard::install(home.path(), |_| Err(cursor_connect_error()));
        let input = CString::new(token).unwrap();
        let pointer = unsafe { needlbar_cursor_import_session_json(input.as_ptr()) };
        let json = unsafe { CStr::from_ptr(pointer) }
            .to_string_lossy()
            .into_owned();
        unsafe { needlbar_free_string(pointer) };
        let value: serde_json::Value = serde_json::from_str(&json).unwrap();

        assert_eq!(value["errors"][0]["code"], "requiresAuthentication");
        assert!(!json.contains(token));
        assert!(!format!("{value:?}").contains(token));
        assert!(runtime.captured_logs().is_empty());
        assert!(!home
            .path()
            .join("Library/Application Support/Needlbar/cursor-session.json")
            .exists());
    }

    #[test]
    fn exported_cursor_disconnect_is_idempotent_and_releases_its_response() {
        let home = tempfile::TempDir::new().unwrap();
        let _runtime = TestCursorImportRuntimeGuard::install(home.path(), |_| Ok(()));
        let store = CursorSessionStore::in_home(home.path());
        store
            .save(&CursorSession::new("cursor-secret-test-token").unwrap())
            .unwrap();

        for _ in 0..2 {
            let pointer = unsafe { needlbar_cursor_clear_session_json() };
            assert!(!pointer.is_null());
            let json = unsafe { CStr::from_ptr(pointer) }
                .to_string_lossy()
                .into_owned();
            unsafe { needlbar_free_string(pointer) };
            let value: serde_json::Value = serde_json::from_str(&json).unwrap();
            assert_eq!(value["schemaVersion"], "needlbar.v1");
            assert_eq!(value["ok"], true);
            assert_eq!(value["data"], serde_json::json!({ "disconnected": true }));
            assert!(!json.contains("cursor-secret-test-token"));
        }

        assert!(matches!(
            store.load(),
            Err(needlbar_source_sync::SourceSyncError::MissingSession)
        ));
    }
}
