use chrono::{DateTime, Utc};
use serde::Serialize;
use std::collections::BTreeMap;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AnalyticsPayload {
    pub analysis_range: AnalysisRange,
    pub repositories: Vec<RepositoryAnalytics>,
    pub unattributed: AttributionBucket,
    pub coverage: AnalyticsCoverage,
    pub errors: Vec<AnalyticsError>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AnalysisRange {
    pub start: DateTime<Utc>,
    pub end: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RepositoryAnalytics {
    pub repository_id: String,
    pub label: String,
    pub state: RepositoryState,
    pub usage: UsageAggregate,
    pub observed_active_time_seconds: String,
    pub provider_models: Vec<ProviderModelAnalytics>,
    pub commits: Vec<CommitAnalytics>,
    pub coverage: RepositoryCoverage,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum RepositoryState {
    Available,
    Unavailable,
}

#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageAggregate {
    pub input_tokens: String,
    pub output_tokens: String,
    pub cache_read_tokens: String,
    pub cache_write_tokens: String,
    pub reasoning_tokens: String,
    pub total_tokens: String,
    #[serde(rename = "estimatedCostUSD")]
    pub estimated_cost_usd: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderModelAnalytics {
    pub provider: String,
    pub model: String,
    pub usage: UsageAggregate,
    #[serde(rename = "costPer1KTokens")]
    pub cost_per_1k_tokens: Option<String>,
    pub tokens_per_observed_active_hour: Option<String>,
    #[serde(rename = "millisecondsPer1KTokens")]
    pub milliseconds_per_1k_tokens: Option<String>,
    pub cost_coverage: String,
    pub timing_coverage: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CommitAnalytics {
    pub commit_id: String,
    pub committed_at: DateTime<Utc>,
    pub correlated_usage: UsageAggregate,
    pub pull_request_number: Option<i32>,
    pub coverage: String,
}

#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AttributionBucket {
    pub usage: UsageAggregate,
    pub fragments: u64,
    pub reasons: BTreeMap<String, u64>,
}

#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AnalyticsCoverage {
    pub attributed_fragments: u64,
    pub unattributed_fragments: u64,
    pub reasons: BTreeMap<String, u64>,
}

#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RepositoryCoverage {
    pub assigned_fragments: u64,
    pub unassigned_fragments: u64,
    pub timing_partial: bool,
    pub reasons: BTreeMap<String, u64>,
}

#[derive(Debug, Clone, Eq, PartialEq, Ord, PartialOrd, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AnalyticsError {
    pub scope: String,
    pub code: String,
}
