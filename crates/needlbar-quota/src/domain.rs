use std::time::Duration;

use chrono::{DateTime, Utc};
use serde::Serialize;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ProviderId {
    Claude,
    Codex,
    Cursor,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QuotaWindow {
    pub id: String,
    pub title: String,
    pub used_percent: f64,
    pub resets_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderQuotaSnapshot {
    pub provider: ProviderId,
    pub windows: Vec<QuotaWindow>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum QuotaErrorCode {
    RequiresAuthentication,
    AuthenticationExpired,
    RateLimited,
    NetworkUnavailable,
    ServiceUnavailable,
    SchemaChanged,
}

/// A deliberately provider-safe error. It never stores a source error, URL,
/// response body, local path, account identity, or credential.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QuotaError {
    pub provider: Option<ProviderId>,
    pub code: QuotaErrorCode,
    pub message: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub retry_after: Option<Duration>,
}

impl QuotaError {
    pub(crate) const fn new(
        provider: Option<ProviderId>,
        code: QuotaErrorCode,
        message: &'static str,
    ) -> Self {
        Self {
            provider,
            code,
            message,
            retry_after: None,
        }
    }

    pub(crate) const fn with_retry_after(mut self, retry_after: Option<Duration>) -> Self {
        self.retry_after = retry_after;
        self
    }

    pub(crate) const fn for_provider(mut self, provider: ProviderId) -> Self {
        self.provider = Some(provider);
        self
    }
}

/// Validates the provider's used quota percentage without correcting it.
/// Clamping would make a changed or corrupt provider schema look valid.
pub fn normalize_percent(value: f64) -> Result<f64, QuotaError> {
    if value.is_finite() && (0.0..=100.0).contains(&value) {
        Ok(value)
    } else {
        Err(QuotaError::new(
            None,
            QuotaErrorCode::SchemaChanged,
            "Quota data was not in the expected format.",
        ))
    }
}
