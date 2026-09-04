import AppKit
import Foundation
import SwiftUI
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

@Test func dashboardPresentationUsesFactoryDefaultVisibleModules() {
    let configuration = SystemMonitorConfiguration()
    let presentation = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(),
        configuration: configuration
    )

    #expect(configuration.visibleModules == Set([.cpu, .memory, .ai]))
    #expect(presentation.moduleIDs == [.cpu, .memory, .ai])
    #expect(presentation.cpu.usage == "24%")
    #expect(presentation.memory.used == "7.5 GiB")
}

@Test func dashboardPresentationFiltersConfiguredOrderByVisibleModules() {
    var configuration = SystemMonitorConfiguration()
    configuration.order = [.ai, .network, .cpu, .battery, .memory, .disk]
    configuration.visibleModules = Set([.disk, .ai, .cpu])

    let presentation = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(),
        configuration: configuration
    )

    #expect(presentation.moduleIDs == [.ai, .cpu, .disk])
}

@Test func dashboardPresentationAllowsEveryModuleToBeTurnedOff() {
    var configuration = SystemMonitorConfiguration()
    configuration.visibleModules = []

    let presentation = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(),
        configuration: configuration
    )

    #expect(presentation.moduleIDs.isEmpty)
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

@Test func dashboardFableDetailIsSeparateAndUsesQuotaFreshness() throws {
    let reset = Date(timeIntervalSince1970: 20_000)
    let base = try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 68, resetsAt: nil)
    let fable = try QuotaWindow(
        id: QuotaWindow.claudeFableWeeklyID,
        title: "Fable weekly",
        usedPercent: 100,
        resetsAt: reset
    )
    let presentation = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(claudeQuotaWindows: [base, fable]),
        configuration: SystemMonitorConfiguration()
    )
    let claude = try #require(presentation.ai.first { $0.provider == .claude })

    #expect(claude.value == "32%")
    #expect(claude.fable?.remaining == "0%")
    #expect(claude.fable?.resetCaption == MetricFormatter.reset(reset).map { String(localized: "Resets \($0)") })
    #expect(claude.fable?.freshness == .fresh)
    #expect(presentation.ai.filter { $0.provider != .claude }.allSatisfy { $0.fable == nil })

    let stale = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(
            claudeQuotaStatus: .stale(lastSuccessfulAt: reset),
            claudeQuotaWindows: [base, fable]
        ),
        configuration: SystemMonitorConfiguration()
    )
    #expect(stale.ai.first { $0.provider == .claude }?.fable?.freshness == .stale)
}

@Test func dashboardFableDetailHandlesMissingAndResetlessWindowsWithoutActions() throws {
    let defaultPresentation = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(), configuration: SystemMonitorConfiguration()
    )
    let defaultClaude = try #require(defaultPresentation.ai.first { $0.provider == .claude })
    #expect(defaultClaude.fable?.remaining == "—")
    #expect(defaultClaude.fable?.resetCaption == "Reset unavailable")
    #expect(defaultClaude.fable?.freshness == .unavailable)
    #expect(defaultClaude.action == nil)

    let fableOnly = try QuotaWindow(
        id: QuotaWindow.claudeFableWeeklyID,
        title: "Fable weekly",
        usedPercent: 25,
        resetsAt: nil
    )
    let resetlessPresentation = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(claudeQuotaWindows: [fableOnly]),
        configuration: SystemMonitorConfiguration()
    )
    let resetlessClaude = try #require(resetlessPresentation.ai.first { $0.provider == .claude })
    #expect(resetlessClaude.fable?.remaining == "75%")
    #expect(resetlessClaude.fable?.resetCaption == "Reset unavailable")

    let authenticationRequired = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(
            claudeQuotaStatus: .requiresAuthentication,
            claudeQuotaWindows: [try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 68, resetsAt: nil)]
        ),
        configuration: SystemMonitorConfiguration()
    )
    #expect(authenticationRequired.ai.first { $0.provider == .claude }?.fable?.remaining == "—")
    #expect(authenticationRequired.ai.first { $0.provider == .claude }?.fable?.freshness == .unavailable)

    let noQuotaAuthenticationRequired = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(claudeQuotaStatus: .requiresAuthentication, claudeHasQuota: false),
        configuration: SystemMonitorConfiguration()
    )
    #expect(noQuotaAuthenticationRequired.ai.first { $0.provider == .claude }?.fable?.remaining == "—")
    #expect(noQuotaAuthenticationRequired.ai.first { $0.provider == .claude }?.fable?.freshness == .unavailable)
}

