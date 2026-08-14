use std::sync::Arc;

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use needlbar_source_sync::{CursorSessionStore, SourceSyncError};
use serde::Deserialize;

use crate::{
    ProviderId, ProviderQuotaSnapshot, QuotaAction, QuotaError, QuotaErrorCode, QuotaProvider,
    QuotaWindow, RedactingHttpClient,
};

const USAGE_SUMMARY_ENDPOINT: &str = "https://cursor.com/api/usage-summary";
const SESSION_COOKIE_NAME: &str = "WorkosCursorSessionToken";

#[async_trait]
pub trait CursorQuotaSource: Send + Sync {
    async fn fetch_usage_summary(&self, session_token: &str) -> Result<String, QuotaError>;
}

pub struct CursorQuotaProvider {
    store: CursorSessionStore,
    source: Arc<dyn CursorQuotaSource>,
}

impl CursorQuotaProvider {
    pub fn new() -> Self {
        let store = CursorSessionStore::new()
            .unwrap_or_else(|_| CursorSessionStore::in_home(std::path::Path::new("/nonexistent")));
        Self::with_source(store, Arc::new(LocalCursorQuotaSource::new()))
    }

    pub fn with_source(store: CursorSessionStore, source: Arc<dyn CursorQuotaSource>) -> Self {
        Self { store, source }
    }

    pub fn parse_usage_payload(payload: &str) -> Result<ProviderQuotaSnapshot, QuotaError> {
        let summary: UsageSummary = serde_json::from_str(payload).map_err(|_| schema_error())?;
        let mut windows = Vec::with_capacity(2);

        if let Some(pool) = summary.individual_usage.plan {
            if let Some(window) = parse_pool(
                pool,
                "cursor.plan",
                "Cursor Models",
                summary.billing_cycle_end,
            )? {
                windows.push(window);
            }
        }
        if let Some(pool) = summary.individual_usage.on_demand {
            if let Some(window) = parse_pool(
                pool,
                "cursor.onDemand",
                "On-Demand",
                summary.billing_cycle_end,
            )? {
                windows.push(window);
            }
        }

        Ok(ProviderQuotaSnapshot {
            provider: ProviderId::Cursor,
            windows,
        })
    }

    pub async fn verify_session_token(&self, session_token: &str) -> Result<(), QuotaError> {
        let payload = self
            .source
            .fetch_usage_summary(session_token)
            .await
            .map_err(cursor_http_error)?;
        Self::parse_usage_payload(&payload).map(|_| ())
    }
}

impl Default for CursorQuotaProvider {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl QuotaProvider for CursorQuotaProvider {
    async fn fetch(&self) -> Result<ProviderQuotaSnapshot, QuotaError> {
        let session = self.store.load().map_err(cursor_session_error)?;
        let payload = self
            .source
            .fetch_usage_summary(session.session_token())
            .await
            .map_err(cursor_http_error)?;
        Self::parse_usage_payload(&payload)
    }
}

struct LocalCursorQuotaSource {
    http: RedactingHttpClient,
}

impl LocalCursorQuotaSource {
    fn new() -> Self {
        Self {
            http: RedactingHttpClient::for_cursor_usage(),
        }
    }
}

#[async_trait]
impl CursorQuotaSource for LocalCursorQuotaSource {
    async fn fetch_usage_summary(&self, session_token: &str) -> Result<String, QuotaError> {
        let request = self
            .http
            .get_cookie(
                USAGE_SUMMARY_ENDPOINT,
                SESSION_COOKIE_NAME,
                session_token,
                &[],
            )
            .map_err(cursor_http_error)?;
        let response = self.http.send(request).await.map_err(cursor_http_error)?;
        let bytes = self
            .http
            .read_limited_body(response)
            .await
            .map_err(cursor_http_error)?;
        String::from_utf8(bytes).map_err(|_| schema_error())
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct UsageSummary {
    #[serde(default)]
    billing_cycle_end: Option<DateTime<Utc>>,
    individual_usage: IndividualUsage,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct IndividualUsage {
    #[serde(default)]
    plan: Option<UsagePool>,
    #[serde(default)]
    on_demand: Option<UsagePool>,
}

#[derive(Deserialize)]
struct UsagePool {
    enabled: bool,
    used: f64,
    limit: f64,
    remaining: f64,
}

fn parse_pool(
    pool: UsagePool,
    id: &str,
    title: &str,
    resets_at: Option<DateTime<Utc>>,
) -> Result<Option<QuotaWindow>, QuotaError> {
    if !pool.enabled {
        return Ok(None);
    }
    if !pool.used.is_finite()
        || !pool.limit.is_finite()
        || !pool.remaining.is_finite()
        || pool.used < 0.0
        || pool.limit <= 0.0
        || pool.remaining < 0.0
        || ((pool.used + pool.remaining) - pool.limit).abs() > f64::EPSILON
    {
        return Err(schema_error());
    }
    QuotaWindow::new(id, title, pool.used * 100.0 / pool.limit, resets_at)
        .map(Some)
        .map_err(|_| schema_error())
}

fn schema_error() -> QuotaError {
    QuotaError::new(
        Some(ProviderId::Cursor),
        QuotaErrorCode::SchemaChanged,
        "Cursor quota data was not in the expected format.",
    )
}

fn requires_authentication() -> QuotaError {
    QuotaError::new(
        Some(ProviderId::Cursor),
        QuotaErrorCode::RequiresAuthentication,
        "Cursor authentication was not available.",
    )
    .with_action(QuotaAction::ConnectCursor)
}

fn cursor_http_error(error: QuotaError) -> QuotaError {
    if matches!(
        error.code,
        QuotaErrorCode::AuthenticationExpired | QuotaErrorCode::RequiresAuthentication
    ) {
        requires_authentication()
    } else {
        error.for_provider(ProviderId::Cursor)
    }
}

fn cursor_session_error(error: SourceSyncError) -> QuotaError {
    match error {
        SourceSyncError::MissingSession
        | SourceSyncError::InvalidSession
        | SourceSyncError::SessionTooLarge => requires_authentication(),
        SourceSyncError::Transport(_)
        | SourceSyncError::HttpStatus(_)
        | SourceSyncError::InvalidCsv
        | SourceSyncError::ResponseTooLarge
        | SourceSyncError::UnsafePath(_)
        | SourceSyncError::Io(_)
        | SourceSyncError::Runtime(_) => QuotaError::new(
            Some(ProviderId::Cursor),
            QuotaErrorCode::ProviderUnavailable,
            "Cursor session storage was unavailable.",
        ),
    }
}
