# API Billing Links Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Add opt-in Claude API and OpenAI API billing-page links to visible matching dashboard rows, with no billing-data retrieval or behavior change elsewhere.

**Architecture:** NeedlbarCore persists a strict false-by-default Boolean with each system-monitor provider preference. The App target maps only Claude and Codex to fixed URLs and opens them through an injected AppKit router. Settings controls the preference only; dashboard visibility gates rendering and view-local state keeps failure/retry measurable.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI, AppKit/NSWorkspace, UserDefaults, make swift-test, make test.

---

## File Map

- Modify: Sources/NeedlbarCore/SystemMetrics/SystemMetricModels.swift; Sources/NeedlbarCore/Configuration/ModuleConfiguration.swift; Tests/NeedlbarCoreTests/ModuleConfigurationTests.swift — persistence.
- Create: Sources/Needlbar/Provider/APIBillingAction.swift; Tests/NeedlbarTests/APIBillingActionTests.swift — fixed action/router.
- Modify: Sources/Needlbar/Settings/SystemMonitorSettingsModel.swift; Sources/Needlbar/Settings/SettingsView.swift; Tests/NeedlbarTests/SettingsStudioTests.swift — Settings control only.
- Modify: Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift; SystemDashboardPopoverView.swift; SystemDashboardPopoverSizing.swift; Sources/Needlbar/MenuBar/MenuBarController.swift; Tests/NeedlbarTests/SystemDashboardPopoverTests.swift; MenuBarControllerTests.swift — gated action/failure/measurement/routing.
- Modify only after full verification: docs/STATUS.md.

### Task 1: Persist the strict opt-in

**Files:**
- Modify: Sources/NeedlbarCore/SystemMetrics/SystemMetricModels.swift:41-82
- Modify: Sources/NeedlbarCore/Configuration/ModuleConfiguration.swift:57-115,145-162
- Test: Tests/NeedlbarCoreTests/ModuleConfigurationTests.swift

- [x] **Step 1: Write the failing persistence test.**

