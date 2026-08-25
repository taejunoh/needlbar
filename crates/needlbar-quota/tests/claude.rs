use std::{
    fs,
    io::{Read, Write},
    net::TcpListener,
    sync::{Arc, Mutex},
    thread,
};

use chrono::{TimeZone, Utc};
use needlbar_quota::{
    normalize_percent, ClaudeCredentialAccess, ClaudeCredentialError, ClaudeCredentialResolver,
    ClaudeOAuthSecret, ClaudeQuotaProvider, FileClaudeCredentialResolver, ProviderId,
    QuotaErrorCode, QuotaProvider, QuotaWindow, RedactingHttpClient,
};
use tempfile::TempDir;

const SUCCESS_FIXTURE: &str = include_str!("../../../Fixtures/quota/claude/usage-success.json");
const MALFORMED_FIXTURE: &str = include_str!("../../../Fixtures/quota/claude/usage-malformed.json");

struct RecordingResolver {
    accesses: Arc<Mutex<Vec<ClaudeCredentialAccess>>>,
    error: ClaudeCredentialError,
}

struct CanaryFileResolver {
    accesses: Arc<Mutex<Vec<ClaudeCredentialAccess>>>,
    file: FileClaudeCredentialResolver,
}

impl ClaudeCredentialResolver for CanaryFileResolver {
    fn resolve(
        &self,
        access: ClaudeCredentialAccess,
    ) -> Result<ClaudeOAuthSecret, ClaudeCredentialError> {
        self.accesses.lock().unwrap().push(access);
        self.file.resolve(access)
    }
}

impl RecordingResolver {
    fn failing(
        accesses: Arc<Mutex<Vec<ClaudeCredentialAccess>>>,
        error: ClaudeCredentialError,
    ) -> Self {
        Self { accesses, error }
    }
}

impl ClaudeCredentialResolver for RecordingResolver {
    fn resolve(
        &self,
        access: ClaudeCredentialAccess,
    ) -> Result<ClaudeOAuthSecret, ClaudeCredentialError> {
        self.accesses.lock().unwrap().push(access);
        Err(self.error)
    }
}

fn provider_with_resolver(resolver: Arc<dyn ClaudeCredentialResolver>) -> ClaudeQuotaProvider {
    ClaudeQuotaProvider::with_resolver(resolver, RedactingHttpClient::new())
}

#[tokio::test]
async fn background_fetch_forbids_keychain_interaction() {
    let accesses = Arc::new(Mutex::new(Vec::new()));
    let provider = provider_with_resolver(Arc::new(RecordingResolver::failing(
        Arc::clone(&accesses),
        ClaudeCredentialError::NotFound,
    )));

    let error = provider.fetch().await.unwrap_err();

    assert_eq!(
        accesses.lock().unwrap().as_slice(),
        [ClaudeCredentialAccess::BackgroundNoUI]
    );
    assert_eq!(error.code, QuotaErrorCode::RequiresAuthentication);
}

#[tokio::test]
async fn user_initiated_fetch_allows_keychain_interaction() {
    let accesses = Arc::new(Mutex::new(Vec::new()));
    let provider = provider_with_resolver(Arc::new(RecordingResolver::failing(
        Arc::clone(&accesses),
        ClaudeCredentialError::NotFound,
    )));

    let error = provider
        .fetch_with_credential_access(ClaudeCredentialAccess::UserInitiatedAllowUI)
        .await
        .unwrap_err();

    assert_eq!(
        accesses.lock().unwrap().as_slice(),
        [ClaudeCredentialAccess::UserInitiatedAllowUI]
    );
    assert_eq!(error.code, QuotaErrorCode::RequiresAuthentication);
}

#[tokio::test]
async fn credential_failures_map_to_safe_quota_errors() {
    let cases = [
        (
            ClaudeCredentialError::NotFound,
            QuotaErrorCode::RequiresAuthentication,
        ),
        (
            ClaudeCredentialError::InteractionNotAllowed,
            QuotaErrorCode::PermissionDenied,
        ),
        (
            ClaudeCredentialError::PermissionDenied,
            QuotaErrorCode::PermissionDenied,
        ),
        (
            ClaudeCredentialError::Cancelled,
            QuotaErrorCode::PermissionDenied,
        ),
        (
            ClaudeCredentialError::Expired,
            QuotaErrorCode::AuthenticationExpired,
        ),
        (
            ClaudeCredentialError::Malformed,
            QuotaErrorCode::SchemaChanged,
        ),
    ];

    for (credential_error, expected_code) in cases {
        let provider = provider_with_resolver(Arc::new(RecordingResolver::failing(
            Arc::new(Mutex::new(Vec::new())),
            credential_error,
        )));
        let error = provider.fetch().await.unwrap_err();

        assert_eq!(error.code, expected_code);
    }
}

