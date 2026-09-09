# Analytics Summary-First Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the native Analytics window summary-first and truthful about repository attribution, unlinked fragments, timing evidence, and diagnostic limits, while gathering only a one-shot, aggregate-only attribution probe before any correction is considered.

**Architecture:** Keep `needlbar-project-analytics` responsible for bounded local correlation and a feature-gated aggregate probe; the probe must not cross `needlbar_analytics_snapshot_json`, `needlbar.h`, Swift decoding, or a release build. Add pure summary/diagnostic presentation semantics to `NeedlbarCore`, derived only from the validated existing `AnalyticsSnapshot`; `AnalyticsView` owns only adaptive AppKit/SwiftUI layout and accessibility.

**Tech Stack:** Rust/Cargo, pinned `tokscale-core`, Swift 6/AppKit/SwiftUI, Swift Testing, Rust integration tests, existing native acceptance harness.

---

## Locked boundaries

- Start in an isolated worktree with the pinned vendor revision (`ecfb694`); never reset or repair main's dirty `vendor/tokscale-core`, `.logs/`, or brainstorming files.
- Do not alter `needlbar.analytics.v1`, `AnalyticsSnapshot`, `AnalyticsBridgeDecoder`, `needlbar_analytics_snapshot_json`, `Sources/CNeedlbar/include/needlbar.h`, pricing, caps, providers, source traversal, refresh scheduling, cache/persistence, or networking.
- `WorkspaceSessionReport` has already normalized timestamps. The diagnostic report may count `last_seen_ms <= 0` as **timestamp unavailable after normalization**, but must not claim absent versus invalid source timestamps.
- Existing `recordLimitReached` is a mixed legacy counter: the adapter currently adds timing overflow into both `missingDuration` and `recordLimitReached`. Do not add those values, infer a cause from equal counts, or relabel either as a fragment count. Until a separately reviewed adapter/schema amendment, UI copy must call it a **mixed bounded-processing signal (unit/cause not separately available)**.
- A repository count and `AnalyticsAttributionBucket.fragments` are independent counts, never a fraction. Existing percentage is allowed only for `attributedFragments / (attributedFragments + unattributedFragments)` when the sum is non-zero and non-overflowing, with that denominator stated.
- No attribution/parser/vendor correction is authorized by this plan. After the one-shot evidence is reviewed, a correction needs a reviewed amendment with a minimal fix and a regression fixture.

## File map

- `crates/needlbar-project-analytics/{Cargo.toml,src/lib.rs,src/correlation.rs,src/diagnostic_probe.rs}` — feature-gated, in-process sanitized aggregate observer; normal builds retain the present payload path.
- `crates/needlbar-bridge/{Cargo.toml,src/analytics.rs}` — explicit, ignored Rust-only unit-test invocation reusing `ReportOptions`/the existing bounded source pipeline; no C export.
- `crates/needlbar-project-analytics/tests/{diagnostic_probe.rs,privacy.rs}` — deterministic fake-Git counts and raw-value redaction canaries.
- `Sources/NeedlbarCore/Analytics/AnalyticsPresentation.swift` — UI-free repository/active-time/linkage and diagnostic-unit semantics derived from `AnalyticsSnapshot`.
- `Tests/NeedlbarCoreTests/AnalyticsPresentationTests.swift` — complete/empty/zero/partial/overflow semantic fixtures.
- `Sources/Needlbar/Analytics/AnalyticsView.swift` — card/grid/scroll/disclosure layout, existing string formatting, accessible state and conservative diagnostics copy.
- `Tests/NeedlbarTests/AnalyticsWindowControllerTests.swift` — view-host layout and disclosure/accessibility fixtures.
- `Fixtures/analytics/{workspace-session-fixture.json,expected-payload.json}` — remain unchanged unless an existing fixture is explicitly extended with only sanitized expected values; no raw diagnostic artifact is checked in.
- `docs/STATUS.md` — evidence and next continuation point after each completed task or changed blocker; final acceptance recorded only after its gates pass.

### Task 1: Add the nonshipping aggregate-only diagnostic probe

