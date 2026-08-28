import Foundation
import Testing
@testable import NeedlbarCore

@Test func threeEventsInsideDebounceIntervalRequestOneUsageRefresh() async throws {
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
    source.sendEvent()
    source.sendEvent()
    await eventually { clock.sleeperCount == 1 }

    clock.advance(by: 0.999)
    await Task.yield()

    #expect(calls.value == 0)

    clock.advance(by: 0.001)
    await eventually { calls.value == 1 }

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

@Test func stopCancelsAPendingDebouncedCallback() async throws {
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
    await eventually { clock.sleeperCount == 1 }
    await watcher.stop()
    clock.advance(by: 1)
    await Task.yield()

    #expect(calls.value == 0)
}

@Test func restartedCoordinatorRejectsAnOldWatcherRequestAfterDebounceBeforeAcceptance() async throws {
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
    await eventually { usage.callCount == 1 }
    source.sendEvent()
    await eventually { clock.sleeperCount == 3 }
    clock.advance(by: 1)
    await eventually { acceptanceGate.waiterCount == 1 }

    await coordinator.stop()
    await coordinator.start()
    await eventually { usage.callCount == 2 }
    acceptanceGate.open()
    await Task.yield()

    #expect(usage.callCount == 2)

    source.sendEvent()
    await eventually { clock.sleeperCount == 3 }
    clock.advance(by: 1)
    await eventually { usage.callCount == 3 }

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
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
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

    func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult {
        lock.withLock { calls += 1 }
        return result
    }
}

private final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    var waiterCount: Int {
        lock.withLock { continuations.count }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeImmediately = lock.withLock { () -> Bool in
                guard !isOpen else { return true }
                continuations.append(continuation)
                return false
            }
            if resumeImmediately {
                continuation.resume()
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
    private var date: Date
    private var continuations: [UUID: Sleeper] = [:]

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
                    continuations[id] = .init(
                        deadline: date.addingTimeInterval(timeInterval(for: duration)),
                        continuation: continuation
                    )
                    return false
                }
                if cancelled {
                    continuation.resume(throwing: CancellationError())
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

private func eventually(
    _ condition: @escaping @Sendable () -> Bool,
    yields: Int = 100
) async {
    for _ in 0 ..< yields where !condition() {
        await Task.yield()
    }
}