#[tokio::test]
async fn injected_file_resolver_preserves_legacy_credentials() {
    let temp = TempDir::new().unwrap();
    let config_dir = temp.path().join("claude-config");
    fs::create_dir_all(&config_dir).unwrap();
    fs::write(
        config_dir.join(".credentials.json"),
        r#"{"claudeAiOauth":{"accessToken":"legacy-token"}}"#,
    )
    .unwrap();
    let resolver =
        FileClaudeCredentialResolver::from_paths(Some(config_dir), temp.path().to_path_buf());
    let result = resolver.resolve(ClaudeCredentialAccess::BackgroundNoUI);

    assert!(result.is_ok());
}

#[tokio::test]
async fn safe_credential_errors_never_expose_a_keychain_canary() {
    let canary = "CLAUDE-KEYCHAIN-CANARY";
    let errors = [
        ClaudeCredentialError::NotFound,
        ClaudeCredentialError::InteractionNotAllowed,
        ClaudeCredentialError::PermissionDenied,
        ClaudeCredentialError::Cancelled,
        ClaudeCredentialError::Expired,
        ClaudeCredentialError::Malformed,
    ];

    for credential_error in errors {
        let provider = provider_with_resolver(Arc::new(RecordingResolver::failing(
            Arc::new(Mutex::new(Vec::new())),
            credential_error,
        )));
        let error = provider.fetch().await.unwrap_err();

        assert!(!format!("{error:?}").contains(canary));
        assert!(!serde_json::to_string(&error).unwrap().contains(canary));
    }
}

#[tokio::test]
async fn parser_canary_reaches_local_bearer_request_but_not_success_or_failure_surfaces() {
    let canary = "CLAUDE-KEYCHAIN-CANARY";
    let temp = TempDir::new().unwrap();
    let config_dir = temp.path().join("claude-config");
    fs::create_dir_all(&config_dir).unwrap();
    fs::write(
        config_dir.join(".credentials.json"),
        format!(r#"{{"claudeAiOauth":{{"accessToken":"{canary}"}}}}"#),
    )
    .unwrap();
    let accesses = Arc::new(Mutex::new(Vec::new()));

    let success_response = format!(
        "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        SUCCESS_FIXTURE.len(),
        SUCCESS_FIXTURE
    )
    .into_bytes();
    let (success_endpoint, success_server) = capturing_local_server(success_response);
    let success_provider = ClaudeQuotaProvider::with_resolver_and_test_endpoint(
        Arc::new(CanaryFileResolver {
            accesses: Arc::clone(&accesses),
            file: FileClaudeCredentialResolver::from_paths(
                Some(config_dir.clone()),
                temp.path().to_path_buf(),
            ),
        }),
        &success_endpoint,
    )
    .unwrap();

    let snapshot = success_provider
        .fetch_with_credential_access(ClaudeCredentialAccess::UserInitiatedAllowUI)
        .await
        .unwrap();
    let success_request = String::from_utf8(success_server.join().unwrap()).unwrap();

    assert!(success_request.contains(canary));
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
    let failure_provider = ClaudeQuotaProvider::with_resolver_and_test_endpoint(
        Arc::new(CanaryFileResolver {
            accesses: Arc::clone(&accesses),
            file: FileClaudeCredentialResolver::from_paths(
                Some(config_dir),
                temp.path().to_path_buf(),
            ),
        }),
        &failure_endpoint,
    )
    .unwrap();

    let error = failure_provider
        .fetch_with_credential_access(ClaudeCredentialAccess::UserInitiatedAllowUI)
        .await
        .unwrap_err();
    let failure_request = String::from_utf8(failure_server.join().unwrap()).unwrap();

    assert!(failure_request.contains(canary));
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
fn normalizes_only_finite_percentages_in_range() {
    assert_eq!(normalize_percent(42.5).unwrap(), 42.5);
    assert_eq!(
        normalize_percent(-0.1).unwrap_err().code,
        QuotaErrorCode::SchemaChanged
    );
    assert_eq!(
        normalize_percent(100.1).unwrap_err().code,
        QuotaErrorCode::SchemaChanged
    );
    assert_eq!(
        normalize_percent(f64::NAN).unwrap_err().code,
        QuotaErrorCode::SchemaChanged
    );
}

#[test]
fn quota_window_constructor_preserves_the_percent_invariant() {
    let error = QuotaWindow::new("test", "Test", 100.1, None).unwrap_err();
    assert_eq!(error.code, QuotaErrorCode::SchemaChanged);

    let window = QuotaWindow::new("test", "Test", 42.5, None).unwrap();
    assert_eq!(window.used_percent(), 42.5);
    assert_eq!(window.id(), "test");
}

#[test]
fn parses_claude_session_and_weekly_windows_from_fixture() {
    let snapshot = ClaudeQuotaProvider::parse_usage_payload(SUCCESS_FIXTURE).unwrap();

    assert_eq!(snapshot.provider, ProviderId::Claude);
    assert_eq!(snapshot.windows.len(), 2);
    assert_eq!(snapshot.windows[0].id(), "claude.session");
    assert_eq!(snapshot.windows[0].used_percent(), 42.5);
    assert_eq!(
        snapshot.windows[0].resets_at(),
        Some(Utc.with_ymd_and_hms(2026, 8, 14, 18, 0, 0).unwrap())
    );
    assert_eq!(snapshot.windows[1].id(), "claude.weekly");
    assert_eq!(snapshot.windows[1].used_percent(), 80.0);
}

#[test]
fn rejects_malformed_or_out_of_range_claude_payloads() {
    let error = ClaudeQuotaProvider::parse_usage_payload(MALFORMED_FIXTURE).unwrap_err();

    assert_eq!(error.code, QuotaErrorCode::SchemaChanged);
}

#[test]
fn rejects_claude_payloads_without_provider_reset_evidence() {
    let error = ClaudeQuotaProvider::parse_usage_payload(
        r#"{
          "five_hour": { "utilization": 42.5 },
          "seven_day": { "utilization": 80.0, "resets_at": "2026-08-18T00:00:00Z" }
        }"#,
    )
    .unwrap_err();

    assert_eq!(error.code, QuotaErrorCode::SchemaChanged);
}

#[test]
fn rejects_claude_payloads_with_malformed_provider_reset_evidence() {
    let error = ClaudeQuotaProvider::parse_usage_payload(
        r#"{
          "five_hour": { "utilization": 42.5, "resets_at": "not-a-timestamp" },
          "seven_day": { "utilization": 80.0, "resets_at": "2026-08-18T00:00:00Z" }
        }"#,
    )
    .unwrap_err();

    assert_eq!(error.code, QuotaErrorCode::SchemaChanged);
}

