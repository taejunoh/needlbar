import Foundation
import Testing
import NeedlbarClaudeStatusLineSupport
@testable import NeedlbarCore

// These tests deliberately hold a synchronous repository call in flight to
// exercise coordinator merge/restart races. The repository protocols are
// synchronous and the coordinator calls them from tasks on Swift's cooperative
// pool, so a held call blocks one pool thread until the test, which needs
// another thread, releases it. The suite is serialized so that at most one
// test holds calls at a time (one call, or a usage and a quota call in
// authenticationVerificationDoesNotTriggerUsageRefresh). Each hold is bounded
// by blockingFakeReleaseTimeout: a forgotten release, or a pool too small to
// run the test beside its held calls, fails the test and frees the thread
// instead of deadlocking the run.
// The time limit cancels a test whose condition never arrives. Every
// test-side wait ends on cancellation (see TestWaiting.swift), so a missed
// wakeup fails that test instead of stalling the whole run.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct RefreshCoordinatorTests {

@Test func attemptIsInProgressUntilStoreAndLegacyCallbackComplete() async throws {
    let quota = BlockingIntentQuotaRepository()
    let application = QuotaApplicationGate()
    let completion = QuotaApplicationGate()
    let events = QuotaAttemptCollector()
    let now = Self.fixedStart
    let clock = ManualClock(now: now)
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota, store: ProviderSnapshotStore(), clock: clock,
        quotaApplicationWillApply: { await application.pause() },
        claudeQuotaOperationCompleted: { await completion.pause() },
        quotaAttemptObserver: { events.record($0) })
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    #expect(events.values.count == 1)
    #expect(events.values.first?.phase == .started)
    #expect(events.values.first?.trigger == .startup)
    #expect(events.values.first?.startedAt == now)
    #expect(events.values.first?.completedAt == nil)
    #expect(events.values.first?.outcome == nil)
    clock.setNowWithoutWakingSleepers(now.addingTimeInterval(20))
    try quota.releaseNext(with: try quotaResult(for: .claude, usedPercent: 10))
    await application.waitUntilEntered()
    #expect(events.values.count == 1)
    await application.resume()
    await completion.waitUntilEntered()
    #expect(events.values.count == 1)
    clock.setNowWithoutWakingSleepers(now.addingTimeInterval(30))
    await completion.resume()
    await events.waitUntilCount(2)
    #expect(events.values.last?.phase == .completed)
    #expect(events.values.last?.id == events.values.first?.id)
    #expect(events.values.last?.startedAt == now)
    #expect(events.values.last?.completedAt == now.addingTimeInterval(30))
    #expect(events.values.last?.directLastSuccessfulAt == now.addingTimeInterval(20))
    #expect(events.values.last?.outcome == .success)
    #expect(events.values.last?.fiveHourSource == .direct)
    await coordinator.stop()
    #expect(events.values.count == 2)
}

@Test func blockedAttemptInvalidatesOnceAndRestartUsesNewIdentityAndGeneration() async throws {
    let quota = BlockingIntentQuotaRepository()
    let events = QuotaAttemptCollector()
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota, store: ProviderSnapshotStore(), clock: ManualClock(now: Self.fixedStart),
        quotaAttemptObserver: { events.record($0) })
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    let original = events.values.first
    await coordinator.stop()
    await coordinator.stop()
    #expect(events.values.map(\.phase) == [.started, .invalidated])
    #expect(events.values.last?.id == original?.id)
    #expect(events.values.last?.startedAt == original?.startedAt)
    #expect(events.values.last?.outcome == nil)
    #expect(events.values.last?.completedAt == nil)
    await coordinator.start()
    #expect(quota.callCount == 1)
    try quota.releaseNext(with: quotaResult(for: .claude))
    await quota.waitUntilCallCount(2)
    #expect(events.values.map(\.phase) == [.started, .invalidated, .started])
    #expect(events.values.last?.id != original?.id)
    #expect(events.values.last?.generation != original?.generation)
    try quota.releaseNext(with: quotaResult(for: .claude))
    await events.waitUntilCount(4)
    #expect(events.values.last?.outcome == .success)
    await coordinator.stop()
}

@Test func expiryPreservesDirectSuccessAndBridgeReceiptsThenSuccessReplacesIt() async throws {
    let now = Self.fixedStart
    let clock = ManualClock(now: now)
    let store = ProviderSnapshotStore()
    let generation = UUID()
    let five = now.addingTimeInterval(-20)
    let seven = now.addingTimeInterval(-10)
    await store.applyQuota(try QuotaSnapshot(windows: [
        .init(id: "claude.session", title: "Session", usedPercent: 10, resetsAt: nil),
        .init(id: QuotaWindow.claudeFableWeeklyID, title: "Fable", usedPercent: 20, resetsAt: nil)
    ]), for: .claude, at: now.addingTimeInterval(-100))
    await store.applyClaudeStatusLineQuota(.init(schemaVersion: 1, generation: generation,
        fiveHour: .init(usedPercent: 30, resetsAt: nil, receivedAt: five),
        sevenDay: .init(usedPercent: 40, resetsAt: nil, receivedAt: seven)))
    let quota = BlockingIntentQuotaRepository()
    let events = QuotaAttemptCollector()
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota, store: store, clock: clock,
        quotaAttemptObserver: { events.record($0) })
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [.claude: .init(
        provider: "claude", code: "authenticationExpired", message: "RAW_ERROR_TOKEN_PATH_CANARY", action: nil)]))
    await events.waitUntilCount(2)
    let failure = events.values.last
    #expect(failure?.outcome == .failure)
    #expect(failure?.failureAttemptAt == now)
    #expect(failure?.directLastSuccessfulAt == now.addingTimeInterval(-100))
    #expect(failure?.fiveHourSource == .statusLine)
    #expect(failure?.sevenDaySource == .statusLine)
    #expect(failure?.fableSource == .direct)
    #expect(failure?.fiveHourReceiptAt == five)
    #expect(failure?.sevenDayReceiptAt == seven)
    #expect(!String(describing: events.values).contains("RAW_ERROR_TOKEN_PATH_CANARY"))
    clock.setNowWithoutWakingSleepers(now.addingTimeInterval(60))
    await coordinator.popoverOpened()
    await quota.waitUntilCallCount(2)
    #expect(events.values.last?.directLastSuccessfulAt == failure?.directLastSuccessfulAt)
    #expect(events.values.last?.fiveHourReceiptAt == five)
    try quota.releaseNext(with: try quotaResult(for: .claude, usedPercent: 15))
    await events.waitUntilCount(4)
    #expect(events.values.last?.outcome == .success)
    #expect(events.values.last?.failureAttemptAt == nil)
    #expect(events.values.last?.directLastSuccessfulAt == now.addingTimeInterval(60))
    #expect(events.values.last?.fiveHourSource == .direct)
    await coordinator.stop()
}

