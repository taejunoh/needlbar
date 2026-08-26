import AppKit
import Testing
@testable import NeedlbarApp

@MainActor
@Test func terminationWaitsForLoginAndRefreshCleanupAndRepliesExactlyOnce() async {
    let loginShutdown = TerminationShutdownGate()
    let refreshShutdown = TerminationShutdownGate()
    let termination = AccessoryTerminationController()
    var startupCancellationCount = 0
    var observationStopCount = 0
    var replyCount = 0

    func requestTermination() -> NSApplication.TerminateReply {
        termination.requestTermination(
            cancelStartup: { startupCancellationCount += 1 },
            stopMenuBarObservation: { observationStopCount += 1 },
            stopLoginCoordinator: {
                await loginShutdown.waitForRelease()
                return .complete
            },
            stopRefreshCoordinator: { await refreshShutdown.waitForRelease() },
            reply: { _ in replyCount += 1 }
        )
    }

    #expect(requestTermination() == .terminateLater)
    #expect(startupCancellationCount == 1)
    #expect(observationStopCount == 1)
    #expect(replyCount == 0)

    #expect(requestTermination() == .terminateLater)
    #expect(startupCancellationCount == 1)
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
}

@MainActor
@Test func terminationRejectsPendingReapWithoutStoppingRefreshAndAllowsALaterCompleteRetry() async {
    let loginShutdown = LoginTerminationGate(results: [.pendingReap, .complete])
    let refreshShutdown = TerminationShutdownGate()
    let termination = AccessoryTerminationController()
    var startupCancellationCount = 0
    var observationStopCount = 0
    var replies: [Bool] = []

    func requestTermination() -> NSApplication.TerminateReply {
        termination.requestTermination(
            cancelStartup: { startupCancellationCount += 1 },
            stopMenuBarObservation: { observationStopCount += 1 },
            stopLoginCoordinator: { await loginShutdown.waitForRelease() },
            stopRefreshCoordinator: { await refreshShutdown.waitForRelease() },
            reply: { replies.append($0) }
        )
    }

    #expect(requestTermination() == .terminateLater)
    #expect(requestTermination() == .terminateLater)
    #expect(await eventually { await loginShutdown.callCount() == 1 })
    #expect(startupCancellationCount == 1)
    #expect(observationStopCount == 1)

    await loginShutdown.releaseNext()
    #expect(await eventually { replies == [false] })
    #expect(await refreshShutdown.callCount() == 0)

    #expect(requestTermination() == .terminateLater)
    #expect(await eventually { await loginShutdown.callCount() == 2 })
    await loginShutdown.releaseNext()
    #expect(await eventually { await refreshShutdown.callCount() == 1 })
    #expect(replies == [false])

    await refreshShutdown.release()
    #expect(await eventually { replies == [false, true] })
    #expect(startupCancellationCount == 1)
    #expect(observationStopCount == 1)
    #expect(await loginShutdown.callCount() == 2)
    #expect(await refreshShutdown.callCount() == 1)
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
