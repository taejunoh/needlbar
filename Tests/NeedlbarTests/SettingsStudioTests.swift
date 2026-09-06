import AppKit
import Foundation
import SwiftUI
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

@Suite("SettingsStudio", .serialized)
@MainActor
struct SettingsStudioTests {
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