@Test func dashboardFableDetailOnlyAppearsForClaudeRemainingMetric() {
    for metric in [AIProviderDisplayMetric.usage, .cost, .connectionStatus] {
        var configuration = SystemMonitorConfiguration()
        configuration.ai[.claude] = AIProviderDisplayPreference(metric: metric)
        let presentation = SystemDashboardPresentation(
            snapshot: dashboardFixtureSnapshot(), configuration: configuration
        )
        #expect(presentation.ai.first { $0.provider == .claude }?.fable == nil)
    }

    var hiddenClaudeConfiguration = SystemMonitorConfiguration()
    hiddenClaudeConfiguration.ai[.claude] = AIProviderDisplayPreference(isVisible: false, metric: .remaining)
    let hiddenClaude = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(), configuration: hiddenClaudeConfiguration
    )
    #expect(hiddenClaude.ai.contains { $0.provider == .claude } == false)
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

@Test @MainActor func dashboardNaturalHeightTracksEnabledModulesAndProviders() throws {
    let snapshot = dashboardFixtureSnapshot(
        claudeQuotaWindows: [
            try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 68, resetsAt: nil),
            try QuotaWindow(
                id: QuotaWindow.claudeFableWeeklyID,
                title: "Fable weekly",
                usedPercent: 25,
                resetsAt: Date(timeIntervalSince1970: 20_000)
            ),
        ],
        perCoreUsage: Array(repeating: MetricPercentage(50)!, count: 15)
    )
    var fullConfiguration = SystemMonitorConfiguration()
    fullConfiguration.visibleModules = Set(MonitorModuleID.allCases)
    let fullModel = SystemDashboardModel(snapshot: snapshot, configuration: fullConfiguration)
    let fullHeight = try #require(SystemDashboardPopoverMeasurement.naturalHeight(for: fullModel))

    var compactConfiguration = fullConfiguration
    compactConfiguration.visibleModules = Set([.cpu, .memory, .ai])
    compactConfiguration.ai[.codex] = AIProviderDisplayPreference(isVisible: false, metric: .remaining)
    compactConfiguration.ai[.cursor] = AIProviderDisplayPreference(isVisible: false, metric: .remaining)
    let compactModel = SystemDashboardModel(snapshot: snapshot, configuration: compactConfiguration)
    let compactHeight = try #require(SystemDashboardPopoverMeasurement.naturalHeight(for: compactModel))

    #expect(fullHeight > 400)
    #expect(compactHeight < fullHeight)
}

@Test func dashboardReadabilitySuppressesNormalFreshnessAndPreservesActionStates() {
    #expect(DashboardReadabilityPolicy.systemStatus(.fresh) == nil)
    #expect(DashboardReadabilityPolicy.systemStatus(.stale) == "Stale")
    #expect(DashboardReadabilityPolicy.systemStatus(.unavailable) == nil)

    #expect(DashboardReadabilityPolicy.providerStatus(usage: .fresh, quota: .fresh) == nil)
    #expect(DashboardReadabilityPolicy.providerStatus(usage: .stale, quota: .fresh) == "Usage Stale")
    #expect(DashboardReadabilityPolicy.providerStatus(usage: .fresh, quota: .requiresAuthentication) == "Quota Authentication required")
    #expect(DashboardReadabilityPolicy.providerStatus(usage: .error, quota: .fresh) == "Usage Error")
    #expect(DashboardReadabilityPolicy.providerStatus(usage: .unavailable, quota: .unavailable) == nil)
}

@Test func dashboardReadabilityPreservesIndependentProviderStatusProvenance() {
    #expect(DashboardReadabilityPolicy.providerStatus(usage: .stale, quota: .stale) == "Usage Stale · Quota Stale")
    #expect(DashboardReadabilityPolicy.providerStatus(usage: .error, quota: .requiresAuthentication) == "Usage Error · Quota Authentication required")
    #expect(DashboardReadabilityPolicy.providerStatus(usage: .requiresAuthentication, quota: .error) == "Usage Authentication required · Quota Error")
}

@Test func dashboardReadabilityKeepsFullValueForHelpAndAccessibility() {
    let address = "2600:1017:b82b:aeb6:819c:69d2:12ef:1fdd"
    let descriptor = DashboardMetricValue(address, truncation: .middle)

    #expect(descriptor.fullValue == address)
    #expect(descriptor.helpValue == address)
    #expect(descriptor.accessibilityValue == address)
    #expect(descriptor.truncation == .middle)
}

