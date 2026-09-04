# Adaptive system dashboard sizing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the main system-dashboard popover 340 points wide and content-height-driven, respecting existing module/provider visibility while preserving a fixed header/footer, safe scrolling, actions, state, and panel anchoring.

**Architecture:** Filter dashboard rows through the existing SystemMonitorConfiguration visibility settings, then measure the same SwiftUI content hierarchy without its ScrollView before presentation. A pure sizing policy clamps the measured height to the current screen, while the existing panel presenter gains a frame-only resize operation so live structural changes do not replace the visible hosting controller or reset scroll/disclosure state.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing, SwiftPM, existing Make verification and packaging scripts; no new dependencies, persistence keys, collectors, timers, or provider requests.

---

## Authority, workspace, and execution rules

The approved source of truth is docs/superpowers/specs/2026-09-03-adaptive-dashboard-sizing-design.md. Read AGENTS.md, docs/STATUS.md, the approved readability spec/plan, and the files named in each task before changing code.

Execute only in:

    /Users/taejunoh/Developer/LFG/needlbar/.worktrees/adaptive-dashboard-sizing

The branch is codex/adaptive-dashboard-sizing. Never use /Users/taejunoh/Documents. Preserve the unrelated root checkout, all other worktrees, the running public app, credentials, persisted preferences outside bounded native acceptance, and any untracked .superpowers/brainstorm content.

Use strict TDD for every production change: add the focused failing assertion, capture the intended RED, implement the smallest code, run the focused GREEN, run git diff --check, then commit. Run Make recipes serially because they install and restore the bridge test runtime. Source /Users/taejunoh/.cargo/env before Make commands when Cargo is absent from PATH. A zero-test filter, bare swift test, or macOS 26.5 host run is not macOS 14 acceptance.

Do not push, merge, publish, sign, notarize, or release unless the user separately requests it.

## Scope and invariants

- Main SystemDashboardPopoverView only; do not redesign Settings, Analytics, menu-bar two-line rendering, notch behavior, widgets, notifications, exports, or provider popovers.
- Fixed width is 340 points.
- Existing system visibleModules and provider isVisible settings drive dashboard rows. Factory defaults remain CPU, RAM, and AI.
- Existing configured order remains authoritative after filtering.
- Minimum height is 180 points, invalid-measurement fallback is 680 points, and the screen allowance is visible-frame height minus the existing 24-point inset.
- If the allowance is below 180 points, the screen allowance wins.
- The natural-height measurement tree contains no ScrollView. The visible tree uses the same section content inside the existing ScrollView.
- In-place resize reuses the current contentViewController and one shared observable layout object: the presenter changes only the panel frame, then the controller updates that object's height. It does not replace the root view, restart monitors, increment presentation generation, or call orderFrontRegardless.
- Usage/quota freshness provenance, Fable, provider actions, IP privacy, numeric formatting, data collection, refresh cadence, and outside-click dismissal remain unchanged.

## File map

| File | Responsibility |
| --- | --- |
| Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift | Filter the valid configured order through visibleModules without changing defaults or provider presentation. |
| Sources/Needlbar/Modules/Overview/SystemDashboardPopoverSizing.swift | New pure height policy, width/minimum/fallback constants, resize epsilon, observable displayed-height state, and AppKit-backed natural-height measurement boundary. |
| Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift | Share one section hierarchy between a non-scrolling measurement mode and the visible scrolling mode; render at the observable bounded height and 340-point width. |
| Sources/Needlbar/MenuBar/MenuPanelPresenter.swift | Add a frame-only resize operation to the existing presenter/window boundary. |
| Sources/Needlbar/MenuBar/MenuBarController.swift | Measure before first presentation, retain shared layout/anchor state, remeasure after existing model/config updates, and request resize only after a material height change. |
| Tests/NeedlbarTests/SystemDashboardPopoverTests.swift | Visibility, natural-height, all-enabled/Fable, provider-hidden, width, short-screen, live-value, appearance, privacy, and action regressions. |
| Tests/NeedlbarTests/MenuPanelPlacementTests.swift | Pure sizing-policy boundary and invalid-input tests. |
| Tests/NeedlbarTests/MenuPanelPresenterTests.swift | Frame-only resize identity, monitor, hidden-panel, and placement-failure tests. |
| Tests/NeedlbarTests/MenuBarControllerTests.swift | Initial measured presentation, structural resize, numeric no-churn, original anchor, and lifecycle regressions. |
| README.md | Factual content-sized dashboard wording and sanitized real-app screenshot, only after native acceptance. |
| docs/STATUS.md | Commits, command results, native evidence/limitations, macOS 14 deferral, and exact continuation point. |

No Package.swift change is planned because SwiftPM discovers the new source file automatically.

### Task 1: Make existing system-module visibility authoritative

**Files:**
- Modify: Tests/NeedlbarTests/SystemDashboardPopoverTests.swift
- Modify: Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift

- [ ] **Step 1: Replace the obsolete all-six test with visibility/order RED tests**

Replace dashboardPresentationAlwaysContainsAllSixSystemModules and update dashboardPresentationPreservesConfiguredModuleOrder with:

```swift
@Test func dashboardPresentationUsesFactoryDefaultVisibleModules() {
    let configuration = SystemMonitorConfiguration()
    let presentation = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(),
        configuration: configuration
    )

    #expect(configuration.visibleModules == Set([.cpu, .memory, .ai]))
    #expect(presentation.moduleIDs == [.cpu, .memory, .ai])
    #expect(presentation.cpu.usage == "24%")
    #expect(presentation.memory.used == "7.5 GiB")
}

@Test func dashboardPresentationFiltersConfiguredOrderByVisibleModules() {
    var configuration = SystemMonitorConfiguration()
    configuration.order = [.ai, .network, .cpu, .battery, .memory, .disk]
    configuration.visibleModules = Set([.disk, .ai, .cpu])

    let presentation = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(),
        configuration: configuration
    )

    #expect(presentation.moduleIDs == [.ai, .cpu, .disk])
}

@Test func dashboardPresentationAllowsEveryModuleToBeTurnedOff() {
    var configuration = SystemMonitorConfiguration()
    configuration.visibleModules = []

    let presentation = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(),
        configuration: configuration
    )

    #expect(presentation.moduleIDs.isEmpty)
}
```

