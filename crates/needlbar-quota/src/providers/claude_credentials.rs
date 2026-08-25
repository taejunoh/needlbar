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
    use std::{ffi::c_void, ptr};

    use core_foundation::{
        array::CFArray,
        base::{TCFType, ToVoid},
        boolean::CFBoolean,
        data::CFData,
        dictionary::CFMutableDictionary,
        string::CFString,
    };
    use core_foundation_sys::{
        base::{CFGetTypeID, CFTypeRef},
        string::CFStringRef,
    };
    use security_framework_sys::{
        base::errSecSuccess,
        item::{
            kSecAttrService, kSecClass, kSecClassGenericPassword, kSecMatchLimit,
            kSecMatchLimitAll, kSecReturnData, kSecUseAuthenticationUI,
        },
        keychain_item::SecItemCopyMatching,
    };

    unsafe extern "C" {
        static kSecUseAuthenticationUIAllow: CFStringRef;
        static kSecUseAuthenticationUIFail: CFStringRef;
    }

    let service = CFString::new("Claude Code-credentials");
    let true_value = CFBoolean::true_value();
    let ui_mode = unsafe {
        match access {
            ClaudeCredentialAccess::BackgroundNoUI => kSecUseAuthenticationUIFail,
            ClaudeCredentialAccess::UserInitiatedAllowUI => kSecUseAuthenticationUIAllow,
        }
    };
    let mut query = CFMutableDictionary::<*const c_void, *const c_void>::from_CFType_pairs(&[]);
    unsafe {
        query.add(
            &(kSecClass as *const c_void),
            &(kSecClassGenericPassword as *const c_void),
        );
        query.add(
            &(kSecAttrService as *const c_void),
            &(service.as_concrete_TypeRef() as *const c_void),
        );
        query.add(
            &(kSecMatchLimit as *const c_void),
            &(kSecMatchLimitAll as *const c_void),
        );
        query.add(&(kSecReturnData as *const c_void), &true_value.to_void());
        query.add(
            &(kSecUseAuthenticationUI as *const c_void),
            &(ui_mode as *const c_void),
        );
    }

    let mut result: CFTypeRef = ptr::null();
    let status = unsafe { SecItemCopyMatching(query.as_concrete_TypeRef(), &mut result) };
    if status != errSecSuccess {
        return Err(map_security_error(
            security_framework::base::Error::from_code(status),
        ));
    }
    if result.is_null() {
        return Err(ClaudeCredentialError::NotFound);
    }

    let payload = unsafe {
        if CFGetTypeID(result) == CFArray::<CFData>::type_id() {
            let values = CFArray::<CFData>::wrap_under_create_rule(result as *mut _);
            if values.len() != 1 {
                return Err(ClaudeCredentialError::Malformed);
            }
            let value = values.get(0).ok_or(ClaudeCredentialError::Malformed)?;
            Zeroizing::new(value.bytes().to_vec())
        } else if CFGetTypeID(result) == CFData::type_id() {
            let value = CFData::wrap_under_create_rule(result as *mut _);
            Zeroizing::new(value.bytes().to_vec())
        } else {
            return Err(ClaudeCredentialError::Malformed);
        }
    };
    parse_credential_payload(&payload)
}

#[cfg(target_os = "macos")]
fn map_security_error(error: security_framework::base::Error) -> ClaudeCredentialError {
    use security_framework_sys::base::{errSecAuthFailed, errSecItemNotFound};

    const ERR_SEC_INTERACTION_NOT_ALLOWED: i32 = -25_308;
    const ERR_SEC_USER_CANCELED: i32 = -128;
    const ERR_SEC_NOT_AVAILABLE: i32 = -25_291;
    const ERR_SEC_ITEM_NOT_FOUND: i32 = errSecItemNotFound;
    const ERR_SEC_AUTH_FAILED: i32 = errSecAuthFailed;

    match error.code() {
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
}
