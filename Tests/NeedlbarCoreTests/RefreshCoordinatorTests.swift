import Foundation
import Testing
@testable import NeedlbarCore

@Test func popoverDoesNotRefreshQuotaBeforeSixtySeconds() async throws {
    let now = try #require(BridgeDecoder.date("2026-08-14T10:00:30Z"))
    let clock = ManualClock(now: now)
    let usage = UsageRefreshSpy(result: .init(snapshots: [:], errors: [:]))
    let quota = QuotaRefreshSpy(result: .init(snapshots: [:], errors: [:]))
    let coordinator = RefreshCoordinator(
        usageRepository: usage,
        quotaRepository: quota,
        store: ProviderSnapshotStore(),
        clock: clock,
        lastQuotaSuccessfulAt: now.addingTimeInterval(-30)
    )

    await coordinator.popoverOpened()
    await Task.yield()

    #expect(quota.callCount == 0)
    await coordinator.stop()
}

@Test func popoverRefreshesQuotaAfterSixtySeconds() async throws {
    let now = try #require(BridgeDecoder.date("2026-08-14T10:01:01Z"))
    let clock = ManualClock(now: now)
    let usage = UsageRefreshSpy(result: .init(snapshots: [:], errors: [:]))
    let quota = QuotaRefreshSpy(result: .init(snapshots: [:], errors: [:]))
    let coordinator = RefreshCoordinator(
        usageRepository: usage,
        quotaRepository: quota,
        store: ProviderSnapshotStore(),
        clock: clock,
        lastQuotaSuccessfulAt: now.addingTimeInterval(-61)
    )

    await coordinator.popoverOpened()
    await eventually { quota.callCount == 1 }

    #expect(quota.callCount == 1)
    await coordinator.stop()
}

@Test func quotaErrorsWithoutAnyValuesDoNotSuppressTheNextPopoverRetry() async throws {
    let now = try #require(BridgeDecoder.date("2026-08-14T10:01:01Z"))
    let quota = QuotaRefreshSpy(result: .init(
        snapshots: [:],
        errors: [.claude: BridgeError(provider: "claude", code: "requiresAuthentication", message: "sign in", action: nil)]
    ))
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota,
        store: ProviderSnapshotStore(),
        clock: ManualClock(now: now)
    )

    await coordinator.popoverOpened()
    await eventually { quota.callCount == 1 }
    await coordinator.popoverOpened()
    await eventually { quota.callCount == 2 }

    #expect(quota.callCount == 2)
    await coordinator.stop()
}

@Test func manualRefreshMergesAnInflightUsageRequestBeforeForcedNextCycle() async throws {
    let now = try #require(BridgeDecoder.date("2026-08-14T10:00:00Z"))
    let clock = ManualClock(now: now)
    let usage = BlockingUsageRepository()
    let quota = QuotaRefreshSpy(result: .init(snapshots: [:], errors: [:]))
    let coordinator = RefreshCoordinator(
        usageRepository: usage,
        quotaRepository: quota,
        store: ProviderSnapshotStore(),
        clock: clock
    )

    await coordinator.start()
    await eventually { usage.callCount == 1 }

    let manual = Task { await coordinator.manualRefresh() }
    await Task.yield()
    #expect(usage.callCount == 1)

    usage.releaseFirstCall()
    await manual.value
    await eventually { usage.callCount == 2 }

    #expect(usage.callCount == 2)
    #expect(usage.forcedCallCount == 1)
    #expect(quota.callCount >= 1)
    await coordinator.stop()
}

