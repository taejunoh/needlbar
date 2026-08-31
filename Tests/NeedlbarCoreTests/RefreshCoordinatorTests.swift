import Foundation
import Testing
@testable import NeedlbarCore

// These tests deliberately hold a synchronous repository call in flight to
// exercise coordinator merge/restart races. Keep the suite serialized so those
// bounded blocking test doubles cannot exhaust Swift's cooperative executor.
@Suite(.serialized)
struct RefreshCoordinatorTests {

@Test func popoverDoesNotRefreshQuotaBeforeSixtySeconds() async throws {
    let now = try #require(BridgeDecoder.date("2026-08-14T10:00:30Z"))
    let clock = ManualClock(now: now)
    let usage = UsageRefreshSpy(result: .init(snapshots: [:], errors: [:]))
    let quota = QuotaRefreshSpy(result: .init(snapshots: [:], errors: [:]))
    let coordinator = RefreshCoordinator(
        usageRepository: usage,
        quotaRepository: quota,
        store: ProviderSnapshotStore(),
        clock: clock,
        lastQuotaSuccessfulAt: now.addingTimeInterval(-30)
    )

    await coordinator.popoverOpened()
    await Task.yield()

    #expect(quota.callCount == 0)
    await coordinator.stop()
}

@Test func popoverRefreshesQuotaAfterSixtySeconds() async throws {
    let now = try #require(BridgeDecoder.date("2026-08-14T10:01:01Z"))
    let clock = ManualClock(now: now)
    let usage = UsageRefreshSpy(result: .init(snapshots: [:], errors: [:]))
    let quota = QuotaRefreshSpy(result: .init(snapshots: [:], errors: [:]))
    let coordinator = RefreshCoordinator(
        usageRepository: usage,
        quotaRepository: quota,
        store: ProviderSnapshotStore(),
        clock: clock,
        lastQuotaSuccessfulAt: now.addingTimeInterval(-61)
    )

    await coordinator.popoverOpened()
    await quota.waitUntilCallCount(1)

    #expect(quota.callCount == 1)
    await coordinator.stop()
}

@Test func quotaErrorsWithoutAnyValuesDoNotSuppressTheNextPopoverRetry() async throws {
    let now = try #require(BridgeDecoder.date("2026-08-14T10:01:01Z"))
    let quota = QuotaRefreshSpy(result: .init(
        snapshots: [:],
        errors: [.claude: BridgeError(provider: "claude", code: "requiresAuthentication", message: "sign in", action: nil)]
    ))
    let store = ProviderSnapshotStore()
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota,
        store: store,
        clock: ManualClock(now: now)
    )

    await coordinator.popoverOpened()
    await quota.waitUntilCallCount(1)
    await eventuallyAsync { await store.snapshot(for: .claude).quotaStatus == .requiresAuthentication }
    await coordinator.popoverOpened()
    await quota.waitUntilCallCount(2)

    #expect(quota.callCount == 2)
    await coordinator.stop()
}

@Test func cursorProviderUnavailableQuotaIsUnavailableWhileClaudeRemainsAnError() async throws {
    let now = try #require(BridgeDecoder.date("2026-08-26T12:00:00Z"))
    let quota = QuotaRefreshSpy(result: .init(
        snapshots: [:],
        errors: [
            .claude: BridgeError(provider: "claude", code: "providerUnavailable", message: "Claude unavailable", action: nil),
            .cursor: BridgeError(provider: "cursor", code: "providerUnavailable", message: "Cursor unavailable", action: nil)
        ]
    ))
    let store = ProviderSnapshotStore()
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota,
        store: store,
        clock: ManualClock(now: now)
    )

    await coordinator.popoverOpened()
    await quota.waitUntilCallCount(1)
    await eventuallyAsync { await store.snapshot(for: .cursor).quotaStatus == .unavailable }

    #expect(await store.snapshot(for: .cursor).quotaStatus == .unavailable)
    #expect(await store.snapshot(for: .claude).quotaStatus == .error(message: "Claude unavailable", lastSuccessfulAt: nil))
    await coordinator.stop()
}

@Test func manualRefreshQueuesOneNormalUsageFollowUpDuringAnInflightCycle() async throws {
    let now = try #require(BridgeDecoder.date("2026-08-14T10:00:00Z"))
    let clock = ManualClock(now: now)
    let usage = BlockingUsageRepository()
    let quota = QuotaRefreshSpy(result: .init(snapshots: [:], errors: [:]))
    let coordinator = RefreshCoordinator(
        usageRepository: usage,
        quotaRepository: quota,
        store: ProviderSnapshotStore(),
        clock: clock
    )

    await coordinator.start()
    await eventually { usage.callCount == 1 }

    let manual = Task { await coordinator.manualRefresh() }
    await Task.yield()
    #expect(usage.callCount == 1)

    usage.releaseFirstCall()
    await manual.value
    await eventually { usage.callCount == 2 }

    #expect(usage.callCount == 2)
    #expect(quota.callCount >= 1)
    await coordinator.stop()
}

