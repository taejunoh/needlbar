//! Bounded, local-only repository analytics.  Raw provider and Git values end
//! at this crate's sanitization boundary.

mod correlation;
#[cfg(feature = "analytics-diagnostic-probe")]
mod diagnostic_probe;
mod git;
mod model;
mod sanitize;

#[cfg(feature = "analytics-diagnostic-probe")]
pub use diagnostic_probe::{
    AnalyticsDiagnosticProbe, CanonicalizationProbeCounts, DiscoveryProbeCounts,
    FragmentProbeCount, MappingProbeCounts, ProbeCaps, ProviderProbeCounts,
};
pub use git::{BoundedGitRunner, GitOutput, GitRequest, GitRequestKind, GitRunner, GitRunnerError};
pub use model::{
    AnalysisRange, AnalyticsCoverage, AnalyticsError, AnalyticsPayload, AttributionBucket,
    CommitAnalytics, ProviderModelAnalytics, RepositoryAnalytics, RepositoryCoverage,
    RepositoryState, UsageAggregate,
};

use chrono::{DateTime, Utc};
use tokscale_core::WorkspaceSessionReport;

/// Builds a complete, serialization-safe snapshot from an already-local report.
pub fn build_analytics_payload(
    report: WorkspaceSessionReport,
    generated_at: DateTime<Utc>,
    git: &dyn GitRunner,
) -> AnalyticsPayload {
    correlation::build(report, generated_at, git)
}

#[cfg(feature = "analytics-diagnostic-probe")]
pub fn build_analytics_diagnostic_probe(
    report: WorkspaceSessionReport,
    generated_at: DateTime<Utc>,
    git: &dyn GitRunner,
) -> AnalyticsDiagnosticProbe {
    diagnostic_probe::build(report, generated_at, git)
}
