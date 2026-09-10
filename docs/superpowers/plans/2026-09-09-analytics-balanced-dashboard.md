# Analytics Balanced Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the remaining summary-first Analytics presentation with the approved balanced native dashboard while preserving every existing Core, bridge, privacy, refresh, and attribution contract.

**Architecture:** This is the visual remainder of Analytics Task 3 only. Keep `AnalyticsPresentation`, `AnalyticsViewModel`, `AnalyticsWindowController`, and all Rust/ABI/source behavior unchanged; add a small internal, view-owned layout/style unit that `AnalyticsView` consumes to keep breakpoint math and card treatment deterministic. The view keeps the existing repository-row details and disclosure state, adds only local scroll navigation for Diagnostics, and derives every value from the existing snapshot/Core projection.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing, existing Makefile-managed Rust bridge runtime, native macOS appearance review.

---

## Locked boundaries and evidence rules

- This plan supersedes only the old plan's unfinished Analytics Task 3 presentation work. Its completed Rust probe and Core presentation-semantics work are not repeated. Do not change `Sources/NeedlbarCore`, `crates/`, `Sources/CNeedlbar`, `Package.swift`, `Makefile`, app startup, public ABI, fixtures, source hydration, refresh ownership, provider logic, or attribution behavior.
- Leave `main`'s private dirty vendor checkout and unrelated files untouched. This worktree already has root-owned modifications to `docs/STATUS.md` and the approved visual spec; do not alter or revert them. The only document changed by this plan is this file.
- Continue to use the existing `AnalyticsPresentation.summary(for:)` and `.diagnostics(for:)` outputs. A positive Core `missingTimestamp` count is the sole predicate for the unverified-30-day qualification. Do not infer it from cost, Git, record-limit, or legacy reason strings.
- The native view owns only layout, semantic color treatment, disclosure state, and a local `ScrollViewReader` navigation. A `View diagnostics` action may set `diagnosticsExpanded = true` and scroll to the Diagnostics anchor, but must never call `refresh()`, hydrate sources, or fetch data.
- `AnalyticsViewModel` remains the source of serialized refresh state. The presentation maps that existing state in exactly this order: initial loading with no snapshot; updating with a displayed last-good snapshot; unavailable with no snapshot; stale; partial; complete. Color supplements the text status; it does not encode status alone.
- Keep unavailable and measured-zero semantics: repository cost/activity with no eligible repository evidence are `—`; a valid zero remains `$0.00`/`0s`; repository and unlinked-fragment counts remain independently labelled; Unattributed cost remains separate from repository totals.
- Raw/unattributed reason rows must not appear under the Unattributed panel. The existing allowlisted `AnalyticsPresentation.diagnostics(for:)` rows appear once, inside Diagnostics. Do not union or add counters from coverage and unattributed buckets; doing so would manufacture a unit/cause relationship the snapshot does not establish.
- Do not add an analytics acceptance-driver mode, public test hook, or production fixture path. The existing `NEEDLBAR_ACCEPTANCE_DRIVER` deliberately omits analytics. A test-target `NSHostingView`/`NSWindow` fixture proves only native view composition; normal `make run`/packaged-app inspection uses live local data. Record those evidence sources separately.
- The historical AX limitation is real: an in-process `NSHostingView` AX traversal has returned no rendered labels even when mounted in an `NSWindow` with a run-loop drain, and CUA timed out. Do not substitute formatter checks for accessibility acceptance or claim keyboard/AX passing while that remains blocked.

## File map and minimal presentation structure

- Create `Sources/Needlbar/Analytics/AnalyticsDashboardLayout.swift` — internal view-owned geometry and semantic-card style values. It is deliberately not public and has no snapshot, fetch, Core, or AppKit-window responsibility. It supplies the bounded content width, card/panel column counts, card accent/icon descriptions, and the 28/24-point value choice consumed by the actual views.
- Modify `Sources/Needlbar/Analytics/AnalyticsView.swift` — retain `AnalyticsReasonDisplay`, `AnalyticsDisplayFormatter`, and `repositoryRow(_:)` behavior; replace only the outer view composition, header/status treatment, summary-card/panel construction, Unattributed reason rendering, and Diagnostics navigation. Keep provider/model and commit disclosure content byte-for-byte except for container styling inherited from the new panel.
- Modify `Tests/NeedlbarTests/AnalyticsWindowControllerTests.swift` — extend the existing serialized, `@MainActor` fixture suite. It continues to use `TestAnalyticsRepository`, `ImmediateAnalyticsRepository`, `testAnalyticsSnapshot()`, `populatedAnalyticsSnapshot()`, and `maximumAnalyticsSnapshot()`; no new service, bridge, ABI, or acceptance-driver fixture is introduced.
- Modify `docs/STATUS.md` only after implementation and acceptance evidence are actually available; root owns that update, not the worker executing this document.

The split is intentionally one small internal layout/style file plus the existing view. Do not create a dashboard model, a new Core presentation API, a preferences object, a theme setting, or a reusable design-system hierarchy.

## Execution roles and cadence

- The main Sol agent orchestrates and performs the final integration decision. The no-extra-review instruction applied to authoring this plan; execution follows the selected subagent-driven-development sequence: a fresh implementer, then a fresh spec-compliance review, then a fresh code-quality review for each task.
- Task 1 uses a fresh Luna fast-worker at `high` to implement the isolated layout/style and native-host test unit, then a fresh Terra deep-reasoner at `high` for spec review and a fresh Luna fast-worker at `high` for quality review. Tasks 2–3 use a fresh Terra deep-reasoner at `high` for SwiftUI integration/debugging, then fresh Terra (`high`) spec and quality reviewers. Task 4 has the main agent coordinate evidence recording; any test-only adjustment again receives fresh implementer → spec review → quality review. Reviewers must not edit unrelated docs, main, or vendor.
- Work serially. While developing a numbered task, run only its listed focused `make swift-test` command. Once its implementation and focused check are green, run exactly one `make test` from this worktree before marking that numbered task complete. Do not overlap full suites, package builds, smoke runs, or agent edits.
- `make swift-test` is mandatory for Swift work because it builds the feature test bridge and restores a normal Rust archive on exit. Do not run direct `swift test` against an unknown bridge archive. The Makefile invokes the Rust build with its required environment; do not replace it with ad-hoc Cargo environment commands.

