import AppKit
import Foundation
import SwiftUI
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
    #expect(presentation.memory.used == "7.5 GiB")
}

@Test func dashboardPresentationIncludesNetworkSpeedAndOptionalIPValues() {
    var configuration = SystemMonitorConfiguration()
    configuration.publicIPEnabled = false
    configuration.localIPEnabled = true
    let presentation = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(),
        configuration: configuration
    )

    #expect(presentation.network.upload == "1.0 KB/s")
    #expect(presentation.network.download == "2.0 KB/s")
    #expect(presentation.network.localIPAddresses == ["192.0.2.10"])
    #expect(presentation.network.publicIPAddress == nil)
}

@Test func dashboardPresentationWithholdsLocalIPUntilItsSeparateOptInIsEnabled() {
    var configuration = SystemMonitorConfiguration()
    configuration.localIPEnabled = false
    var presentation = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(),
        configuration: configuration
    )

    #expect(presentation.network.primaryLocalAddress == nil)
    #expect(presentation.network.additionalLocalAddresses.isEmpty)

    configuration.localIPEnabled = true
    presentation = SystemDashboardPresentation(snapshot: dashboardFixtureSnapshot(), configuration: configuration)
    #expect(presentation.network.primaryLocalAddress == "192.0.2.10")
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

@Test func dashboardPresentationDefaultsToRemainingEvenWhenTokenUsageExists() {
    let presentation = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(), configuration: SystemMonitorConfiguration()
    )

    #expect(presentation.ai.first(where: { $0.provider == .claude })?.value == "32%")
    #expect(presentation.ai.first(where: { $0.provider == .claude })?.caption == "Most constrained quota remaining")
}

@Test func dashboardPresentationDoesNotFallBackToTokensWhenDefaultRemainingHasNoQuota() {
    let presentation = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(claudeHasQuota: false), configuration: SystemMonitorConfiguration()
    )

    #expect(presentation.ai.first(where: { $0.provider == .claude })?.value == "—")
}

@Test func dashboardPresentationUsesBillionsForLargeTokenCounts() {
    var configuration = SystemMonitorConfiguration()
    configuration.ai[.claude] = AIProviderDisplayPreference(metric: .usage)
    let presentation = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(todayTokens: 1_683_150_000), configuration: configuration
    )

    #expect(presentation.ai.first(where: { $0.provider == .claude })?.value == "1.68B")
}

@Test func dashboardPresentationOffersOnlyExistingProviderAuthenticationActions() {
    let presentation = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(
            claudeQuotaStatus: .requiresAuthentication,
            cursorQuotaStatus: .stale(lastSuccessfulAt: Date(timeIntervalSince1970: 9_999)),
            cursorHasQuota: false
        ),
        configuration: SystemMonitorConfiguration()
    )

    #expect(presentation.ai.first(where: { $0.provider == .claude })?.action == .browserLogin(title: "Sign in with Claude"))
    #expect(presentation.ai.first(where: { $0.provider == .cursor })?.action == .openCursorSpending(title: "Open Cursor Spending"))
    #expect(presentation.ai.first(where: { $0.provider == .codex })?.action == nil)
}

@Test @MainActor func dashboardModelKeepsOnlySixtyFreshSystemSamplesAndSkipsProviderOnlyUpdates() {
    let configuration = SystemMonitorConfiguration()
    let start = Date(timeIntervalSince1970: 10_000)
    let model = SystemDashboardModel(
        snapshot: dashboardFixtureSnapshot(capturedAt: start),
        configuration: configuration
    )

    model.update(
        snapshot: dashboardFixtureSnapshot(capturedAt: start, providerUpdatedAt: start.addingTimeInterval(1)),
        configuration: configuration
    )
    #expect(model.history.network.count == 1)

    for second in 1...60 {
        model.update(
            snapshot: dashboardFixtureSnapshot(capturedAt: start.addingTimeInterval(Double(second))),
            configuration: configuration
        )
    }

    #expect(model.history.network.count == 60)
    #expect(model.history.network.first?.capturedAt == start.addingTimeInterval(1))
    #expect(model.history.network.last?.uploadBytesPerSecond == 1_000)
    #expect(model.history.network.last?.downloadBytesPerSecond == 2_000)
    #expect(model.history.disk.last?.readBytesPerSecond == 10)
    #expect(model.history.disk.last?.writeBytesPerSecond == 20)
}

