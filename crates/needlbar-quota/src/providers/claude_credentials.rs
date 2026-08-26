use std::{env, fs, path::PathBuf, sync::Arc};

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
        let contents = Zeroizing::new(
            fs::read(self.credentials_path()).map_err(|_| ClaudeCredentialError::NotFound)?,
        );
        parse_credential_payload(&contents).map_err(|error| match error {
            // Preserve the legacy file behavior: malformed local file evidence
            // is indistinguishable from unavailable credentials.
            ClaudeCredentialError::Malformed => ClaudeCredentialError::NotFound,
            other => other,
        })
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
fn resolve_keychain(
    access: ClaudeCredentialAccess,
) -> Result<ClaudeOAuthSecret, ClaudeCredentialError> {
    use std::ptr;

    use core_foundation::base::TCFType;
    use core_foundation::string::CFString;
    use core_foundation_sys::base::CFTypeRef;
    use security_framework_sys::{base::errSecSuccess, keychain_item::SecItemCopyMatching};

    let service = CFString::new("Claude Code-credentials");
    let ui_mode = unsafe {
        match access {
            ClaudeCredentialAccess::BackgroundNoUI => kSecUseAuthenticationUIFail,
            ClaudeCredentialAccess::UserInitiatedAllowUI => kSecUseAuthenticationUIAllow,
        }
    };
    let query = build_keychain_query(&service, ui_mode, KeychainQueryPhase::PersistentReference);
    let mut result: CFTypeRef = ptr::null();
    let status = unsafe { SecItemCopyMatching(query.as_concrete_TypeRef(), &mut result) };
    if status != errSecSuccess {
        return Err(map_security_error(
            security_framework::base::Error::from_code(status),
        ));
    }

    let persistent_ref = single_persistent_ref(result)?;
    let query = build_keychain_query(&service, ui_mode, KeychainQueryPhase::Data(&persistent_ref));
    let mut result: CFTypeRef = ptr::null();
    let status = unsafe { SecItemCopyMatching(query.as_concrete_TypeRef(), &mut result) };
    if status != errSecSuccess {
        return Err(map_security_error(
            security_framework::base::Error::from_code(status),
        ));
    }

    let payload = single_keychain_data(result)?;
    parse_credential_payload(&payload)
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
                return Err(ClaudeCredentialError::Malformed);
            }
            let value = values.get(0).ok_or(ClaudeCredentialError::Malformed)?;
            value
                .downcast::<CFData>()
                .ok_or(ClaudeCredentialError::Malformed)
        } else if CFGetTypeID(result) == CFData::type_id() {
            Ok(CFData::wrap_under_create_rule(result as *mut _))
        } else {
            CFRelease(result);
            Err(ClaudeCredentialError::Malformed)
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
            return Err(ClaudeCredentialError::Malformed);
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
        ERR_SEC_PARAM => ClaudeCredentialError::Malformed,
        ERR_SEC_ITEM_NOT_FOUND => ClaudeCredentialError::NotFound,
        ERR_SEC_INTERACTION_NOT_ALLOWED => ClaudeCredentialError::InteractionNotAllowed,
        ERR_SEC_USER_CANCELED => ClaudeCredentialError::Cancelled,
        ERR_SEC_AUTH_FAILED | ERR_SEC_NOT_AVAILABLE => ClaudeCredentialError::PermissionDenied,
        _ => ClaudeCredentialError::PermissionDenied,
    }
}

#[cfg(test)]
mod tests {
    use super::{parse_credential_payload, ClaudeCredentialError};
    use crate::RedactingHttpClient;

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
    fn invalid_keychain_query_is_reported_as_malformed() {
        let error = super::map_security_error(security_framework::base::Error::from_code(-50));

        assert_eq!(error, ClaudeCredentialError::Malformed);
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
            Err(ClaudeCredentialError::Malformed)
        );

        let first = CFData::from_buffer(b"first");
        let second = CFData::from_buffer(b"second");
        let multiple = CFArray::from_CFTypes(&[first, second]);
        assert_eq!(
            resolve_owned(multiple.into_CFType()),
            Err(ClaudeCredentialError::Malformed)
        );

        let wrong_type = CFString::new("not-data");
        assert_eq!(
            resolve_owned(wrong_type.into_CFType()),
            Err(ClaudeCredentialError::Malformed)
        );
    }
}