Completed at `d8eca27` plus `464011c`, with spec/quality re-review PASS.
Actual internal feature-only names are `FragmentProbeCount`,
`CanonicalizationProbeCounts`, `DiscoveryProbeCounts`, `MappingProbeCounts`;
they replace the shorter illustrative names below without any C ABI change.
The automated nonshipping gate additionally owns `Makefile`, `scripts/build-rust.sh`,
`scripts/verify-public-bridge-surface.sh` and its synthetic behavior test under
`scripts/tests/verify-public-bridge-surface-tests.sh`. Final generic-marker delta
had fresh focused/normal-build verification; full final-tree gates remain Task 5.

**Files:**
- Modify: `crates/needlbar-project-analytics/Cargo.toml`, `crates/needlbar-project-analytics/src/lib.rs`, `crates/needlbar-project-analytics/src/correlation.rs`
- Create: `crates/needlbar-project-analytics/src/diagnostic_probe.rs`
- Modify: `crates/needlbar-bridge/Cargo.toml`, `crates/needlbar-bridge/src/analytics.rs`
- Test: `crates/needlbar-project-analytics/tests/diagnostic_probe.rs`, `crates/needlbar-project-analytics/tests/privacy.rs`

- [x] **Step 1: Write failing deterministic probe and redaction tests.**

First add only `analytics-diagnostic-probe = []` in `crates/needlbar-project-analytics/Cargo.toml`, `analytics-diagnostic-probe = ["needlbar-project-analytics/analytics-diagnostic-probe"]` in `crates/needlbar-bridge/Cargo.toml`, and the feature-gated test modules. Use this complete local fixture in `crates/needlbar-project-analytics/tests/diagnostic_probe.rs`; it is derived from the existing correlation test types and exposes no live source:

```rust
use chrono::{DateTime, Utc};
use needlbar_project_analytics::{build_analytics_diagnostic_probe, GitOutput, GitRequest, GitRunner, GitRunnerError};
use std::collections::VecDeque;
use std::sync::Mutex;
use tokscale_core::{TokenBreakdown, WorkspaceSessionFragment, WorkspaceSessionReport};

struct FakeGitRunner(Mutex<VecDeque<Result<GitOutput, GitRunnerError>>>);
impl GitRunner for FakeGitRunner {
    fn run(&self, _: GitRequest) -> Result<GitOutput, GitRunnerError> {
        self.0.lock().unwrap().pop_front().unwrap()
    }
}
fn fixed_time() -> DateTime<Utc> { "2026-09-01T16:00:00Z".parse().unwrap() }
fn fragment(workspace_key: Option<&str>, last_seen_ms: i64) -> WorkspaceSessionFragment {
    WorkspaceSessionFragment {
        client: "codex".into(), workspace_key: workspace_key.map(str::to_owned),
        session_id: "session-probe-canary".into(), first_seen_ms: last_seen_ms, last_seen_ms,
        active_time_ms: 0, timing_coverage_partial: false,
        tokens: TokenBreakdown::default(), message_count: 0, estimated_cost_usd: 0.0, models: vec![],
    }
}
fn report() -> WorkspaceSessionReport {
    WorkspaceSessionReport {
        fragments: vec![
            fragment(Some("/private/probe-path-canary"), 0),
            fragment(Some("/private/probe-path-canary"), fixed_time().timestamp_millis() - 60_000),
        ],
        processing_time_ms: 0, record_limit_reached: true, timing_coverage_partial: true,
        overflowed_fragment_observations: 3, overflowed_timing_observations: 7, overflowed_model_observations: 2,
    }
}
```

```rust
#[test]
fn probe_keeps_units_separate_and_never_serializes_source_values() {
    let fake_git = FakeGitRunner(Mutex::new(VecDeque::from([Err(GitRunnerError::CleanupFailed)])));
    let probe = build_analytics_diagnostic_probe(report(), fixed_time(), &fake_git);
    assert_eq!(probe.timestamp_unavailable_after_normalization.fragments, 1);
    assert_eq!(probe.discovery.cleanup_failures, 1);
    assert_eq!(probe.caps.overflowed_timing_observations, 7);
    assert_eq!(probe.caps.overflowed_fragment_observations, 3);
    assert_eq!(probe.caps.overflowed_model_observations, 2);
    assert_eq!(probe.caps.record_limit_flag, 1);
    assert_eq!(probe.by_provider["codex"].timestamp_unavailable_after_normalization, 1);
    let text = serde_json::to_string(&probe).unwrap();
    for forbidden in ["/private/probe-path-canary", "session-probe-canary", "raw-git-canary"] {
        assert!(!text.contains(forbidden));
    }
}
```