- [ ] **Step 2: Run the focused tests and capture the intended RED**

Run:

```bash
source /Users/taejunoh/.cargo/env
make swift-test SWIFT_TEST_FILTER='dashboardPresentationUsesFactoryDefaultVisibleModules\|dashboardPresentationFiltersConfiguredOrderByVisibleModules\|dashboardPresentationAllowsEveryModuleToBeTurnedOff'
```

Expected: the default and filtered-order assertions fail because SystemDashboardPresentation currently ignores visibleModules and returns all six modules.

- [ ] **Step 3: Filter only the validated configured order**

In SystemDashboardPresentation.init, replace the current moduleIDs assignment with:

```swift
let configuredOrder = configuration.order
let validOrder = configuredOrder.count == MonitorModuleID.allCases.count
    && Set(configuredOrder) == Set(MonitorModuleID.allCases)
    ? configuredOrder
    : MonitorModuleID.defaultOrder
moduleIDs = validOrder.filter(configuration.visibleModules.contains)
```

Do not change SystemMonitorConfiguration defaults, ModuleConfiguration keys, menu-bar rendering, or AI visibility.

- [ ] **Step 4: Run focused and neighboring presentation tests**

Run:

```bash
source /Users/taejunoh/.cargo/env
make swift-test SWIFT_TEST_FILTER='dashboardPresentation\|dashboardReadabilityPreservesConfiguredOrderAndIPPrivacy'
git diff --check
```

Expected: all selected tests pass. If dashboardReadabilityPreservesConfiguredOrderAndIPPrivacy still expects all six rows, set its visibleModules to Set(MonitorModuleID.allCases) before constructing the presentation; do not weaken its order or IP assertions.

- [ ] **Step 5: Run the full gate and commit**

```bash
source /Users/taejunoh/.cargo/env
make test
git add Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift Tests/NeedlbarTests/SystemDashboardPopoverTests.swift
git commit -m "feat: respect dashboard module visibility"
```

Expected: make test exits 0 with all Rust, vendor, Swift, widget, package, and notarization contract tests passing.

### Task 2: Add the pure adaptive sizing policy

**Files:**
- Create: Sources/Needlbar/Modules/Overview/SystemDashboardPopoverSizing.swift
- Modify: Tests/NeedlbarTests/MenuPanelPlacementTests.swift

- [ ] **Step 1: Add policy RED tests**

Append inside MenuPanelPlacementTests:

```swift
@Test func dashboardSizingUsesApprovedWidthAndMeasuredHeight() {
    #expect(SystemDashboardPanelSizing.width == 340)
    #expect(SystemDashboardPanelSizing.height(
        naturalContentHeight: 742,
        visibleScreenHeight: 1_000
    ) == 742)
}

@Test func dashboardSizingClampsToMinimumAndScreenAllowance() {
    #expect(SystemDashboardPanelSizing.height(
        naturalContentHeight: 120,
        visibleScreenHeight: 1_000
    ) == 180)
    #expect(SystemDashboardPanelSizing.height(
        naturalContentHeight: 900,
        visibleScreenHeight: 824
    ) == 800)
    #expect(SystemDashboardPanelSizing.height(
        naturalContentHeight: 400,
        visibleScreenHeight: 150
    ) == 126)
}

@Test func dashboardSizingFallsBackForEveryInvalidMeasurement() {
    for measurement in [CGFloat?.none, 0, -1, .nan, .infinity, -.infinity] {
        #expect(SystemDashboardPanelSizing.height(
            naturalContentHeight: measurement,
            visibleScreenHeight: 1_000
        ) == 680)
    }
}

@Test func dashboardSizingRejectsInvalidScreenAllowanceAndUsesResizeEpsilon() {
    #expect(SystemDashboardPanelSizing.height(
        naturalContentHeight: 400,
        visibleScreenHeight: .nan
    ) == 0)
    #expect(!SystemDashboardPanelSizing.shouldResize(current: 700, proposed: 700.49))
    #expect(SystemDashboardPanelSizing.shouldResize(current: 700, proposed: 700.5))
}
```

- [ ] **Step 2: Run the policy tests and capture RED**

```bash
source /Users/taejunoh/.cargo/env
make swift-test SWIFT_TEST_FILTER='dashboardSizing'
```

Expected: compilation fails because SystemDashboardPanelSizing does not exist.

- [ ] **Step 3: Create the complete policy file**

Create SystemDashboardPopoverSizing.swift with:

```swift
import AppKit

enum SystemDashboardPanelSizing {
    static let width: CGFloat = 340
    static let minimumHeight: CGFloat = 180
    static let fallbackHeight: CGFloat = 680
    static let verticalScreenAllowanceInset: CGFloat = 24
    static let resizeEpsilon: CGFloat = 0.5

    static func height(
        naturalContentHeight: CGFloat?,
        visibleScreenHeight: CGFloat
    ) -> CGFloat {
        guard visibleScreenHeight.isFinite, visibleScreenHeight > 0 else {
            return 0
        }
        let allowance = max(0, visibleScreenHeight - verticalScreenAllowanceInset)
        guard allowance > 0 else { return 0 }

        let candidate: CGFloat
        if let naturalContentHeight,
           naturalContentHeight.isFinite,
           naturalContentHeight > 0 {
            candidate = naturalContentHeight
        } else {
            candidate = fallbackHeight
        }
        let effectiveMinimum = min(minimumHeight, allowance)
        return min(max(effectiveMinimum, candidate), allowance)
    }

    static func shouldResize(current: CGFloat, proposed: CGFloat) -> Bool {
        current.isFinite
            && proposed.isFinite
            && abs(current - proposed) >= resizeEpsilon
    }
}
```

