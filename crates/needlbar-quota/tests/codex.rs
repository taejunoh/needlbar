use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Arc,
};

use async_trait::async_trait;
use chrono::{TimeZone, Utc};
use needlbar_quota::{
    CodexQuotaProvider, CodexQuotaSource, ProviderId, ProviderQuotaSnapshot, QuotaError,
    QuotaErrorCode, QuotaProvider, QuotaWindow,
};

const SUCCESS_FIXTURE: &str =
    include_str!("../../../Fixtures/quota/codex/rate-limits-success.json");
const INVALID_FIXTURE: &str =
    include_str!("../../../Fixtures/quota/codex/rate-limits-invalid.json");

#[test]
fn parses_codex_primary_and_secondary_windows_from_fixture() {
    let snapshot = CodexQuotaProvider::parse_usage_payload(SUCCESS_FIXTURE).unwrap();

    assert_eq!(snapshot.provider, ProviderId::Codex);
    assert_eq!(snapshot.windows.len(), 2);
    assert_eq!(snapshot.windows[0].id(), "codex.primary");
    assert_eq!(snapshot.windows[0].title(), "5-hour limit");
    assert_eq!(snapshot.windows[0].used_percent(), 25.0);
    assert_eq!(
        snapshot.windows[0].resets_at(),
        Some(Utc.timestamp_opt(1_786_723_200, 0).unwrap())
    );
    assert_eq!(snapshot.windows[1].id(), "codex.secondary");
    assert_eq!(snapshot.windows[1].title(), "Weekly limit");
    assert_eq!(snapshot.windows[1].used_percent(), 60.0);
    assert_eq!(
        snapshot.windows[1].resets_at(),
        Some(Utc.with_ymd_and_hms(2026, 8, 18, 0, 0, 0).unwrap())
    );
}

#[test]
fn rejects_codex_window_with_contradictory_used_and_remaining_percentages() {
    let error = CodexQuotaProvider::parse_usage_payload(INVALID_FIXTURE).unwrap_err();

    assert_eq!(error.code, QuotaErrorCode::SchemaChanged);
}

#[tokio::test]
async fn falls_back_to_app_server_for_authentication_failure() {
    let snapshot = successful_snapshot();
    let source = TestSource::new(Err(auth_error()), Ok(snapshot.clone()));
    let provider = CodexQuotaProvider::with_source(Arc::new(source.clone()));

    assert_eq!(provider.fetch().await.unwrap(), snapshot);
    assert_eq!(source.auth_calls.load(Ordering::SeqCst), 1);
    assert_eq!(source.app_server_calls.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn does_not_mask_rate_limit_with_app_server_fallback() {
    let source = TestSource::new(Err(rate_limited_error()), Ok(successful_snapshot()));
    let provider = CodexQuotaProvider::with_source(Arc::new(source.clone()));

    let error = provider.fetch().await.unwrap_err();

    assert_eq!(error.code, QuotaErrorCode::RateLimited);
    assert_eq!(source.auth_calls.load(Ordering::SeqCst), 1);
    assert_eq!(source.app_server_calls.load(Ordering::SeqCst), 0);
}

fn successful_snapshot() -> ProviderQuotaSnapshot {
    ProviderQuotaSnapshot {
        provider: ProviderId::Codex,
        windows: vec![QuotaWindow::new("codex.primary", "5-hour limit", 25.0, None).unwrap()],
    }
}

fn auth_error() -> QuotaError {
    QuotaError {
        provider: Some(ProviderId::Codex),
        code: QuotaErrorCode::RequiresAuthentication,
        message: "Codex authentication was not available.",
        retry_after: None,
    }
}

fn rate_limited_error() -> QuotaError {
    QuotaError {
        provider: Some(ProviderId::Codex),
        code: QuotaErrorCode::RateLimited,
        message: "The quota service asked us to retry later.",
        retry_after: None,
    }
}

#[derive(Clone)]
struct TestSource {
    auth: Result<ProviderQuotaSnapshot, QuotaError>,
    app_server: Result<ProviderQuotaSnapshot, QuotaError>,
    auth_calls: Arc<AtomicUsize>,
    app_server_calls: Arc<AtomicUsize>,
}

impl TestSource {
    fn new(
        auth: Result<ProviderQuotaSnapshot, QuotaError>,
        app_server: Result<ProviderQuotaSnapshot, QuotaError>,
    ) -> Self {
        Self {
            auth,
            app_server,
            auth_calls: Arc::new(AtomicUsize::new(0)),
            app_server_calls: Arc::new(AtomicUsize::new(0)),
        }
    }
}

#[async_trait]
impl CodexQuotaSource for TestSource {
    async fn fetch_from_auth(&self) -> Result<ProviderQuotaSnapshot, QuotaError> {
        self.auth_calls.fetch_add(1, Ordering::SeqCst);
        self.auth.clone()
    }

    async fn fetch_from_app_server(&self) -> Result<ProviderQuotaSnapshot, QuotaError> {
        self.app_server_calls.fetch_add(1, Ordering::SeqCst);
        self.app_server.clone()
    }
}
