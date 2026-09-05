# Settings Module Studio Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship native Module Studio Settings with independent menu-bar/dashboard visibility, preserved user preferences, and working existing provider, privacy, export, and notification controls.

**Architecture:** Keep canonical visibility in NeedlbarCore and mutate it through the existing configuration notification path. Separate Settings navigation, reusable rows, configuration editing, and read-only renderer previews; AppKit retains window ownership. Do not add collection, provider-refresh, or preview timers.

**Tech Stack:** Swift 6, macOS 14 deployment target, SwiftUI/AppKit, Combine, UserDefaults, Swift Testing, existing Rust bridge test-runtime build wrapper.

---

## Authority, scope, and execution rules

- Approved spec: `docs/superpowers/specs/2026-09-05-settings-module-studio-design.md`.
- Approved visual reference: `docs/superpowers/mockups/2026-09-05-settings-module-studio.html`.
- Phase 1 does **not** implement graph/bar/ring choices, units, volume/interface selection, per-module sampling, or system alerts. Those remain subsequent feature stages, not canceled requirements. Never ship their mock controls or sample values.
- Read `AGENTS.md` and the current `docs/STATUS.md` before execution. Use the worktree skill at execution time; preserve the dirty main-checkout submodule and unrelated files.
- Suggested isolated branch: `codex/settings-module-studio`; suggested worktree: `.worktrees/settings-module-studio`. Resolve collisions before creating either. Initialize submodules only inside the new worktree; never reset the user's current vendor checkout.
- Baseline: `make test` in that worktree. Record actual exit status before Task 1; a missing toolchain/dependency is not a product-test failure and must not be disguised as RED.
- Run one numbered task at a time. Do not run parallel SwiftPM/Make invocations in the same worktree.
- The code blocks below are planned edits, **not executed or compiled evidence**. Preserve surrounding unchanged implementations where a block replaces a named member rather than a whole file.
- Use `make swift-test SWIFT_TEST_FILTER=SettingsStudio` for new tests: put them inside suites whose names start with `SettingsStudio`. This wrapper installs and restores bridge-test-runtime. Do not substitute a bare `swift test` for full app tests.
- After each task's focused GREEN run, run `make test` before its implementation commit. Do not change the pinned vendor revision to obtain GREEN.
- Every task commit stages only its listed implementation/test files. No push, install, sign, notarize, or release is authorized by this plan.

## File map and responsibility

| File | Responsibility |
| --- | --- |
| `Sources/NeedlbarCore/SystemMetrics/SystemMetricModels.swift` | two-surface value model and source-compatible shared initializers |
| `Sources/NeedlbarCore/Configuration/ModuleConfiguration.swift` | lazy UserDefaults migration; canonical writes |
| `Sources/Needlbar/MenuBar/MenuBarDashboardRenderer.swift` | menu-only visibility filtering in both text and segment paths |
| `Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift` | dashboard-only module/provider filtering |
| `Sources/Needlbar/Settings/SystemMonitorSettingsModel.swift` (new) | extract existing configuration editor; explicit surface setters |
| `Sources/Needlbar/Settings/SystemMonitorSettingsView.swift` | remove extracted model; retain legacy view until shell replacement |
| `Sources/Needlbar/Settings/SettingsStudioNavigation.swift` (new) | page/tab identity, labels, safe surface routing |
| `Sources/Needlbar/Settings/SettingsStudioComponents.swift` (new) | sidebar, grouped rows, appearance/accessibility constants |
| `Sources/Needlbar/Settings/SettingsStudioConfigurationPane.swift` (new) | module/provider visibility, ordering, shared metric and IP rows |
| `Sources/Needlbar/Settings/SettingsPreviewModel.swift` (new) | passive renderer-result delivery; no store or timer |
| `Sources/Needlbar/Settings/SettingsPreviewView.swift` (new) | existing two-line layout/image renderer reuse |
| `Sources/Needlbar/Settings/SettingsView.swift` | selected pane composition; retain existing action helpers |
| `Sources/Needlbar/Settings/SettingsWindowController.swift` | resizable screen-clamped window and preview delivery |
| `Sources/Needlbar/MenuBar/MenuBarController.swift` | deliver current combined snapshot to Settings during existing reconciliation |
| `Tests/NeedlbarCoreTests/SettingsStudioConfigurationTests.swift` (new) | migration/value tests |
| `Tests/NeedlbarTests/SettingsStudioTests.swift` (new) | editor, navigation, renderer, preview, window and integration tests |
| `docs/STATUS.md` | actual results, limitations, exact continuation point |

No Rust, C ABI, collector, notification-ledger, or export-schema change belongs in these tasks.

## Task 1: Define two-surface values and migrate stored visibility

**Files:** Modify both Core files in the map; create `Tests/NeedlbarCoreTests/SettingsStudioConfigurationTests.swift`.

- [ ] **1. Add failing migration tests.** Use an isolated suite and remove only that generated domain.

```swift
import Foundation
import Testing
@testable import NeedlbarCore

@Suite("SettingsStudioConfiguration")
struct SettingsStudioConfigurationTests {
    @Test func legacyReadIsLazyAndWritesPreserveLegacy() {
        let name = "SettingsStudio.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["cpu", "ai"], forKey: "needlbar.systemMonitor.visible")
        defaults.set(false, forKey: "needlbar.systemMonitor.ai.claude.visible")
        let before = defaults.persistentDomain(forName: name)! as NSDictionary
        let store = ModuleConfiguration(defaults: defaults)
        var value = store.systemMonitor
        #expect(value.menuBarVisibleModules == [.cpu, .ai])
        #expect(value.dashboardVisibleModules == [.cpu, .ai])
        #expect(value.ai[.claude]?.dashboardVisible == false)
        #expect(before.isEqual(to: defaults.persistentDomain(forName: name)!))
        value.menuBarVisibleModules = []
        value.ai[.claude]?.menuBarVisible = true
        store.setSystemMonitor(value)
        let loaded = store.systemMonitor
        #expect(loaded.menuBarVisibleModules.isEmpty)
        #expect(loaded.dashboardVisibleModules == [.cpu, .ai])
        #expect(loaded.ai[.claude]?.menuBarVisible == true)
        #expect(loaded.ai[.claude]?.dashboardVisible == false)
        #expect(defaults.stringArray(forKey: "needlbar.systemMonitor.visible") == ["cpu", "ai"])
        #expect(defaults.object(forKey: "needlbar.systemMonitor.ai.claude.visible") as? Bool == false)
    }

    @Test func malformedAndEmptyAreDifferent() {
        let name = "SettingsStudio.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["disk"], forKey: "needlbar.systemMonitor.visible")
        defaults.set([String](), forKey: "needlbar.systemMonitor.menuBar.visible")
        defaults.set("not-an-array", forKey: "needlbar.systemMonitor.dashboard.visible")
        defaults.set(false, forKey: "needlbar.systemMonitor.ai.codex.visible")
        defaults.set("true", forKey: "needlbar.systemMonitor.ai.codex.menuBar.visible")
        let value = ModuleConfiguration(defaults: defaults).systemMonitor
        #expect(value.menuBarVisibleModules.isEmpty)
        #expect(value.dashboardVisibleModules == [.disk])
        #expect(value.ai[.codex]?.menuBarVisible == false)
    }

    @Test func valuesRoundTrip() throws {
        var value = SystemMonitorConfiguration()
        value.menuBarVisibleModules = []
        value.dashboardVisibleModules = [.network]
        value.ai[.claude]?.dashboardVisible = false
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(SystemMonitorConfiguration.self, from: data) == value)
    }
}
```

