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
        sourceFactory: { _ in source },
        onUsageRefreshRequested: { calls.increment() }
    )

    await watcher.start()
    source.sendEvent()
    source.sendEvent()
    source.sendEvent()
    await eventually { clock.sleeperCount == 1 }

    clock.advance(by: 1)
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
        sourceFactory: { _ in source },
        onUsageRefreshRequested: { calls.increment() }
    )

    await watcher.start()
    source.sendEvent()
    await eventually { clock.sleeperCount == 1 }
    await watcher.stop()
    clock.advance(by: 1)
    await Task.yield()

    #expect(calls.value == 0)
}

@Test func startAndStopAreIdempotent() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = TestEventSource()
    let watcher = UsageFileWatcher(
        homeDirectory: directory,
        cursorCacheDirectory: directory,
        sourceFactory: { _ in source },
        onUsageRefreshRequested: {}
    )

    await watcher.start()
    await watcher.start()
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

private final class WatcherClock: ClockLike, @unchecked Sendable {
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
