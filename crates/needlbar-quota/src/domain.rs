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
    id: String,
    title: String,
    used_percent: f64,
    resets_at: Option<DateTime<Utc>>,
}

impl QuotaWindow {
    pub fn new(
        id: impl Into<String>,
        title: impl Into<String>,
        used_percent: f64,
        resets_at: Option<DateTime<Utc>>,
    ) -> Result<Self, QuotaError> {
        Ok(Self {
            id: id.into(),
            title: title.into(),
            used_percent: normalize_percent(used_percent)?,
            resets_at,
        })
    }

    pub fn id(&self) -> &str {
        &self.id
    }

    pub fn title(&self) -> &str {
        &self.title
    }

    pub fn used_percent(&self) -> f64 {
        self.used_percent
    }

    pub fn resets_at(&self) -> Option<DateTime<Utc>> {
        self.resets_at
    }
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
    NotInstalled,
    RequiresAuthentication,
    AuthenticationExpired,
    PermissionDenied,
    RateLimited,
    NetworkUnavailable,
    ServiceUnavailable,
    ProviderUnavailable,
    SchemaChanged,
}

/// A provider-safe next step which remains structured for bridge collection.
/// It deliberately carries no credential, account, path, or provider payload.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum QuotaAction {
    ConnectCursor,
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
    #[serde(skip_serializing_if = "Option::is_none")]
    pub action: Option<QuotaAction>,
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
            action: None,
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

    #[allow(dead_code)]
    pub(crate) const fn with_action(mut self, action: QuotaAction) -> Self {
        self.action = Some(action);
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