- [ ] **2. Run RED.** `make swift-test SWIFT_TEST_FILTER=SettingsStudioConfiguration`. Expected: missing new properties, not a bridge/link failure.
- [ ] **3. Add the Core surface enum and provider representation.** Replace `AIProviderDisplayPreference` with this complete declaration:

```swift
public enum MonitorDisplaySurface: String, CaseIterable, Sendable {
    case menuBar, dashboard
}

public struct AIProviderDisplayPreference: Codable, Equatable, Sendable {
    public var menuBarVisible: Bool
    public var dashboardVisible: Bool
    public var metric: AIProviderDisplayMetric

    // Compatibility API: explicit shared writes still update both surfaces.
    public var isVisible: Bool {
        get { menuBarVisible }
        set { menuBarVisible = newValue; dashboardVisible = newValue }
    }

    public init(isVisible: Bool = true, metric: AIProviderDisplayMetric = .remaining,
                dashboardVisible: Bool? = nil) {
        menuBarVisible = isVisible
        self.dashboardVisible = dashboardVisible ?? isVisible
        self.metric = metric
    }

    private enum CodingKeys: String, CodingKey {
        case menuBarVisible, dashboardVisible, isVisible, metric
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let shared = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        menuBarVisible = try c.decodeIfPresent(Bool.self, forKey: .menuBarVisible) ?? shared
        dashboardVisible = try c.decodeIfPresent(Bool.self, forKey: .dashboardVisible) ?? shared
        metric = try c.decodeIfPresent(AIProviderDisplayMetric.self, forKey: .metric) ?? .remaining
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(menuBarVisible, forKey: .menuBarVisible)
        try c.encode(dashboardVisible, forKey: .dashboardVisible)
        try c.encode(metric, forKey: .metric)
    }
}
```

In `SystemMonitorConfiguration`, replace stored `visibleModules` with the following properties. Preserve all other stored fields and the existing initializer argument order; append `dashboardVisibleModules: Set<MonitorModuleID>? = nil` to that initializer. Replace its `self.visibleModules = visibleModules` assignment with the two assignments below.

```swift
public var menuBarVisibleModules: Set<MonitorModuleID>
public var dashboardVisibleModules: Set<MonitorModuleID>
public var visibleModules: Set<MonitorModuleID> {
    get { menuBarVisibleModules }
    set { menuBarVisibleModules = newValue; dashboardVisibleModules = newValue }
}
// In existing initializer:
self.menuBarVisibleModules = visibleModules
self.dashboardVisibleModules = dashboardVisibleModules ?? visibleModules
```

Add these explicit Codable members inside that struct, preserving legacy decode and new-value round trips. They do not alter snapshot export, which does not serialize Settings configuration.

```swift
private enum CodingKeys: String, CodingKey {
    case order, visibleModules, menuBarVisibleModules, dashboardVisibleModules
    case localIPEnabled, publicIPEnabled, aiOrder, ai
}
public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let shared = try c.decodeIfPresent(Set<MonitorModuleID>.self, forKey: .visibleModules)
        ?? Set([.cpu, .memory, .ai])
    self.init(
        order: try c.decodeIfPresent([MonitorModuleID].self, forKey: .order) ?? MonitorModuleID.defaultOrder,
        visibleModules: try c.decodeIfPresent(Set<MonitorModuleID>.self, forKey: .menuBarVisibleModules) ?? shared,
        publicIPEnabled: try c.decodeIfPresent(Bool.self, forKey: .publicIPEnabled) ?? false,
        aiOrder: try c.decodeIfPresent([ProviderID].self, forKey: .aiOrder) ?? ProviderID.allCases,
        ai: try c.decodeIfPresent([ProviderID: AIProviderDisplayPreference].self, forKey: .ai)
            ?? Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, AIProviderDisplayPreference()) }),
        localIPEnabled: try c.decodeIfPresent(Bool.self, forKey: .localIPEnabled) ?? false,
        dashboardVisibleModules: try c.decodeIfPresent(Set<MonitorModuleID>.self, forKey: .dashboardVisibleModules) ?? shared
    )
}
public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(order, forKey: .order)
    try c.encode(menuBarVisibleModules, forKey: .menuBarVisibleModules)
    try c.encode(dashboardVisibleModules, forKey: .dashboardVisibleModules)
    try c.encode(localIPEnabled, forKey: .localIPEnabled)
    try c.encode(publicIPEnabled, forKey: .publicIPEnabled)
    try c.encode(aiOrder, forKey: .aiOrder)
    try c.encode(ai, forKey: .ai)
}
```

- [ ] **4. Implement lazy defaults migration.** Import CoreFoundation in `ModuleConfiguration.swift`. Add these helpers; use `strictBool` for both new and legacy provider flags. Do not use `bool(forKey:)`, which conflates missing/malformed with false.

