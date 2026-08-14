use std::{env, fs, future::pending, io::ErrorKind, path::PathBuf, sync::Arc, time::Duration};

use async_trait::async_trait;
use chrono::{DateTime, TimeZone, Utc};
use reqwest::header::HeaderValue;
use serde::Deserialize;
use serde_json::{json, Value};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt, BufReader},
    process::{Child, ChildStdin, ChildStdout, Command},
    time::{timeout, timeout_at, Instant},
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
            app_server_program: PathBuf::from("codex"),
            app_server_deadline: APP_SERVER_DEADLINE,
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
    app_server_program: PathBuf,
    app_server_deadline: Duration,
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
        self.fetch_from_app_server_bounded().await
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
        let deadline = Instant::now() + self.app_server_deadline;
        let mut command = Command::new(&self.app_server_program);
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
        let mut stderr_reader = tokio::spawn(async move {
            match drain_stderr(stderr).await {
                Ok(()) => pending::<Result<(), QuotaError>>().await,
                Err(error) => Err(error),
            }
        });
        let protocol = run_app_server_protocol(stdin, stdout);
        tokio::pin!(protocol);
        let (result, stderr_finished) = match timeout_at(deadline, async {
            tokio::select! {
                result = &mut protocol => (result, false),
                result = &mut stderr_reader => (match result {
                    Ok(Err(error)) => Err(error),
                    Ok(Ok(())) => Err(provider_unavailable()),
                    Err(_) => Err(provider_unavailable()),
                }, true),
            }
        })
        .await
        {
            Ok((result, stderr_finished)) => (result, stderr_finished),
            Err(_) => (Err(provider_unavailable()), false),
        };

        // The app server is a one-shot fallback. Always terminate it rather
        // than leaving a background process attached to Needlbar.
        stop_child(&mut child, deadline).await;
        if !stderr_finished {
            stderr_reader.abort();
            let _ = stderr_reader.await;
        }
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
    let primary = optional_window(rate_limit, &["primary_window", "primaryWindow", "primary"])?;
    let secondary = optional_window(
        rate_limit,
        &["secondary_window", "secondaryWindow", "secondary"],
    )?;

    let mut windows = Vec::with_capacity(2);
    if let Some(primary) = primary {
        windows.push(parse_window(primary, "codex.primary", "Primary")?);
    }
    if let Some(secondary) = secondary {
        windows.push(parse_window(secondary, "codex.secondary", "Secondary")?);
    }

    Ok(ProviderQuotaSnapshot {
        provider: ProviderId::Codex,
        windows,
    })
}

fn optional_window<'a>(value: &'a Value, names: &[&str]) -> Result<Option<&'a Value>, QuotaError> {
    match names.iter().find_map(|name| value.get(*name)) {
        None | Some(Value::Null) => Ok(None),
        Some(window @ Value::Object(_)) => Ok(Some(window)),
        Some(_) => Err(schema_error()),
    }
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
    let resets_at =
        optional_timestamp_field(value, &["reset_at", "resetAt", "resets_at", "resetsAt"])?;
    QuotaWindow::new(id, title, used_percent, resets_at).map_err(|_| schema_error())
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