- [ ] **Step 4: Run focused tests, diff check, and commit**

```bash
source /Users/taejunoh/.cargo/env
make swift-test SWIFT_TEST_FILTER='dashboardSizing\|MenuPanelPlacement'
git diff --check
git add Sources/Needlbar/Modules/Overview/SystemDashboardPopoverSizing.swift Tests/NeedlbarTests/MenuPanelPlacementTests.swift
git commit -m "feat: define adaptive dashboard sizing policy"
```

Expected: the sizing and existing placement tests pass. Do not modify MenuPanelPlacement's existing 6-point safety margin.

### Task 3: Measure the real shared dashboard content

**Files:**
- Modify: Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift
- Modify: Sources/Needlbar/Modules/Overview/SystemDashboardPopoverSizing.swift
- Modify: Tests/NeedlbarTests/SystemDashboardPopoverTests.swift

- [ ] **Step 1: Add natural-height and bounded-view RED tests**

Replace the two fixed 360-by-680 fitting tests with these tests. Keep the existing fixture helper and all privacy, Fable, state, action, and accessibility assertions.

```swift
@Test @MainActor func dashboardNaturalHeightTracksEnabledModulesAndProviders() throws {
    let snapshot = dashboardFixtureSnapshot(
        claudeQuotaWindows: [
            try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 68, resetsAt: nil),
            try QuotaWindow(
                id: QuotaWindow.claudeFableWeeklyID,
                title: "Fable weekly",
                usedPercent: 25,
                resetsAt: Date(timeIntervalSince1970: 20_000)
            ),
        ],
        perCoreUsage: Array(repeating: MetricPercentage(50)!, count: 15)
    )
    var fullConfiguration = SystemMonitorConfiguration()
    fullConfiguration.visibleModules = Set(MonitorModuleID.allCases)
    let fullModel = SystemDashboardModel(snapshot: snapshot, configuration: fullConfiguration)
    let fullHeight = try #require(SystemDashboardPopoverMeasurement.naturalHeight(for: fullModel))

    var compactConfiguration = fullConfiguration
    compactConfiguration.visibleModules = Set([.cpu, .memory, .ai])
    compactConfiguration.ai[.codex] = AIProviderDisplayPreference(isVisible: false, metric: .remaining)
    compactConfiguration.ai[.cursor] = AIProviderDisplayPreference(isVisible: false, metric: .remaining)
    let compactModel = SystemDashboardModel(snapshot: snapshot, configuration: compactConfiguration)
    let compactHeight = try #require(SystemDashboardPopoverMeasurement.naturalHeight(for: compactModel))

    #expect(fullHeight > 400)
    #expect(compactHeight < fullHeight)
}

@Test @MainActor func dashboardVisibleViewUsesMeasuredOrScreenLimitedHeight() throws {
    var configuration = SystemMonitorConfiguration()
    configuration.visibleModules = Set(MonitorModuleID.allCases)
    let model = SystemDashboardModel(
        snapshot: dashboardFixtureSnapshot(
            claudeQuotaWindows: [
                try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 68, resetsAt: nil),
                try QuotaWindow(
                    id: QuotaWindow.claudeFableWeeklyID,
                    title: "Fable weekly",
                    usedPercent: 25,
                    resetsAt: Date(timeIntervalSince1970: 20_000)
                ),
            ]
        ),
        configuration: configuration
    )
    let naturalHeight = try #require(SystemDashboardPopoverMeasurement.naturalHeight(for: model))
    let tallHeight = SystemDashboardPanelSizing.height(
        naturalContentHeight: naturalHeight,
        visibleScreenHeight: naturalHeight + SystemDashboardPanelSizing.verticalScreenAllowanceInset
    )
    let shortHeight = SystemDashboardPanelSizing.height(
        naturalContentHeight: naturalHeight,
        visibleScreenHeight: 424
    )
    let tall = NSHostingController(
        rootView: SystemDashboardPopoverView(model: model, height: tallHeight)
    )
    let short = NSHostingController(
        rootView: SystemDashboardPopoverView(model: model, height: shortHeight)
    )

    #expect(tall.view.fittingSize == NSSize(width: 340, height: tallHeight))
    #expect(tallHeight == naturalHeight)
    #expect(short.view.fittingSize == NSSize(width: 340, height: 400))
}
```

Update dashboardReadabilityFittingIsStableAcrossLiveNumericChanges and dashboardReadabilityKeepsSizeStableAcrossAppearances to construct each visible view with the same measured height and expect width 340. The two compared natural heights must also be equal.

- [ ] **Step 2: Run the focused tests and capture RED**

```bash
source /Users/taejunoh/.cargo/env
make swift-test SWIFT_TEST_FILTER='dashboardNaturalHeight\|dashboardVisibleView\|dashboardReadabilityFitting\|dashboardReadabilityKeepsSizeStableAcrossAppearances'
```

Expected: compilation fails because the measurement boundary and height initializer do not exist; existing 360-point expectations also fail once updated.

- [ ] **Step 3: Add visible and measurement modes to the popover**

In SystemDashboardPopoverSizing.swift, add the displayed-height state below SystemDashboardPanelSizing:

```swift
@MainActor
final class SystemDashboardPopoverLayout: ObservableObject {
    @Published var height: CGFloat

    init(height: CGFloat) {
        self.height = height
    }
}
```

