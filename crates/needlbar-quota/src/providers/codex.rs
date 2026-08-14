use std::{env, fs, io::ErrorKind, path::PathBuf, sync::Arc, time::Duration};

use async_trait::async_trait;
use chrono::{DateTime, TimeZone, Utc};
use reqwest::header::HeaderValue;
use serde::Deserialize;
use serde_json::{json, Value};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt, BufReader},
    process::{Child, ChildStdin, ChildStdout, Command},
    time::timeout,
};

use crate::{
    ProviderId, ProviderQuotaSnapshot, QuotaError, QuotaErrorCode, QuotaProvider, QuotaWindow,
    RedactingHttpClient,
};

const USAGE_ENDPOINT: &str = "https://chatgpt.com/backend-api/wham/usage";
const APP_SERVER_DEADLINE: Duration = Duration::from_secs(20);
const MAX_RPC_MESSAGE_BYTES: usize = 64 * 1024;
const MAX_RPC_STDERR_BYTES: usize = 64 * 1024;

/// Source boundary used to test the authentication-to-RPC fallback policy
/// without reading a user's credentials or spawning their CLI.
#[async_trait]
pub trait CodexQuotaSource: Send + Sync {
    async fn fetch_from_auth(&self) -> Result<ProviderQuotaSnapshot, QuotaError>;
    async fn fetch_from_app_server(&self) -> Result<ProviderQuotaSnapshot, QuotaError>;
}

pub struct CodexQuotaProvider {
    source: Arc<dyn CodexQuotaSource>,
}

impl CodexQuotaProvider {
    pub fn new() -> Self {
        let config_dir = env::var_os("CODEX_HOME").map(PathBuf::from);
        let home_dir = env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("/nonexistent"));
        Self::from_paths(config_dir, home_dir, RedactingHttpClient::for_codex_usage())
    }

    pub fn from_paths(
        config_dir: Option<PathBuf>,
        home_dir: PathBuf,
        http: RedactingHttpClient,
    ) -> Self {
        Self::with_source(Arc::new(LocalCodexQuotaSource {
            config_dir: config_dir.filter(|path| !path.as_os_str().is_empty()),
            home_dir,
            http,
        }))
    }

    pub fn with_source(source: Arc<dyn CodexQuotaSource>) -> Self {
        Self { source }
    }

    pub fn parse_usage_payload(payload: &str) -> Result<ProviderQuotaSnapshot, QuotaError> {
        let value: Value = serde_json::from_str(payload).map_err(|_| schema_error())?;
        parse_rate_limits(&value)
    }
}

impl Default for CodexQuotaProvider {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl QuotaProvider for CodexQuotaProvider {
    async fn fetch(&self) -> Result<ProviderQuotaSnapshot, QuotaError> {
        match self.source.fetch_from_auth().await {
            Ok(snapshot) => Ok(snapshot),
            Err(error) if is_fallback_safe(&error) => self.source.fetch_from_app_server().await,
            Err(error) => Err(error),
        }
    }
}

fn is_fallback_safe(error: &QuotaError) -> bool {
    matches!(
        error.code,
        QuotaErrorCode::RequiresAuthentication | QuotaErrorCode::AuthenticationExpired
    )
}

struct LocalCodexQuotaSource {
    config_dir: Option<PathBuf>,
    home_dir: PathBuf,
    http: RedactingHttpClient,
}

#[async_trait]
impl CodexQuotaSource for LocalCodexQuotaSource {
    async fn fetch_from_auth(&self) -> Result<ProviderQuotaSnapshot, QuotaError> {
        let credentials = self.load_credentials()?;
        let request = self
            .http
            .get_bearer(USAGE_ENDPOINT, &credentials.access_token, &[])
            .map_err(codex_http_error)?;
        let response = self.http.send(request).await.map_err(codex_http_error)?;
        let bytes = self
            .http
            .read_limited_body(response)
            .await
            .map_err(codex_http_error)?;
        let payload = std::str::from_utf8(&bytes).map_err(|_| schema_error())?;
        CodexQuotaProvider::parse_usage_payload(payload)
    }

    async fn fetch_from_app_server(&self) -> Result<ProviderQuotaSnapshot, QuotaError> {
        match timeout(APP_SERVER_DEADLINE, self.fetch_from_app_server_bounded()).await {
            Ok(result) => result,
            Err(_) => Err(provider_unavailable()),
        }
    }
}

impl LocalCodexQuotaSource {
    fn credentials_path(&self) -> PathBuf {
        match &self.config_dir {
            Some(config_dir) => config_dir.join("auth.json"),
            None => self.home_dir.join(".codex/auth.json"),
        }
    }