// Amendment of 2026-10-22: the attempt's per-window source follows the shared
// presentation selection, so a status-line window older than 24 hours reads as
// unavailable. Its local receipt time is still recorded unchanged.
@Test func attemptSourceTreatsStatusLineOlderThanTwentyFourHoursAsUnavailableAndKeepsItsReceipt() async throws {
    let now = Self.fixedStart
    let store = ProviderSnapshotStore()
    let five = now.addingTimeInterval(-86_401)
    let seven = now.addingTimeInterval(-86_399)
    await store.applyClaudeStatusLineQuota(.init(schemaVersion: 1, generation: UUID(),
        fiveHour: .init(usedPercent: 30, resetsAt: nil, receivedAt: five),
        sevenDay: .init(usedPercent: 40, resetsAt: nil, receivedAt: seven)))
    let quota = BlockingIntentQuotaRepository()
    let events = QuotaAttemptCollector()
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota, store: store, clock: ManualClock(now: now),
        quotaAttemptObserver: { events.record($0) })
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [.claude: .init(
        provider: "claude", code: "authenticationExpired", message: "fixture", action: nil)]))
    await events.waitUntilCount(2)
    let failure = events.values.last
    #expect(failure?.outcome == .failure)
    #expect(failure?.fiveHourSource == .unavailable)
    #expect(failure?.sevenDaySource == .statusLine)
    #expect(failure?.fableSource == .unavailable)
    #expect(failure?.fiveHourReceiptAt == five)
    #expect(failure?.sevenDayReceiptAt == seven)
    await coordinator.stop()
}

@Test func currentResultDeterminesAttemptOutcomeWithoutCachedSuccessInference() async throws {
    let quota = BlockingIntentQuotaRepository()
    let events = QuotaAttemptCollector()
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota, store: ProviderSnapshotStore(), clock: ManualClock(now: Self.fixedStart),
        quotaAttemptObserver: { events.record($0) })
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: quotaResult(for: .claude))
    await events.waitUntilCount(2)
    await coordinator.manualRefresh()
    await quota.waitUntilCallCount(2)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    await events.waitUntilCount(4)
    #expect(events.values.last?.outcome == .unavailable)
    #expect(events.values.last?.failureAttemptAt == Self.fixedStart)
    await coordinator.manualRefresh()
    await quota.waitUntilCallCount(3)
    try quota.releaseNext(throwing: NSError(domain: "RAW_ERROR_TOKEN_PATH_CANARY", code: 1))
    await events.waitUntilCount(6)
    #expect(events.values.last?.outcome == .failure)
    #expect(!String(describing: events.values).contains("RAW_ERROR_TOKEN_PATH_CANARY"))
    let claudeFailure = events.values.last
    let codex = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .codex) }
    await quota.waitUntilCallCount(4)
    try quota.releaseNext(with: quotaResult(for: .codex))
    #expect(await codex.valueUnlessCancelled == true)
    #expect(events.values.last?.outcome == .success)
    #expect(events.values.last?.trigger == .manual)
    #expect(events.values.last?.failureAttemptAt == claudeFailure?.failureAttemptAt)
    #expect(events.values.last?.directLastSuccessfulAt == claudeFailure?.directLastSuccessfulAt)
    #expect(events.values.last?.fiveHourSource == claudeFailure?.fiveHourSource)
    await coordinator.stop()
}

@Test func statusLineOnlyRecoveryDoesNotEmitDirectAttemptOrSuccess() async throws {
    let now = Self.fixedStart
    let generation = UUID()
    let cache = StatusLineCacheSpy(generation: generation, record: .init(schemaVersion: 1,
        generation: generation, fiveHour: .init(usedPercent: 12, resetsAt: nil, receivedAt: now), sevenDay: nil))
    let quota = BlockingIntentQuotaRepository()
    let events = QuotaAttemptCollector()
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota, store: ProviderSnapshotStore(), clock: ManualClock(now: now),
        statusLineRepository: cache, quotaAttemptObserver: { events.record($0) })
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    await events.waitUntilCount(2)
    await cache.waitUntilReadCount(1)
    let previous = events.values
    let token = await coordinator.recoveryRequestToken()
    await token.submit(.wake)
    await cache.waitUntilReadCount(2)
    #expect(events.values == previous)
    #expect(quota.callCount == 1)
    #expect(events.values.last?.directLastSuccessfulAt == nil)
    #expect(events.values.last?.outcome == .unavailable)
    await coordinator.stop()
}

@Test func codexOnlyCompletionKeepsThePriorClaudeProjection() async throws {
    let now = Self.fixedStart
    let quota = BlockingIntentQuotaRepository()
    let store = ProviderSnapshotStore()
    let events = QuotaAttemptCollector()
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota, store: store, clock: ManualClock(now: now),
        quotaAttemptObserver: { events.record($0) })
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: try quotaResult(for: .claude, usedPercent: 20))
    await events.waitUntilCount(2)
    let previous = events.values.last
    let codex = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .codex) }
    await quota.waitUntilCallCount(2)
    await store.markQuotaFailure(for: .claude, status: .requiresAuthentication, at: now)
    await store.applyClaudeStatusLineQuota(.init(schemaVersion: 1, generation: UUID(),
        fiveHour: .init(usedPercent: 60, resetsAt: nil, receivedAt: now), sevenDay: nil))
    try quota.releaseNext(with: quotaResult(for: .codex))
    #expect(await codex.valueUnlessCancelled == true)
    #expect(events.values.last?.outcome == .success)
    #expect(events.values.last?.fiveHourSource == previous?.fiveHourSource)
    #expect(events.values.last?.fiveHourReceiptAt == previous?.fiveHourReceiptAt)
    #expect(events.values.last?.failureAttemptAt == previous?.failureAttemptAt)
    await coordinator.stop()
}

@Test func stopDuringLegacyCallbackInvalidatesAndCannotCompleteAfterResume() async throws {
    let quota = BlockingIntentQuotaRepository()
    let callback = QuotaApplicationGate()
    let events = QuotaAttemptCollector()
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota, store: ProviderSnapshotStore(), clock: ManualClock(now: Self.fixedStart),
        claudeQuotaOperationCompleted: { await callback.pause() }, quotaAttemptObserver: { events.record($0) })
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: quotaResult(for: .claude))
    await callback.waitUntilEntered()
    await coordinator.stop()
    await callback.resume()
    await settle(watchingFor: { events.values.count > 2 })
    #expect(events.values.map(\.phase) == [.started, .invalidated])
}

@Test func unclaimedOldGenerationCannotStartARepositoryAttempt() {
    let events = QuotaAttemptCollector()
    let ledger = QuotaAttemptLedger(observer: { events.record($0) })
    let id = UUID()
    ledger.reserve(id: id, generation: 0, trigger: .popover)
    ledger.advance(to: 1)
    #expect(ledger.claim(id: id, generation: 0, at: Self.fixedStart, backgroundClock: nil) == nil)
    #expect(events.values.isEmpty)
    let current = UUID()
    ledger.reserve(id: current, generation: 1, trigger: .startup)
    #expect(ledger.claim(id: current, generation: 1, at: Self.fixedStart, backgroundClock: nil)?.id == current)
    #expect(events.values.map(\.phase) == [.started])
}

@Test func wakeReadsCacheImmediatelyButOnlyFetchesAtFiveMinutes() async throws {
    let now = Date(timeIntervalSince1970: 0)
    let clock = ManualClock(now: now)
    let quota = BlockingIntentQuotaRepository()
    let generation = UUID()
    let cache = StatusLineCacheSpy(generation: generation, record: .init(
        schemaVersion: 1, generation: generation, fiveHour: nil, sevenDay: nil))
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota, store: ProviderSnapshotStore(), clock: clock,
        statusLineRepository: cache)
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: quotaResult(for: .claude))
    let token = await coordinator.recoveryRequestToken()
    await cache.waitUntilReadCount(1)
    clock.setNowWithoutWakingSleepers(now.addingTimeInterval(299))
    await token.submit(.wake)
    await cache.waitUntilReadCount(2)
    #expect(cache.readCount == 2)
    #expect(quota.callCount == 1)
    clock.setNowWithoutWakingSleepers(now.addingTimeInterval(300))
    await token.submit(.connectivity)
    await quota.waitUntilCallCount(2)
    #expect(quota.callCount == 2)
    quota.forbidAdditionalCalls()
    if quota.callCount == 2 { try quota.releaseNext(with: quotaResult(for: .claude)) }
    await coordinator.stop()
}