fn optional_timestamp_field(
    value: &Value,
    names: &[&str],
) -> Result<Option<DateTime<Utc>>, QuotaError> {
    match names.iter().find_map(|name| value.get(*name)) {
        None | Some(Value::Null) => Ok(None),
        Some(value) => parse_timestamp(value).map(Some).ok_or_else(schema_error),
    }
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
        Some(json!({
            "clientInfo": { "name": "needlbar", "version": "0.1.0" },
            "capabilities": {}
        })),
    )
    .await?;
    let _ = read_rpc_response(&mut stdout, 1).await?;
    write_rpc_notification(&mut stdin, "initialized", json!({})).await?;

    write_rpc_request(&mut stdin, 2, "account/read", None).await?;
    let account = read_rpc_response(&mut stdout, 2).await?;
    if !account_is_signed_in(&account) {
        return Err(auth_required());
    }

    write_rpc_request(&mut stdin, 3, "account/rateLimits/read", None).await?;
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
    params: Option<Value>,
) -> Result<(), QuotaError> {
    let mut message = json!({ "jsonrpc": "2.0", "id": id, "method": method });
    if let Some(params) = params {
        message["params"] = params;
    }
    write_rpc_message(stdin, &message).await
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

async fn stop_child(child: &mut Child, deadline: Instant) {
    let _ = child.start_kill();
    if timeout_at(deadline, child.wait()).await.is_err() {
        let _ = timeout(Duration::from_millis(250), child.wait()).await;
    }
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
    use std::{
        fs,
        os::unix::fs::PermissionsExt,
        path::Path,
        process::{Command as StdCommand, Stdio},
        time::{Duration, Instant},
    };

    use tempfile::TempDir;
    use tokio::time::sleep;

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
            app_server_program: PathBuf::from("codex"),
            app_server_deadline: APP_SERVER_DEADLINE,
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

    #[tokio::test]
    async fn app_server_transport_uses_the_documented_order_and_reaps_the_child() {
        let temp = TempDir::new().unwrap();
        let transcript = temp.path().join("transcript.jsonl");
        let pid_file = temp.path().join("child.pid");
        let contents = format!(
            "#!/bin/sh\nset -eu\n[ \"$1\" = \"-s\" ] && [ \"$2\" = \"read-only\" ] && [ \"$3\" = \"-a\" ] && [ \"$4\" = \"untrusted\" ] && [ \"$5\" = \"app-server\" ]\nprintf '%s\\n' \"$$\" > '{pid_file}'\nIFS= read -r line; printf '%s\\n' \"$line\" > '{transcript}'\nprintf '%s\\n' '{{\"jsonrpc\":\"2.0\",\"id\":99,\"result\":{{}}}}'\nprintf '%s\\n' '{{\"jsonrpc\":\"2.0\",\"method\":\"account/updated\",\"params\":{{}}}}'\nprintf '%s\\n' '{{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{{}}}}'\nIFS= read -r line; printf '%s\\n' \"$line\" >> '{transcript}'\nIFS= read -r line; printf '%s\\n' \"$line\" >> '{transcript}'\nprintf '%s\\n' '{{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{{\"account\":{{\"type\":\"chatgpt\"}}}}}}'\nIFS= read -r line; printf '%s\\n' \"$line\" >> '{transcript}'\nprintf '%s\\n' '{{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{{\"rateLimits\":{{\"primary\":{{\"usedPercent\":12,\"resetsAt\":null}},\"secondary\":null}}}}}}'\nsleep 10\n",
            pid_file = shell_path(&pid_file),
            transcript = shell_path(&transcript),
        );
        let source = test_source(
            write_script(temp.path(), "app-server.sh", &contents),
            Duration::from_secs(2),
        );

        let snapshot = source.fetch_from_app_server().await.unwrap();

        assert_eq!(snapshot.windows.len(), 1);
        assert_eq!(snapshot.windows[0].id(), "codex.primary");
        let messages: Vec<Value> = fs::read_to_string(&transcript)
            .unwrap()
            .lines()
            .map(|line| serde_json::from_str(line).unwrap())
            .collect();
        assert_eq!(messages.len(), 4);
        assert_eq!(messages[0]["id"], 1);
        assert_eq!(messages[0]["method"], "initialize");
        assert_eq!(messages[1]["method"], "initialized");
        assert!(messages[1].get("id").is_none());
        assert_eq!(messages[2]["id"], 2);
        assert_eq!(messages[2]["method"], "account/read");
        assert_eq!(messages[3]["id"], 3);
        assert_eq!(messages[3]["method"], "account/rateLimits/read");
        assert!(messages[3].get("params").is_none());
        assert_process_exits(&pid_file).await;
    }

    #[tokio::test]
    async fn app_server_timeout_kills_and_reaps_the_child() {
        let temp = TempDir::new().unwrap();
        let pid_file = temp.path().join("child.pid");
        let contents = format!(
            "#!/bin/sh\nprintf '%s\\n' \"$$\" > '{}'\nsleep 10\n",
            shell_path(&pid_file),
        );
        let source = test_source(
            write_script(temp.path(), "timeout.sh", &contents),
            Duration::from_secs(1),
        );
        let started = Instant::now();

        let error = source.fetch_from_app_server().await.unwrap_err();

        assert_eq!(error.code, QuotaErrorCode::ProviderUnavailable);
        assert!(started.elapsed() < Duration::from_secs(3));
        assert_process_exits(&pid_file).await;
    }

    #[tokio::test]
    async fn app_server_stderr_limit_fails_before_the_process_deadline() {
        let temp = TempDir::new().unwrap();
        let pid_file = temp.path().join("child.pid");
        let contents = format!(
            "#!/bin/sh\nprintf '%s\\n' \"$$\" > '{}'\nhead -c 65537 /dev/zero >&2\nsleep 10\n",
            shell_path(&pid_file),
        );
        let source = test_source(
            write_script(temp.path(), "stderr.sh", &contents),
            Duration::from_secs(2),
        );
        let started = Instant::now();

        let error = source.fetch_from_app_server().await.unwrap_err();

        assert_eq!(error.code, QuotaErrorCode::SchemaChanged);
        assert!(started.elapsed() < Duration::from_secs(1));
        assert_process_exits(&pid_file).await;
    }

    fn test_source(
        app_server_program: PathBuf,
        app_server_deadline: Duration,
    ) -> LocalCodexQuotaSource {
        LocalCodexQuotaSource {
            config_dir: None,
            home_dir: PathBuf::from("/nonexistent"),
            http: RedactingHttpClient::for_codex_usage(),
            app_server_program,
            app_server_deadline,
        }
    }

    fn write_script(directory: &Path, name: &str, contents: &str) -> PathBuf {
        let path = directory.join(name);
        fs::write(&path, contents).unwrap();
        let mut permissions = fs::metadata(&path).unwrap().permissions();
        permissions.set_mode(0o700);
        fs::set_permissions(&path, permissions).unwrap();
        path
    }

    fn shell_path(path: &Path) -> String {
        path.display().to_string().replace('\'', "'\\\"'\\\"'")
    }

    async fn assert_process_exits(pid_file: &Path) {
        let pid = fs::read_to_string(pid_file).unwrap();
        for _ in 0..20 {
            let status = StdCommand::new("kill")
                .args(["-0", pid.trim()])
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .unwrap();
            if !status.success() {
                return;
            }
            sleep(Duration::from_millis(25)).await;
        }
        panic!("scripted app-server process was still running");
    }
}
