import AppKit
import Foundation
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

@Test func rendererUsesCompactLayoutWhenTheMeasuredBudgetIsSmall() {
    let value = MenuBarDashboardRenderer.render(
        snapshot: fixtureCombinedSnapshot(),
        configuration: fixtureMonitorConfiguration(),
        availableWidth: 120
    )

    #expect(value.layout == .compact)
    #expect(value.title.contains("CPU"))
    #expect(value.title.contains("24%"))
}

@Test func rendererUsesExpandedLayoutWhenTheMeasuredBudgetIsWide() {
    let value = MenuBarDashboardRenderer.render(
        snapshot: fixtureCombinedSnapshot(),
        configuration: fixtureMonitorConfiguration(),
        availableWidth: 400
    )

    #expect(value.layout == .expanded)
    #expect(value.title.contains("CPU 24%"))
    #expect(value.title.contains("NET"))
}

@Test func rendererPreservesConfiguredOrderAndOmitsHiddenModules() {
    var configuration = fixtureMonitorConfiguration()
    configuration.order = [.network, .cpu, .ai, .memory, .disk, .battery]
    configuration.visibleModules = [.network, .ai]

    let value = MenuBarDashboardRenderer.render(
        snapshot: fixtureCombinedSnapshot(), configuration: configuration, availableWidth: 400
    )

    #expect(value.moduleIDs == [.network, .ai])
    #expect(value.title.hasPrefix("NET"))
    #expect(!value.title.contains("CPU"))
}

@Test func rendererKeepsUnavailableModulesAsStableSlots() {
    var configuration = fixtureMonitorConfiguration()
    configuration.visibleModules = [.cpu, .battery]
    let unavailable = CombinedUsageSnapshot(
        system: nil,
        providers: [],
        capturedAt: Date(timeIntervalSince1970: 10_000),
        systemAvailability: [:]
    )

    let value = MenuBarDashboardRenderer.render(
        snapshot: unavailable, configuration: configuration, availableWidth: 400
    )

    #expect(value.moduleIDs == [.cpu, .battery])
    #expect(value.title.contains("CPU —"))
    #expect(value.title.contains("BAT —"))
}

@Test func rendererUsesEachVisibleAIProviderPreference() throws {
    var configuration = fixtureMonitorConfiguration()
    configuration.visibleModules = [.ai]
    configuration.ai[.claude] = AIProviderDisplayPreference(isVisible: false, metric: .cost)
    configuration.ai[.codex] = AIProviderDisplayPreference(isVisible: true, metric: .remaining)

    let value = MenuBarDashboardRenderer.render(
        snapshot: fixtureCombinedSnapshot(), configuration: configuration, availableWidth: 400
    )

    #expect(value.moduleIDs == [.ai])
    #expect(!value.title.contains("Claude"))
    #expect(value.title.contains("Codex"))
    #expect(value.title.contains("55%"))
}

private func fixtureMonitorConfiguration() -> SystemMonitorConfiguration {
    SystemMonitorConfiguration()
}

private func fixtureCombinedSnapshot() -> CombinedUsageSnapshot {
    let date = Date(timeIntervalSince1970: 10_000)
    let system = SystemMetricsSnapshot(
        capturedAt: date,
        cpu: .init(totalUsage: MetricPercentage(24), perCoreUsage: [MetricPercentage(24)!]),
        memory: .init(usedBytes: 8 * 1_024 * 1_024 * 1_024, freeBytes: 2 * 1_024 * 1_024 * 1_024, swapUsedBytes: 0, pressure: "normal"),
        disks: [.init(name: "Macintosh HD", usedBytes: 100, freeBytes: 200, readBytesPerSecond: 10, writeBytesPerSecond: 20)],
        network: .init(uploadBytesPerSecond: 1_000, downloadBytesPerSecond: 2_000, localIPAddresses: ["192.0.2.10"], publicIPAddress: nil),
        battery: .init(level: MetricPercentage(100), isCharging: true, health: MetricPercentage(96)),
        availability: Dictionary(uniqueKeysWithValues: MonitorModuleID.allCases.map {
            ($0, .fresh(capturedAt: date))
        })
    )
    return CombinedUsageSnapshot(
        system: system,
        providers: [
            rendererProviderSnapshot(provider: .claude, usedPercent: 68, tokens: 1_420_000),
            rendererProviderSnapshot(provider: .codex, usedPercent: 45, tokens: 500),
        ],
        capturedAt: date,
        systemAvailability: system.availability
    )
}

private func rendererProviderSnapshot(provider: ProviderID, usedPercent: Double, tokens: UInt64) -> ProviderSnapshot {
    let period = UsagePeriod(
        inputTokens: tokens, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0,
        totalTokens: tokens, estimatedCostUSD: Decimal(string: "7.81")!
    )
    return ProviderSnapshot(
        provider: provider,
        usage: UsageSnapshot(
            inputTokens: tokens, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0,
            totalTokens: tokens, estimatedCostUSD: Decimal(string: "7.81")!, today: period,
            last7Days: period, last30Days: period
        ),
        quota: QuotaSnapshot(windows: [try! QuotaWindow(id: "window", title: "Window", usedPercent: usedPercent, resetsAt: nil)]),
        usageStatus: .fresh,
        quotaStatus: .fresh,
        updatedAt: Date(timeIntervalSince1970: 10_000)
    )
}