### Task 1: Establish the consumer-linked balanced layout and card style contract

**Files:**

- Create: `Sources/Needlbar/Analytics/AnalyticsDashboardLayout.swift`
- Modify: `Tests/NeedlbarTests/AnalyticsWindowControllerTests.swift`

- [ ] **Step 1: Add the failing geometry and style tests to the existing Analytics suite.**

Append these tests inside `AnalyticsWindowControllerTests`. Task 2 binds the geometry helpers to actual `LazyVGrid` tracks; the style test locks the approved semantic mapping without exporting an API.

```swift
@Test func balancedDashboardUsesTheApprovedBoundedGridBreakpoints() {
    #expect(AnalyticsDashboardLayout.contentColumnWidth(forWindowContentWidth: 640) == 592)
    #expect(AnalyticsDashboardLayout.summaryColumnCount(forContentWidth: 592) == 2)
    #expect(AnalyticsDashboardLayout.contentColumnWidth(forWindowContentWidth: 760) == 712)
    #expect(AnalyticsDashboardLayout.summaryColumnCount(forContentWidth: 712) == 3)
    #expect(AnalyticsDashboardLayout.contentColumnWidth(forWindowContentWidth: 1_400) == 960)
    #expect(AnalyticsDashboardLayout.summaryColumnCount(forContentWidth: 960) == 3)
    #expect(AnalyticsDashboardLayout.evidencePanelColumnCount(forContentWidth: 592) == 1)
    #expect(AnalyticsDashboardLayout.evidencePanelColumnCount(forContentWidth: 712) == 1)
    #expect(AnalyticsDashboardLayout.evidencePanelColumnCount(forContentWidth: 960) == 2)
}

@Test func balancedDashboardCardStylesDriveTheRenderedSemanticTreatments() {
    let cost = AnalyticsDashboardCardKind.repositoryEstimate
    let linkage = AnalyticsDashboardCardKind.repositoryLinkage
    let activity = AnalyticsDashboardCardKind.observedActivity

    #expect(cost.accent == Color.blue)
    #expect(linkage.accent == Color.teal)
    #expect(activity.accent == Color.purple)
    #expect(cost.symbolName == "dollarsign.circle")
    #expect(linkage.symbolName == "link.circle")
    #expect(activity.symbolName == "sparkles")
    #expect(AnalyticsDashboardLayout.summaryValuePointSize(for: "$12.50") == 28)
    #expect(AnalyticsDashboardLayout.summaryValuePointSize(for: "$123,456,789.00") == 24)
}
```

The existing fixture test already imports `@testable import NeedlbarApp`, so these internal symbols remain testable without making a production API public.

- [ ] **Step 2: Run the focused test to establish RED.**

Run: `make swift-test SWIFT_TEST_FILTER=AnalyticsWindowControllerTests`

Expected: compile failure naming missing `AnalyticsDashboardLayout` and `AnalyticsDashboardCardKind`; no production behavior is changed yet.

- [ ] **Step 3: Add the complete private presentation helper used by the real view.**

Create `Sources/Needlbar/Analytics/AnalyticsDashboardLayout.swift` with this complete content. The adaptive choices obey the 180-point minimum and 12-point inter-card spacing: at supported minimum width (592) two cards fit; three become explicit only at 600. `summaryValuePointSize(for:)` is used directly by the card below.

```swift
import SwiftUI

enum AnalyticsDashboardLayout {
    static let horizontalInset: CGFloat = 24
    static let maximumContentWidth: CGFloat = 960
    static let sectionSpacing: CGFloat = 16
    static let gridSpacing: CGFloat = 12
    static let minimumCardWidth: CGFloat = 180
    static let summaryWideBreakpoint: CGFloat = 600
    static let evidenceTwoColumnBreakpoint: CGFloat = 800

    static func contentColumnWidth(forWindowContentWidth width: CGFloat) -> CGFloat {
        min(max(0, width - horizontalInset * 2), maximumContentWidth)
    }

    static func summaryColumnCount(forContentWidth width: CGFloat) -> Int {
        if width >= summaryWideBreakpoint { return 3 }
        return width >= minimumCardWidth * 2 + gridSpacing ? 2 : 1
    }

    static func evidencePanelColumnCount(forContentWidth width: CGFloat) -> Int {
        width >= evidenceTwoColumnBreakpoint ? 2 : 1
    }

    static func summaryValuePointSize(for value: String) -> CGFloat {
        value.count > 12 ? 24 : 28
    }

    static func equalTracks(count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: minimumCardWidth), spacing: gridSpacing), count: count)
    }
}

enum AnalyticsDashboardCardKind: CaseIterable {
    case repositoryEstimate
    case repositoryLinkage
    case observedActivity

    var accent: Color {
        switch self {
        case .repositoryEstimate: .blue
        case .repositoryLinkage: .teal
        case .observedActivity: .purple
        }
    }

    var symbolName: String {
        switch self {
        case .repositoryEstimate: "dollarsign.circle"
        case .repositoryLinkage: "link.circle"
        case .observedActivity: "sparkles"
        }
    }
}

struct AnalyticsDashboardCard: View {
    let kind: AnalyticsDashboardCardKind
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle()
                .fill(kind.accent)
                .frame(height: 3)
                .accessibilityHidden(true)
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    Text(value)
                        .font(.system(size: AnalyticsDashboardLayout.summaryValuePointSize(for: value), weight: .semibold))
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: kind.symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(kind.accent.opacity(0.14), in: Circle())
                    .foregroundStyle(kind.accent)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(kind.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(kind.accent.opacity(0.30), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct AnalyticsDashboardPanel<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.30), lineWidth: 1)
        }
    }
}
```