@Test func manualRefreshBurstDoesNotStartAnotherUsageCycleAfterItsQueuedFollowUpCompletes() async throws {
    let now = try #require(BridgeDecoder.date("2026-08-14T10:00:00Z"))
    let usage = RecordingUsageRepository()
    let coordinator = RefreshCoordinator(
        usageRepository: usage,
        quotaRepository: QuotaRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        store: ProviderSnapshotStore(),
        clock: ManualClock(now: now)
    )

    await coordinator.start()
    await eventually { usage.callCount == 1 }

    var manualRequests: [Task<Void, Never>] = []
    for _ in 0 ..< 3 {
        manualRequests.append(Task { await coordinator.manualRefresh() })
        for _ in 0 ..< 10 {
            await Task.yield()
        }
    }

    usage.releaseFirstCall()
    await eventually { usage.callCount == 2 }
    await eventually { usage.completedCallCount == 2 }
    for request in manualRequests {
        await request.value
    }
    await Task.yield()

    #expect(usage.callCount == 2)
    await coordinator.stop()
}

@Test func safetyCadenceRefreshesUsageAndQuotaEveryFiveMinutes() async throws {
    let now = try #require(BridgeDecoder.date("2026-08-14T10:00:00Z"))
    let clock = ManualClock(now: now)
    let usage = UsageRefreshSpy(result: .init(snapshots: [:], errors: [:]))
    let quota = QuotaRefreshSpy(result: .init(snapshots: [:], errors: [:]))
    let coordinator = RefreshCoordinator(
        usageRepository: usage,
        quotaRepository: quota,
        store: ProviderSnapshotStore(),
        clock: clock
    )

    await coordinator.start()
    await eventually { usage.callCount == 1 && quota.callCount == 1 && clock.sleeperCount == 2 }

    clock.advance(by: 5 * 60 - 1)
    await Task.yield()

    #expect(usage.callCount == 1)
    #expect(quota.callCount == 1)

    clock.advance(by: 1)
    await usage.waitUntilCallCount(2)
    await quota.waitUntilCallCount(2)

    #expect(usage.callCount == 2)
    #expect(quota.callCount == 2)
    await coordinator.stop()
}

@Test func restartDoesNotOverlapARefreshCancelledDuringStop() async throws {
    let now = try #require(BridgeDecoder.date("2026-08-14T10:00:00Z"))
    let usage = BlockingUsageRepository()
    let quota = QuotaRefreshSpy(result: .init(snapshots: [:], errors: [:]))
    let coordinator = RefreshCoordinator(
        usageRepository: usage,
        quotaRepository: quota,
        store: ProviderSnapshotStore(),
        clock: ManualClock(now: now)
    )

    await coordinator.start()
    await eventually { usage.callCount == 1 }
    await coordinator.stop()
    await coordinator.start()
    await Task.yield()

    #expect(usage.callCount == 1)
    usage.releaseFirstCall()
    await eventually { usage.callCount == 2 }
    await coordinator.stop()
}

@Test func staleWatcherStartupCannotStopTheWatcherInstalledByANewerRun() async throws {
    let now = try #require(BridgeDecoder.date("2026-08-14T10:00:00Z"))
    let usage = UsageRefreshSpy(result: .init(snapshots: [:], errors: [:]))
    let watcher = DelayedUsageFileWatcher()
    let coordinator = RefreshCoordinator(
        usageRepository: usage,
        quotaRepository: QuotaRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        store: ProviderSnapshotStore(),
        clock: ManualClock(now: now),
        usageFileWatcher: watcher
    )

    let firstStart = Task { await coordinator.start() }
    await eventuallyAsync { await watcher.firstStartIsSuspended }

    await coordinator.stop()
    await coordinator.start()
    await eventually { usage.callCount == 1 }

    await watcher.resumeFirstStart()
    await firstStart.value

    let lifecycleBeforeEvent = await watcher.lifecycle
    #expect(lifecycleBeforeEvent == ["start-1", "stop", "start-2"])
    #expect(await watcher.isActive)

    await watcher.sendEvent()
    await usage.waitUntilCallCount(2)

    #expect(usage.callCount == 2)
    let lifecycleAfterEvent = await watcher.lifecycle
    #expect(lifecycleAfterEvent == ["start-1", "stop", "start-2"])
    await coordinator.stop()
}

