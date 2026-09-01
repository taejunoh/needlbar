//! Bounded, local-only repository analytics.  Raw provider and Git values end
//! at this crate's sanitization boundary.

mod correlation;
mod git;
mod model;
mod sanitize;

pub use git::{BoundedGitRunner, GitOutput, GitRequest, GitRequestKind, GitRunner, GitRunnerError};
pub use model::AnalyticsPayload;

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
