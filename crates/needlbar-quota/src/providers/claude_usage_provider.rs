//! Claude quota from `/usage` run by the user's installed `claude`.

use std::{env, path::PathBuf, sync::Arc, time::Instant};

use serde::Serialize;

use super::{
    claude_cli::ClaudeCliLocator,
    claude_usage_probe::{
        run_usage_probe, UsageProbeControl, UsageProbeEnvironment, UsageProbeFailure,
        UsageProbeLimits,
    },
    claude_usage_report::{
        parse_usage_report_stream, ClaudeUsageReportOutcome, ClaudeUsageRowKind,
        ClaudeUsageRowSummary,
    },
};
use crate::{
    ClaudeQuotaFailureOrigin, ProviderId, ProviderQuotaSnapshot, QuotaError, QuotaErrorCode,
};

/// What diagnostics may record about a run: closed values and counts only.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClaudeUsageProbeSummary {
    pub duration_ms: u64,
    pub row_kinds: Vec<ClaudeUsageRowKind>,
    pub unknown_row_count: u32,
    pub skipped_row_count: u32,
}

pub struct ClaudeUsageReportRun {
    pub result: Result<ProviderQuotaSnapshot, QuotaError>,
    pub summary: Option<ClaudeUsageProbeSummary>,
}

pub struct ClaudeUsageReportProvider {
    locator: ClaudeCliLocator,
    environment: UsageProbeEnvironment,
    limits: UsageProbeLimits,
    control: Arc<UsageProbeControl>,
    run_id: u64,
}

impl ClaudeUsageReportProvider {
    pub fn new(run_id: u64) -> Self {
        let home = env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("/nonexistent"));
        Self::with_parts(
            ClaudeCliLocator::for_home(&home),
            UsageProbeEnvironment::from_process(),
            UsageProbeLimits::default(),
            UsageProbeControl::shared(),
            run_id,
        )
    }

    pub fn with_parts(
        locator: ClaudeCliLocator,
        environment: UsageProbeEnvironment,
        limits: UsageProbeLimits,
        control: Arc<UsageProbeControl>,
        run_id: u64,
    ) -> Self {
        Self {
            locator,
            environment,
            limits,
            control,
            run_id,
        }
    }

    pub async fn run(&self) -> ClaudeUsageReportRun {
        let started = Instant::now();
        let Some(executable) = self.locator.locate() else {
            return finished(
                Err(failure(
                    QuotaErrorCode::NotInstalled,
                    "Claude Code was not found on this Mac.",
                    ClaudeQuotaFailureOrigin::ClaudeCliNotFound,
                )),
                ClaudeUsageRowSummary::default(),
                started,
            );
        };
        let output = run_usage_probe(
            &executable,
            &self.environment,
            self.limits,
            &self.control,
            self.run_id,
        )
        .await;
        let bytes = match output {
            Ok(bytes) => bytes,
            Err(UsageProbeFailure::Cancelled) => {
                return ClaudeUsageReportRun {
                    result: Err(QuotaError::claude_usage_report_cancelled()),
                    summary: None,
                };
            }
            Err(probe_failure) => {
                return finished(
                    Err(from_probe_failure(probe_failure)),
                    ClaudeUsageRowSummary::default(),
                    started,
                );
            }
        };
        let (result, rows) = match parse_usage_report_stream(&bytes) {
            ClaudeUsageReportOutcome::Windows { windows, rows } => (
                Ok(ProviderQuotaSnapshot {
                    provider: ProviderId::Claude,
                    windows,
                }),
                rows,
            ),
            ClaudeUsageReportOutcome::NoUsageAvailable { rows } => (
                // The CLI also reports null limits while its own usage fetch is
                // failing, so this is a failed check, not proof of a signed-out
                // user. It retries under backoff like any other check failure.
                Err(failure(
                    QuotaErrorCode::ProviderUnavailable,
                    "Claude Code reported no usage.",
                    ClaudeQuotaFailureOrigin::UsageReportNoUsage,
                )),
                rows,
            ),
            ClaudeUsageReportOutcome::RateLimited => (
                Err(failure(
                    QuotaErrorCode::RateLimited,
                    "The Claude usage check was rate limited.",
                    ClaudeQuotaFailureOrigin::UsageReportRateLimited,
                )),
                ClaudeUsageRowSummary::default(),
            ),
            ClaudeUsageReportOutcome::FormatChanged { rows } => (
                Err(failure(
                    QuotaErrorCode::SchemaChanged,
                    "Claude usage data was not in the expected format.",
                    ClaudeQuotaFailureOrigin::UsageReportFormatChanged,
                )),
                rows,
            ),
        };
        finished(result, rows, started)
    }
}

fn finished(
    result: Result<ProviderQuotaSnapshot, QuotaError>,
    rows: ClaudeUsageRowSummary,
    started: Instant,
) -> ClaudeUsageReportRun {
    ClaudeUsageReportRun {
        result,
        summary: Some(ClaudeUsageProbeSummary {
            duration_ms: u64::try_from(started.elapsed().as_millis()).unwrap_or(u64::MAX),
            row_kinds: rows.row_kinds,
            unknown_row_count: rows.unknown_row_count,
            skipped_row_count: rows.skipped_row_count,
        }),
    }
}

fn failure(
    code: QuotaErrorCode,
    message: &'static str,
    origin: ClaudeQuotaFailureOrigin,
) -> QuotaError {
    QuotaError::new(Some(ProviderId::Claude), code, message).with_claude_failure_origin(origin)
}

fn from_probe_failure(probe_failure: UsageProbeFailure) -> QuotaError {
    let (message, origin) = match probe_failure {
        UsageProbeFailure::TimedOut => (
            "The Claude usage check timed out.",
            ClaudeQuotaFailureOrigin::UsageProbeTimedOut,
        ),
        UsageProbeFailure::OutputTooLarge => (
            "The Claude usage check produced too much output.",
            ClaudeQuotaFailureOrigin::UsageProbeOutputTooLarge,
        ),
        UsageProbeFailure::LaunchFailed
        | UsageProbeFailure::ExitedUnsuccessfully
        | UsageProbeFailure::Cancelled => (
            "The Claude usage check did not finish.",
            ClaudeQuotaFailureOrigin::UsageProbeFailed,
        ),
    };
    failure(QuotaErrorCode::ProviderUnavailable, message, origin)
}