@Test func authenticationVerificationDoesNotTriggerUsageRefresh() async throws {
    let quota = BlockingIntentQuotaRepository()
    let usage = RecordingUsageRepository()
    let coordinator = makeRunningCoordinator(usage: usage, quota: quota)
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    usage.releaseFirstCall()
    await eventually { usage.completedCallCount == 1 }

    let verification = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await quota.waitUntilCallCount(2)
    try quota.releaseNext(with: quotaResult(for: .claude))

    #expect(await verification.value)
    #expect(usage.callCount == 1)
    await coordinator.stop()
}

@Test func claudeAuthenticationVerificationReturnsTrueOnlyAfterFreshClaudeQuota() async throws {
    let quota = BlockingIntentQuotaRepository()
    let coordinator = makeRunningCoordinator(quota: quota)
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))

    let verification = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await quota.waitUntilCallCount(2)
    #expect(!verification.isCancelled)
    try quota.releaseNext(with: quotaResult(for: .claude))

    #expect(await verification.value)
    #expect(quota.intents == [.backgroundAll, .userInitiated(provider: .claude)])
    await coordinator.stop()
}

@Test func blockingQuotaRepositoryRejectsAReleaseBeforeAnyCallRegisters() async throws {
    let quota = BlockingIntentQuotaRepository()

    #expect(throws: BlockingQuotaRepositoryError.unexpectedRelease) {
        try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    }
}

@Test func permissionDeniedVerificationPreservesLastKnownGoodQuotaAndReturnsFalse() async throws {
    let quota = BlockingIntentQuotaRepository()
    let store = ProviderSnapshotStore()
    let previous = QuotaSnapshot(windows: [try .init(id: "claude.session", title: "Session", usedPercent: 42, resetsAt: nil)])
    await store.applyQuota(previous, for: .claude)
    let coordinator = makeRunningCoordinator(quota: quota, store: store)
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))

    let verification = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await quota.waitUntilCallCount(2)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [.claude: permissionDenied(for: .claude)]))

    let verified = await verification.value
    #expect(!verified)
    #expect(await store.snapshot(for: .claude).quota == previous)
    if case .error(message: "access denied", lastSuccessfulAt: _) = await store.snapshot(for: .claude).quotaStatus {
        // The previous quota timestamp must survive the failed verification.
    } else {
        Issue.record("Expected a safe permission-denied quota failure.")
    }
    await coordinator.stop()
}

@Test func malformedDedicatedVerificationMarksOnlyTheRequestedQuotaStaleAndPreservesItsValue() async throws {
    let quota = BlockingIntentQuotaRepository()
    let store = ProviderSnapshotStore()
    let previous = QuotaSnapshot(windows: [try .init(id: "claude.session", title: "Session", usedPercent: 42, resetsAt: nil)])
    await store.applyQuota(previous, for: .claude)
    let coordinator = makeRunningCoordinator(quota: quota, store: store)
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))

    let verification = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await quota.waitUntilCallCount(2)
    try quota.releaseNext(throwing: BridgeFailure.bridgeFailed([
        .init(provider: ProviderID.claude.rawValue, code: "invalidResponse", message: "Provider verification returned no result.", action: nil)
    ]))

    #expect(!(await verification.value))
    #expect(await store.snapshot(for: .claude).quota == previous)
    if case .error(message: "Provider verification returned no result.", lastSuccessfulAt: _) = await store.snapshot(for: .claude).quotaStatus {
        // A malformed dedicated response must make only the requested quota stale.
    } else {
        Issue.record("Expected the requested quota to be marked stale after a malformed dedicated response.")
    }
    #expect(await store.snapshot(for: .codex).quota == nil)
    await coordinator.stop()
}

@Test func userVerificationQueuedDuringBackgroundRefreshIsNotMergedAway() async throws {
    let quota = BlockingIntentQuotaRepository()
    let registrations = QuotaIntentRegistrationGate()
    let coordinator = makeRunningCoordinator(quota: quota, quotaIntentRegistered: registrations.record)
    await coordinator.start()
    await quota.waitUntilCallCount(1)

    let verification = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await registrations.waitUntil([.userInitiated(provider: .claude)])
    #expect(quota.callCount == 1)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    await quota.waitUntilCallCount(2)
    try quota.releaseNext(with: quotaResult(for: .claude))

    #expect(await verification.value)
    #expect(quota.intents == [.backgroundAll, .userInitiated(provider: .claude)])
    await coordinator.stop()
}

