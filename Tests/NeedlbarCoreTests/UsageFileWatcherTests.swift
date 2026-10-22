import Foundation
import Testing
@testable import NeedlbarCore

// Tests that wait on the doubles below carry a time limit; every such wait
// ends on cancellation, so a missed wakeup fails the test instead of stalling
// the run.
@Test(.timeLimit(.minutes(1)))
func threeEventsInsideDebounceIntervalRequestOneUsageRefresh() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let clock = WatcherClock(now: .now)
    let source = TestEventSource()
    let calls = AsyncCounter()
    let watcher = UsageFileWatcher(
        homeDirectory: directory,
        cursorCacheDirectory: directory,
        clock: clock,
        sourceFactory: { _ in source }
    )

    await watcher.start(using: UsageRefreshRequestToken { calls.increment() })
    source.sendEvent()
    await clock.waitUntilSleeperRegistrationCount(1)
    try #require(clock.sleeperRegistrationCount >= 1)

    source.sendEvent()
    await clock.waitUntilSleeperRegistrationCount(2)
    try #require(clock.sleeperRegistrationCount >= 2)

    source.sendEvent()
    await clock.waitUntilSleeperRegistrationCount(3)
    try #require(clock.sleeperRegistrationCount >= 3)

    clock.advance(by: 0.999)
    await Task.yield()

    #expect(calls.value == 0)

    clock.advance(by: 0.001)
    await calls.waitUntilValue(1)

    #expect(calls.value == 1)
    await watcher.stop()
}

@Test func discoversOnlyExistingApprovedRootsAndTreatsEmptyCodexHomeAsDefault() async throws {
    let home = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    let expected = [
        home.appending(path: ".claude/projects", directoryHint: .isDirectory),
        home.appending(path: ".codex/sessions", directoryHint: .isDirectory),
        home.appending(path: ".config/tokscale/cursor-cache", directoryHint: .isDirectory),
    ]
    for directory in expected {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    let roots = UsageFileWatcher.discoverExistingRoots(
        homeDirectory: home,
        environment: ["CODEX_HOME": ""],
        cursorCacheDirectory: expected[2]
    )

    #expect(roots == expected)
}

@Test(.timeLimit(.minutes(1)))
func stopCancelsAPendingDebouncedCallback() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let clock = WatcherClock(now: .now)
    let source = TestEventSource()
    let calls = AsyncCounter()
    let watcher = UsageFileWatcher(
        homeDirectory: directory,
        cursorCacheDirectory: directory,
        clock: clock,
        sourceFactory: { _ in source }
    )

    await watcher.start(using: UsageRefreshRequestToken { calls.increment() })
    source.sendEvent()
    await clock.waitUntilSleeperCount(1)
    await watcher.stop()
    clock.advance(by: 1)
    await Task.yield()

    #expect(calls.value == 0)
}

@Test(.timeLimit(.minutes(1)))
func restartedCoordinatorRejectsAnOldWatcherRequestAfterDebounceBeforeAcceptance() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let clock = WatcherClock(now: .now)
    let source = TestEventSource()
    let acceptanceGate = AsyncGate()
    let watcher = UsageFileWatcher(
        homeDirectory: directory,
        cursorCacheDirectory: directory,
        clock: clock,
        sourceFactory: { _ in source },
        beforeRefreshDelivery: { await acceptanceGate.wait() }
    )
    let usage = UsageRefreshSpy(result: .init(snapshots: [:], errors: [:]))
    let coordinator = RefreshCoordinator(
        usageRepository: usage,
        quotaRepository: QuotaRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        store: ProviderSnapshotStore(),
        clock: clock,
        usageFileWatcher: watcher
    )

    await coordinator.start()
    await usage.waitUntilCallCount(1)
    source.sendEvent()
    await clock.waitUntilSleeperCount(3)
    clock.advance(by: 1)
    await acceptanceGate.waitUntilWaiterCount(1)

    await coordinator.stop()
    await coordinator.start()
    await usage.waitUntilCallCount(2)
    acceptanceGate.open()
    await Task.yield()

    #expect(usage.callCount == 2)

    source.sendEvent()
    await clock.waitUntilSleeperCount(3)
    clock.advance(by: 1)
    await usage.waitUntilCallCount(3)

    #expect(usage.callCount == 3)
    await coordinator.stop()
}

