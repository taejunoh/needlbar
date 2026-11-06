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
    /// No executable `claude` at any fixed location.
    ClaudeCliNotFound,
    /// `rate_limits` was null, or `limits` was null or empty.
    UsageReportNoUsage,
    UsageProbeTimedOut,
    UsageProbeOutputTooLarge,
    /// The process could not start or exited unsuccessfully.
    UsageProbeFailed,
    UsageReportRateLimited,
    /// A run finished without a usable `usage_report`.
    UsageReportFormatChanged,
    OtherFailure,
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
    claude_usage_report_cancelled: bool,
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
            claude_usage_report_cancelled: false,
        }
    }

    /// A run stopped because the app is stopping. It describes no outcome, so
    /// collectors drop it rather than report a Claude failure.
    pub const fn claude_usage_report_cancelled() -> Self {
        let mut error = Self::new(
            Some(ProviderId::Claude),
            QuotaErrorCode::ProviderUnavailable,
            "The Claude usage check was cancelled.",
        );
        error.claude_usage_report_cancelled = true;
        error
    }

    pub const fn is_claude_usage_report_cancelled(&self) -> bool {
        self.claude_usage_report_cancelled
    }

    pub(crate) const fn with_retry_after(mut self, retry_after: Option<Duration>) -> Self {
        self.retry_after = retry_after;
        self
    }

    pub(crate) const fn with_claude_failure_origin(
        mut self,
        origin: ClaudeQuotaFailureOrigin,
    ) -> Self {
        self.claude_failure_origin = Some(origin);
        self
    }

    pub fn claude_failure_origin(&self) -> Option<ClaudeQuotaFailureOrigin> {
        self.claude_failure_origin
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
