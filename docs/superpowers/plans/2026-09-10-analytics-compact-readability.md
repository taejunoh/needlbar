# Analytics Compact Readability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved Compact rows (A) presentation without changing analytics evidence or calculations.

**Architecture:** Keep existing Core presentation, formatters, status resolution and refresh ownership. Add a small view-only compact presentation policy, then consume it in the actual native view for aligned rows and stable disclosures. Preserve existing repository detail bodies rather than reconstructing their evidence.

**Tech Stack:** Swift, SwiftUI/AppKit, Swift Testing; existing Rust bridge remains unchanged.

---

## Authority and working tree

Approved spec: `docs/superpowers/specs/2026-09-10-analytics-compact-readability-design.md`
(written-spec approval received after commit `04f732f`). Work only in
`/Users/taejunoh/Developer/LFG/needlbar/.worktrees/analytics-summary-first`, branch
`codex/analytics-summary-first`. This is an existing isolated worktree with
uncommitted earlier analytics contract/layout corrections. Do not reset, clean,
overwrite or silently include them in a new task commit. Record incremental
diffs separately; defer overlapping-file commits until their provenance is reviewed.
No new worktree from HEAD alone: that would omit the tested prerequisite changes.

No Rust/Core changes, new dependencies, menu-bar fix, settings changes, permission
changes, source scans, installation, push, merge, tag or public release. Build/test
only in this worktree; serialize all operations touching its bridge archive.
Read `docs/STATUS.md` and the approved spec before implementation.

## File responsibility map

- Create `Sources/Needlbar/Analytics/AnalyticsCompactPresentation.swift`: compact
  copy and row geometry used by the view, with no snapshot mutation or fetches.
- Modify `Sources/Needlbar/Analytics/AnalyticsView.swift`: existing header,
  diagnosticsContent, repositoryRow and unattributedCostSummary only, plus small
  label subviews. Retain AnalyticsDashboardStatus.resolve and all Core formatters.
- Modify `Tests/NeedlbarTests/AnalyticsWindowControllerTests.swift`: compact policy,
  disclosure-state and native fixture checks using existing test conventions.
- Read unchanged `Sources/NeedlbarCore/Analytics/AnalyticsPresentation.swift` and
  `Tests/NeedlbarCoreTests/AnalyticsPresentationTests.swift` for truth invariants.
- Update `docs/STATUS.md` with evidence and remaining native acceptance gaps.

Implementation is sequential: a Luna worker handles each bounded edit/test task;
Terra reviews semantic preservation after Task 3. Root integrates and verifies.
Workers are not alone; preserve others' edits. Do not run competing builds.

## Task 1: Compact presentation policy, test first

- [ ] Add these tests to the existing AnalyticsWindowControllerTests suite:

```swift
@Test func compactCopyPreservesWarningAndDiagnosticMeaning() {
    let partial = AnalyticsDashboardStatus.partial("Original coverage qualification")
    #expect(AnalyticsCompactPresentation.statusTitle(partial) == "Partial coverage")
    #expect(partial.text == "Original coverage qualification")
    #expect(AnalyticsCompactPresentation.statusTitle(.stale("Retained snapshot")) == "Retained snapshot")
    #expect(AnalyticsCompactPresentation.diagnosticContext("recordLimitReached") == "Mixed processing limits")
    #expect(AnalyticsCompactPresentation.diagnosticContext("missingDuration") == "Response duration missing")
    #expect(AnalyticsCompactPresentation.diagnosticContext("unrecognized") == "Limited evidence")
    #expect(AnalyticsCompactPresentation.diagnosticID("missingDuration") == "diagnostic-missingDuration")
    #expect(AnalyticsCompactPresentation.repositoryID("sample") == "repository-sample")
    #expect(AnalyticsCompactPresentation.estimateQualifier == "Estimated cost · not a bill")
}

@Test func compactRowWidthsAdaptWithoutChangingEvidenceColumns() {
    #expect(!AnalyticsCompactPresentation.wideRows(592))
    #expect(AnalyticsCompactPresentation.wideRows(712))
    #expect(AnalyticsCompactPresentation.wideRows(960))
    #expect(AnalyticsCompactPresentation.quality(cost: "Complete", timing: "Complete") == nil)
    #expect(AnalyticsCompactPresentation.quality(cost: "Complete", timing: "Partial") == "Timing Partial")
    #expect(AnalyticsCompactPresentation.quality(cost: "Unavailable", timing: "Unavailable") == "Cost Unavailable · Timing Unavailable")
}
```

- [ ] Run RED: `source /Users/taejunoh/.cargo/env` then
  `make swift-test SWIFT_TEST_FILTER=AnalyticsWindowControllerTests`.
  Expect missing AnalyticsCompactPresentation, not unrelated build errors.
- [ ] Create the policy file with this code:

```swift
import Foundation

enum AnalyticsCompactPresentation {
    static let estimateQualifier = "Estimated cost · not a bill"
    static let countsQualification = "Counts use different units and may overlap. They are not a total."
    static func wideRows(_ width: CGFloat) -> Bool { width >= 680 }
    static func repositoryID(_ id: String) -> String { "repository-\(id)" }
    static func diagnosticID(_ code: String) -> String { "diagnostic-\(code)" }
    static func statusTitle(_ status: AnalyticsDashboardStatus) -> String {
        if case .partial = status { return "Partial coverage" }
        return status.text
    }
    static func quality(cost: String, timing: String) -> String? {
        let parts = [cost == "Complete" ? nil : "Cost \(cost)",
                     timing == "Complete" ? nil : "Timing \(timing)"].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    static func diagnosticContext(_ code: String) -> String {
        switch code {
        case "missingDuration": "Response duration missing"
        case "missingTimestamp": "Period coverage incomplete"
        case "recordLimitReached": "Mixed processing limits"
        case "gitOutputLimitReached": "Inspection output bounded"
        case "gitTimedOut", "gitUnavailable": "Inspection unavailable or incomplete"
        default: "Limited evidence"
        }
    }
}
```

- [ ] Run the same focused command; expect GREEN. These helpers must be consumed
  in Tasks 2–3, not remain a disconnected test proxy. No Core diagnostic remapping.

## Task 2: Aligned, individually expandable diagnostics

- [ ] First extend the existing disclosure test to exercise a diagnostic key and
  repository key in expandedSections: initially false, independently toggle true,
  render with a refreshed snapshot using the same bindings, and assert both remain
  true. Use the existing acceptance fixture and controller-test binding pattern;
  test the real binding logic, not a separate state container.
- [ ] Run focused tests and record the new failure before adding the controls.
- [ ] In diagnosticsContent retain its empty case. Replace each current permanent
  prose row with the following DisclosureGroup. Keep ForEach keyed by code:

```swift
DisclosureGroup(isExpanded: disclosureBinding(AnalyticsCompactPresentation.diagnosticID(diagnostic.code))) {
    Text(AnalyticsDisplayFormatter.diagnosticExplanation(diagnostic.code))
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
} label: {
    diagnosticLabel(diagnostic)
}
.accessibilityLabel("Explanation: \(AnalyticsDisplayFormatter.diagnosticTitle(diagnostic.code))")
Divider()
```

- [ ] Add the label function to AnalyticsDashboardContent:

```swift
private func diagnosticLabel(_ diagnostic: AnalyticsPresentationDiagnostic) -> some View {
    let wide = AnalyticsCompactPresentation.wideRows(contentWidth)
    return VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(AnalyticsDisplayFormatter.diagnosticTitle(diagnostic.code))
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(diagnostic.count) \(AnalyticsDisplayFormatter.diagnosticUnit(diagnostic.unit))")
                .font(.system(size: 12).monospacedDigit())
                .multilineTextAlignment(.trailing)
                .frame(width: wide ? 190 : 165, alignment: .trailing)
            if wide {
                Text(AnalyticsCompactPresentation.diagnosticContext(diagnostic.code))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 190, alignment: .leading)
            }
        }
        if !wide {
            Text(AnalyticsCompactPresentation.diagnosticContext(diagnostic.code))
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
    .fixedSize(horizontal: false, vertical: true)
    .padding(.vertical, 5)
}
```

- [ ] Above nonempty rows show countsQualification once using 12 pt secondary
  text. Keep original diagnosticTitle/unit/explanation APIs unchanged, including
  Pending 4-hour window. Keep outer diagnostics ID, reveal action and definitions.
- [ ] Re-run focused tests. Verify full original caveats are reachable for every
  row and no raw unknown diagnostic/reason values were added to visible copy.

## Task 3: Repository comparison, compact status and clear estimate

- [ ] Add native fixture assertions for visible comparison headers and labelled
  row values before changing the view. Existing long-name and maximum fixtures
  should still render and expose repository details after expansion.
- [ ] Run RED using the same focused test entry point.
- [ ] Rename the existing repositoryRow function to repositoryDetails, preserving
  its body verbatim (Git reasons, providerModels, commits, timing and coverage).
  Add this wrapper as the new repositoryRow:

```swift
private func repositoryRow(_ repository: AnalyticsRepositoryAnalytics) -> some View {
    DisclosureGroup(isExpanded: disclosureBinding(AnalyticsCompactPresentation.repositoryID(repository.repositoryID))) {
        repositoryDetails(repository).padding(.top, 8)
    } label: {
        repositoryComparisonLabel(repository)
    }
    .accessibilityLabel("Repository details: \(repository.label)")
}

private func repositoryComparisonLabel(_ repository: AnalyticsRepositoryAnalytics) -> some View {
    let costCoverage = AnalyticsDisplayFormatter.repositoryCostCoverage(repository.coverage, state: repository.state)
    let timingCoverage = AnalyticsDisplayFormatter.repositoryTimingCoverage(repository.coverage, state: repository.state)
    return VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(repository.label)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(AnalyticsDisplayFormatter.cost(repository.usage.estimatedCostUSDValue))
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .frame(width: 132, alignment: .trailing)
                .accessibilityLabel("Estimated cost")
                .accessibilityValue(AnalyticsDisplayFormatter.cost(repository.usage.estimatedCostUSDValue))
            Text(AnalyticsDisplayFormatter.tokens(repository.usage.totalTokens))
                .font(.system(size: 12).monospacedDigit())
                .frame(width: 88, alignment: .trailing)
                .accessibilityLabel("Tokens")
                .accessibilityValue(AnalyticsDisplayFormatter.tokensAccessibilityValue(repository.usage.totalTokens))
        }
        if let quality = AnalyticsCompactPresentation.quality(cost: costCoverage, timing: timingCoverage) {
            Text(quality).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
    .fixedSize(horizontal: false, vertical: true)
    .padding(.vertical, 5)
}
```

- [ ] Above populated repository rows add the matching header, retaining the
  exact original ForEach order and outer scroll container:

```swift
HStack(alignment: .firstTextBaseline, spacing: 12) {
    Text("Repository").frame(maxWidth: .infinity, alignment: .leading)
    Text("Estimated cost").frame(width: 132, alignment: .trailing)
    Text("Tokens").frame(width: 88, alignment: .trailing)
}
.font(.system(size: 11, weight: .medium))
.foregroundStyle(.secondary)
.padding(.leading, 16)
```

  Native check must align this inset with the actual DisclosureGroup chevron;
  correct the shared inset if AppKit renders a different width. Do not shrink text
  or clip long values to conceal a layout failure. Wrap inside allocated columns.

- [ ] In header's existing warning Label replace only `status.text` with
  `AnalyticsCompactPresentation.statusTitle(status)` and add
  `.accessibilityLabel(status.text).help(status.text)`. Remove its rounded amber
  background and horizontal padding; retain amber icon/text, 5 pt vertical spacing
  and View diagnostics. Non-partial text remains complete, preserving stale/errors
  and updating caveats. Keep all status resolver/refresh code unchanged.
- [ ] In unattributedCostSummary add directly below the amount:

```swift
Text(AnalyticsCompactPresentation.estimateQualifier)
    .font(.system(size: 12))
    .foregroundStyle(.secondary)
    .fixedSize(horizontal: false, vertical: true)
```

  Keep formatter, separate count, narrow/wide layout and missingTimestamp warning
  unchanged. Do not copy the HTML's illustrative “not a total” badge into unrelated
  states. Keep the three original summary cards, not duplicate Unlinked cost there.
- [ ] Run `make swift-test SWIFT_TEST_FILTER=AnalyticsWindowControllerTests` and
  `make swift-test SWIFT_TEST_FILTER=AnalyticsPresentationTests`; expect all pass.
- [ ] Terra review: compare every changed label and moved detail to the approved
  spec and previous view. Require unchanged evidence, stable keys, accessible
  full caveats and no unused compact helpers before final verification.

## Task 4: Final verification and handoff

- [ ] Run `source /Users/taejunoh/.cargo/env`, then `make test` with a saved log
  under `/Users/taejunoh/Developer/LFG/needlbar-compact-readability-test.log`.
  Require exit 0; record actual Swift count, not the previous 461 count by assumption.
- [ ] Run `git diff --check`; require no whitespace errors.
- [ ] Review incremental changes only. Confirm no Core/Rust delta was added by
  this work and that the earlier contract/layout fixes remain intact.
- [ ] Exercise the existing isolated native acceptance fixture mechanism; never
  replace/launch a second production app or refresh real sources for fixture QA.
  Cover light/dark at640×400,760×520 and about1400pt wide; populated/empty/long
  labels/maximum fixtures; loading/updating/stale/unavailable/partial; quality
  markers; missingTimestamp qualifier; repository/provider/commit disclosures;
  diagnostic expansion and last scroll item; keyboard/focus and accessible labels.
  If that mechanism cannot provide a scenario, record the exact gap instead of
  treating a screenshot of the HTML or a source-text test as native evidence.
- [ ] Update STATUS with tests, reviewer verdict, native observations and remaining
  gaps. Keep production installation separate and user-authorized. Do not claim
  menu-bar visibility has been fixed by this presentation-only work.
- [ ] Prepare scoped commits only after resolving provenance of overlapping dirty
  files with root. Never stage the entire repository or private mockup directory.

## Plan self-review

Spec coverage: hierarchy/columns (Tasks2–3); compact header and full caveats (Task3);
separate estimated amount (Task3); counts/units/individual explanations (Tasks1–2);
state and disclosure persistence (Tasks2–3); unchanged source semantics and native
acceptance (Task4). No new behavior outside the approved presentation scope.
Existing Core invariant tests cover zero/unavailable, missing timestamps and cost
separation. Every new helper has a named real-view consumer. No dependency on
mockup values or the unresolved menu-bar hypothesis.
