use std::{path::PathBuf, sync::Arc};

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::{de::Deserializer, Deserialize};
use serde_json::Value;

use super::claude_credentials::{
    production_resolver, ClaudeCredentialAccess, ClaudeCredentialError, ClaudeCredentialResolver,
    FileClaudeCredentialResolver,
};
use crate::{
    ProviderId, ProviderQuotaSnapshot, QuotaError, QuotaErrorCode, QuotaProvider, QuotaWindow,
    RedactingHttpClient,
};

const USAGE_ENDPOINT: &str = "https://api.anthropic.com/api/oauth/usage";
const OAUTH_BETA_HEADER: &str = "oauth-2025-04-20";

pub struct ClaudeQuotaProvider {
    credentials: Arc<dyn ClaudeCredentialResolver>,
    http: RedactingHttpClient,
    #[cfg(test)]
    usage_endpoint: String,
}

impl ClaudeQuotaProvider {
    pub fn new() -> Self {
        Self::with_resolver(production_resolver(), RedactingHttpClient::new())
    }

    /// `config_dir` is the value of `CLAUDE_CONFIG_DIR`, not a credentials
    /// filename. This legacy constructor deliberately uses the file resolver,
    /// keeping fixture and non-macOS behavior deterministic without Keychain
    /// access.
    pub fn from_paths(
        config_dir: Option<PathBuf>,
        home_dir: PathBuf,
        http: RedactingHttpClient,
    ) -> Self {
        Self::with_resolver(
            Arc::new(FileClaudeCredentialResolver::from_paths(
                config_dir, home_dir,
            )),
            http,
        )
    }

    pub fn with_resolver(
        credentials: Arc<dyn ClaudeCredentialResolver>,
        http: RedactingHttpClient,
    ) -> Self {
        Self {
            credentials,
            http,
            #[cfg(test)]
            usage_endpoint: USAGE_ENDPOINT.to_owned(),
        }
    }

    #[cfg(test)]
    fn with_resolver_and_test_endpoint_for_test(
        credentials: Arc<dyn ClaudeCredentialResolver>,
        endpoint: &str,
    ) -> Result<Self, QuotaError> {
        let url = reqwest::Url::parse(endpoint).map_err(|_| schema_error())?;
        if url.scheme() != "http"
            || !matches!(
                url.host_str(),
                Some("127.0.0.1") | Some("::1") | Some("localhost")
            )
        {
            return Err(schema_error());
        }
        let host = url.host_str().ok_or_else(schema_error)?.to_owned();

        Ok(Self {
            credentials,
            http: RedactingHttpClient::for_test(host),
            usage_endpoint: endpoint.to_owned(),
        })
    }

    pub async fn fetch_with_credential_access(
        &self,
        access: ClaudeCredentialAccess,
    ) -> Result<ProviderQuotaSnapshot, QuotaError> {
        let credentials = self
            .credentials
            .resolve(access)
            .map_err(credential_error_to_quota_error)?;
        #[cfg(test)]
        let usage_endpoint = self.usage_endpoint.as_str();
        #[cfg(not(test))]
        let usage_endpoint = USAGE_ENDPOINT;
        let request = self
            .http
            .get_bearer(
                usage_endpoint,
                credentials.access_token(),
                &[("anthropic-beta", OAUTH_BETA_HEADER)],
            )
            .map_err(|error| error.for_provider(ProviderId::Claude))?;
        let response = self
            .http
            .send(request)
            .await
            .map_err(|error| error.for_provider(ProviderId::Claude))?;
        let bytes = self
            .http
            .read_limited_body(response)
            .await
            .map_err(|error| error.for_provider(ProviderId::Claude))?;
        let payload = String::from_utf8(bytes).map_err(|_| schema_error())?;

        Self::parse_usage_payload(&payload)
    }

    pub fn parse_usage_payload(payload: &str) -> Result<ProviderQuotaSnapshot, QuotaError> {
        let response: UsageResponse = serde_json::from_str(payload).map_err(|_| schema_error())?;
        let session = parse_window(response.five_hour, "claude.session", "Session")?;
        let weekly = parse_window(response.seven_day, "claude.weekly", "Weekly")?;
        let mut windows = vec![session, weekly];
        if let Some(fable) = parse_fable_window(response.limits.as_ref()) {
            windows.push(fable);
        }

        Ok(ProviderQuotaSnapshot {
            provider: ProviderId::Claude,
            windows,
        })
    }

    #[cfg(test)]
    fn resolve_credentials(&self, access: ClaudeCredentialAccess) -> Result<(), QuotaError> {
        self.credentials
            .resolve(access)
            .map(|_| ())
            .map_err(credential_error_to_quota_error)
    }
}

