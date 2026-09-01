use crate::git::{
    GitOutput, GitRequest, GitRunner, GitRunnerError, MAX_STDERR_BYTES, MAX_STDOUT_BYTES,
};
use crate::model::{
    AnalysisRange, AnalyticsCoverage, AnalyticsError, AnalyticsPayload, AttributionBucket,
    CommitAnalytics, ProviderModelAnalytics, RepositoryAnalytics, RepositoryCoverage,
    RepositoryState,
};
use crate::sanitize::{decimal, label, model, short_oid, Totals};
use chrono::{DateTime, Duration, Utc};
use std::collections::{BTreeMap, BTreeSet, HashMap};
use tokscale_core::{WorkspaceSessionFragment, WorkspaceSessionReport};

const MAX_REPOSITORIES: usize = 64;
const MAX_PARSED_COMMITS: usize = 500;
const MAX_RETURNED_COMMITS: usize = 200;

#[derive(Clone)]
struct MappedFragment {
    fragment: WorkspaceSessionFragment,
    root: String,
}
#[derive(Clone)]
struct RawCommit {
    oid: String,
    committed_at: DateTime<Utc>,
    pr: Option<i32>,
}
#[derive(Default)]
struct MutableBucket {
    totals: Totals,
    fragments: u64,
    reasons: BTreeMap<String, u64>,
}
impl MutableBucket {
    fn add(&mut self, f: &WorkspaceSessionFragment, reason: &str) {
        self.totals.add(&f.tokens, f.estimated_cost_usd);
        self.fragments += 1;
        bump(&mut self.reasons, reason);
    }
    fn reason(&mut self, reason: &str) {
        self.reason_by(reason, 1);
    }
    fn reason_by(&mut self, reason: &str, count: u64) {
        bump_by(&mut self.reasons, reason, count);
    }
    fn dto(self) -> AttributionBucket {
        AttributionBucket {
            usage: self.totals.dto(),
            fragments: self.fragments,
            reasons: self.reasons,
        }
    }
}
fn bump(map: &mut BTreeMap<String, u64>, code: &str) {
    bump_by(map, code, 1);
}
fn bump_by(map: &mut BTreeMap<String, u64>, code: &str, count: u64) {
    let entry = map.entry(code.to_owned()).or_default();
    *entry = entry.saturating_add(count);
}

