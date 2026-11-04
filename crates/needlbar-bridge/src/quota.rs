use std::{future::Future, pin::Pin, sync::Arc};

use needlbar_quota::{
    ClaudeQuotaFailureOrigin, ClaudeUsageProbeSummary, ClaudeUsageReportProvider,
    ClaudeUsageReportRun, ProviderId, ProviderQuotaSnapshot, QuotaError, QuotaErrorCode,
    QuotaProvider, UsageProbeControl,
};
#[cfg(not(feature = "bridge-test-runtime"))]
use needlbar_quota::{CodexQuotaProvider, CursorQuotaProvider};
use serde::Serialize;

use crate::envelope::{BridgeError, Envelope, SCHEMA_VERSION};

#[derive(Debug, Serialize)]
pub struct QuotaPayload {
    pub providers: Vec<ProviderQuotaSnapshot>,
    #[serde(skip)]
    pub(crate) claude_failure_origin: Option<ClaudeQuotaFailureOrigin>,
    #[serde(skip)]
    pub(crate) claude_attempted: bool,
}

pub struct QuotaCollection {
    pub providers: Vec<ProviderQuotaSnapshot>,
    pub errors: Vec<BridgeError>,
    pub claude_failure_origin: Option<ClaudeQuotaFailureOrigin>,
    pub claude_attempted: bool,
    pub claude_usage_probe: Option<ClaudeUsageProbeSummary>,
}

/// The Claude quota run. A dedicated collection, so a run of up to 30 seconds
/// never holds the Codex and Cursor refresh.
pub trait ClaudeUsageReportSource: Send + Sync {
    fn run_usage_report<'a>(
        &'a self,
    ) -> Pin<Box<dyn Future<Output = ClaudeUsageReportRun> + Send + 'a>>;
}

impl ClaudeUsageReportSource for ClaudeUsageReportProvider {
    fn run_usage_report<'a>(
        &'a self,
    ) -> Pin<Box<dyn Future<Output = ClaudeUsageReportRun> + Send + 'a>> {
        Box::pin(ClaudeUsageReportProvider::run(self))
    }
}

pub async fn collect_claude_usage_report(run_id: u64) -> QuotaCollection {
    #[cfg(feature = "bridge-test-runtime")]
    {
        let _ = run_id;
        if let Some(source) = crate::test_runtime::claude_usage_report_source() {
            return collect_claude_usage_report_with_source(source).await;
        }
        test_runtime_unavailable_collection()
    }
    #[cfg(not(feature = "bridge-test-runtime"))]
    {
        collect_claude_usage_report_with_source(Arc::new(ClaudeUsageReportProvider::new(run_id)))
            .await
    }
}

pub async fn collect_claude_usage_report_with_source(
    source: Arc<dyn ClaudeUsageReportSource>,
) -> QuotaCollection {
    let run = source.run_usage_report().await;
    let mut collection = collection_from_results([run.result]);
    collection.claude_usage_probe = run.summary;
    collection
}

pub fn cancel_claude_usage_report_through(run_id: u64) {
    UsageProbeControl::shared().cancel_through(run_id);
}

/// Collects Codex and Cursor concurrently. Claude has its own collection and
/// slot, so a run of up to 30 seconds cannot hold these two.
pub async fn collect_quota() -> QuotaCollection {
    #[cfg(feature = "bridge-test-runtime")]
    if let Some((codex, cursor)) = crate::test_runtime::background_quota_providers() {
        return collect_quota_with_providers(codex, cursor).await;
    }
    #[cfg(feature = "bridge-test-runtime")]
    return test_runtime_unavailable_collection();
    #[cfg(not(feature = "bridge-test-runtime"))]
    {
        collect_quota_with_providers(
            Arc::new(CodexQuotaProvider::new()),
            Arc::new(CursorQuotaProvider::new()),
        )
        .await
    }
}

/// Runs only Codex quota collection. It does not construct Claude or Cursor
/// providers, preserving the physical provider boundary of the C export.
pub async fn collect_codex_only() -> QuotaCollection {
    #[cfg(feature = "bridge-test-runtime")]
    if let Some(provider) = crate::test_runtime::codex_quota_provider() {
        return collect_codex_with_provider(provider).await;
    }
    #[cfg(feature = "bridge-test-runtime")]
    return test_runtime_unavailable_collection();
    #[cfg(not(feature = "bridge-test-runtime"))]
    {
        collect_codex_with_provider(Arc::new(CodexQuotaProvider::new())).await
    }
}

