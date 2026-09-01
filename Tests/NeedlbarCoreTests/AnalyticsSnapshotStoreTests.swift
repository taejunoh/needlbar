import Foundation
import Testing
@testable import NeedlbarCore

private struct GateRepository: AnalyticsRepository {
    let result: Result<AnalyticsSnapshot, Error>
    let gate: Gate?
    let counter: Counter

    func refreshAnalytics() async throws -> AnalyticsSnapshot {
        await counter.increment()
        if let gate { await gate.wait() }
        return try result.get()
    }
}

private actor Gate {
    var released = false
    var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async { if released { return }; await withCheckedContinuation { waiters.append($0) } }
    func release() { released = true; waiters.forEach { $0.resume() }; waiters.removeAll() }
}

private actor Counter {
    var value = 0
    func increment() { value += 1 }
    func read() -> Int { value }
}

private struct FailingError: Error, Sendable {}

private func snapshot() -> AnalyticsSnapshot {
    try! AnalyticsBridgeDecoder().decodeSnapshot(Data("""
    {"schemaVersion":"needlbar.analytics.v1","ok":true,"generatedAt":"2026-09-01T12:00:00.000Z","data":{"analysisRange":{"start":"2026-08-02T12:00:00.000Z","end":"2026-09-01T12:00:00.000Z"},"repositories":[],"unattributed":{"usage":{"inputTokens":"0","outputTokens":"0","cacheReadTokens":"0","cacheWriteTokens":"0","reasoningTokens":"0","totalTokens":"0","estimatedCostUSD":"0"},"fragments":0,"reasons":{}},"coverage":{"attributedFragments":0,"unattributedFragments":0,"reasons":{}},"errors":[]},"errors":[]}
    """.utf8))
}

@Test func concurrentRefreshesShareOneRepositoryCallAndPublishFreshOnce() async {
    let gate = Gate(); let counter = Counter(); let expected = snapshot()
    let repository = GateRepository(result: .success(expected), gate: gate, counter: counter)
    let store = AnalyticsSnapshotStore()
    async let first = store.refresh(using: repository)
    async let second = store.refresh(using: repository)
    await gate.release()
    #expect(await first == expected)
    #expect(await second == expected)
    #expect(await counter.read() == 1)
    #expect(await store.state == .fresh(expected))
}

@Test func failedRefreshRetainsLastGoodAsStaleAndInitialFailureIsUnavailable() async {
    let good = snapshot(); let counter = Counter()
    let store = AnalyticsSnapshotStore()
    _ = await store.refresh(using: GateRepository(result: .success(good), gate: nil, counter: counter))
    _ = await store.refresh(using: GateRepository(result: .failure(FailingError()), gate: nil, counter: counter))
    #expect(await store.state == .stale(good))
    let empty = AnalyticsSnapshotStore()
    _ = await empty.refresh(using: GateRepository(result: .failure(FailingError()), gate: nil, counter: Counter()))
    #expect(await empty.state == .unavailable)
}

@Test func cancelledWaiterDoesNotCancelSharedAnalyticsTask() async {
    let gate = Gate(); let counter = Counter(); let expected = snapshot()
    let repository = GateRepository(result: .success(expected), gate: gate, counter: counter)
    let store = AnalyticsSnapshotStore()
    let first = Task { await store.refresh(using: repository) }
    await Task.yield()
    let cancelled = Task { await store.refresh(using: repository) }
    cancelled.cancel()
    await gate.release()
    _ = await cancelled.result
    #expect(await first.value == expected)
    #expect(await counter.read() == 1)
}