pub(crate) fn build(
    report: WorkspaceSessionReport,
    generated_at: DateTime<Utc>,
    git: &dyn GitRunner,
) -> AnalyticsPayload {
    let start = generated_at - Duration::days(30);
    let global_timing_partial = report.timing_coverage_partial;
    let mut unattributed = MutableBucket::default();
    let mut coverage = AnalyticsCoverage::default();
    let mut errors = BTreeSet::new();
    let overflow = report
        .overflowed_fragment_observations
        .saturating_add(report.overflowed_model_observations)
        .saturating_add(u64::from(report.record_limit_reached));
    bump_by(&mut coverage.reasons, "recordLimitReached", overflow);
    unattributed.reason_by("recordLimitReached", overflow);
    if overflow > 0 {
        errors.insert(error("analytics", "recordLimitReached"));
    }
    let timing_overflow = report
        .overflowed_timing_observations
        .saturating_add(u64::from(report.timing_coverage_partial));
    bump_by(&mut coverage.reasons, "missingDuration", timing_overflow);
    unattributed.reason_by("missingDuration", timing_overflow);
    bump_by(&mut coverage.reasons, "recordLimitReached", timing_overflow);
    unattributed.reason_by("recordLimitReached", timing_overflow);
    let mut mapped = Vec::new();
    for fragment in report.fragments {
        if fragment.workspace_key.is_none()
            || fragment
                .workspace_key
                .as_deref()
                .is_some_and(|v| v.is_empty())
        {
            unattributed.add(&fragment, "missingWorkspace");
            coverage.unattributed_fragments += 1;
            bump(&mut coverage.reasons, "missingWorkspace");
            continue;
        }
        if !valid_fragment(&fragment, start, generated_at) {
            let reason = if !fragment.estimated_cost_usd.is_finite()
                || fragment.estimated_cost_usd < 0.0
                || !nonnegative_tokens(&fragment.tokens)
            {
                "missingCost"
            } else {
                "missingTimestamp"
            };
            unattributed.add(&fragment, reason);
            coverage.unattributed_fragments += 1;
            bump(&mut coverage.reasons, reason);
            continue;
        }
        let workspace = fragment.workspace_key.as_ref().expect("checked");
        let canonical_workspace =
            std::fs::canonicalize(workspace).unwrap_or_else(|_| workspace.into());
        match git.run(GitRequest::discover(canonical_workspace.clone())) {
            Ok(output) => match parse_root(&output) {
                Ok(root) if root_contains(&root, &canonical_workspace) => {
                    mapped.push(MappedFragment { fragment, root })
                }
                Ok(_) => {
                    unattributed.add(&fragment, "invalidWorkspace");
                    coverage.unattributed_fragments += 1;
                    bump(&mut coverage.reasons, "invalidWorkspace");
                }
                Err(code) => {
                    unattributed.add(&fragment, code);
                    coverage.unattributed_fragments += 1;
                    bump(&mut coverage.reasons, code);
                    errors.insert(error("git", code));
                }
            },
            Err(err) => {
                let code = git_code(&err);
                unattributed.add(&fragment, code);
                coverage.unattributed_fragments += 1;
                bump(&mut coverage.reasons, code);
                errors.insert(error(scope_for(&err), code));
            }
        }
    }
    mapped.sort_by(|a, b| {
        a.root
            .cmp(&b.root)
            .then(a.fragment.last_seen_ms.cmp(&b.fragment.last_seen_ms))
    });
    let mut roots = mapped.iter().map(|f| f.root.clone()).collect::<Vec<_>>();
    roots.dedup();
    let admitted: BTreeSet<_> = roots.iter().take(MAX_REPOSITORIES).cloned().collect();
    for value in mapped.iter().filter(|f| !admitted.contains(&f.root)) {
        unattributed.add(&value.fragment, "recordLimitReached");
        coverage.unattributed_fragments += 1;
        bump(&mut coverage.reasons, "recordLimitReached");
    }
    if roots.len() > MAX_REPOSITORIES {
        errors.insert(error("analytics", "recordLimitReached"));
    }
    let mut repositories = Vec::new();
    for (position, root) in roots.iter().take(MAX_REPOSITORIES).enumerate() {
        let fragments = mapped
            .iter()
            .filter(|f| &f.root == root)
            .cloned()
            .collect::<Vec<_>>();
        repositories.push(repository(
            position,
            root,
            fragments,
            BuildState {
                generated_at,
                global_timing_partial,
                git,
                unattributed: &mut unattributed,
                coverage: &mut coverage,
                errors: &mut errors,
            },
        ));
    }
    let mut labels = BTreeMap::<String, usize>::new();
    for repository in &repositories {
        *labels.entry(repository.label.clone()).or_default() += 1;
    }
    for repository in &mut repositories {
        if labels.get(&repository.label).copied().unwrap_or_default() > 1 {
            repository.label = format!("Repository {}", &repository.repository_id[..8]);
        }
    }
    repositories.sort_by(|a, b| {
        b.usage
            .estimated_cost_usd
            .parse::<f64>()
            .unwrap_or_default()
            .partial_cmp(
                &a.usage
                    .estimated_cost_usd
                    .parse::<f64>()
                    .unwrap_or_default(),
            )
            .unwrap_or(std::cmp::Ordering::Equal)
            .then(a.repository_id.cmp(&b.repository_id))
    });
    AnalyticsPayload {
        analysis_range: AnalysisRange {
            start,
            end: generated_at,
        },
        repositories,
        unattributed: unattributed.dto(),
        coverage,
        errors: errors.into_iter().collect(),
    }
}