pub async fn collect_codex_with_provider(provider: Arc<dyn QuotaProvider>) -> QuotaCollection {
    collection_from_results([provider.fetch().await])
}

pub async fn collect_quota_with_providers(
    codex: Arc<dyn QuotaProvider>,
    cursor: Arc<dyn QuotaProvider>,
) -> QuotaCollection {
    let (codex, cursor) = tokio::join!(codex.fetch(), cursor.fetch());
    collection_from_results([codex, cursor])
}

fn collection_from_results(
    results: impl IntoIterator<Item = Result<ProviderQuotaSnapshot, QuotaError>>,
) -> QuotaCollection {
    let mut providers = Vec::new();
    let mut errors = Vec::new();
    let mut claude_failure_origin = None;
    let mut claude_attempted = false;

    for result in results {
        match result {
            Ok(snapshot) => {
                claude_attempted |= snapshot.provider == ProviderId::Claude;
                providers.push(snapshot);
            }
            // The read did not run or was cancelled, so there is no Claude outcome to report.
            Err(error)
                if error.is_claude_credential_busy()
                    || error.is_claude_usage_report_cancelled() => {}
            Err(error) => {
                if error.provider == Some(ProviderId::Claude) {
                    claude_attempted = true;
                    claude_failure_origin = Some(
                        error
                            .claude_failure_origin()
                            .unwrap_or(ClaudeQuotaFailureOrigin::OtherFailure),
                    );
                }
                errors.push(bridge_error_from_quota(error));
            }
        }
    }

    QuotaCollection {
        providers,
        errors,
        claude_failure_origin,
        claude_attempted,
        claude_usage_probe: None,
    }
}

#[cfg(feature = "bridge-test-runtime")]
fn test_runtime_unavailable_collection() -> QuotaCollection {
    collection_from_results([Err(QuotaError::new(
        None,
        QuotaErrorCode::ProviderUnavailable,
        "Bridge test fixture runtime was not installed.",
    ))])
}

pub fn envelope_from_collection(collection: QuotaCollection) -> Envelope<QuotaPayload> {
    Envelope {
        schema_version: SCHEMA_VERSION,
        ok: true,
        generated_at: chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true),
        data: Some(QuotaPayload {
            providers: collection.providers,
            claude_failure_origin: collection.claude_failure_origin,
            claude_attempted: collection.claude_attempted,
        }),
        errors: collection.errors,
    }
}

fn bridge_error_from_quota(error: QuotaError) -> BridgeError {
    let provider = error.provider.map(provider_name).map(str::to_owned);
    let code = match error.code {
        QuotaErrorCode::NotInstalled => "notInstalled",
        QuotaErrorCode::RequiresAuthentication => "requiresAuthentication",
        QuotaErrorCode::AuthenticationExpired => "authenticationExpired",
        QuotaErrorCode::PermissionDenied => "permissionDenied",
        QuotaErrorCode::RateLimited => "rateLimited",
        QuotaErrorCode::NetworkUnavailable => "networkUnavailable",
        QuotaErrorCode::ServiceUnavailable | QuotaErrorCode::ProviderUnavailable => {
            "providerUnavailable"
        }
        QuotaErrorCode::SchemaChanged => "schemaChanged",
    };

    BridgeError {
        provider,
        code: code.to_owned(),
        message: safe_quota_message(code).to_owned(),
    }
}

fn safe_quota_message(code: &str) -> &'static str {
    match code {
        "notInstalled" => "The provider application is not available.",
        "requiresAuthentication" => "Provider authentication is required.",
        "authenticationExpired" => "Provider authentication has expired.",
        "permissionDenied" => "Provider credential access was denied.",
        "rateLimited" => "The provider rate limit was reached.",
        "networkUnavailable" => "The provider could not be reached.",
        "providerUnavailable" => "The provider is currently unavailable.",
        "schemaChanged" => "The provider response could not be validated.",
        _ => "Provider quota data is unavailable.",
    }
}

fn provider_name(provider: ProviderId) -> &'static str {
    match provider {
        ProviderId::Claude => "claude",
        ProviderId::Codex => "codex",
        ProviderId::Cursor => "cursor",
    }
}