@Test func safetyCadenceRefreshesUsageAndQuotaEveryFiveMinutes() async throws {
    let now = try #require(BridgeDecoder.date("2026-08-14T10:00:00Z"))
    let clock = ManualClock(now: now)
    let usage = UsageRefreshSpy(result: .init(snapshots: [:], errors: [:]))
    let quota = QuotaRefreshSpy(result: .init(snapshots: [:], errors: [:]))
    let coordinator = RefreshCoordinator(
        usageRepository: usage,
        quotaRepository: quota,
        store: ProviderSnapshotStore(),
        clock: clock
    )

    await coordinator.start()
    await eventually { usage.callCount == 1 && quota.callCount == 1 && clock.sleeperCount == 2 }

    clock.advance(by: 5 * 60)
    await eventually { usage.callCount == 2 && quota.callCount == 2 }

    #expect(usage.callCount == 2)
    #expect(quota.callCount == 2)
    await coordinator.stop()
}

@Test func restartDoesNotOverlapARefreshCancelledDuringStop() async throws {
    let now = try #require(BridgeDecoder.date("2026-08-14T10:00:00Z"))
    let usage = BlockingUsageRepository()
    let quota = QuotaRefreshSpy(result: .init(snapshots: [:], errors: [:]))
    let coordinator = RefreshCoordinator(
        usageRepository: usage,
        quotaRepository: quota,
        store: ProviderSnapshotStore(),
        clock: ManualClock(now: now)
    )

    await coordinator.start()
    await eventually { usage.callCount == 1 }
    await coordinator.stop()
    await coordinator.start()
    await Task.yield()

    #expect(usage.callCount == 1)
    usage.releaseFirstCall()
    await eventually { usage.callCount == 2 }
    await coordinator.stop()
}

private final class UsageRefreshSpy: UsageRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let result: UsageRefreshResult
    private var calls = 0

    init(result: UsageRefreshResult) {
        self.result = result
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func refresh() throws -> UsageRefreshResult {
        lock.withLock { calls += 1 }
        return result
    }
}

private final class QuotaRefreshSpy: QuotaRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let result: QuotaRefreshResult
    private var calls = 0

    init(result: QuotaRefreshResult) {
        self.result = result
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func refresh() throws -> QuotaRefreshResult {
        lock.withLock { calls += 1 }
        return result
    }
}

private final class BlockingUsageRepository: UsageRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let released = DispatchSemaphore(value: 0)
    private var calls = 0
    private var forcedCalls = 0

    var callCount: Int {
        lock.withLock { calls }
    }

    var forcedCallCount: Int {
        lock.withLock { forcedCalls }
    }

    func refresh() throws -> UsageRefreshResult {
        try refresh(forceCursorSync: false)
    }

    func refresh(forceCursorSync: Bool) throws -> UsageRefreshResult {
        let count = lock.withLock { () -> Int in
            calls += 1
            if forceCursorSync { forcedCalls += 1 }
            return calls
        }
        if count == 1 {
            released.wait()
        }
        return .init(snapshots: [:], errors: [:])
    }

    func releaseFirstCall() {
        released.signal()
    }
}

private final class ManualClock: ClockLike, @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    private var continuations: [UUID: CheckedContinuation<Void, Error>] = [:]

    init(now: Date) {
        date = now
    }

    var now: Date {
        lock.withLock { date }
    }

    var sleeperCount: Int {
        lock.withLock { continuations.count }
    }

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        let id = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let cancelled = lock.withLock { () -> Bool in
                    if Task.isCancelled { return true }
                    continuations[id] = continuation
                    return false
                }
                if cancelled {
                    continuation.resume(throwing: CancellationError())
                }
            }
        }, onCancel: {
            let continuation = self.lock.withLock { self.continuations.removeValue(forKey: id) }
            continuation?.resume(throwing: CancellationError())
        })
    }

    func advance(by interval: TimeInterval) {
        let sleepers = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            date = date.addingTimeInterval(interval)
            defer { continuations.removeAll() }
            return Array(continuations.values)
        }
        sleepers.forEach { $0.resume() }
    }
}

private func eventually(
    _ condition: @escaping @Sendable () -> Bool,
    yields: Int = 100
) async {
    for _ in 0 ..< yields where !condition() {
        await Task.yield()
    }
}