No hex colors, app-wide theme override, or color preference is added. Native semantic colors adapt to the active light/dark appearance; all text remains present without the color/icon.

- [ ] **Step 4: Run the focused GREEN check, then the one Task-1 full gate.**

Run: `make swift-test SWIFT_TEST_FILTER=AnalyticsWindowControllerTests`

Expected: the Analytics suite passes, including 640 → 592/2 cards, 760 → 712/3 cards, 1,400 → 960/3 cards, and panel counts 1/1/2.

Then, after the focused run is green and no other task is running, run: `make test`

Expected: exit `0`; the normal bridge archive is restored by the Swift test target and no Rust/Core/public-surface behavior changes.

- [ ] **Step 5: Commit the focused task.**

```bash
git add Sources/Needlbar/Analytics/AnalyticsDashboardLayout.swift Tests/NeedlbarTests/AnalyticsWindowControllerTests.swift
git commit -m "feat: define balanced analytics dashboard layout"
```

### Task 2: Build one real width-owned dashboard content component

**Files:**

- Modify: `Sources/Needlbar/Analytics/AnalyticsView.swift`
- Modify: `Sources/Needlbar/Analytics/AnalyticsDashboardLayout.swift`
- Modify: `Tests/NeedlbarTests/AnalyticsWindowControllerTests.swift`

- [ ] **Step 1: Add a RED test for the actual production content component and scroll geometry.**

Add this test and recursive lookup beside the existing `NSView.containsSubview` extension. It hosts `AnalyticsDashboardContent` inside the same native `ScrollView` shell that Task 2 installs in `AnalyticsView`; it is not a formatter proxy. The maximum fixture makes its document taller than a 400-point viewport and proves the native scroll view can reach the final content rectangle.

```swift
@Test func balancedDashboardContentHasNaturalHeightAndReachesItsFinalDisclosure() throws {
    var diagnosticsExpanded = false
    var definitionExpanded = false
    var expandedSections: Set<String> = []
    let content = AnalyticsDashboardContent(
        snapshot: maximumAnalyticsSnapshot(),
        contentWidth: 592,
        diagnosticsExpanded: Binding(get: { diagnosticsExpanded }, set: { diagnosticsExpanded = $0 }),
        estimateDefinitionExpanded: Binding(get: { definitionExpanded }, set: { definitionExpanded = $0 }),
        expandedSections: Binding(get: { expandedSections }, set: { expandedSections = $0 }),
        onViewDiagnostics: {}
    )
    let hosted = NSHostingView(rootView: ScrollView { content })
    hosted.frame = NSRect(x: 0, y: 0, width: 640, height: 400)
    hosted.layoutSubtreeIfNeeded()

    let scroll = try #require(hosted.firstSubview(ofType: NSScrollView.self))
    let document = try #require(scroll.documentView)
    #expect(document.frame.height > scroll.contentView.bounds.height)
    scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.frame.height - scroll.contentView.bounds.height)))
    scroll.reflectScrolledClipView(scroll.contentView)
    #expect(scroll.contentView.bounds.maxY >= document.bounds.maxY - 1)
}

private extension NSView {
    func firstSubview<T: NSView>(ofType type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T { return match }
            if let match = subview.firstSubview(ofType: type) { return match }
        }
        return nil
    }
}
```

Also retain the existing formatter assertions for `—` versus `$0.00`/`0s`; those are regression gates, not the RED proof for this layout task.

- [ ] **Step 2: Run the focused RED test.**

Run: `make swift-test SWIFT_TEST_FILTER=AnalyticsWindowControllerTests`

Expected: compile failure naming missing `AnalyticsDashboardContent`; the old `AnalyticsView` cannot satisfy a test that hosts this production width-owned component.

- [ ] **Step 3: Add the complete width-owned component, then have the root view consume it.**

In `AnalyticsDashboardLayout.swift`, add these consumer-linked track helpers inside `AnalyticsDashboardLayout`:

```swift
static func summaryTracks(forContentWidth width: CGFloat) -> [GridItem] {
    equalTracks(count: summaryColumnCount(forContentWidth: width))
}

static func evidencePanelTracks(forContentWidth width: CGFloat) -> [GridItem] {
    equalTracks(count: evidencePanelColumnCount(forContentWidth: width))
}
```

Then replace the old `snapshotContent(_:)`, `summaryCard(_:_:)`, `unattributedCost(_:)`, `diagnosticsContent(_:)`, `estimateDefinition`, `disclosureBinding(_:)`, and `repositoryRow(_:)` members of `AnalyticsView` with an internal `AnalyticsDashboardContent` in the same file. Move `repositoryRow(_:)` and its `disclosureBinding(_:)` implementation into the new struct **byte-for-byte**; only change their containing type. Keep `AnalyticsReasonDisplay` and every `AnalyticsDisplayFormatter` function unchanged. In this task, also replace the old `body` with the following outer geometry/reader/scroll shell so `contentWidth` and `onViewDiagnostics` exist before this task's commit; Task 3 refines its status and shared interaction handler without changing the measurement ownership:

```swift
public var body: some View {
    GeometryReader { windowProxy in
        let contentWidth = AnalyticsDashboardLayout.contentColumnWidth(forWindowContentWidth: windowProxy.size.width)
        ScrollViewReader { proxy in
            let revealDiagnostics = {
                diagnosticsExpanded = true
                DispatchQueue.main.async { withAnimation { proxy.scrollTo("analytics-diagnostics", anchor: .top) } }
            }
            VStack(spacing: 0) {
                header
                    .frame(width: contentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: AnalyticsDashboardLayout.sectionSpacing) {
                        if viewModel.isLoading { ProgressView(viewModel.statusCopy).controlSize(.small) }
                        if let snapshot = displayedSnapshot {
                            AnalyticsDashboardContent(
                                snapshot: snapshot,
                                contentWidth: contentWidth,
                                diagnosticsExpanded: $diagnosticsExpanded,
                                estimateDefinitionExpanded: $estimateDefinitionExpanded,
                                expandedSections: $expandedSections,
                                onViewDiagnostics: revealDiagnostics
                            )
                        } else if !viewModel.isLoading {
                            Text(viewModel.statusCopy).font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: contentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, AnalyticsDashboardLayout.horizontalInset)
                }
            }
        }
    }
    .frame(minWidth: 640, minHeight: 400)
    .onReceive(viewModel.$state) { state in
        if case let .fresh(snapshot) = state { lastSuccessfulSnapshot = snapshot }
        if case let .stale(snapshot) = state { lastSuccessfulSnapshot = snapshot }
    }
}
```

