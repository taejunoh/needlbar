use std::{
    future::Future,
    pin::Pin,
    sync::{Arc, Mutex},
};

use async_trait::async_trait;
use needlbar_bridge::quota::{
    collect_claude_usage_report_with_source, collect_codex_with_provider,
    collect_quota_with_providers, envelope_from_collection, ClaudeUsageReportSource,
};
use needlbar_quota::{
    ClaudeUsageProbeSummary, ClaudeUsageReportRun, ClaudeUsageRowKind, ProviderId,
    ProviderQuotaSnapshot, QuotaError, QuotaErrorCode, QuotaProvider, QuotaWindow,
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
    QuotaError::new(
        Some(ProviderId::Codex),
        QuotaErrorCode::RequiresAuthentication,
        "Codex authentication was not available.",
    )
}

#[tokio::test]
async fn bridge_carries_only_the_windows_the_report_gave() {
    let snapshot = ProviderQuotaSnapshot {
        provider: ProviderId::Claude,
        windows: vec![
            QuotaWindow::new("claude.weekly", "Weekly", 74.0, None).unwrap(),
            QuotaWindow::new("claude.fable.weekly", "Fable weekly", 0.0, None).unwrap(),
        ],
    };
    let collection = collect_claude_usage_report_with_source(Arc::new(ScriptedUsageReportSource {
        result: Ok(snapshot),
        summary: Some(fixture_summary()),
    }))
    .await;
    let value = serde_json::to_value(envelope_from_collection(collection)).unwrap();
    let windows = &value["data"]["providers"][0]["windows"];
    assert_eq!(windows.as_array().map(Vec::len), Some(2));
    assert_eq!(windows[0]["id"], "claude.weekly");
    assert_eq!(windows[1]["id"], "claude.fable.weekly");
    assert_eq!(windows[1]["usedPercent"].as_f64(), Some(0.0));
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
async fn background_collection_never_names_claude_and_keeps_codex_and_cursor_independent() {
    let collection = collect_quota_with_providers(
        Arc::new(FakeProvider {
            result: Err(authentication_error()),
        }),
        Arc::new(FakeProvider {
            result: Ok(successful_snapshot(ProviderId::Cursor, "cursor.plan")),
        }),
    )
    .await;
    assert!(!collection.claude_attempted);
    let value = serde_json::to_value(envelope_from_collection(collection)).expect("quota envelope");
    assert_eq!(value["ok"], true);
    assert_eq!(value["data"]["providers"].as_array().unwrap().len(), 1);
    assert_eq!(value["data"]["providers"][0]["provider"], "cursor");
    assert_eq!(value["errors"].as_array().unwrap().len(), 1);
    assert_eq!(value["errors"][0]["provider"], "codex");
    assert_eq!(value["errors"][0]["code"], "requiresAuthentication");
}

#[tokio::test]
async fn background_collection_with_only_provider_errors_is_a_successful_bridge_response() {
    let collection = collect_quota_with_providers(
        Arc::new(FakeProvider {
            result: Err(authentication_error()),
        }),
        Arc::new(FakeProvider {
            result: Err(QuotaError::new(
                Some(ProviderId::Cursor),
                QuotaErrorCode::ProviderUnavailable,
                "Cursor personal quota is unavailable.",
            )),
        }),
    )
    .await;
    let value = serde_json::to_value(envelope_from_collection(collection)).expect("quota envelope");
    assert_eq!(value["ok"], true);
    assert_eq!(value["data"]["providers"], serde_json::json!([]));
    assert_eq!(value["errors"].as_array().unwrap().len(), 2);
    assert_eq!(value["errors"][0]["provider"], "codex");
    assert_eq!(value["errors"][1]["provider"], "cursor");
    assert_eq!(value["errors"][1]["code"], "providerUnavailable");
}

struct ScriptedUsageReportSource {
    result: Result<ProviderQuotaSnapshot, QuotaError>,
    summary: Option<ClaudeUsageProbeSummary>,
}

impl ClaudeUsageReportSource for ScriptedUsageReportSource {
    fn run_usage_report<'a>(
        &'a self,
    ) -> Pin<Box<dyn Future<Output = ClaudeUsageReportRun> + Send + 'a>> {
        Box::pin(async move {
            ClaudeUsageReportRun {
                result: self.result.clone(),
                summary: self.summary.clone(),
            }
        })
    }
}

fn fixture_summary() -> ClaudeUsageProbeSummary {
    ClaudeUsageProbeSummary {
        duration_ms: 1_500,
        row_kinds: vec![ClaudeUsageRowKind::WeeklyAll],
        unknown_row_count: 0,
        skipped_row_count: 0,
    }
}

#[tokio::test]
async fn usage_report_collection_uses_only_claude_and_carries_its_summary() {
    let collection = collect_claude_usage_report_with_source(Arc::new(ScriptedUsageReportSource {
        result: Ok(successful_snapshot(ProviderId::Claude, "claude.weekly")),
        summary: Some(fixture_summary()),
    }))
    .await;
    assert!(collection.claude_attempted);
    assert_eq!(collection.claude_usage_probe, Some(fixture_summary()));
    let value = serde_json::to_value(envelope_from_collection(collection)).unwrap();
    assert_eq!(value["data"]["providers"].as_array().map(Vec::len), Some(1));
    assert_eq!(value["data"]["providers"][0]["provider"], "claude");
    assert_eq!(value["errors"], serde_json::json!([]));
    assert!(
        value.to_string().find("durationMs").is_none(),
        "the summary stays out of the quota envelope"
    );
}

#[tokio::test]
async fn a_cancelled_usage_report_is_dropped_and_describes_no_attempt() {
    let collection = collect_claude_usage_report_with_source(Arc::new(ScriptedUsageReportSource {
        result: Err(QuotaError::claude_usage_report_cancelled()),
        summary: None,
    }))
    .await;
    assert!(collection.providers.is_empty());
    assert!(collection.errors.is_empty());
    assert!(!collection.claude_attempted);
    assert_eq!(collection.claude_failure_origin, None);
}
