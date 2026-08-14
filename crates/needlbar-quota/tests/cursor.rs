use std::sync::Arc;

use async_trait::async_trait;
use chrono::{TimeZone, Utc};
use needlbar_quota::{
    CursorQuotaProvider, CursorQuotaSource, ProviderId, QuotaAction, QuotaError, QuotaErrorCode,
    QuotaProvider,
};
use needlbar_source_sync::{CursorSession, CursorSessionStore};
use tempfile::TempDir;

const SUCCESS_FIXTURE: &str =
    include_str!("../../../Fixtures/quota/cursor/usage-summary-success.json");
const INVALID_FIXTURE: &str =
    include_str!("../../../Fixtures/quota/cursor/usage-summary-invalid.json");

#[test]
fn parses_cursor_usage_summary_into_bounded_quota_windows() {
    let snapshot = CursorQuotaProvider::parse_usage_payload(SUCCESS_FIXTURE).unwrap();

    assert_eq!(snapshot.provider, ProviderId::Cursor);
    assert_eq!(snapshot.windows.len(), 2);
    assert_eq!(snapshot.windows[0].id(), "cursor.plan");
    assert_eq!(snapshot.windows[0].used_percent(), 35.0);
    assert_eq!(
        snapshot.windows[0].resets_at(),
        Some(Utc.with_ymd_and_hms(2026, 9, 1, 0, 0, 0).unwrap())
    );
    assert_eq!(snapshot.windows[1].id(), "cursor.onDemand");
    assert_eq!(snapshot.windows[1].used_percent(), 20.0);
}

#[test]
fn missing_cursor_billing_cycle_end_remains_unknown() {
    let snapshot = CursorQuotaProvider::parse_usage_payload(
        r#"{
          "individualUsage": {
            "plan": { "enabled": true, "used": 1, "limit": 4, "remaining": 3 }
          }
        }"#,
    )
    .unwrap();

    assert_eq!(snapshot.windows.len(), 1);
    assert_eq!(snapshot.windows[0].resets_at(), None);
}

#[test]
fn rejects_cursor_usage_summary_with_invalid_percentages() {
    let error = CursorQuotaProvider::parse_usage_payload(INVALID_FIXTURE).unwrap_err();

    assert_eq!(error.code, QuotaErrorCode::SchemaChanged);
    assert!(serde_json::to_value(error).unwrap().get("action").is_none());
}

#[tokio::test]
async fn fetches_cursor_quota_from_the_shared_rust_owned_session_store() {
    let home = TempDir::new().unwrap();
    let store = CursorSessionStore::in_home(home.path());
    store
        .save(&CursorSession::new("cursor-test-session").unwrap())
        .unwrap();
    let provider = CursorQuotaProvider::with_source(
        store,
        Arc::new(FixtureSource(Ok(SUCCESS_FIXTURE.to_owned()))),
    );

    let snapshot = provider.fetch().await.unwrap();

    assert_eq!(snapshot.provider, ProviderId::Cursor);
    assert_eq!(snapshot.windows.len(), 2);
}

#[tokio::test]
async fn missing_cursor_session_requires_explicit_connect_action() {
    let home = TempDir::new().unwrap();
    let provider = CursorQuotaProvider::with_source(
        CursorSessionStore::in_home(home.path()),
        Arc::new(FixtureSource(Ok(SUCCESS_FIXTURE.to_owned()))),
    );

    let error = provider.fetch().await.unwrap_err();

    assert_eq!(error.code, QuotaErrorCode::RequiresAuthentication);
    assert_eq!(error.action, Some(QuotaAction::ConnectCursor));
    let value = serde_json::to_value(error).unwrap();
    assert_eq!(value["action"], "connectCursor");
}

#[tokio::test]
async fn expired_cursor_transport_session_requires_explicit_reconnection() {
    let home = TempDir::new().unwrap();
    let store = CursorSessionStore::in_home(home.path());
    store
        .save(&CursorSession::new("cursor-test-session").unwrap())
        .unwrap();
    let provider = CursorQuotaProvider::with_source(
        store,
        Arc::new(FixtureSource(Err(QuotaError {
            provider: None,
            code: QuotaErrorCode::AuthenticationExpired,
            message: "The quota service rejected the session.",
            retry_after: None,
            action: None,
        }))),
    );

    let error = provider.fetch().await.unwrap_err();

    assert_eq!(error.code, QuotaErrorCode::RequiresAuthentication);
    assert_eq!(error.action, Some(QuotaAction::ConnectCursor));
}

#[cfg(unix)]
#[tokio::test]
async fn unsafe_cursor_session_storage_does_not_offer_a_connect_action() {
    use std::{fs, os::unix::fs::symlink};

    let home = TempDir::new().unwrap();
    let outside = TempDir::new().unwrap();
    let parent = home.path().join("Library/Application Support");
    fs::create_dir_all(&parent).unwrap();
    symlink(outside.path(), parent.join("Needlbar")).unwrap();
    let provider = CursorQuotaProvider::with_source(
        CursorSessionStore::in_home(home.path()),
        Arc::new(FixtureSource(Ok(SUCCESS_FIXTURE.to_owned()))),
    );

    let error = provider.fetch().await.unwrap_err();

    assert_eq!(error.code, QuotaErrorCode::ProviderUnavailable);
    assert_eq!(error.action, None);
}

struct FixtureSource(Result<String, QuotaError>);

#[async_trait]
impl CursorQuotaSource for FixtureSource {
    async fn fetch_usage_summary(&self, _session_token: &str) -> Result<String, QuotaError> {
        self.0.clone()
    }
}