In the retained `header`, remove the old horizontal padding at its use site; the one `contentWidth` frame above now supplies the horizontal 24-point inset. Use the `revealDiagnostics` closure shown above, not an undefined callback name.

Use this complete outer shape for the new production component. `contentWidth` is already measured outside the vertical scroll view by this task's outer shell; the component never contains a `GeometryReader` and never subtracts the 24-point inset again.

```swift
struct AnalyticsDashboardContent: View {
    let snapshot: AnalyticsSnapshot
    let contentWidth: CGFloat
    @Binding var diagnosticsExpanded: Bool
    @Binding var estimateDefinitionExpanded: Bool
    @Binding var expandedSections: Set<String>
    let onViewDiagnostics: () -> Void

    var body: some View {
        let summary = AnalyticsPresentation.summary(for: snapshot)
        let diagnostics = AnalyticsPresentation.diagnostics(for: snapshot)

        VStack(alignment: .leading, spacing: AnalyticsDashboardLayout.sectionSpacing) {
            LazyVGrid(columns: AnalyticsDashboardLayout.summaryTracks(forContentWidth: contentWidth), alignment: .leading, spacing: AnalyticsDashboardLayout.gridSpacing) {
                AnalyticsDashboardCard(
                    kind: .repositoryEstimate,
                    title: "Repository-attributed estimate",
                    value: AnalyticsDisplayFormatter.repositoryAttributedEstimate(summary.repositoryAttributedCostUSD, knownSubtotal: false),
                    detail: repositoryEstimateDetail(summary)
                )
                AnalyticsDashboardCard(
                    kind: .repositoryLinkage,
                    title: "Repository linkage",
                    value: "\(summary.linkedRepositoryCount)",
                    detail: "Repositories · \(summary.unlinkedFragmentCount) unlinked fragments"
                )
                AnalyticsDashboardCard(
                    kind: .observedActivity,
                    title: "Observed AI activity",
                    value: AnalyticsDisplayFormatter.observedAIActivity(summary.observedAIActivitySeconds),
                    detail: summary.observedAIActivitySeconds == nil
                        ? "No repository-attributed timing evidence."
                        : diagnostics.contains(where: { $0.code == "missingDuration" })
                            ? "Some responses lack duration; observed activity remains separate."
                            : "Timestamp-gap observation, not coding hours."
                )
            }

            LazyVGrid(columns: AnalyticsDashboardLayout.evidencePanelTracks(forContentWidth: contentWidth), alignment: .leading, spacing: AnalyticsDashboardLayout.gridSpacing) {
                repositoriesPanel
                unattributedPanel(summary)
            }

            disclosures(diagnostics)
        }
        .frame(width: contentWidth, alignment: .leading)
    }

    private func repositoryEstimateDetail(_ summary: AnalyticsPresentationSummary) -> String {
        guard summary.repositoryAttributedCostUSD != nil else {
            return summary.linkedRepositoryCount == 0 ? "No linked repositories" : "No estimate available"
        }
        return summary.repositoryCostIsKnownSubtotal
            ? "Known subtotal; local coverage is limited."
            : "Local engine pricing; not an invoice."
    }
}
```

Implement the three referenced panel/disclosure views with these exact content rules:

```swift
private var repositoriesPanel: some View {
    AnalyticsDashboardPanel(title: "Repositories") {
        if snapshot.repositories.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("No usable local repository association was established for this capture.")
                    .font(.system(size: 13))
                Text("This does not mean there were no repositories or AI usage.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button("View diagnostics", action: onViewDiagnostics)
                    .font(.system(size: 12, weight: .medium))
                    .accessibilityLabel("View analytics diagnostics")
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(snapshot.repositories, id: \.repositoryID) { repository in
                    repositoryRow(repository)
                    if repository.repositoryID != snapshot.repositories.last?.repositoryID { Divider() }
                }
            }
        }
    }
}

private func unattributedPanel(_ summary: AnalyticsPresentationSummary) -> some View {
    AnalyticsDashboardPanel(title: "Unattributed") {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unattributed estimated cost")
                .font(.system(size: 13, weight: .medium))
            Text(unattributedCost)
                .font(.system(size: AnalyticsDashboardLayout.summaryValuePointSize(for: unattributedCost), weight: .semibold))
                .monospacedDigit()
            LabeledContent("Unlinked fragments", value: "\(snapshot.unattributed.fragments)")
            Text("Some retained local usage could not be matched to a repository.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if summary.unattributedTimestampCoverageIsIncomplete {
                Label("Not a verified 30-day total", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.14), in: Capsule())
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private var unattributedCost: String {
    guard let cost = snapshot.unattributed.usage.estimatedCostUSDValue else { return "—" }
    return AnalyticsDisplayFormatter.cost(cost)
}

private func disclosures(_ diagnostics: [AnalyticsPresentationDiagnostic]) -> some View {
    VStack(alignment: .leading, spacing: AnalyticsDashboardLayout.sectionSpacing) {
        DisclosureGroup(isExpanded: $diagnosticsExpanded) {
            diagnosticsContent(diagnostics).padding(.top, 6)
        } label: {
            Text(AnalyticsDisplayFormatter.disclosureAccessibilityLabels.diagnostics)
                .font(.system(size: 13, weight: .semibold))
        }
        .id("analytics-diagnostics")
        .accessibilityLabel(AnalyticsDisplayFormatter.disclosureAccessibilityLabels.diagnostics)
        .accessibilityValue(AnalyticsDisplayFormatter.disclosureAccessibilityValue(isExpanded: diagnosticsExpanded))
        .accessibilityHint(AnalyticsDisplayFormatter.disclosureAccessibilityHint)

        DisclosureGroup(isExpanded: $estimateDefinitionExpanded) {
            estimateDefinition.padding(.top, 6)
        } label: {
            Text(AnalyticsDisplayFormatter.disclosureAccessibilityLabels.estimateDefinition)
                .font(.system(size: 13, weight: .semibold))
        }
        .accessibilityLabel(AnalyticsDisplayFormatter.disclosureAccessibilityLabels.estimateDefinition)
        .accessibilityValue(AnalyticsDisplayFormatter.disclosureAccessibilityValue(isExpanded: estimateDefinitionExpanded))
        .accessibilityHint(AnalyticsDisplayFormatter.disclosureAccessibilityHint)
    }
}
```

