import AppKit
import NeedlbarCore
import Testing
@testable import NeedlbarApp

@Suite("QuotaRecoveryMonitorTests") @MainActor
struct QuotaRecoveryMonitorTests {
    @Test func pathRequiresObservedOfflineToOnlineTransition() async {
        let path = FakeQuotaPath()
        let monitor = QuotaRecoveryMonitor(center: NotificationCenter(), makePath: { path })
        let received = RecoveryTriggerRecorder()
        monitor.start(using: QuotaRecoveryRequestToken { await received.append($0) })
        path.receive?(true)
        path.receive?(true)
        for _ in 0..<100 { await Task.yield() }
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
        let received = RecoveryTriggerRecorder()
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
        let old = RecoveryTriggerRecorder()
        let current = RecoveryTriggerRecorder()
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
        for _ in 0..<100 { await Task.yield() }
        #expect(await old.values.isEmpty)
        #expect(await current.values.isEmpty)
        second.receive?(false)
        second.receive?(true)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        await current.waitForCount(2)
        #expect(await current.values.count == 2)
        #expect(await current.values.contains(.wake))
        #expect(await current.values.contains(.connectivity))
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
    func append(_ value: QuotaRefreshTrigger) { values.append(value) }
    func waitForCount(_ count: Int) async {
        for _ in 0..<10_000 where values.count < count { await Task.yield() }
    }
}