@Test func recoveryUsesFreshPopoverAttemptRatherThanStartupAttempt() async throws {
    let now = Date(timeIntervalSince1970: 0)
    let clock = ManualClock(now: now)
    let quota = BlockingIntentQuotaRepository()
    let completed = ClaudeQuotaCompletionRecorder()
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota, store: ProviderSnapshotStore(), clock: clock,
        claudeQuotaOperationCompleted: { await completed.record() })
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: quotaResult(for: .claude))
    await completed.waitUntilCount(1)
    clock.setNowWithoutWakingSleepers(now.addingTimeInterval(100))
    await coordinator.popoverOpened()
    await quota.waitUntilCallCount(2)
    try quota.releaseNext(with: quotaResult(for: .claude))
    await completed.waitUntilCount(2)
    let token = await coordinator.recoveryRequestToken()
    clock.setNowWithoutWakingSleepers(now.addingTimeInterval(399))
    await token.submit(.wake)
    await settle(watchingFor: { quota.callCount == 3 })
    #expect(quota.callCount == 2)
    clock.setNowWithoutWakingSleepers(now.addingTimeInterval(400))
    await token.submit(.connectivity)
    await quota.waitUntilCallCount(3)
    #expect(quota.callCount == 3)
    quota.forbidAdditionalCalls()
    if quota.callCount == 3 { try quota.releaseNext(with: quotaResult(for: .claude)) }
    await coordinator.stop()
}

@Test func recoveryBeforeAndImmediatelyAfterStartDoesNotDuplicateStartup() async throws {
    let quota = BlockingIntentQuotaRepository()
    let completed = ClaudeQuotaCompletionRecorder()
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota, store: ProviderSnapshotStore(),
        clock: ManualClock(now: Date(timeIntervalSince1970: 0)),
        claudeQuotaOperationCompleted: { await completed.record() })
    let oldToken = await coordinator.recoveryRequestToken()
    await oldToken.submit(.wake)
    #expect(quota.callCount == 0)
    await coordinator.start()
    let token = await coordinator.recoveryRequestToken()
    await token.submit(.connectivity)
    await quota.waitUntilCallCount(1)
    quota.forbidAdditionalCalls()
    try quota.releaseNext(with: quotaResult(for: .claude))
    await completed.waitUntilCount(1)
    await settle(watchingFor: { !quota.unexpectedIntents.isEmpty })
    #expect(quota.callCount == 1)
    #expect(quota.unexpectedIntents.isEmpty)
    await coordinator.stop()
}

@Test(arguments: [false, true])
func recoveryBurstQueuesOneAggregateFollowUp(includesPopover: Bool) async throws {
    let clock = ManualClock(now: Date(timeIntervalSince1970: 0))
    let quota = BlockingIntentQuotaRepository()
    let completed = ClaudeQuotaCompletionRecorder()
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota, store: ProviderSnapshotStore(), clock: clock,
        claudeQuotaOperationCompleted: { await completed.record() })
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    let token = await coordinator.recoveryRequestToken()
    clock.setNowWithoutWakingSleepers(Date(timeIntervalSince1970: 300))
    for _ in 0 ..< 3 {
        await token.submit(.wake)
        await token.submit(.connectivity)
        if includesPopover { await coordinator.popoverOpened() }
    }
    #expect(quota.callCount == 1)
    try quota.releaseNext(with: quotaResult(for: .claude))
    await quota.waitUntilCallCount(2)
    #expect(quota.callCount == 2)
    quota.forbidAdditionalCalls()
    if quota.callCount == 2 { try quota.releaseNext(with: quotaResult(for: .claude)) }
    await completed.waitUntilCount(2)
    #expect(await completed.count == 2)
    await settle(watchingFor: { !quota.unexpectedIntents.isEmpty })
    #expect(quota.intents == [.backgroundAll, .backgroundAll])
    #expect(quota.unexpectedIntents.isEmpty)
    await coordinator.stop()
}

@Test func forcedAggregateUpgradesPendingRecoveryWithoutAnotherTicket() async throws {
    let clock = ManualClock(now: Date(timeIntervalSince1970: 0))
    let quota = BlockingIntentQuotaRepository()
    let gate = QuotaApplicationGate()
    let completed = ClaudeQuotaCompletionRecorder()
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota, store: ProviderSnapshotStore(), clock: clock,
        quotaApplicationWillApply: { await gate.pause() },
        claudeQuotaOperationCompleted: { await completed.record() })
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: quotaResult(for: .claude))
    await gate.waitUntilEntered()
    let token = await coordinator.recoveryRequestToken()
    clock.setNowWithoutWakingSleepers(Date(timeIntervalSince1970: 300))
    await token.submit(.wake)
    await coordinator.popoverOpened()
    await gate.resume()
    await quota.waitUntilCallCount(2)
    #expect(quota.callCount == 2)
    await token.submit(.connectivity)
    quota.forbidAdditionalCalls()
    if quota.callCount == 2 { try quota.releaseNext(with: quotaResult(for: .claude)) }
    await completed.waitUntilCount(2)
    #expect(await completed.count == 2)
    await settle(watchingFor: { !quota.unexpectedIntents.isEmpty })
    #expect(quota.unexpectedIntents.isEmpty)
    await coordinator.stop()
}

@Test(arguments: [true, false])
func periodicAndRecoveryBoundaryShareOnePhysicalAttempt(periodicFirst: Bool) async throws {
    let clock = ManualClock(now: Date(timeIntervalSince1970: 0))
    let quota = BlockingIntentQuotaRepository()
    let completed = ClaudeQuotaCompletionRecorder()
    let generation = UUID()
    let cache = StatusLineCacheSpy(generation: generation, record: .init(
        schemaVersion: 1, generation: generation, fiveHour: nil, sevenDay: nil))
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota, store: ProviderSnapshotStore(), clock: clock,
        statusLineRepository: cache,
        claudeQuotaOperationCompleted: { await completed.record() })
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: quotaResult(for: .claude))
    await completed.waitUntilCount(1)
    #expect(await completed.count == 1)
    await cache.waitUntilReadCount(1)
    await clock.waitUntilSleeperCount(2)
    let token = await coordinator.recoveryRequestToken()
    if periodicFirst {
        clock.advance(by: 300)
    } else {
        clock.setNowWithoutWakingSleepers(Date(timeIntervalSince1970: 300))
        await token.submit(.wake)
    }
    await quota.waitUntilCallCount(2)
    #expect(quota.callCount == 2)
    if periodicFirst {
        await token.submit(.wake)
        await token.submit(.connectivity)
    } else {
        await cache.waitUntilReadCount(2)
        clock.advance(by: 0)
        await clock.waitUntilSleeperCount(2)
        await cache.waitUntilReadCount(3)
        #expect(cache.readCount == 3)
    }
    quota.forbidAdditionalCalls()
    if quota.callCount == 2 { try quota.releaseNext(with: quotaResult(for: .claude)) }
    await completed.waitUntilCount(2)
    #expect(await completed.count == 2)
    await settle(watchingFor: { !quota.unexpectedIntents.isEmpty })
    #expect(quota.intents == [.backgroundAll, .backgroundAll])
    #expect(quota.unexpectedIntents.isEmpty)
    await coordinator.stop()
}