@Test func concurrentClaudeVerificationsCoalesceToOneFollowUpAndResumeAllWaitersOnce() async throws {
    let quota = BlockingIntentQuotaRepository()
    let registrations = QuotaIntentRegistrationGate()
    let coordinator = makeRunningCoordinator(quota: quota, quotaIntentRegistered: registrations.record)
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))

    let callers = (0 ..< 3).map { _ in Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) } }
    await registrations.waitUntil([
        .userInitiated(provider: .claude),
        .userInitiated(provider: .claude),
        .userInitiated(provider: .claude)
    ])
    await quota.waitUntilCallCount(2)
    try quota.releaseNext(with: quotaResult(for: .claude))

    for caller in callers {
        #expect(await caller.value)
    }
    #expect(quota.intents == [.backgroundAll, .userInitiated(provider: .claude)])
    await coordinator.stop()
}

@Test func simultaneousProviderVerificationsRunInStableProviderOrderAndResumeOnlyTheirWaiters() async throws {
    let quota = BlockingIntentQuotaRepository()
    let registrations = QuotaIntentRegistrationGate()
    let coordinator = makeRunningCoordinator(quota: quota, quotaIntentRegistered: registrations.record)
    await coordinator.start()
    await quota.waitUntilCallCount(1)

    let codex = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .codex) }
    await registrations.waitUntil([.userInitiated(provider: .codex)])
    let claude = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await registrations.waitUntil([.userInitiated(provider: .codex), .userInitiated(provider: .claude)])
    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    await quota.waitUntilCallCount(2)
    #expect(quota.intents[1] == .userInitiated(provider: .claude))
    try quota.releaseNext(with: .init(snapshots: [:], errors: [.claude: permissionDenied(for: .claude)]))
    await quota.waitUntilCallCount(3)
    let claudeVerified = await claude.value
    #expect(!claudeVerified)
    try quota.releaseNext(with: quotaResult(for: .codex))

    #expect(await codex.value)
    #expect(quota.intents == [.backgroundAll, .userInitiated(provider: .claude), .userInitiated(provider: .codex)])
    await coordinator.stop()
}

@Test func stopAndRestartResumeOutstandingVerificationWaitersFalseAndIgnoreLateQuota() async throws {
    let quota = BlockingIntentQuotaRepository()
    let store = ProviderSnapshotStore()
    let coordinator = makeRunningCoordinator(quota: quota, store: store)
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    let verification = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await quota.waitUntilCallCount(2)

    await coordinator.stop()
    let verified = await verification.value
    #expect(!verified)
    try quota.releaseNext(with: quotaResult(for: .claude))
    await coordinator.start()
    await quota.waitUntilCallCount(3)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))

    #expect(await store.snapshot(for: .claude).quota == nil)
    await coordinator.stop()
}

@Test func providerOnlyVerificationDoesNotAdvanceBackgroundFreshnessAndPopoverQueuesBackgroundAll() async throws {
    let now = try #require(BridgeDecoder.date("2026-08-25T12:00:00Z"))
    let quota = BlockingIntentQuotaRepository()
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota,
        store: ProviderSnapshotStore(),
        clock: ManualClock(now: now),
        lastQuotaSuccessfulAt: now.addingTimeInterval(-61)
    )
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    let verification = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await quota.waitUntilCallCount(2)
    try quota.releaseNext(with: quotaResult(for: .claude))
    #expect(await verification.value)

    await coordinator.popoverOpened()
    await quota.waitUntilCallCount(3)
    #expect(quota.intents[2] == .backgroundAll)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    await coordinator.stop()
}

@Test func unsupportedCursorAuthenticationVerificationReturnsFalseWithoutQuotaFetch() async throws {
    let quota = BlockingIntentQuotaRepository()
    let coordinator = makeRunningCoordinator(quota: quota)
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))

    let verified = await coordinator.refreshQuota(afterUserAuthenticationFor: .cursor)
    #expect(!verified)
    #expect(quota.callCount == 1)
    await coordinator.stop()
}

@Test func timerPopoverAndManualQuotaPathsAlwaysUseBackgroundAllIntent() async throws {
    let now = try #require(BridgeDecoder.date("2026-08-25T12:00:00Z"))
    let clock = ManualClock(now: now)
    let quota = IntentRecordingQuotaRepository()
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota,
        store: ProviderSnapshotStore(),
        clock: clock
    )
    await coordinator.start()
    await eventually { quota.callCount == 1 && clock.sleeperCount == 2 }
    await coordinator.manualRefresh()
    await eventually { quota.callCount >= 2 }
    await coordinator.popoverOpened()
    await eventually { quota.callCount >= 3 }
    clock.advance(by: 5 * 60)
    await eventually { quota.callCount >= 4 }

    #expect(quota.intents.allSatisfy { $0 == .backgroundAll })
    await coordinator.stop()
}