```swift
private func strictBool(_ key: String) -> Bool? {
    guard let number = defaults.object(forKey: key) as? NSNumber,
          CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
    return number.boolValue
}
private func visibleModules(for surface: MonitorDisplaySurface) -> Set<MonitorModuleID> {
    let raw = defaults.stringArray(forKey: "needlbar.systemMonitor.\(surface.rawValue).visible")
        ?? defaults.stringArray(forKey: "needlbar.systemMonitor.visible")
    return validVisibleModules(from: raw)
}
private func providerVisible(_ provider: ProviderID, surface: MonitorDisplaySurface) -> Bool {
    let base = "needlbar.systemMonitor.ai.\(provider.rawValue)"
    return strictBool("\(base).\(surface.rawValue).visible")
        ?? strictBool("\(base).visible")
        ?? strictBool("needlbar.menuBar.\(provider.rawValue).enabled")
        ?? true
}
```

In the existing getter, set `visibleModules` from `visibleModules(for: .menuBar)` and pass `dashboardVisibleModules: visibleModules(for: .dashboard)` as the final initializer argument. Replace provider preference construction with:

```swift
let preference = AIProviderDisplayPreference(
    isVisible: providerVisible(provider, surface: .menuBar),
    metric: defaults.string(forKey: metricKey).flatMap(AIProviderDisplayMetric.init(rawValue:)) ?? .remaining,
    dashboardVisible: providerVisible(provider, surface: .dashboard)
)
```

In `setSystemMonitor`, remove writes to legacy shared visibility keys and replace just those writes with:

```swift
defaults.set(configuration.menuBarVisibleModules.map(\.rawValue).sorted(),
             forKey: "needlbar.systemMonitor.menuBar.visible")
defaults.set(configuration.dashboardVisibleModules.map(\.rawValue).sorted(),
             forKey: "needlbar.systemMonitor.dashboard.visible")
// Inside the existing provider loop:
defaults.set(preference.menuBarVisible,
             forKey: "needlbar.systemMonitor.ai.\(provider.rawValue).menuBar.visible")
defaults.set(preference.dashboardVisible,
             forKey: "needlbar.systemMonitor.ai.\(provider.rawValue).dashboard.visible")
```

Preserve order, metric, IP writes and both existing notifications. Remove the now-unused shared-visible local and `migratedAIVisibility` helper after callers are gone. No new notification is posted by the getter.

- [ ] **5. Extend the malformed-value test with numeric provider values `0`, `1`, string `"false"`, and absent keys; verify they fall through to a valid false legacy flag. Add fresh-default and legacy JSON-decode checks in the same suite.** Use this legacy decode assertion:

```swift
// Standalone provider and configuration fixtures preserve their legacy shapes.
let provider = try JSONDecoder().decode(AIProviderDisplayPreference.self,
    from: Data(#"{"isVisible":false,"metric":"remaining"}"#.utf8))
#expect(!provider.menuBarVisible && !provider.dashboardVisible)
let configuration = try JSONDecoder().decode(SystemMonitorConfiguration.self,
    from: Data(#"{"visibleModules":["network"]}"#.utf8))
#expect(configuration.menuBarVisibleModules == [.network])
#expect(configuration.dashboardVisibleModules == [.network])
```

Run these throwing assertions inside a throwing `@Test` method in the same suite.

- [ ] **6. Run GREEN and commit.** `make swift-test SWIFT_TEST_FILTER=SettingsStudioConfiguration`, then `make test`. Stage the two Core files and the new Core test; commit `feat: split monitor visibility with lazy preferences migration`.

## Task 2: Route each renderer to its own visibility

**Files:** Modify `MenuBarDashboardRenderer.swift`, `SystemDashboardModel.swift`; create `Tests/NeedlbarTests/SettingsStudioTests.swift`.

- [ ] **1. Add this failing cross-surface test.** It deliberately uses unavailable data; no fixture file or provider access is needed.

```swift
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

@Suite("SettingsStudio", .serialized)
@MainActor
struct SettingsStudioTests {
    static var emptySnapshot: CombinedUsageSnapshot {
        .init(system: nil, providers: [], capturedAt: .distantPast, systemAvailability: [:])
    }
    @Test func consumersUseDifferentSurfaces() {
        var c = SystemMonitorConfiguration()
        c.menuBarVisibleModules = [.cpu, .ai]
        c.dashboardVisibleModules = [.memory, .ai]
        c.ai[.claude]?.menuBarVisible = false
        c.ai[.claude]?.dashboardVisible = true
        c.ai[.codex]?.dashboardVisible = false
        c.ai[.cursor]?.dashboardVisible = false
        let menu = MenuBarDashboardRenderer.render(snapshot: Self.emptySnapshot, configuration: c, availableWidth: 240)
        let dashboard = SystemDashboardPresentation(snapshot: Self.emptySnapshot, configuration: c)
        #expect(menu.configuredModuleIDs == [.cpu, .ai])
        #expect(!menu.tooltip.contains("Claude"))
        #expect(dashboard.moduleIDs == [.memory, .ai])
        #expect(dashboard.ai.map(\.provider) == [.claude])
        c.menuBarVisibleModules = []
        #expect(MenuBarDashboardRenderer.render(snapshot: Self.emptySnapshot, configuration: c,
            availableWidth: 240).usesIconFallback)
        #expect(SystemDashboardPresentation(snapshot: Self.emptySnapshot, configuration: c).moduleIDs == [.memory, .ai])
    }
}
```

- [ ] **2. Run RED:** `make swift-test SWIFT_TEST_FILTER=SettingsStudio`. Expected: dashboard still follows the menu/shared compatibility value.
- [ ] **3. Apply these exact expression substitutions in the named consumers only.** Do not globally replace compatibility APIs in tests or other code.

```swift
// MenuBarDashboardRenderer: orderedVisibleModules
configuration.menuBarVisibleModules.contains($0) && seen.insert($0).inserted
// MenuBarDashboardRenderer: BOTH provider filters (segment and renderAI)
configuration.ai[$0]?.menuBarVisible ?? true
// SystemDashboardPresentation.init: provider inclusion
guard preference.dashboardVisible else { return nil }
// SystemDashboardPresentation.init: final module filter
moduleIDs = validOrder.filter(configuration.dashboardVisibleModules.contains)
```

- [ ] **4. Run GREEN and existing suites:** `make swift-test SWIFT_TEST_FILTER=SettingsStudio`, `make swift-test SWIFT_TEST_FILTER=renderer`, `make swift-test SWIFT_TEST_FILTER=dashboard`, serially. Verify the current empty-AI message, Fable rows, unavailable quota, shared order and compact menu overflow remain unchanged. Then `make test`.
- [ ] **5. Commit only the two consumers and new app test:** `fix: respect independent menu and dashboard visibility`.

