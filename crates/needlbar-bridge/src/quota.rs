use std::{future::Future, pin::Pin, sync::Arc};

use needlbar_quota::{
    ClaudeCredentialAccess, ClaudeQuotaProvider, CodexQuotaProvider, CursorQuotaProvider,
    ProviderId, ProviderQuotaSnapshot, QuotaAction, QuotaError, QuotaErrorCode, QuotaProvider,
};
use serde::Serialize;

use crate::envelope::{BridgeError, Envelope, SCHEMA_VERSION};

#[derive(Debug, Serialize)]
pub struct QuotaPayload {
    pub providers: Vec<ProviderQuotaSnapshot>,
}

pub struct QuotaCollection {
    pub providers: Vec<ProviderQuotaSnapshot>,
    pub errors: Vec<BridgeError>,
}

/// Narrow Claude boundary used by the explicit verification path. Keeping the
/// credential access mode at this boundary makes it testable without exposing
/// Claude credentials or a provider-selection parameter over the C ABI.
pub trait ClaudeUserInitiatedQuotaSource: Send + Sync {
    fn fetch_with_credential_access<'a>(
        &'a self,
        access: ClaudeCredentialAccess,
    ) -> Pin<Box<dyn Future<Output = Result<ProviderQuotaSnapshot, QuotaError>> + Send + 'a>>;
}

impl ClaudeUserInitiatedQuotaSource for ClaudeQuotaProvider {
    fn fetch_with_credential_access<'a>(
        &'a self,
        access: ClaudeCredentialAccess,
    ) -> Pin<Box<dyn Future<Output = Result<ProviderQuotaSnapshot, QuotaError>> + Send + 'a>> {
        Box::pin(ClaudeQuotaProvider::fetch_with_credential_access(
            self, access,
        ))
    }
}

/// Collects each independently-bounded provider concurrently. The explicit
/// result order makes the JSON payload independent of provider completion
/// timing.
pub async fn collect_quota() -> QuotaCollection {
    #[cfg(feature = "bridge-test-runtime")]
    if let Some((claude, codex, cursor)) = crate::test_runtime::all_quota_providers() {
        return collect_quota_with_providers(claude, codex, cursor).await;
    }
    collect_quota_with_providers(
        Arc::new(ClaudeQuotaProvider::new()),
        Arc::new(CodexQuotaProvider::new()),
        Arc::new(CursorQuotaProvider::new()),
    )
    .await
}

/// Runs only the explicit Claude verification flow. Production construction is
/// intentionally kept here so callers cannot accidentally request interactive
/// Keychain access through the all-provider collector.
pub async fn collect_claude_user_initiated() -> QuotaCollection {
    #[cfg(feature = "bridge-test-runtime")]
    if let Some(source) = crate::test_runtime::claude_user_initiated_source() {
        return collect_claude_user_initiated_with_source(source).await;
    }
    collect_claude_user_initiated_with_source(Arc::new(ClaudeQuotaProvider::new())).await
}

pub async fn collect_claude_user_initiated_with_source(
    source: Arc<dyn ClaudeUserInitiatedQuotaSource>,
) -> QuotaCollection {
    collection_from_results([source
        .fetch_with_credential_access(ClaudeCredentialAccess::UserInitiatedAllowUI)
        .await])
}

/// Runs only Codex quota collection. It does not construct Claude or Cursor
/// providers, preserving the physical provider boundary of the C export.
pub async fn collect_codex_only() -> QuotaCollection {
    #[cfg(feature = "bridge-test-runtime")]
    if let Some(provider) = crate::test_runtime::codex_quota_provider() {
        return collect_codex_with_provider(provider).await;
    }
    collect_codex_with_provider(Arc::new(CodexQuotaProvider::new())).await
}

pub async fn collect_codex_with_provider(provider: Arc<dyn QuotaProvider>) -> QuotaCollection {
    collection_from_results([provider.fetch().await])
}

pub async fn collect_quota_with_providers(
    claude: Arc<dyn QuotaProvider>,
    codex: Arc<dyn QuotaProvider>,
    cursor: Arc<dyn QuotaProvider>,
) -> QuotaCollection {
    let (claude, codex, cursor) = tokio::join!(claude.fetch(), codex.fetch(), cursor.fetch());
    collection_from_results([claude, codex, cursor])
}

fn collection_from_results(
    results: impl IntoIterator<Item = Result<ProviderQuotaSnapshot, QuotaError>>,
) -> QuotaCollection {
    let mut providers = Vec::new();
    let mut errors = Vec::new();

    for result in results {
        match result {
            Ok(snapshot) => providers.push(snapshot),
            Err(error) => errors.push(bridge_error_from_quota(error)),
        }
    }

    QuotaCollection { providers, errors }
}

pub fn envelope_from_collection(collection: QuotaCollection) -> Envelope<QuotaPayload> {
    Envelope {
        schema_version: SCHEMA_VERSION,
        ok: true,
        generated_at: chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true),
        data: Some(QuotaPayload {
            providers: collection.providers,
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
        action: error.action.map(action_name).map(str::to_owned),
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

fn action_name(action: QuotaAction) -> &'static str {
    match action {
        QuotaAction::ConnectCursor => "connectCursor",
    }
}