@Test @MainActor func dashboardModelRecordsAVisualGapForStaleSystemData() {
    let configuration = SystemMonitorConfiguration()
    let start = Date(timeIntervalSince1970: 10_000)
    let model = SystemDashboardModel(
        snapshot: dashboardFixtureSnapshot(capturedAt: start),
        configuration: configuration
    )

    model.update(
        snapshot: dashboardFixtureSnapshot(
            capturedAt: start.addingTimeInterval(1),
            networkAvailability: .stale(lastSuccessfulAt: start),
            diskAvailability: .stale(lastSuccessfulAt: start)
        ),
        configuration: configuration
    )

    #expect(model.history.network.count == 2)
    #expect(model.history.network.last?.uploadBytesPerSecond == nil)
    #expect(model.history.network.last?.downloadBytesPerSecond == nil)
    #expect(model.history.disk.last?.readBytesPerSecond == nil)
    #expect(model.history.disk.last?.writeBytesPerSecond == nil)
}

@Test @MainActor func dashboardPopoverFittingSizeCapsTallCoreFixturesAndRespectsSmallerHeight() {
    let snapshot = dashboardFixtureSnapshot(
        perCoreUsage: Array(repeating: MetricPercentage(50)!, count: 15)
    )
    let model = SystemDashboardModel(snapshot: snapshot, configuration: SystemMonitorConfiguration())
    let tallController = NSHostingController(
        rootView: SystemDashboardPopoverView(model: model, maximumHeight: 1_400)
    )
    let shortController = NSHostingController(
        rootView: SystemDashboardPopoverView(model: model, maximumHeight: 400)
    )

    #expect(tallController.view.fittingSize.width == 360)
    #expect(tallController.view.fittingSize.height <= 680)
    #expect(shortController.view.fittingSize.width == 360)
    #expect(shortController.view.fittingSize.height == 400)
}

private func dashboardFixtureSnapshot(
    capturedAt date: Date = Date(timeIntervalSince1970: 10_000),
    networkAvailability: MetricAvailability? = nil,
    diskAvailability: MetricAvailability? = nil,
    claudeQuotaStatus: DataStatus? = nil,
    claudeHasQuota: Bool = true,
    cursorQuotaStatus: DataStatus? = nil,
    cursorHasQuota: Bool = true,
    providerUpdatedAt: Date? = nil,
    perCoreUsage: [MetricPercentage] = [],
    todayTokens: UInt64 = 1_420_000
) -> CombinedUsageSnapshot {
    let system = SystemMetricsSnapshot(
        capturedAt: date,
        cpu: .init(totalUsage: MetricPercentage(24), perCoreUsage: perCoreUsage),
        memory: .init(usedBytes: 8_000_000_000, freeBytes: 2_000_000_000, swapUsedBytes: 0, pressure: "normal"),
        disks: [.init(name: "Macintosh HD", usedBytes: 100, freeBytes: 200, readBytesPerSecond: 10, writeBytesPerSecond: 20)],
        network: .init(uploadBytesPerSecond: 1_000, downloadBytesPerSecond: 2_000, localIPAddresses: ["192.0.2.10"], publicIPAddress: nil),
        battery: .init(level: MetricPercentage(100), isCharging: true, health: MetricPercentage(96)),
        availability: Dictionary(uniqueKeysWithValues: MonitorModuleID.allCases.map { module in
            let availability: MetricAvailability
            switch module {
            case .network:
                availability = networkAvailability ?? .fresh(capturedAt: date)
            case .disk:
                availability = diskAvailability ?? .fresh(capturedAt: date)
            default:
                availability = .fresh(capturedAt: date)
            }
            return (module, availability)
        })
    )
    let period = UsagePeriod(
        inputTokens: todayTokens, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0,
        totalTokens: todayTokens, estimatedCostUSD: Decimal(string: "7.81")!
    )
    let providers = ProviderID.allCases.map { provider in
        ProviderSnapshot(
            provider: provider,
            usage: UsageSnapshot(
                inputTokens: todayTokens, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0,
                totalTokens: todayTokens, estimatedCostUSD: Decimal(string: "7.81")!, today: period,
                last7Days: period, last30Days: period
            ),
            quota: (provider == .claude && !claudeHasQuota) || (provider == .cursor && !cursorHasQuota)
                ? nil
                : QuotaSnapshot(windows: [try! QuotaWindow(id: "window", title: "Window", usedPercent: provider == .codex ? 45 : 68, resetsAt: nil)]),
            usageStatus: .fresh,
            quotaStatus: provider == .claude ? (claudeQuotaStatus ?? .fresh) : provider == .cursor ? (cursorQuotaStatus ?? .fresh) : .fresh,
            updatedAt: providerUpdatedAt ?? date
        )
    }
    return CombinedUsageSnapshot(
        system: system,
        providers: providers,
        capturedAt: date,
        systemAvailability: system.availability
    )
}