fn valid_fragment(f: &WorkspaceSessionFragment, start: DateTime<Utc>, end: DateTime<Utc>) -> bool {
    f.last_seen_ms > 0
        && DateTime::from_timestamp_millis(f.last_seen_ms)
            .is_some_and(|time| time >= start && time <= end)
        && f.estimated_cost_usd.is_finite()
        && f.estimated_cost_usd >= 0.0
        && nonnegative_tokens(&f.tokens)
}
fn nonnegative_tokens(tokens: &tokscale_core::TokenBreakdown) -> bool {
    tokens.input >= 0
        && tokens.output >= 0
        && tokens.cache_read >= 0
        && tokens.cache_write >= 0
        && tokens.reasoning >= 0
}
fn root_contains(root: &str, workspace: &std::path::Path) -> bool {
    workspace.starts_with(std::path::Path::new(root))
}
fn parse_root(output: &GitOutput) -> Result<String, &'static str> {
    if output.stdout.len() > MAX_STDOUT_BYTES || output.stderr.len() > MAX_STDERR_BYTES {
        return Err("gitOutputLimitReached");
    }
    let root = std::str::from_utf8(&output.stdout)
        .map_err(|_| "invalidWorkspace")?
        .trim_end_matches(['\r', '\n']);
    if root.contains('\n') || root.contains('\r') {
        return Err("ambiguousRepository");
    }
    if root.is_empty() || root.len() > 4096 || root.chars().any(char::is_control) {
        Err("invalidWorkspace")
    } else {
        Ok(root.to_owned())
    }
}
fn error(scope: &str, code: &str) -> AnalyticsError {
    AnalyticsError {
        scope: scope.to_owned(),
        code: code.to_owned(),
    }
}
fn git_code(error: &GitRunnerError) -> &'static str {
    match error {
        GitRunnerError::TimedOut => "gitTimedOut",
        GitRunnerError::OutputLimitReached => "gitOutputLimitReached",
        GitRunnerError::RecordLimitReached => "recordLimitReached",
        GitRunnerError::CleanupFailed => "gitUnavailable",
        GitRunnerError::NotRepository => "nonRepositoryWorkspace",
        GitRunnerError::Unavailable => "gitUnavailable",
    }
}
fn scope_for(error: &GitRunnerError) -> &'static str {
    match error {
        GitRunnerError::Unavailable => "git",
        _ => "git",
    }
}

struct BuildState<'a> {
    generated_at: DateTime<Utc>,
    global_timing_partial: bool,
    git: &'a dyn GitRunner,
    unattributed: &'a mut MutableBucket,
    coverage: &'a mut AnalyticsCoverage,
    errors: &'a mut BTreeSet<AnalyticsError>,
}

