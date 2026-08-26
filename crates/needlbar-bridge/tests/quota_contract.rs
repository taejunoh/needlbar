use std::{
    future::Future,
    pin::Pin,
    sync::{Arc, Mutex},
};

use async_trait::async_trait;
use needlbar_bridge::quota::{
    collect_claude_user_initiated_with_source, collect_codex_with_provider,
    collect_quota_with_providers, envelope_from_collection, ClaudeUserInitiatedQuotaSource,
};
use needlbar_quota::{
    ClaudeCredentialAccess, ClaudeCredentialError, ClaudeCredentialResolver, ClaudeOAuthSecret,
    ClaudeQuotaProvider, ProviderId, ProviderQuotaSnapshot, QuotaError, QuotaErrorCode,
    QuotaProvider, QuotaWindow, RedactingHttpClient,
};

struct FakeProvider {
    result: Result<ProviderQuotaSnapshot, QuotaError>,
}

#[async_trait]
impl QuotaProvider for FakeProvider {
    async fn fetch(&self) -> Result<ProviderQuotaSnapshot, QuotaError> {
        self.result.clone()
    }
}

fn successful_snapshot(provider: ProviderId, window_id: &str) -> ProviderQuotaSnapshot {
    ProviderQuotaSnapshot {
        provider,
        windows: vec![QuotaWindow::new(window_id, "Test", 25.0, None).expect("valid window")],
    }
}

fn authentication_error() -> QuotaError {
    QuotaError {
        provider: Some(ProviderId::Codex),
        code: QuotaErrorCode::RequiresAuthentication,
        message: "Codex authentication was not available.",
        retry_after: None,
        action: None,
    }
}

struct RecordingClaudeResolver {
    accesses: Arc<Mutex<Vec<ClaudeCredentialAccess>>>,
}

impl ClaudeCredentialResolver for RecordingClaudeResolver {
    fn resolve(
        &self,
        access: ClaudeCredentialAccess,
    ) -> Result<ClaudeOAuthSecret, ClaudeCredentialError> {
        self.accesses.lock().expect("accesses lock").push(access);
        Err(ClaudeCredentialError::NotFound)
    }
}

struct RecordingClaudeSource {
    accesses: Arc<Mutex<Vec<ClaudeCredentialAccess>>>,
    result: Result<ProviderQuotaSnapshot, QuotaError>,
}

impl ClaudeUserInitiatedQuotaSource for RecordingClaudeSource {
    fn fetch_with_credential_access<'a>(
        &'a self,
        access: ClaudeCredentialAccess,
    ) -> Pin<Box<dyn Future<Output = Result<ProviderQuotaSnapshot, QuotaError>> + Send + 'a>> {
        self.accesses.lock().expect("accesses lock").push(access);
        Box::pin(async move { self.result.clone() })
    }
}

#[tokio::test]
async fn ordinary_all_provider_collection_uses_background_claude_credential_access() {
    // This catches an all-provider refresh that can accidentally trigger
    // user-interactive Keychain access.
    let accesses = Arc::new(Mutex::new(Vec::new()));
    let claude = ClaudeQuotaProvider::with_resolver(
        Arc::new(RecordingClaudeResolver {
            accesses: Arc::clone(&accesses),
        }),
        RedactingHttpClient::new(),
    );

    let collection = collect_quota_with_providers(
        Arc::new(claude),
        Arc::new(FakeProvider {
            result: Ok(successful_snapshot(ProviderId::Codex, "codex.primary")),
        }),
        Arc::new(FakeProvider {
            result: Ok(successful_snapshot(ProviderId::Cursor, "cursor.plan")),
        }),
    )
    .await;

    assert_eq!(
        *accesses.lock().expect("accesses lock"),
        vec![ClaudeCredentialAccess::BackgroundNoUI]
    );
    assert_eq!(collection.providers.len(), 2);
    assert_eq!(collection.errors[0].provider.as_deref(), Some("claude"));
}

#[tokio::test]
async fn claude_user_initiated_collection_uses_only_claude_with_ui_access() {
    // This catches a verification path that either falls back to all providers
    // or drops the explicit user-initiated Keychain access mode.
    let accesses = Arc::new(Mutex::new(Vec::new()));
    let collection = collect_claude_user_initiated_with_source(Arc::new(RecordingClaudeSource {
        accesses: Arc::clone(&accesses),
        result: Ok(successful_snapshot(ProviderId::Claude, "claude.session")),
    }))
    .await;
    let value = serde_json::to_value(envelope_from_collection(collection))
        .expect("Claude envelope serializes");

    assert_eq!(
        *accesses.lock().expect("accesses lock"),
        vec![ClaudeCredentialAccess::UserInitiatedAllowUI]
    );
    assert_eq!(value["data"]["providers"].as_array().map(Vec::len), Some(1));
    assert_eq!(value["data"]["providers"][0]["provider"], "claude");
    assert_eq!(value["errors"], serde_json::json!([]));
}