Keep `diagnosticsContent(_:)` as a single `ForEach(diagnostics, id: \.code)` and never pass `snapshot.unattributed.reasons` to it. Change its title to `.system(size: 13, weight: .medium)` and all secondary/detail text to `.system(size: 12)`. Keep the current three `estimateDefinition` sentences but use `.system(size: 12)` and append `.frame(maxWidth: .infinity, alignment: .leading)`. Thus the component is complete in Task 2 and compiles before Task 3 refines the shared reader action.

- [ ] **Step 4: Run the focused GREEN check, then the one Task-2 full gate.**

Run: `make swift-test SWIFT_TEST_FILTER=AnalyticsWindowControllerTests`

Expected: the new production component has natural maximum-fixture height and an independently verifiable scroll endpoint; the root view consumes it; 640/760/1,400 grid outputs are the helper outputs used by the live grids; zero/unavailable, raw-reason privacy, known-subtotal, and repository detail behavior remain truthful.

Then run, serially after the focused run: `make test`

Expected: exit `0`; this task changes no Rust/Core/ABI/fixture contract.

- [ ] **Step 5: Commit the focused task.**

```bash
git add Sources/Needlbar/Analytics/AnalyticsDashboardLayout.swift Sources/Needlbar/Analytics/AnalyticsView.swift Tests/NeedlbarTests/AnalyticsWindowControllerTests.swift
git commit -m "feat: render balanced analytics evidence dashboard"
```

### Task 3: Add canonical status priority and no-fetch Diagnostics navigation

**Files:**

- Modify: `Sources/Needlbar/Analytics/AnalyticsView.swift`
- Modify: `Tests/NeedlbarTests/AnalyticsWindowControllerTests.swift`

- [ ] **Step 1: Add RED tests for the pure status resolver and the shared disclosure interaction.**

Add this complete test code to `AnalyticsWindowControllerTests`. It calls the real production interaction handler with a real `Binding` and a scroll spy, then verifies the existing repository's request count remains one. It neither depends on the empty AX tree nor mistakes formatter output for a user action.

```swift
@Test func balancedStatusResolverUsesTheApprovedSinglePriorityOrder() {
    #expect(AnalyticsDashboardStatus.resolve(isLoading: true, presentationState: .loading, hasDisplayedSnapshot: false, hasPartialDisplayedSnapshot: false, statusCopy: "ignored") == .initialLoading)
    let updating = AnalyticsDashboardStatus.resolve(isLoading: true, presentationState: .loading, hasDisplayedSnapshot: true, hasPartialDisplayedSnapshot: true, statusCopy: "ignored")
    #expect(updating.text.contains("last captured snapshot"))
    #expect(updating.text.contains("partial"))
    #expect(AnalyticsDashboardStatus.resolve(isLoading: false, presentationState: .unavailable, hasDisplayedSnapshot: false, hasPartialDisplayedSnapshot: false, statusCopy: "Analytics unavailable. Refresh to try again.").isWarning)
    #expect(AnalyticsDashboardStatus.resolve(isLoading: false, presentationState: .stale, hasDisplayedSnapshot: true, hasPartialDisplayedSnapshot: true, statusCopy: "Showing the last successful local analysis. Refresh to try again.").isWarning)
    #expect(AnalyticsDashboardStatus.resolve(isLoading: false, presentationState: .fresh, hasDisplayedSnapshot: true, hasPartialDisplayedSnapshot: true, statusCopy: "Some local usage or repository coverage is partial.").isWarning)
    #expect(AnalyticsDashboardStatus.resolve(isLoading: false, presentationState: .fresh, hasDisplayedSnapshot: true, hasPartialDisplayedSnapshot: false, statusCopy: "Local analysis complete.").isWarning == false)
}

@Test func viewDiagnosticsExpandsThenScrollsWithoutFetching() async {
    let repository = TestAnalyticsRepository()
    let controller = AnalyticsWindowController(store: AnalyticsSnapshotStore(), repository: repository)
    controller.showAnalytics()
    await repository.waitForCall(1)
    await repository.completeNext(with: .success(populatedAnalyticsSnapshot()))
    #expect(await eventually { controller.viewModel.presentationState == .fresh })

    var expanded = false
    let spy = AnalyticsScrollSpy()
    AnalyticsDiagnosticsInteraction.reveal(
        diagnosticsExpanded: Binding(get: { expanded }, set: { expanded = $0 }),
        scrollToDiagnostics: { spy.targets.append("analytics-diagnostics") }
    )

    #expect(expanded)
    #expect(await eventually { spy.targets == ["analytics-diagnostics"] })
    #expect(await repository.callCount == 1)
    #expect(controller.viewModel.isLoading == false)
}

@MainActor
private final class AnalyticsScrollSpy {
    var targets: [String] = []
}
```

- [ ] **Step 2: Run the focused RED test.**

Run: `make swift-test SWIFT_TEST_FILTER=AnalyticsWindowControllerTests`

Expected: compile failure naming missing `AnalyticsDashboardStatus` and `AnalyticsDiagnosticsInteraction`; existing ViewModel tests alone cannot satisfy the new view-owned behavior.

- [ ] **Step 3: Add the testable view-owned resolver and real deferred interaction handler.**