fn repository(
    position: usize,
    root: &str,
    fragments: Vec<MappedFragment>,
    state: BuildState<'_>,
) -> RepositoryAnalytics {
    let id = format!("r{position:08x}");
    let mut total = Totals::default();
    let mut active_ms = 0_i64;
    let mut models: BTreeMap<(String, String), ModelTotal> = BTreeMap::new();
    for value in &fragments {
        total.add(&value.fragment.tokens, value.fragment.estimated_cost_usd);
        active_ms = active_ms.saturating_add(value.fragment.active_time_ms.max(0));
        add_models(&mut models, &value.fragment);
    }
    let mut repo_coverage = RepositoryCoverage {
        timing_partial: state.global_timing_partial
            || fragments
                .iter()
                .any(|value| value.fragment.timing_coverage_partial),
        ..Default::default()
    };
    if total.cost_partial {
        bump(&mut repo_coverage.reasons, "missingCost");
        state.errors.insert(error("repository", "missingCost"));
    }
    let (repository_state, mut parsed) = match state.git.run(GitRequest::commits(root.into())) {
        Ok(output) => match parse_commits(&output) {
            Ok((items, record_cap)) => {
                if record_cap {
                    bump(&mut repo_coverage.reasons, "recordLimitReached");
                    state
                        .errors
                        .insert(error("repository", "recordLimitReached"));
                }
                (RepositoryState::Available, items)
            }
            Err(code) => {
                bump(&mut repo_coverage.reasons, code);
                state.errors.insert(error("repository", code));
                (RepositoryState::Unavailable, Vec::new())
            }
        },
        Err(value) => {
            let code = if matches!(value, GitRunnerError::Unavailable) {
                "repositoryUnavailable"
            } else {
                git_code(&value)
            };
            bump(&mut repo_coverage.reasons, code);
            state.errors.insert(error("repository", code));
            (RepositoryState::Unavailable, Vec::new())
        }
    };
    parsed.sort_by(|a, b| b.committed_at.cmp(&a.committed_at).then(a.oid.cmp(&b.oid)));
    let mut assigned: HashMap<String, Totals> = HashMap::new();
    if matches!(repository_state, RepositoryState::Available) {
        for value in &fragments {
            let end = DateTime::from_timestamp_millis(value.fragment.last_seen_ms)
                .expect("validated before mapping");
            let limit = end + Duration::hours(4);
            let found = parsed
                .iter()
                .filter(|commit| commit.committed_at >= end && commit.committed_at <= limit)
                .min_by(|a, b| a.committed_at.cmp(&b.committed_at).then(a.oid.cmp(&b.oid)));
            if let Some(commit) = found {
                assigned
                    .entry(commit.oid.clone())
                    .or_default()
                    .add(&value.fragment.tokens, value.fragment.estimated_cost_usd);
                repo_coverage.assigned_fragments += 1;
                state.coverage.attributed_fragments += 1;
            } else {
                repo_coverage.unassigned_fragments += 1;
                let reason = if limit > state.generated_at {
                    "pendingCommitWindow"
                } else {
                    "noEligibleCommit"
                };
                bump(&mut repo_coverage.reasons, reason);
                state.unattributed.reason(reason);
                bump(&mut state.coverage.reasons, reason);
                state.coverage.attributed_fragments += 1;
            }
        }
    }
    let mut commits = parsed
        .into_iter()
        .filter_map(|raw| {
            assigned.remove(&raw.oid).and_then(|usage| {
                short_oid(&raw.oid).map(|commit_id| CommitAnalytics {
                    commit_id,
                    committed_at: raw.committed_at,
                    correlated_usage: usage.dto(),
                    pull_request_number: raw.pr,
                    coverage: if usage.cost_partial {
                        "partial".into()
                    } else {
                        "correlated".into()
                    },
                })
            })
        })
        .collect::<Vec<_>>();
    commits.sort_by(|a, b| {
        b.committed_at
            .cmp(&a.committed_at)
            .then(a.commit_id.cmp(&b.commit_id))
    });
    commits.truncate(MAX_RETURNED_COMMITS);
    let provider_models = models
        .into_iter()
        .map(|((provider, name), values)| ProviderModelAnalytics {
            provider,
            model: name,
            usage: values.total.dto(),
            cost_per_1k_tokens: (values.cost_coverage != "none")
                .then(|| nonzero_ratio(values.total.cost * 1000.0, values.total.tokens.total()))
                .flatten(),
            tokens_per_observed_active_hour: nonzero_ratio(
                values.total.tokens.total() as f64 * 3_600_000.0,
                values.active_ms,
            ),
            milliseconds_per_1k_tokens: nonzero_ratio(
                values.timed_duration_ms as f64 * 1000.0,
                values.timed_tokens,
            ),
            cost_coverage: values.cost_coverage,
            timing_coverage: if values.timed_tokens > 0 && !values.timing_partial {
                "complete".into()
            } else if values.timed_tokens > 0 {
                "partial".into()
            } else {
                "missingDuration".into()
            },
        })
        .collect();
    RepositoryAnalytics {
        repository_id: id.clone(),
        label: label(root, &id),
        state: repository_state,
        usage: total.dto(),
        observed_active_time_seconds: (active_ms / 1000).max(0).to_string(),
        provider_models,
        commits,
        coverage: repo_coverage,
    }
}
#[derive(Default)]
struct ModelTotal {
    total: Totals,
    active_ms: i64,
    timed_duration_ms: i64,
    timed_tokens: i64,
    cost_coverage: String,
    timing_partial: bool,
}
fn add_models(target: &mut BTreeMap<(String, String), ModelTotal>, f: &WorkspaceSessionFragment) {
    for entry in &f.models {
        let provider = match f.client.as_str() {
            "claude" | "codex" | "cursor" => f.client.clone(),
            _ => continue,
        };
        let item = target.entry((provider, model(&entry.model))).or_default();
        item.total.add(&entry.tokens, entry.estimated_cost_usd);
        item.active_ms = item.active_ms.saturating_add(f.active_time_ms.max(0));
        item.timed_duration_ms = item
            .timed_duration_ms
            .saturating_add(entry.timed_duration_ms.max(0));
        item.timed_tokens = item.timed_tokens.saturating_add(entry.timed_tokens.max(0));
        item.cost_coverage = fold_coverage(&item.cost_coverage, entry.cost_coverage);
        if item.total.cost_partial {
            item.cost_coverage = "partial".into();
        }
        item.timing_partial |= f.timing_coverage_partial || entry.timed_tokens <= 0;
    }
}
fn fold_coverage(current: &str, next: tokscale_core::CostCoverage) -> String {
    let next = match next {
        tokscale_core::CostCoverage::Complete => "complete",
        tokscale_core::CostCoverage::Partial => "partial",
        tokscale_core::CostCoverage::None => "none",
    };
    match (current, next) {
        ("", value) => value.into(),
        ("complete", "complete") => "complete".into(),
        ("none", "none") => "none".into(),
        _ => "partial".into(),
    }
}

