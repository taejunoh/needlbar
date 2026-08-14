use std::sync::Arc;

use async_trait::async_trait;
use needlbar_bridge::quota::{collect_quota_with_providers, envelope_from_collection};
use needlbar_quota::{
    ProviderId, ProviderQuotaSnapshot, QuotaAction, QuotaError, QuotaErrorCode, QuotaProvider,
    QuotaWindow,
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
                code: QuotaErrorCode::RequiresAuthentication,
                message: "Cursor authentication was not available.",
                retry_after: None,
                action: Some(QuotaAction::ConnectCursor),
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
    assert_eq!(value["errors"][2]["action"], "connectCursor");
}