Add these internal (not public) types immediately above `AnalyticsView`. The resolver uses only typed state and the already computed partial predicate; it never classifies fresh quality by comparing `statusCopy` text.

```swift
enum AnalyticsDashboardStatus: Equatable {
    case initialLoading
    case updating(String)
    case unavailable(String)
    case stale(String)
    case partial(String)
    case complete(String)

    static func resolve(
        isLoading: Bool,
        presentationState: AnalyticsViewModel.PresentationState,
        hasDisplayedSnapshot: Bool,
        hasPartialDisplayedSnapshot: Bool,
        statusCopy: String
    ) -> AnalyticsDashboardStatus {
        if isLoading {
            guard hasDisplayedSnapshot else { return .initialLoading }
            let caveat = hasPartialDisplayedSnapshot ? " Some local usage or repository coverage is partial." : ""
            return .updating("Refreshing local analysis. Showing the last captured snapshot.\(caveat)")
        }
        return switch presentationState {
        case .unavailable: .unavailable(statusCopy)
        case .stale: .stale(statusCopy)
        case .fresh: hasPartialDisplayedSnapshot ? .partial(statusCopy) : .complete(statusCopy)
        case .idle, .loading: .initialLoading
        }
    }

    var text: String {
        switch self {
        case .initialLoading: "Analyzing local repository data…"
        case let .updating(text), let .unavailable(text), let .stale(text), let .partial(text), let .complete(text): text
        }
    }

    var isWarning: Bool {
        switch self {
        case .partial, .stale, .unavailable: true
        case .initialLoading, .updating, .complete: false
        }
    }
}

@MainActor
enum AnalyticsDiagnosticsInteraction {
    static func reveal(diagnosticsExpanded: Binding<Bool>, scrollToDiagnostics: @escaping @MainActor () -> Void) {
        diagnosticsExpanded.wrappedValue = true
        DispatchQueue.main.async { scrollToDiagnostics() }
    }
}

private func analyticsSnapshotHasPartialEvidence(_ snapshot: AnalyticsSnapshot) -> Bool {
    if !snapshot.errors.isEmpty || !snapshot.coverage.reasons.isEmpty || !snapshot.unattributed.reasons.isEmpty {
        return true
    }
    return snapshot.repositories.contains {
        $0.coverage.timingPartial || !$0.coverage.reasons.isEmpty || $0.state == "unavailable"
    }
}
```

The dispatch defers the proxy call until after the expanded state has scheduled layout. It is the same path the test invokes; no test-only hook is introduced.

- [ ] **Step 4: Replace the outer layout with one measured width and explicit reader closures.**

Replace the Task-2 outer `AnalyticsView.body`/header composition with this complete code. The `GeometryReader` is outside the `ScrollView`, so `contentWidth` is measured once from window content width. Neither header nor scroll content adds horizontal padding: their `width: contentWidth` frame provides exactly the required centered 24-point insets at 640 and the 960-point cap at wide widths.

```swift
public var body: some View {
    GeometryReader { windowProxy in
        let contentWidth = AnalyticsDashboardLayout.contentColumnWidth(forWindowContentWidth: windowProxy.size.width)
        let snapshot = displayedSnapshot
        let status = AnalyticsDashboardStatus.resolve(
            isLoading: viewModel.isLoading,
            presentationState: viewModel.presentationState,
            hasDisplayedSnapshot: snapshot != nil,
            hasPartialDisplayedSnapshot: snapshot.map(analyticsSnapshotHasPartialEvidence) ?? false,
            statusCopy: viewModel.statusCopy
        )

        ScrollViewReader { proxy in
            let revealDiagnostics = {
                AnalyticsDiagnosticsInteraction.reveal(diagnosticsExpanded: $diagnosticsExpanded) {
                    withAnimation { proxy.scrollTo("analytics-diagnostics", anchor: .top) }
                }
            }
            VStack(spacing: 0) {
                header(status, contentWidth: contentWidth, onViewDiagnostics: revealDiagnostics)
                    .padding(.vertical, 16)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: AnalyticsDashboardLayout.sectionSpacing) {
                        if case .initialLoading = status {
                            ProgressView().controlSize(.small).accessibilityHidden(true)
                        }
                        if let snapshot {
                            AnalyticsDashboardContent(
                                snapshot: snapshot,
                                contentWidth: contentWidth,
                                diagnosticsExpanded: $diagnosticsExpanded,
                                estimateDefinitionExpanded: $estimateDefinitionExpanded,
                                expandedSections: $expandedSections,
                                onViewDiagnostics: revealDiagnostics
                            )
                        }
                    }
                    .frame(width: contentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, AnalyticsDashboardLayout.horizontalInset)
                }
            }
        }
    }
    .frame(minWidth: 640, minHeight: 400)
    .onReceive(viewModel.$state) { state in
        if case let .fresh(snapshot) = state { lastSuccessfulSnapshot = snapshot }
        if case let .stale(snapshot) = state { lastSuccessfulSnapshot = snapshot }
    }
}

private func header(
    _ status: AnalyticsDashboardStatus,
    contentWidth: CGFloat,
    onViewDiagnostics: @escaping () -> Void
) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Analytics").font(.title2.weight(.semibold))
                Text(captureCopy).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh") { viewModel.refresh() }
                .disabled(viewModel.isLoading)
                .accessibilityLabel("Refresh analytics")
                .accessibilityValue(AnalyticsDisplayFormatter.refreshAccessibilityValue(isLoading: viewModel.isLoading))
        }
        if status.isWarning {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(status.text, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if displayedSnapshot != nil {
                    Button("View diagnostics", action: onViewDiagnostics)
                        .font(.system(size: 12, weight: .medium))
                        .accessibilityLabel("View analytics diagnostics")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Text(status.text).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
    .frame(width: contentWidth, alignment: .leading)
    .frame(maxWidth: .infinity, alignment: .center)
}
```

This preserves the old `captureCopy`, fixed header, one retained window, and disabled in-flight Refresh. The generic update text carries an actual partial-data caveat when the retained snapshot is partial; it does not falsely claim a healthy state.

