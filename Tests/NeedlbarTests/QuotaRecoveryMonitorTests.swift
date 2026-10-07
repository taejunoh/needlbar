import AppKit
import NeedlbarCore
import Testing
@testable import NeedlbarApp

@Suite("QuotaRecoveryMonitorTests") @MainActor
struct QuotaRecoveryMonitorTests {
    @Test func countWaiterRemainsPendingUntilRequestedCallback() async {
        let received = RecoveryTriggerRecorder(maximumCount: 2)
        let (checkpoints, checkpoint) = AsyncStream<CountWaitCheckpoint>.makeStream()
        let waiting = Task {
            await received.waitForCount(2, onPending: { checkpoint.yield(.pending) })
            let values = await received.values
            checkpoint.yield(.completed(values))
            return values
        }
        var iterator = checkpoints.makeAsyncIterator()
        // Callbacks are withheld until the waiter either suspends or returns.
        // The polling implementation deterministically returns an empty result.
        #expect(await iterator.next() == .pending)
        await received.append(.wake)
        #expect(await received.pendingWaiterCount == 1)
        await received.append(.connectivity)
        #expect(await waiting.value == [.wake, .connectivity])
        #expect(await received.pendingWaiterCount == 0)
        checkpoint.finish()
    }

    @Test func pathRequiresObservedOfflineToOnlineTransition() async {
        let path = FakeQuotaPath()
        let monitor = QuotaRecoveryMonitor(center: NotificationCenter(), makePath: { path })
        let received = RecoveryTriggerRecorder(maximumCount: 1)
        monitor.start(using: QuotaRecoveryRequestToken { await received.append($0) })
        path.receive?(true)
        path.receive?(true)
        #expect(await received.values.isEmpty)
        path.receive?(false)
        path.receive?(true)
        await received.waitForCount(1)
        #expect(await received.values == [.connectivity])
        monitor.stop()
        #expect(path.cancels == 1)
    }

    @Test func duplicateStartRegistersOneWakeObserverAndOnePath() async {
        let center = NotificationCenter()
        let path = FakeQuotaPath()
        let monitor = QuotaRecoveryMonitor(center: center, makePath: { path })
        let received = RecoveryTriggerRecorder(maximumCount: 1)
        let token = QuotaRecoveryRequestToken { await received.append($0) }
        monitor.start(using: token)
        monitor.start(using: token)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        await received.waitForCount(1)
        #expect(path.starts == 1)
        #expect(await received.values == [.wake])
        monitor.stop()
        monitor.stop()
        #expect(path.cancels == 1)
    }

    @Test func stoppedAndDelayedOldCallbacksCannotReachRestartedToken() async {
        let center = NotificationCenter()
        let first = FakeQuotaPath()
        let second = FakeQuotaPath()
        var paths = [first, second]
        let monitor = QuotaRecoveryMonitor(center: center, makePath: { paths.removeFirst() })
        // Fail on any forbidden delivery itself, even if it arrives after an
        // earlier empty snapshot; no scheduler-drain assumption is needed.
        let old = RecoveryTriggerRecorder(maximumCount: 0)
        let current = RecoveryTriggerRecorder(maximumCount: 2)
        monitor.start(using: QuotaRecoveryRequestToken { await old.append($0) })
        first.receive?(false)
        // Queues the notification's MainActor hop; stop/restart happens before it runs.
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        let saved = first.receive
        monitor.stop()
        saved?(true)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        monitor.start(using: QuotaRecoveryRequestToken { await current.append($0) })
        saved?(false)
        saved?(true)
        second.receive?(true)
        #expect(await old.values.isEmpty)
        #expect(await current.values.isEmpty)
        second.receive?(false)
        second.receive?(true)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        await current.waitForCount(2)
        let values = await current.values
        #expect(values.count == 2)
        #expect(values.contains(.wake))
        #expect(values.contains(.connectivity))
        #expect(await old.values.isEmpty)
        #expect(first.cancels == 1)
        #expect(second.starts == 1)
        monitor.stop()
        #expect(second.cancels == 1)
    }
}

@MainActor private final class FakeQuotaPath: QuotaPathMonitoring {
    var receive: (@MainActor @Sendable (Bool) -> Void)?
    var starts = 0
    var cancels = 0
    func start(_ receive: @escaping @MainActor @Sendable (Bool) -> Void) {
        starts += 1
        self.receive = receive
    }
    func cancel() { cancels += 1 }
}

private actor RecoveryTriggerRecorder {
    var values: [QuotaRefreshTrigger] = []
    private let maximumCount: Int
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    var pendingWaiterCount: Int { waiters.count }

    init(maximumCount: Int) { self.maximumCount = maximumCount }

    func append(_ value: QuotaRefreshTrigger) {
        values.append(value)
        #expect(values.count <= maximumCount, "Unexpected recovery callback: \(value.rawValue)")
        let ready = waiters.filter { values.count >= $0.count }
        waiters.removeAll { values.count >= $0.count }
        ready.forEach { $0.continuation.resume() }
    }

    func waitForCount(_ count: Int, onPending: @Sendable () -> Void = {}) async {
        guard values.count < count else { return }
        await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
            onPending()
        }
    }
}

private enum CountWaitCheckpoint: Equatable, Sendable {
    case pending
    case completed([QuotaRefreshTrigger])
}
