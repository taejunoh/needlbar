import Foundation
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

@Test func freshUsageAndQuotaRenderKnownValues() throws {
    let presentation = ProviderPopoverPresentation(snapshot: snapshot(
        provider: .claude,
        usage: usage(totalTokens: 1_420, cacheWriteTokens: 80),
        quota: quota(usedPercent: 35),
        usageStatus: .fresh,
        quotaStatus: .fresh
    ))

    #expect(presentation.tokensToday == "1.42K")
    #expect(presentation.estimatedCostToday == "$2.50")
    #expect(presentation.quotaWindows.count == 1)
    #expect(presentation.usageFreshness == .fresh)
    #expect(presentation.quotaFreshness == .fresh)
    #expect(presentation.cacheWriteTokens == "80")
}

@Test func freshUsageWithAuthenticationRequiredQuotaDoesNotInventAQuotaValue() {
    let presentation = ProviderPopoverPresentation(snapshot: snapshot(
        provider: .codex,
        usage: usage(totalTokens: 500, cacheWriteTokens: 0),
        quota: nil,
        usageStatus: .fresh,
        quotaStatus: .requiresAuthentication
    ))

    #expect(presentation.tokensToday == "500")
    #expect(presentation.quotaWindows.isEmpty)
    #expect(presentation.headlineQuotaRemaining == nil)
    #expect(presentation.requiresProviderSignIn)
    #expect(presentation.cacheWriteTokens == "0")
}

@Test func staleUsageKeepsTheLastKnownUsageWhileFreshQuotaRendersNormally() throws {
    let presentation = ProviderPopoverPresentation(snapshot: snapshot(
        provider: .cursor,
        usage: usage(totalTokens: 900, cacheWriteTokens: 10),
        quota: quota(usedPercent: 74),
        usageStatus: .stale(lastSuccessfulAt: .distantPast),
        quotaStatus: .fresh
    ))

    #expect(presentation.tokensToday == "900")
    #expect(presentation.headlineQuotaRemaining == "26%")
    #expect(presentation.usageFreshness == .stale)
    #expect(presentation.quotaFreshness == .fresh)
}

@Test func unavailableStreamsRemainAbsentInsteadOfDisplayingZero() {
    let presentation = ProviderPopoverPresentation(snapshot: snapshot(
        provider: .claude,
        usage: nil,
        quota: nil,
        usageStatus: .unavailable,
        quotaStatus: .unavailable
    ))

    #expect(presentation.tokensToday == nil)
    #expect(presentation.estimatedCostToday == nil)
    #expect(presentation.cacheWriteTokens == nil)
    #expect(presentation.headlineQuotaRemaining == nil)
    #expect(presentation.quotaWindows.isEmpty)
}

@Test func overviewAggregatesOnlyRealDailySeriesByDate() {
    let overview = OverviewPopoverPresentation(
        snapshots: [
            snapshot(provider: .claude, usage: usage(totalTokens: 100), quota: nil, usageStatus: .fresh, quotaStatus: .unavailable),
            snapshot(provider: .codex, usage: usage(totalTokens: 50), quota: nil, usageStatus: .fresh, quotaStatus: .unavailable),
        ],
        dailyUsage: [
            .init(provider: .claude, date: "2026-08-10", totalTokens: 20),
            .init(provider: .codex, date: "2026-08-10", totalTokens: 30),
            .init(provider: .claude, date: "2026-08-11", totalTokens: 50),
        ]
    )

    #expect(overview.tokensToday == "150")
    #expect(overview.sevenDayTokens == [50, 50])
}

@Test func overviewLeavesTheChartUnavailableWhenNoDailySeriesExists() {
    let overview = OverviewPopoverPresentation(
        snapshots: [snapshot(provider: .claude, usage: usage(totalTokens: 100), quota: nil, usageStatus: .fresh, quotaStatus: .unavailable)],
        dailyUsage: []
    )

    #expect(overview.sevenDayTokens == nil)
}

@Test func overviewHeadlineQuotaUsesOnlyEnabledProviderModules() throws {
    let overview = OverviewPopoverPresentation(
        snapshots: [
            snapshot(provider: .claude, usage: nil, quota: quota(usedPercent: 20), usageStatus: .unavailable, quotaStatus: .fresh),
            snapshot(provider: .cursor, usage: nil, quota: quota(usedPercent: 90), usageStatus: .unavailable, quotaStatus: .fresh),
        ],
        dailyUsage: [],
        enabledProviders: [.claude]
    )

    #expect(overview.headlineQuotaRemaining == "80%")
}

@MainActor
@Test func cursorConnectClearsTransientInputBeforeTheOffMainImporterFinishes() async {
    let importer = SuspendedCursorSessionImporter()
    let controller = CursorSessionConnectionController(
        importer: { token in await importer.importSession(token) },
        clearer: { true }
    )
    var transientInput = "cursor-secret-test-token"
    var completion: Bool?

    controller.connect(
        transientInput,
        clearInput: { transientInput = "" },
        completion: { completion = $0 }
    )

    #expect(transientInput.isEmpty)
    #expect(await eventuallyOnMainActor { await importer.receivedToken() != nil })

    var mainActorWasResponsive = false
    Task { @MainActor in mainActorWasResponsive = true }
    await Task.yield()
    #expect(mainActorWasResponsive)
    #expect(completion == nil)

    await importer.complete(with: true)
    #expect(await eventuallyOnMainActor { completion == true })
}

private func snapshot(
    provider: ProviderID,
    usage: UsageSnapshot?,
    quota: QuotaSnapshot?,
    usageStatus: DataStatus,
    quotaStatus: DataStatus
) -> ProviderSnapshot {
    ProviderSnapshot(
        provider: provider,
        usage: usage,
        quota: quota,
        usageStatus: usageStatus,
        quotaStatus: quotaStatus,
        updatedAt: .now
    )
}

private func usage(totalTokens: UInt64, cacheWriteTokens: UInt64 = 0) -> UsageSnapshot {
    let today = UsagePeriod(
        inputTokens: totalTokens,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheWriteTokens: cacheWriteTokens,
        totalTokens: totalTokens,
        estimatedCostUSD: Decimal(string: "2.50")!
    )
    return UsageSnapshot(
        inputTokens: totalTokens,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheWriteTokens: cacheWriteTokens,
        totalTokens: totalTokens,
        estimatedCostUSD: Decimal(string: "2.50")!,
        today: today,
        last7Days: today,
        last30Days: today
    )
}

private func quota(usedPercent: Double) -> QuotaSnapshot {
    QuotaSnapshot(windows: [
        try! QuotaWindow(id: "window", title: "Plan", usedPercent: usedPercent, resetsAt: nil),
    ])
}

@MainActor
private func eventuallyOnMainActor(
    _ condition: @escaping @MainActor () async -> Bool
) async -> Bool {
    for _ in 0..<100 {
        if await condition() { return true }
        await Task.yield()
    }
    return false
}

private actor SuspendedCursorSessionImporter {
    private var token: String?
    private var continuation: CheckedContinuation<Bool, Never>?

    func importSession(_ token: String) async -> Bool {
        self.token = token
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func receivedToken() -> String? {
        token
    }

    func complete(with result: Bool) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
