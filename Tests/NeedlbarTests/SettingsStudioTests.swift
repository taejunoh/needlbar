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
