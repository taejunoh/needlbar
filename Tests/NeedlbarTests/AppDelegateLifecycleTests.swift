import AppKit
import NeedlbarCore
import Testing
@testable import NeedlbarApp

@Suite("AppDelegateLifecycleTests", .serialized)
@MainActor
struct AppDelegateLifecycleTests {
#if !NEEDLBAR_ACCEPTANCE_DRIVER
@Test func productionLifecycleStartsAndStopsSystemMetricsBeforeMenuTeardown() async {
    let services = RecordingProductionLifecycleServices()
    let lifecycle = ProductionLifecycleController(services: services)

    await lifecycle.start()
    await lifecycle.start()
    await lifecycle.stop()
    await lifecycle.stop()

    #expect(await services.events == [
        "menu.start", "system.start", "notifications.start", "publisher.start", "refresh.start", "recovery.start",
        "recovery.stop", "refresh.stop", "publisher.stop", "notifications.stop", "system.stop", "menu.stop",
    ])
}

@Test(arguments: [false, true])
func recoveryTokenAcquisitionCannotRegisterAfterStop(restartBeforeOldToken: Bool) async {
    let tokenGate = LifecycleStartGate()
    let monitor = RecordingTerminationRecoveryMonitor()
    let recovery = QuotaRecoveryLifecycleController(monitor: monitor, requestToken: {
        await tokenGate.pause()
        return QuotaRecoveryRequestToken { _ in }
    })
    let services = RecordingProductionLifecycleServices(recovery: recovery)
    let lifecycle = ProductionLifecycleController(services: services)
    let oldStart = Task { await lifecycle.start() }
    await tokenGate.waitForEntry(1)
    await lifecycle.stop()
    #expect(monitor.starts == 0)
    #expect(monitor.stops == 1)
    #expect(!monitor.isRegistered)
    if restartBeforeOldToken {
        let newStart = Task { await lifecycle.start() }
        await tokenGate.waitForEntry(2)
        tokenGate.resume(2)
        await newStart.value
        #expect(monitor.starts == 1)
        #expect(monitor.isRegistered)
    }
    tokenGate.resume(1)
    await oldStart.value
    #expect(monitor.starts == (restartBeforeOldToken ? 1 : 0))
    #expect(monitor.stops == 1)
    #expect(monitor.isRegistered == restartBeforeOldToken)
    if restartBeforeOldToken { await lifecycle.stop() }
}

@Test(arguments: [false, true])
func stoppedRefreshStartupCannotAdmitLateRecovery(restartBeforeOldRefresh: Bool) async {
    let refreshGate = LifecycleStartGate()
    let monitor = RecordingTerminationRecoveryMonitor()
    let recovery = QuotaRecoveryLifecycleController(monitor: monitor, requestToken: {
        QuotaRecoveryRequestToken { _ in }
    })
    let services = RecordingProductionLifecycleServices(recovery: recovery, startRefresh: { await refreshGate.pause() })
    let lifecycle = ProductionLifecycleController(services: services)
    let oldStart = Task { await lifecycle.start() }
    await refreshGate.waitForEntry(1)
    await lifecycle.stop()
    if restartBeforeOldRefresh {
        let newStart = Task { await lifecycle.start() }
        await refreshGate.waitForEntry(2)
        refreshGate.resume(2)
        await newStart.value
        #expect(monitor.starts == 1)
        #expect(monitor.isRegistered)
    }
    refreshGate.resume(1)
    await oldStart.value
    #expect(services.events.filter { $0 == "recovery.start" }.count == (restartBeforeOldRefresh ? 1 : 0))
    #expect(monitor.starts == (restartBeforeOldRefresh ? 1 : 0))
    #expect(monitor.stops == 1)
    #expect(monitor.isRegistered == restartBeforeOldRefresh)
    if restartBeforeOldRefresh { await lifecycle.stop() }
}
#endif

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
    let recovery = RecordingTerminationRecoveryMonitor()
    recovery.start(using: QuotaRecoveryRequestToken { _ in })
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
                recovery.stop()
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
    #expect(recovery.stops == 0)
    #expect(await refreshShutdown.entryCount() == 0)

    await loginShutdown.release()
    await refreshShutdown.waitForEntry()
    #expect(recovery.stops == 1)
    #expect(replies.values.isEmpty)

    await refreshShutdown.release()
    await replies.waitForCount(1)
    #expect(replies.values == [true])
    #expect(loginAdmissionResumeCount == 0)
    #expect(events == ["notificationStop", "loginStop", "refreshStop", "reply:true"])
}

@Test func pendingReapResumesNotificationsAndResetsSynchronousCleanupForLaterRetry() async {
    let recovery = RecordingTerminationRecoveryMonitor()
    recovery.start(using: QuotaRecoveryRequestToken { _ in })
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
                recovery.stop()
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
    #expect(recovery.stops == 0)
    #expect(recovery.starts == 1)

    #expect(requestTermination() == .terminateLater)
    await loginShutdown.waitForEntry(count: 2)
    await loginShutdown.releaseNext()
    await refreshShutdown.waitForEntry()
    #expect(recovery.stops == 1)
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

#if !NEEDLBAR_ACCEPTANCE_DRIVER
@MainActor
private final class RecordingProductionLifecycleServices: ProductionLifecycleServing {
    private(set) var events: [String] = []
    private let recovery: QuotaRecoveryLifecycleController?
    private let startRefresh: @MainActor () async -> Void

    init(recovery: QuotaRecoveryLifecycleController? = nil,
         startRefresh: @escaping @MainActor () async -> Void = {}) {
        self.recovery = recovery
        self.startRefresh = startRefresh
    }

    func startProductionMenu() async { events.append("menu.start") }
    func startProductionSystem() async { events.append("system.start") }
    func startProductionNotifications() async { events.append("notifications.start") }
    func startProductionPublisher() async { events.append("publisher.start") }
    func startProductionRefresh() async { events.append("refresh.start"); await startRefresh() }
    func startProductionRecovery() async { events.append("recovery.start"); await recovery?.start() }
    func stopProductionRecovery() { events.append("recovery.stop"); recovery?.stop() }
    func stopProductionRefresh() async { events.append("refresh.stop") }
    func stopProductionPublisher() async { events.append("publisher.stop") }
    func stopProductionNotifications() async { events.append("notifications.stop") }
    func stopProductionSystem() async { events.append("system.stop") }
    func stopProductionMenu() async { events.append("menu.stop") }
}
#endif
}

@MainActor
private final class RecordingTerminationRecoveryMonitor: QuotaRecoveryMonitoring {
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var isRegistered = false
    func start(using token: QuotaRecoveryRequestToken) { starts += 1; isRegistered = true }
    func stop() { stops += 1; isRegistered = false }
}

@MainActor
private final class LifecycleStartGate {
    private var entries = 0
    private var pending: [Int: CheckedContinuation<Void, Never>] = [:]
    private var entryWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func pause() async {
        entries += 1
        let entry = entries
        await withCheckedContinuation { continuation in
            pending[entry] = continuation
            let ready = entryWaiters.filter { $0.0 <= entries }
            entryWaiters.removeAll { $0.0 <= entries }
            ready.forEach { $0.1.resume() }
        }
    }

    func waitForEntry(_ count: Int) async {
        guard entries < count else { return }
        await withCheckedContinuation { entryWaiters.append((count, $0)) }
    }

    func resume(_ entry: Int) { pending.removeValue(forKey: entry)?.resume() }
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