Extend the same test with a fake successful discovery `GitOutput::new(b"/private/raw-git-canary\n".to_vec(), vec![])`; assert that neither its bytes nor the session/path canaries appear in `serde_json::to_string(&probe)` or `format!("{probe:?}")`.

- [x] **Step 2: Run the RED test.**

Run: `cargo test -p needlbar-project-analytics --features analytics-diagnostic-probe --test diagnostic_probe`

Expected: compile failure because `build_analytics_diagnostic_probe` and `AnalyticsDiagnosticProbe` do not exist. The declared feature ensures this test is compiled rather than silently skipped.

- [x] **Step 3: Implement one feature-gated, observer-backed probe without changing the payload or ABI.**

Export the API only under the feature in `src/lib.rs`; have `correlation::build` use a no-op observer and have the probe reuse the same validation, canonicalization fallback, `GitRunner::run`, caps, and result branches. It records the fixed provider categories below and only numeric counters; it never stores a `PathBuf`, `String` derived from a path/error/output, token amount, cost, session ID, or model label.

```rust
#[derive(Debug, Default, Serialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AnalyticsDiagnosticProbe {
    pub by_provider: BTreeMap<String, ProviderProbeCounts>,
    pub timestamp_unavailable_after_normalization: ProbeCount,
    pub canonicalization: CanonicalizationCounts,
    pub discovery: DiscoveryCounts,
    pub mapping: MappingCounts,
    pub caps: ProbeCaps,
}

#[derive(Debug, Default, Serialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProviderProbeCounts { pub timestamp_unavailable_after_normalization: u64, pub mapped_fragments: u64, pub unmapped_fragments: u64 }

#[derive(Debug, Default, Serialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProbeCount { pub fragments: u64 }

#[derive(Debug, Default, Serialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CanonicalizationCounts { pub path_absent: u64, pub path_inaccessible: u64, pub path_malformed: u64, pub path_other: u64 }

#[derive(Debug, Default, Serialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct DiscoveryCounts { pub non_repository: u64, pub cleanup_failures: u64, pub unavailable_stage_unknown: u64, pub timed_out: u64, pub output_limited: u64, pub record_limited: u64 }

#[derive(Debug, Default, Serialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MappingCounts { pub mapped_fragments: u64, pub unmapped_fragments: u64 }

#[derive(Debug, Default, Serialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProbeCaps { pub overflowed_timing_observations: u64, pub overflowed_fragment_observations: u64, pub overflowed_model_observations: u64, pub record_limit_flag: u64 }

pub fn build_analytics_diagnostic_probe(report: WorkspaceSessionReport, generated_at: DateTime<Utc>, git: &dyn GitRunner) -> AnalyticsDiagnosticProbe
```

Use only the fixed BTreeMap keys `claude`, `codex`, `cursor`, and `other`; the fixture asserts that no caller-provided provider/model text becomes a key. Classify `std::io::ErrorKind::{NotFound, PermissionDenied, InvalidInput, InvalidData}` as `pathAbsent`, `pathInaccessible`, `pathMalformed`, and `pathOther`; retain the present fallback-to-original-path behavior. `GitRunnerError::Unavailable` is `unavailableStageUnknown`, not a spawn failure: the current `GitRunner` result cannot distinguish runner canonicalization, spawn, reader, or other unavailable paths. `CleanupFailed` is counted separately.

In `needlbar-bridge`, factor the present source scan in `analytics.rs` into a private shared function accepting the existing `generated_at`; `collect_analytics()` and the feature-gated Rust-only function call it. No `extern "C"`, `#[no_mangle]`, header declaration, Swift call, or production command is added.

```rust
#[cfg(feature = "analytics-diagnostic-probe")]
fn collect_analytics_diagnostic_probe() -> Result<needlbar_project_analytics::AnalyticsDiagnosticProbe, &'static str> {
    let generated_at = Utc::now();
    let report = collect_workspace_session_report(generated_at)?;
    Ok(needlbar_project_analytics::build_analytics_diagnostic_probe(
        report,
        generated_at,
        &BoundedGitRunner::default(),
    ))
}
```

- [x] **Step 4: Add explicit one-shot invocation and prove it is nonshipping.**