## Task 3: Extract the Settings editor and make every edit surface-explicit

**Files:** Create `SystemMonitorSettingsModel.swift`; modify `SystemMonitorSettingsView.swift`; extend `SettingsStudioTests.swift`.

- [ ] **1. Write the failing editor test inside `SettingsStudioTests`.**

```swift
@Test func editorDoesNotCrossSurfaces() {
    let name = "SettingsStudio.editor.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let store = ModuleConfiguration(defaults: defaults)
    var initial = SystemMonitorConfiguration(visibleModules: Set(MonitorModuleID.allCases))
    initial.publicIPEnabled = true
    store.setSystemMonitor(initial)
    let model = SystemMonitorSettingsModel(configuration: store)
    model.setVisible(.cpu, false, surface: .menuBar)
    model.setAIProvider(.claude, visible: false, surface: .dashboard)
    model.setAIProvider(.claude, metric: .cost)
    model.useCompactDefaults(surface: .dashboard)
    let value = store.systemMonitor
    #expect(!value.menuBarVisibleModules.contains(.cpu))
    #expect(value.dashboardVisibleModules == [.cpu, .memory, .ai])
    #expect(value.ai[.claude]?.menuBarVisible == true)
    #expect(value.ai[.claude]?.dashboardVisible == false)
    #expect(value.ai[.claude]?.metric == .cost)
    #expect(value.publicIPEnabled)
}
```

- [ ] **2. Run RED:** `make swift-test SWIFT_TEST_FILTER=SettingsStudio` (missing surface arguments).
- [ ] **3. Move the existing model declaration unchanged into its own file with Combine, NeedlbarCore and SwiftUI imports.** Replace just the setters below; preserve reorder, IP, refresh, and commit methods. Default `.menuBar` arguments retain old call-site compilation until Task 5 removes the legacy view.

```swift
public func setVisible(_ module: MonitorModuleID, _ visible: Bool,
                       surface: MonitorDisplaySurface = .menuBar) {
    var next = value
    var set = surface == .menuBar ? next.menuBarVisibleModules : next.dashboardVisibleModules
    if visible { set.insert(module) } else { set.remove(module) }
    if surface == .menuBar { next.menuBarVisibleModules = set }
    else { next.dashboardVisibleModules = set }
    commit(next)
}
public func useCompactDefaults(surface: MonitorDisplaySurface = .menuBar) {
    var next = value
    if surface == .menuBar { next.menuBarVisibleModules = [.cpu, .memory, .ai] }
    else { next.dashboardVisibleModules = [.cpu, .memory, .ai] }
    commit(next)
}
public func setAIProvider(_ provider: ProviderID, visible: Bool? = nil,
                          metric: AIProviderDisplayMetric? = nil,
                          surface: MonitorDisplaySurface = .menuBar) {
    var next = value
    var preference = next.ai[provider] ?? AIProviderDisplayPreference()
    if let visible {
        if surface == .menuBar { preference.menuBarVisible = visible }
        else { preference.dashboardVisible = visible }
    }
    if let metric { preference.metric = metric }
    next.ai[provider] = preference
    commit(next)
}
public func isVisible(_ module: MonitorModuleID, surface: MonitorDisplaySurface) -> Bool {
    (surface == .menuBar ? value.menuBarVisibleModules : value.dashboardVisibleModules).contains(module)
}
public func isVisible(_ provider: ProviderID, surface: MonitorDisplaySurface) -> Bool {
    let preference = value.ai[provider] ?? AIProviderDisplayPreference()
    return surface == .menuBar ? preference.menuBarVisible : preference.dashboardVisible
}
```

Update the temporary legacy button to `Button("Use compact defaults") { model.useCompactDefaults() }`; a method with a default argument is not a zero-argument function reference. The legacy view will be retired in Task 5.

- [ ] **4. Run GREEN:** new suite plus `make swift-test SWIFT_TEST_FILTER=Settings` and `make test`. Existing model tests still test menu defaults and shared metrics; add the explicit dashboard assertion above rather than weakening them.
- [ ] **5. Commit editor extraction, legacy button adjustment, and tests:** `refactor: isolate surface-aware settings editing`.

## Task 4: Define native navigation, sections, and real configuration controls

**Files:** Create `SettingsStudioNavigation.swift`, `SettingsStudioComponents.swift`, `SettingsStudioConfigurationPane.swift`; extend `SettingsStudioTests.swift`.

- [ ] **1. Add a failing tab-policy test.**

```swift
@Test func tabsCannotRouteAlertsIntoVisibility() {
    #expect(SettingsStudioTab.alerts.surface == nil)
    #expect(SettingsStudioPage.layout.tabs == [.menuBar, .dashboard])
    #expect(SettingsStudioPage.notifications.tabs.isEmpty)
    #expect(SettingsStudioPage.data.tabs.isEmpty)
    #expect(SettingsStudioPage.module(.cpu).tabs == [.menuBar, .dashboard, .alerts])
}
```

- [ ] **2. Run RED.** `make swift-test SWIFT_TEST_FILTER=SettingsStudio`.
- [ ] **3. Add the navigation definitions.** Move the existing `MonitorModuleID.title/systemImage` and `AIProviderDisplayMetric.title` extensions from the old view into this file, removing `private` so all Settings components can use them. Their switch bodies remain unchanged.

```swift
import NeedlbarCore
import SwiftUI

enum SettingsStudioTab: String, CaseIterable, Identifiable {
    case menuBar = "Menu bar", dashboard = "Dashboard", alerts = "Alerts"
    var id: Self { self }
    var surface: MonitorDisplaySurface? {
        switch self { case .menuBar: .menuBar; case .dashboard: .dashboard; case .alerts: nil }
    }
}
enum SettingsStudioPage: Hashable {
    case layout, module(MonitorModuleID), provider(ProviderID), notifications, data
    var title: String {
        switch self {
        case .layout: "Menu bar & dashboard"
        case let .module(id): id.title
        case let .provider(id): id.displayName
        case .notifications: "Notifications"
        case .data: "Data & Privacy"
        }
    }
    var tabs: [SettingsStudioTab] {
        switch self {
        case .layout: [.menuBar, .dashboard]
        case .module, .provider: SettingsStudioTab.allCases
        case .notifications, .data: []
        }
    }
}
```

Add these reusable components. Native grouped material and foreground styles must adapt to light/dark appearance; do not hard-code mockup colors or badges.

