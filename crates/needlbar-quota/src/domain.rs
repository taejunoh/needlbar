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

/// Closed, non-secret stage labels for a failed Claude quota operation.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ClaudeQuotaFailureOrigin {
    CredentialMissing,
    KeychainCredentialExpired,
    FileCredentialExpired,
    CredentialAccessDenied,
    UsageEndpointUnauthorized,
    UsageEndpointForbidden,
    OtherFailure,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ClaudeUsageEndpointStatus {
    Unauthorized,
    Forbidden,
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
    #[serde(skip)]
    claude_failure_origin: Option<ClaudeQuotaFailureOrigin>,
    #[serde(skip)]
    usage_endpoint_status: Option<ClaudeUsageEndpointStatus>,
}

impl QuotaError {
    pub const fn new(
        provider: Option<ProviderId>,
        code: QuotaErrorCode,
        message: &'static str,
    ) -> Self {
        Self {
            provider,
            code,
            message,
            retry_after: None,
            claude_failure_origin: None,
            usage_endpoint_status: None,
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

    pub(crate) const fn with_claude_failure_origin(
        mut self,
        origin: ClaudeQuotaFailureOrigin,
    ) -> Self {
        self.claude_failure_origin = Some(origin);
        self
    }

    pub(crate) const fn with_usage_endpoint_status(
        mut self,
        status: ClaudeUsageEndpointStatus,
    ) -> Self {
        self.usage_endpoint_status = Some(status);
        self
    }

    pub fn claude_failure_origin(&self) -> Option<ClaudeQuotaFailureOrigin> {
        self.claude_failure_origin
    }

    pub(crate) const fn usage_endpoint_status(&self) -> Option<ClaudeUsageEndpointStatus> {
        self.usage_endpoint_status
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