Add import SwiftUI to that file for ObservableObject and Published.

In SystemDashboardPopoverView, replace maximumHeight with:

```swift
@ObservedObject private var layout: SystemDashboardPopoverLayout
private let isMeasuring: Bool
```

Replace the public model initializer, add the internal shared-layout initializer used by MenuBarController, and add the internal measurement initializer:

```swift
public init(
    model: SystemDashboardModel,
    height: CGFloat = SystemDashboardPanelSizing.fallbackHeight,
    onShowSettings: @escaping () -> Void = {},
    onShowAnalytics: @escaping () -> Void = {},
    onProviderAction: @escaping (ProviderID) -> Void = { _ in }
) {
    _model = ObservedObject(wrappedValue: model)
    _layout = ObservedObject(
        wrappedValue: SystemDashboardPopoverLayout(height: height)
    )
    isMeasuring = false
    self.onShowSettings = onShowSettings
    self.onShowAnalytics = onShowAnalytics
    self.onProviderAction = onProviderAction
}

init(
    model: SystemDashboardModel,
    layout: SystemDashboardPopoverLayout,
    onShowSettings: @escaping () -> Void = {},
    onShowAnalytics: @escaping () -> Void = {},
    onProviderAction: @escaping (ProviderID) -> Void = { _ in }
) {
    _model = ObservedObject(wrappedValue: model)
    _layout = ObservedObject(wrappedValue: layout)
    isMeasuring = false
    self.onShowSettings = onShowSettings
    self.onShowAnalytics = onShowAnalytics
    self.onProviderAction = onProviderAction
}

init(measuring model: SystemDashboardModel) {
    _model = ObservedObject(wrappedValue: model)
    _layout = ObservedObject(
        wrappedValue: SystemDashboardPopoverLayout(
            height: SystemDashboardPanelSizing.fallbackHeight
        )
    )
    isMeasuring = true
    onShowSettings = {}
    onShowAnalytics = {}
    onProviderAction = { _ in }
}
```

Change the snapshot/configuration initializer's self.init call to pass height: SystemDashboardPanelSizing.fallbackHeight.

Replace body and add these two shared helpers immediately below it:

```swift
@ViewBuilder
public var body: some View {
    if isMeasuring {
        dashboardChrome {
            dashboardSections
        }
        .frame(width: SystemDashboardPanelSizing.width)
        .fixedSize(horizontal: false, vertical: true)
    } else {
        dashboardChrome {
            ScrollView {
                dashboardSections
            }
        }
        .frame(width: SystemDashboardPanelSizing.width, height: layout.height)
    }
}

private func dashboardChrome<Content: View>(
    @ViewBuilder content: () -> Content
) -> some View {
    DashboardSurface {
        VStack(spacing: 0) {
            header
            Divider()
            content()
            Divider()
            footer
        }
    }
}

private var dashboardSections: some View {
    VStack(alignment: .leading, spacing: 0) {
        ForEach(model.presentation.moduleIDs, id: \.self) { module in
            dashboardSection(module)
            if module != model.presentation.moduleIDs.last {
                Divider().padding(.leading, 18)
            }
        }
    }
    .padding(.vertical, 4)
}
```

Delete only the old body-local LazyVStack and fixed min(680, ...) frame. Leave every dashboardSection, network, provider/Fable, header, footer, action, truncation, help, and accessibility implementation unchanged. The same SystemDashboardPopoverLayout instance passed by MenuBarController must remain installed for the lifetime of the shown panel.

- [ ] **Step 4: Add the complete measurement boundary**

Append to SystemDashboardPopoverSizing.swift:

```swift
@MainActor
enum SystemDashboardPopoverMeasurement {
    static func naturalHeight(for model: SystemDashboardModel) -> CGFloat? {
        let controller = NSHostingController(
            rootView: SystemDashboardPopoverView(measuring: model)
        )
        controller.view.layoutSubtreeIfNeeded()
        let measured = controller.view.fittingSize.height
        guard measured.isFinite, measured > 0 else { return nil }
        return measured
    }
}
```

This host is measurement-only and is discarded after fitting. Do not measure the visible ScrollView and do not reuse this controller as the displayed controller.

- [ ] **Step 5: Run focused and regression tests**

```bash
source /Users/taejunoh/.cargo/env
make swift-test SWIFT_TEST_FILTER='dashboardNaturalHeight\|dashboardVisibleView\|dashboardReadability\|dashboardPresentation'
git diff --check
```

Expected: all selected tests pass, including full/compact height ordering, 340-point width, 400-point short-screen height, live-value stability, light/dark fitting parity, IP privacy, provider status provenance, and Fable semantics.

- [ ] **Step 6: Run the full gate and commit**

```bash
source /Users/taejunoh/.cargo/env
make test
git add Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift Sources/Needlbar/Modules/Overview/SystemDashboardPopoverSizing.swift Tests/NeedlbarTests/SystemDashboardPopoverTests.swift
git commit -m "feat: measure adaptive dashboard content"
```

### Task 4: Resize an existing panel without replacing its content

**Files:**
- Modify: Sources/Needlbar/MenuBar/MenuPanelPresenter.swift
- Modify: Tests/NeedlbarTests/MenuPanelPresenterTests.swift
- Modify: Tests/NeedlbarTests/MenuBarControllerTests.swift

- [ ] **Step 1: Add presenter resize RED tests**

Append inside MenuPanelPresenterTests:

```swift
@Test func resizeChangesOnlyTheShownPanelFrame() throws {
    let window = FakeMenuPanelWindow()
    let monitor = FakeMenuPanelDismissalMonitor()
    let presenter = AppKitMenuPanelPresenter(window: window, dismissalMonitor: monitor)
    let anchor = testAnchor()

    #expect(presenter.present(
        FixedSizeViewController(size: NSSize(width: 340, height: 500)),
        anchoredAt: anchor
    ))
    let installedController = try #require(window.contentViewController)
    let expectedFrame = try #require(MenuPanelPlacement.frame(
        contentSize: NSSize(width: 340, height: 740),
        anchor: anchor
    ))

    #expect(presenter.resize(
        to: NSSize(width: 340, height: 740),
        anchoredAt: anchor
    ))
    #expect(window.frame == expectedFrame)
    #expect(window.contentViewController === installedController)
    #expect(window.orderFrontRegardlessCallCount == 1)
    #expect(monitor.startCallCount == 1)
    #expect(monitor.token.cancelCallCount == 0)
    #expect(presenter.isShown)
}

@Test func resizeRejectsHiddenOrUnplaceablePanelsWithoutMutation() {
    let window = FakeMenuPanelWindow()
    let monitor = FakeMenuPanelDismissalMonitor()
    let presenter = AppKitMenuPanelPresenter(window: window, dismissalMonitor: monitor)
    let anchor = testAnchor()

    #expect(!presenter.resize(
        to: NSSize(width: 340, height: 500),
        anchoredAt: anchor
    ))
    #expect(window.setFrameCalls.isEmpty)

    #expect(presenter.present(
        FixedSizeViewController(size: NSSize(width: 340, height: 500)),
        anchoredAt: anchor
    ))
    let originalFrame = window.frame
    #expect(!presenter.resize(
        to: NSSize(width: 2_000, height: 2_000),
        anchoredAt: anchor
    ))
    #expect(window.frame == originalFrame)
    #expect(window.setFrameCalls.count == 1)
}
```

Add a compile-only stub with call recording to FakeMenuPanelPresenter in MenuBarControllerTests so the test target can adopt the new protocol after production changes:

```swift
private(set) var resizedSizes: [NSSize] = []
private(set) var resizedAnchors: [StatusItemPresentationAnchor] = []

func resize(
    to contentSize: NSSize,
    anchoredAt anchor: StatusItemPresentationAnchor
) -> Bool {
    guard isShown else { return false }
    resizedSizes.append(contentSize)
    resizedAnchors.append(anchor)
    return true
}
```

- [ ] **Step 2: Run the presenter tests and capture RED**

```bash
source /Users/taejunoh/.cargo/env
make swift-test SWIFT_TEST_FILTER='resizeChangesOnlyTheShownPanelFrame\|resizeRejectsHiddenOrUnplaceablePanels'
```

Expected: compilation fails because MenuPanelPresenting and AppKitMenuPanelPresenter do not define resize.

- [ ] **Step 3: Extend the protocol and implement frame-only resize**

Add to MenuPanelPresenting:

```swift
@discardableResult
func resize(
    to contentSize: NSSize,
    anchoredAt anchor: StatusItemPresentationAnchor
) -> Bool
```

Add to AppKitMenuPanelPresenter immediately before dismiss:

```swift
@discardableResult
public func resize(
    to contentSize: NSSize,
    anchoredAt anchor: StatusItemPresentationAnchor
) -> Bool {
    guard shown,
          let frame = MenuPanelPlacement.frame(contentSize: contentSize, anchor: anchor)
    else {
        return false
    }
    window.setFrame(frame, display: true)
    return true
}
```

Do not change window.contentViewController, presentationGeneration, dismissalMonitoringToken, monitor start/cancel behavior, or order-front state in resize.

- [ ] **Step 4: Run presenter and lifecycle regressions**

```bash
source /Users/taejunoh/.cargo/env
make swift-test SWIFT_TEST_FILTER='MenuPanelPresenter\|MenuPanelPlacement\|MenuBarController'
git diff --check
```

Expected: resize tests and all existing presentation/dismissal/generation/outside-click tests pass.

- [ ] **Step 5: Commit the presenter boundary**

```bash
git add Sources/Needlbar/MenuBar/MenuPanelPresenter.swift Tests/NeedlbarTests/MenuPanelPresenterTests.swift Tests/NeedlbarTests/MenuBarControllerTests.swift
git commit -m "feat: resize the active menu panel in place"
```

### Task 5: Measure before presentation and resize on structural updates

**Files:**
- Modify: Sources/Needlbar/MenuBar/MenuBarController.swift
- Modify: Tests/NeedlbarTests/MenuBarControllerTests.swift

- [ ] **Step 1: Add controller RED tests**

Extend FakeMenuPanelPresenter.present to record the fitted content size before returning:

```swift
private(set) var presentedContentSizes: [NSSize] = []
private(set) var presentedContentViewControllers: [NSViewController] = []

func present(
    _ contentViewController: NSViewController,
    anchoredAt anchor: StatusItemPresentationAnchor
) -> Bool {
    presentCount += 1
    presentedAnchors.append(anchor)
    contentViewController.view.layoutSubtreeIfNeeded()
    presentedContentSizes.append(contentViewController.view.fittingSize)
    presentedContentViewControllers.append(contentViewController)
    eventLog?.events.append("present")
    guard presentResult else { return false }
    isShown = true
    return true
}
```

Add these tests to MenuBarControllerTests:

```swift
@Test func overviewUsesMeasured340PointContentBeforeFirstPresentation() async throws {
    let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
    let combinedStore = CombinedSnapshotStore(now: Date(timeIntervalSince1970: 10_000))
    let presenter = FakeMenuPanelPresenter()
    let controller = makeMenuBarController(
        configuration: configuration,
        snapshotStore: ProviderSnapshotStore(),
        combinedSnapshotStore: combinedStore,
        loginCoordinator: testLoginCoordinator(),
        statusItemFactory: FakeStatusItemFactory(),
        panelPresenter: presenter
    )
    await controller.refresh()
    let snapshot = await combinedStore.snapshot()
    let expectedModel = SystemDashboardModel(
        snapshot: snapshot,
        configuration: configuration.systemMonitor
    )
    let naturalHeight = try #require(
        SystemDashboardPopoverMeasurement.naturalHeight(for: expectedModel)
    )
    let expectedHeight = SystemDashboardPanelSizing.height(
        naturalContentHeight: naturalHeight,
        visibleScreenHeight: FakeStatusItemHandle.literalAnchor.visibleFrameInScreen.height
    )

    controller.openOverview()

    #expect(presenter.presentCount == 1)
    #expect(presenter.presentedContentSizes.first == NSSize(width: 340, height: expectedHeight))
}

@Test func visibleModuleChangeResizesWithoutRepresentingAndKeepsAnchor() async throws {
    let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
    let factory = FakeStatusItemFactory()
    let presenter = FakeMenuPanelPresenter()
    let controller = makeMenuBarController(
        configuration: configuration,
        snapshotStore: ProviderSnapshotStore(),
        loginCoordinator: testLoginCoordinator(),
        statusItemFactory: factory,
        panelPresenter: presenter
    )
    await controller.startObserving()
    defer { controller.stopObserving() }
    let item = try #require(factory.created.first)
    item.performAction()
    #expect(await eventually { presenter.presentCount == 1 && presenter.isShown })

    var monitor = configuration.systemMonitor
    monitor.visibleModules.insert(.disk)
    configuration.setSystemMonitor(monitor)

    #expect(await eventually { presenter.resizedSizes.count == 1 })
    #expect(presenter.presentCount == 1)
    #expect(presenter.resizedSizes.first?.width == 340)
    #expect(presenter.resizedAnchors == presenter.presentedAnchors)
    let installedController = try #require(presenter.presentedContentViewControllers.first)
    let resizedHeight = try #require(presenter.resizedSizes.first?.height)
    #expect(await eventually {
        installedController.view.layoutSubtreeIfNeeded()
        return installedController.view.fittingSize.height == resizedHeight
    })
    #expect(presenter.presentedContentViewControllers.count == 1)
}

@Test func visibleAIProviderChangeResizesWithoutRepresentingAndKeepsAnchor() async throws {
    let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
    let factory = FakeStatusItemFactory()
    let presenter = FakeMenuPanelPresenter()
    let controller = makeMenuBarController(
        configuration: configuration,
        snapshotStore: ProviderSnapshotStore(),
        loginCoordinator: testLoginCoordinator(),
        statusItemFactory: factory,
        panelPresenter: presenter
    )
    await controller.startObserving()
    defer { controller.stopObserving() }
    let item = try #require(factory.created.first)
    item.performAction()
    #expect(await eventually { presenter.presentCount == 1 && presenter.isShown })

    var monitor = configuration.systemMonitor
    monitor.ai[.cursor]?.isVisible = false
    configuration.setSystemMonitor(monitor)

    #expect(await eventually { presenter.resizedSizes.count == 1 })
    #expect(presenter.presentCount == 1)
    #expect(presenter.resizedAnchors == presenter.presentedAnchors)
    #expect(presenter.presentedContentViewControllers.count == 1)
}
```

In liveCombinedUpdatesRefreshTheDashboardModelWithoutRepresentingThePanel add:

```swift
#expect(presenter.resizedSizes.isEmpty)
```

after the existing presentCount/isShown assertions. This turns the existing live numeric update into an explicit no-resize regression.

- [ ] **Step 2: Run the controller tests and capture RED**

```bash
source /Users/taejunoh/.cargo/env
make swift-test SWIFT_TEST_FILTER='overviewUsesMeasured340PointContentBeforeFirstPresentation\|visibleModuleChangeResizesWithoutRepresentingAndKeepsAnchor\|visibleAIProviderChangeResizesWithoutRepresentingAndKeepsAnchor\|liveCombinedUpdatesRefreshTheDashboardModelWithoutRepresentingThePanel'
```

Expected: the new initial-size assertion fails because showPanel still constructs the old fixed-height view, and both structural-change tests time out because reconcile never requests resize.

- [ ] **Step 3: Add displayed dashboard sizing state**

Add beside dashboardModel:

```swift
private var displayedDashboardLayout: SystemDashboardPopoverLayout?
private var displayedDashboardAnchor: StatusItemPresentationAnchor?
```

- [ ] **Step 4: Measure after existing model reconciliation**

After reconcile updates or creates dashboardModel, call:

```swift
resizeDisplayedDashboardIfNeeded()
```

Add this complete helper near showPanel:

```swift
private func resizeDisplayedDashboardIfNeeded() {
    guard panelPresenter.isShown,
          activeMenuModule == .overview,
          let model = dashboardModel,
          let layout = displayedDashboardLayout,
          let anchor = displayedDashboardAnchor
    else {
        return
    }

    let naturalHeight = SystemDashboardPopoverMeasurement.naturalHeight(for: model)
    let proposedHeight = SystemDashboardPanelSizing.height(
        naturalContentHeight: naturalHeight,
        visibleScreenHeight: anchor.visibleFrameInScreen.height
    )
    guard SystemDashboardPanelSizing.shouldResize(
        current: layout.height,
        proposed: proposedHeight
    ) else {
        return
    }

    if panelPresenter.resize(
        to: NSSize(width: SystemDashboardPanelSizing.width, height: proposedHeight),
        anchoredAt: anchor
    ) {
        layout.height = proposedHeight
    }
}
```

This helper may measure on every existing combined/config update, but must not call resize when the bounded height differs by less than 0.5 point.

- [ ] **Step 5: Replace fixed-cap construction in showPanel**