```swift
import NeedlbarCore
import SwiftUI

struct SettingsStudioSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 0, content: content)
                .padding(.horizontal, 16)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
struct SettingsStudioToggle: View {
    let title: String
    @Binding var value: Bool
    var body: some View {
        Toggle(title, isOn: $value).toggleStyle(.switch)
            .font(.system(size: 17)).frame(minHeight: 54)
            .accessibilityLabel(title)
    }
}
struct SettingsStudioSidebar: View {
    @Binding var selection: SettingsStudioPage
    private func item(_ page: SettingsStudioPage, icon: String) -> some View {
        Button { selection = page } label: {
            HStack(spacing: 10) {
                if case let .provider(provider) = page {
                    ProviderBrandIcon(provider: provider, accessibility: .decorative)
                } else { Image(systemName: icon).frame(width: 20) }
                Text(page.title).font(.system(size: 15, weight: selection == page ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .padding(10).contentShape(Rectangle())
            .background(selection == page ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 7))
            .foregroundStyle(selection == page ? Color.white : Color.primary)
        }.buttonStyle(.plain)
         .accessibilityAddTraits(selection == page ? .isSelected : [])
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Needlbar").font(.title2.bold()).padding(.vertical, 18)
                item(.layout, icon: "rectangle.3.group")
                Text("SYSTEM").font(.caption).foregroundStyle(.secondary).padding(.top, 16)
                ForEach(MonitorModuleID.allCases.filter { $0 != .ai }, id: \.self) {
                    item(.module($0), icon: $0.systemImage)
                }
                Text("AI PROVIDERS").font(.caption).foregroundStyle(.secondary).padding(.top, 16)
                ForEach(ProviderID.allCases, id: \.self) { item(.provider($0), icon: "") }
                Divider().padding(.vertical, 12)
                item(.notifications, icon: "bell")
                item(.data, icon: "lock.shield")
            }.padding(12)
        }.frame(width: 220).background(.regularMaterial)
    }
}
```

- [ ] **4. Add the configuration pane.** Reorder buttons are keyboard-operable companions to native drag ordering. The native List `.onMove` implementation is retained; expose explicit move labels so accessibility users do not depend on drag gestures.

```swift
import NeedlbarCore
import SwiftUI

struct SettingsStudioConfigurationPane: View {
    @ObservedObject var model: SystemMonitorSettingsModel
    let page: SettingsStudioPage
    let surface: MonitorDisplaySurface

    private func moduleToggle(_ id: MonitorModuleID) -> some View {
        SettingsStudioToggle(title: id.title, value: Binding(
            get: { model.isVisible(id, surface: surface) },
            set: { model.setVisible(id, $0, surface: surface) }))
    }
    private func providerToggle(_ id: ProviderID) -> some View {
        SettingsStudioToggle(title: id.displayName, value: Binding(
            get: { model.isVisible(id, surface: surface) },
            set: { model.setAIProvider(id, visible: $0, surface: surface) }))
    }
    private func moveButtons(_ index: Int, count: Int, name: String,
                             move: @escaping (IndexSet, Int) -> Void) -> some View {
        HStack {
            Button { move(IndexSet(integer: index), index - 1) } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0).accessibilityLabel("Move \(name) up")
            Button { move(IndexSet(integer: index), index + 2) } label: { Image(systemName: "chevron.down") }
                .disabled(index == count - 1).accessibilityLabel("Move \(name) down")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch page {
            case .layout:
                Text("Visibility is independent. Order is shared by both surfaces.")
                    .foregroundStyle(.secondary)
                List {
                    ForEach(Array(model.orderedModules.enumerated()), id: \.element) { index, id in
                        HStack {
                            Image(systemName: "line.3.horizontal").accessibilityHidden(true)
                            moduleToggle(id)
                            moveButtons(index, count: model.orderedModules.count, name: id.title, move: model.moveModules)
                        }
                    }.onMove(perform: model.moveModules)
                }.frame(height: 370)
                Button("Use compact defaults for this surface") { model.useCompactDefaults(surface: surface) }
                Text("AI provider order").font(.headline)
                List {
                    ForEach(Array(model.orderedProviders.enumerated()), id: \.element) { index, id in
                        HStack {
                            ProviderBrandIcon(provider: id, accessibility: .decorative)
                            providerToggle(id)
                            moveButtons(index, count: model.orderedProviders.count, name: id.displayName, move: model.moveAIProviders)
                        }
                    }.onMove(perform: model.moveAIProviders)
                }.frame(height: 195)
            case let .module(id):
                SettingsStudioSection(title: surface == .menuBar ? "Show in menu bar" : "Show in dashboard") {
                    moduleToggle(id)
                }
                if id == .network && surface == .dashboard {
                    SettingsStudioSection(title: "Network details") {
                        SettingsStudioToggle(title: "Show local IP addresses", value: Binding(
                            get: { model.value.localIPEnabled }, set: model.setLocalIPEnabled))
                        Divider()
                        SettingsStudioToggle(title: "Show public IP address", value: Binding(
                            get: { model.value.publicIPEnabled }, set: model.setPublicIPEnabled))
                    }
                    Text("Addresses appear in the dashboard only and are never exported. Public IP uses a fixed HTTPS endpoint and is cached for at least five minutes.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            case let .provider(id):
                SettingsStudioSection(title: surface == .menuBar ? "Show in menu bar" : "Show in dashboard") {
                    providerToggle(id)
                    Divider()
                    Picker("Display value (shared)", selection: Binding(
                        get: { model.value.ai[id]?.metric ?? .remaining },
                        set: { model.setAIProvider(id, metric: $0) })) {
                            ForEach(AIProviderDisplayMetric.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.font(.system(size: 17)).frame(minHeight: 54)
                }
            case .notifications, .data: EmptyView()
            }
        }
    }
}
```

- [ ] **5. Run GREEN:** `make swift-test SWIFT_TEST_FILTER=SettingsStudio`, then `make test`. Confirm no private-extension visibility errors and no undefined new symbols. Native layout inspection occurs after Task 6 wiring.
- [ ] **6. Commit the three new UI files, moved extensions, and tests:** `feat: add native module studio settings components`.

## Task 5: Compose the Settings shell while preserving action behavior

**Files:** Modify `SettingsView.swift` and `Tests/NeedlbarTests/ProviderBrandSurfaceContractTests.swift`; remove unused legacy `SystemMonitorSettingsView` declaration after replacement; create preview model/view; extend `SettingsStudioTests.swift`.

