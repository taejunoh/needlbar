import Foundation
import Testing
@testable import NeedlbarCore

@Test func exportCaptureHasOneClockValueFixedProviderOrderAndIndependentStreamTimes() async throws {
    let captureAt = try #require(BridgeDecoder.date("2026-08-29T12:34:56.000Z"))
    let usageAt = try #require(BridgeDecoder.date("2026-08-29T10:00:00.000Z"))
    let quotaAt = try #require(BridgeDecoder.date("2026-08-29T11:00:00.000Z"))
    let store = ProviderSnapshotStore(now: { captureAt })
    await store.applyUsage(exportUsage(total: 42), for: .claude, at: usageAt)
    await store.applyQuota(try exportQuota(id: "claude.session"), for: .claude, at: quotaAt)
    await store.markUsageFailure(for: .codex, status: .requiresAuthentication, at: quotaAt)

    let capture = await store.captureForExport(exportedAt: captureAt)

    #expect(capture.exportedAt == captureAt)
    #expect(capture.providers.map(\.provider) == [.claude, .codex, .cursor])
    let claude = try #require(capture.providers.first { $0.provider == .claude })
    #expect(claude.usageLastSuccessfulAt == usageAt)
    #expect(claude.quotaLastSuccessfulAt == quotaAt)
    #expect(claude.updatedAt == quotaAt)
    let cursor = try #require(capture.providers.last)
    #expect(cursor.everUpdated == false)
    #expect(cursor.updatedAt == nil)
    #expect(cursor.usageStatus == .unavailable)
    #expect(cursor.quotaStatus == .unavailable)
}

private func exportUsage(total: UInt64) -> UsageSnapshot {
    let period = UsagePeriod(
        inputTokens: total,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheWriteTokens: 0,
        totalTokens: total,
        estimatedCostUSD: Decimal(string: "1.00")!
    )
    return UsageSnapshot(
        inputTokens: total,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheWriteTokens: 0,
        totalTokens: total,
        estimatedCostUSD: Decimal(string: "1.00")!,
        today: period,
        last7Days: period,
        last30Days: period
    )
}

private func exportQuota(id: String) throws -> QuotaSnapshot {
    QuotaSnapshot(windows: [
        try QuotaWindow(id: id, title: "Session", usedPercent: 20, resetsAt: nil)
    ])
}
