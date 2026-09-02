import AppKit
import Testing
@testable import NeedlbarApp

@Suite("AppDelegateLifecycleTests", .serialized)
@MainActor
struct AppDelegateLifecycleTests {
#if NEEDLBAR_ACCEPTANCE_DRIVER
@Test func acceptanceLifecycleStartsAndStopsOnlyAcceptanceSurfacesInOrder() async {
    let services = RecordingAcceptanceLifecycleServices()
    let lifecycle = AcceptanceLifecycleController(services: services)
    await lifecycle.start()
    await lifecycle.stop()
    #expect(await services.events == [
        "menu.start", "notifications.start", "publisher.start", "driver.start",
        "driver.stop", "publisher.stop", "notifications.stop", "menu.stop",
    ])
}
#endif

@Test func terminationStopsNotificationsBeforeLoginAndRefreshCleanup() async {
    let loginShutdown = TerminationShutdownGate()
    let refreshShutdown = TerminationShutdownGate()
    let termination = AccessoryTerminationController()
    var startupCancellationCount = 0
    var notificationStopCount = 0
    var observationStopCount = 0
    var loginAdmissionResumeCount = 0
    var events: [String] = []
    let replies = TerminationReplyGate()

    func requestTermination() -> NSApplication.TerminateReply {
        termination.requestTermination(
            cancelStartup: { startupCancellationCount += 1 },
            stopNotifications: {
                notificationStopCount += 1
                events.append("notificationStop")
            },
            stopMenuBarObservation: { observationStopCount += 1 },
            stopLoginCoordinator: {
                events.append("loginStop")
                await loginShutdown.waitForRelease()
                return .complete
            },
            stopRefreshCoordinator: {
                events.append("refreshStop")
                await refreshShutdown.waitForRelease()
            },
            reply: { value in
                replies.record(value)
                events.append("reply:\(value)")
            },
            resumeLoginAdmission: { loginAdmissionResumeCount += 1 },
            resumeNotifications: {}
        )
    }

    #expect(requestTermination() == .terminateLater)
    #expect(startupCancellationCount == 1)
    #expect(notificationStopCount == 1)
    #expect(observationStopCount == 1)
    #expect(replies.values.isEmpty)

    #expect(requestTermination() == .terminateLater)
    #expect(startupCancellationCount == 1)
    #expect(notificationStopCount == 1)
    #expect(observationStopCount == 1)
    await loginShutdown.waitForEntry()
    #expect(await refreshShutdown.entryCount() == 0)

    await loginShutdown.release()
    await refreshShutdown.waitForEntry()
    #expect(replies.values.isEmpty)

    await refreshShutdown.release()
    await replies.waitForCount(1)
    #expect(replies.values == [true])
    #expect(loginAdmissionResumeCount == 0)
    #expect(events == ["notificationStop", "loginStop", "refreshStop", "reply:true"])
}

