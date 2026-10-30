use std::{env, fs, io, path::PathBuf, sync::Arc};

use chrono::{DateTime, TimeZone, Utc};
use reqwest::header::HeaderValue;
use serde::Deserialize;
use zeroize::Zeroizing;

/// Controls whether resolving Claude's provider-owned credential may request
/// Keychain interaction. Background refreshes must always use the no-UI mode.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClaudeCredentialAccess {
    BackgroundNoUI,
    UserInitiatedAllowUI,
}

/// A short-lived OAuth credential. It deliberately has no Debug, Clone, or
/// serialization implementation so token-bearing data cannot cross the quota
/// boundary accidentally.
pub struct ClaudeOAuthSecret {
    access_token: Zeroizing<String>,
    #[allow(dead_code)]
    expires_at: Option<DateTime<Utc>>,
}

impl ClaudeOAuthSecret {
    fn from_parts(access_token: String, expires_at: Option<DateTime<Utc>>) -> Self {
        Self {
            access_token: Zeroizing::new(access_token),
            expires_at,
        }
    }

    pub(crate) fn access_token(&self) -> &str {
        &self.access_token
    }
}

/// Closed, payload-free failures produced while resolving Claude credentials.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClaudeCredentialError {
    NotFound,
    InteractionNotAllowed,
    PermissionDenied,
    Cancelled,
    /// The Keychain lookup did not yield exactly one usable data item: the
    /// match list was empty or held several items, a result had an unexpected
    /// type, or the Keychain rejected the query parameters (errSecParam).
    KeychainAmbiguous,
    KeychainExpired,
    FileExpired,
    FileMalformed,
    FileReadFailed,
    FilePermissionDenied,
    Expired,
    Malformed,
}

pub trait ClaudeCredentialResolver: Send + Sync {
    fn resolve(
        &self,
        access: ClaudeCredentialAccess,
    ) -> Result<ClaudeOAuthSecret, ClaudeCredentialError>;
}

/// Legacy Claude file credentials. This is the production resolver on
/// non-macOS and an injected compatibility resolver for legacy fixtures.
pub struct FileClaudeCredentialResolver {
    config_dir: Option<PathBuf>,
    home_dir: PathBuf,
}

impl FileClaudeCredentialResolver {
    pub fn from_paths(config_dir: Option<PathBuf>, home_dir: PathBuf) -> Self {
        Self {
            config_dir: config_dir.filter(|path| !path.as_os_str().is_empty()),
            home_dir,
        }
    }

    fn credentials_path(&self) -> PathBuf {
        match &self.config_dir {
            Some(config_dir) => config_dir.join(".credentials.json"),
            None => self.home_dir.join(".claude/.credentials.json"),
        }
    }
}

impl ClaudeCredentialResolver for FileClaudeCredentialResolver {
    fn resolve(
        &self,
        _access: ClaudeCredentialAccess,
    ) -> Result<ClaudeOAuthSecret, ClaudeCredentialError> {
        let contents =
            Zeroizing::new(fs::read(self.credentials_path()).map_err(map_file_read_error)?);
        parse_credential_payload(&contents).map_err(|error| match error {
            // Preserve the legacy safe public code while retaining the source
            // distinction needed by diagnostics.
            ClaudeCredentialError::Malformed => ClaudeCredentialError::FileMalformed,
            ClaudeCredentialError::Expired => ClaudeCredentialError::FileExpired,
            other => other,
        })
    }
}

fn map_file_read_error(error: io::Error) -> ClaudeCredentialError {
    match error.kind() {
        io::ErrorKind::NotFound => ClaudeCredentialError::NotFound,
        io::ErrorKind::PermissionDenied => ClaudeCredentialError::FilePermissionDenied,
        _ => ClaudeCredentialError::FileReadFailed,
    }
}