@Test func stopDuringQuotaStoreApplicationResumesCapturedVerificationWaiterFalseExactlyOnce() async throws {
    let quota = BlockingIntentQuotaRepository()
    let storeGate = QuotaApplicationGate()
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota,
        store: ProviderSnapshotStore(),
        clock: ManualClock(now: try #require(BridgeDecoder.date("2026-08-25T12:00:00Z"))),
        quotaApplicationWillApply: { await storeGate.pause() }
    )
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))

    let verification = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await quota.waitUntilCallCount(2)
    try quota.releaseNext(with: try quotaResult(for: .claude, usedPercent: 10))
    await storeGate.waitUntilEntered()
    await coordinator.stop()

    let verified = await verification.value
    #expect(!verified)
    await storeGate.resume()
}

@Test func sameProviderVerificationJoiningDuringQuotaApplicationUsesTheActiveResult() async throws {
    let quota = BlockingIntentQuotaRepository()
    let storeGate = QuotaApplicationGate()
    let registrations = QuotaIntentRegistrationGate()
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota,
        store: ProviderSnapshotStore(),
        clock: ManualClock(now: try #require(BridgeDecoder.date("2026-08-25T12:00:00Z"))),
        quotaApplicationWillApply: { await storeGate.pause() },
        quotaIntentRegistered: registrations.record
    )
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))

    let first = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await registrations.waitUntil([.userInitiated(provider: .claude)])
    await quota.waitUntilCallCount(2)
    try quota.releaseNext(with: try quotaResult(for: .claude, usedPercent: 10))
    await storeGate.waitUntilEntered()
    let joining = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await registrations.waitUntil([.userInitiated(provider: .claude), .userInitiated(provider: .claude)])
    quota.forbidAdditionalCalls()
    await storeGate.resume()

    #expect(await first.value)
    #expect(quota.callCount == 2)
    #expect(await joining.value)
    #expect(quota.unexpectedIntents.isEmpty)
    await coordinator.stop()
}

@Test func queuedBackgroundRunsAfterItsFiniteAheadBatchDespiteLaterUserRequests() async throws {
    let quota = BlockingIntentQuotaRepository()
    let registrations = QuotaIntentRegistrationGate()
    let coordinator = makeRunningCoordinator(quota: quota, quotaIntentRegistered: registrations.record)
    await coordinator.start()
    await quota.waitUntilCallCount(1)

    let aheadClaude = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await registrations.waitUntil([.userInitiated(provider: .claude)])
    let manual = Task { await coordinator.manualRefresh() }
    await registrations.waitUntil([.userInitiated(provider: .claude), .backgroundAll])
    let behindCodex = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .codex) }
    await registrations.waitUntil([
        .userInitiated(provider: .claude),
        .backgroundAll,
        .userInitiated(provider: .codex)
    ])
    let behindClaude = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await registrations.waitUntil([
        .userInitiated(provider: .claude),
        .backgroundAll,
        .userInitiated(provider: .codex),
        .userInitiated(provider: .claude)
    ])

    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    await quota.waitUntilCallCount(2)
    #expect(quota.intents[1] == .userInitiated(provider: .claude))
    try quota.releaseNext(with: quotaResult(for: .claude))
    #expect(await aheadClaude.value)
    await quota.waitUntilCallCount(3)
    #expect(quota.intents[2] == .backgroundAll)

    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    await quota.waitUntilCallCount(4)
    #expect(quota.intents[3] == .userInitiated(provider: .claude))
    try quota.releaseNext(with: quotaResult(for: .claude))
    await quota.waitUntilCallCount(5)
    #expect(quota.intents[4] == .userInitiated(provider: .codex))
    try quota.releaseNext(with: quotaResult(for: .codex))

    #expect(await behindClaude.value)
    #expect(await behindCodex.value)
    await manual.value
    await coordinator.stop()
}

@Test func restartedGenerationKeepsNewProviderWaiterSeparateFromLateOldCompletion() async throws {
    let quota = BlockingIntentQuotaRepository()
    let store = ProviderSnapshotStore()
    let coordinator = makeRunningCoordinator(quota: quota, store: store)
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))

    let oldVerification = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await quota.waitUntilCallCount(2)
    await coordinator.stop()
    #expect(!(await oldVerification.value))
    await coordinator.start()
    let newVerification = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }

    try quota.releaseNext(with: try quotaResult(for: .claude, usedPercent: 10))
    await quota.waitUntilCallCount(3)
    #expect(quota.intents[2] == .backgroundAll)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    await quota.waitUntilCallCount(4)
    #expect(quota.intents[3] == .userInitiated(provider: .claude))
    try quota.releaseNext(with: try quotaResult(for: .claude, usedPercent: 20))

    #expect(await newVerification.value)
    let expected = try QuotaSnapshot(windows: [.init(id: "claude.session", title: "Session", usedPercent: 20, resetsAt: nil)])
    await eventuallyAsync { await store.snapshot(for: .claude).quota == expected }
    #expect(await store.snapshot(for: .claude).quota == expected)
    await coordinator.stop()
}

