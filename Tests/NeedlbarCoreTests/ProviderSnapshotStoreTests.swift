import Foundation
import Testing
@testable import NeedlbarCore

@Test func usageAndQuotaFailuresPreserveIndependentLastKnownGoodValues() async throws {
    let start = try #require(BridgeDecoder.date("2026-08-14T10:00:00Z"))
    let quotaUpdate = try #require(BridgeDecoder.date("2026-08-14T10:01:00Z"))
    let store = ProviderSnapshotStore(now: { start })
    let usage = makeUsage(totalTokens: 100)
    let firstQuota = QuotaSnapshot(windows: [
        try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 20, resetsAt: nil)
    ])
    let refreshedQuota = QuotaSnapshot(windows: [
        try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 30, resetsAt: nil)
    ])

    await store.applyUsage(usage, for: .claude, at: start)
    var snapshot = await store.snapshot(for: .claude)
    #expect(snapshot.usage == usage)
    #expect(snapshot.quota == nil)
    #expect(snapshot.usageStatus == .fresh)
    #expect(snapshot.quotaStatus == .unavailable)

    await store.applyQuota(firstQuota, for: .claude, at: quotaUpdate)
    snapshot = await store.snapshot(for: .claude)
    #expect(snapshot.usage == usage)
    #expect(snapshot.quota == firstQuota)
    #expect(snapshot.usageStatus == .fresh)
    #expect(snapshot.quotaStatus == .fresh)

    await store.markUsageFailure(for: .claude, status: .error(message: "usage source unavailable", lastSuccessfulAt: nil), at: quotaUpdate)
    snapshot = await store.snapshot(for: .claude)
    #expect(snapshot.usage == usage)
    #expect(snapshot.usageStatus == .error(message: "usage source unavailable", lastSuccessfulAt: start))
    #expect(snapshot.quota == firstQuota)
    #expect(snapshot.quotaStatus == .fresh)

    await store.applyQuota(refreshedQuota, for: .claude, at: quotaUpdate)
    snapshot = await store.snapshot(for: .claude)
    #expect(snapshot.usage == usage)
    #expect(snapshot.usageStatus == .error(message: "usage source unavailable", lastSuccessfulAt: start))
    #expect(snapshot.quota == refreshedQuota)
    #expect(snapshot.quotaStatus == .fresh)

    await store.markQuotaFailure(for: .claude, status: .requiresAuthentication, at: quotaUpdate)
    snapshot = await store.snapshot(for: .claude)
    #expect(snapshot.quota == refreshedQuota)
    #expect(snapshot.quotaStatus == .error(message: "Authentication is required.", lastSuccessfulAt: quotaUpdate))
}

@Test func authenticationFailureWithoutKnownQuotaRequiresAuthentication() async throws {
    let date = try #require(BridgeDecoder.date("2026-08-14T10:00:00Z"))
    let store = ProviderSnapshotStore(now: { date })

    await store.markQuotaFailure(for: .codex, status: .requiresAuthentication, at: date)

    let snapshot = await store.snapshot(for: .codex)
    #expect(snapshot.quota == nil)
    #expect(snapshot.quotaStatus == .requiresAuthentication)
    #expect(snapshot.usageStatus == .unavailable)
}

private func makeUsage(totalTokens: UInt64) -> UsageSnapshot {
    let period = UsagePeriod(
        inputTokens: totalTokens,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheWriteTokens: 0,
        totalTokens: totalTokens,
        estimatedCostUSD: Decimal(string: "1.00")!
    )
    return UsageSnapshot(
        inputTokens: totalTokens,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheWriteTokens: 0,
        totalTokens: totalTokens,
        estimatedCostUSD: Decimal(string: "1.00")!,
        today: period,
        last7Days: period,
        last30Days: period
    )
}