@Test func recoveryTokenCannotCrossStopRestartOrOverlapOldPhysicalCall() async throws {
    let clock = ManualClock(now: Date(timeIntervalSince1970: 0))
    let quota = BlockingIntentQuotaRepository()
    let store = ProviderSnapshotStore()
    let gate = QuotaApplicationGate()
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota, store: store, clock: clock,
        quotaApplicationWillApply: { await gate.pause() })
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    let oldToken = await coordinator.recoveryRequestToken()
    clock.setNowWithoutWakingSleepers(Date(timeIntervalSince1970: 300))
    await coordinator.stop()
    await coordinator.start()
    await oldToken.submit(.wake)
    await settle(watchingFor: { quota.callCount == 2 })
    #expect(quota.callCount == 1)
    try quota.releaseNext(with: quotaResult(for: .claude, usedPercent: 10))
    await quota.waitUntilCallCount(2)
    #expect(quota.callCount == 2)
    #expect(await store.snapshot(for: .claude).quota == nil)
    quota.forbidAdditionalCalls()
    if quota.callCount == 2 { try quota.releaseNext(with: quotaResult(for: .claude, usedPercent: 60)) }
    if quota.callCount == 2 {
        await gate.waitUntilEntered()
        #expect(await store.snapshot(for: .claude).quota == nil)
    }
    await gate.resume()
    await pollUntil { await store.snapshot(for: .claude).quota?.windows.first?.usedPercent == 60 }
    #expect(await store.snapshot(for: .claude).quota?.windows.first?.usedPercent == 60)
    await settle(watchingFor: { !quota.unexpectedIntents.isEmpty })
    #expect(quota.unexpectedIntents.isEmpty)
    await coordinator.stop()
}

@Test func recoveryTicketRechecksClockAndStillDrainsAfterTicketUserWaiter() async throws {
    let clock = ManualClock(now: Date(timeIntervalSince1970: 0))
    let quota = BlockingIntentQuotaRepository()
    let gate = QuotaApplicationGate()
    let registrations = QuotaIntentRegistrationGate()
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota, store: ProviderSnapshotStore(), clock: clock,
        quotaApplicationWillApply: { await gate.pause() },
        quotaIntentRegistered: { registrations.record($0) })
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: quotaResult(for: .claude))
    await gate.waitUntilEntered()
    let token = await coordinator.recoveryRequestToken()
    clock.setNowWithoutWakingSleepers(Date(timeIntervalSince1970: 300))
    await token.submit(.wake)
    let user = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .codex) }
    await registrations.waitUntil([.backgroundAll, .userInitiated(provider: .codex)])
    #expect(registrations.intents == [.backgroundAll, .userInitiated(provider: .codex)])
    // A wall-clock adjustment makes the already queued automatic ticket no
    // longer due. It must still release the user waiter queued after it.
    clock.setNowWithoutWakingSleepers(Date(timeIntervalSince1970: 299))
    await gate.resume()
    await quota.waitUntilCallCount(2)
    #expect(quota.intents == [.backgroundAll, .userInitiated(provider: .codex)])
    quota.forbidAdditionalCalls()
    if quota.callCount == 2 { try quota.releaseNext(with: quotaResult(for: .codex)) }
    if quota.callCount < 2 { await coordinator.stop() }
    #expect(await user.valueUnlessCancelled == true)
    #expect(quota.unexpectedIntents.isEmpty)
    await coordinator.stop()
}

@Test func preStartCacheReadCannotBlockTheNewRunCacheRead() async {
    let now = Date(timeIntervalSince1970: 0)
    let generation = UUID()
    let cache = StatusLineCacheSpy(generation: generation, record: .init(
        schemaVersion: 1, generation: generation,
        fiveHour: .init(usedPercent: 25, resetsAt: now.addingTimeInterval(3600), receivedAt: now),
        sevenDay: nil))
    let gate = QuotaApplicationGate()
    let applications = ClaudeQuotaCompletionRecorder()
    let store = ProviderSnapshotStore(now: { now })
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: QuotaRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        store: store, clock: ManualClock(now: now), lastQuotaSuccessfulAt: now,
        statusLineApplicationWillApply: {
            await applications.record()
            if await applications.count == 1 { await gate.pause() }
        }, statusLineRepository: cache)
    await coordinator.popoverOpened()
    await gate.waitUntilEntered()
    await coordinator.start()
    await gate.resume()
    await pollUntil { await store.snapshot(for: .claude).claudeStatusLineQuota != nil }
    #expect(cache.readCount == 2)
    #expect(await store.snapshot(for: .claude).claudeStatusLineQuota?.fiveHour?.usedPercent == 25)
    await coordinator.stop()
}

@Test func recoveryDuringCacheApplicationReadsActiveConnectionOnceMore() async throws {
    let now = Date(timeIntervalSince1970: 0)
    let generation = UUID()
    let cache = StatusLineCacheSpy(generation: generation, record: .init(
        schemaVersion: 1, generation: generation,
        fiveHour: .init(usedPercent: 25, resetsAt: now.addingTimeInterval(3600), receivedAt: now),
        sevenDay: nil))
    let gate = QuotaApplicationGate()
    let store = ProviderSnapshotStore(now: { now })
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: QuotaRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        store: store, clock: ManualClock(now: now),
        statusLineApplicationWillApply: { await gate.pause() }, statusLineRepository: cache)
    await coordinator.start()
    await gate.waitUntilEntered()
    let token = await coordinator.recoveryRequestToken()
    await token.submit(.wake)
    await token.submit(.connectivity)
    let active = UUID()
    cache.connect(generation: active, record: .init(
        schemaVersion: 1, generation: active,
        fiveHour: .init(usedPercent: 60, resetsAt: now.addingTimeInterval(3600), receivedAt: now),
        sevenDay: nil))
    await gate.resume()
    await pollUntil { await store.snapshot(for: .claude).claudeStatusLineQuota?.generation == active }
    #expect(cache.readCount == 2)
    #expect(await store.snapshot(for: .claude).claudeStatusLineQuota?.fiveHour?.usedPercent == 60)
    await coordinator.stop()
}

@Test func localStatusLineReadSurvivesDirectFailureAndClearsAfterDisconnectOnNextCadence() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let generation = UUID()
    let cache = StatusLineCacheSpy(generation: generation, record: .init(
        schemaVersion: StatusLineQuotaRecord.currentSchemaVersion,
        generation: generation,
        fiveHour: .init(usedPercent: 25, resetsAt: now.addingTimeInterval(3_600), receivedAt: now),
        sevenDay: nil
    ))
    let store = ProviderSnapshotStore(now: { now })
    let quota = QuotaRefreshSpy(result: .init(snapshots: [:], errors: [
        .claude: .init(provider: "claude", code: "authenticationExpired", message: "fixture", action: nil)
    ]))
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota,
        store: store,
        clock: ManualClock(now: now),
        statusLineRepository: cache
    )
    await coordinator.start()
    await pollUntil { await store.snapshot(for: .claude).claudeStatusLineQuota != nil }
    await pollUntil { await store.snapshot(for: .claude).claudeQuotaFailureReason == .quotaAccessUnavailable }
    #expect(cache.readCount == 1)
    #expect(await store.snapshot(for: .claude).quota == nil)

    cache.disconnect()
    await coordinator.manualRefresh()
    await pollUntil { await store.snapshot(for: .claude).claudeStatusLineQuota == nil }
    #expect(await store.snapshot(for: .claude).claudeQuotaFailureReason == .quotaAccessUnavailable)
    await coordinator.stop()
}