impl Default for ClaudeQuotaProvider {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl QuotaProvider for ClaudeQuotaProvider {
    async fn fetch(&self) -> Result<ProviderQuotaSnapshot, QuotaError> {
        self.fetch_with_credential_access(ClaudeCredentialAccess::BackgroundNoUI)
            .await
    }
}

#[derive(Deserialize)]
struct UsageResponse {
    five_hour: UsageWindow,
    seven_day: UsageWindow,
    #[serde(default)]
    limits: Option<Value>,
}

#[derive(Deserialize)]
struct UsageWindow {
    utilization: f64,
    #[serde(deserialize_with = "deserialize_required_optional_timestamp")]
    resets_at: Option<DateTime<Utc>>,
}

fn deserialize_required_optional_timestamp<'de, D>(
    deserializer: D,
) -> Result<Option<DateTime<Utc>>, D::Error>
where
    D: Deserializer<'de>,
{
    Option::<DateTime<Utc>>::deserialize(deserializer)
}

fn parse_window(source: UsageWindow, id: &str, title: &str) -> Result<QuotaWindow, QuotaError> {
    QuotaWindow::new(id, title, source.utilization, source.resets_at).map_err(|_| schema_error())
}

fn is_fable_weekly_candidate(limit: &Value) -> bool {
    limit.get("kind").and_then(Value::as_str) == Some("weekly_scoped")
        && limit.get("group").and_then(Value::as_str) == Some("weekly")
        && limit
            .pointer("/scope/model/display_name")
            .and_then(Value::as_str)
            == Some("Fable")
        && limit.pointer("/scope/surface").is_some_and(Value::is_null)
}

fn parse_optional_fable_reset(limit: &Value) -> Option<Option<DateTime<Utc>>> {
    match limit.get("resets_at") {
        None | Some(Value::Null) => Some(None),
        Some(Value::String(value)) => DateTime::parse_from_rfc3339(value)
            .ok()
            .map(|value| Some(value.with_timezone(&Utc))),
        Some(_) => None,
    }
}

fn parse_fable_window(limits: Option<&Value>) -> Option<QuotaWindow> {
    let mut candidates = limits?
        .as_array()?
        .iter()
        .filter(|value| is_fable_weekly_candidate(value));
    let candidate = candidates.next()?;
    if candidates.next().is_some() {
        return None;
    }
    let percent = candidate.get("percent")?.as_f64()?;
    let resets_at = parse_optional_fable_reset(candidate)?;
    QuotaWindow::new("claude.fable.weekly", "Fable weekly", percent, resets_at).ok()
}

fn credential_error_to_quota_error(error: ClaudeCredentialError) -> QuotaError {
    match error {
        ClaudeCredentialError::NotFound => QuotaError::new(
            Some(ProviderId::Claude),
            QuotaErrorCode::RequiresAuthentication,
            "Claude authentication was not available.",
        ),
        ClaudeCredentialError::InteractionNotAllowed
        | ClaudeCredentialError::PermissionDenied
        | ClaudeCredentialError::Cancelled => QuotaError::new(
            Some(ProviderId::Claude),
            QuotaErrorCode::PermissionDenied,
            "Claude credential access was denied.",
        ),
        ClaudeCredentialError::Expired => QuotaError::new(
            Some(ProviderId::Claude),
            QuotaErrorCode::AuthenticationExpired,
            "Claude authentication has expired.",
        ),
        ClaudeCredentialError::Malformed => schema_error(),
    }
}

fn schema_error() -> QuotaError {
    QuotaError::new(
        Some(ProviderId::Claude),
        QuotaErrorCode::SchemaChanged,
        "Claude quota data was not in the expected format.",
    )
}

#[cfg(test)]
mod tests {
    use std::{
        fs,
        io::{Read, Write},
        net::TcpListener,
        sync::{Arc, Mutex},
        thread,
    };

    use tempfile::TempDir;

    use super::*;
    use crate::providers::claude_credentials::parse_credential_payload;

    struct CanaryResolver {
        accesses: Arc<Mutex<Vec<ClaudeCredentialAccess>>>,
    }

    impl ClaudeCredentialResolver for CanaryResolver {
        fn resolve(
            &self,
            access: ClaudeCredentialAccess,
        ) -> Result<super::super::claude_credentials::ClaudeOAuthSecret, ClaudeCredentialError>
        {
            self.accesses.lock().unwrap().push(access);
            parse_credential_payload(
                br#"{"claudeAiOauth":{"accessToken":"CLAUDE-KEYCHAIN-CANARY"}}"#,
            )
        }
    }

