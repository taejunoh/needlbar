import Foundation
import AppKit
import NeedlbarCore
import SwiftUI
import Testing
@testable import NeedlbarApp

@Suite("ProviderBrandSurfaceContractTests", .serialized)
struct ProviderBrandSurfaceContractTests {
    @Test("all approved provider surfaces use the shared decorative brand icon")
    func approvedProviderSurfacesUseSharedBrandIcon() throws {
        for relativePath in Self.surfacePaths {
            let source = try String(contentsOf: Self.repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)

            #expect(source.contains("ProviderBrandIcon(provider:"), "Missing ProviderBrandIcon wiring in \(relativePath)")
            #expect(source.contains("accessibility: .decorative"), "Provider brand icon must be decorative in \(relativePath)")
            #expect(!source.contains("provider.systemImage"), "Legacy provider systemImage usage remains in \(relativePath)")
            #expect(!source.contains("presentation.provider.systemImage"), "Legacy provider systemImage usage remains in \(relativePath)")
            #expect(!source.contains("row.provider.systemImage"), "Legacy provider systemImage usage remains in \(relativePath)")
        }

        let settingsSource = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("Sources/Needlbar/Settings/SettingsView.swift"),
            encoding: .utf8
        )
        #expect(
            settingsSource.components(separatedBy: "HStack(alignment: .top, spacing: 8)").count - 1 >= 2,
            "Claude/Codex and Cursor connection rows must top-align their brand icons"
        )
    }

    @MainActor @Test("overview popover hosts and lays out in aqua and dark aqua")
    func overviewPopoverHostsInLightAndDarkAppearance() throws {
        let suiteName = "ProviderBrandSurfaceContractTests.overview.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let snapshots = try Self.providerSnapshots()
        let configuration = ModuleConfiguration(defaults: defaults)
        let light = Self.host(
            OverviewPopoverView(snapshots: snapshots, configuration: configuration),
            appearance: .aqua
        )
        let dark = Self.host(
            OverviewPopoverView(snapshots: snapshots, configuration: configuration),
            appearance: .darkAqua
        )

        let lightSize = light.view.fittingSize
        let darkSize = dark.view.fittingSize
        #expect(light.view.appearance?.name == .aqua)
        #expect(dark.view.appearance?.name == .darkAqua)
        #expect(light.view.effectiveAppearance.bestMatch(from: Self.appearanceNames) == .aqua)
        #expect(dark.view.effectiveAppearance.bestMatch(from: Self.appearanceNames) == .darkAqua)
        #expect(lightSize == darkSize)
        #expect(lightSize.width == 300)
        #expect(darkSize.width == 300)
        #expect(lightSize.width > 0 && lightSize.height > 0)
        #expect(darkSize.width > 0 && darkSize.height > 0)
    }

    @MainActor @Test("provider detail hosts and lays out in aqua and dark aqua")
    func providerDetailHostsInLightAndDarkAppearance() throws {
        let snapshot = try #require(Self.providerSnapshots().first)
        let light = Self.host(ProviderPopoverView(snapshot: snapshot), appearance: .aqua)
        let dark = Self.host(ProviderPopoverView(snapshot: snapshot), appearance: .darkAqua)

        let lightSize = light.view.fittingSize
        let darkSize = dark.view.fittingSize
        #expect(light.view.appearance?.name == .aqua)
        #expect(dark.view.appearance?.name == .darkAqua)
        #expect(light.view.effectiveAppearance.bestMatch(from: Self.appearanceNames) == .aqua)
        #expect(dark.view.effectiveAppearance.bestMatch(from: Self.appearanceNames) == .darkAqua)
        #expect(lightSize == darkSize)
        #expect(lightSize.width == 300)
        #expect(darkSize.width == 300)
        #expect(lightSize.width > 0 && lightSize.height > 0)
        #expect(darkSize.width > 0 && darkSize.height > 0)
    }

    @MainActor @Test("system monitor settings hosts and lays out in aqua and dark aqua")
    func systemMonitorSettingsHostsInLightAndDarkAppearance() throws {
        let suiteName = "ProviderBrandSurfaceContractTests.monitor.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = SystemMonitorSettingsModel(configuration: ModuleConfiguration(defaults: defaults))
        let light = Self.host(Form { SystemMonitorSettingsView(model: model) }, appearance: .aqua)
        let dark = Self.host(Form { SystemMonitorSettingsView(model: model) }, appearance: .darkAqua)

        let lightSize = light.view.fittingSize
        let darkSize = dark.view.fittingSize
        #expect(light.view.appearance?.name == .aqua)
        #expect(dark.view.appearance?.name == .darkAqua)
        #expect(light.view.effectiveAppearance.bestMatch(from: Self.appearanceNames) == .aqua)
        #expect(dark.view.effectiveAppearance.bestMatch(from: Self.appearanceNames) == .darkAqua)
        #expect(lightSize == darkSize)
        #expect(lightSize.width > 0 && lightSize.height > 0)
        #expect(darkSize.width > 0 && darkSize.height > 0)
    }

    @MainActor @Test("settings connections host and lay out in aqua and dark aqua")
    func settingsConnectionsHostInLightAndDarkAppearance() throws {
        let suiteName = "ProviderBrandSurfaceContractTests.settings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = QuotaNotificationPreferences(defaults: defaults)
        let view = SettingsView(
            configuration: ModuleConfiguration(defaults: defaults),
            actions: SettingsActions(),
            notificationPreferences: preferences,
            notificationService: QuotaNotificationService(
                store: ProviderSnapshotStore(),
                preferences: preferences
            ),
            openCursorSpending: {}
        )
        let light = Self.host(view, appearance: .aqua)
        let dark = Self.host(view, appearance: .darkAqua)

        let lightSize = light.view.fittingSize
        let darkSize = dark.view.fittingSize
        #expect(light.view.appearance?.name == .aqua)
        #expect(dark.view.appearance?.name == .darkAqua)
        #expect(light.view.effectiveAppearance.bestMatch(from: Self.appearanceNames) == .aqua)
        #expect(dark.view.effectiveAppearance.bestMatch(from: Self.appearanceNames) == .darkAqua)
        #expect(lightSize == darkSize)
        #expect(lightSize.width == 520)
        #expect(darkSize.width == 520)
        #expect(lightSize.width > 0 && lightSize.height > 0)
        #expect(darkSize.width > 0 && darkSize.height > 0)
    }

    private static let surfacePaths = [
        "Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift",
        "Sources/Needlbar/Modules/Overview/OverviewPopoverView.swift",
        "Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift",
        "Sources/Needlbar/Settings/SystemMonitorSettingsView.swift",
        "Sources/Needlbar/Settings/SettingsView.swift",
    ]

    private static let appearanceNames: [NSAppearance.Name] = [.aqua, .darkAqua]

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @MainActor
    private static func host<Content: View>(
        _ rootView: Content,
        appearance: NSAppearance.Name
    ) -> NSHostingController<Content> {
        let controller = NSHostingController(rootView: rootView)
        controller.view.appearance = NSAppearance(named: appearance)
        controller.view.layoutSubtreeIfNeeded()
        return controller
    }

    private static func providerSnapshots() throws -> [ProviderSnapshot] {
        let period = UsagePeriod(
            inputTokens: 100,
            outputTokens: 50,
            cacheReadTokens: 25,
            cacheWriteTokens: 10,
            totalTokens: 185,
            estimatedCostUSD: Decimal(string: "1.25")!
        )
        let usage = UsageSnapshot(
            inputTokens: 100,
            outputTokens: 50,
            cacheReadTokens: 25,
            cacheWriteTokens: 10,
            totalTokens: 185,
            estimatedCostUSD: Decimal(string: "1.25")!,
            today: period,
            last7Days: period,
            last7DaysDaily: [DailyUsagePoint(date: "2026-09-04", totalTokens: 185)],
            last30Days: period
        )
        return try ProviderID.allCases.map { provider in
            ProviderSnapshot(
                provider: provider,
                usage: usage,
                quota: QuotaSnapshot(windows: [
                    try QuotaWindow(id: "\(provider.rawValue).window", title: "Window", usedPercent: 25, resetsAt: nil)
                ]),
                usageStatus: .fresh,
                quotaStatus: .fresh,
                updatedAt: Date(timeIntervalSince1970: 10_000)
            )
        }
    }
}
