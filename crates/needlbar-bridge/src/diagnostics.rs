use std::sync::{LazyLock, Mutex};

use serde::Serialize;

use crate::{envelope::Envelope, quota::QuotaPayload, usage::UsagePayload};

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum DiagnosticProvider {
    Claude,
    Codex,
    Cursor,
}

impl DiagnosticProvider {
    const ALL: [Self; 3] = [Self::Claude, Self::Codex, Self::Cursor];

    fn name(self) -> &'static str {
        match self {
            Self::Claude => "claude",
            Self::Codex => "codex",
            Self::Cursor => "cursor",
        }
    }

    fn usage_source(self) -> UsageSource {
        let _ = self;
        UsageSource::Local
    }

    fn quota_source(self) -> QuotaSource {
        match self {
            Self::Cursor => QuotaSource::Unavailable,
            Self::Claude | Self::Codex => QuotaSource::OAuth,
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum SubsystemStatus {
    Available,
    Unavailable,
    RequiresAuthentication,
    Error,
}

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum UsageSource {
    Local,
}

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum QuotaSource {
    OAuth,
    Unavailable,
}

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum SafeErrorCode {
    NotInstalled,
    RequiresAuthentication,
    AuthenticationExpired,
    PermissionDenied,
    RateLimited,
    NetworkUnavailable,
    ProviderUnavailable,
    SchemaChanged,
    NoUsageData,
    UsageRuntimeUnavailable,
    UsageReportUnavailable,
    InvalidUsageDate,
    InvalidUsageData,
    InternalError,
}

impl SafeErrorCode {
    fn parse(value: &str) -> Option<Self> {
        Some(match value {
            "notInstalled" => Self::NotInstalled,
            "requiresAuthentication" => Self::RequiresAuthentication,
            "authenticationExpired" => Self::AuthenticationExpired,
            "permissionDenied" => Self::PermissionDenied,
            "rateLimited" => Self::RateLimited,
            "networkUnavailable" => Self::NetworkUnavailable,
            "providerUnavailable" => Self::ProviderUnavailable,
            "schemaChanged" => Self::SchemaChanged,
            "noUsageData" => Self::NoUsageData,
            "usageRuntimeUnavailable" => Self::UsageRuntimeUnavailable,
            "usageReportUnavailable" => Self::UsageReportUnavailable,
            "invalidUsageDate" => Self::InvalidUsageDate,
            "invalidUsageData" => Self::InvalidUsageData,
            "internalError" => Self::InternalError,
            _ => return None,
        })
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderDiagnostic {
    provider: DiagnosticProvider,
    usage_status: SubsystemStatus,
    quota_status: SubsystemStatus,
    usage_source: UsageSource,
    quota_source: QuotaSource,
    #[serde(skip_serializing_if = "Option::is_none")]
    last_usage_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    last_quota_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    usage_error_code: Option<SafeErrorCode>,
    #[serde(skip_serializing_if = "Option::is_none")]
    quota_error_code: Option<SafeErrorCode>,
}

impl ProviderDiagnostic {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        provider: DiagnosticProvider,
        usage_status: SubsystemStatus,
        quota_status: SubsystemStatus,
        usage_source: UsageSource,
        quota_source: QuotaSource,
        last_usage_at: Option<&str>,
        last_quota_at: Option<&str>,
        usage_error_code: Option<String>,
        quota_error_code: Option<String>,
    ) -> Self {
        Self {
            provider,
            usage_status,
            quota_status,
            usage_source,
            quota_source,
            last_usage_at: last_usage_at.map(ToOwned::to_owned),
            last_quota_at: last_quota_at.map(ToOwned::to_owned),
            usage_error_code: usage_error_code.as_deref().and_then(SafeErrorCode::parse),
            quota_error_code: quota_error_code.as_deref().and_then(SafeErrorCode::parse),
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct DiagnosticsSnapshot {
    providers: Vec<ProviderDiagnostic>,
}

impl DiagnosticsSnapshot {
    pub fn new(providers: Vec<ProviderDiagnostic>) -> Self {
        Self { providers }
    }

    pub fn from_envelopes(usage: &Envelope<UsagePayload>, quota: &Envelope<QuotaPayload>) -> Self {
        let providers = DiagnosticProvider::ALL
            .into_iter()
            .map(|provider| Self::provider_from_envelopes(provider, usage, quota))
            .collect();
        Self { providers }
    }

    pub fn from_recorded_outcomes() -> Self {
        let observations = RECORDED_OUTCOMES
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .clone();
        Self {
            providers: DiagnosticProvider::ALL
                .into_iter()
                .enumerate()
                .map(|(index, provider)| {
                    let usage = observations.usage.as_ref().map(|entries| &entries[index]);
                    let quota = observations.quota.as_ref().map(|entries| &entries[index]);
                    ProviderDiagnostic {
                        provider,
                        usage_status: usage
                            .map_or(SubsystemStatus::Unavailable, |entry| entry.status),
                        quota_status: quota
                            .map_or(SubsystemStatus::Unavailable, |entry| entry.status),
                        usage_source: provider.usage_source(),
                        quota_source: provider.quota_source(),
                        last_usage_at: usage.and_then(|entry| entry.observed_at.clone()),
                        last_quota_at: quota.and_then(|entry| entry.observed_at.clone()),
                        usage_error_code: usage.and_then(|entry| entry.error_code),
                        quota_error_code: quota.and_then(|entry| entry.error_code),
                    }
                })
                .collect(),
        }
    }

    fn provider_from_envelopes(
        provider: DiagnosticProvider,
        usage: &Envelope<UsagePayload>,
        quota: &Envelope<QuotaPayload>,
    ) -> ProviderDiagnostic {
        let name = provider.name();
        let usage_present = usage
            .data
            .as_ref()
            .is_some_and(|payload| payload.providers.iter().any(|entry| entry.provider == name));
        let quota_present = quota.data.as_ref().is_some_and(|payload| {
            payload
                .providers
                .iter()
                .any(|entry| provider_name(entry.provider) == name)
        });
        let usage_error = usage
            .errors
            .iter()
            .find(|error| error.provider.as_deref() == Some(name));
        let quota_error = quota
            .errors
            .iter()
            .find(|error| error.provider.as_deref() == Some(name));
        ProviderDiagnostic::new(
            provider,
            status(usage_present, usage_error.map(|error| error.code.as_str())),
            quota_status(
                provider,
                quota_present,
                quota_error.map(|error| error.code.as_str()),
            ),
            provider.usage_source(),
            provider.quota_source(),
            usage_present.then_some(usage.generated_at.as_str()),
            quota_present.then_some(quota.generated_at.as_str()),
            usage_error.map(|error| error.code.clone()),
            quota_error.map(|error| error.code.clone()),
        )
    }
}

#[derive(Debug, Clone)]
struct StreamObservation {
    status: SubsystemStatus,
    observed_at: Option<String>,
    error_code: Option<SafeErrorCode>,
}

#[derive(Debug, Clone, Default)]
struct RecordedOutcomes {
    usage: Option<Vec<StreamObservation>>,
    quota: Option<Vec<StreamObservation>>,
}

static RECORDED_OUTCOMES: LazyLock<Mutex<RecordedOutcomes>> =
    LazyLock::new(|| Mutex::new(RecordedOutcomes::default()));

pub fn record_usage(envelope: &Envelope<UsagePayload>) {
    let entries = DiagnosticProvider::ALL
        .into_iter()
        .map(|provider| {
            let name = provider.name();
            let present = envelope.data.as_ref().is_some_and(|payload| {
                payload.providers.iter().any(|entry| entry.provider == name)
            });
            let error = envelope
                .errors
                .iter()
                .find(|error| error.provider.as_deref() == Some(name));
            stream_observation(
                present,
                envelope.generated_at.as_str(),
                error.map(|error| error.code.as_str()),
            )
        })
        .collect();
    RECORDED_OUTCOMES
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .usage = Some(entries);
}

pub fn record_quota(envelope: &Envelope<QuotaPayload>) {
    let entries = DiagnosticProvider::ALL
        .into_iter()
        .map(|provider| {
            let name = provider.name();
            let present = envelope.data.as_ref().is_some_and(|payload| {
                payload
                    .providers
                    .iter()
                    .any(|entry| provider_name(entry.provider) == name)
            });
            let error = envelope
                .errors
                .iter()
                .find(|error| error.provider.as_deref() == Some(name));
            StreamObservation {
                status: quota_status(provider, present, error.map(|error| error.code.as_str())),
                observed_at: present.then(|| envelope.generated_at.to_owned()),
                error_code: error.and_then(|error| SafeErrorCode::parse(&error.code)),
            }
        })
        .collect();
    RECORDED_OUTCOMES
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .quota = Some(entries);
}

/// Records only the provider outcomes represented by a provider-specific quota
/// envelope, preserving last-known outcomes for omitted providers.
pub fn record_partial_quota(envelope: &Envelope<QuotaPayload>) {
    let mut outcomes = RECORDED_OUTCOMES
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let entries = outcomes.quota.get_or_insert_with(|| {
        DiagnosticProvider::ALL
            .into_iter()
            .map(|_| stream_observation(false, envelope.generated_at.as_str(), None))
            .collect()
    });
    for (index, provider) in DiagnosticProvider::ALL.into_iter().enumerate() {
        let name = provider.name();
        let present = envelope.data.as_ref().is_some_and(|payload| {
            payload
                .providers
                .iter()
                .any(|entry| provider_name(entry.provider) == name)
        });
        let error = envelope
            .errors
            .iter()
            .find(|error| error.provider.as_deref() == Some(name));
        if present || error.is_some() {
            entries[index] = StreamObservation {
                status: quota_status(provider, present, error.map(|error| error.code.as_str())),
                observed_at: present.then(|| envelope.generated_at.to_owned()),
                error_code: error.and_then(|error| SafeErrorCode::parse(&error.code)),
            };
        }
    }
}

fn stream_observation(
    present: bool,
    generated_at: &str,
    error_code: Option<&str>,
) -> StreamObservation {
    StreamObservation {
        status: status(present, error_code),
        observed_at: present.then(|| generated_at.to_owned()),
        error_code: error_code.and_then(SafeErrorCode::parse),
    }
}

fn provider_name(provider: needlbar_quota::ProviderId) -> &'static str {
    match provider {
        needlbar_quota::ProviderId::Claude => "claude",
        needlbar_quota::ProviderId::Codex => "codex",
        needlbar_quota::ProviderId::Cursor => "cursor",
    }
}

fn status(present: bool, error_code: Option<&str>) -> SubsystemStatus {
    if present {
        return SubsystemStatus::Available;
    }
    match error_code {
        Some("requiresAuthentication" | "authenticationExpired") => {
            SubsystemStatus::RequiresAuthentication
        }
        Some(_) => SubsystemStatus::Error,
        None => SubsystemStatus::Unavailable,
    }
}

fn quota_status(
    provider: DiagnosticProvider,
    present: bool,
    error_code: Option<&str>,
) -> SubsystemStatus {
    if provider == DiagnosticProvider::Cursor && error_code == Some("providerUnavailable") {
        return SubsystemStatus::Unavailable;
    }
    status(present, error_code)
}
