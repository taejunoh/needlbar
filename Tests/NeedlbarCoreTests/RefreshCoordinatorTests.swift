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
    await eventually { quota.callCount == 1 }

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
    await eventually { quota.callCount == 1 }
    await eventuallyAsync { await store.snapshot(for: .claude).quotaStatus == .requiresAuthentication }
    await coordinator.popoverOpened()
    await eventually { quota.callCount == 2 }

    #expect(quota.callCount == 2)
    await coordinator.stop()
}

@Test func manualRefreshMergesAnInflightUsageRequestBeforeForcedNextCycle() async throws {
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
    #expect(usage.forcedCallCount == 1)
    #expect(quota.callCount >= 1)
    await coordinator.stop()
}

@Test func manualRefreshBurstDoesNotStartAnotherForcedCycleAfterItsQueuedCycleCompletes() async throws {
    let now = try #require(BridgeDecoder.date("2026-08-14T10:00:00Z"))
    let usage = ForceRecordingUsageRepository()
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
    #expect(usage.forceFlags == [false, true])
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
    await eventually { usage.callCount == 2 && quota.callCount == 2 }

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
    await eventually { usage.callCount == 2 }

    #expect(usage.callCount == 2)
    let lifecycleAfterEvent = await watcher.lifecycle
    #expect(lifecycleAfterEvent == ["start-1", "stop", "start-2"])
    await coordinator.stop()
}

@Test func authenticationVerificationDoesNotTriggerUsageOrForcedCursorSync() async throws {
    let quota = BlockingIntentQuotaRepository()
    let usage = ForceRecordingUsageRepository()
    let coordinator = makeRunningCoordinator(usage: usage, quota: quota)
    await coordinator.start()
    await eventually { quota.callCount == 1 }
    quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    usage.releaseFirstCall()
    await eventually { usage.completedCallCount == 1 }

    let verification = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await eventually { quota.callCount == 2 }
    quota.releaseNext(with: quotaResult(for: .claude))

    #expect(await verification.value)
    #expect(usage.callCount == 1)
    #expect(usage.forceFlags == [false])
    await coordinator.stop()
}

@Test func claudeAuthenticationVerificationReturnsTrueOnlyAfterFreshClaudeQuota() async throws {
    let quota = BlockingIntentQuotaRepository()
    let coordinator = makeRunningCoordinator(quota: quota)
    await coordinator.start()
    await eventually { quota.callCount == 1 }
    quota.releaseNext(with: .init(snapshots: [:], errors: [:]))

    let verification = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await eventually { quota.callCount == 2 }
    #expect(!verification.isCancelled)
    quota.releaseNext(with: quotaResult(for: .claude))

    #expect(await verification.value)
    #expect(quota.intents == [.backgroundAll, .userInitiated(provider: .claude)])
    await coordinator.stop()
}

