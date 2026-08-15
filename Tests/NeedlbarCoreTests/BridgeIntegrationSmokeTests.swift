import Darwin
import Foundation
import Testing
@testable import NeedlbarCore

@Test func fixtureBridgeSnapshotsMergeAllProvidersAndPreservePartialFailure() async throws {
    let calls = SnapshotCallRecorder()
    let bridge = RustBridge(
        usageCall: {
            calls.recordUsage()
            return makeCString(usageFixture)
        },
        quotaCall: {
            calls.recordQuota()
            return makeCString(quotaFixture)
        },
        free: { pointer in
            guard let pointer else { return }
            UnsafeMutablePointer(mutating: pointer).deallocate()
        }
    )
    let usage = try RustUsageRepository(bridge: bridge).refresh()
    let quota = try RustQuotaRepository(bridge: bridge).refresh()
    let now = try #require(BridgeDecoder.date("2026-08-14T12:00:00Z"))
    let store = ProviderSnapshotStore(now: { now })

    for (provider, snapshot) in usage.snapshots {
        await store.applyUsage(snapshot, for: provider, at: now)
    }
    for (provider, snapshot) in quota.snapshots {
        await store.applyQuota(snapshot, for: provider, at: now)
    }
    for (provider, error) in usage.errors {
        await store.markUsageFailure(
            for: provider,
            status: .error(message: error.message, lastSuccessfulAt: nil),
            at: now
        )
    }

    let snapshots = await store.snapshots()
    #expect(calls.usageCalls == 1)
    #expect(calls.quotaCalls == 1)
    #expect(snapshots.allSatisfy { $0.usage != nil && $0.quota != nil })
    #expect(HeadlineQuotaSelector.mostConstrained(snapshots)?.id == "cursor.plan")

    let codex = try #require(snapshots.first(where: { $0.provider == .codex }))
    #expect(codex.usage?.today.totalTokens == 200)
    #expect(codex.usageStatus == .error(message: "Codex usage source is temporarily unavailable.", lastSuccessfulAt: now))
    #expect(codex.quota?.windows.first?.remainingPercent == 50)

    let claude = try #require(snapshots.first(where: { $0.provider == .claude }))
    let cursor = try #require(snapshots.first(where: { $0.provider == .cursor }))
    #expect(claude.usageStatus == .fresh)
    #expect(cursor.quotaStatus == .fresh)
}

private final class SnapshotCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var usages = 0
    private var quotas = 0

    var usageCalls: Int { lock.withLock { usages } }
    var quotaCalls: Int { lock.withLock { quotas } }

    func recordUsage() { lock.withLock { usages += 1 } }
    func recordQuota() { lock.withLock { quotas += 1 } }
}

private func makeCString(_ value: String) -> UnsafePointer<CChar>? {
    let bytes = Array(value.utf8).map(CChar.init) + [0]
    let pointer = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count)
    pointer.initialize(from: bytes, count: bytes.count)
    return UnsafePointer(pointer)
}

private let usageFixture = """
{
  "schemaVersion": "needlbar.v1", "ok": true, "generatedAt": "2026-08-14T12:00:00Z",
  "data": { "providers": [
    { "provider": "claude", "inputTokens": 100, "outputTokens": 20, "cacheReadTokens": 10, "cacheWriteTokens": 5, "totalTokens": 135, "estimatedCostUSD": 1.25, "today": { "inputTokens": 100, "outputTokens": 20, "cacheReadTokens": 10, "cacheWriteTokens": 5, "totalTokens": 135, "estimatedCostUSD": 1.25 }, "last7Days": { "inputTokens": 100, "outputTokens": 20, "cacheReadTokens": 10, "cacheWriteTokens": 5, "totalTokens": 135, "estimatedCostUSD": 1.25 }, "last30Days": { "inputTokens": 100, "outputTokens": 20, "cacheReadTokens": 10, "cacheWriteTokens": 5, "totalTokens": 135, "estimatedCostUSD": 1.25 } },
    { "provider": "codex", "inputTokens": 150, "outputTokens": 30, "cacheReadTokens": 20, "cacheWriteTokens": 0, "totalTokens": 200, "estimatedCostUSD": 2.5, "today": { "inputTokens": 150, "outputTokens": 30, "cacheReadTokens": 20, "cacheWriteTokens": 0, "totalTokens": 200, "estimatedCostUSD": 2.5 }, "last7Days": { "inputTokens": 150, "outputTokens": 30, "cacheReadTokens": 20, "cacheWriteTokens": 0, "totalTokens": 200, "estimatedCostUSD": 2.5 }, "last30Days": { "inputTokens": 150, "outputTokens": 30, "cacheReadTokens": 20, "cacheWriteTokens": 0, "totalTokens": 200, "estimatedCostUSD": 2.5 } },
    { "provider": "cursor", "inputTokens": 60, "outputTokens": 10, "cacheReadTokens": 0, "cacheWriteTokens": 0, "totalTokens": 70, "estimatedCostUSD": 0.75, "today": { "inputTokens": 60, "outputTokens": 10, "cacheReadTokens": 0, "cacheWriteTokens": 0, "totalTokens": 70, "estimatedCostUSD": 0.75 }, "last7Days": { "inputTokens": 60, "outputTokens": 10, "cacheReadTokens": 0, "cacheWriteTokens": 0, "totalTokens": 70, "estimatedCostUSD": 0.75 }, "last30Days": { "inputTokens": 60, "outputTokens": 10, "cacheReadTokens": 0, "cacheWriteTokens": 0, "totalTokens": 70, "estimatedCostUSD": 0.75 } }
  ] },
  "errors": [{ "provider": "codex", "code": "providerUnavailable", "message": "Codex usage source is temporarily unavailable." }]
}
"""

private let quotaFixture = """
{
  "schemaVersion": "needlbar.v1", "ok": true, "generatedAt": "2026-08-14T12:00:00Z",
  "data": { "providers": [
    { "provider": "claude", "windows": [{ "id": "claude.session", "title": "Session", "usedPercent": 20, "resetsAt": null }] },
    { "provider": "codex", "windows": [{ "id": "codex.primary", "title": "Primary", "usedPercent": 50, "resetsAt": null }] },
    { "provider": "cursor", "windows": [{ "id": "cursor.plan", "title": "Plan", "usedPercent": 90, "resetsAt": null }] }
  ] },
  "errors": []
}
"""