@Test func popoverReadsLocalStatusLineEvenWhenDirectQuotaIsTooRecentToRefresh() async {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let generation = UUID()
    let cache = StatusLineCacheSpy(generation: generation, record: .init(
        schemaVersion: StatusLineQuotaRecord.currentSchemaVersion,
        generation: generation,
        fiveHour: .init(usedPercent: 40, resetsAt: now.addingTimeInterval(3_600), receivedAt: now),
        sevenDay: nil
    ))
    let store = ProviderSnapshotStore(now: { now })
    let quota = QuotaRefreshSpy(result: .init(snapshots: [:], errors: [:]))
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota,
        store: store,
        clock: ManualClock(now: now),
        lastQuotaSuccessfulAt: now,
        statusLineRepository: cache
    )
    await coordinator.popoverOpened()
    await pollUntil { await store.snapshot(for: .claude).claudeStatusLineQuota != nil }
    #expect(await store.snapshot(for: .claude).claudeStatusLineQuota?.fiveHour?.usedPercent == 40)
    #expect(cache.readCount == 1)
    #expect(quota.callCount == 0)
    await coordinator.stop()
}

@Test func disconnectWhileOldReadWaitsToApplyCannotResurrectClaudeQuota() async {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let generation = UUID()
    let old = StatusLineQuotaRecord(
        schemaVersion: StatusLineQuotaRecord.currentSchemaVersion, generation: generation,
        fiveHour: .init(usedPercent: 25, resetsAt: now.addingTimeInterval(3_600), receivedAt: now), sevenDay: nil
    )
    let cache = StatusLineCacheSpy(generation: generation, record: old)
    let gate = QuotaApplicationGate()
    let store = ProviderSnapshotStore(now: { now })
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: QuotaRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        store: store, clock: ManualClock(now: now),
        statusLineApplicationWillApply: { await gate.pause() }, statusLineRepository: cache
    )

    await coordinator.popoverOpened()
    await gate.waitUntilEntered()
    cache.disconnect()
    await store.reconcileClaudeStatusLineQuota(activeGeneration: { cache.activeGeneration() })
    await gate.resume()
    await cache.waitUntilActiveGenerationChecks(3)

    #expect(await store.snapshot(for: .claude).claudeStatusLineQuota == nil)
    await coordinator.stop()
}

@Test func oldReadCannotReplaceNewlyConnectedGeneration() async {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let oldGeneration = UUID()
    let old = StatusLineQuotaRecord(
        schemaVersion: StatusLineQuotaRecord.currentSchemaVersion, generation: oldGeneration,
        fiveHour: .init(usedPercent: 25, resetsAt: now.addingTimeInterval(3_600), receivedAt: now), sevenDay: nil
    )
    let cache = StatusLineCacheSpy(generation: oldGeneration, record: old)
    let gate = QuotaApplicationGate()
    let store = ProviderSnapshotStore(now: { now })
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: QuotaRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        store: store, clock: ManualClock(now: now),
        statusLineApplicationWillApply: { await gate.pause() }, statusLineRepository: cache
    )

    await coordinator.popoverOpened()
    await gate.waitUntilEntered()
    cache.disconnect()
    await store.reconcileClaudeStatusLineQuota(activeGeneration: { cache.activeGeneration() })
    let newGeneration = UUID()
    let newer = StatusLineQuotaRecord(
        schemaVersion: StatusLineQuotaRecord.currentSchemaVersion, generation: newGeneration,
        fiveHour: .init(usedPercent: 60, resetsAt: now.addingTimeInterval(3_600), receivedAt: now), sevenDay: nil
    )
    cache.connect(generation: newGeneration, record: newer)
    await store.applyClaudeStatusLineQuota(newer, expectedGeneration: newGeneration,
                                          activeGeneration: { cache.activeGeneration() })
    // A delayed disconnect callback must preserve the newly connected generation.
    await store.reconcileClaudeStatusLineQuota(activeGeneration: { cache.activeGeneration() })
    await gate.resume()
    await cache.waitUntilActiveGenerationChecks(5)

    let retained = await store.snapshot(for: .claude).claudeStatusLineQuota
    #expect(retained?.generation == newGeneration)
    #expect(retained?.fiveHour?.usedPercent == 60)
    await coordinator.stop()
}

private final class StatusLineCacheSpy: ClaudeStatusLineCacheReading, @unchecked Sendable {
    private let lock = NSLock()
    private let changes = ConditionWaiters()
    private var generation: UUID?
    private var record: StatusLineQuotaRecord
    private var reads = 0
    private var activeChecks = 0

    init(generation: UUID, record: StatusLineQuotaRecord) {
        self.generation = generation
        self.record = record
    }

    var readCount: Int { lock.withLock { reads } }
    var activeGenerationChecks: Int { lock.withLock { activeChecks } }

    func activeGeneration() -> UUID? {
        let active = lock.withLock { () -> UUID? in
            activeChecks += 1
            return generation
        }
        changes.signal()
        return active
    }

    func read(expectedGeneration: UUID) -> StatusLineQuotaRecord? {
        let result = lock.withLock { () -> StatusLineQuotaRecord? in
            reads += 1
            return generation == expectedGeneration ? record : nil
        }
        changes.signal()
        return result
    }

    func waitUntilReadCount(_ expectedCount: Int) async {
        await changes.wait { self.readCount >= expectedCount }
    }

    func waitUntilActiveGenerationChecks(_ expectedCount: Int) async {
        await changes.wait { self.activeGenerationChecks >= expectedCount }
    }