    fn load_credentials(&self) -> Result<CodexOauthEvidence, QuotaError> {
        let contents = fs::read_to_string(self.credentials_path()).map_err(|_| auth_required())?;
        let credentials: CredentialsFile =
            serde_json::from_str(&contents).map_err(|_| auth_required())?;
        let oauth = credentials.tokens.unwrap_or(OAuthTokens {
            access_token: credentials.access_token,
            expires_at: credentials.expires_at,
        });
        let access_token = oauth
            .access_token
            .as_deref()
            .and_then(normalize_access_token)
            .ok_or_else(auth_required)?;

        if let Some(value) = oauth.expires_at.as_ref() {
            let expires_at = parse_expiry(value).ok_or_else(auth_required)?;
            if expires_at <= Utc::now() {
                return Err(auth_expired());
            }
        }

        Ok(CodexOauthEvidence { access_token })
    }

    async fn fetch_from_app_server_bounded(&self) -> Result<ProviderQuotaSnapshot, QuotaError> {
        let mut command = Command::new("codex");
        command
            .args(["-s", "read-only", "-a", "untrusted", "app-server"])
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .kill_on_drop(true)
            .env_clear();
        if let Some(path) = env::var_os("PATH") {
            command.env("PATH", path);
        }
        if let Some(home) = env::var_os("HOME") {
            command.env("HOME", home);
        }
        if let Some(config_dir) = &self.config_dir {
            command.env("CODEX_HOME", config_dir);
        }

        let mut child = command.spawn().map_err(|error| {
            if error.kind() == ErrorKind::NotFound {
                not_installed()
            } else {
                provider_unavailable()
            }
        })?;
        let stdin = child.stdin.take().ok_or_else(provider_unavailable)?;
        let stdout = child.stdout.take().ok_or_else(provider_unavailable)?;
        let stderr = child.stderr.take().ok_or_else(provider_unavailable)?;
        let stderr_reader = tokio::spawn(drain_stderr(stderr));
        let result = run_app_server_protocol(stdin, stdout).await;

        // The app server is a one-shot fallback. Always terminate it rather
        // than leaving a background process attached to Needlbar.
        stop_child(&mut child).await;
        let _ = stderr_reader.await;
        result
    }
}

#[derive(Deserialize)]
struct CredentialsFile {
    #[serde(default)]
    tokens: Option<OAuthTokens>,
    #[serde(default, alias = "accessToken")]
    access_token: Option<String>,
    #[serde(default, alias = "expiresAt")]
    expires_at: Option<Value>,
}

#[derive(Deserialize)]
struct OAuthTokens {
    #[serde(default, alias = "accessToken")]
    access_token: Option<String>,
    #[serde(default, alias = "expiresAt")]
    expires_at: Option<Value>,
}

struct CodexOauthEvidence {
    access_token: String,
}

fn parse_rate_limits(value: &Value) -> Result<ProviderQuotaSnapshot, QuotaError> {
    let rate_limit = value
        .get("rate_limit")
        .or_else(|| value.get("rateLimits"))
        .or_else(|| value.pointer("/result/rate_limit"))
        .or_else(|| value.pointer("/result/rateLimits"))
        .ok_or_else(schema_error)?;
    let primary = rate_limit
        .get("primary_window")
        .or_else(|| rate_limit.get("primaryWindow"))
        .or_else(|| rate_limit.get("primary"))
        .ok_or_else(schema_error)?;
    let secondary = rate_limit
        .get("secondary_window")
        .or_else(|| rate_limit.get("secondaryWindow"))
        .or_else(|| rate_limit.get("secondary"))
        .ok_or_else(schema_error)?;

    Ok(ProviderQuotaSnapshot {
        provider: ProviderId::Codex,
        windows: vec![
            parse_window(primary, "codex.primary", "Primary")?,
            parse_window(secondary, "codex.secondary", "Secondary")?,
        ],
    })
}

fn parse_window(value: &Value, id: &str, default_title: &str) -> Result<QuotaWindow, QuotaError> {
    let used_percent = number_field(value, &["used_percent", "usedPercent"])?;
    if let Some(remaining_percent) =
        optional_number_field(value, &["remaining_percent", "remainingPercent"])?
    {
        if ((used_percent + remaining_percent) - 100.0).abs() > f64::EPSILON {
            return Err(schema_error());
        }
    }
    let title = string_field(value, &["label", "title"]).unwrap_or(default_title);
    let resets_at = timestamp_field(value, &["reset_at", "resetAt", "resets_at", "resetsAt"])?;
    QuotaWindow::new(id, title, used_percent, Some(resets_at)).map_err(|_| schema_error())
}

fn number_field(value: &Value, names: &[&str]) -> Result<f64, QuotaError> {
    optional_number_field(value, names)?.ok_or_else(schema_error)
}

fn optional_number_field(value: &Value, names: &[&str]) -> Result<Option<f64>, QuotaError> {
    let Some(value) = names.iter().find_map(|name| value.get(*name)) else {
        return Ok(None);
    };
    value.as_f64().map(Some).ok_or_else(schema_error)
}

fn string_field<'a>(value: &'a Value, names: &[&str]) -> Option<&'a str> {
    names.iter().find_map(|name| value.get(*name)?.as_str())
}

