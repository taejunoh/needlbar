use std::{
    fs,
    sync::{Arc, Mutex},
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
const FABLE_SUCCESS_FIXTURE: &str =
    include_str!("../../../Fixtures/quota/claude/usage-fable-success.json");

fn fable_payload() -> serde_json::Value {
    serde_json::from_str(FABLE_SUCCESS_FIXTURE).unwrap()
}

struct RecordingResolver {
    accesses: Arc<Mutex<Vec<ClaudeCredentialAccess>>>,
    error: ClaudeCredentialError,
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
fn fable_is_an_additive_used_percent_window_even_when_inactive() {
    let snapshot = ClaudeQuotaProvider::parse_usage_payload(FABLE_SUCCESS_FIXTURE).unwrap();

    assert_eq!(snapshot.windows.len(), 3);
    assert_eq!(snapshot.windows[0].used_percent(), 42.5);
    assert_eq!(snapshot.windows[1].used_percent(), 80.0);
    let fable = &snapshot.windows[2];
    assert_eq!(fable.id(), "claude.fable.weekly");
    assert_eq!(fable.title(), "Fable weekly");
    assert_eq!(fable.used_percent(), 25.0);
    assert_eq!(fable.resets_at().unwrap().timestamp(), 1_896_829_200);
}

#[test]
fn malformed_or_unmatched_fable_preserves_both_base_windows() {
    use serde_json::{json, Value};

    let mut cases = Vec::new();
    let mut missing = fable_payload();
    missing.as_object_mut().unwrap().remove("limits");
    cases.push(missing);
    for limits in [
        Value::Null,
        json!({}),
        json!("invalid"),
        json!([]),
        json!([null]),
    ] {
        let mut payload = fable_payload();
        payload["limits"] = limits;
        cases.push(payload);
    }
    for (pointer, invalid) in [
        ("/limits/0/percent", json!(-1)),
        ("/limits/0/percent", json!(101)),
        ("/limits/0/percent", json!("25")),
        ("/limits/0/percent", Value::Null),
        ("/limits/0/resets_at", json!("not-a-date")),
        ("/limits/0/resets_at", json!(123)),
        ("/limits/0/kind", json!("weekly_all")),
        ("/limits/0/group", json!("session")),
        ("/limits/0/scope/model/display_name", json!("Omelette")),
        ("/limits/0/scope/surface", json!("cli")),
    ] {
        let mut payload = fable_payload();
        *payload.pointer_mut(pointer).unwrap() = invalid;
        cases.push(payload);
    }
    for (object, field) in [("/limits/0", "percent"), ("/limits/0/scope", "surface")] {
        let mut payload = fable_payload();
        payload
            .pointer_mut(object)
            .unwrap()
            .as_object_mut()
            .unwrap()
            .remove(field);
        cases.push(payload);
    }
    let mut duplicate = fable_payload();
    let entry = duplicate["limits"][0].clone();
    duplicate["limits"].as_array_mut().unwrap().push(entry);
    cases.push(duplicate);
    let mut duplicate_malformed = fable_payload();
    let mut malformed_entry = duplicate_malformed["limits"][0].clone();
    malformed_entry["percent"] = json!("25");
    duplicate_malformed["limits"]
        .as_array_mut()
        .unwrap()
        .push(malformed_entry);
    cases.push(duplicate_malformed);

    for (index, payload) in cases.into_iter().enumerate() {
        let snapshot = ClaudeQuotaProvider::parse_usage_payload(&payload.to_string()).unwrap();
        assert_eq!(snapshot.windows.len(), 2, "case {index}");
        assert_eq!(snapshot.windows[0].used_percent(), 42.5);
        assert_eq!(snapshot.windows[1].used_percent(), 80.0);
    }
}

#[test]
fn fable_unknown_reset_and_opaque_metadata_remain_valid() {
    for remove_reset in [false, true] {
        let mut payload = fable_payload();
        payload["limits"][0]["resets_at"] = serde_json::Value::Null;
        if remove_reset {
            payload["limits"][0]
                .as_object_mut()
                .unwrap()
                .remove("resets_at");
        }
        payload["limits"][0]["percent"] = serde_json::json!(0);
        payload["limits"][0]["scope"]["model"]["id"] = serde_json::json!("synthetic-opaque-id");
        payload["limits"][0]
            .as_object_mut()
            .unwrap()
            .remove("is_active");
        let snapshot = ClaudeQuotaProvider::parse_usage_payload(&payload.to_string()).unwrap();
        assert_eq!(snapshot.windows.len(), 3);
        assert_eq!(snapshot.windows[2].used_percent(), 0.0);
        assert_eq!(snapshot.windows[2].resets_at(), None);
    }
}

#[test]
fn optional_fable_does_not_relax_required_base_window_validation() {
    let mut payload = fable_payload();
    payload["five_hour"]["utilization"] = serde_json::json!(101);
    assert!(ClaudeQuotaProvider::parse_usage_payload(&payload.to_string()).is_err());
}

#[test]
fn accepts_null_session_reset_while_preserving_weekly_reset() {
    let snapshot = ClaudeQuotaProvider::parse_usage_payload(
        r#"{
          "five_hour": { "utilization": 42.5, "resets_at": null },
          "seven_day": { "utilization": 80.0, "resets_at": "2026-08-18T00:00:00Z" }
        }"#,
    )
    .unwrap();

    assert_eq!(snapshot.windows.len(), 2);
    assert_eq!(snapshot.windows[0].id(), "claude.session");
    assert_eq!(snapshot.windows[0].resets_at(), None);
    assert_eq!(snapshot.windows[1].id(), "claude.weekly");
    assert_eq!(
        snapshot.windows[1].resets_at(),
        Some(Utc.with_ymd_and_hms(2026, 8, 18, 0, 0, 0).unwrap())
    );
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