Insert the ignored unit test inside the existing `mod tests` in `crates/needlbar-bridge/src/analytics.rs` (not at module root). It serializes only the returned aggregate struct to stdout and does no file write. It is the sole permitted live invocation:

```rust
#[cfg(feature = "analytics-diagnostic-probe")]
#[test]
#[ignore = "explicit local aggregate-only diagnostics"]
fn one_shot_local_probe_is_json_and_has_no_ffi_surface() {
    let probe = super::collect_analytics_diagnostic_probe().unwrap();
    println!("{}", serde_json::to_string(&probe).unwrap());
}
```

Add a normal-build contract assertion that `Sources/CNeedlbar/include/needlbar.h` contains no `diagnostic_probe` and `nm -gU target/release/libneedlbar_bridge.a` contains neither `analytics_diagnostic_probe` nor `needlbar_test_`. Do not run the ignored test during CI/package verification; an investigator runs it once only after fixture tests pass.

- [x] **Step 5: Run narrow tests and commit.**

Run: `cargo test -p needlbar-project-analytics --features analytics-diagnostic-probe --test diagnostic_probe && cargo test -p needlbar-project-analytics --features analytics-diagnostic-probe --test privacy && cargo test -p needlbar-bridge --features analytics-diagnostic-probe analytics::tests::one_shot_local_probe_is_json_and_has_no_ffi_surface -- --ignored --exact --nocapture`

Expected: fixture/privacy tests pass; the final explicit command runs exactly one ignored test and emits one sanitized JSON object with counters only. Record its aggregate output outside the repository and state unknown stage/timestamp limits in `docs/STATUS.md`; do not convert it into an attribution fix.

Commit: `git add crates/needlbar-project-analytics/Cargo.toml crates/needlbar-project-analytics/src/lib.rs crates/needlbar-project-analytics/src/correlation.rs crates/needlbar-project-analytics/src/diagnostic_probe.rs crates/needlbar-project-analytics/tests/diagnostic_probe.rs crates/needlbar-project-analytics/tests/privacy.rs crates/needlbar-bridge/Cargo.toml crates/needlbar-bridge/src/analytics.rs && git commit -m "test: add aggregate analytics diagnostic probe"`

### Task 2: Define test-first Core presentation semantics

**Files:**
- Create: `Sources/NeedlbarCore/Analytics/AnalyticsPresentation.swift`
- Create: `Tests/NeedlbarCoreTests/AnalyticsPresentationTests.swift`

- [ ] **Step 1: Add failing formatter tests for all truthful states.**

Add Core fixtures for: no repositories with unlinked fragments; no data; one repository with genuine `$0.00` and `0s`; mixed attribution with partial pricing; overflow signals; and a maximum snapshot. Define the named cases using the fixture constructor in the implementation detail section below. Test the Core facts below; the App target supplies localized UI strings.

```swift
#expect(AnalyticsPresentation.summary(for: snapshotWithoutRepositories).repositoryAttributedCostUSD == nil)
#expect(AnalyticsPresentation.summary(for: validZeroSnapshot).repositoryAttributedCostUSD == .zero)
#expect(AnalyticsPresentation.summary(for: snapshotWithoutRepositories).observedAIActivitySeconds == nil)
#expect(AnalyticsPresentation.summary(for: validZeroSnapshot).observedAIActivitySeconds == 0)
#expect(AnalyticsPresentation.summary(for: mixedSnapshot).linkedRepositoryCount == 1)
#expect(AnalyticsPresentation.summary(for: mixedSnapshot).unlinkedFragmentCount == 7)
#expect(AnalyticsPresentation.diagnostics(for: mixedCounterSnapshot).first?.unit == .mixedBoundedProcessing)
```

- [ ] **Step 2: Run the RED test.**

Run: `make swift-test SWIFT_TEST_FILTER=AnalyticsPresentationTests`

Expected: compile failure because `AnalyticsPresentation` does not exist.

- [ ] **Step 3: Implement pure formatter helpers before changing view structure.**

Keep `AnalyticsSnapshot` unchanged. Create this UI-free Core model and computation; all values are validated snapshot values, not strings for the view:

```swift
import Foundation

public enum AnalyticsDiagnosticUnit: Sendable, Equatable {
    case fragments
    case observations
    case inspectionFailures
    case mixedBoundedProcessing
}

public struct AnalyticsPresentationSummary: Sendable, Equatable {
    public let repositoryAttributedCostUSD: Decimal?
    public let repositoryCostIsKnownSubtotal: Bool
    public let observedAIActivitySeconds: UInt64?
    public let linkedRepositoryCount: UInt64
    public let unlinkedFragmentCount: UInt64
    public let eligibleFragmentCount: UInt64?
}

public struct AnalyticsPresentationDiagnostic: Sendable, Equatable {
    public let code: String
    public let count: UInt64
    public let unit: AnalyticsDiagnosticUnit
}

public enum AnalyticsPresentation {
    public static func summary(for snapshot: AnalyticsSnapshot) -> AnalyticsPresentationSummary
    public static func diagnostics(for snapshot: AnalyticsSnapshot) -> [AnalyticsPresentationDiagnostic]
}
```

`summary(for:)` returns nil cost/activity for `repositories.isEmpty`; otherwise it uses checked `UInt64.addingReportingOverflow` for activity, so a valid repository value of zero remains `0`. It sums only repository cost; `unattributed.usage` remains separate. `eligibleFragmentCount` is a checked sum of `coverage.attributedFragments` and `coverage.unattributedFragments`, nil for zero/overflow. `repositoryCostIsKnownSubtotal` preserves the existing missing-cost/cap semantics. `diagnostics(for:)` gives `recordLimitReached` `.mixedBoundedProcessing`, `missingDuration` `.observations`, `gitOutputLimitReached`, `gitTimedOut`, and `gitUnavailable` `.inspectionFailures`, and all other existing coverage reasons `.fragments`; it does not add counts or manufacture a cause.

- [ ] **Step 4: Run the focused test and commit.**

Run: `make swift-test SWIFT_TEST_FILTER=AnalyticsPresentationTests`

Expected: all `AnalyticsPresentationTests` pass; no Swift view/controller behavior has changed in this task.

Commit: `git add Sources/NeedlbarCore/Analytics/AnalyticsPresentation.swift Tests/NeedlbarCoreTests/AnalyticsPresentationTests.swift && git commit -m "feat: define analytics presentation semantics"`

### Task 3: Build the adaptive summary-first Analytics view

**Files:**
- Modify: `Sources/Needlbar/Analytics/AnalyticsView.swift`
- Test: `Tests/NeedlbarTests/AnalyticsWindowControllerTests.swift`

- [ ] **Step 1: Add failing hosted-view contract tests.**

At `760x520` and the existing minimum `640x400`, host `AnalyticsView` with the no-repository, mixed, and maximum snapshots. Assert that the fixed header/Refresh accessibility values, Core-derived summary labels (`— · No linked repositories`, valid `$0.00`, and valid `0s`), Unattributed heading, Diagnostics disclosure, Estimate definition disclosure, long-label wrapping, and final disclosure accessibility element exist. Continue asserting refresh is disabled while `viewModel.isLoading`.

- [ ] **Step 2: Run the RED test.**

Run: `make swift-test SWIFT_TEST_FILTER=AnalyticsWindowControllerTests`

Expected: assertions fail because the new card labels/disclosures are absent.

- [ ] **Step 3: Replace only `AnalyticsView` presentation composition.**

Use `AnalyticsPresentation.summary(for:)` and `AnalyticsPresentation.diagnostics(for:)`; do not calculate evidence meaning in `AnalyticsView`. Keep `AnalyticsWindowController`, refresh action, repository sort order, provider/model and commit disclosure content. Move the compact header outside the vertical `ScrollView`, then use `LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)])` for three summary cards inside it. Render, in order: `Repository-attributed estimate`, `Repository linkage`, `Observed AI activity`; `Repositories`; `Unattributed`; collapsed `Diagnostics`; collapsed `Estimate definition`. Use `.fixedSize(horizontal: false, vertical: true)` for model/diagnostic text instead of the current one-line clipping. Disclosure controls receive distinct labels, the existing expansion hint, and an accessibility value of `Expanded` or `Collapsed` bound to state. Warning color supplements text rather than replacing it.

Diagnostics lists each reason with its unit in its own row: `fragments`, `observations`, `inspection failures`, or the literal mixed-counter warning. It never adds them. The Unattributed section says timestamp coverage can be incomplete and its amount is not a verified 30-day total; it does not promise that Refresh repairs source metadata. Retain the stale last-good/status copy and never render bridge errors.