@Test func permissionDeniedVerificationPreservesLastKnownGoodQuotaAndReturnsFalse() async throws {
    let quota = BlockingIntentQuotaRepository()
    let store = ProviderSnapshotStore()
    let previous = QuotaSnapshot(windows: [try .init(id: "claude.session", title: "Session", usedPercent: 42, resetsAt: nil)])
    await store.applyQuota(previous, for: .claude)
    let coordinator = makeRunningCoordinator(quota: quota, store: store)
    await coordinator.start()
    await eventually { quota.callCount == 1 }
    quota.releaseNext(with: .init(snapshots: [:], errors: [:]))

    let verification = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await eventually { quota.callCount == 2 }
    quota.releaseNext(with: .init(snapshots: [:], errors: [.claude: permissionDenied(for: .claude)]))

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
    await eventually { quota.callCount == 1 }
    quota.releaseNext(with: .init(snapshots: [:], errors: [:]))

    let verification = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await eventually { quota.callCount == 2 }
    quota.releaseNext(throwing: BridgeFailure.bridgeFailed([
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
    await eventually { quota.callCount == 1 }

    let verification = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await registrations.waitUntil([.userInitiated(provider: .claude)])
    #expect(quota.callCount == 1)
    quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    await eventually { quota.callCount == 2 }
    quota.releaseNext(with: quotaResult(for: .claude))

    #expect(await verification.value)
    #expect(quota.intents == [.backgroundAll, .userInitiated(provider: .claude)])
    await coordinator.stop()
}

@Test func concurrentClaudeVerificationsCoalesceToOneFollowUpAndResumeAllWaitersOnce() async throws {
    let quota = BlockingIntentQuotaRepository()
    let registrations = QuotaIntentRegistrationGate()
    let coordinator = makeRunningCoordinator(quota: quota, quotaIntentRegistered: registrations.record)
    await coordinator.start()
    await eventually { quota.callCount == 1 }
    quota.releaseNext(with: .init(snapshots: [:], errors: [:]))

    let callers = (0 ..< 3).map { _ in Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) } }
    await registrations.waitUntil([
        .userInitiated(provider: .claude),
        .userInitiated(provider: .claude),
        .userInitiated(provider: .claude)
    ])
    await eventually { quota.callCount == 2 }
    quota.releaseNext(with: quotaResult(for: .claude))

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
    await eventually { quota.callCount == 1 }

    let codex = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .codex) }
    await registrations.waitUntil([.userInitiated(provider: .codex)])
    let claude = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await registrations.waitUntil([.userInitiated(provider: .codex), .userInitiated(provider: .claude)])
    quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    await eventually { quota.callCount == 2 }
    #expect(quota.intents[1] == .userInitiated(provider: .claude))
    quota.releaseNext(with: .init(snapshots: [:], errors: [.claude: permissionDenied(for: .claude)]))
    await eventually { quota.callCount == 3 }
    let claudeVerified = await claude.value
    #expect(!claudeVerified)
    quota.releaseNext(with: quotaResult(for: .codex))

    #expect(await codex.value)
    #expect(quota.intents == [.backgroundAll, .userInitiated(provider: .claude), .userInitiated(provider: .codex)])
    await coordinator.stop()
}

@Test func stopAndRestartResumeOutstandingVerificationWaitersFalseAndIgnoreLateQuota() async throws {
    let quota = BlockingIntentQuotaRepository()
    let store = ProviderSnapshotStore()
    let coordinator = makeRunningCoordinator(quota: quota, store: store)
    await coordinator.start()
    await eventually { quota.callCount == 1 }
    quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    let verification = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await eventually { quota.callCount == 2 }

    await coordinator.stop()
    let verified = await verification.value
    #expect(!verified)
    quota.releaseNext(with: quotaResult(for: .claude))
    await coordinator.start()
    await eventually { quota.callCount == 3 }
    quota.releaseNext(with: .init(snapshots: [:], errors: [:]))

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
    await eventually { quota.callCount == 1 }
    quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    let verification = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await eventually { quota.callCount == 2 }
    quota.releaseNext(with: quotaResult(for: .claude))
    #expect(await verification.value)

    await coordinator.popoverOpened()
    await eventually { quota.callCount == 3 }
    #expect(quota.intents[2] == .backgroundAll)
    quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    await coordinator.stop()
}