@Test func usageRefreshCapturesOneStableDayProofAroundOneRepositoryCall() async throws {
    let usage = UsageRefreshSpy(result: .init(
        snapshots: [.claude: usageSnapshotForWidgetProvenanceTest()],
        errors: [:]
    ))
    let store = ProviderSnapshotStore()
    let context = WidgetUsageDayContext(
        dayKey: "2027-01-15",
        timeZoneIdentifier: "America/New_York",
        utcOffsetSeconds: -18_000
    )
    let updates = await store.updates()
    let appliedUsage = Task {
        for await snapshots in updates where snapshots[0].usage != nil {
            return
        }
    }
    let coordinator = RefreshCoordinator(
        usageRepository: usage,
        quotaRepository: QuotaRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        store: store,
        clock: ManualClock(now: Self.fixedStart),
        widgetUsageDayCapture: FixedDayCapture(values: [context, context])
    )

    await coordinator.start()
    await usage.waitUntilCallCount(1)
    await appliedUsage.value

    #expect(usage.callCount == 1)
    #expect(await store.captureForWidget(exportedAt: Self.fixedStart).providers[0].usageDayProvenance?.provenContext == context)
    await coordinator.stop()
}

private func usageSnapshotForWidgetProvenanceTest() -> UsageSnapshot {
    let period = UsagePeriod(inputTokens: 1, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, totalTokens: 1, estimatedCostUSD: Decimal(string: "1")!)
    return .init(inputTokens: 1, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, totalTokens: 1, estimatedCostUSD: Decimal(string: "1")!, today: period, last7Days: period, last7DaysDaily: [.init(date: "2027-01-15", totalTokens: 1)], last30Days: period)
}

private struct FixedDayCapture: WidgetUsageDayCapturing {
    let values: [WidgetUsageDayContext]

    func capture(at date: Date) -> WidgetUsageDayContext {
        values[date == RefreshCoordinatorTests.fixedStart ? 0 : 1]
    }
}

private static let fixedStart = Date(timeIntervalSince1970: 1_800_000_000)

private func makeRunningCoordinator(
    usage: any UsageRepository = UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
    quota: any QuotaRepository,
    store: ProviderSnapshotStore = ProviderSnapshotStore(),
    quotaIntentRegistered: (@Sendable (QuotaRefreshIntent) -> Void)? = nil
) -> RefreshCoordinator {
    RefreshCoordinator(
        usageRepository: usage,
        quotaRepository: quota,
        store: store,
        clock: ManualClock(now: BridgeDecoder.date("2026-08-25T12:00:00Z")!),
        quotaIntentRegistered: quotaIntentRegistered
    )
}

private func quotaResult(for provider: ProviderID) -> QuotaRefreshResult {
    .init(snapshots: [provider: QuotaSnapshot(windows: [])], errors: [:])
}

private func quotaResult(for provider: ProviderID, usedPercent: Double) throws -> QuotaRefreshResult {
    .init(
        snapshots: [provider: QuotaSnapshot(windows: [
            try .init(id: "\(provider.rawValue).session", title: "Session", usedPercent: usedPercent, resetsAt: nil)
        ])],
        errors: [:]
    )
}

private func permissionDenied(for provider: ProviderID) -> BridgeError {
    .init(provider: provider.rawValue, code: "permissionDenied", message: "access denied", action: nil)
}

