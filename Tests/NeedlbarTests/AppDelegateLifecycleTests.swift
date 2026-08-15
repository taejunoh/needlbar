import AppKit
import Testing
@testable import NeedlbarApp

@MainActor
@Test func terminationWaitsForRefreshCleanupAndRepliesExactlyOnce() async {
    let shutdown = TerminationShutdownGate()
    let termination = AccessoryTerminationController()
    var startupCancellationCount = 0
    var observationStopCount = 0
    var replyCount = 0

    func requestTermination() -> NSApplication.TerminateReply {
        termination.requestTermination(
            cancelStartup: { startupCancellationCount += 1 },
            stopMenuBarObservation: { observationStopCount += 1 },
            stopRefreshCoordinator: { await shutdown.waitForRelease() },
            reply: { replyCount += 1 }
        )
    }

    #expect(requestTermination() == .terminateLater)
    #expect(startupCancellationCount == 1)
    #expect(observationStopCount == 1)
    #expect(replyCount == 0)

    #expect(requestTermination() == .terminateLater)
    #expect(startupCancellationCount == 1)
    #expect(observationStopCount == 1)
    #expect(await eventually { await shutdown.callCount() == 1 })

    await shutdown.release()

    #expect(await eventually { replyCount == 1 })
    #expect(replyCount == 1)
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
