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

    resolve_keychain_with(access, &mut |query, result| unsafe {
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
    copy_matching: &mut KeychainCopyMatching<'_>,
) -> Result<ClaudeOAuthSecret, ClaudeCredentialError> {
    use core_foundation::string::CFString;

    let service = CFString::new(CLAUDE_KEYCHAIN_SERVICE);
    let ui_mode = keychain_ui_mode(access);
    let query = build_keychain_query(&service, ui_mode, KeychainQueryPhase::PersistentReference);
    let persistent_ref =
        copy_matching_result(copy_matching, &query).and_then(single_persistent_ref)?;
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
    PersistentReference,
    Data(&'a core_foundation::data::CFData),
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
        kSecAttrService, kSecClass, kSecClassGenericPassword, kSecMatchLimit, kSecMatchLimitAll,
        kSecReturnData, kSecReturnPersistentRef, kSecUseAuthenticationUI,
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
            KeychainQueryPhase::PersistentReference => {
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
            super::KeychainQueryPhase::PersistentReference,
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
        keychain: &mut fake_keychain::FakeKeychain,
    ) -> Result<String, ClaudeCredentialError> {
        super::resolve_keychain_with(access, &mut |query, result| {
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
            resolve_with_fake(ClaudeCredentialAccess::BackgroundNoUI, &mut keychain),
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
            resolve_with_fake(ClaudeCredentialAccess::UserInitiatedAllowUI, &mut keychain),
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
            resolve_with_fake(ClaudeCredentialAccess::BackgroundNoUI, &mut keychain),
            Err(ClaudeCredentialError::NotFound)
        );
        assert_eq!(keychain.queries, [Query::ServiceOnly]);
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