pub(crate) fn production_resolver() -> Arc<dyn ClaudeCredentialResolver> {
    let config_dir = env::var_os("CLAUDE_CONFIG_DIR").map(PathBuf::from);
    let home_dir = env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/nonexistent"));
    let file = Arc::new(FileClaudeCredentialResolver::from_paths(
        config_dir, home_dir,
    ));

    #[cfg(target_os = "macos")]
    {
        Arc::new(MacClaudeCredentialResolver { file })
    }

    #[cfg(not(target_os = "macos"))]
    {
        file
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct CredentialPayload {
    claude_ai_oauth: Option<ClaudeOAuthProjection>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ClaudeOAuthProjection {
    access_token: Option<String>,
    #[serde(default)]
    expires_at: Option<serde_json::Value>,
}

pub(crate) fn parse_credential_payload(
    payload: &[u8],
) -> Result<ClaudeOAuthSecret, ClaudeCredentialError> {
    let credentials: CredentialPayload =
        serde_json::from_slice(payload).map_err(|_| ClaudeCredentialError::Malformed)?;
    let oauth = credentials
        .claude_ai_oauth
        .ok_or(ClaudeCredentialError::Malformed)?;
    let access_token = oauth
        .access_token
        .and_then(normalize_access_token)
        .ok_or(ClaudeCredentialError::Malformed)?;
    let expires_at = match oauth.expires_at.as_ref() {
        Some(value) => parse_expiry(value).ok_or(ClaudeCredentialError::Malformed)?,
        None => None,
    };
    if expires_at.is_some_and(|value| value <= Utc::now()) {
        return Err(ClaudeCredentialError::Expired);
    }

    Ok(ClaudeOAuthSecret::from_parts(access_token, expires_at))
}

fn normalize_access_token(value: String) -> Option<String> {
    if value.is_empty()
        || value.chars().any(char::is_whitespace)
        || HeaderValue::from_str(&value).is_err()
    {
        None
    } else {
        Some(value)
    }
}

fn parse_expiry(value: &serde_json::Value) -> Option<Option<DateTime<Utc>>> {
    let parsed = match value {
        serde_json::Value::String(value) => DateTime::parse_from_rfc3339(value)
            .map(|date| date.with_timezone(&Utc))
            .ok()
            .or_else(|| value.parse::<i64>().ok().and_then(epoch_to_utc)),
        serde_json::Value::Number(number) => number.as_i64().and_then(epoch_to_utc),
        serde_json::Value::Null => return Some(None),
        _ => return None,
    };
    parsed.map(Some)
}

fn epoch_to_utc(timestamp: i64) -> Option<DateTime<Utc>> {
    let seconds = if timestamp.unsigned_abs() > 100_000_000_000 {
        timestamp / 1_000
    } else {
        timestamp
    };
    Utc.timestamp_opt(seconds, 0).single()
}

#[cfg(target_os = "macos")]
struct MacClaudeCredentialResolver {
    file: Arc<FileClaudeCredentialResolver>,
}

#[cfg(target_os = "macos")]
impl ClaudeCredentialResolver for MacClaudeCredentialResolver {
    fn resolve(
        &self,
        access: ClaudeCredentialAccess,
    ) -> Result<ClaudeOAuthSecret, ClaudeCredentialError> {
        match resolve_keychain(access) {
            Err(ClaudeCredentialError::NotFound) => self.file.resolve(access),
            result => result,
        }
    }
}

#[cfg(target_os = "macos")]
const CLAUDE_KEYCHAIN_SERVICE: &str = "Claude Code-credentials";

#[cfg(target_os = "macos")]
fn resolve_keychain(
    access: ClaudeCredentialAccess,
) -> Result<ClaudeOAuthSecret, ClaudeCredentialError> {
    use security_framework_sys::keychain_item::SecItemCopyMatching;

    let login_name = current_login_name();
    resolve_keychain_with(access, login_name.as_deref(), &mut |query, result| unsafe {
        SecItemCopyMatching(query, result)
    })
}

/// The single Security.framework call the Keychain resolver makes, injected so
/// query wiring can be tested against a fake store. Production passes
/// `SecItemCopyMatching`; tests never reach the real Keychain.
#[cfg(target_os = "macos")]
type KeychainCopyMatching<'a> = dyn FnMut(
        core_foundation_sys::dictionary::CFDictionaryRef,
        &mut core_foundation_sys::base::CFTypeRef,
    ) -> core_foundation_sys::base::OSStatus
    + 'a;

#[cfg(target_os = "macos")]
fn resolve_keychain_with(
    access: ClaudeCredentialAccess,
    login_name: Option<&str>,
    copy_matching: &mut KeychainCopyMatching<'_>,
) -> Result<ClaudeOAuthSecret, ClaudeCredentialError> {
    use core_foundation::string::CFString;

    let service = CFString::new(CLAUDE_KEYCHAIN_SERVICE);
    let ui_mode = keychain_ui_mode(access);
    let persistent_ref = select_persistent_ref(login_name, |account| {
        let account = account.map(CFString::new);
        let query = build_keychain_query(
            &service,
            ui_mode,
            KeychainQueryPhase::PersistentReference {
                account: account.as_ref(),
            },
        );
        copy_matching_result(copy_matching, &query).and_then(single_persistent_ref)
    })?;
    let query = build_keychain_query(&service, ui_mode, KeychainQueryPhase::Data(&persistent_ref));
    let payload = copy_matching_result(copy_matching, &query).and_then(single_keychain_data)?;
    parse_credential_payload(&payload).map_err(|error| match error {
        ClaudeCredentialError::Expired => ClaudeCredentialError::KeychainExpired,
        other => other,
    })
}

/// Background access must never display Keychain UI; only the user-initiated
/// path may allow it.
#[cfg(target_os = "macos")]
fn keychain_ui_mode(access: ClaudeCredentialAccess) -> core_foundation_sys::string::CFStringRef {
    unsafe {
        match access {
            ClaudeCredentialAccess::BackgroundNoUI => kSecUseAuthenticationUIFail,
            ClaudeCredentialAccess::UserInitiatedAllowUI => kSecUseAuthenticationUIAllow,
        }
    }
}

/// Runs one query and returns the owned (create-rule) result, mapping a
/// non-success status exactly as the resolver always has.
#[cfg(target_os = "macos")]
fn copy_matching_result(
    copy_matching: &mut KeychainCopyMatching<'_>,
    query: &core_foundation::dictionary::CFMutableDictionary<
        *const std::ffi::c_void,
        *const std::ffi::c_void,
    >,
) -> Result<core_foundation_sys::base::CFTypeRef, ClaudeCredentialError> {
    use core_foundation::base::TCFType;
    use core_foundation_sys::dictionary::CFDictionaryRef;
    use security_framework_sys::base::errSecSuccess;

    let mut result: core_foundation_sys::base::CFTypeRef = std::ptr::null();
    let status = copy_matching(query.as_concrete_TypeRef() as CFDictionaryRef, &mut result);
    if status != errSecSuccess {
        return Err(map_security_error(
            security_framework::base::Error::from_code(status),
        ));
    }
    Ok(result)
}

#[cfg(target_os = "macos")]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum KeychainQueryPhase<'a> {
    /// Reference-only lookup for the exact service, narrowed to one account
    /// when given. It returns persistent references, never item data.
    PersistentReference {
        account: Option<&'a core_foundation::string::CFString>,
    },
    Data(&'a core_foundation::data::CFData),
}

/// Chooses the one Keychain item to read. `lookup` runs the reference-only
/// query for the exact service: `Some(account)` narrows it to that account,
/// `None` is the service-only query. The current login user's item is
/// preferred because Claude Code is expected to save its item under that
/// account. Only a definite NotFound for that account reaches the unchanged
/// service-only single-match rule; several matches, access errors,
/// cancellation and errSecParam are final, so the query is only ever narrowed
/// and never broadened.
#[cfg(target_os = "macos")]
fn select_persistent_ref<R>(
    login_name: Option<&str>,
    mut lookup: impl FnMut(Option<&str>) -> Result<R, ClaudeCredentialError>,
) -> Result<R, ClaudeCredentialError> {
    if let Some(account) = login_name {
        match lookup(Some(account)) {
            Err(ClaudeCredentialError::NotFound) => {}
            decided => return decided,
        }
    }
    lookup(None)
}

/// The current user's short login name from the local user database
/// (`getpwuid_r`), never from the environment or Keychain contents. `None`
/// when the entry cannot be read; the caller then uses only the
/// service-only rule.
#[cfg(target_os = "macos")]
fn current_login_name() -> Option<String> {
    use std::{ffi::CStr, mem::MaybeUninit, ptr};

    const DEFAULT_BUFFER_LEN: usize = 1_024;
    const MAX_BUFFER_LEN: usize = 1 << 20;

    let uid = unsafe { libc::getuid() };
    let suggested = unsafe { libc::sysconf(libc::_SC_GETPW_R_SIZE_MAX) };
    let mut buffer_len = usize::try_from(suggested)
        .ok()
        .filter(|len| *len > 0)
        .unwrap_or(DEFAULT_BUFFER_LEN)
        .min(MAX_BUFFER_LEN);
    loop {
        let mut buffer: Vec<libc::c_char> = vec![0; buffer_len];
        let mut entry = MaybeUninit::<libc::passwd>::uninit();
        let mut found: *mut libc::passwd = ptr::null_mut();
        let status = unsafe {
            libc::getpwuid_r(
                uid,
                entry.as_mut_ptr(),
                buffer.as_mut_ptr(),
                buffer.len(),
                &mut found,
            )
        };
        if status == libc::ERANGE && buffer_len < MAX_BUFFER_LEN {
            buffer_len = buffer_len.saturating_mul(2).min(MAX_BUFFER_LEN);
            continue;
        }
        if status != 0 || found.is_null() {
            return None;
        }
        // `pw_name` points into `buffer`, which outlives this conversion.
        let name = unsafe { (*found).pw_name };
        if name.is_null() {
            return None;
        }
        return login_name_from_c_str(unsafe { CStr::from_ptr(name) });
    }
}

/// Accepts only a non-empty UTF-8 name; anything else means no account
/// narrowing.
#[cfg(target_os = "macos")]
fn login_name_from_c_str(name: &std::ffi::CStr) -> Option<String> {
    let name = name.to_str().ok()?;
    (!name.is_empty()).then(|| name.to_owned())
}

#[cfg(target_os = "macos")]
unsafe extern "C" {
    static kSecUseAuthenticationUIAllow: core_foundation_sys::string::CFStringRef;
    static kSecUseAuthenticationUIFail: core_foundation_sys::string::CFStringRef;
    #[link_name = "kSecMatchItemList"]
    static K_SEC_MATCH_ITEM_LIST: core_foundation_sys::string::CFStringRef;
}

#[cfg(target_os = "macos")]
fn build_keychain_query(
    service: &core_foundation::string::CFString,
    ui_mode: core_foundation_sys::string::CFStringRef,
    phase: KeychainQueryPhase<'_>,
) -> core_foundation::dictionary::CFMutableDictionary<
    *const std::ffi::c_void,
    *const std::ffi::c_void,
> {
    use core_foundation::{
        array::CFArray,
        base::{CFType, TCFType, ToVoid},
        boolean::CFBoolean,
        dictionary::CFMutableDictionary,
    };
    use security_framework_sys::item::{
        kSecAttrAccount, kSecAttrService, kSecClass, kSecClassGenericPassword, kSecMatchLimit,
        kSecMatchLimitAll, kSecReturnData, kSecReturnPersistentRef, kSecUseAuthenticationUI,
    };

    let true_value = CFBoolean::true_value();
    let mut query = CFMutableDictionary::<*const std::ffi::c_void, *const std::ffi::c_void>::new();
    unsafe {
        query.add(
            &(kSecClass as *const std::ffi::c_void),
            &(kSecClassGenericPassword as *const std::ffi::c_void),
        );
        query.add(
            &(kSecAttrService as *const std::ffi::c_void),
            &(service.as_concrete_TypeRef() as *const std::ffi::c_void),
        );
        query.add(
            &(kSecUseAuthenticationUI as *const std::ffi::c_void),
            &(ui_mode as *const std::ffi::c_void),
        );
        match phase {
            KeychainQueryPhase::PersistentReference { account } => {
                if let Some(account) = account {
                    query.add(
                        &(kSecAttrAccount as *const std::ffi::c_void),
                        &(account.as_concrete_TypeRef() as *const std::ffi::c_void),
                    );
                }
                query.add(
                    &(kSecMatchLimit as *const std::ffi::c_void),
                    &(kSecMatchLimitAll as *const std::ffi::c_void),
                );
                query.add(
                    &(kSecReturnPersistentRef as *const std::ffi::c_void),
                    &true_value.to_void(),
                );
            }
            KeychainQueryPhase::Data(persistent_ref) => {
                let item_list = CFArray::from_CFTypes(&[persistent_ref.as_CFType()]);
                let item_list_value: CFType = item_list.as_CFType();
                query.add(
                    &(K_SEC_MATCH_ITEM_LIST as *const std::ffi::c_void),
                    &item_list_value.to_void(),
                );
                query.add(
                    &(kSecReturnData as *const std::ffi::c_void),
                    &true_value.to_void(),
                );
            }
        }
    }
    query
}

#[cfg(target_os = "macos")]
fn single_persistent_ref(
    result: core_foundation_sys::base::CFTypeRef,
) -> Result<core_foundation::data::CFData, ClaudeCredentialError> {
    use core_foundation::{
        array::CFArray,
        base::{CFType, TCFType},
        data::CFData,
    };
    use core_foundation_sys::base::{CFGetTypeID, CFRelease};

    if result.is_null() {
        return Err(ClaudeCredentialError::NotFound);
    }

    unsafe {
        if CFGetTypeID(result) == CFArray::<CFType>::type_id() {
            let values = CFArray::<CFType>::wrap_under_create_rule(result as *mut _);
            if values.len() != 1 {
                return Err(ClaudeCredentialError::KeychainAmbiguous);
            }
            let value = values
                .get(0)
                .ok_or(ClaudeCredentialError::KeychainAmbiguous)?;
            value
                .downcast::<CFData>()
                .ok_or(ClaudeCredentialError::KeychainAmbiguous)
        } else if CFGetTypeID(result) == CFData::type_id() {
            Ok(CFData::wrap_under_create_rule(result as *mut _))
        } else {
            CFRelease(result);
            Err(ClaudeCredentialError::KeychainAmbiguous)
        }
    }
}

#[cfg(target_os = "macos")]
fn single_keychain_data(
    result: core_foundation_sys::base::CFTypeRef,
) -> Result<Zeroizing<Vec<u8>>, ClaudeCredentialError> {
    use core_foundation::{base::TCFType, data::CFData};
    use core_foundation_sys::base::{CFGetTypeID, CFRelease};

    if result.is_null() {
        return Err(ClaudeCredentialError::NotFound);
    }

    unsafe {
        if CFGetTypeID(result) != CFData::type_id() {
            CFRelease(result);
            return Err(ClaudeCredentialError::KeychainAmbiguous);
        }
        let value = CFData::wrap_under_create_rule(result as *mut _);
        Ok(Zeroizing::new(value.bytes().to_vec()))
    }
}

#[cfg(target_os = "macos")]
fn map_security_error(error: security_framework::base::Error) -> ClaudeCredentialError {
    use security_framework_sys::base::{errSecAuthFailed, errSecItemNotFound};

    const ERR_SEC_PARAM: i32 = -50;
    const ERR_SEC_INTERACTION_NOT_ALLOWED: i32 = -25_308;
    const ERR_SEC_USER_CANCELED: i32 = -128;
    const ERR_SEC_NOT_AVAILABLE: i32 = -25_291;
    const ERR_SEC_ITEM_NOT_FOUND: i32 = errSecItemNotFound;
    const ERR_SEC_AUTH_FAILED: i32 = errSecAuthFailed;

    match error.code() {
        ERR_SEC_PARAM => ClaudeCredentialError::KeychainAmbiguous,
        ERR_SEC_ITEM_NOT_FOUND => ClaudeCredentialError::NotFound,
        ERR_SEC_INTERACTION_NOT_ALLOWED => ClaudeCredentialError::InteractionNotAllowed,
        ERR_SEC_USER_CANCELED => ClaudeCredentialError::Cancelled,
        ERR_SEC_AUTH_FAILED | ERR_SEC_NOT_AVAILABLE => ClaudeCredentialError::PermissionDenied,
        _ => ClaudeCredentialError::PermissionDenied,
    }
}

#[cfg(test)]
mod tests {
    use std::io;

    use super::{map_file_read_error, parse_credential_payload, ClaudeCredentialError};
    use crate::RedactingHttpClient;

    #[test]
    fn file_read_errors_keep_missing_and_permission_denied_distinct() {
        assert_eq!(
            map_file_read_error(io::Error::from(io::ErrorKind::NotFound)),
            ClaudeCredentialError::NotFound
        );
        assert_eq!(
            map_file_read_error(io::Error::from(io::ErrorKind::PermissionDenied)),
            ClaudeCredentialError::FilePermissionDenied
        );
        assert_eq!(
            map_file_read_error(io::Error::from(io::ErrorKind::IsADirectory)),
            ClaudeCredentialError::FileReadFailed
        );
    }

    #[test]
    fn parser_keeps_refresh_tokens_out_of_the_typed_projection() {
        let canary = "CLAUDE-KEYCHAIN-CANARY";
        let payload = format!(
            r#"{{"claudeAiOauth":{{"accessToken":"test-token","refreshToken":"{canary}"}}}}"#
        );

        let secret = parse_credential_payload(payload.as_bytes()).unwrap();

        assert_eq!(secret.access_token(), "test-token");
    }

    #[test]
    fn keychain_canary_never_reaches_safe_error_surfaces() {
        let canary = "CLAUDE-KEYCHAIN-CANARY";
        let payload = format!(r#"{{"claudeAiOauth":{{"accessToken":"{canary}"}}}}"#);
        let secret = parse_credential_payload(payload.as_bytes()).unwrap();
        let error = RedactingHttpClient::new()
            .get_bearer(
                "https://example.invalid/api/oauth/usage",
                secret.access_token(),
                &[],
            )
            .unwrap_err();

        assert!(!format!("{error:?}").contains(canary));
        assert!(!serde_json::to_string(&error).unwrap().contains(canary));
    }

    #[test]
    fn malformed_keychain_payload_fails_without_echoing_data() {
        let error = match parse_credential_payload(br#"{"claudeAiOauth":{"accessToken":""}}"#) {
            Err(error) => error,
            Ok(_) => panic!("empty access tokens must not resolve"),
        };

        assert_eq!(error, ClaudeCredentialError::Malformed);
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn invalid_keychain_query_is_reported_as_an_ambiguous_store() {
        let error = super::map_security_error(security_framework::base::Error::from_code(-50));

        assert_eq!(error, ClaudeCredentialError::KeychainAmbiguous);
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn keychain_queries_keep_match_all_separate_from_return_data() {
        use core_foundation::{
            array::CFArray,
            base::{CFType, TCFType},
            string::CFString,
        };
        use core_foundation_sys::base::{CFGetTypeID, CFTypeRef};
        use security_framework_sys::item::{
            kSecMatchLimit, kSecReturnData, kSecReturnPersistentRef,
        };
        use std::ffi::c_void;

        unsafe extern "C" {
            #[link_name = "kSecMatchItemList"]
            static K_SEC_MATCH_ITEM_LIST_TEST: core_foundation_sys::string::CFStringRef;
            #[link_name = "kSecValuePersistentRef"]
            static K_SEC_VALUE_PERSISTENT_REF_TEST: core_foundation_sys::string::CFStringRef;
        }

        let service = CFString::new("Claude Code-credentials");
        let first = super::build_keychain_query(
            &service,
            unsafe { super::kSecUseAuthenticationUIFail },
            super::KeychainQueryPhase::PersistentReference { account: None },
        );
        unsafe {
            assert!(first.contains_key(kSecMatchLimit as *const c_void));
            assert!(first.contains_key(kSecReturnPersistentRef as *const c_void));
            assert!(!first.contains_key(kSecReturnData as *const c_void));
        }

        let persistent_ref = core_foundation::data::CFData::from_buffer(b"persistent-ref");
        let second = super::build_keychain_query(
            &service,
            unsafe { super::kSecUseAuthenticationUIFail },
            super::KeychainQueryPhase::Data(&persistent_ref),
        );
        unsafe {
            assert!(!second.contains_key(kSecMatchLimit as *const c_void));
            assert!(second.contains_key(kSecReturnData as *const c_void));
            assert!(second.contains_key(K_SEC_MATCH_ITEM_LIST_TEST as *const c_void));
            assert!(!second.contains_key(K_SEC_VALUE_PERSISTENT_REF_TEST as *const c_void));

            let item_list_key = K_SEC_MATCH_ITEM_LIST_TEST as *const c_void;
            let item_list_ref = *second
                .to_immutable()
                .find(item_list_key)
                .expect("phase 2 must provide an item list");
            assert_eq!(
                CFGetTypeID(item_list_ref as CFTypeRef),
                CFArray::<CFType>::type_id()
            );
            let item_list = CFArray::<CFType>::wrap_under_get_rule(item_list_ref as *mut _);
            assert_eq!(item_list.len(), 1);
        }
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn persistent_reference_result_requires_exactly_one_data_value() {
        use core_foundation::{
            array::CFArray,
            base::{CFType, TCFType},
            data::CFData,
            string::CFString,
        };
        use std::mem;

        fn resolve_owned(value: CFType) -> Result<CFData, ClaudeCredentialError> {
            let raw = value.as_CFTypeRef();
            mem::forget(value);
            super::single_persistent_ref(raw)
        }

        let data = CFData::from_buffer(b"persistent-ref");
        assert!(resolve_owned(data.into_CFType()).is_ok());

        let data = CFData::from_buffer(b"persistent-ref");
        let array = CFArray::from_CFTypes(&[data]);
        assert!(resolve_owned(array.into_CFType()).is_ok());

        let empty = CFArray::<CFData>::from_CFTypes(&[]);
        assert_eq!(
            resolve_owned(empty.into_CFType()),
            Err(ClaudeCredentialError::KeychainAmbiguous)
        );

        let first = CFData::from_buffer(b"first");
        let second = CFData::from_buffer(b"second");
        let multiple = CFArray::from_CFTypes(&[first, second]);
        assert_eq!(
            resolve_owned(multiple.into_CFType()),
            Err(ClaudeCredentialError::KeychainAmbiguous)
        );

        let not_data = CFArray::from_CFTypes(&[CFString::new("not-data")]);
        assert_eq!(
            resolve_owned(not_data.into_CFType()),
            Err(ClaudeCredentialError::KeychainAmbiguous)
        );

        let wrong_type = CFString::new("not-data");
        assert_eq!(
            resolve_owned(wrong_type.into_CFType()),
            Err(ClaudeCredentialError::KeychainAmbiguous)
        );
    }

    /// In-memory stand-in for `SecItemCopyMatching`. It answers the
    /// reference-only queries from configured outcomes, answers the data query
    /// with a synthetic payload whose access token names the chosen item, and
    /// records every query. No real Keychain is ever consulted.
    #[cfg(target_os = "macos")]
    mod fake_keychain {
        use core_foundation::{
            array::{CFArray, CFArrayRef},
            base::{CFType, TCFType},
            data::CFData,
            dictionary::CFDictionary,
            string::{CFString, CFStringRef},
        };
        use core_foundation_sys::{
            base::{CFTypeRef, OSStatus},
            dictionary::CFDictionaryRef,
        };
        use security_framework_sys::item::{
            kSecAttrAccount, kSecAttrService, kSecClass, kSecClassGenericPassword, kSecMatchLimit,
            kSecMatchLimitAll, kSecReturnData, kSecReturnPersistentRef, kSecUseAuthenticationUI,
        };
        use std::{ffi::c_void, mem};

        pub(super) const ITEM_NOT_FOUND: OSStatus = -25_300;

        #[derive(Clone, Copy)]
        pub(super) enum Lookup {
            Status(OSStatus),
            Items(&'static [&'static str]),
        }

        #[derive(Debug, PartialEq, Eq)]
        pub(super) enum Query {
            Account(String),
            ServiceOnly,
            Data(String),
        }

        pub(super) struct FakeKeychain {
            account: Lookup,
            service_only: Lookup,
            pub(super) queries: Vec<Query>,
            pub(super) ui_modes: Vec<CFStringRef>,
        }

        impl FakeKeychain {
            pub(super) fn new(account: Lookup, service_only: Lookup) -> Self {
                Self {
                    account,
                    service_only,
                    queries: Vec::new(),
                    ui_modes: Vec::new(),
                }
            }

            pub(super) fn copy_matching(
                &mut self,
                query: CFDictionaryRef,
                result: &mut CFTypeRef,
            ) -> OSStatus {
                let query = unsafe {
                    CFDictionary::<*const c_void, *const c_void>::wrap_under_get_rule(query)
                };
                let value = |key: CFStringRef| query.find(key as *const c_void).map(|value| *value);
                unsafe {
                    assert_eq!(
                        value(kSecClass),
                        Some(kSecClassGenericPassword as *const c_void)
                    );
                    let service = value(kSecAttrService).expect("every query names the service");
                    assert_eq!(string(service), "Claude Code-credentials");
                    self.ui_modes.push(
                        value(kSecUseAuthenticationUI).expect("every query sets a UI mode")
                            as CFStringRef,
                    );

                    if value(kSecReturnData).is_some() {
                        assert!(value(kSecReturnPersistentRef).is_none());
                        assert!(value(kSecMatchLimit).is_none());
                        assert!(value(kSecAttrAccount).is_none());
                        let item_list = value(super::super::K_SEC_MATCH_ITEM_LIST)
                            .expect("the data query names one item");
                        let item_list =
                            CFArray::<CFType>::wrap_under_get_rule(item_list as CFArrayRef);
                        assert_eq!(item_list.len(), 1);
                        let item = item_list
                            .get(0)
                            .and_then(|item| item.downcast::<CFData>())
                            .expect("the item list holds a persistent reference");
                        let item = String::from_utf8(item.bytes().to_vec()).unwrap();
                        let payload = format!(r#"{{"claudeAiOauth":{{"accessToken":"{item}"}}}}"#);
                        self.queries.push(Query::Data(item));
                        *result = hand_over(CFData::from_buffer(payload.as_bytes()).into_CFType());
                        return 0;
                    }

                    assert!(value(kSecReturnPersistentRef).is_some());
                    assert_eq!(
                        value(kSecMatchLimit),
                        Some(kSecMatchLimitAll as *const c_void)
                    );
                    let lookup = match value(kSecAttrAccount) {
                        Some(account) => {
                            self.queries.push(Query::Account(string(account)));
                            self.account
                        }
                        None => {
                            self.queries.push(Query::ServiceOnly);
                            self.service_only
                        }
                    };
                    match lookup {
                        Lookup::Status(status) => status,
                        Lookup::Items(items) => {
                            let refs: Vec<CFData> = items
                                .iter()
                                .map(|item| CFData::from_buffer(item.as_bytes()))
                                .collect();
                            *result = hand_over(CFArray::from_CFTypes(&refs).into_CFType());
                            0
                        }
                    }
                }
            }
        }

        /// `value` must be a live CFString owned by the query being inspected.
        fn string(value: *const c_void) -> String {
            unsafe { CFString::wrap_under_get_rule(value as CFStringRef) }.to_string()
        }

        /// Returns a +1 reference, as `SecItemCopyMatching` does.
        fn hand_over(value: CFType) -> CFTypeRef {
            let raw = value.as_CFTypeRef();
            mem::forget(value);
            raw
        }
    }

    #[cfg(target_os = "macos")]
    fn resolve_with_fake(
        access: super::ClaudeCredentialAccess,
        login_name: Option<&str>,
        keychain: &mut fake_keychain::FakeKeychain,
    ) -> Result<String, ClaudeCredentialError> {
        super::resolve_keychain_with(access, login_name, &mut |query, result| {
            keychain.copy_matching(query, result)
        })
        .map(|secret| secret.access_token().to_owned())
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn background_access_never_allows_keychain_ui() {
        use super::ClaudeCredentialAccess;

        unsafe {
            assert_eq!(
                super::keychain_ui_mode(ClaudeCredentialAccess::BackgroundNoUI),
                super::kSecUseAuthenticationUIFail
            );
            assert_eq!(
                super::keychain_ui_mode(ClaudeCredentialAccess::UserInitiatedAllowUI),
                super::kSecUseAuthenticationUIAllow
            );
        }
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn single_service_item_is_read_once_by_persistent_reference() {
        use super::ClaudeCredentialAccess;
        use fake_keychain::{FakeKeychain, Lookup, Query};

        let mut keychain = FakeKeychain::new(
            Lookup::Status(fake_keychain::ITEM_NOT_FOUND),
            Lookup::Items(&["only-item"]),
        );

        assert_eq!(
            resolve_with_fake(ClaudeCredentialAccess::BackgroundNoUI, None, &mut keychain),
            Ok("only-item".to_owned())
        );
        assert_eq!(
            keychain.queries,
            [Query::ServiceOnly, Query::Data("only-item".to_owned())]
        );
        assert!(keychain
            .ui_modes
            .iter()
            .all(|mode| *mode == unsafe { super::kSecUseAuthenticationUIFail }));
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn several_service_items_fail_closed_before_any_data_read() {
        use super::ClaudeCredentialAccess;
        use fake_keychain::{FakeKeychain, Lookup, Query};

        let mut keychain = FakeKeychain::new(
            Lookup::Status(fake_keychain::ITEM_NOT_FOUND),
            Lookup::Items(&["first-item", "second-item"]),
        );

        assert_eq!(
            resolve_with_fake(
                ClaudeCredentialAccess::UserInitiatedAllowUI,
                None,
                &mut keychain
            ),
            Err(ClaudeCredentialError::KeychainAmbiguous)
        );
        assert_eq!(keychain.queries, [Query::ServiceOnly]);
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn missing_service_item_is_not_found_and_reads_no_data() {
        use super::ClaudeCredentialAccess;
        use fake_keychain::{FakeKeychain, Lookup, Query};

        let mut keychain = FakeKeychain::new(
            Lookup::Status(fake_keychain::ITEM_NOT_FOUND),
            Lookup::Status(fake_keychain::ITEM_NOT_FOUND),
        );

        assert_eq!(
            resolve_with_fake(ClaudeCredentialAccess::BackgroundNoUI, None, &mut keychain),
            Err(ClaudeCredentialError::NotFound)
        );
        assert_eq!(keychain.queries, [Query::ServiceOnly]);
    }

    #[cfg(target_os = "macos")]
    const TEST_LOGIN_NAME: &str = "test-login-user";

    /// Runs the selection with fixed lookup outcomes and records each lookup
    /// scope: `Some(account)` for the account-scoped query, `None` for the
    /// service-only query.
    #[cfg(target_os = "macos")]
    fn select_with(
        login_name: Option<&str>,
        account: Result<&'static str, ClaudeCredentialError>,
        service_only: Result<&'static str, ClaudeCredentialError>,
    ) -> (
        Result<&'static str, ClaudeCredentialError>,
        Vec<Option<String>>,
    ) {
        let mut scopes = Vec::new();
        let chosen = super::select_persistent_ref(login_name, |scope| {
            scopes.push(scope.map(str::to_owned));
            match scope {
                Some(_) => account,
                None => service_only,
            }
        });
        (chosen, scopes)
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn login_account_match_is_chosen_even_when_the_service_holds_several_items() {
        let (chosen, scopes) = select_with(
            Some(TEST_LOGIN_NAME),
            Ok("login-item"),
            Err(ClaudeCredentialError::KeychainAmbiguous),
        );

        assert_eq!(chosen, Ok("login-item"));
        assert_eq!(scopes, [Some(TEST_LOGIN_NAME.to_owned())]);
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn several_login_account_matches_stay_ambiguous_without_fallback() {
        let (chosen, scopes) = select_with(
            Some(TEST_LOGIN_NAME),
            Err(ClaudeCredentialError::KeychainAmbiguous),
            Ok("service-item"),
        );

        assert_eq!(chosen, Err(ClaudeCredentialError::KeychainAmbiguous));
        assert_eq!(scopes, [Some(TEST_LOGIN_NAME.to_owned())]);
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn missing_login_account_item_falls_back_to_the_unchanged_service_only_rule() {
        let both = [Some(TEST_LOGIN_NAME.to_owned()), None];
        for (service_only, expected) in [
            (Ok("service-item"), Ok("service-item")),
            (
                Err(ClaudeCredentialError::KeychainAmbiguous),
                Err(ClaudeCredentialError::KeychainAmbiguous),
            ),
            (
                Err(ClaudeCredentialError::NotFound),
                Err(ClaudeCredentialError::NotFound),
            ),
        ] {
            let (chosen, scopes) = select_with(
                Some(TEST_LOGIN_NAME),
                Err(ClaudeCredentialError::NotFound),
                service_only,
            );

            assert_eq!(chosen, expected);
            assert_eq!(scopes, both);
        }
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn keychain_errors_on_the_login_account_lookup_never_fall_back() {
        for (status, expected) in [
            (-25_308, ClaudeCredentialError::InteractionNotAllowed),
            (-128, ClaudeCredentialError::Cancelled),
            (-50, ClaudeCredentialError::KeychainAmbiguous),
            (-25_293, ClaudeCredentialError::PermissionDenied),
            (-25_291, ClaudeCredentialError::PermissionDenied),
            (-34_018, ClaudeCredentialError::PermissionDenied),
        ] {
            let mapped =
                super::map_security_error(security_framework::base::Error::from_code(status));
            assert_eq!(mapped, expected, "status {status} keeps its mapping");

            let (chosen, scopes) =
                select_with(Some(TEST_LOGIN_NAME), Err(mapped), Ok("service-item"));

            assert_eq!(chosen, Err(expected), "status {status} must not fall back");
            assert_eq!(scopes, [Some(TEST_LOGIN_NAME.to_owned())]);
        }
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn unavailable_login_name_uses_only_the_service_only_rule() {
        for (service_only, expected) in [
            (Ok("service-item"), Ok("service-item")),
            (
                Err(ClaudeCredentialError::KeychainAmbiguous),
                Err(ClaudeCredentialError::KeychainAmbiguous),
            ),
        ] {
            let (chosen, scopes) = select_with(None, Ok("login-item"), service_only);

            assert_eq!(chosen, expected);
            assert_eq!(scopes, [None]);
        }
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn only_the_account_scoped_reference_query_names_an_account() {
        use core_foundation::{
            base::TCFType,
            data::CFData,
            string::{CFString, CFStringRef},
        };
        use security_framework_sys::item::{
            kSecAttrAccount, kSecAttrService, kSecMatchLimit, kSecMatchLimitAll, kSecReturnData,
            kSecReturnPersistentRef, kSecUseAuthenticationUI,
        };
        use std::ffi::c_void;

        let service = CFString::new("Claude Code-credentials");
        let account = CFString::new(TEST_LOGIN_NAME);
        for ui_mode in unsafe {
            [
                super::kSecUseAuthenticationUIFail,
                super::kSecUseAuthenticationUIAllow,
            ]
        } {
            let scoped = super::build_keychain_query(
                &service,
                ui_mode,
                super::KeychainQueryPhase::PersistentReference {
                    account: Some(&account),
                },
            )
            .to_immutable();
            let service_only = super::build_keychain_query(
                &service,
                ui_mode,
                super::KeychainQueryPhase::PersistentReference { account: None },
            )
            .to_immutable();
            let persistent_ref = CFData::from_buffer(b"persistent-ref");
            let data = super::build_keychain_query(
                &service,
                ui_mode,
                super::KeychainQueryPhase::Data(&persistent_ref),
            )
            .to_immutable();

            unsafe {
                let string_value = |value: *const c_void| {
                    CFString::wrap_under_get_rule(value as CFStringRef).to_string()
                };
                let account_value = scoped
                    .find(kSecAttrAccount as *const c_void)
                    .map(|value| string_value(*value));
                assert_eq!(account_value.as_deref(), Some(TEST_LOGIN_NAME));
                assert!(!service_only.contains_key(&(kSecAttrAccount as *const c_void)));
                assert!(!data.contains_key(&(kSecAttrAccount as *const c_void)));
                assert_eq!(scoped.len(), service_only.len() + 1);

                for query in [&scoped, &service_only] {
                    let service_value = query
                        .find(kSecAttrService as *const c_void)
                        .map(|value| string_value(*value));
                    assert_eq!(service_value.as_deref(), Some("Claude Code-credentials"));
                    assert_eq!(
                        query
                            .find(kSecMatchLimit as *const c_void)
                            .map(|value| *value),
                        Some(kSecMatchLimitAll as *const c_void)
                    );
                    assert!(query.contains_key(&(kSecReturnPersistentRef as *const c_void)));
                    assert!(!query.contains_key(&(kSecReturnData as *const c_void)));
                    assert_eq!(
                        query
                            .find(kSecUseAuthenticationUI as *const c_void)
                            .map(|value| *value),
                        Some(ui_mode as *const c_void)
                    );
                }
            }
        }
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn login_account_item_is_read_without_the_service_only_query() {
        use super::ClaudeCredentialAccess;
        use fake_keychain::{FakeKeychain, Lookup, Query};

        let mut keychain = FakeKeychain::new(
            Lookup::Items(&["login-item"]),
            Lookup::Items(&["login-item", "unknown-account-item"]),
        );

        assert_eq!(
            resolve_with_fake(
                ClaudeCredentialAccess::BackgroundNoUI,
                Some(TEST_LOGIN_NAME),
                &mut keychain
            ),
            Ok("login-item".to_owned())
        );
        assert_eq!(
            keychain.queries,
            [
                Query::Account(TEST_LOGIN_NAME.to_owned()),
                Query::Data("login-item".to_owned()),
            ]
        );
        assert!(keychain
            .ui_modes
            .iter()
            .all(|mode| *mode == unsafe { super::kSecUseAuthenticationUIFail }));
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn missing_login_account_item_reads_the_single_service_item_once() {
        use super::ClaudeCredentialAccess;
        use fake_keychain::{FakeKeychain, Lookup, Query};

        let mut keychain = FakeKeychain::new(
            Lookup::Status(fake_keychain::ITEM_NOT_FOUND),
            Lookup::Items(&["only-item"]),
        );

        assert_eq!(
            resolve_with_fake(
                ClaudeCredentialAccess::UserInitiatedAllowUI,
                Some(TEST_LOGIN_NAME),
                &mut keychain
            ),
            Ok("only-item".to_owned())
        );
        assert_eq!(
            keychain.queries,
            [
                Query::Account(TEST_LOGIN_NAME.to_owned()),
                Query::ServiceOnly,
                Query::Data("only-item".to_owned()),
            ]
        );
        assert_eq!(keychain.ui_modes.len(), 3);
        assert!(keychain
            .ui_modes
            .iter()
            .all(|mode| *mode == unsafe { super::kSecUseAuthenticationUIAllow }));
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn missing_login_account_item_with_several_service_items_stays_ambiguous() {
        use super::ClaudeCredentialAccess;
        use fake_keychain::{FakeKeychain, Lookup, Query};

        let mut keychain = FakeKeychain::new(
            Lookup::Status(fake_keychain::ITEM_NOT_FOUND),
            Lookup::Items(&["first-item", "second-item"]),
        );

        assert_eq!(
            resolve_with_fake(
                ClaudeCredentialAccess::BackgroundNoUI,
                Some(TEST_LOGIN_NAME),
                &mut keychain
            ),
            Err(ClaudeCredentialError::KeychainAmbiguous)
        );
        assert_eq!(
            keychain.queries,
            [
                Query::Account(TEST_LOGIN_NAME.to_owned()),
                Query::ServiceOnly
            ]
        );
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn several_login_account_items_stay_ambiguous_before_any_data_read() {
        use super::ClaudeCredentialAccess;
        use fake_keychain::{FakeKeychain, Lookup, Query};

        let mut keychain = FakeKeychain::new(
            Lookup::Items(&["first-item", "second-item"]),
            Lookup::Items(&["only-item"]),
        );

        assert_eq!(
            resolve_with_fake(
                ClaudeCredentialAccess::BackgroundNoUI,
                Some(TEST_LOGIN_NAME),
                &mut keychain
            ),
            Err(ClaudeCredentialError::KeychainAmbiguous)
        );
        assert_eq!(
            keychain.queries,
            [Query::Account(TEST_LOGIN_NAME.to_owned())]
        );
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn refused_login_account_lookup_issues_no_further_query() {
        use super::ClaudeCredentialAccess;
        use fake_keychain::{FakeKeychain, Lookup, Query};

        for (access, status, expected) in [
            (
                ClaudeCredentialAccess::BackgroundNoUI,
                -25_308,
                ClaudeCredentialError::InteractionNotAllowed,
            ),
            (
                ClaudeCredentialAccess::UserInitiatedAllowUI,
                -128,
                ClaudeCredentialError::Cancelled,
            ),
            (
                ClaudeCredentialAccess::UserInitiatedAllowUI,
                -50,
                ClaudeCredentialError::KeychainAmbiguous,
            ),
        ] {
            let mut keychain =
                FakeKeychain::new(Lookup::Status(status), Lookup::Items(&["only-item"]));

            assert_eq!(
                resolve_with_fake(access, Some(TEST_LOGIN_NAME), &mut keychain),
                Err(expected)
            );
            assert_eq!(
                keychain.queries,
                [Query::Account(TEST_LOGIN_NAME.to_owned())]
            );
        }
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn login_name_must_be_non_empty_utf8() {
        use std::ffi::CStr;

        let name =
            |bytes: &[u8]| super::login_name_from_c_str(CStr::from_bytes_with_nul(bytes).unwrap());

        assert_eq!(name(b"test-login-user\0"), Some(TEST_LOGIN_NAME.to_owned()));
        assert_eq!(name(b"\0"), None);
        assert_eq!(name(b"\xff\xfe\0"), None);
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn current_login_name_comes_from_the_user_database() {
        let name = super::current_login_name().expect("the test user has a passwd entry");

        assert!(!name.is_empty());
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn keychain_data_result_must_be_data() {
        use core_foundation::{
            base::{CFType, TCFType},
            data::CFData,
            string::CFString,
        };
        use std::mem;

        fn resolve_owned(value: CFType) -> Result<Vec<u8>, ClaudeCredentialError> {
            let raw = value.as_CFTypeRef();
            mem::forget(value);
            super::single_keychain_data(raw).map(|data| data.to_vec())
        }

        assert_eq!(
            resolve_owned(CFData::from_buffer(b"payload").into_CFType()),
            Ok(b"payload".to_vec())
        );
        assert_eq!(
            super::single_keychain_data(std::ptr::null()).map(|data| data.to_vec()),
            Err(ClaudeCredentialError::NotFound)
        );
        assert_eq!(
            resolve_owned(CFString::new("not-data").into_CFType()),
            Err(ClaudeCredentialError::KeychainAmbiguous)
        );
    }
}