private final class UsageRefreshSpy: UsageRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let result: UsageRefreshResult
    private var calls = 0
    private var callCountWaiters: [QuotaCallCountWaiter] = []

    init(result: UsageRefreshResult) {
        self.result = result
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func refresh() throws -> UsageRefreshResult {
        let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            calls += 1
            let ready = callCountWaiters.filter { calls >= $0.expectedCount }.map(\.continuation)
            callCountWaiters.removeAll { calls >= $0.expectedCount }
            return ready
        }
        waiters.forEach { $0.resume() }
        return result
    }

    func waitUntilCallCount(_ expectedCount: Int) async {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock { () -> Bool in
                guard calls < expectedCount else { return true }
                callCountWaiters.append(.init(expectedCount: expectedCount, continuation: continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }
}

private struct QuotaCallCountWaiter {
    let expectedCount: Int
    let continuation: CheckedContinuation<Void, Never>
}

private final class QuotaRefreshSpy: QuotaRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let result: QuotaRefreshResult
    private var calls = 0
    private var callCountWaiters: [QuotaCallCountWaiter] = []

    init(result: QuotaRefreshResult) {
        self.result = result
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult {
        let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            calls += 1
            var remaining: [QuotaCallCountWaiter] = []
            var ready: [CheckedContinuation<Void, Never>] = []
            for waiter in callCountWaiters {
                if calls >= waiter.expectedCount {
                    ready.append(waiter.continuation)
                } else {
                    remaining.append(waiter)
                }
            }
            callCountWaiters = remaining
            return ready
        }
        waiters.forEach { $0.resume() }
        return result
    }

    func waitUntilCallCount(_ expectedCount: Int) async {
        await withCheckedContinuation { continuation in
            let resumeImmediately = lock.withLock { () -> Bool in
                if calls >= expectedCount {
                    return true
                }
                callCountWaiters.append(.init(expectedCount: expectedCount, continuation: continuation))
                return false
            }
            if resumeImmediately {
                continuation.resume()
            }
        }
    }
}

private final class BlockingIntentQuotaRepository: QuotaRepository, @unchecked Sendable {
    private final class PendingCall {
        let gate = DispatchSemaphore(value: 0)
        var outcome: Result<QuotaRefreshResult, Error>?
    }

    private let lock = NSLock()
    private var calls: [QuotaRefreshIntent] = []
    private var pendingCalls: [PendingCall] = []
    private var callCountWaiters: [QuotaCallCountWaiter] = []
    private var blockedAfterCallCount: Int?
    private var unexpected: [QuotaRefreshIntent] = []

    var callCount: Int {
        lock.withLock { calls.count }
    }

    var intents: [QuotaRefreshIntent] {
        lock.withLock { calls }
    }

    var unexpectedIntents: [QuotaRefreshIntent] {
        lock.withLock { unexpected }
    }

    func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult {
        let pendingCall = PendingCall()
        let registrationWaiters = lock.withLock { () -> ([CheckedContinuation<Void, Never>], Bool) in
            if let blockedAfterCallCount, calls.count >= blockedAfterCallCount {
                unexpected.append(intent)
                return ([], true)
            }
            calls.append(intent)
            pendingCalls.append(pendingCall)
            var remaining: [QuotaCallCountWaiter] = []
            var ready: [CheckedContinuation<Void, Never>] = []
            for waiter in callCountWaiters {
                if calls.count >= waiter.expectedCount {
                    ready.append(waiter.continuation)
                } else {
                    remaining.append(waiter)
                }
            }
            callCountWaiters = remaining
            return (ready, false)
        }
        registrationWaiters.0.forEach { $0.resume() }
        if registrationWaiters.1 { throw BlockingQuotaRepositoryError.unexpectedCall }
        pendingCall.gate.wait()
        let outcome = lock.withLock { pendingCall.outcome }
        guard let outcome else { throw BlockingQuotaRepositoryError.missingOutcome }
        return try outcome.get()
    }

    func waitUntilCallCount(_ expectedCount: Int) async {
        await withCheckedContinuation { continuation in
            let resumeImmediately = lock.withLock { () -> Bool in
                if calls.count >= expectedCount {
                    return true
                }
                callCountWaiters.append(.init(expectedCount: expectedCount, continuation: continuation))
                return false
            }
            if resumeImmediately {
                continuation.resume()
            }
        }
    }

    func releaseNext(with result: QuotaRefreshResult) throws {
        try releaseNext(outcome: .success(result))
    }

    func releaseNext(throwing error: Error) throws {
        try releaseNext(outcome: .failure(error))
    }

    func forbidAdditionalCalls() {
        lock.withLock { blockedAfterCallCount = calls.count }
    }

    private func releaseNext(outcome: Result<QuotaRefreshResult, Error>) throws {
        let pendingCall = try lock.withLock { () throws -> PendingCall in
            guard !pendingCalls.isEmpty else {
                throw BlockingQuotaRepositoryError.unexpectedRelease
            }
            let pendingCall = pendingCalls.removeFirst()
            pendingCall.outcome = outcome
            return pendingCall
        }
        pendingCall.gate.signal()
    }
}

private enum BlockingQuotaRepositoryError: Error, Equatable {
    case unexpectedCall
    case unexpectedRelease
    case missingOutcome
}

private final class IntentRecordingQuotaRepository: QuotaRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [QuotaRefreshIntent] = []

    var callCount: Int {
        lock.withLock { calls.count }
    }

    var intents: [QuotaRefreshIntent] {
        lock.withLock { calls }
    }

    func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult {
        lock.withLock { calls.append(intent) }
        return .init(snapshots: [:], errors: [:])
    }
}