    func disconnect() { lock.withLock { generation = nil } }
    func connect(generation: UUID, record: StatusLineQuotaRecord) {
        lock.withLock {
            self.generation = generation
            self.record = record
        }
    }
}

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
    await pollUntil { await store.snapshot(for: .claude).quotaStatus == .requiresAuthentication }
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
    await pollUntil { await store.snapshot(for: .cursor).quotaStatus == .unavailable }

    #expect(await store.snapshot(for: .cursor).quotaStatus == .unavailable)
    #expect(await store.snapshot(for: .claude).quotaStatus == .error(message: "Claude unavailable", lastSuccessfulAt: nil))
        await coordinator.stop()
    }

    @Test func returnedClaudeQuotaErrorsMapOnlyAllowlistedCodesToSafeReasons() async throws {
        let cases: [(String, ClaudeQuotaFailureReason)] = [
            ("requiresAuthentication", .quotaAccessUnavailable),
            ("authenticationExpired", .quotaAccessUnavailable),
            ("permissionDenied", .credentialAccessUnavailable),
            ("networkUnavailable", .connectionUnavailable),
            ("rateLimited", .temporarilyLimited),
            ("notInstalled", .couldNotUpdateQuota),
            ("providerUnavailable", .couldNotUpdateQuota),
            ("schemaChanged", .couldNotUpdateQuota),
            ("internalError", .couldNotUpdateQuota),
            ("", .couldNotUpdateQuota),
            ("unknown-code", .couldNotUpdateQuota),
        ]

        for (code, expectedReason) in cases {
            let now = try #require(BridgeDecoder.date("2026-09-15T12:00:00Z"))
            let store = ProviderSnapshotStore()
            let completionGate = QuotaApplicationGate()
            let quota = QuotaRefreshSpy(result: .init(
                snapshots: [:],
                errors: [.claude: .init(provider: "claude", code: code, message: "untrusted raw detail", action: nil)]
            ))
            let coordinator = RefreshCoordinator(
                usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
                quotaRepository: quota,
                store: store,
                clock: ManualClock(now: now),
                claudeQuotaOperationCompleted: { await completionGate.pause() }
            )

            await coordinator.popoverOpened()
            await quota.waitUntilCallCount(1)
            await completionGate.waitUntilEntered()
            let actualReason = await store.snapshot(for: .claude).claudeQuotaFailureReason
            #expect(
                actualReason == expectedReason,
                "Claude quota error code '\(code)' mapped to \(String(describing: actualReason)); expected \(expectedReason)"
            )
            await completionGate.resume()
            await coordinator.stop()
        }
    }

    @Test func bridgeFailuresAndUntypedQuotaFailuresUseSafeClaudeReasons() async throws {
        let quota = BlockingIntentQuotaRepository()
        let store = ProviderSnapshotStore()
        let coordinator = makeRunningCoordinator(quota: quota, store: store)
        await coordinator.start()
        await quota.waitUntilCallCount(1)
        try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))

        let cases: [(String, ClaudeQuotaFailureReason)] = [
            ("requiresAuthentication", .quotaAccessUnavailable),
            ("authenticationExpired", .quotaAccessUnavailable),
            ("permissionDenied", .credentialAccessUnavailable),
            ("networkUnavailable", .connectionUnavailable),
            ("rateLimited", .temporarilyLimited),
            ("notInstalled", .couldNotUpdateQuota),
            ("providerUnavailable", .couldNotUpdateQuota),
            ("schemaChanged", .couldNotUpdateQuota),
            ("internalError", .couldNotUpdateQuota),
            ("", .couldNotUpdateQuota),
            ("unknown-code", .couldNotUpdateQuota),
        ]
        for (index, entry) in cases.enumerated() {
            let bridgeRefresh = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
            await quota.waitUntilCallCount(index + 2)
            try quota.releaseNext(throwing: BridgeFailure.bridgeFailed([
                .init(provider: "claude", code: entry.0, message: "untrusted raw detail", action: nil)
            ]))
            #expect(await bridgeRefresh.valueUnlessCancelled == false)
            await pollUntil { await store.snapshot(for: .claude).claudeQuotaFailureReason == entry.1 }
        }

        let untypedRefresh = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
        await quota.waitUntilCallCount(cases.count + 2)
        try quota.releaseNext(throwing: BlockingQuotaRepositoryError.missingOutcome)
        #expect(await untypedRefresh.valueUnlessCancelled == false)
        await pollUntil { await store.snapshot(for: .claude).claudeQuotaFailureReason == .couldNotUpdateQuota }
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
    await usage.waitUntilCallCount(1)

    let manual = Task { await coordinator.manualRefresh() }
    await Task.yield()
    #expect(usage.callCount == 1)

    usage.releaseFirstCall()
    _ = await manual.valueUnlessCancelled
    await usage.waitUntilCallCount(2)

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
    await usage.waitUntilCallCount(1)

    var manualRequests: [Task<Void, Never>] = []
    for _ in 0 ..< 3 {
        manualRequests.append(Task { await coordinator.manualRefresh() })
        for _ in 0 ..< 10 {
            await Task.yield()
        }
    }

    usage.releaseFirstCall()
    await usage.waitUntilCallCount(2)
    await usage.waitUntilCompletedCallCount(2)
    for request in manualRequests {
        _ = await request.valueUnlessCancelled
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
    // Advance only once both startup calls ran and both safety loops are asleep.
    // A bounded wait could give up first; a loop that then sleeps from the
    // advanced clock never reaches its deadline, so the waits below never return.
    await usage.waitUntilCallCount(1)
    await quota.waitUntilCallCount(1)
    await clock.waitUntilSleeperCount(2)

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
    await usage.waitUntilCallCount(1)
    await coordinator.stop()
    await coordinator.start()
    await Task.yield()

    #expect(usage.callCount == 1)
    usage.releaseFirstCall()
    await usage.waitUntilCallCount(2)
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
    await pollUntil { await watcher.firstStartIsSuspended }

    await coordinator.stop()
    await coordinator.start()
    await usage.waitUntilCallCount(1)

    await watcher.resumeFirstStart()
    _ = await firstStart.valueUnlessCancelled

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
    await usage.waitUntilCompletedCallCount(1)

    let verification = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
    await quota.waitUntilCallCount(2)
    try quota.releaseNext(with: quotaResult(for: .claude))

    #expect(await verification.valueUnlessCancelled == true)
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

    #expect(await verification.valueUnlessCancelled == true)
    #expect(quota.intents == [.backgroundAll, .userInitiated(provider: .claude)])
    await coordinator.stop()
}

@Test func blockingQuotaRepositoryRejectsAReleaseBeforeAnyCallRegisters() async throws {
    let quota = BlockingIntentQuotaRepository()

    #expect(throws: BlockingQuotaRepositoryError.unexpectedRelease) {
        try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    }
}

@Test func testWaitsEndWhenTheirTaskIsCancelled() async {
    // The time limit can end a test only by cancelling it, so each wait must
    // return once cancelled even though its condition never arrives.
    let gate = QuotaApplicationGate()
    let held = Task { await gate.pause() }
    let quota = BlockingIntentQuotaRepository()
    let usage = RecordingUsageRepository()
    let clock = ManualClock(now: Self.fixedStart)
    let registrations = QuotaIntentRegistrationGate()
    let completions = ClaudeQuotaCompletionRecorder()
    let events = QuotaAttemptCollector()
    let cache = StatusLineCacheSpy(generation: UUID(), record: .init(
        schemaVersion: 1, generation: UUID(), fiveHour: nil, sevenDay: nil))
    let waits: [(String, @Sendable () async -> Void)] = [
        ("quota calls", { await quota.waitUntilCallCount(1) }),
        ("completed usage calls", { await usage.waitUntilCompletedCallCount(1) }),
        ("sleepers", { await clock.waitUntilSleeperCount(1) }),
        ("intent registrations", { await registrations.waitUntil([.backgroundAll]) }),
        ("attempt events", { await events.waitUntilCount(1) }),
        ("cache reads", { await cache.waitUntilReadCount(1) }),
        ("gate entry", { await QuotaApplicationGate().waitUntilEntered() }),
        ("completions", { await completions.waitUntilCount(1) }),
        ("task value", { _ = await held.valueUnlessCancelled }),
    ]
    for (name, wait) in waits {
        let waiting = Task { await wait(); return true }
        try? await Task.sleep(for: .milliseconds(10))
        waiting.cancel()
        #expect(await waiting.valueUnlessCancelled == true, "the \(name) wait must end once cancelled")
    }
    await gate.resume()
    _ = await held.valueUnlessCancelled
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

    let verified = await verification.valueUnlessCancelled
    #expect(verified == false)
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

    #expect(await verification.valueUnlessCancelled == false)
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

    #expect(await verification.valueUnlessCancelled == true)
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
        #expect(await caller.valueUnlessCancelled == true)
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
    let claudeVerified = await claude.valueUnlessCancelled
    #expect(claudeVerified == false)
    try quota.releaseNext(with: quotaResult(for: .codex))

    #expect(await codex.valueUnlessCancelled == true)
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
    let verified = await verification.valueUnlessCancelled
    #expect(verified == false)
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
    #expect(await verification.valueUnlessCancelled == true)

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
    #expect(verified == false)
    #expect(quota.callCount == 1)
    await coordinator.stop()
}