@Test func dashboardReadabilityUsesTailTruncationForOrdinaryText() {
    let descriptor = DashboardMetricValue("Authentication required", truncation: .tail)

    #expect(descriptor.truncation == .tail)
    #expect(descriptor.fullValue == "Authentication required")
}

@Test @MainActor func dashboardVisibleViewUsesMeasuredOrScreenLimitedHeight() throws {
    var configuration = SystemMonitorConfiguration()
    configuration.visibleModules = Set(MonitorModuleID.allCases)
    let model = SystemDashboardModel(
        snapshot: dashboardFixtureSnapshot(
            claudeQuotaWindows: [
                try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 68, resetsAt: nil),
                try QuotaWindow(
                    id: QuotaWindow.claudeFableWeeklyID,
                    title: "Fable weekly",
                    usedPercent: 25,
                    resetsAt: Date(timeIntervalSince1970: 20_000)
                ),
            ]
        ),
        configuration: configuration
    )
    let naturalHeight = try #require(SystemDashboardPopoverMeasurement.naturalHeight(for: model))
    let tallHeight = SystemDashboardPanelSizing.height(
        naturalContentHeight: naturalHeight,
        visibleScreenHeight: naturalHeight + SystemDashboardPanelSizing.verticalScreenAllowanceInset
    )
    let shortHeight = SystemDashboardPanelSizing.height(
        naturalContentHeight: naturalHeight,
        visibleScreenHeight: 424
    )
    let tall = NSHostingController(
        rootView: SystemDashboardPopoverView(model: model, height: tallHeight)
    )
    let short = NSHostingController(
        rootView: SystemDashboardPopoverView(model: model, height: shortHeight)
    )

    #expect(tall.view.fittingSize == NSSize(width: 340, height: tallHeight))
    #expect(tallHeight == naturalHeight)
    #expect(short.view.fittingSize == NSSize(width: 340, height: 400))
}

@Test @MainActor func dashboardCompatibilityMaximumHeightPreservesLegacyClamp() {
    let model = SystemDashboardModel(
        snapshot: dashboardFixtureSnapshot(),
        configuration: SystemMonitorConfiguration()
    )
    let tall = NSHostingController(
        rootView: SystemDashboardPopoverView(model: model, maximumHeight: 900)
    )
    let short = NSHostingController(
        rootView: SystemDashboardPopoverView(model: model, maximumHeight: 120)
    )

    #expect(tall.view.fittingSize == NSSize(width: 340, height: 680))
    #expect(short.view.fittingSize == NSSize(width: 340, height: 180))
}

@Test @MainActor func dashboardReadabilityPreservesConfiguredOrderAndIPPrivacy() {
    var configuration = SystemMonitorConfiguration()
    configuration.order = [.ai, .network, .cpu, .battery, .memory, .disk]
    configuration.visibleModules = Set(MonitorModuleID.allCases)
    configuration.localIPEnabled = false
    configuration.publicIPEnabled = false

    let presentation = SystemDashboardPresentation(snapshot: dashboardFixtureSnapshot(), configuration: configuration)

    #expect(presentation.moduleIDs == configuration.order)
    #expect(presentation.network.primaryLocalAddress == nil)
    #expect(presentation.network.additionalLocalAddresses.isEmpty)
    #expect(presentation.network.publicIPAddress == nil)
}

@Test func dashboardReadabilityPreservesSeparateFableSemantics() throws {
    let windows = [
        try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 68, resetsAt: nil),
        try QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "Fable weekly", usedPercent: 100, resetsAt: Date(timeIntervalSince1970: 20_000))
    ]
    let presentation = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(claudeQuotaWindows: windows),
        configuration: SystemMonitorConfiguration()
    )
    let claude = try #require(presentation.ai.first { $0.provider == .claude })

    #expect(claude.value == "32%")
    #expect(claude.fable?.remaining == "0%")
    #expect(presentation.ai.filter { $0.provider != .claude }.allSatisfy { $0.fable == nil })
}

