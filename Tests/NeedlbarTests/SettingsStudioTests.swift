import AppKit
import Foundation
import SwiftUI
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

@Suite("SettingsStudio", .serialized)
@MainActor
struct SettingsStudioTests {
    @Test func claudeUsageActionHasOnlyTheApprovedDestination() {
        var openedURL: URL?

        let opened = ClaudeUsageAction.open { url in
            openedURL = url
            return false
        }

        #expect(!opened)
        #expect(openedURL?.absoluteString == "https://claude.ai/settings/usage")
    }

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

    @Test func compactMenuResetPreservesDashboardAndProviderChoices() throws {
        let name = "SettingsStudio.menu-reset.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ModuleConfiguration(defaults: defaults)
        var initial = SystemMonitorConfiguration(visibleModules: [.disk], dashboardVisibleModules: [.network])
        initial.ai[.claude]?.dashboardVisible = false
        initial.ai[.codex]?.metric = .usage
        store.setSystemMonitor(initial)
        SystemMonitorSettingsModel(configuration: store).useCompactDefaults(surface: .menuBar)
        let saved = store.systemMonitor
        #expect(saved.menuBarVisibleModules == [.cpu, .memory, .ai])
        #expect(saved.dashboardVisibleModules == [.network])
        #expect(saved.ai == initial.ai)
    }