@Test func claudePreflightClassifiesTheCurrentSilentResultBeforeCachedQuota() async throws {
    let quota = BlockingIntentQuotaRepository()
    let store = ProviderSnapshotStore()
    let cached = QuotaSnapshot(windows: [try .init(id: "claude.session", title: "Session", usedPercent: 42, resetsAt: nil)])
    await store.applyQuota(cached, for: .claude)
    let coordinator = makeRunningCoordinator(quota: quota, store: store)
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))

    let authentication = Task { await coordinator.preflightClaudeLogin() }
    await quota.waitUntilCallCount(2)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [.claude: BridgeError(provider: "claude", code: "requiresAuthentication", message: "sign in", action: nil)]))
    #expect(await authentication.valueUnlessCancelled == .requiresAuthentication)
    #expect(await store.snapshot(for: .claude).quota == cached)

    let expiredAuthentication = Task { await coordinator.preflightClaudeLogin() }
    await quota.waitUntilCallCount(3)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [.claude: BridgeError(provider: "claude", code: "authenticationExpired", message: "expired", action: nil)]))
    #expect(await expiredAuthentication.valueUnlessCancelled == .requiresAuthentication)

    let permission = Task { await coordinator.preflightClaudeLogin() }
    await quota.waitUntilCallCount(4)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [.claude: permissionDenied(for: .claude)]))
    #expect(await permission.valueUnlessCancelled == .keychainPermissionRequired)

    let failed = Task { await coordinator.preflightClaudeLogin() }
    await quota.waitUntilCallCount(5)
    try quota.releaseNext(with: .init(snapshots: [.claude: cached], errors: [.claude: BridgeError(provider: "claude", code: "networkUnavailable", message: "offline", action: nil)]))
    #expect(await failed.valueUnlessCancelled == .verificationFailed)
    await coordinator.stop()
}

@Test func claudePreflightCoalescesCallersAndStopCompletesThemOnceWithFailure() async throws {
    let quota = BlockingIntentQuotaRepository()
    let coordinator = makeRunningCoordinator(quota: quota)
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))

    let first = Task { await coordinator.preflightClaudeLogin() }
    let second = Task { await coordinator.preflightClaudeLogin() }
    await quota.waitUntilCallCount(2)
    #expect(quota.intents == [.backgroundAll, .claudePreflight])
    await coordinator.stop()

    #expect(await first.valueUnlessCancelled == .verificationFailed)
    #expect(await second.valueUnlessCancelled == .verificationFailed)
    try quota.releaseNext(with: quotaResult(for: .claude))
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
    await quota.waitUntilCallCount(1)
    await clock.waitUntilSleeperCount(2)
    await coordinator.manualRefresh()
    await quota.waitUntilCallCount(2)
    await coordinator.popoverOpened()
    await quota.waitUntilCallCount(3)
    clock.advance(by: 5 * 60)
    await quota.waitUntilCallCount(4)

    #expect(quota.callCount == 4)
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

    let verified = await verification.valueUnlessCancelled
    #expect(verified == false)
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

    #expect(await first.valueUnlessCancelled == true)
    #expect(quota.callCount == 2)
    #expect(await joining.valueUnlessCancelled == true)
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
    #expect(await aheadClaude.valueUnlessCancelled == true)
    await quota.waitUntilCallCount(3)
    #expect(quota.intents[2] == .backgroundAll)

    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    await quota.waitUntilCallCount(4)
    #expect(quota.intents[3] == .userInitiated(provider: .claude))
    try quota.releaseNext(with: quotaResult(for: .claude))
    await quota.waitUntilCallCount(5)
    #expect(quota.intents[4] == .userInitiated(provider: .codex))
    try quota.releaseNext(with: quotaResult(for: .codex))

    #expect(await behindClaude.valueUnlessCancelled == true)
    #expect(await behindCodex.valueUnlessCancelled == true)
    _ = await manual.valueUnlessCancelled
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
    #expect(await oldVerification.valueUnlessCancelled == false)
    await coordinator.start()
    let newVerification = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }

    try quota.releaseNext(with: try quotaResult(for: .claude, usedPercent: 10))
    await quota.waitUntilCallCount(3)
    #expect(quota.intents[2] == .backgroundAll)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    await quota.waitUntilCallCount(4)
    #expect(quota.intents[3] == .userInitiated(provider: .claude))
    try quota.releaseNext(with: try quotaResult(for: .claude, usedPercent: 20))

    #expect(await newVerification.valueUnlessCancelled == true)
    let expected = try QuotaSnapshot(windows: [.init(id: "claude.session", title: "Session", usedPercent: 20, resetsAt: nil)])
    await pollUntil { await store.snapshot(for: .claude).quota == expected }
    #expect(await store.snapshot(for: .claude).quota == expected)
    await coordinator.stop()
}

@Test func claudeQuotaCompletionHandlerBlocksQueuedQuotaUntilItCompletes() async throws {
    let quota = BlockingIntentQuotaRepository()
    let observerGate = QuotaApplicationGate()
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota,
        store: ProviderSnapshotStore(),
        clock: ManualClock(now: Self.fixedStart),
        claudeQuotaOperationCompleted: { await observerGate.pause() }
    )

    await coordinator.start()
    await quota.waitUntilCallCount(1)
    let queuedCodex = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .codex) }
    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))

    await observerGate.waitUntilEntered()
    #expect(quota.callCount == 1)
    await observerGate.resume()
    await quota.waitUntilCallCount(2)
    #expect(quota.intents[1] == .userInitiated(provider: .codex))
    try quota.releaseNext(with: quotaResult(for: .codex))
    #expect(await queuedCodex.valueUnlessCancelled == true)
    await coordinator.stop()
}

@Test func staleClaudeGenerationSkipsCompletionHandlerAfterApplicationGate() async throws {
    let quota = BlockingIntentQuotaRepository()
    let gate = QuotaApplicationGate()
    let observer = ClaudeQuotaCompletionRecorder()
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota,
        store: ProviderSnapshotStore(),
        clock: ManualClock(now: Self.fixedStart),
        quotaApplicationWillApply: { await gate.pause() },
        claudeQuotaOperationCompleted: { await observer.record() }
    )
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: quotaResult(for: .claude))
    await gate.waitUntilEntered()
    await coordinator.stop()
    await gate.resume()
    await Task.yield()
    #expect(await observer.count == 0)
}

@Test func claudeQuotaCompletionHandlerSkipsCodexOnlyAndCancelledRefreshes() async throws {
    let codexCounter = ClaudeQuotaCompletionRecorder()
    let codexQuota = QuotaRefreshSpy(result: .init(snapshots: [:], errors: [:]))
    let codexCoordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: codexQuota,
        store: ProviderSnapshotStore(),
        clock: ManualClock(now: Self.fixedStart),
        claudeQuotaOperationCompleted: { await codexCounter.record() }
    )
    await codexCoordinator.start()
    await codexQuota.waitUntilCallCount(1)
    await codexCounter.waitUntilCount(1)
    _ = await codexCoordinator.refreshQuota(afterUserAuthenticationFor: .codex)
    await codexQuota.waitUntilCallCount(2)
    await Task.yield()
    #expect(await codexCounter.count == 1)
    await codexCoordinator.stop()

    let cancelledCounter = ClaudeQuotaCompletionRecorder()
    let cancelledQuota = BlockingIntentQuotaRepository()
    let cancelledCoordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: cancelledQuota,
        store: ProviderSnapshotStore(),
        clock: ManualClock(now: Self.fixedStart),
        claudeQuotaOperationCompleted: { await cancelledCounter.record() }
    )
    await cancelledCoordinator.start()
    await cancelledQuota.waitUntilCallCount(1)
    await cancelledCoordinator.stop()
    try cancelledQuota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    await Task.yield()
    #expect(await cancelledCounter.count == 0)
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
    _ = await appliedUsage.valueUnlessCancelled

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