private actor QuotaApplicationGate {
    private var entered = false
    private var released = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func pause() async {
        entered = true
        enteredContinuation?.resume()
        enteredContinuation = nil
        guard !released else { return }
        await withCheckedContinuation { continuation in
            if released {
                continuation.resume()
            } else {
                releaseContinuation = continuation
            }
        }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { continuation in
            enteredContinuation = continuation
        }
    }

    func resume() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private final class QuotaIntentRegistrationGate: @unchecked Sendable {
    private struct Waiter {
        let expected: [QuotaRefreshIntent]
        let continuation: CheckedContinuation<Void, Never>
    }

    private let lock = NSLock()
    private var events: [QuotaRefreshIntent] = []
    private var waiters: [Waiter] = []

    func record(_ intent: QuotaRefreshIntent) {
        let ready = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            events.append(intent)
            var remaining: [Waiter] = []
            var ready: [CheckedContinuation<Void, Never>] = []
            for waiter in waiters {
                if events.starts(with: waiter.expected) {
                    ready.append(waiter.continuation)
                } else {
                    remaining.append(waiter)
                }
            }
            waiters = remaining
            return ready
        }
        ready.forEach { $0.resume() }
    }

    func waitUntil(_ expected: [QuotaRefreshIntent]) async {
        await withCheckedContinuation { continuation in
            let resumeImmediately = lock.withLock { () -> Bool in
                if events.starts(with: expected) {
                    return true
                }
                waiters.append(.init(expected: expected, continuation: continuation))
                return false
            }
            if resumeImmediately {
                continuation.resume()
            }
        }
    }
}

private final class BlockingUsageRepository: UsageRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let released = DispatchSemaphore(value: 0)
    private var calls = 0

    var callCount: Int {
        lock.withLock { calls }
    }

    func refresh() throws -> UsageRefreshResult {
        let count = lock.withLock { () -> Int in
            calls += 1
            return calls
        }
        if count == 1 {
            released.wait()
        }
        return .init(snapshots: [:], errors: [:])
    }

    func releaseFirstCall() {
        released.signal()
    }
}

private final class RecordingUsageRepository: UsageRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let released = DispatchSemaphore(value: 0)
    private var calls = 0
    private var completedCalls = 0

    var callCount: Int {
        lock.withLock { calls }
    }

    var completedCallCount: Int {
        lock.withLock { completedCalls }
    }

    func refresh() throws -> UsageRefreshResult {
        let count = lock.withLock { () -> Int in
            calls += 1
            return calls
        }
        if count == 1 {
            released.wait()
        }
        lock.withLock { completedCalls += 1 }
        return .init(snapshots: [:], errors: [:])
    }

    func releaseFirstCall() {
        released.signal()
    }
}

private actor DelayedUsageFileWatcher: UsageFileWatching {
    private var activeRefreshRequest: UsageRefreshRequestToken?
    private var firstStartContinuation: CheckedContinuation<Void, Never>?
    private var starts = 0
    private var lifecycleCalls: [String] = []

    var firstStartIsSuspended: Bool {
        firstStartContinuation != nil
    }

    var isActive: Bool {
        activeRefreshRequest != nil
    }

    var lifecycle: [String] {
        lifecycleCalls
    }

    func start(using refreshRequest: UsageRefreshRequestToken) async {
        starts += 1
        lifecycleCalls.append("start-\(starts)")
        activeRefreshRequest = refreshRequest
        guard starts == 1 else { return }
        await withCheckedContinuation { continuation in
            firstStartContinuation = continuation
        }
    }

    func stop() {
        lifecycleCalls.append("stop")
        activeRefreshRequest = nil
    }

    func resumeFirstStart() {
        let continuation = firstStartContinuation
        firstStartContinuation = nil
        continuation?.resume()
    }

    func sendEvent() async {
        if let activeRefreshRequest {
            await activeRefreshRequest.submit()
        }
    }
}

private final class ManualClock: ClockLike, @unchecked Sendable {
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

private func eventually(
    _ condition: @escaping @Sendable () -> Bool,
    yields: Int = 100
) async {
    for _ in 0 ..< yields where !condition() {
        await Task.yield()
    }
}

private func eventuallyAsync(
    _ condition: @escaping @Sendable () async -> Bool,
    yields: Int = 100
) async {
    for _ in 0 ..< yields where !(await condition()) {
        await Task.yield()
    }
}

}