@Test func startAndStopAreIdempotent() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = TestEventSource()
    let watcher = UsageFileWatcher(
        homeDirectory: directory,
        cursorCacheDirectory: directory,
        sourceFactory: { _ in source }
    )

    let refreshRequest = UsageRefreshRequestToken {}
    await watcher.start(using: refreshRequest)
    await watcher.start(using: refreshRequest)
    await watcher.stop()
    await watcher.stop()

    #expect(source.startCount == 1)
    #expect(source.stopCount == 1)
}

private final class TestEventSource: UsageFileEventSource, @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable () -> Void)?
    private var starts = 0
    private var stops = 0

    var startCount: Int {
        lock.withLock { starts }
    }

    var stopCount: Int {
        lock.withLock { stops }
    }

    func start(onEvent: @escaping @Sendable () -> Void) {
        lock.withLock {
            starts += 1
            callback = onEvent
        }
    }

    func stop() {
        lock.withLock {
            stops += 1
            callback = nil
        }
    }

    func sendEvent() {
        lock.withLock { callback }?()
    }
}

private final class AsyncCounter: @unchecked Sendable {
    private let lock = NSLock()
    private let changes = ConditionWaiters()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
        changes.signal()
    }

    func waitUntilValue(_ expectedValue: Int) async {
        await changes.wait { self.value >= expectedValue }
    }
}

private final class UsageRefreshSpy: UsageRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let changes = ConditionWaiters()
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
        changes.signal()
        return result
    }

    func waitUntilCallCount(_ expectedCount: Int) async {
        await changes.wait { self.callCount >= expectedCount }
    }
}

private final class QuotaRefreshSpy: QuotaRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let result: QuotaRefreshResult
    private var calls = 0

    init(result: QuotaRefreshResult) {
        self.result = result
    }

    func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult {
        lock.withLock { calls += 1 }
        return result
    }
}

private final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private let changes = ConditionWaiters()
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    var waiterCount: Int {
        lock.withLock { continuations.count }
    }

    func waitUntilWaiterCount(_ expectedCount: Int) async {
        await changes.wait { self.waiterCount >= expectedCount }
    }

    /// The watcher's delivery hook. Like the delivery it holds, it ignores
    /// cancellation and returns only once the test calls `open()`.
    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeImmediately = lock.withLock { () -> Bool in
                guard !isOpen else { return true }
                continuations.append(continuation)
                return false
            }
            if resumeImmediately {
                continuation.resume()
            } else {
                changes.signal()
            }
        }
    }

    func open() {
        let waiting = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isOpen = true
            defer { continuations.removeAll() }
            return continuations
        }
        waiting.forEach { $0.resume() }
    }
}

private final class WatcherClock: ClockLike, @unchecked Sendable {
    private struct Sleeper {
        let deadline: Date
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private let changes = ConditionWaiters()
    private var date: Date
    private var continuations: [UUID: Sleeper] = [:]
    private var registeredSleeperCount = 0

    init(now: Date) {
        date = now
    }

    var now: Date {
        lock.withLock { date }
    }

    var sleeperCount: Int {
        lock.withLock { continuations.count }
    }

    var sleeperRegistrationCount: Int {
        lock.withLock { registeredSleeperCount }
    }

    func waitUntilSleeperCount(_ expectedCount: Int) async {
        await changes.wait { self.sleeperCount >= expectedCount }
    }

    func waitUntilSleeperRegistrationCount(_ expectedCount: Int) async {
        await changes.wait { self.sleeperRegistrationCount >= expectedCount }
    }

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        let id = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let cancelled = lock.withLock { () -> Bool in
                    if Task.isCancelled { return true }
                    continuations[id] = .init(
                        deadline: date.addingTimeInterval(timeInterval(for: duration)),
                        continuation: continuation
                    )
                    registeredSleeperCount += 1
                    return false
                }
                if cancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    changes.signal()
                }
            }
        }, onCancel: {
            let sleeper = self.lock.withLock { self.continuations.removeValue(forKey: id) }
            sleeper?.continuation.resume(throwing: CancellationError())
        })
    }

    func advance(by interval: TimeInterval) {
        let sleepers = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            date = date.addingTimeInterval(interval)
            let due = continuations.filter { $0.value.deadline <= date }
            due.keys.forEach { continuations.removeValue(forKey: $0) }
            return due.values.map(\.continuation)
        }
        sleepers.forEach { $0.resume() }
    }

    private func timeInterval(for duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