- [ ] **Step 5: Run the focused GREEN check, then the one Task-3 full gate.**

Run: `make swift-test SWIFT_TEST_FILTER=AnalyticsWindowControllerTests`

Expected: the typed six-state priority sequence is green; calling the actual shared diagnostics action expands its real binding, schedules the exact anchor, and leaves repository calls at one; a failed refresh retains last-good content and raw error text stays absent.

Then run, serially after the focused run: `make test`

Expected: exit `0`; no direct Swift test invocation, Core semantics, ABI, or analytics test driver is added.

- [ ] **Step 6: Commit the focused task.**

```bash
git add Sources/Needlbar/Analytics/AnalyticsView.swift Tests/NeedlbarTests/AnalyticsWindowControllerTests.swift
git commit -m "feat: add balanced analytics status and diagnostics navigation"
```

### Task 4: Perform bounded native QA and final serial gates without overstating accessibility evidence

**Files:**

- Modify only if a focused fixture assertion is genuinely missing: `Tests/NeedlbarTests/AnalyticsWindowControllerTests.swift`
- Update after truthful evidence exists (root-owned): `docs/STATUS.md`

- [ ] **Step 1: Add any remaining in-process native-host fixture assertions before visual inspection.**

Use only the existing test target builders. Add this test-target pixel-render matrix; it keeps deterministic fixture/native-host evidence distinct from the normal app's live capture. It intentionally covers every requested fixture state and width, whereas a live capture can cover only states the local data happens to expose.

```swift
@Test func balancedNativeFixturePixelMatrixCoversRequiredStatesWidthsAndAppearances() throws {
    let fixtures: [(String, AnalyticsSnapshot)] = [
        ("empty", testAnalyticsSnapshot()),
        ("mixed", populatedAnalyticsSnapshot()),
        ("maximum", maximumAnalyticsSnapshot())
    ]
    let widths: [CGFloat] = [640, 760, 1_400]
    let appearances = [NSAppearance(named: .aqua), NSAppearance(named: .darkAqua)]

    for (name, snapshot) in fixtures {
        for width in widths {
            for optionalAppearance in appearances {
                let appearance = try #require(optionalAppearance)
                let png = try renderAnalyticsFixturePNG(snapshot: snapshot, width: width, appearance: appearance)
                #expect(png.count > 64, "\(name) at \(width) must produce a native pixel render")
                let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                    .appendingPathComponent("needlbar-analytics-pixel-qa", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let file = directory.appendingPathComponent("\(name)-\(Int(width))-\(appearance.name.rawValue).png")
                try png.write(to: file, options: .atomic)
            }
        }
    }
}

@MainActor
private func renderAnalyticsFixturePNG(snapshot: AnalyticsSnapshot, width: CGFloat, appearance: NSAppearance) throws -> Data {
    var diagnostics = false
    var definition = false
    var sections: Set<String> = []
    let root = ScrollView {
        AnalyticsDashboardContent(
            snapshot: snapshot,
            contentWidth: AnalyticsDashboardLayout.contentColumnWidth(forWindowContentWidth: width),
            diagnosticsExpanded: Binding(get: { diagnostics }, set: { diagnostics = $0 }),
            estimateDefinitionExpanded: Binding(get: { definition }, set: { definition = $0 }),
            expandedSections: Binding(get: { sections }, set: { sections = $0 }),
            onViewDiagnostics: {}
        )
    }
    return try renderAnalyticsViewPNG(root, width: width, appearance: appearance)
}

@MainActor
private func renderAnalyticsViewPNG<V: View>(_ root: V, width: CGFloat, appearance: NSAppearance) throws -> Data {
    let hosted = NSHostingView(rootView: root)
    hosted.appearance = appearance
    hosted.frame = NSRect(x: 0, y: 0, width: width, height: 520)
    hosted.layoutSubtreeIfNeeded()
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: 520,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ))
    hosted.cacheDisplay(in: hosted.bounds, to: bitmap)
    return try #require(bitmap.representation(using: .png, properties: [:]))
}
```

Add this full-shell state matrix to the same test suite. It exercises the header and retained snapshot as well as the body. The image-size assertion establishes only successful rendering; human inspection of the files is mandatory, and blank or clipped renders fail acceptance even if this assertion passes.

```swift
@Test func balancedNativeShellPixelMatrixIncludesLoadingStaleAndUnavailable() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("needlbar-analytics-pixel-qa", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for state in ["loading", "fresh", "updating", "stale", "unavailable"] {
        let repository = TestAnalyticsRepository()
        let model = AnalyticsViewModel(store: AnalyticsSnapshotStore(), repository: repository)
        model.loadIfNeeded()
        await repository.waitForCall(1)
        if state != "loading" {
            if state == "unavailable" {
                await repository.completeNext(with: .failure(TestAnalyticsError(raw: "fixture unavailable")))
            } else {
                await repository.completeNext(with: .success(populatedAnalyticsSnapshot()))
            }
            #expect(await eventually { !model.isLoading })
        }
        let hosted = NSHostingView(rootView: AnalyticsView(viewModel: model))
        // Mount before refresh so the view's local last-good retention observes fresh data.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosted
        hosted.layoutSubtreeIfNeeded()
        await Task.yield()
        if state == "updating" || state == "stale" {
            model.refresh()
            await repository.waitForCall(2)
            if state == "stale" {
                await repository.completeNext(with: .failure(TestAnalyticsError(raw: "fixture stale")))
                #expect(await eventually { model.presentationState == .stale })
            }
        }
        for width in [CGFloat(640), 760, 1_400] {
            for name in [NSAppearance.Name.aqua, .darkAqua] {
                let appearance = try #require(NSAppearance(named: name))
                window.appearance = appearance
                window.setContentSize(NSSize(width: width, height: width == 640 ? 400 : 520))
                hosted.layoutSubtreeIfNeeded()
                await Task.yield()
                let bitmap = try #require(hosted.bitmapImageRepForCachingDisplay(in: hosted.bounds))
                hosted.cacheDisplay(in: hosted.bounds, to: bitmap)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                #expect(png.count > 64)
                try png.write(to: directory.appendingPathComponent("shell-\(state)-\(Int(width))-\(name.rawValue).png"), options: .atomic)
            }
        }
        // Complete held requests so the fixture does not leave a suspended continuation.
        if state == "loading" || state == "updating" {
            await repository.completeNext(with: .success(populatedAnalyticsSnapshot()))
            #expect(await eventually { !model.isLoading })
        }
        window.close()
    }
}
```

