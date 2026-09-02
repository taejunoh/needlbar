import Foundation
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

@Test func dashboardPresentationAlwaysContainsAllSixSystemModules() {
    var configuration = SystemMonitorConfiguration()
    configuration.visibleModules = [.cpu]
    let presentation = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(),
        configuration: configuration
    )

    #expect(Set(presentation.moduleIDs) == Set(MonitorModuleID.allCases))
    #expect(presentation.moduleIDs == MonitorModuleID.defaultOrder)
    #expect(presentation.cpu.usage == "24%")
    #expect(presentation.memory.used == "8.0 GB")
}

@Test func dashboardPresentationIncludesNetworkSpeedAndOptionalIPValues() {
    var configuration = SystemMonitorConfiguration()
    configuration.publicIPEnabled = false
    let presentation = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(),
        configuration: configuration
    )

    #expect(presentation.network.upload == "1.0 KB/s")
    #expect(presentation.network.download == "2.0 KB/s")
    #expect(presentation.network.localIPAddresses == ["192.0.2.10"])
    #expect(presentation.network.publicIPAddress == nil)
}

@Test func dashboardPresentationPreservesConfiguredModuleOrder() {
    var configuration = SystemMonitorConfiguration()
    configuration.order = [.ai, .network, .cpu, .battery, .memory, .disk]

    let presentation = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(),
        configuration: configuration
    )

    #expect(presentation.moduleIDs == configuration.order)
}

@Test func dashboardPresentationUsesConfiguredAIDisplayMetric() {
    var configuration = SystemMonitorConfiguration()
    configuration.ai[.claude] = AIProviderDisplayPreference(isVisible: true, metric: .cost)
    configuration.ai[.codex] = AIProviderDisplayPreference(isVisible: true, metric: .remaining)
    let presentation = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(),
        configuration: configuration
    )

    #expect(presentation.ai.first(where: { $0.provider == .claude })?.value == "$7.81")
    #expect(presentation.ai.first(where: { $0.provider == .codex })?.value == "55%")
}

private func dashboardFixtureSnapshot() -> CombinedUsageSnapshot {
    let date = Date(timeIntervalSince1970: 10_000)
    let system = SystemMetricsSnapshot(
        capturedAt: date,
        cpu: .init(totalUsage: MetricPercentage(24), perCoreUsage: []),
        memory: .init(usedBytes: 8_000_000_000, freeBytes: 2_000_000_000, swapUsedBytes: 0, pressure: "normal"),
        disks: [.init(name: "Macintosh HD", usedBytes: 100, freeBytes: 200, readBytesPerSecond: 10, writeBytesPerSecond: 20)],
        network: .init(uploadBytesPerSecond: 1_000, downloadBytesPerSecond: 2_000, localIPAddresses: ["192.0.2.10"], publicIPAddress: nil),
        battery: .init(level: MetricPercentage(100), isCharging: true, health: MetricPercentage(96)),
        availability: Dictionary(uniqueKeysWithValues: MonitorModuleID.allCases.map {
            ($0, .fresh(capturedAt: date))
        })
    )
    let period = UsagePeriod(
        inputTokens: 1_420_000, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0,
        totalTokens: 1_420_000, estimatedCostUSD: Decimal(string: "7.81")!
    )
    let providers = ProviderID.allCases.map { provider in
        ProviderSnapshot(
            provider: provider,
            usage: UsageSnapshot(
                inputTokens: 1_420_000, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0,
                totalTokens: 1_420_000, estimatedCostUSD: Decimal(string: "7.81")!, today: period,
                last7Days: period, last30Days: period
            ),
            quota: QuotaSnapshot(windows: [try! QuotaWindow(id: "window", title: "Window", usedPercent: provider == .codex ? 45 : 68, resetsAt: nil)]),
            usageStatus: .fresh,
            quotaStatus: .fresh,
            updatedAt: date
        )
    }
    return CombinedUsageSnapshot(
        system: system,
        providers: providers,
        capturedAt: date,
        systemAvailability: system.availability
    )
}
