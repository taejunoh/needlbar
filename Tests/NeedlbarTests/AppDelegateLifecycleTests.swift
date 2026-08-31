import AppKit
import Testing
@testable import NeedlbarApp

@Suite("AppDelegateLifecycleTests", .serialized)
@MainActor
struct AppDelegateLifecycleTests {
@Test func terminationStopsNotificationsBeforeLoginAndRefreshCleanup() async {
    let loginShutdown = TerminationShutdownGate()
    let refreshShutdown = TerminationShutdownGate()
    let termination = AccessoryTerminationController()
    var startupCancellationCount = 0
    var notificationStopCount = 0
    var observationStopCount = 0
    var replyCount = 0
    var loginAdmissionResumeCount = 0
    var events: [String] = []

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
            reply: {
                replyCount += 1
                events.append("reply:\($0)")
            },
            resumeLoginAdmission: { loginAdmissionResumeCount += 1 },
            resumeNotifications: {}
        )
    }

    #expect(requestTermination() == .terminateLater)
    #expect(startupCancellationCount == 1)
    #expect(notificationStopCount == 1)
    #expect(observationStopCount == 1)
    #expect(replyCount == 0)

    #expect(requestTermination() == .terminateLater)
    #expect(startupCancellationCount == 1)
    #expect(notificationStopCount == 1)
    #expect(observationStopCount == 1)
    #expect(await eventually { await loginShutdown.callCount() == 1 })
    #expect(await loginShutdown.callCount() == 1)
    #expect(await refreshShutdown.callCount() == 0)

    await loginShutdown.release()
    #expect(await eventually { await refreshShutdown.callCount() == 1 })
    #expect(replyCount == 0)

    await refreshShutdown.release()

    #expect(await eventually { replyCount == 1 })
    #expect(replyCount == 1)
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
    var replies: [Bool] = []
    var events: [String] = []

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
            reply: {
                replies.append($0)
                events.append("reply:\($0)")
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
    #expect(await eventually { await loginShutdown.callCount() == 1 })
    #expect(startupCancellationCount == 1)
    #expect(notificationStopCount == 1)
    #expect(observationStopCount == 1)

    await loginShutdown.releaseNext()
    #expect(await eventually { replies == [false] })
    #expect(await refreshShutdown.callCount() == 0)
    #expect(events == ["notificationStop", "loginStop", "reply:false", "resumeLoginAdmission", "resumeNotifications"])
    #expect(notificationResumeCount == 1)

    #expect(requestTermination() == .terminateLater)
    #expect(await eventually { await loginShutdown.callCount() == 2 })
    await loginShutdown.releaseNext()
    #expect(await eventually { await refreshShutdown.callCount() == 1 })
    #expect(replies == [false])

    await refreshShutdown.release()
    #expect(await eventually { replies == [false, true] })
    #expect(events == [
        "notificationStop", "loginStop", "reply:false", "resumeLoginAdmission", "resumeNotifications",
        "notificationStop",
        "loginStop", "refreshStop", "reply:true",
    ])
    #expect(startupCancellationCount == 2)
    #expect(notificationStopCount == 2)
    #expect(observationStopCount == 2)
    #expect(await loginShutdown.callCount() == 2)
    #expect(await refreshShutdown.callCount() == 1)
}
}

@MainActor
private func eventually(_ condition: @escaping @MainActor () async -> Bool) async -> Bool {
    for _ in 0..<100 {
        if await condition() { return true }
        await Task.yield()
    }
    return false
}

private actor TerminationShutdownGate {
    private var starts = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func waitForRelease() async {
        starts += 1
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func callCount() -> Int {
        starts
    }

    func release() {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor LoginTerminationGate {
    private var results: [ProviderLoginCleanupResult]
    private var starts = 0
    private var continuations: [CheckedContinuation<ProviderLoginCleanupResult, Never>] = []

    init(results: [ProviderLoginCleanupResult]) {
        self.results = results
    }

    func waitForRelease() async -> ProviderLoginCleanupResult {
        starts += 1
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func callCount() -> Int {
        starts
    }

    func releaseNext() {
        guard !continuations.isEmpty, !results.isEmpty else { return }
        continuations.removeFirst().resume(returning: results.removeFirst())
    }
}