Replace maximumHeight and the view construction with:

```swift
let naturalHeight = SystemDashboardPopoverMeasurement.naturalHeight(for: model)
let panelHeight = SystemDashboardPanelSizing.height(
    naturalContentHeight: naturalHeight,
    visibleScreenHeight: anchor.visibleFrameInScreen.height
)
let layout = SystemDashboardPopoverLayout(height: panelHeight)
let view = AnyView(SystemDashboardPopoverView(
    model: model,
    layout: layout,
    onShowSettings: { [weak self] in self?.performSettingsAction() },
    onShowAnalytics: { [weak self] in self?.performAnalyticsAction() },
    onProviderAction: { [weak self] provider in
        self?.performAuthenticationAction(for: provider)
    }
))
```

After panelPresenter.present succeeds and alongside activeMenuModule assignment, store:

```swift
displayedDashboardLayout = layout
displayedDashboardAnchor = anchor
```

In panelDidDismiss, clear both:

```swift
displayedDashboardLayout = nil
displayedDashboardAnchor = nil
```

Do not increment panelPresentationGeneration during resize, restart global monitoring, request another snapshot, or replace the hosting controller/root view. Update the shared layout object only after presenter resize succeeds, so placement failure leaves both the panel frame and SwiftUI viewport at the previous height.

- [ ] **Step 6: Run focused controller, view, presenter, and action tests**

```bash
source /Users/taejunoh/.cargo/env
make swift-test SWIFT_TEST_FILTER='MenuBarController\|MenuPanelPresenter\|MenuPanelPlacement\|dashboardNaturalHeight\|dashboardVisibleView\|dashboardReadability\|Fable'
git diff --check
```

Expected: initial presentation is 340 points wide and exactly matches the independently measured bounded height; module and provider-visibility changes each create exactly one resize with the original anchor while the installed hosting controller and observed layout object remain live; numeric-only updates do not resize or re-present; existing Settings, Analytics, Claude/Codex, Cursor Spending, Fable, dismissal, and stale-generation tests pass.

- [ ] **Step 7: Run the full gate and commit**

```bash
source /Users/taejunoh/.cargo/env
make test
git add Sources/Needlbar/MenuBar/MenuBarController.swift Tests/NeedlbarTests/MenuBarControllerTests.swift
git commit -m "feat: adapt dashboard panel to visible content"
```

### Task 6: Review, package, native acceptance, and documentation

**Files:**
- Modify after native acceptance: README.md
- Replace after sanitized native acceptance: docs/images/system-dashboard.png
- Modify after native acceptance: docs/STATUS.md
- Modify as execution proceeds: docs/superpowers/plans/2026-09-03-adaptive-dashboard-sizing.md

- [ ] **Step 1: Request two independent scoped reviews**

Request a spec-compliance review against docs/superpowers/specs/2026-09-03-adaptive-dashboard-sizing-design.md and a separate code-quality review of all implementation commits. Reviewers must verify:

- existing defaults remain CPU/RAM/AI while visibleModules now filters dashboard rows;
- configured order and provider visibility are preserved;
- measurement uses the shared non-scrolling content, not the visible ScrollView;
- first presentation is measured before display;
- resize keeps the installed hosting controller, monitor token, generation, anchor, scroll/disclosure state, and actions;
- invalid measurement and short-screen bounds match the policy;
- menu-bar rendering, providers, collectors, widgets, notifications, exports, and persistence keys are untouched.

Apply only verified in-scope findings with a regression test, rerun the affected focused suite, and request re-review before continuing.

- [ ] **Step 2: Run final automated gates serially and retain logs outside the repo**

```bash
source /Users/taejunoh/.cargo/env
make swift-test SWIFT_TEST_FILTER='dashboard\|SystemDashboard\|MenuPanel\|MenuBarController\|Fable\|Popover\|AcceptanceFixture'
source /Users/taejunoh/.cargo/env
make acceptance-test
source /Users/taejunoh/.cargo/env
make test
source /Users/taejunoh/.cargo/env
make package
source /Users/taejunoh/.cargo/env
make smoke
git diff --check
```

Record each full output under /Users/taejunoh/Developer/LFG/needlbar-adaptive-dashboard-sizing-qa/. Expected: every command exits 0. Existing macOS 26.5-object/macOS 14-link warnings may remain if they match the fresh baseline; do not report them as macOS 14 acceptance.

- [ ] **Step 3: Identify only the packaged development app**

Resolve exact process identities and paths before UI interaction:

```bash
ps -axo pid,etime,args | rg '/Users/taejunoh/Developer/LFG/needlbar/.worktrees/adaptive-dashboard-sizing/.*/Needlbar\.app/Contents/MacOS/Needlbar$'
```

Launch only the exact app produced by this worktree's make package. Keep the public release process and every unrelated app untouched. If the development and public processes cannot be distinguished by exact path and PID, stop native interaction and record the blocker.

- [ ] **Step 4: Perform bounded current-host native acceptance**

Using the exact development process:

1. Before changing anything, record one complete configuration snapshot: system visible set and order, every AI provider's visibility and metric, AI order, and both local/public IP toggles.
2. Through Settings, enable every system module and Claude/Codex/Cursor while keeping both IP rows disabled. Capture a narrow sanitized app-only image and verify 340-point width plus the complete AI Usage/Fable rows on a sufficiently tall display.
3. Turn one enabled system module and one enabled AI provider off through Settings, reopen the dashboard, and verify the panel height decreases without empty space.
4. Restore the entire configuration snapshot from item 1 through Settings before ending the check, including all system visibility/order, provider visibility/metric/order, and IP values—not only the two toggled rows.
5. Verify a constrained-height presentation keeps header/footer visible and scrolls only the section body; if the host cannot provide a short screen safely, mark this native item unobserved.
6. Verify dark-mode contrast without changing the global appearance unless the user explicitly authorizes it; otherwise mark dark native appearance unobserved.
7. Confirm the panel remains under the same status item, ordinary values refresh without width movement, and clicking outside dismisses only the panel.
8. Confirm Settings, Analytics, Claude/Codex browser login, Cursor Spending, Fable subordinate semantics, state wording, IP privacy, and accessibility/help behavior when safely observable. Do not trigger external login/spending actions merely to claim acceptance.