@Test func pendingReapResumesNotificationsAndResetsSynchronousCleanupForLaterRetry() async {
    let loginShutdown = LoginTerminationGate(results: [.pendingReap, .complete])
    let refreshShutdown = TerminationShutdownGate()
    let termination = AccessoryTerminationController()
    var startupCancellationCount = 0
    var notificationStopCount = 0
    var notificationResumeCount = 0
    var observationStopCount = 0
    var events: [String] = []
    let replies = TerminationReplyGate()

    func requestTermination() -> NSApplication.TerminateReply {
        termination.requestTermination(
            cancelStartup: { startupCancellationCount += 1 },
            stopNotifications: {
                notificationStopCount += 1
                events.append("notificationStop")
            },
            stopMenuBarObservation: { observationStopCount += 1 },
            stopLoginCoordinator: {
                let result = await loginShutdown.waitForRelease()
                events.append("loginStop")
                return result
            },
            stopRefreshCoordinator: {
                events.append("refreshStop")
                await refreshShutdown.waitForRelease()
            },
            reply: { value in
                replies.record(value)
                events.append("reply:\(value)")
            },
            resumeLoginAdmission: { events.append("resumeLoginAdmission") },
            resumeNotifications: {
                notificationResumeCount += 1
                events.append("resumeNotifications")
            }
        )
    }

    #expect(requestTermination() == .terminateLater)
    #expect(requestTermination() == .terminateLater)
    await loginShutdown.waitForEntry(count: 1)
    #expect(startupCancellationCount == 1)
    #expect(notificationStopCount == 1)
    #expect(observationStopCount == 1)

    await loginShutdown.releaseNext()
    await replies.waitForCount(1)
    #expect(await refreshShutdown.entryCount() == 0)
    #expect(replies.values == [false])
    #expect(events == ["notificationStop", "loginStop", "reply:false", "resumeLoginAdmission", "resumeNotifications"])
    #expect(notificationResumeCount == 1)

    #expect(requestTermination() == .terminateLater)
    await loginShutdown.waitForEntry(count: 2)
    await loginShutdown.releaseNext()
    await refreshShutdown.waitForEntry()
    #expect(replies.values == [false])

    await refreshShutdown.release()
    await replies.waitForCount(2)
    #expect(replies.values == [false, true])
    #expect(events == [
        "notificationStop", "loginStop", "reply:false", "resumeLoginAdmission", "resumeNotifications",
        "notificationStop",
        "loginStop", "refreshStop", "reply:true",
    ])
    #expect(startupCancellationCount == 2)
    #expect(notificationStopCount == 2)
    #expect(observationStopCount == 2)
    #expect(await loginShutdown.entryCount() == 2)
    #expect(await refreshShutdown.entryCount() == 1)
}

#if NEEDLBAR_ACCEPTANCE_DRIVER
@MainActor
private final class RecordingAcceptanceLifecycleServices: AcceptanceLifecycleServing {
    private(set) var events: [String] = []

    func startMenu() async { events.append("menu.start") }
    func startNotifications() async { events.append("notifications.start") }
    func startPublisher() async { events.append("publisher.start") }
    func startDriver() async { events.append("driver.start") }
    func stopDriver() async { events.append("driver.stop") }
    func stopPublisher() async { events.append("publisher.stop") }
    func stopNotifications() { events.append("notifications.stop") }
    func stopMenu() { events.append("menu.stop") }
}
#endif
}

@MainActor
private final class TerminationReplyGate {
    private(set) var values: [Bool] = []
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func record(_ value: Bool) {
        values.append(value)
        resumeSatisfiedWaiters()
    }

    func waitForCount(_ count: Int) async {
        guard values.count < count else { return }
        await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }

    private func resumeSatisfiedWaiters() {
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            if values.count >= waiter.count {
                waiter.continuation.resume()
            } else {
                waiters.append(waiter)
            }
        }
    }
}

private actor TerminationShutdownGate {
    private var starts = 0
    private var entryWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func waitForRelease() async {
        starts += 1
        resumeSatisfiedEntryWaiters()
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitForEntry(count: Int = 1) async {
        guard starts < count else { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append((count, continuation))
        }
    }

    func entryCount() -> Int {
        starts
    }

    func release() {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }

    private func resumeSatisfiedEntryWaiters() {
        let pending = entryWaiters
        entryWaiters.removeAll()
        for waiter in pending {
            if starts >= waiter.count {
                waiter.continuation.resume()
            } else {
                entryWaiters.append(waiter)
            }
        }
    }
}

private actor LoginTerminationGate {
    private var results: [ProviderLoginCleanupResult]
    private var starts = 0
    private var entryWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var continuations: [CheckedContinuation<ProviderLoginCleanupResult, Never>] = []

    init(results: [ProviderLoginCleanupResult]) {
        self.results = results
    }

    func waitForRelease() async -> ProviderLoginCleanupResult {
        starts += 1
        resumeSatisfiedEntryWaiters()
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitForEntry(count: Int = 1) async {
        guard starts < count else { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append((count, continuation))
        }
    }

    func entryCount() -> Int {
        starts
    }

    func releaseNext() {
        guard !continuations.isEmpty, !results.isEmpty else { return }
        continuations.removeFirst().resume(returning: results.removeFirst())
    }

    private func resumeSatisfiedEntryWaiters() {
        let pending = entryWaiters
        entryWaiters.removeAll()
        for waiter in pending {
            if starts >= waiter.count {
                waiter.continuation.resume()
            } else {
                entryWaiters.append(waiter)
            }
        }
    }
}