This is deterministic rendered-pixel evidence, not an accessibility proxy. Preserve the output directory as test evidence. Do not add screenshot tooling to the public bundle, an analytics acceptance flag, or a bundle fixture parser. Expanded repository/disclosure and final-scroll interaction remain required native checks; a collapsed first-screen PNG cannot establish those.

- [ ] **Step 2: Run the focused fixture/native-host gate.**

Run: `make swift-test SWIFT_TEST_FILTER=AnalyticsWindowControllerTests`

Expected: exit `0` with native rendered pixels for empty/mixed/maximum at 640/760/1,400 in light/dark, and existing loading/stale/unavailable shell fixtures. Human QA inspects those artifacts for the specified stripes, tints, hierarchy, wrap/scroll and panel arrangements. This establishes test-target native rendering, not accessibility traversal or live-source attribution.

- [ ] **Step 3: Inspect the normal application manually and record two distinct evidence rows.**

First run the normal app from this worktree after `make rust`:

```bash
make rust
swift run Needlbar
```

Open Analytics using the regular app menu path and inspect only the **live local states actually available** at default 760×520, minimum 640×400, and approximately 1,400-point content width, in light and dark appearance. Check the retained window, centered 960-point cap/insets, fixed aligned header, 3/2/3 card layouts, 1/1/2 lower-panel layouts, stripes/icon badges, type hierarchy, actual long labels/details, and final-disclosure scroll reachability. Do not claim that a live capture covered empty, mixed, loading, stale, unavailable, or maximum fixtures unless it actually did; those deterministic states belong to the test-host pixel matrix.

Record this separately from the **test-target fixture host** result in `docs/STATUS.md`: test-host pixel output covers deterministic fixture states; normal app covers the actual retained window and whatever live source state occurred. It must not say the live capture proves the repository-attribution cause.

Try keyboard traversal and VoiceOver/AX labels/expanded values once with the normal app. If AX traversal or CUA is still empty/times out, record the method, exact blocker, and unverified checks (keyboard traversal, accessible labels/state, and final-scroll reachability if not manually observable). Do not retry indefinitely and do not mark those items passed from formatter or NSHosting composition tests.

If a fixture-fed launched **normal app** is required for acceptance rather than the current test-target native host plus live normal app, stop and request a new, reviewed scope: the only existing acceptance driver intentionally excludes analytics, and this plan forbids adding a production hook or public analytics test ABI.

- [ ] **Step 4: Run the final serial project gates.**

Run these commands one at a time, only after the manual observation is recorded; do not run them in parallel:

```bash
make test
make package
make smoke
```

Expected: each command exits `0`. `make package` creates only the local `dist/Needlbar.app` and archive; `make smoke` verifies that local bundle starts and cleans up its child. Neither command authorizes installation, replacement of a runtime bundle, merge, push, tag, release, or settings reset.

- [ ] **Step 5: Record only the acceptance actually achieved.**

Root updates `docs/STATUS.md` with exact focused/full/package/smoke exits, test-host pixel versus normal-app-live methods, any retained AX/CUA blocker, and the next approved continuation point. If keyboard/AX or manual final-scroll acceptance remains blocked, state that the implementation is test/package verified but **Task 3 visual acceptance remains open**. Do not use a "complete" task status or completion commit in that case.

Only if all required native acceptance is observed may root make a final documentation commit after self-review. Otherwise retain the already committed implementation/test history, commit only a truthful blocker/status update if authorized, and wait for the required observation capability; do not manufacture a final-success commit.

Do not merge, push, install, replace an existing app, tag, release, or package beyond the local verification artifact without a later, explicit user authorization for the exact current runtime. Any later installation must back up the resolved target recoverably and preserve preferences/credentials; it is not part of this plan.

## Requirement-to-task trace and tradeoffs

| Approved requirement | Plan coverage |
| --- | --- |
| 640×400 minimum / 760×520 default; centered `min(width - 48, 960)` column | Tasks 1–2 geometry helper and hosted widths; Task 4 normal-app inspection |
| 3 equal cards at ≥600, otherwise 2/1 at 180 minimum; 1/1/2 lower panels | Task 1 exact geometry assertions and Task 2 consumed grids |
| 3-point blue/teal/purple stripe, tinted outlined cards, 30-point SF Symbol badge; 28/24 values and 13/12/11 typography | Task 1 production card primitive and style assertions; Task 4 visual check |
| fixed aligned header, single canonical priority state, disabled in-flight Refresh | Task 3 resolver/header and existing serialized-view-model tests |
| truthful unavailable/zero, separate repository/unattributed totals, timestamp predicate | Task 2 existing Core projection consumption and Task 3 reason-free Unattributed panel |
| retained repository details; raw reasons only once in Diagnostics | Task 2 keeps `repositoryRow`; Task 3 removes Unattributed rows and retains Core diagnostics once |
| collapsed disclosures, View diagnostics expands/scrolls without fetch | Task 3 local reader callback and request-count fixture test |
| native light/dark, width/state, scroll/keyboard/AX acceptance | Task 4 bounded fixture-host + normal-app evidence; blocker remains explicit rather than fabricated |

The one tradeoff is deliberately conservative: no launched-app fixture driver is added because it would broaden the approved visual-only scope and violate the existing acceptance-driver boundary. The native test host gives deterministic composition evidence, while normal app inspection exercises the retained real window and live source path. If native AX/keyboard inspection remains inaccessible, the implementation may be build/test verified but visual acceptance remains open and must be reported as such.
