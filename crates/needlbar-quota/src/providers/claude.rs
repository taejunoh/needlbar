use std::{path::PathBuf, sync::Arc};

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::Deserialize;

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
        Self { credentials, http }
    }

    pub async fn fetch_with_credential_access(
        &self,
        access: ClaudeCredentialAccess,
    ) -> Result<ProviderQuotaSnapshot, QuotaError> {
        let credentials = self
            .credentials
            .resolve(access)
            .map_err(credential_error_to_quota_error)?;
        let request = self
            .http
            .get_bearer(
                USAGE_ENDPOINT,
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

        Ok(ProviderQuotaSnapshot {
            provider: ProviderId::Claude,
            windows: vec![session, weekly],
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
}

#[derive(Deserialize)]
struct UsageWindow {
    utilization: f64,
    resets_at: DateTime<Utc>,
}

fn parse_window(source: UsageWindow, id: &str, title: &str) -> Result<QuotaWindow, QuotaError> {
    QuotaWindow::new(id, title, source.utilization, Some(source.resets_at))
        .map_err(|_| schema_error())
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
    use std::fs;

    use tempfile::TempDir;

    use super::*;

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