@Test func unsupportedCursorAuthenticationVerificationReturnsFalseWithoutQuotaFetch() async throws {
    let quota = BlockingIntentQuotaRepository()
    let coordinator = makeRunningCoordinator(quota: quota)
    await coordinator.start()
    await eventually { quota.callCount == 1 }
    quota.releaseNext(with: .init(snapshots: [:], errors: [:]))

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
    await eventually { quota.callCount == 1 }
    quota.releaseNext(with: .init(snapshots: [:], errors: [:]))

    let verification = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await eventually { quota.callCount == 2 }
    quota.releaseNext(with: try quotaResult(for: .claude, usedPercent: 10))
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
    await eventually { quota.callCount == 1 }
    quota.releaseNext(with: .init(snapshots: [:], errors: [:]))

    let first = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await registrations.waitUntil([.userInitiated(provider: .claude)])
    await eventually { quota.callCount == 2 }
    quota.releaseNext(with: try quotaResult(for: .claude, usedPercent: 10))
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
    await eventually { quota.callCount == 1 }

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

    quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    await eventually { quota.callCount == 2 }
    #expect(quota.intents[1] == .userInitiated(provider: .claude))
    quota.releaseNext(with: quotaResult(for: .claude))
    #expect(await aheadClaude.value)
    await eventually { quota.callCount == 3 }
    #expect(quota.intents[2] == .backgroundAll)

    quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    await eventually { quota.callCount == 4 }
    #expect(quota.intents[3] == .userInitiated(provider: .claude))
    quota.releaseNext(with: quotaResult(for: .claude))
    await eventually { quota.callCount == 5 }
    #expect(quota.intents[4] == .userInitiated(provider: .codex))
    quota.releaseNext(with: quotaResult(for: .codex))

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
    await eventually { quota.callCount == 1 }
    quota.releaseNext(with: .init(snapshots: [:], errors: [:]))

    let oldVerification = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await eventually { quota.callCount == 2 }
    await coordinator.stop()
    #expect(!(await oldVerification.value))
    await coordinator.start()
    let newVerification = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }

    quota.releaseNext(with: try quotaResult(for: .claude, usedPercent: 10))
    await eventually { quota.callCount == 3 }
    #expect(quota.intents[2] == .backgroundAll)
    quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    await eventually { quota.callCount == 4 }
    #expect(quota.intents[3] == .userInitiated(provider: .claude))
    quota.releaseNext(with: try quotaResult(for: .claude, usedPercent: 20))

    #expect(await newVerification.value)
    let expected = try QuotaSnapshot(windows: [.init(id: "claude.session", title: "Session", usedPercent: 20, resetsAt: nil)])
    await eventuallyAsync { await store.snapshot(for: .claude).quota == expected }
    #expect(await store.snapshot(for: .claude).quota == expected)
    await coordinator.stop()
}

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

    var callCount: Int {
        lock.withLock { calls }
    }

    func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult {
        lock.withLock { calls += 1 }
        return result
    }
}

private final class BlockingIntentQuotaRepository: QuotaRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [QuotaRefreshIntent] = []
    private var gates: [DispatchSemaphore] = []
    private var outcomes: [Result<QuotaRefreshResult, Error>] = []
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
        let gate = DispatchSemaphore(value: 0)
        let isUnexpected = lock.withLock { () -> Bool in
            if let blockedAfterCallCount, calls.count >= blockedAfterCallCount {
                unexpected.append(intent)
                return true
            }
            calls.append(intent)
            gates.append(gate)
            return false
        }
        if isUnexpected { throw BlockingQuotaRepositoryError.unexpectedCall }
        gate.wait()
        return try lock.withLock { try outcomes.removeFirst().get() }
    }

    func releaseNext(with result: QuotaRefreshResult) {
        releaseNext(outcome: .success(result))
    }

    func releaseNext(throwing error: Error) {
        releaseNext(outcome: .failure(error))
    }

    func forbidAdditionalCalls() {
        lock.withLock { blockedAfterCallCount = calls.count }
    }

    private func releaseNext(outcome: Result<QuotaRefreshResult, Error>) {
        let gate = lock.withLock { () -> DispatchSemaphore in
            outcomes.append(outcome)
            return gates.removeFirst()
        }
        gate.signal()
    }
}

private enum BlockingQuotaRepositoryError: Error {
    case unexpectedCall
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
    private var forcedCalls = 0

    var callCount: Int {
        lock.withLock { calls }
    }

    var forcedCallCount: Int {
        lock.withLock { forcedCalls }
    }

    func refresh() throws -> UsageRefreshResult {
        try refresh(forceCursorSync: false)
    }

    func refresh(forceCursorSync: Bool) throws -> UsageRefreshResult {
        let count = lock.withLock { () -> Int in
            calls += 1
            if forceCursorSync { forcedCalls += 1 }
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

private final class ForceRecordingUsageRepository: UsageRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let released = DispatchSemaphore(value: 0)
    private var calls: [Bool] = []
    private var completedCalls = 0

    var callCount: Int {
        lock.withLock { calls.count }
    }

    var completedCallCount: Int {
        lock.withLock { completedCalls }
    }

    var forceFlags: [Bool] {
        lock.withLock { calls }
    }

    func refresh() throws -> UsageRefreshResult {
        try refresh(forceCursorSync: false)
    }

    func refresh(forceCursorSync: Bool) throws -> UsageRefreshResult {
        let count = lock.withLock { () -> Int in
            calls.append(forceCursorSync)
            return calls.count
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
