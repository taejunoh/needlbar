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

@Test func rendererUsesCompactLayoutWhenAWideCallerBudgetIsCappedConservatively() {
    let value = MenuBarDashboardRenderer.render(
        snapshot: fixtureCombinedSnapshot(),
        configuration: fixtureMonitorConfiguration(),
        availableWidth: 400
    )

    #expect(value.layout == .compact)
    #expect(value.title.contains("CPU 24%"))
    #expect(value.title.contains("RAM 80%"))
    #expect(value.title.contains("AI"))
}

@Test func rendererFitsEveryPositiveWidthBudgetAndReportsRenderedModules() {
    var configuration = fixtureMonitorConfiguration()
    configuration.visibleModules = Set(MonitorModuleID.allCases)

    for width in [1.0, 80.0, 120.0, 240.0, 300.0] {
        let value = MenuBarDashboardRenderer.render(
            snapshot: fixtureCombinedSnapshot(), configuration: configuration, availableWidth: width
        )
        let measured = Double((value.title as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width)
        #expect(measured <= width + 0.01)
        #expect(value.moduleIDs.count <= 3)
        #expect(value.configuredModuleIDs == MonitorModuleID.allCases)
        if width < 22 {
            #expect(value.usesIconFallback)
            #expect(!value.title.contains("+"))
        }
    }
}

@Test func rendererKeepsTypicalCompactDefaultsTogetherAtTheConservativeCap() {
    let value = MenuBarDashboardRenderer.render(
        snapshot: fixtureCombinedSnapshot(),
        configuration: fixtureMonitorConfiguration(),
        availableWidth: 240
    )

    #expect(value.moduleIDs == [.cpu, .memory, .ai])
    #expect(value.title.contains("CPU 24%"))
    #expect(value.title.contains("RAM 80%"))
    #expect(value.title.contains("AI"))
}

@Test func fableDoesNotChangeAdaptiveMenuTitleOrTooltip() throws {
    var configuration = fixtureMonitorConfiguration()
    configuration.visibleModules = [.ai]
    configuration.ai[.claude] = AIProviderDisplayPreference(isVisible: true, metric: .remaining)
    let baseline = fixtureCombinedSnapshot()
    let claude = try #require(baseline.providers.first(where: { $0.provider == .claude }))
    let fable = try QuotaWindow(
        id: QuotaWindow.claudeFableWeeklyID,
        title: "Fable weekly",
        usedPercent: 100,
        resetsAt: baseline.capturedAt.addingTimeInterval(3600)
    )
    let augmentedClaude = ProviderSnapshot(
        provider: claude.provider,
        usage: claude.usage,
        quota: QuotaSnapshot(windows: (claude.quota?.windows ?? []) + [fable]),
        usageStatus: claude.usageStatus,
        quotaStatus: claude.quotaStatus,
        updatedAt: claude.updatedAt
    )
    let augmented = CombinedUsageSnapshot(
        system: baseline.system,
        providers: baseline.providers.map { $0.provider == .claude ? augmentedClaude : $0 },
        capturedAt: baseline.capturedAt,
        systemAvailability: baseline.systemAvailability
    )

    let before = MenuBarDashboardRenderer.render(snapshot: baseline, configuration: configuration, availableWidth: 240)
    let after = MenuBarDashboardRenderer.render(snapshot: augmented, configuration: configuration, availableWidth: 240)

    #expect(after.title == before.title)
    #expect(after.tooltip == before.tooltip)
}

@Test func rendererUsesBillionsAndOverflowForLargeProviderValues() {
    var configuration = fixtureMonitorConfiguration()
    configuration.visibleModules = [.ai]
    configuration.ai[.claude] = AIProviderDisplayPreference(metric: .usage)
    let value = MenuBarDashboardRenderer.render(
        snapshot: fixtureCombinedSnapshot(tokens: 4_200_000_000),
        configuration: configuration,
        availableWidth: 240
    )

    #expect(value.title.contains("B"))
    #expect(value.tooltip.contains("Claude"))
}

@Test func rendererPreservesConfiguredOrderAndOmitsHiddenModules() {
    var configuration = fixtureMonitorConfiguration()
    configuration.order = [.network, .cpu, .ai, .memory, .disk, .battery]
    configuration.visibleModules = [.network, .ai]

    let value = MenuBarDashboardRenderer.render(
        snapshot: fixtureCombinedSnapshot(), configuration: configuration, availableWidth: 400
    )

    #expect(value.configuredModuleIDs == [.network, .ai])
    #expect(!value.moduleIDs.isEmpty)
    #expect(value.moduleIDs == Array([.network, .ai].prefix(value.moduleIDs.count)))
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
    #expect(value.title.contains("CX"))
    #expect(value.title.contains("55%"))
}

@Test func rendererDefaultsToRemainingEvenWhenTokenUsageExists() {
    var configuration = fixtureMonitorConfiguration()
    configuration.visibleModules = [.ai]

    let value = MenuBarDashboardRenderer.render(
        snapshot: fixtureCombinedSnapshot(), configuration: configuration, availableWidth: 400
    )

    #expect(value.title.contains("AI CL 32%"))
    #expect(!value.title.contains("1.42M"))
}

@Test func rendererDoesNotFallBackToTokensWhenDefaultRemainingHasNoQuota() {
    var configuration = fixtureMonitorConfiguration()
    configuration.visibleModules = [.ai]

    let value = MenuBarDashboardRenderer.render(
        snapshot: fixtureCombinedSnapshot(hasQuota: false), configuration: configuration, availableWidth: 400
    )

    #expect(value.title.contains("AI CL —"))
    #expect(!value.title.contains("1.42M"))
}

private func fixtureMonitorConfiguration() -> SystemMonitorConfiguration {
    SystemMonitorConfiguration()
}

private func fixtureCombinedSnapshot(tokens: UInt64 = 1_420_000, hasQuota: Bool = true) -> CombinedUsageSnapshot {
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
            rendererProviderSnapshot(provider: .claude, usedPercent: 68, tokens: tokens, hasQuota: hasQuota),
            rendererProviderSnapshot(provider: .codex, usedPercent: 45, tokens: 500, hasQuota: hasQuota),
        ],
        capturedAt: date,
        systemAvailability: system.availability
    )
}

private func rendererProviderSnapshot(provider: ProviderID, usedPercent: Double, tokens: UInt64, hasQuota: Bool) -> ProviderSnapshot {
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
        quota: hasQuota
            ? QuotaSnapshot(windows: [try! QuotaWindow(id: "window", title: "Window", usedPercent: usedPercent, resetsAt: nil)])
            : nil,
        usageStatus: .fresh,
        quotaStatus: .fresh,
        updatedAt: Date(timeIntervalSince1970: 10_000)
    )
}