@Test @MainActor func dashboardReadabilityFittingIsStableAcrossLiveNumericChanges() throws {
    let configuration = SystemMonitorConfiguration()
    let first = dashboardFixtureSnapshot(capturedAt: Date(timeIntervalSince1970: 10_000))
    let second = dashboardFixtureSnapshot(capturedAt: Date(timeIntervalSince1970: 10_001), todayTokens: 1_683_150_000)
    let firstModel = SystemDashboardModel(snapshot: first, configuration: configuration)
    let secondModel = SystemDashboardModel(snapshot: second, configuration: configuration)
    let firstHeight = try #require(SystemDashboardPopoverMeasurement.naturalHeight(for: firstModel))
    let secondHeight = try #require(SystemDashboardPopoverMeasurement.naturalHeight(for: secondModel))
    let firstView = NSHostingController(rootView: SystemDashboardPopoverView(model: firstModel, height: firstHeight))
    let secondView = NSHostingController(rootView: SystemDashboardPopoverView(model: secondModel, height: firstHeight))

    #expect(firstHeight == secondHeight)
    #expect(firstView.view.fittingSize == secondView.view.fittingSize)
}

@Test @MainActor func dashboardReadabilityKeepsSizeStableAcrossAppearances() throws {
    let model = SystemDashboardModel(snapshot: dashboardFixtureSnapshot(), configuration: SystemMonitorConfiguration())
    let height = try #require(SystemDashboardPopoverMeasurement.naturalHeight(for: model))
    let light = NSHostingController(rootView: SystemDashboardPopoverView(model: model, height: height))
    let dark = NSHostingController(rootView: SystemDashboardPopoverView(model: model, height: height))
    light.view.appearance = NSAppearance(named: .aqua)
    dark.view.appearance = NSAppearance(named: .darkAqua)

    #expect(light.view.fittingSize == dark.view.fittingSize)
    #expect(light.view.fittingSize.width == 340)
    #expect(dark.view.fittingSize.width == 340)
}

@Test func dashboardReadabilityPreservesUnavailableAndStalePresentation() {
    let stale = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(
            networkAvailability: .stale(lastSuccessfulAt: Date(timeIntervalSince1970: 9_999)),
            diskAvailability: .stale(lastSuccessfulAt: Date(timeIntervalSince1970: 9_999)),
            claudeQuotaStatus: .requiresAuthentication,
            cursorQuotaStatus: .error(message: "refresh failed", lastSuccessfulAt: nil),
            cursorHasQuota: false
        ),
        configuration: SystemMonitorConfiguration()
    )

    #expect(stale.network.download == "2.0 KB/s")
    #expect(stale.disk.read == "10 B/s")
    #expect(stale.ai.first { $0.provider == .claude }?.value == "32%")
    #expect(stale.ai.first { $0.provider == .cursor }?.value == "—")
    #expect(DashboardReadabilityPolicy.systemStatus(stale.network.freshness) == "Stale")
    #expect(DashboardReadabilityPolicy.providerStatus(
        usage: stale.ai.first { $0.provider == .claude }!.usageStatus,
        quota: stale.ai.first { $0.provider == .claude }!.quotaStatus
    ) == "Quota Authentication required")
}

private func dashboardFixtureSnapshot(
    capturedAt date: Date = Date(timeIntervalSince1970: 10_000),
    networkAvailability: MetricAvailability? = nil,
    diskAvailability: MetricAvailability? = nil,
    claudeQuotaStatus: DataStatus? = nil,
    claudeHasQuota: Bool = true,
    claudeQuotaWindows: [QuotaWindow]? = nil,
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
    let defaultClaudeQuota = QuotaSnapshot(windows: [
        try! QuotaWindow(id: "window", title: "Window", usedPercent: 68, resetsAt: nil)
    ])
    let providers = ProviderID.allCases.map { provider in
        let quota: QuotaSnapshot?
        if provider == .claude {
            quota = claudeHasQuota
                ? QuotaSnapshot(windows: claudeQuotaWindows ?? defaultClaudeQuota.windows)
                : nil
        } else if provider == .cursor && !cursorHasQuota {
            quota = nil
        } else {
            quota = QuotaSnapshot(windows: [
                try! QuotaWindow(id: "window", title: "Window", usedPercent: provider == .codex ? 45 : 68, resetsAt: nil)
            ])
        }
        return ProviderSnapshot(
            provider: provider,
            usage: UsageSnapshot(
                inputTokens: todayTokens, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0,
                totalTokens: todayTokens, estimatedCostUSD: Decimal(string: "7.81")!, today: period,
                last7Days: period, last30Days: period
            ),
            quota: quota,
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
