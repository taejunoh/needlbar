use std::sync::Arc;

use async_trait::async_trait;
use needlbar_bridge::{
    diagnostics::{
        DiagnosticProvider, DiagnosticsSnapshot, ProviderDiagnostic, QuotaSource, SubsystemStatus,
        UsageSource,
    },
    quota::{collect_quota_with_providers, envelope_from_collection},
    usage::{UsagePayload, UsagePeriod, UsageProviderSnapshot},
};
use needlbar_quota::{
    ProviderId, ProviderQuotaSnapshot, QuotaError, QuotaErrorCode, QuotaProvider,
};

const CANARIES: [&str; 3] = [
    "CLAUDE-CANARY-SECRET",
    "CODEX-CANARY-SECRET",
    "CURSOR-CANARY-SECRET",
];

struct FakeProvider {
    result: Result<ProviderQuotaSnapshot, QuotaError>,
}

#[async_trait]
impl QuotaProvider for FakeProvider {
    async fn fetch(&self) -> Result<ProviderQuotaSnapshot, QuotaError> {
        self.result.clone()
    }
}

#[tokio::test]
async fn provider_credential_canaries_never_cross_usage_quota_diagnostics_or_error_envelopes() {
    let claude = "CLAUDE-CANARY-SECRET";
    let codex = "CODEX-CANARY-SECRET";
    let cursor = "CURSOR-CANARY-SECRET";
    let quota = envelope_from_collection(
        collect_quota_with_providers(
            Arc::new(FakeProvider {
                result: Err(QuotaError {
                    provider: Some(ProviderId::Claude),
                    code: QuotaErrorCode::RequiresAuthentication,
                    message: Box::leak(format!("invalid credential: {claude}").into_boxed_str()),
                    retry_after: None,
                    action: None,
                }),
            }),
            Arc::new(FakeProvider {
                result: Err(QuotaError {
                    provider: Some(ProviderId::Codex),
                    code: QuotaErrorCode::RequiresAuthentication,
                    message: Box::leak(format!("invalid credential: {codex}").into_boxed_str()),
                    retry_after: None,
                    action: None,
                }),
            }),
            Arc::new(FakeProvider {
                result: Err(QuotaError {
                    provider: Some(ProviderId::Cursor),
                    code: QuotaErrorCode::RequiresAuthentication,
                    message: Box::leak(format!("invalid cookie: {cursor}").into_boxed_str()),
                    retry_after: None,
                    action: None,
                }),
            }),
        )
        .await,
    );
    let diagnostics = DiagnosticsSnapshot::new(vec![
        ProviderDiagnostic::new(
            DiagnosticProvider::Claude,
            SubsystemStatus::Available,
            SubsystemStatus::Unavailable,
            UsageSource::Local,
            QuotaSource::OAuth,
            Some("2026-08-14T12:00:00Z"),
            None,
            Some("noUsageData".to_owned()),
            None,
        ),
        ProviderDiagnostic::new(
            DiagnosticProvider::Codex,
            SubsystemStatus::Unavailable,
            SubsystemStatus::RequiresAuthentication,
            UsageSource::Local,
            QuotaSource::OAuth,
            None,
            None,
            None,
            Some(format!("failed credential: {codex}")),
        ),
        ProviderDiagnostic::new(
            DiagnosticProvider::Cursor,
            SubsystemStatus::Unavailable,
            SubsystemStatus::RequiresAuthentication,
            UsageSource::CursorExport,
            QuotaSource::Session,
            None,
            None,
            None,
            Some(format!("failed cookie: {cursor}")),
        ),
    ]);

    let usage = UsagePayload {
        providers: vec![UsageProviderSnapshot {
            provider: "claude".to_owned(),
            all_time_split: UsagePeriod::default(),
            today: UsagePeriod::default(),
            last_7_days: UsagePeriod::default(),
            last_7_days_daily: Vec::new(),
            last_30_days: UsagePeriod::default(),
        }],
    };
    let output = [
        serde_json::to_string(&usage).expect("usage envelope serializes"),
        serde_json::to_string(&quota).expect("quota envelope serializes"),
        serde_json::to_string(&diagnostics).expect("diagnostics serializes"),
    ];

    let quota_value = serde_json::to_value(&quota).expect("quota envelope value");
    assert_eq!(quota_value["errors"][0]["code"], "requiresAuthentication");
    assert_eq!(
        quota_value["errors"][0]["message"],
        "Provider authentication is required."
    );
    assert_eq!(quota_value["errors"][1]["code"], "requiresAuthentication");
    assert_eq!(
        quota_value["errors"][1]["message"],
        "Provider authentication is required."
    );
    let diagnostics_value = serde_json::to_value(&diagnostics).expect("diagnostics value");
    assert_eq!(
        diagnostics_value["providers"][0]["usageErrorCode"],
        "noUsageData"
    );
    assert!(diagnostics_value["providers"][1]
        .get("quotaErrorCode")
        .is_none());

    for serialized in output {
        for canary in CANARIES {
            assert!(
                !serialized.contains(canary),
                "canary unexpectedly crossed bridge boundary: {canary}"
            );
        }
    }
}