- [ ] **1. Add the failing passive-preview test.**

```swift
@Test func previewUsesProductionRendererAndHasNoFixtureValues() {
    let model = SettingsPreviewModel()
    var config = SystemMonitorConfiguration()
    config.menuBarVisibleModules = [.cpu]
    model.update(snapshot: Self.emptySnapshot, configuration: config)
    #expect(model.result == MenuBarDashboardRenderer.render(snapshot: Self.emptySnapshot,
        configuration: config, availableWidth: 240))
    #expect(!model.result.tooltip.contains("18%"))
}
```

- [ ] **2. Run RED:** `make swift-test SWIFT_TEST_FILTER=SettingsStudio`.
- [ ] **3. Create these preview types.** The model receives snapshots from the existing controller, not a new observation stream.

```swift
// SettingsPreviewModel.swift
import Combine
import Foundation
import NeedlbarCore

@MainActor
public final class SettingsPreviewModel: ObservableObject {
    @Published public private(set) var result: MenuBarDashboardRenderResult
    public init() {
        result = MenuBarDashboardRenderer.render(snapshot: CombinedUsageSnapshot(
            system: nil, providers: [], capturedAt: .distantPast, systemAvailability: [:]),
            configuration: SystemMonitorConfiguration(), availableWidth: 240)
    }
    public func update(snapshot: CombinedUsageSnapshot, configuration: SystemMonitorConfiguration) {
        result = MenuBarDashboardRenderer.render(snapshot: snapshot, configuration: configuration, availableWidth: 240)
    }
}
```

```swift
// SettingsPreviewView.swift
import AppKit
import SwiftUI

@MainActor
struct SettingsPreviewView: View {
    @ObservedObject var model: SettingsPreviewModel
    @Environment(\.displayScale) private var scale
    var body: some View {
        SettingsStudioSection(title: "Menu bar preview") {
            HStack {
                if let layout = MenuBarDashboardTwoLineLayout.fit(segments: model.result.segments,
                    width: 240, height: 22, scale: scale),
                   let image = MenuBarDashboardImageRenderer.render(layout: layout, scale: scale) {
                    Image(nsImage: image).accessibilityHidden(true)
                } else {
                    Image(systemName: "chart.bar.fill").accessibilityHidden(true)
                }
                Spacer()
            }.frame(minHeight: 54)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.result.tooltip)
    }
}
```

In `SettingsView`, add the following stored state and a `preview: SettingsPreviewModel? = nil` trailing argument to **both** initializers; forward it through the convenience initializer. Initialize `_preview` in the primary initializer. Change `_systemMonitorModel` from `ObservedObject` to `StateObject` because this view creates/owns the editor; preserve the other ObservedObjects.

```swift
@State private var selectedPage: SettingsStudioPage = .layout
@State private var selectedTab: SettingsStudioTab = .menuBar
@ObservedObject private var preview: SettingsPreviewModel
// Primary initializer assignments:
_systemMonitorModel = StateObject(wrappedValue: SystemMonitorSettingsModel(configuration: configuration))
_preview = ObservedObject(wrappedValue: preview ?? SettingsPreviewModel())
```

Replace `body` with the following shell. Keep existing `exportSnapshot`, `isExportButtonDisabled`, `setQuotaAlertsEnabled`, `notificationStatusCopy`, `providerLoginRow`, `isLoginInFlight`, and `loginStatusCopy` implementations in this file unchanged.

```swift
public var body: some View {
    HStack(spacing: 0) {
        SettingsStudioSidebar(selection: $selectedPage)
        Divider()
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(selectedPage.title).font(.system(size: 24, weight: .bold))
                if !selectedPage.tabs.isEmpty {
                    Picker("Settings surface", selection: $selectedTab) {
                        ForEach(selectedPage.tabs) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                }
                if selectedPage == .layout { SettingsPreviewView(model: preview) }
                detailPane
                Spacer(minLength: 0)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    .onChange(of: selectedPage) { _, page in
        if !page.tabs.contains(selectedTab) { selectedTab = page.tabs.first ?? .menuBar }
    }
    .onReceive(NotificationCenter.default.publisher(for: ModuleConfiguration.systemMonitorDidChangeNotification)) { note in
        guard let changed = note.object as? ModuleConfiguration, changed === configuration else { return }
        systemMonitorModel.refresh()
    }
}

@ViewBuilder private var detailPane: some View {
    switch selectedPage {
    case .notifications:
        SettingsStudioSection(title: "Quota reminders") {
            SettingsStudioToggle(title: "Quota threshold alerts", value: Binding(
                get: { notificationPreferences.isEnabled }, set: setQuotaAlertsEnabled))
        }
        Text(notificationStatusCopy).foregroundStyle(.secondary)
    case .data:
        SettingsStudioSection(title: "Snapshot export") {
            Button("Export snapshot…", action: exportSnapshot)
                .disabled(isExportButtonDisabled).frame(minHeight: 54)
            if actions.exportState == .exported { Text("Exported") }
            if actions.exportState == .failed { Text("Could not export snapshot.") }
        }
        Text("IP addresses and credentials are not included in snapshot exports.").foregroundStyle(.secondary)
    case .layout, .module, .provider:
        if let surface = selectedTab.surface {
            SettingsStudioConfigurationPane(model: systemMonitorModel, page: selectedPage, surface: surface)
            if case let .provider(provider) = selectedPage { connectionPane(provider) }
        } else if case .module = selectedPage {
            Text("System threshold alerts are not available yet.").foregroundStyle(.secondary)
        } else if case .provider = selectedPage {
            Text("Quota reminders use the global Notifications setting.").foregroundStyle(.secondary)
            Button("Open Notifications") { selectedPage = .notifications }
        }
    }
}

@ViewBuilder private func connectionPane(_ provider: ProviderID) -> some View {
    SettingsStudioSection(title: "Connection") {
        switch provider {
        case .claude: providerLoginRow(provider: .claude, title: "Claude", actionTitle: "Sign in with Claude")
        case .codex: providerLoginRow(provider: .codex, title: "Codex", actionTitle: "Sign in with ChatGPT")
        case .cursor:
            HStack {
                ProviderBrandIcon(provider: .cursor, accessibility: .decorative)
                Text("Usage comes from an existing local cache. Quota is available in Cursor Spending.")
                Spacer()
                Button("Open Cursor Spending", action: openCursorSpending)
            }.padding(.vertical, 12)
        }
    }
}
```