#[cfg(test)]
#[allow(clippy::items_after_test_module)]
mod coverage_tests {
    use super::fold_coverage;
    use tokscale_core::CostCoverage;
    #[test]
    fn coverage_fold_is_order_independent_for_complete_and_none() {
        let left = fold_coverage(
            &fold_coverage("", CostCoverage::Complete),
            CostCoverage::None,
        );
        let right = fold_coverage(
            &fold_coverage("", CostCoverage::None),
            CostCoverage::Complete,
        );
        assert_eq!(left, "partial");
        assert_eq!(left, right);
    }
}
fn nonzero_ratio(numerator: f64, denominator: i64) -> Option<String> {
    (denominator > 0 && numerator.is_finite() && numerator >= 0.0)
        .then(|| decimal(numerator / denominator as f64))
}

fn parse_commits(output: &GitOutput) -> Result<(Vec<RawCommit>, bool), &'static str> {
    if output.stdout.len() > MAX_STDOUT_BYTES || output.stderr.len() > MAX_STDERR_BYTES {
        return Err("gitOutputLimitReached");
    }
    if output.stdout.is_empty() {
        return Ok((Vec::new(), false));
    }
    if output.stdout.last() != Some(&0) {
        return Err("repositoryUnavailable");
    }
    let fields = output.stdout[..output.stdout.len() - 1]
        .split(|b| *b == 0)
        .collect::<Vec<_>>();
    if fields.is_empty() {
        return Err("repositoryUnavailable");
    }
    if fields.len() % 3 != 0 {
        return Err("repositoryUnavailable");
    }
    let mut parsed = Vec::new();
    let mut ids = BTreeSet::new();
    for chunk in fields.chunks_exact(3) {
        if chunk[0].is_empty() || chunk[1].is_empty() || chunk[2].len() > 8192 {
            return Err("repositoryUnavailable");
        }
        let oid = std::str::from_utf8(chunk[0])
            .map_err(|_| "repositoryUnavailable")?
            .to_owned();
        if oid.len() != 40
            || !oid.bytes().all(|b| b.is_ascii_hexdigit())
            || oid.bytes().any(|b| b.is_ascii_uppercase())
            || !ids.insert(oid.clone())
        {
            return Err("repositoryUnavailable");
        }
        let committed_at = std::str::from_utf8(chunk[1])
            .ok()
            .and_then(|value| value.parse().ok())
            .ok_or("repositoryUnavailable")?;
        let message = std::str::from_utf8(chunk[2]).map_err(|_| "repositoryUnavailable")?;
        parsed.push(RawCommit {
            oid,
            committed_at,
            pr: parse_pr(message),
        });
        if parsed.len() == MAX_PARSED_COMMITS + 1 {
            parsed.truncate(MAX_PARSED_COMMITS);
            return Ok((parsed, true));
        }
    }
    Ok((parsed, false))
}
fn parse_pr(message: &str) -> Option<i32> {
    let bytes = message.as_bytes();
    let mut candidates = Vec::new();
    let mut malformed = false;
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i..].starts_with(b"(#") {
            let (end, value) = digits(bytes, i + 2);
            if end < bytes.len() && bytes[end] == b')' && token_boundary(bytes, i, end + 1) {
                candidates.push(value);
                i = end + 1;
                continue;
            }
            malformed = true;
        }
        if bytes[i..].starts_with(b"PR #") && (i == 0 || !is_word(bytes[i - 1])) {
            let (end, value) = digits(bytes, i + 4);
            if end > i + 4 && (end == bytes.len() || !is_word(bytes[end])) {
                candidates.push(value);
                i = end;
                continue;
            }
            malformed = true;
        }
        i += 1;
    }
    if malformed || candidates.len() != 1 {
        return None;
    }
    candidates
        .pop()
        .and_then(|value| value.parse::<i32>().ok())
        .filter(|value| *value >= 1)
}
fn digits(bytes: &[u8], mut index: usize) -> (usize, String) {
    let start = index;
    while index < bytes.len() && bytes[index].is_ascii_digit() {
        index += 1;
    }
    (
        index,
        std::str::from_utf8(&bytes[start..index])
            .unwrap_or_default()
            .to_owned(),
    )
}
fn is_word(value: u8) -> bool {
    value >= 128 || value.is_ascii_alphanumeric() || value == b'_'
}
fn token_boundary(bytes: &[u8], start: usize, end: usize) -> bool {
    (start == 0 || !is_word(bytes[start - 1])) && (end == bytes.len() || !is_word(bytes[end]))
}