#[tokio::test]
async fn missing_file_oauth_requires_authentication_without_prompting() {
    let empty_home = TempDir::new().unwrap();
    let provider = ClaudeQuotaProvider::from_paths(
        Some(empty_home.path().join("configured")),
        empty_home.path().to_path_buf(),
        RedactingHttpClient::new(),
    );

    let error = provider.fetch().await.unwrap_err();

    assert_eq!(error.code, QuotaErrorCode::RequiresAuthentication);
}

#[tokio::test]
async fn known_expired_file_oauth_is_reported_as_expired() {
    let temp = TempDir::new().unwrap();
    let config_dir = temp.path().join("claude-config");
    fs::create_dir_all(&config_dir).unwrap();
    fs::write(
        config_dir.join(".credentials.json"),
        r#"{"claudeAiOauth":{"accessToken":"test-token","expiresAt":0}}"#,
    )
    .unwrap();
    let provider = ClaudeQuotaProvider::from_paths(
        Some(config_dir),
        temp.path().to_path_buf(),
        RedactingHttpClient::new(),
    );

    let error = provider.fetch().await.unwrap_err();

    assert_eq!(error.code, QuotaErrorCode::AuthenticationExpired);
}

#[tokio::test]
async fn configured_credentials_take_precedence_over_home_credentials() {
    let temp = TempDir::new().unwrap();
    let config_dir = temp.path().join("claude-config");
    let home_credentials = temp.path().join(".claude/.credentials.json");
    fs::create_dir_all(&config_dir).unwrap();
    fs::create_dir_all(home_credentials.parent().unwrap()).unwrap();
    fs::write(
        config_dir.join(".credentials.json"),
        r#"{"claudeAiOauth":{"accessToken":"configured-token","expiresAt":0}}"#,
    )
    .unwrap();
    fs::write(
        home_credentials,
        r#"{"claudeAiOauth":{"accessToken":"home-token"}}"#,
    )
    .unwrap();
    let provider = ClaudeQuotaProvider::from_paths(
        Some(config_dir),
        temp.path().to_path_buf(),
        RedactingHttpClient::new(),
    );

    let error = provider.fetch().await.unwrap_err();

    assert_eq!(error.code, QuotaErrorCode::AuthenticationExpired);
}

#[tokio::test]
async fn empty_config_directory_is_treated_as_absent_not_a_relative_path() {
    let temp = TempDir::new().unwrap();
    let home_credentials = temp.path().join(".claude/.credentials.json");
    fs::create_dir_all(home_credentials.parent().unwrap()).unwrap();
    fs::write(
        home_credentials,
        r#"{"claudeAiOauth":{"accessToken":"home-token","expiresAt":0}}"#,
    )
    .unwrap();
    let provider = ClaudeQuotaProvider::from_paths(
        Some(std::path::PathBuf::new()),
        temp.path().to_path_buf(),
        RedactingHttpClient::new(),
    );

    let error = provider.fetch().await.unwrap_err();

    assert_eq!(error.code, QuotaErrorCode::AuthenticationExpired);
}

#[test]
fn unsafe_endpoint_error_redacts_bearer_token_in_debug_output() {
    let token = "CLAUDE-CANARY-SECRET";
    let error = RedactingHttpClient::new()
        .get_bearer("https://example.invalid/api/oauth/usage", token, &[])
        .unwrap_err();

    assert!(!format!("{error:?}").contains(token));
    assert_eq!(error.code, QuotaErrorCode::NetworkUnavailable);
}
