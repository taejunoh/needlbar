//! Provider quota retrieval. This crate deliberately keeps credentials and
//! provider responses on the Rust side of the bridge.

mod domain;
mod http;
pub mod providers;

pub use domain::{
    normalize_percent, ClaudeQuotaFailureOrigin, ProviderId, ProviderQuotaSnapshot, QuotaError,
    QuotaErrorCode, QuotaWindow,
};
pub use http::RedactingHttpClient;
pub use providers::claude_cli::ClaudeCliLocator;
pub use providers::claude_usage_probe::{
    run_usage_probe, UsageProbeControl, UsageProbeEnvironment, UsageProbeFailure, UsageProbeLimits,
    USAGE_PROBE_ARGUMENTS,
};
pub use providers::claude_usage_provider::{
    ClaudeUsageProbeSummary, ClaudeUsageReportProvider, ClaudeUsageReportRun,
};
pub use providers::claude_usage_report::{
    parse_usage_report_stream, ClaudeUsageReportOutcome, ClaudeUsageRowKind, ClaudeUsageRowSummary,
};
pub use providers::codex::{CodexQuotaProvider, CodexQuotaSource};
pub use providers::cursor::CursorQuotaProvider;
pub use providers::QuotaProvider;
