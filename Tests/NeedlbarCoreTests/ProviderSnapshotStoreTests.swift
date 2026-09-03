import Foundation
import Testing
@testable import NeedlbarCore

@Suite("ProviderSnapshotStoreTests")
struct ProviderSnapshotStoreTests {

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

@Test func quotaAlertCaptureIsQuotaOnlyAndCoalescingStillCapturesBothProviders() async throws {
    let date = try #require(BridgeDecoder.date("2026-08-31T12:00:00Z"))
    let store = ProviderSnapshotStore(now: { date })
    let signals = await store.quotaAlertChangeSignals()
    var iterator = signals.makeAsyncIterator()

    await store.applyUsage(makeUsage(totalTokens: 99), for: .claude, at: date)
    let usageOnly = await store.currentQuotaAlertSample(for: .claude)
    #expect(usageOnly.quota == nil)
    #expect(usageOnly.revision == 0)
    await store.applyQuota(try alertQuota(id: "claude.session", usedPercent: 60), for: .claude, at: date)
    await store.applyQuota(try alertQuota(id: "codex.primary", usedPercent: 60), for: .codex, at: date)

    _ = await iterator.next()
    let capture = await store.quotaAlertCapture()
    let claude = try #require(capture.first { $0.provider == .claude })
    let codex = try #require(capture.first { $0.provider == .codex })
    let cursor = try #require(capture.first { $0.provider == .cursor })
    #expect(capture.map(\.provider) == [.claude, .codex, .cursor])
    #expect(claude.revision == 1)
    #expect(codex.revision == 1)
    #expect(cursor.revision == 0)
    #expect(claude.lastSuccessfulAt == date)
    #expect(codex.lastSuccessfulAt == date)
}

@Test func currentQuotaAlertSampleReflectsAFailureAfterItsSuccessfulRevision() async throws {
    let date = try #require(BridgeDecoder.date("2026-08-31T12:00:00Z"))
    let store = ProviderSnapshotStore(now: { date })
    let quota = try alertQuota(id: "claude.session", usedPercent: 60)

    await store.applyQuota(quota, for: .claude, at: date)
    await store.markQuotaFailure(
        for: .claude,
        status: .error(message: "fixture-only failure", lastSuccessfulAt: nil),
        at: date.addingTimeInterval(1)
    )

    let current = await store.currentQuotaAlertSample(for: .claude)
    #expect(current.revision == 1)
    #expect(current.quota == quota)
    #expect(current.status == .error(message: "fixture-only failure", lastSuccessfulAt: date))
}

@Test func applyAPIsKeepUsageAndQuotaIndependentlyLastKnownGood() async throws {
    let now = try #require(BridgeDecoder.date("2026-09-01T12:00:00Z"))
    let store = ProviderSnapshotStore(now: { now })
    await store.applyUsage(makeUsage(totalTokens: 7), for: .claude, at: now)
    await store.applyQuota(try alertQuota(id: "claude.session", usedPercent: 80), for: .claude, at: now)
    await store.markUsageFailure(
        for: .claude,
        status: .error(message: "Fixture usage unavailable.", lastSuccessfulAt: nil),
        at: now
    )
    let snapshot = await store.snapshot(for: .claude)
    #expect(snapshot.usage?.today.totalTokens == 7)
    #expect(snapshot.usageStatus != .fresh)
    #expect(snapshot.quotaStatus == .fresh)
}

@Test func quotaRefreshReplacesFableWindowWhileFailuresRetainItsLastKnownGoodValue() async throws {
    let now = Date(timeIntervalSince1970: 20_000)
    let store = ProviderSnapshotStore(now: { now })
    let base = try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 68, resetsAt: nil)
    let fable = try QuotaWindow(
        id: QuotaWindow.claudeFableWeeklyID,
        title: "Fable weekly",
        usedPercent: 25,
        resetsAt: now
    )

    await store.applyQuota(QuotaSnapshot(windows: [base, fable]), for: .claude, at: now)
    await store.markQuotaFailure(for: .claude, status: .requiresAuthentication, at: now)
    var snapshot = await store.snapshot(for: .claude)
    #expect(snapshot.quota?.windows == [base, fable])
    #expect(snapshot.quotaStatus != .fresh)
    #expect(snapshot.usageStatus == .unavailable)

    await store.applyQuota(QuotaSnapshot(windows: [base]), for: .claude, at: now)
    snapshot = await store.snapshot(for: .claude)
    #expect(snapshot.quota?.windows == [base])
    #expect(snapshot.quotaStatus == .fresh)
    #expect(snapshot.usageStatus == .unavailable)
}
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

private func alertQuota(id: String, usedPercent: Double) throws -> QuotaSnapshot {
    QuotaSnapshot(windows: [
        try QuotaWindow(id: id, title: "fixture title", usedPercent: usedPercent, resetsAt: nil)
    ])
}