    @Test func settingsSectionUsesAllocatedDetailWidth() throws {
        let measurement = SettingsStudioWidthMeasurement()
        let content = SettingsStudioMeasuringLayout(measurement: measurement) {
            SettingsStudioSection(title: "Show in dashboard") {
                SettingsStudioToggle(title: "CPU", value: .constant(true))
            }
        }.frame(width: 500, height: 160, alignment: .topLeading)
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 160)
        host.layoutSubtreeIfNeeded()
        _ = host.fittingSize
        let width = try #require(measurement.width)
        #expect(width >= 499)
    }

    @Test func hostingLayoutDoesNotOverwriteWindowMinimum() async throws {
        let name = "SettingsStudio.window-minimum.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = QuotaNotificationPreferences(defaults: defaults)
        let controller = SettingsWindowController(configuration: ModuleConfiguration(defaults: defaults),
            actions: SettingsActions(), notificationPreferences: preferences,
            notificationService: QuotaNotificationService(store: ProviderSnapshotStore(), preferences: preferences),
            openCursorSpending: {})
        let window = try #require(controller.window)
        window.contentMinSize = NSSize(width: 760, height: 560)
        window.setContentSize(NSSize(width: 760, height: 560))
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        #expect(window.contentMinSize == NSSize(width: 760, height: 560))
    }

    @Test func settingsWindowFitsSmallAndOffsetScreens() {
        let screen = NSRect(x: -1440, y: 50, width: 800, height: 600)
        let desired = NSRect(x: 1000, y: -1000, width: 960, height: 720)
        let frame = SettingsWindowController.fittedFrame(desired, in: screen)
        #expect(screen.contains(frame))
        #expect(frame == screen)
        let inside = NSRect(x: -1400, y: 100, width: 500, height: 400)
        #expect(SettingsWindowController.fittedFrame(inside, in: screen) == inside)
    }

    @Test func previewUsesProductionRendererAndHasNoFixtureValues() {
        let model = SettingsPreviewModel()
        var configuration = SystemMonitorConfiguration()
        configuration.menuBarVisibleModules = [.cpu]
        model.update(snapshot: Self.emptySnapshot, configuration: configuration)
        #expect(model.result == MenuBarDashboardRenderer.render(snapshot: Self.emptySnapshot,
            configuration: configuration, availableWidth: 240))
        #expect(model.result.tooltip == "CPU —")
        #expect(model.result.configuredModuleIDs == [.cpu])
    }

    @Test func tabsCannotRouteAlertsIntoVisibility() {
        #expect(SettingsStudioTab.alerts.surface == nil)
        #expect(SettingsStudioTab.menuBar.surface == .menuBar)
        #expect(SettingsStudioTab.dashboard.surface == .dashboard)
        #expect(SettingsStudioPage.layout.tabs == [.menuBar, .dashboard])
        #expect(SettingsStudioPage.notifications.tabs.isEmpty)
        #expect(SettingsStudioPage.data.tabs.isEmpty)
        #expect(SettingsStudioPage.module(.cpu).tabs == [.menuBar, .dashboard, .alerts])
        #expect(SettingsStudioPage.provider(.claude).tabs == [.menuBar, .dashboard, .alerts])
    }

    static var emptySnapshot: CombinedUsageSnapshot {
        .init(system: nil, providers: [], capturedAt: .distantPast, systemAvailability: [:])
    }

    @Test func editorDoesNotCrossSurfaces() {
        let name = "SettingsStudio.editor.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ModuleConfiguration(defaults: defaults)
        var initial = SystemMonitorConfiguration(visibleModules: Set(MonitorModuleID.allCases))
        initial.publicIPEnabled = true
        initial.localIPEnabled = true
        initial.order = [.ai, .network, .battery, .disk, .memory, .cpu]
        initial.aiOrder = [.cursor, .codex, .claude]
        store.setSystemMonitor(initial)
        let model = SystemMonitorSettingsModel(configuration: store)
        model.setVisible(.cpu, false, surface: .menuBar)
        model.setAIProvider(.claude, visible: false, surface: .dashboard)
        model.setAIProvider(.claude, metric: .cost)
        model.useCompactDefaults(surface: .dashboard)
        let value = store.systemMonitor
        #expect(value.menuBarVisibleModules == [.memory, .disk, .network, .battery, .ai])
        #expect(value.dashboardVisibleModules == [.cpu, .memory, .ai])
        #expect(value.ai[.claude]?.menuBarVisible == true)
        #expect(value.ai[.claude]?.dashboardVisible == false)
        #expect(value.ai[.claude]?.metric == .cost)
        #expect(value.publicIPEnabled && value.localIPEnabled)
        #expect(value.order == [.ai, .network, .battery, .disk, .memory, .cpu])
        #expect(value.aiOrder == [.cursor, .codex, .claude])
        #expect(model.isVisible(.cpu, surface: .dashboard))
        #expect(!model.isVisible(.cpu, surface: .menuBar))
        #expect(model.isVisible(.claude, surface: .menuBar))
        #expect(!model.isVisible(.claude, surface: .dashboard))
    }

    @Test func consumersUseDifferentSurfaces() {
        var configuration = SystemMonitorConfiguration()
        configuration.menuBarVisibleModules = [.cpu, .ai]
        configuration.dashboardVisibleModules = [.memory, .ai]
        configuration.ai[.claude]?.menuBarVisible = false
        configuration.ai[.claude]?.dashboardVisible = true
        configuration.ai[.codex]?.dashboardVisible = false
        configuration.ai[.cursor]?.dashboardVisible = false
        let menu = MenuBarDashboardRenderer.render(snapshot: Self.emptySnapshot,
            configuration: configuration, availableWidth: 240)
        let dashboard = SystemDashboardPresentation(snapshot: Self.emptySnapshot, configuration: configuration)
        #expect(menu.configuredModuleIDs == [.cpu, .ai])
        #expect(!menu.tooltip.contains("Claude"))
        #expect(dashboard.moduleIDs == [.memory, .ai])
        #expect(dashboard.ai.map(\.provider) == [.claude])
        configuration.menuBarVisibleModules = []
        #expect(MenuBarDashboardRenderer.render(snapshot: Self.emptySnapshot,
            configuration: configuration, availableWidth: 240).usesIconFallback)
        #expect(SystemDashboardPresentation(snapshot: Self.emptySnapshot,
            configuration: configuration).moduleIDs == [.memory, .ai])
    }
}

private struct SettingsStudioMeasuringLayout: Layout {
    let measurement: SettingsStudioWidthMeasurement
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let view = subviews.first else { return .zero }
        let size = view.sizeThatFits(proposal)
        if proposal.width == 500 { measurement.record(size.width) }
        return size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: proposal)
    }
}

private final class SettingsStudioWidthMeasurement: @unchecked Sendable {
    private let lock = NSLock()
    private var measuredWidth: CGFloat?
    var width: CGFloat? { lock.withLock { measuredWidth } }
    func record(_ width: CGFloat) { lock.withLock { measuredWidth = width } }
}
