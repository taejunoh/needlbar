use std::{env, fs, path::PathBuf};

use async_trait::async_trait;
use chrono::{DateTime, TimeZone, Utc};
use reqwest::header::HeaderValue;
use serde::Deserialize;

use crate::{
    ProviderId, ProviderQuotaSnapshot, QuotaError, QuotaErrorCode, QuotaProvider, QuotaWindow,
    RedactingHttpClient,
};

const USAGE_ENDPOINT: &str = "https://api.anthropic.com/api/oauth/usage";
const OAUTH_BETA_HEADER: &str = "oauth-2025-04-20";

pub struct ClaudeQuotaProvider {
    config_dir: Option<PathBuf>,
    home_dir: PathBuf,
    http: RedactingHttpClient,
}

impl ClaudeQuotaProvider {
    pub fn new() -> Self {
        let config_dir = env::var_os("CLAUDE_CONFIG_DIR").map(PathBuf::from);
        let home_dir = env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("/nonexistent"));
        Self::from_paths(config_dir, home_dir, RedactingHttpClient::new())
    }

    /// `config_dir` is the value of `CLAUDE_CONFIG_DIR`, not a credentials
    /// filename. Keeping it injectable makes the precedence deterministic in
    /// tests without reading user state.
    pub fn from_paths(
        config_dir: Option<PathBuf>,
        home_dir: PathBuf,
        http: RedactingHttpClient,
    ) -> Self {
        Self {
            config_dir: config_dir.filter(|path| !path.as_os_str().is_empty()),
            home_dir,
            http,
        }
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

    fn credentials_path(&self) -> PathBuf {
        match &self.config_dir {
            Some(config_dir) => config_dir.join(".credentials.json"),
            None => self.home_dir.join(".claude/.credentials.json"),
        }
    }

    fn load_credentials(&self) -> Result<ClaudeOauthEvidence, QuotaError> {
        let contents = fs::read_to_string(self.credentials_path()).map_err(|_| auth_required())?;
        let credentials: CredentialsFile =
            serde_json::from_str(&contents).map_err(|_| auth_required())?;
        let oauth = credentials.claude_ai_oauth.ok_or_else(auth_required)?;
        let access_token = oauth
            .access_token
            .as_deref()
            .and_then(normalize_access_token)
            .ok_or_else(auth_required)?;
        if let Some(value) = oauth.expires_at.as_ref() {
            let expires_at = parse_expiry(value).ok_or_else(auth_required)?;
            if expires_at <= Utc::now() {
                // A refresh token alone is not enough to safely guess an
                // undocumented token-refresh exchange in a passive refresh.
                return Err(auth_expired());
            }
        }

        Ok(ClaudeOauthEvidence { access_token })
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
        let credentials = self.load_credentials()?;
        let request = self
            .http
            .get_bearer(
                USAGE_ENDPOINT,
                &credentials.access_token,
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
        let payload = String::from_utf8(bytes).map_err(|_| {
            QuotaError::new(
                Some(ProviderId::Claude),
                QuotaErrorCode::SchemaChanged,
                "Claude quota data was not in the expected format.",
            )
        })?;

        Self::parse_usage_payload(&payload)
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct CredentialsFile {
    claude_ai_oauth: Option<ClaudeOauth>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ClaudeOauth {
    access_token: Option<String>,
    #[allow(dead_code)]
    refresh_token: Option<String>,
    #[serde(default)]
    expires_at: Option<serde_json::Value>,
}

struct ClaudeOauthEvidence {
    access_token: String,
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

fn normalize_access_token(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty()
        || trimmed.chars().any(char::is_whitespace)
        || HeaderValue::from_str(trimmed).is_err()
    {
        None
    } else {
        Some(trimmed.to_owned())
    }
}

fn parse_expiry(value: &serde_json::Value) -> Option<DateTime<Utc>> {
    match value {
        serde_json::Value::String(value) => {
            if let Ok(date) = DateTime::parse_from_rfc3339(value) {
                return Some(date.with_timezone(&Utc));
            }
            value.parse::<i64>().ok().and_then(epoch_to_utc)
        }
        serde_json::Value::Number(number) => number.as_i64().and_then(epoch_to_utc),
        _ => None,
    }
}

fn epoch_to_utc(timestamp: i64) -> Option<DateTime<Utc>> {
    let seconds = if timestamp.unsigned_abs() > 100_000_000_000 {
        timestamp / 1_000
    } else {
        timestamp
    };
    Utc.timestamp_opt(seconds, 0).single()
}

fn auth_required() -> QuotaError {
    QuotaError::new(
        Some(ProviderId::Claude),
        QuotaErrorCode::RequiresAuthentication,
        "Claude authentication was not available.",
    )
}

fn auth_expired() -> QuotaError {
    QuotaError::new(
        Some(ProviderId::Claude),
        QuotaErrorCode::AuthenticationExpired,
        "Claude authentication has expired.",
    )
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

        let error = provider.load_credentials().err().unwrap();

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

            let error = provider.load_credentials().err().unwrap();

            assert_eq!(error.code, QuotaErrorCode::RequiresAuthentication);
        }
    }
}
