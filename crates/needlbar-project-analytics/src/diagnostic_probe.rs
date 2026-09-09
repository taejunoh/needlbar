use crate::correlation::CorrelationObserver;
use crate::git::GitRunnerError;
use chrono::{DateTime, Utc};
use serde::Serialize;
use std::collections::BTreeMap;
use std::io::ErrorKind;
use tokscale_core::{WorkspaceSessionFragment, WorkspaceSessionReport};

#[derive(Debug, Default, Serialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProviderProbeCounts {
    pub timestamp_unavailable_after_normalization: u64,
    pub mapped_fragments: u64,
    pub unmapped_fragments: u64,
}

#[derive(Debug, Default, Serialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct FragmentProbeCount {
    pub fragments: u64,
}

#[derive(Debug, Default, Serialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CanonicalizationProbeCounts {
    pub path_absent: u64,
    pub path_inaccessible: u64,
    pub path_malformed: u64,
    pub path_other: u64,
}

#[derive(Debug, Default, Serialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct DiscoveryProbeCounts {
    pub non_repository: u64,
    pub cleanup_failures: u64,
    pub unavailable_stage_unknown: u64,
    pub timed_out: u64,
    pub output_limited: u64,
    pub record_limited: u64,
}

#[derive(Debug, Default, Serialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MappingProbeCounts {
    pub mapped_fragments: u64,
    pub unmapped_fragments: u64,
}

#[derive(Debug, Default, Serialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProbeCaps {
    pub overflowed_timing_observations: u64,
    pub overflowed_fragment_observations: u64,
    pub overflowed_model_observations: u64,
    pub record_limit_flag: u64,
}

#[derive(Debug, Serialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AnalyticsDiagnosticProbe {
    pub by_provider: BTreeMap<String, ProviderProbeCounts>,
    pub timestamp_unavailable_after_normalization: FragmentProbeCount,
    pub canonicalization: CanonicalizationProbeCounts,
    pub discovery: DiscoveryProbeCounts,
    pub mapping: MappingProbeCounts,
    pub caps: ProbeCaps,
}

impl Default for AnalyticsDiagnosticProbe {
    fn default() -> Self {
        let mut by_provider = BTreeMap::new();
        for provider in ["claude", "codex", "cursor", "other"] {
            by_provider.insert(provider.to_owned(), ProviderProbeCounts::default());
        }
        Self {
            by_provider,
            timestamp_unavailable_after_normalization: FragmentProbeCount::default(),
            canonicalization: CanonicalizationProbeCounts::default(),
            discovery: DiscoveryProbeCounts::default(),
            mapping: MappingProbeCounts::default(),
            caps: ProbeCaps::default(),
        }
    }
}

pub(crate) struct ProbeObserver {
    probe: AnalyticsDiagnosticProbe,
}

impl ProbeObserver {
    pub(crate) fn new(report: &WorkspaceSessionReport) -> Self {
        Self {
            probe: AnalyticsDiagnosticProbe {
                caps: ProbeCaps {
                    overflowed_timing_observations: report.overflowed_timing_observations,
                    overflowed_fragment_observations: report.overflowed_fragment_observations,
                    overflowed_model_observations: report.overflowed_model_observations,
                    record_limit_flag: u64::from(report.record_limit_reached),
                },
                ..Default::default()
            },
        }
    }

    pub(crate) fn into_probe(self) -> AnalyticsDiagnosticProbe {
        self.probe
    }

    fn provider(&mut self, fragment: &WorkspaceSessionFragment) -> &mut ProviderProbeCounts {
        let key = match fragment.client.as_str() {
            "claude" | "codex" | "cursor" => fragment.client.as_str(),
            _ => "other",
        };
        self.probe
            .by_provider
            .get_mut(key)
            .expect("fixed provider keys are initialized")
    }
}

impl CorrelationObserver for ProbeObserver {
    fn timestamp_unavailable_after_normalization(&mut self, fragment: &WorkspaceSessionFragment) {
        self.probe
            .timestamp_unavailable_after_normalization
            .fragments = self
            .probe
            .timestamp_unavailable_after_normalization
            .fragments
            .saturating_add(1);
        let provider = self.provider(fragment);
        provider.timestamp_unavailable_after_normalization = provider
            .timestamp_unavailable_after_normalization
            .saturating_add(1);
    }

    fn canonicalization_error(&mut self, error: ErrorKind) {
        let count = match error {
            ErrorKind::NotFound => &mut self.probe.canonicalization.path_absent,
            ErrorKind::PermissionDenied => &mut self.probe.canonicalization.path_inaccessible,
            ErrorKind::InvalidInput | ErrorKind::InvalidData => {
                &mut self.probe.canonicalization.path_malformed
            }
            _ => &mut self.probe.canonicalization.path_other,
        };
        *count = count.saturating_add(1);
    }

    fn discovery_error(&mut self, error: &GitRunnerError) {
        let count = match error {
            GitRunnerError::NotRepository => &mut self.probe.discovery.non_repository,
            GitRunnerError::CleanupFailed => &mut self.probe.discovery.cleanup_failures,
            GitRunnerError::Unavailable => &mut self.probe.discovery.unavailable_stage_unknown,
            GitRunnerError::TimedOut => &mut self.probe.discovery.timed_out,
            GitRunnerError::OutputLimitReached => &mut self.probe.discovery.output_limited,
            GitRunnerError::RecordLimitReached => &mut self.probe.discovery.record_limited,
        };
        *count = count.saturating_add(1);
    }

    fn discovery_output_limited(&mut self) {
        self.probe.discovery.output_limited = self.probe.discovery.output_limited.saturating_add(1);
    }

    fn mapped_fragment(&mut self, fragment: &WorkspaceSessionFragment) {
        self.probe.mapping.mapped_fragments = self.probe.mapping.mapped_fragments.saturating_add(1);
        let provider = self.provider(fragment);
        provider.mapped_fragments = provider.mapped_fragments.saturating_add(1);
    }

    fn unmapped_fragment(&mut self, fragment: &WorkspaceSessionFragment) {
        self.probe.mapping.unmapped_fragments =
            self.probe.mapping.unmapped_fragments.saturating_add(1);
        let provider = self.provider(fragment);
        provider.unmapped_fragments = provider.unmapped_fragments.saturating_add(1);
    }
}

pub(crate) fn build(
    report: WorkspaceSessionReport,
    generated_at: DateTime<Utc>,
    git: &dyn crate::GitRunner,
) -> AnalyticsDiagnosticProbe {
    let mut observer = ProbeObserver::new(&report);
    let _payload =
        crate::correlation::build_with_observer(report, generated_at, git, &mut observer);
    observer.into_probe()
}