- [ ] **Step 4: Run focused tests and commit.**

Run: `make swift-test SWIFT_TEST_FILTER=AnalyticsWindowControllerTests`

Expected: hosted-view and formatter tests pass; no existing controller/state test regresses.

Commit: `git add Sources/Needlbar/Analytics/AnalyticsView.swift Tests/NeedlbarTests/AnalyticsWindowControllerTests.swift && git commit -m "feat: present analytics summaries first"`

### Task 4: Verify native fixture, appearance, accessibility, and scroll acceptance

**Files:**
- Modify: `Tests/NeedlbarTests/AnalyticsWindowControllerTests.swift`

- [ ] **Step 1: Add mocked native-host acceptance assertions.**

Use the existing `AnalyticsSnapshot` test builders and `NSHostingView(rootView: AnalyticsView(viewModel:))`, not the production collector, to cover loading, fresh complete, partial/mixed legacy counter, stale last-good, unavailable, empty repositories with unlinked usage, populated expanded rows, default/minimum sizes, vertical scroll reachability, and light/dark appearance. The mocked host proves view composition only; it is not a live-source finding. Do not add the diagnostic probe to C, JSON, Swift DTOs, or fixture JSON.

- [ ] **Step 2: Run the RED native test.**

Run: `make swift-test SWIFT_TEST_FILTER=AnalyticsWindowControllerTests`

Expected: the new accessibility/scroll/appearance assertions fail until the layout is complete.

- [ ] **Step 3: Make only bounded view-test adjustments needed for inspection.**

Place any disclosure-state hook in the Swift test target. Do not add an acceptance-driver mode that constructs analytics services, because `AppDelegate` deliberately omits analytics in `NEEDLBAR_ACCEPTANCE_DRIVER`; never add a public C header prototype.

- [ ] **Step 4: Perform actual native inspection.**

Run: `make swift-test SWIFT_TEST_FILTER=AnalyticsWindowControllerTests`

Expected: pass. Then launch the normal app from the isolated worktree, open Analytics manually, and inspect light/dark default/minimum states, keyboard tab order, VoiceOver label/expanded state, and scrolling to the last disclosure. Record this as live native layout inspection; do not claim its real local content proves or disproves repository attribution.

Commit: `git add Tests/NeedlbarTests/AnalyticsWindowControllerTests.swift && git commit -m "test: cover native analytics summary acceptance"`

### Task 5: Full serial verification and evidence handoff

**Files:**
- Modify: `docs/STATUS.md`

- [ ] **Step 1: Re-run Rust, Swift, and production-artifact boundaries serially.**

Run:

```bash
cargo test --workspace --features bridge-test-runtime
make swift-test SWIFT_TEST_FILTER=AnalyticsWindowControllerTests
make test
make package
make smoke
```

Expected: every command exits `0`; `make swift-test` builds its feature bridge then restores a normal bridge archive, and `make package`/`make smoke` use that normal production archive. Do not invoke a direct `swift test` without Makefile bridge setup.

- [ ] **Step 2: Verify nonshipping boundaries after the normal build.**

Run:

```bash
./scripts/build-rust.sh
! strings target/release/libneedlbar_bridge.a | grep -E 'analytics_diagnostic_probe|needlbar_test_'
! rg -n 'diagnostic_probe' Sources/CNeedlbar/include/needlbar.h
```

Expected: all commands exit `0`; the probe is neither packaged nor public ABI.

- [ ] **Step 3: Record facts and the explicit decision gate.**

Update `docs/STATUS.md` with command exits, fixture/native acceptance, any one-shot probe's aggregate counters, the immutable unknowns (timestamp source distinction and unavailable Git stage), and whether attribution remains unexplained. If a probe identifies a probable cause, stop: write and obtain review for a technical amendment naming the minimal correction and regression fixture before changing parser/correlation/vendor/schema behavior.

- [ ] **Step 4: Commit documentation only after all gates pass.**

Commit: `git add docs/STATUS.md && git commit -m "docs: record analytics summary verification"`

## Self-review