Capture only the exact app window or a narrow sanitized region. Do not retain account identifiers, IP addresses, credentials, raw provider payloads, or a full desktop screenshot. Mark every unavailable native capability unobserved in STATUS rather than inferring it from tests. macOS 14 remains deferred.

- [ ] **Step 5: Update README and the real screenshot only after native acceptance**

Replace the existing system-monitor paragraph with:

```markdown
The main dashboard combines enabled CPU, RAM, disk, network, battery, and AI usage in a compact, content-sized popover. It grows to fit enabled rows when screen space permits, scrolls only when needed, uses aligned high-contrast values, hides normal freshness noise, and keeps stale or failed states visible without changing the underlying metrics or provider actions.
```

Replace docs/images/system-dashboard.png only with the sanitized exact-app capture from Step 4 and change its README display width from 360 to 340. If the capture cannot be sanitized, retain the existing image and its existing width instead of using synthetic evidence. Keep the Settings screenshots.

- [ ] **Step 6: Update STATUS and plan checkboxes**

Append a dated docs/STATUS.md section with:

- all implementation and review-fix commit hashes;
- focused, acceptance, full, package, smoke, and diff-check results with exact counts and log paths;
- exact development app PID/path and sanitized capture path;
- observed width, natural full height, full AI/Fable visibility, settings-driven shrink, anchor, refresh stability, scroll, dark mode, actions, privacy, and dismissal behaviors;
- explicit unobserved limitations and macOS 14 deferral;
- confirmation that the full pre-acceptance configuration snapshot—not only sampled toggles—was restored;
- confirmation that the public app, credentials, widgets, push, merge, and release were untouched;
- the exact continuation point.

Mark only evidence-backed plan checkboxes complete. Use partial markers with a sentence for native items that remain unobserved.

- [ ] **Step 7: Verify the documentation checkpoint**

```bash
source /Users/taejunoh/.cargo/env
make test
source /Users/taejunoh/.cargo/env
make package
source /Users/taejunoh/.cargo/env
make smoke
git diff --check
git status --short
```

Expected: all commands exit 0 and only the intended README, optional real screenshot, STATUS, and plan-checkbox changes remain. Review the diff for credentials, identifiers, IP addresses, synthetic evidence, unrelated UI changes, or altered persistence defaults.

- [ ] **Step 8: Commit the verified documentation checkpoint**

```bash
git add README.md docs/STATUS.md docs/superpowers/plans/2026-09-03-adaptive-dashboard-sizing.md
git add docs/images/system-dashboard.png
git commit -m "docs: record adaptive dashboard sizing verification"
```

If the screenshot was intentionally retained, omit its git add command. Do not push, merge, publish, sign, notarize, or release.

## Execution acceptance checklist

- [ ] Dashboard rows are the configured-order intersection with existing visibleModules; factory defaults remain CPU/RAM/AI.
- [ ] AI provider visibility/order and Fable presentation remain unchanged and contribute to natural height only when rendered.
- [ ] The panel is exactly 340 points wide.
- [ ] A tall screen uses the measured natural content height with no unnecessary body scroll; a short screen clamps to its allowance and keeps header/footer fixed.
- [ ] Invalid natural height uses the bounded 680-point fallback, minimum height is 180 points when the screen permits, and a smaller screen allowance wins.
- [ ] Initial height is measured before presentation without a visible expansion jump.
- [ ] System-module and AI-provider visibility changes resize the same panel at the same anchor; numeric-only equal-height updates do not mutate the frame.
- [ ] The visible hosting controller, scroll/disclosure state, dismissal monitor, generation, Settings/Analytics/provider actions, status provenance, IP privacy, and outside-click dismissal are preserved.
- [ ] Focused, acceptance, full, package, smoke, and diff-check gates pass.
- [ ] Native evidence and unobserved/macOS 14 limitations are recorded without synthetic evidence or private data.
- [ ] README/screenshot/STATUS are changed only after bounded native acceptance; no push, merge, or release is performed.

## Plan self-review

Spec coverage: Task 1 makes existing visibility authoritative without changing defaults. Tasks 2–3 provide the 340-point constants, finite fallback/clamping, shared non-scroll measurement tree, visible scroll tree, shared observable height state, and fitting regressions. Task 4 provides identity-preserving frame-only resize. Task 5 wires pre-presentation measurement and update-driven no-churn resize through the existing anchor/model/layout flow, including both system-module and AI-provider visibility changes. Task 6 covers reviews, complete automated gates, bounded native evidence, full preference restoration, documentation timing, privacy, and macOS 14 deferral.

Placeholder scan: the plan contains no TBD, TODO, implement-later step, unspecified error handling, or undefined production symbol. Every production type introduced in a later task is defined earlier in the plan, and every code-changing step includes the exact declaration or replacement body.

Type consistency: SystemDashboardPanelSizing returns CGFloat, SystemDashboardPopoverMeasurement returns CGFloat?, SystemDashboardPopoverLayout owns a published CGFloat height, SystemDashboardPopoverView accepts either an exact public CGFloat or the controller's shared layout object, MenuPanelPresenting.resize accepts NSSize plus StatusItemPresentationAnchor, and all relevant layout/controller/presenter code runs on MainActor.