#[tokio::test]
async fn codex_only_collection_invokes_only_its_injected_provider() {
    // This catches a Codex verification path that reconstructs the ordinary
    // fan-out collector and reaches Claude or Cursor.
    let calls = Arc::new(Mutex::new(0usize));
    struct RecordingCodexProvider {
        calls: Arc<Mutex<usize>>,
    }
    #[async_trait]
    impl QuotaProvider for RecordingCodexProvider {
        async fn fetch(&self) -> Result<ProviderQuotaSnapshot, QuotaError> {
            *self.calls.lock().expect("calls lock") += 1;
            Ok(successful_snapshot(ProviderId::Codex, "codex.primary"))
        }
    }

    let collection = collect_codex_with_provider(Arc::new(RecordingCodexProvider {
        calls: Arc::clone(&calls),
    }))
    .await;
    let value = serde_json::to_value(envelope_from_collection(collection))
        .expect("Codex envelope serializes");

    assert_eq!(*calls.lock().expect("calls lock"), 1);
    assert_eq!(value["data"]["providers"].as_array().map(Vec::len), Some(1));
    assert_eq!(value["data"]["providers"][0]["provider"], "codex");
}

#[tokio::test]
async fn claude_permission_denial_uses_safe_bridge_copy_without_token_data() {
    // This catches forwarding an upstream Keychain detail or accidentally
    // serializing failed Claude data into the provider payload.
    let canary = "CLAUDE-KEYCHAIN-CANARY";
    let collection = collect_claude_user_initiated_with_source(Arc::new(RecordingClaudeSource {
        accesses: Arc::new(Mutex::new(Vec::new())),
        result: Err(QuotaError {
            provider: Some(ProviderId::Claude),
            code: QuotaErrorCode::PermissionDenied,
            message: Box::leak(format!("denied {canary}").into_boxed_str()),
            retry_after: None,
            action: None,
        }),
    }))
    .await;
    let json = serde_json::to_string(&envelope_from_collection(collection))
        .expect("Claude permission envelope serializes");
    let value: serde_json::Value = serde_json::from_str(&json).expect("Claude permission JSON");

    assert_eq!(value["data"]["providers"], serde_json::json!([]));
    assert_eq!(value["errors"][0]["provider"], "claude");
    assert_eq!(value["errors"][0]["code"], "permissionDenied");
    assert_eq!(
        value["errors"][0]["message"],
        "Provider credential access was denied."
    );
    assert!(!json.contains(canary));
}

#[tokio::test]
async fn quota_collection_keeps_successes_and_stable_provider_order_when_codex_auth_fails() {
    // This catches a collector that short-circuits on the first provider
    // error, leaks failed providers into data, or returns completion order.
    let collection = collect_quota_with_providers(
        Arc::new(FakeProvider {
            result: Ok(successful_snapshot(ProviderId::Claude, "claude.session")),
        }),
        Arc::new(FakeProvider {
            result: Err(authentication_error()),
        }),
        Arc::new(FakeProvider {
            result: Ok(successful_snapshot(ProviderId::Cursor, "cursor.plan")),
        }),
    )
    .await;
    let envelope = envelope_from_collection(collection);
    let value = serde_json::to_value(envelope).expect("quota envelope serializes");

    assert_eq!(value["schemaVersion"], "needlbar.v1");
    assert_eq!(value["ok"], true);
    assert_eq!(value["data"]["providers"].as_array().unwrap().len(), 2);
    assert_eq!(value["data"]["providers"][0]["provider"], "claude");
    assert_eq!(value["data"]["providers"][1]["provider"], "cursor");
    assert_eq!(value["errors"].as_array().unwrap().len(), 1);
    assert_eq!(value["errors"][0]["provider"], "codex");
    assert_eq!(value["errors"][0]["code"], "requiresAuthentication");
}

#[tokio::test]
async fn quota_collection_with_only_provider_errors_is_a_successful_bridge_response() {
    // This catches an envelope that reports a bridge failure merely because
    // every independently-refreshable provider failed.
    let codex_error = authentication_error();
    let collection = collect_quota_with_providers(
        Arc::new(FakeProvider {
            result: Err(QuotaError {
                provider: Some(ProviderId::Claude),
                ..codex_error.clone()
            }),
        }),
        Arc::new(FakeProvider {
            result: Err(codex_error),
        }),
        Arc::new(FakeProvider {
            result: Err(QuotaError {
                provider: Some(ProviderId::Cursor),
                code: QuotaErrorCode::ProviderUnavailable,
                message: "Cursor personal quota is unavailable.",
                retry_after: None,
                action: None,
            }),
        }),
    )
    .await;
    let envelope = envelope_from_collection(collection);
    let value = serde_json::to_value(envelope).expect("quota envelope serializes");

    assert_eq!(value["ok"], true);
    assert_eq!(value["data"]["providers"], serde_json::json!([]));
    assert_eq!(value["errors"].as_array().unwrap().len(), 3);
    assert_eq!(value["errors"][0]["provider"], "claude");
    assert_eq!(value["errors"][1]["provider"], "codex");
    assert_eq!(value["errors"][2]["provider"], "cursor");
    assert_eq!(value["errors"][2]["code"], "providerUnavailable");
    assert!(value["errors"][2].get("action").is_none());
}