~~~swift
@Test func apiBillingPreferencesAreStrictAndIndependent() {
    let defaults = freshMonitorConfigurationDefaults()
    let configuration = ModuleConfiguration(defaults: defaults)
    #expect(configuration.systemMonitor.ai[.claude]?.apiBillingLinkVisible == false)
    #expect(configuration.systemMonitor.ai[.codex]?.apiBillingLinkVisible == false)
    defaults.set("true", forKey: "needlbar.systemMonitor.ai.claude.apiBillingLink.visible")
    defaults.set(1, forKey: "needlbar.systemMonitor.ai.codex.apiBillingLink.visible")
    #expect(configuration.systemMonitor.ai[.claude]?.apiBillingLinkVisible == false)
    #expect(configuration.systemMonitor.ai[.codex]?.apiBillingLinkVisible == false)
    configuration.setAPIBillingLinkVisible(true, for: .claude)
    configuration.setAPIBillingLinkVisible(true, for: .codex)
    #expect(ModuleConfiguration(defaults: defaults).systemMonitor.ai[.claude]?.apiBillingLinkVisible == true)
    #expect(ModuleConfiguration(defaults: defaults).systemMonitor.ai[.codex]?.apiBillingLinkVisible == true)
    configuration.setAPIBillingLinkVisible(false, for: .claude)
    #expect(ModuleConfiguration(defaults: defaults).systemMonitor.ai[.claude]?.apiBillingLinkVisible == false)
    #expect(configuration.systemMonitor.ai[.cursor]?.apiBillingLinkVisible == false)
    let malformed = try! JSONDecoder().decode(
        AIProviderDisplayPreference.self, from: Data(#"{"apiBillingLinkVisible":"true"}"#.utf8))
    #expect(malformed.apiBillingLinkVisible == false)
}
~~~

- [x] **Step 2: Run RED.**

Run: make swift-test SWIFT_TEST_FILTER='apiBillingPreferencesAreStrictAndIndependent'

Expected: FAIL because the field and setter do not exist.

- [x] **Step 3: Implement the narrow Core contract.**

Add apiBillingLinkVisible: Bool = false to AIProviderDisplayPreference and its initializer/Codable implementation. Decode it with `(try? container.decode(Bool.self, forKey: .apiBillingLinkVisible)) ?? false`, so missing and malformed Codable data are false. In ModuleConfiguration.systemMonitor, read strictBool for needlbar.systemMonitor.ai.<provider>.apiBillingLink.visible only for Claude/Codex; Cursor is always false. Persist only those provider fields in setSystemMonitor(_:). Add:

~~~swift
public func setAPIBillingLinkVisible(_ visible: Bool, for provider: ProviderID) {
    guard provider == .claude || provider == .codex else { return }
    defaults.set(visible, forKey: "needlbar.systemMonitor.ai.\(provider.rawValue).apiBillingLink.visible")
    NotificationCenter.default.post(name: Self.systemMonitorDidChangeNotification, object: self)
    NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
}
~~~

Reads do not write defaults, migrate keys, or refresh data.

- [x] **Step 4: Run GREEN and commit.**

Run: make swift-test SWIFT_TEST_FILTER='ModuleConfiguration\|apiBilling'

Expected: PASS; only real Booleans enable Claude/Codex.

~~~bash
git add Sources/NeedlbarCore/SystemMetrics/SystemMetricModels.swift Sources/NeedlbarCore/Configuration/ModuleConfiguration.swift Tests/NeedlbarCoreTests/ModuleConfigurationTests.swift
git commit -m "feat: persist API billing link preferences"
~~~

### Task 2: Add the closed fixed-URL browser router

**Files:**
- Create: Sources/Needlbar/Provider/APIBillingAction.swift
- Test: Tests/NeedlbarTests/APIBillingActionTests.swift

- [x] **Step 1: Write the failing router contract.**

~~~swift
@Test func apiBillingActionsUseExactLabelsURLsAndOneInjectedOpen() throws {
    let claude = try #require(ProviderAPIBillingAction(provider: .claude))
    let codex = try #require(ProviderAPIBillingAction(provider: .codex))
    #expect(claude.providerLabel == "Claude API")
    #expect(claude.destination == URL(string: "https://platform.claude.com/settings/billing")!)
    #expect(codex.providerLabel == "OpenAI API")
    #expect(codex.destination == URL(string: "https://platform.openai.com/settings/organization/billing/overview")!)
    #expect(ProviderAPIBillingAction(provider: .cursor) == nil)
    var opened: [URL] = []
    #expect(ProviderAPIBillingActionRouter.open(codex) { opened.append($0); return false } == false)
    #expect(opened == [codex.destination])
}
~~~

- [x] **Step 2: Run RED.**

Run: make swift-test SWIFT_TEST_FILTER='apiBillingActionsUseExactLabelsURLsAndOneInjectedOpen'

Expected: FAIL because the action/router is absent.

- [x] **Step 3: Implement the closed mapping.**

~~~swift
enum ProviderAPIBillingAction: Equatable, Sendable {
    case claude, codex
    init?(provider: ProviderID) {
        switch provider { case .claude: self = .claude; case .codex: self = .codex; case .cursor: return nil }
    }
    var provider: ProviderID { switch self { case .claude: .claude; case .codex: .codex } }
    var providerLabel: String { switch self { case .claude: "Claude API"; case .codex: "OpenAI API" } }
    var destination: URL { switch self {
    case .claude: URL(string: "https://platform.claude.com/settings/billing")!
    case .codex: URL(string: "https://platform.openai.com/settings/organization/billing/overview")! } }
}
@MainActor enum ProviderAPIBillingActionRouter {
    @discardableResult static func open(_ action: ProviderAPIBillingAction,
        using opener: (URL) -> Bool = NSWorkspace.shared.open) -> Bool { opener(action.destination) }
}
~~~

Import AppKit and NeedlbarCore only. No URL input, network, task, account, or credential access.

- [x] **Step 4: Run GREEN and commit.**

Run: make swift-test SWIFT_TEST_FILTER='APIBillingAction'

Expected: PASS.

~~~bash
git add Sources/Needlbar/Provider/APIBillingAction.swift Tests/NeedlbarTests/APIBillingActionTests.swift
git commit -m "feat: add fixed API billing browser actions"
~~~

### Task 3: Add the Settings control, not a Settings action

**Files:**
- Modify: Sources/Needlbar/Settings/SystemMonitorSettingsModel.swift:83-127
- Modify: Sources/Needlbar/Settings/SettingsView.swift:105-132
- Test: Tests/NeedlbarTests/SettingsStudioTests.swift

- [x] **Step 1: Write the failing Settings-model test.**

~~~swift
@Test func apiBillingSettingsToggleDoesNotMakeProviderVisible() throws {
    let name = "SettingsStudio.api.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let store = ModuleConfiguration(defaults: defaults)
    var value = store.systemMonitor
    value.ai[.claude] = AIProviderDisplayPreference(isVisible: false, metric: .usage, dashboardVisible: false)
    store.setSystemMonitor(value)
    let model = SystemMonitorSettingsModel(configuration: store)
    model.setAPIBillingLinkVisible(true, for: .claude)
    #expect(store.systemMonitor.ai[.claude]?.apiBillingLinkVisible == true)
    #expect(!model.isVisible(.claude, surface: .menuBar))
    #expect(!model.isVisible(.claude, surface: .dashboard))
    #expect(store.systemMonitor.ai[.claude]?.metric == .usage)
    model.setAPIBillingLinkVisible(false, for: .claude)
    #expect(store.systemMonitor.ai[.claude]?.apiBillingLinkVisible == false)
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Needlbar/Settings/SettingsView.swift"), encoding: .utf8)
    #expect(source.contains("SettingsStudioSection(title: \"API Billing\")"))
    #expect(source.contains("Show API billing link"))
    #expect(!source.contains("ProviderAPIBillingActionRouter.open"))
}
~~~

- [x] **Step 2: Run RED.**

Run: make swift-test SWIFT_TEST_FILTER='apiBillingSettingsToggleDoesNotMakeProviderVisible'

Expected: FAIL because the setter is absent.

- [x] **Step 3: Implement the control-only pane.**

~~~swift
public func setAPIBillingLinkVisible(_ visible: Bool, for provider: ProviderID) {
    configuration.setAPIBillingLinkVisible(visible, for: provider)
    value = configuration.systemMonitor
}
~~~

Call apiBillingPane(provider) immediately after connectionPane(provider). It renders only when ProviderAPIBillingAction(provider:) succeeds:

~~~swift
SettingsStudioSection(title: "API Billing") {
    SettingsStudioToggle(title: "Show API billing link", value: Binding(
        get: { systemMonitorModel.value.ai[provider]?.apiBillingLinkVisible ?? false },
        set: { systemMonitorModel.setAPIBillingLinkVisible($0, for: provider) }))
    Divider()
    Text("\(action.providerLabel) · \(action.destination.absoluteString)")
        .font(.caption).foregroundStyle(.secondary).padding(.vertical, 12)
}
~~~

Cursor gets no section. Do not add a Button/router call or alter login, visibility, metric, or ordering.

- [x] **Step 4: Run GREEN and commit.**

Run: make swift-test SWIFT_TEST_FILTER='SettingsStudio\|apiBillingSettingsToggle'

Expected: PASS.

~~~bash
git add Sources/Needlbar/Settings/SystemMonitorSettingsModel.swift Sources/Needlbar/Settings/SettingsView.swift Tests/NeedlbarTests/SettingsStudioTests.swift
git commit -m "feat: add API billing link settings"
~~~

### Task 4: Render, measure, and retry the dashboard action

**Files:**
- Modify: Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift:130-138,204-218
- Modify: Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift:16-95,240-352
- Modify: Sources/Needlbar/Modules/Overview/SystemDashboardPopoverSizing.swift:49-59
- Modify: Sources/Needlbar/MenuBar/MenuBarController.swift:430-506,671-710,794-815
- Test: Tests/NeedlbarTests/SystemDashboardPopoverTests.swift; Tests/NeedlbarTests/MenuBarControllerTests.swift

- [x] **Step 1: Write failing dashboard and route tests.**

~~~swift
@Test @MainActor func dashboardBillingLinkIsVisibleOnlyWhenOptedInAndMeasured() throws {
    var configuration = SystemMonitorConfiguration()
    configuration.ai[.claude]?.apiBillingLinkVisible = true
    let model = SystemDashboardModel(snapshot: dashboardFixtureSnapshot(), configuration: configuration)
    #expect(model.presentation.ai.first { $0.provider == .claude }?.apiBillingAction == .claude)
    #expect(SystemDashboardPresentation(snapshot: dashboardFixtureSnapshot(), configuration: .init()).ai.first { $0.provider == .claude }?.apiBillingAction == nil)
    let rowHeight = try #require(SystemDashboardPopoverMeasurement.naturalHeight(for: model))
    var state = DashboardAPIBillingLinkState(); state.recordOpenResult(false, for: .claude)
    #expect(try #require(SystemDashboardPopoverMeasurement.naturalHeight(for: model, billingState: state)) > rowHeight)
    configuration.ai[.claude]?.apiBillingLinkVisible = false
    #expect(SystemDashboardPresentation(snapshot: dashboardFixtureSnapshot(), configuration: configuration).ai.first { $0.provider == .claude }?.apiBillingAction == nil)
    configuration.ai[.claude]?.dashboardVisible = false
    #expect(SystemDashboardPresentation(snapshot: dashboardFixtureSnapshot(), configuration: configuration).ai.contains { $0.provider == .claude } == false)
}
@Test func billingFailureClearsOnlyAfterSuccess() {
    var state = DashboardAPIBillingLinkState(); state.recordOpenResult(false, for: .claude)
    #expect(state.showsFailure(for: .claude))
    #expect(state.failureMessage == "Couldn't open billing page. Try again.")
    state.recordOpenResult(true, for: .claude); #expect(!state.showsFailure(for: .claude))
}
~~~

Add this MenuBarController test, and extend its existing makeMenuBarController helper with an openAPIBilling parameter that forwards to the initializer:

~~~swift
@MainActor @Test func apiBillingActionKeepsPanelOpenWithoutLoginOrRefresh() {
    let presenter = FakeMenuPanelPresenter(); var opened: [URL] = []; var logins = 0
    let controller = makeMenuBarController(
        configuration: ModuleConfiguration(defaults: freshMenuBarDefaults()), snapshotStore: ProviderSnapshotStore(),
        loginCoordinator: testLoginCoordinator(), panelPresenter: presenter,
        onProviderLoginRequested: { _ in logins += 1 },
        openAPIBilling: { opened.append($0.destination); return true })
    presenter.markShownForTesting()
    #expect(controller.performAPIBillingAction(.claude))
    #expect(presenter.isShown); #expect(logins == 0)
    #expect(opened == [URL(string: "https://platform.claude.com/settings/billing")!])
}
~~~

- [x] **Step 2: Run RED.**

Run: make swift-test SWIFT_TEST_FILTER='dashboardBillingLinkIsVisibleOnlyWhenOptedInAndMeasured\|billingFailureClearsOnlyAfterSuccess\|apiBilling'

Expected: FAIL because action projection/state/measurement/controller route are absent.

- [x] **Step 3: Implement the minimal dashboard contract.**

Add apiBillingAction: ProviderAPIBillingAction? to AIProvider; calculate preference.apiBillingLinkVisible ? ProviderAPIBillingAction(provider: provider) : nil, separate from existing authentication action. Add view-local state:

~~~swift
struct DashboardAPIBillingLinkState: Equatable {
    private var failed: Set<ProviderID> = []
    static let failureMessage = "Couldn't open billing page. Try again."
    mutating func recordOpenResult(_ opened: Bool, for provider: ProviderID) {
        if opened { failed.remove(provider) } else { failed.insert(provider) }
    }
    func showsFailure(for provider: ProviderID) -> Bool { failed.contains(provider) }
    var failureMessage: String { Self.failureMessage }
}
~~~

Inject onAPIBillingAction: (ProviderAPIBillingAction) -> Bool and onAPIBillingStateChanged: (DashboardAPIBillingLinkState) -> Void into the existing dashboard view. Store the state as @State, and make both Check balance and Retry call this exact helper so a real click changes the visible view before requesting its new measured height:

~~~swift
private func performAPIBillingAction(_ action: ProviderAPIBillingAction) {
    billingState.recordOpenResult(onAPIBillingAction(action), for: action.provider)
    onAPIBillingStateChanged(billingState)
}
~~~

For each action, render providerLabel, borderless Check balance with accessibility label Check balance in <label>, and on failure the exact accessible message plus Retry labelled Retry opening <label> billing page. Extend only the measuring initializer and naturalHeight(for:billingState:) so failure text contributes fittingSize. MenuBarController stores the displayed billing state, resets it when presenting/dismissing, and on onAPIBillingStateChanged updates that stored value then calls resizeDisplayedDashboardIfNeeded(); that method measures naturalHeight(for: model, billingState: displayedBillingState). Add a controller test that opens an opted-in dashboard, routes false, then true, and asserts FakeMenuPanelPresenter.resizedSizes first grows and then returns to the original height. This proves the native visible-state path, not merely an isolated measurement overload.

Inject openAPIBilling: (ProviderAPIBillingAction) -> Bool = { ProviderAPIBillingActionRouter.open($0) } into both current and retained Legacy MenuBarController initializers; forward it only to the dashboard and implement `func performAPIBillingAction(_ action: ProviderAPIBillingAction) -> Bool { openAPIBilling(action) }`. Never dismiss the panel or invoke login, retry/refresh, Cursor Spending, repository, widget, Analytics, Rust/C ABI, network, or auth flow.

- [x] **Step 4: Run GREEN and commit.**

Run: make swift-test SWIFT_TEST_FILTER='SystemDashboardPopover\|dashboardBilling\|MenuBarController\|apiBilling\|authenticationActionsRouteClaudeAndCodex\|cursorSpendingAction'

Expected: PASS; hidden providers have no row; failed opening retains accessible measured retry; existing action routes are unchanged.

~~~bash
git add Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift Sources/Needlbar/Modules/Overview/SystemDashboardPopoverSizing.swift Sources/Needlbar/MenuBar/MenuBarController.swift Tests/NeedlbarTests/SystemDashboardPopoverTests.swift Tests/NeedlbarTests/MenuBarControllerTests.swift
git commit -m "feat: show opt-in API billing links on dashboard"
~~~

### Task 5: Verify unchanged surfaces and record scope

**Files:**
- Verify: Task 1-4 files
- Modify after success: docs/STATUS.md

- [x] **Step 1: Run focused regressions.**

Run: make swift-test SWIFT_TEST_FILTER='ModuleConfiguration\|APIBilling\|SettingsStudio\|SystemDashboardPopover\|MenuBarController\|ProviderLoginCoordinator\|RefreshCoordinator\|AnalyticsPresentation\|WidgetProjection\|MenuBarDashboardRenderer'

Expected: PASS; subscription quota/sign-in, Cursor Spending, usage/cost, refresh, menu-bar text, widget, and Analytics behavior remain unchanged.

- [x] **Step 2: Run the implementation gate.**

~~~bash
make test
git diff --check
git status --short
~~~

Expected: make test and git diff --check exit 0; no Rust, C ABI, quota, usage, widget, Analytics, or auth/network source change belongs to this increment.

- [x] **Step 3: Record verified facts and commit.**

After the commands pass, append beneath the existing API Billing Links section in docs/STATUS.md:

~~~markdown
Implementation verification: the opt-in Claude API and OpenAI API billing links are false by default, shown only for their visible dashboard provider rows, and open fixed official HTTPS URLs only after an explicit click. Failure retains an accessible retry and participates in dashboard height measurement. Focused Swift coverage and make test passed. No balance/account lookup, credential access, background work, quota/usage/estimated-cost behavior, Cursor behavior, menu-bar action, widget, Analytics, Rust bridge, or refresh behavior changed.
~~~

~~~bash
git add docs/STATUS.md
git commit -m "docs: record API billing link verification"
~~~