    #[tokio::test]
    async fn test_only_provider_endpoint_keeps_parser_canary_off_success_and_failure_surfaces() {
        let canary = "CLAUDE-KEYCHAIN-CANARY";
        let accesses = Arc::new(Mutex::new(Vec::new()));
        let success_payload = include_str!("../../../../Fixtures/quota/claude/usage-success.json");
        let success_response = format!(
            "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
            success_payload.len(),
            success_payload
        )
        .into_bytes();
        let (success_endpoint, success_server) = capturing_local_server(success_response);
        let success_provider = ClaudeQuotaProvider::with_resolver_and_test_endpoint_for_test(
            Arc::new(CanaryResolver {
                accesses: Arc::clone(&accesses),
            }),
            &success_endpoint,
        )
        .unwrap();

        let snapshot = success_provider
            .fetch_with_credential_access(ClaudeCredentialAccess::UserInitiatedAllowUI)
            .await
            .unwrap();
        let success_request = String::from_utf8(success_server.join().unwrap()).unwrap();

        assert!(success_request
            .to_ascii_lowercase()
            .contains("authorization: bearer claude-keychain-canary"));
        assert_eq!(success_request.matches(canary).count(), 1);
        assert!(!format!("{snapshot:?}").contains(canary));
        assert!(!serde_json::to_string(&snapshot).unwrap().contains(canary));

        let (failure_endpoint, failure_server) = capturing_local_server(
            b"HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                .to_vec(),
        );
        let failure_provider = ClaudeQuotaProvider::with_resolver_and_test_endpoint_for_test(
            Arc::new(CanaryResolver {
                accesses: Arc::clone(&accesses),
            }),
            &failure_endpoint,
        )
        .unwrap();

        let error = failure_provider
            .fetch_with_credential_access(ClaudeCredentialAccess::UserInitiatedAllowUI)
            .await
            .unwrap_err();
        let failure_request = String::from_utf8(failure_server.join().unwrap()).unwrap();

        assert!(failure_request
            .to_ascii_lowercase()
            .contains("authorization: bearer claude-keychain-canary"));
        assert_eq!(failure_request.matches(canary).count(), 1);
        assert!(!format!("{error:?}").contains(canary));
        assert!(!serde_json::to_string(&error).unwrap().contains(canary));
        assert_eq!(
            accesses.lock().unwrap().as_slice(),
            [
                ClaudeCredentialAccess::UserInitiatedAllowUI,
                ClaudeCredentialAccess::UserInitiatedAllowUI,
            ]
        );
    }

    fn capturing_local_server(response: Vec<u8>) -> (String, thread::JoinHandle<Vec<u8>>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let endpoint = format!("http://{}/usage", listener.local_addr().unwrap());
        let server = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut request = Vec::new();
            let mut chunk = [0_u8; 1024];
            loop {
                let read = stream.read(&mut chunk).unwrap();
                if read == 0 {
                    break;
                }
                request.extend_from_slice(&chunk[..read]);
                if request.windows(4).any(|window| window == b"\r\n\r\n") {
                    break;
                }
            }
            stream.write_all(&response).unwrap();
            stream.flush().unwrap();
            request
        });
        (endpoint, server)
    }

    #[test]
    fn malformed_expiry_is_unusable_oauth_evidence() {
        let temp = TempDir::new().unwrap();
        let config_dir = temp.path().join("claude-config");
        fs::create_dir_all(&config_dir).unwrap();
        fs::write(
            config_dir.join(".credentials.json"),
            r#"{"claudeAiOauth":{"accessToken":"token","expiresAt":"not-an-expiry"}}"#,
        )
        .unwrap();
        let provider = ClaudeQuotaProvider::from_paths(
            Some(config_dir),
            temp.path().to_path_buf(),
            RedactingHttpClient::new(),
        );

        let error = provider
            .resolve_credentials(ClaudeCredentialAccess::BackgroundNoUI)
            .err()
            .unwrap();

        assert_eq!(error.code, QuotaErrorCode::RequiresAuthentication);
    }

    #[test]
    fn whitespace_or_header_invalid_access_tokens_are_unusable() {
        for token in ["   ", "valid\\ninvalid"] {
            let temp = TempDir::new().unwrap();
            let config_dir = temp.path().join("claude-config");
            fs::create_dir_all(&config_dir).unwrap();
            fs::write(
                config_dir.join(".credentials.json"),
                format!(r#"{{"claudeAiOauth":{{"accessToken":"{token}"}}}}"#),
            )
            .unwrap();
            let provider = ClaudeQuotaProvider::from_paths(
                Some(config_dir),
                temp.path().to_path_buf(),
                RedactingHttpClient::new(),
            );

            let error = provider
                .resolve_credentials(ClaudeCredentialAccess::BackgroundNoUI)
                .err()
                .unwrap();

            assert_eq!(error.code, QuotaErrorCode::RequiresAuthentication);
        }
    }
}