Import Foundation/Combine for the notification publisher. Remove the old fixed `.frame(width: 520)` and grouped Form root, not the provider/export/notification helpers. Remove the obsolete `SystemMonitorSettingsView` file only after its model and label extensions have moved. Update the brand surface tests below before removing it; do not delete existing model tests.

In `ProviderBrandSurfaceContractTests.systemMonitorSettingsHostsInLightAndDarkAppearance`, replace each `Form { SystemMonitorSettingsView(model: model) }` host argument with:

```swift
SettingsStudioConfigurationPane(model: model, page: .layout, surface: .menuBar)
    .frame(width: 700, height: 660)
```

In `settingsConnectionsHostInLightAndDarkAppearance`, host `view.frame(width: 960, height: 720)` instead of the unconstrained view. Replace the two obsolete width-520 assertions with width-960 and height-720 assertions for both appearances. Preserve effective appearance/equal-size checks. Replace the old Settings view path in `surfacePaths` with `Sources/Needlbar/Settings/SettingsStudioConfigurationPane.swift`; add `Sources/Needlbar/Settings/SettingsStudioComponents.swift` so both provider icon surfaces stay covered.

```swift
#expect(lightSize.width == 960 && lightSize.height == 720)
#expect(darkSize.width == 960 && darkSize.height == 720)
```

- [ ] **4. Run GREEN:** `make swift-test SWIFT_TEST_FILTER=SettingsStudio`, `make swift-test SWIFT_TEST_FILTER=Settings`, then `make test`. Existing SettingsActions tests must still exercise login in-flight/failure, Cursor routing and export outcomes; no action is invoked by rendering a pane.
- [ ] **5. Commit shell, preview, legacy-view removal, and tests:** `feat: compose module studio settings with retained actions`.

## Task 6: Wire passive snapshots and a resizable screen-safe window

**Files:** Modify `SettingsWindowController.swift` and `MenuBarController.swift`; extend `SettingsStudioTests.swift` and existing `MenuBarControllerTests.swift`.

- [ ] **1. Add a failing geometry test.**

```swift
@Test func settingsWindowFitsSmallAndOffsetScreens() {
    let screen = NSRect(x: -1440, y: 50, width: 800, height: 600)
    let desired = NSRect(x: 1000, y: -1000, width: 960, height: 720)
    let frame = SettingsWindowController.fittedFrame(desired, in: screen)
    #expect(screen.contains(frame))
    #expect(frame.width <= 800 && frame.height <= 600)
}
```

- [ ] **2. Run RED:** `make swift-test SWIFT_TEST_FILTER=SettingsStudio`.
- [ ] **3. Add the window fitting function, preview ownership and snapshot delivery.** Change the existing NSWindow content rect to 960×720 and add `.resizable`. Give `SettingsView` the owned preview. Preserve both public controller initializers and action forwarding.

```swift
private let preview: SettingsPreviewModel

public func update(snapshot: CombinedUsageSnapshot, configuration: SystemMonitorConfiguration) {
    preview.update(snapshot: snapshot, configuration: configuration)
}

static func fittedFrame(_ desired: NSRect, in screen: NSRect) -> NSRect {
    let width = min(max(1, desired.width), max(1, screen.width))
    let height = min(max(1, desired.height), max(1, screen.height))
    return NSRect(x: min(max(desired.minX, screen.minX), screen.maxX - width),
                  y: min(max(desired.minY, screen.minY), screen.maxY - height),
                  width: width, height: height)
}
```

Swift initialization ordering matters: assign a local `let preview = SettingsPreviewModel()` before building the hosting view and store it in `self.preview`. Do not read `self` before `super.init(window:)`. Pass `preview: preview` to the existing `SettingsView` call.

Add this fitting step inside `showSettings()` before `showWindow(nil)`:

```swift
if let window, let screen = window.screen ?? NSScreen.main {
    let available = screen.visibleFrame.insetBy(dx: 8, dy: 8)
    let chrome = window.frame.height - window.contentLayoutRect.height
    window.contentMinSize = NSSize(width: min(760, available.width),
                                  height: min(560, max(1, available.height - chrome)))
    window.maxSize = available.size
    window.setFrame(Self.fittedFrame(window.frame, in: available), display: false)
}
```

Put that block in a private `fitToCurrentScreen()` helper and call it from `showSettings`. Add the following observer owner in the same file and hold it in the controller. It is a display-topology observer, not a snapshot/refresh timer:

```swift
private final class SettingsScreenObservation {
    private let token: NSObjectProtocol
    init(_ change: @escaping @Sendable () -> Void) {
        token = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { _ in change() }
    }
    deinit { NotificationCenter.default.removeObserver(token) }
}
// SettingsWindowController stored property:
private var screenObservation: SettingsScreenObservation?
// After super.init(window:) in primary initializer:
screenObservation = SettingsScreenObservation { [weak self] in
    Task { @MainActor [weak self] in
        guard let self, self.window?.isVisible == true else { return }
        self.fitToCurrentScreen()
    }
}
```

Inside the production `MenuBarController.reconcile(using snapshot: CombinedUsageSnapshot)`, after `let monitorConfiguration = configuration.systemMonitor`, add:

```swift
settingsWindowController.update(snapshot: snapshot, configuration: monitorConfiguration)
```

Do not attach another stream to `CombinedSnapshotStore`; its existing observer already calls this function for snapshot updates and configuration reconciliation. The legacy provider-only controller may leave Settings preview unavailable rather than invent system data; do not change its provider rendering path.

- [ ] **4. Add the following regression to `MenuBarControllerTests.swift`, where the existing private fake helpers are accessible.** Preserve the existing panel identity, anchor, scroll/disclosure and dismissal tests. Add the internal read-only preview seams:

```swift
// SettingsWindowController:
var previewResult: MenuBarDashboardRenderResult { preview.result }
// Production MenuBarController:
var settingsPreviewResult: MenuBarDashboardRenderResult { settingsWindowController.previewResult }
```