fn timestamp_field(value: &Value, names: &[&str]) -> Result<DateTime<Utc>, QuotaError> {
    let value = names
        .iter()
        .find_map(|name| value.get(*name))
        .ok_or_else(schema_error)?;
    parse_timestamp(value).ok_or_else(schema_error)
}

fn parse_timestamp(value: &Value) -> Option<DateTime<Utc>> {
    match value {
        Value::String(value) => DateTime::parse_from_rfc3339(value)
            .map(|time| time.with_timezone(&Utc))
            .ok()
            .or_else(|| value.parse::<i64>().ok().and_then(epoch_to_utc)),
        Value::Number(value) => value.as_i64().and_then(epoch_to_utc),
        _ => None,
    }
}

fn parse_expiry(value: &Value) -> Option<DateTime<Utc>> {
    parse_timestamp(value)
}

fn epoch_to_utc(timestamp: i64) -> Option<DateTime<Utc>> {
    let seconds = if timestamp.unsigned_abs() > 100_000_000_000 {
        timestamp / 1_000
    } else {
        timestamp
    };
    Utc.timestamp_opt(seconds, 0).single()
}

async fn run_app_server_protocol(
    mut stdin: ChildStdin,
    stdout: ChildStdout,
) -> Result<ProviderQuotaSnapshot, QuotaError> {
    let mut stdout = BufReader::new(stdout);
    write_rpc_request(
        &mut stdin,
        1,
        "initialize",
        json!({
            "clientInfo": { "name": "needlbar", "version": "0.1.0" },
            "capabilities": {}
        }),
    )
    .await?;
    let _ = read_rpc_response(&mut stdout, 1).await?;
    write_rpc_notification(&mut stdin, "initialized", json!({})).await?;

    write_rpc_request(&mut stdin, 2, "account/read", json!({})).await?;
    let account = read_rpc_response(&mut stdout, 2).await?;
    if !account_is_signed_in(&account) {
        return Err(auth_required());
    }

    write_rpc_request(&mut stdin, 3, "account/rateLimits/read", json!({})).await?;
    let rate_limits = read_rpc_response(&mut stdout, 3).await?;
    parse_rate_limits(&rate_limits)
}

fn account_is_signed_in(account: &Value) -> bool {
    let account = account.get("account").unwrap_or(account);
    !account.is_null()
        && account
            .as_object()
            .is_some_and(|account| !account.is_empty())
        && account.get("type").is_none_or(|value| value != "none")
}

async fn write_rpc_request(
    stdin: &mut ChildStdin,
    id: u64,
    method: &str,
    params: Value,
) -> Result<(), QuotaError> {
    write_rpc_message(
        stdin,
        &json!({ "jsonrpc": "2.0", "id": id, "method": method, "params": params }),
    )
    .await
}

async fn write_rpc_notification(
    stdin: &mut ChildStdin,
    method: &str,
    params: Value,
) -> Result<(), QuotaError> {
    write_rpc_message(
        stdin,
        &json!({ "jsonrpc": "2.0", "method": method, "params": params }),
    )
    .await
}

async fn write_rpc_message(stdin: &mut ChildStdin, message: &Value) -> Result<(), QuotaError> {
    let mut bytes = serde_json::to_vec(message).map_err(|_| schema_error())?;
    bytes.push(b'\n');
    stdin
        .write_all(&bytes)
        .await
        .map_err(|_| provider_unavailable())?;
    stdin.flush().await.map_err(|_| provider_unavailable())
}

async fn read_rpc_response(
    stdout: &mut BufReader<ChildStdout>,
    expected_id: u64,
) -> Result<Value, QuotaError> {
    loop {
        let message = read_limited_line(stdout).await?;
        let value: Value = serde_json::from_slice(&message).map_err(|_| schema_error())?;
        if value.get("id").and_then(Value::as_u64) != Some(expected_id) {
            continue;
        }
        if value.get("error").is_some() {
            return Err(schema_error());
        }
        return value.get("result").cloned().ok_or_else(schema_error);
    }
}

