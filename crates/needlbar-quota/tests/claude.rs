use std::fs;

use chrono::{TimeZone, Utc};
use needlbar_quota::{
    normalize_percent, ClaudeQuotaProvider, ProviderId, QuotaErrorCode, QuotaProvider,
    RedactingHttpClient,
};
use tempfile::TempDir;

const SUCCESS_FIXTURE: &str = include_str!("../../../Fixtures/quota/claude/usage-success.json");
const MALFORMED_FIXTURE: &str = include_str!("../../../Fixtures/quota/claude/usage-malformed.json");

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
fn parses_claude_session_and_weekly_windows_from_fixture() {
    let snapshot = ClaudeQuotaProvider::parse_usage_payload(SUCCESS_FIXTURE).unwrap();

    assert_eq!(snapshot.provider, ProviderId::Claude);
    assert_eq!(snapshot.windows.len(), 2);
    assert_eq!(snapshot.windows[0].id, "claude.session");
    assert_eq!(snapshot.windows[0].used_percent, 42.5);
    assert_eq!(
        snapshot.windows[0].resets_at,
        Some(Utc.with_ymd_and_hms(2026, 8, 14, 18, 0, 0).unwrap())
    );
    assert_eq!(snapshot.windows[1].id, "claude.weekly");
    assert_eq!(snapshot.windows[1].used_percent, 80.0);
}

#[test]
fn rejects_malformed_or_out_of_range_claude_payloads() {
    let error = ClaudeQuotaProvider::parse_usage_payload(MALFORMED_FIXTURE).unwrap_err();

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

#[test]
fn unsafe_endpoint_error_redacts_bearer_token_in_debug_output() {
    let token = "CLAUDE-CANARY-SECRET";
    let error = RedactingHttpClient::new()
        .get_bearer("https://example.invalid/api/oauth/usage", token, &[])
        .unwrap_err();

    assert!(!format!("{error:?}").contains(token));
    assert_eq!(error.code, QuotaErrorCode::NetworkUnavailable);
}