private final class QuotaAttemptCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let changes = ConditionWaiters()
    private var events: [QuotaAttemptEvent] = []
    var values: [QuotaAttemptEvent] { lock.withLock { events } }
    func record(_ event: QuotaAttemptEvent) {
        lock.withLock { events.append(event) }
        changes.signal()
    }

    func waitUntilCount(_ expectedCount: Int) async {
        await changes.wait { self.values.count >= expectedCount }
    }
}

private final class UsageRefreshSpy: UsageRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let changes = ConditionWaiters()
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
        changes.signal()
        return result
    }

    func waitUntilCallCount(_ expectedCount: Int) async {
        await changes.wait { self.callCount >= expectedCount }
    }
}

private final class QuotaRefreshSpy: QuotaRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let changes = ConditionWaiters()
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
        changes.signal()
        return result
    }

    func waitUntilCallCount(_ expectedCount: Int) async {
        await changes.wait { self.callCount >= expectedCount }
    }
}

private final class BlockingIntentQuotaRepository: QuotaRepository, @unchecked Sendable {
    private final class PendingCall {
        let gate = DispatchSemaphore(value: 0)
        var outcome: Result<QuotaRefreshResult, Error>?
    }

    private let lock = NSLock()
    private let changes = ConditionWaiters()
    private var calls: [QuotaRefreshIntent] = []
    private var pendingCalls: [PendingCall] = []
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
        let callNumber = lock.withLock { () -> Int? in
            if let blockedAfterCallCount, calls.count >= blockedAfterCallCount {
                unexpected.append(intent)
                return nil
            }
            calls.append(intent)
            pendingCalls.append(pendingCall)
            return calls.count
        }
        changes.signal()
        guard let callNumber else { throw BlockingQuotaRepositoryError.unexpectedCall }
        // The coordinator makes this synchronous call on a cooperative thread,
        // which stays blocked until the test releases the call; see the suite
        // comment and blockingFakeReleaseTimeout.
        if pendingCall.gate.wait(timeout: .now() + .seconds(blockingFakeReleaseTimeout)) == .timedOut {
            let abandoned = lock.withLock { () -> Bool in
                guard let index = pendingCalls.firstIndex(where: { $0 === pendingCall }) else { return false }
                pendingCalls.remove(at: index)
                return true
            }
            if abandoned {
                recordReleaseTimeout(of: "BlockingIntentQuotaRepository call \(callNumber) (\(intent))")
                throw BlockingFakeError.notReleasedInTime
            }
            // A release claimed this call as the wait timed out; its signal follows at once.
            pendingCall.gate.wait()
        }
        let outcome = lock.withLock { pendingCall.outcome }
        guard let outcome else { throw BlockingQuotaRepositoryError.missingOutcome }
        return try outcome.get()
    }

    func waitUntilCallCount(_ expectedCount: Int) async {
        await changes.wait { self.callCount >= expectedCount }
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
    private let changes = ConditionWaiters()
    private var calls: [QuotaRefreshIntent] = []

    var callCount: Int {
        lock.withLock { calls.count }
    }

    var intents: [QuotaRefreshIntent] {
        lock.withLock { calls }
    }

    func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult {
        lock.withLock { calls.append(intent) }
        changes.signal()
        return .init(snapshots: [:], errors: [:])
    }

    func waitUntilCallCount(_ expectedCount: Int) async {
        await changes.wait { self.callCount >= expectedCount }
    }
}

private actor QuotaApplicationGate {
    private var entered = false
    private var released = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    /// The coordinator's hook. Like the call it holds, it ignores cancellation
    /// and returns only once the test calls `resume()`.
    func pause() async {
        entered = true
        guard !released else { return }
        await withCheckedContinuation { continuation in
            if released {
                continuation.resume()
            } else {
                releaseContinuation = continuation
            }
        }
    }

    nonisolated func waitUntilEntered() async {
        await pollUntil { await self.entered }
    }

    func resume() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor ClaudeQuotaCompletionRecorder {
    private(set) var count = 0

    func record() {
        count += 1
    }

    nonisolated func waitUntilCount(_ expectedCount: Int) async {
        await pollUntil { await self.count >= expectedCount }
    }
}

private final class QuotaIntentRegistrationGate: @unchecked Sendable {
    private let lock = NSLock()
    private let changes = ConditionWaiters()
    private var events: [QuotaRefreshIntent] = []

    var intents: [QuotaRefreshIntent] { lock.withLock { events } }

    func record(_ intent: QuotaRefreshIntent) {
        lock.withLock { events.append(intent) }
        changes.signal()
    }

    func waitUntil(_ expected: [QuotaRefreshIntent]) async {
        await changes.wait { self.intents.starts(with: expected) }
    }
}

private final class BlockingUsageRepository: UsageRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let changes = ConditionWaiters()
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
        changes.signal()
        if count == 1, released.wait(timeout: .now() + .seconds(blockingFakeReleaseTimeout)) == .timedOut {
            recordReleaseTimeout(of: "BlockingUsageRepository's first call")
            throw BlockingFakeError.notReleasedInTime
        }
        return .init(snapshots: [:], errors: [:])
    }

    func releaseFirstCall() {
        released.signal()
    }

    func waitUntilCallCount(_ expectedCount: Int) async {
        await changes.wait { self.callCount >= expectedCount }
    }
}

private final class RecordingUsageRepository: UsageRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let changes = ConditionWaiters()
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
        changes.signal()
        if count == 1, released.wait(timeout: .now() + .seconds(blockingFakeReleaseTimeout)) == .timedOut {
            recordReleaseTimeout(of: "RecordingUsageRepository's first call")
            throw BlockingFakeError.notReleasedInTime
        }
        lock.withLock { completedCalls += 1 }
        changes.signal()
        return .init(snapshots: [:], errors: [:])
    }

    func releaseFirstCall() {
        released.signal()
    }

    func waitUntilCallCount(_ expectedCount: Int) async {
        await changes.wait { self.callCount >= expectedCount }
    }

    func waitUntilCompletedCallCount(_ expectedCount: Int) async {
        await changes.wait { self.completedCallCount >= expectedCount }
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
    private let changes = ConditionWaiters()
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

    func setNowWithoutWakingSleepers(_ value: Date) {
        lock.withLock { date = value }
    }

    /// Returns once at least `expectedCount` sleepers are registered, so a test
    /// can advance the clock only after every loop has computed its deadline.
    func waitUntilSleeperCount(_ expectedCount: Int) async {
        await changes.wait { self.sleeperCount >= expectedCount }
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
                } else {
                    changes.signal()
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

}

/// How long a blocking fake holds its cooperative thread waiting for the test
/// to release it. It is far above any legitimate hold and below the suite time
/// limit, so a forgotten release or a starved pool fails the test with a
/// diagnostic and frees the thread before the time limit cancels the test.
private let blockingFakeReleaseTimeout = 30

private enum BlockingFakeError: Error {
    case notReleasedInTime
}

private func recordReleaseTimeout(of call: String) {
    Issue.record("""
        \(call) was not released within \(blockingFakeReleaseTimeout) s. Either the test \
        never released it, or no cooperative thread was free to run the test while \
        the held call blocked one.
        """)
}
