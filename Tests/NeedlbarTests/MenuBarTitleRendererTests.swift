import Foundation
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

@Test func overviewQuotaTitleUsesTheLowestEnabledProviderQuota() throws {
    let defaults = freshDefaults()
    let configuration = ModuleConfiguration(defaults: defaults)
    configuration.claude = ModuleSettings(isEnabled: true, metric: .quotaRemaining)
    configuration.codex = ModuleSettings(isEnabled: true, metric: .quotaRemaining)

    let title = MenuBarTitleRenderer.render(
        module: .overview,
        snapshot: nil,
        allSnapshots: [
            snapshot(provider: .claude, usedPercent: 68),
            snapshot(provider: .codex, usedPercent: 81),
            snapshot(provider: .cursor, usedPercent: 36),
        ],
        configuration: configuration
    )

    #expect(title == "AI 19%")
}

@Test func providerTitleUsesTheConfiguredTokensOrCostMetric() throws {
    let defaults = freshDefaults()
    let configuration = ModuleConfiguration(defaults: defaults)
    let providerSnapshot = snapshot(
        provider: .claude,
        usedPercent: 68,
        tokens: 1_420_000,
        cost: Decimal(string: "7.81")!
    )

    configuration.claude = ModuleSettings(isEnabled: true, metric: .tokensToday)
    #expect(MenuBarTitleRenderer.render(
        module: .claude,
        snapshot: providerSnapshot,
        allSnapshots: [providerSnapshot],
        configuration: configuration
    ) == "Claude 1.42M")

    configuration.claude = ModuleSettings(isEnabled: true, metric: .costToday)
    #expect(MenuBarTitleRenderer.render(
        module: .claude,
        snapshot: providerSnapshot,
        allSnapshots: [providerSnapshot],
        configuration: configuration
    ) == "Claude $7.81")
}

@Test func unavailableDataUsesANeutralTitleInsteadOfZero() {
    let title = MenuBarTitleRenderer.render(
        module: .claude,
        snapshot: nil,
        allSnapshots: [],
        configuration: ModuleConfiguration(defaults: freshDefaults())
    )

    #expect(title == "Claude —")
}

private func freshDefaults() -> UserDefaults {
    let suiteName = "MenuBarTitleRendererTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private func snapshot(
    provider: ProviderID,
    usedPercent: Double,
    tokens: UInt64 = 0,
    cost: Decimal = 0
) -> ProviderSnapshot {
    let period = UsagePeriod(
        inputTokens: tokens,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheWriteTokens: 0,
        totalTokens: tokens,
        estimatedCostUSD: cost
    )
    let usage = UsageSnapshot(
        inputTokens: tokens,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheWriteTokens: 0,
        totalTokens: tokens,
        estimatedCostUSD: cost,
        today: period,
        last7Days: period,
        last30Days: period
    )
    return ProviderSnapshot(
        provider: provider,
        usage: usage,
        quota: QuotaSnapshot(windows: [
            try! QuotaWindow(id: "\(provider.rawValue).window", title: "Window", usedPercent: usedPercent, resetsAt: nil),
        ]),
        usageStatus: .fresh,
        quotaStatus: .fresh,
        updatedAt: .now
    )
}