- Presentation requirements map to Tasks 2–4: summary-first cards, empty-vs-zero, independent unlinked usage, retained rows, collapsed definitions/diagnostics, scroll/min-size, loading/stale/unavailable, keyboard and accessibility.
- Privacy and no-ABI/no-production-probe requirements map to Tasks 1, 4, and 5; every proposed diagnostic field is a numeric aggregate with fixed names and fixtures carry canaries.
- The plan deliberately does not solve repository attribution. It records only observable aggregate evidence, treats timestamp origin and generic unavailable stage as unknown, preserves all existing caps, and requires a reviewed amendment for any future correction.
- Main review corrected layer ownership, exact ignored-test routing, normal-build boundary checks, provider-count privacy and fixture-versus-live acceptance. Commands below are planned checks, not already executed implementation tests.

## Implementation details for Task 2 fixtures

Place this helper in `AnalyticsPresentationTests.swift` with `import Foundation`,
`import Testing` and `@testable import NeedlbarCore`. No source file or live provider
is read by these tests.

```swift
private func fixture(linked: Bool, unlinked: UInt64,
                     reasons: [String: UInt64] = [:]) -> AnalyticsSnapshot {
    let end = Date(timeIntervalSince1970: 1_788_278_400)
    let usage = AnalyticsUsageAggregate(inputTokens: "0", outputTokens: "0",
        cacheReadTokens: "0", cacheWriteTokens: "0", reasoningTokens: "0",
        totalTokens: "0", estimatedCostUSD: "0")
    let row = AnalyticsRepositoryAnalytics(repositoryID: "fixture-repository",
        label: "Fixture", state: "available", usage: usage,
        observedActiveTimeSeconds: "0", providerModels: [], commits: [],
        coverage: RepositoryCoverage(assignedFragments: 0, unassignedFragments: 1,
                                     timingPartial: false, reasons: [:]))
    return AnalyticsSnapshot(schemaVersion: "needlbar.analytics.v1", ok: true,
        generatedAt: end,
        analysisRange: AnalyticsDateRange(start: end.addingTimeInterval(-30 * 86_400), end: end),
        repositories: linked ? [row] : [],
        unattributed: AnalyticsAttributionBucket(usage: usage, fragments: unlinked, reasons: reasons),
        coverage: AnalyticsCoverage(attributedFragments: linked ? 1 : 0,
                                    unattributedFragments: unlinked, reasons: reasons), errors: [])
}
```

Inside each test define its input explicitly:

```swift
let snapshotWithoutRepositories = fixture(linked: false, unlinked: 430)
let validZeroSnapshot = fixture(linked: true, unlinked: 0)
let mixedSnapshot = fixture(linked: true, unlinked: 7)
let mixedCounterSnapshot = fixture(linked: false, unlinked: 1,
                                   reasons: ["recordLimitReached": 12])
```

Core summation must not silently replace invalid/overflowing values with zero.
Use this concrete checked-time implementation inside `AnalyticsPresentation`:

```swift
private static func activitySeconds(_ rows: [AnalyticsRepositoryAnalytics]) -> UInt64? {
    guard !rows.isEmpty else { return nil }
    var total: UInt64 = 0
    for row in rows {
        guard let value = row.observedActiveTimeSecondsValue else { return nil }
        let next = total.addingReportingOverflow(value)
        guard !next.overflow else { return nil }
        total = next.partialValue
    }
    return total
}
```

For Decimal cost, use `NSDecimalAdd` and accept only `.noError`; invalid, overflow
or precision-loss results become unavailable rather than an invented zero.
Copy the existing `AnalyticsDisplayFormatter.summaryCost` partial-cost predicates
into Core's `repositoryCostIsKnownSubtotal` calculation without changing their
meaning. Task 3 keeps monetary/duration text formatting in the view formatter.

All API signatures in Task 1 and Task 2 are contracts to implement, not standalone
source files. Task 1's shared report helper must preserve the current
`ReportOptions`, cache-only pricing, exact instant-range call and fixture-home
handling from `collect_analytics`; keep the existing fixture early return before
calling it. Add `use serde::Serialize` and `use std::collections::BTreeMap` to the
new probe module, and `#![cfg(feature = "analytics-diagnostic-probe")]` to its
integration test. Require exact equality of normal payloads with/without the probe
observer for the same fake inputs; no extra Git call or changed budget is allowed.

When mapping canonicalization errors, both `InvalidInput` and `InvalidData` mean
`pathMalformed`; all unlisted error kinds mean `pathOther`. Discovery-unavailable
is still stage-unknown even if a preceding fallback canonicalization failed.
Do not claim the source failure is conclusively repaired after this limited probe.