async fn read_limited_line(stdout: &mut BufReader<ChildStdout>) -> Result<Vec<u8>, QuotaError> {
    let mut line = Vec::with_capacity(1024);
    let mut byte = [0_u8; 1];
    loop {
        let read = stdout
            .read(&mut byte)
            .await
            .map_err(|_| provider_unavailable())?;
        if read == 0 {
            return Err(schema_error());
        }
        if byte[0] == b'\n' {
            return Ok(line);
        }
        if line.len() == MAX_RPC_MESSAGE_BYTES {
            return Err(schema_error());
        }
        line.push(byte[0]);
    }
}

async fn drain_stderr(mut stderr: tokio::process::ChildStderr) -> Result<(), QuotaError> {
    let mut buffer = [0_u8; 4096];
    let mut total = 0_usize;
    loop {
        let read = stderr
            .read(&mut buffer)
            .await
            .map_err(|_| provider_unavailable())?;
        if read == 0 {
            return Ok(());
        }
        total = total.saturating_add(read);
        if total > MAX_RPC_STDERR_BYTES {
            return Err(schema_error());
        }
    }
}

async fn stop_child(child: &mut Child) {
    let _ = child.start_kill();
    let _ = child.wait().await;
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

fn codex_http_error(error: QuotaError) -> QuotaError {
    let message = match error.code {
        QuotaErrorCode::AuthenticationExpired => "Codex authentication has expired.",
        QuotaErrorCode::RateLimited => "The quota service asked us to retry later.",
        QuotaErrorCode::ServiceUnavailable | QuotaErrorCode::ProviderUnavailable => {
            "The quota service is temporarily unavailable."
        }
        QuotaErrorCode::SchemaChanged => "Codex quota data was not in the expected format.",
        _ => "The quota service could not be reached.",
    };
    QuotaError::new(Some(ProviderId::Codex), error.code, message)
        .with_retry_after(error.retry_after)
}

fn not_installed() -> QuotaError {
    QuotaError::new(
        Some(ProviderId::Codex),
        QuotaErrorCode::NotInstalled,
        "Codex CLI is not installed.",
    )
}

fn auth_required() -> QuotaError {
    QuotaError::new(
        Some(ProviderId::Codex),
        QuotaErrorCode::RequiresAuthentication,
        "Codex authentication was not available.",
    )
}

fn auth_expired() -> QuotaError {
    QuotaError::new(
        Some(ProviderId::Codex),
        QuotaErrorCode::AuthenticationExpired,
        "Codex authentication has expired.",
    )
}

fn provider_unavailable() -> QuotaError {
    QuotaError::new(
        Some(ProviderId::Codex),
        QuotaErrorCode::ProviderUnavailable,
        "Codex CLI did not respond in time.",
    )
}

fn schema_error() -> QuotaError {
    QuotaError::new(
        Some(ProviderId::Codex),
        QuotaErrorCode::SchemaChanged,
        "Codex quota data was not in the expected format.",
    )
}

#[cfg(test)]
mod tests {
    use std::fs;

    use tempfile::TempDir;

    use super::*;

    #[test]
    fn configured_codex_home_takes_precedence_over_home_directory() {
        let temp = TempDir::new().unwrap();
        let codex_home = temp.path().join("configured-codex");
        fs::create_dir_all(&codex_home).unwrap();
        fs::create_dir_all(temp.path().join(".codex")).unwrap();
        fs::write(
            codex_home.join("auth.json"),
            r#"{"tokens":{"access_token":"configured-token","expires_at":0}}"#,
        )
        .unwrap();
        fs::write(
            temp.path().join(".codex/auth.json"),
            r#"{"tokens":{"access_token":"home-token"}}"#,
        )
        .unwrap();
        let source = LocalCodexQuotaSource {
            config_dir: Some(codex_home),
            home_dir: temp.path().to_path_buf(),
            http: RedactingHttpClient::for_codex_usage(),
        };

        let error = match source.load_credentials() {
            Ok(_) => panic!("configured expired credentials must not use the home credentials"),
            Err(error) => error,
        };

        assert_eq!(error.code, QuotaErrorCode::AuthenticationExpired);
        assert!(!format!("{error:?}").contains("configured-token"));
    }

    #[test]
    fn app_server_account_result_must_contain_a_signed_in_account() {
        assert!(!account_is_signed_in(&json!({"account": null})));
        assert!(!account_is_signed_in(&json!({"type": "none"})));
        assert!(account_is_signed_in(
            &json!({"account": {"type": "chatgpt"}})
        ));
    }
}