```swift
@MainActor
@Test func settingsStudioEditsResizeOnlyDashboardAndRefreshPreview() async throws {
    let name = "SettingsStudio.controller.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let configuration = ModuleConfiguration(defaults: defaults)
    let combinedStore = CombinedSnapshotStore()
    let factory = FakeStatusItemFactory()
    let presenter = FakeMenuPanelPresenter()
    let controller = makeMenuBarController(configuration: configuration,
        snapshotStore: ProviderSnapshotStore(), combinedSnapshotStore: combinedStore,
        loginCoordinator: testLoginCoordinator(), statusItemFactory: factory, panelPresenter: presenter)
    await controller.startObserving()
    defer { controller.stopObserving() }
    let item = try #require(factory.created.first)
    item.performAction()
    #expect(await eventually { presenter.presentCount == 1 && presenter.isShown })
    var value = configuration.systemMonitor
    value.menuBarVisibleModules = [.cpu]
    configuration.setSystemMonitor(value)
    #expect(await eventually { controller.settingsPreviewResult.configuredModuleIDs == [.cpu] })
    #expect(presenter.resizedSizes.isEmpty)
    value.dashboardVisibleModules.insert(.disk)
    configuration.setSystemMonitor(value)
    #expect(await eventually { presenter.resizedSizes.count == 1 })
    #expect(presenter.presentCount == 1)
    #expect(presenter.resizedAnchors == presenter.presentedAnchors)
    #expect(presenter.presentedContentViewControllers.count == 1)
    let combined = await combinedStore.snapshot()
    #expect(controller.settingsPreviewResult == MenuBarDashboardRenderer.render(
        snapshot: combined, configuration: configuration.systemMonitor, availableWidth: 240))
}
```

- [ ] **5. Run GREEN:** `make swift-test SWIFT_TEST_FILTER=SettingsStudio`, `make swift-test SWIFT_TEST_FILTER=MenuBarController`, then `make test`.
- [ ] **6. Commit controller wiring/geometry and tests:** `feat: connect live settings previews and adaptive window sizing`.

## Task 7: Regression matrix, native acceptance, and documentation handoff

**Files:** Extend the new Core/app test files as needed; update `docs/STATUS.md`. No release or runtime-service modifications.

- [ ] **1. Run the migration matrix in isolated suites.** Add parameterized tests for independent system/provider empty, missing, malformed and valid new values; unknown module IDs; numeric/string fake Booleans; legacy enabled flags; empty provider arrays; saved `.usage`/`.cost`; noncanonical orders. The expected results are fixed by Tasks 1–3, never by whichever behavior happens to pass. Add a getter-notification count test using a scoped observer and assert zero notifications before any setter.

```swift
@Test(arguments: ["true", "false", "1", "0"])
func malformedProviderStringsUseLegacy(_ raw: String) {
    let name = "SettingsStudio.bad-bool.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(false, forKey: "needlbar.systemMonitor.ai.cursor.visible")
    defaults.set(raw, forKey: "needlbar.systemMonitor.ai.cursor.dashboard.visible")
    #expect(ModuleConfiguration(defaults: defaults).systemMonitor.ai[.cursor]?.dashboardVisible == false)
}
```

- [ ] **2. Run project gates serially and record real exit codes.**

```bash
make swift-test SWIFT_TEST_FILTER=SettingsStudio
make test
make acceptance-test
git diff --check
```

Expected: all executed commands exit 0. Record actual Swift Testing counts, not the XCTest compatibility footer. These commands do not prove native appearance.

- [ ] **3. Inspect native Settings safely on the current host.** Use an isolated test-host NSWindow/NSHostingView with a generated UserDefaults suite, the real Settings view, passive snapshots, and existing SettingsActions test doubles. Do not start production `AppDelegate`/refresh services merely to take a screenshot. Reuse the project's existing fake action and notification dependencies from tests. If that test-host cannot be safely displayed, record the native gate as pending instead of claiming a pass or silently signing/installing a release bundle.

The existing `scripts/native-acceptance-run.sh` is a **macOS 14, network-disabled, widget/notification harness**, not a shortcut for this host's Settings validation. Do not change network services or invoke the Developer-ID acceptance packager for this task without user scope.

Acceptance checklist (record a result per row):

| Check | Required observation |
| --- | --- |
| Default/minimum window | 960×720 content default, 760×560 minimum when screen allows; no clipped sidebar or right-hand controls |
| Screen changes | move/resize on available displays; fitted frame remains within usable frame |
| Navigation | every page and tab changes its pane; no duplicate tabs on Layout/Preferences |
| Typography/appearance | 24-point headings, 17-point primary rows; light/dark contrast; official provider marks |
| Visibility | CPU off in menu remains on dashboard; Claude off in dashboard remains on menu |
| Order/reset | explicit keyboard reorder and drag; shared order; compact reset affects selected surface only |
| Provider state | idle/in-flight/connected/failure fixture copy and disabled in-flight actions; Cursor Spending only |
| Data/privacy | export busy/success/failure fixtures; no IP/credential/source-path disclosure in Settings/preview |
| Notifications | global quota setting only; system Alerts explanatory, no proposed threshold controls |
| Preview | renderer matches current configuration; unavailable is neutral; no mock values/style choices |
| Dashboard regression | existing panel resizes in place; correct anchor, scroll/disclosure, outside-click dismissal |

- [ ] **4. Update `docs/STATUS.md` with branch/commit, task completion, exact commands/results, screenshots if safely captured, remaining native/macOS 14 limitations, and the next feature-spec stage.** Do not mark Phase 2 style/unit work complete or imply Stats feature parity.
- [ ] **5. Commit only the regression tests and status record:** `test: verify module studio migration and native behavior`.
- [ ] **6. Use the branch-finishing skill after all required implementation gates are satisfied.** Ask before push/merge/install/release; none follows automatically from this plan.

## Plan self-review / requirement coverage

| Approved requirement | Implementing tasks |
| --- | --- |
| independent module and provider visibility; lazy migration; defaults | 1, 2, 3, 7 |
| shared order/metric; selected-surface compact reset | 3, 4, 7 |
| sidebar, single tab group, native row hierarchy, accessibility | 4, 5, 7 |
| existing sign-in, Cursor Spending, global quota, export, IP | 4, 5, 7 |
| passive preview; no scheduling change; in-place dashboard reconciliation | 2, 5, 6, 7 |
| screen-clamped resizable window | 6, 7 |
| no proposed fake controls; no release or macOS 14 claim | scope rules, 5, 7 |

Execution uses fresh task workers and review checkpoints when the configured
agents are available. At plan-writing time, both configured worker roles reported
an account usage-limit error; no reset was redeemed and no alternate model was
silently selected. This availability issue must not be misreported as a code or
test failure. The plan remains usable for a later execution session.
