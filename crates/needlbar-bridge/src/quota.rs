use std::sync::Arc;

use needlbar_quota::{
    ClaudeQuotaProvider, CodexQuotaProvider, CursorQuotaProvider, ProviderId,
    ProviderQuotaSnapshot, QuotaAction, QuotaError, QuotaErrorCode, QuotaProvider,
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

/// Collects each independently-bounded provider concurrently. The explicit
/// result order makes the JSON payload independent of provider completion
/// timing.
pub async fn collect_quota() -> QuotaCollection {
    collect_quota_with_providers(
        Arc::new(ClaudeQuotaProvider::new()),
        Arc::new(CodexQuotaProvider::new()),
        Arc::new(CursorQuotaProvider::new()),
    )
    .await
}

pub async fn collect_quota_with_providers(
    claude: Arc<dyn QuotaProvider>,
    codex: Arc<dyn QuotaProvider>,
    cursor: Arc<dyn QuotaProvider>,
) -> QuotaCollection {
    let (claude, codex, cursor) = tokio::join!(claude.fetch(), codex.fetch(), cursor.fetch());
    let mut providers = Vec::with_capacity(3);
    let mut errors = Vec::with_capacity(3);

    for result in [claude, codex, cursor] {
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
