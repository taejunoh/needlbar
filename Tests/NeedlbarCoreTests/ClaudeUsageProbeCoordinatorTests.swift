import Foundation
import Testing
@testable import NeedlbarCore

// Everything is synthetic: fake repositories and a manual clock. Nothing here
// touches a process, the network, credentials or the Keychain.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ClaudeUsageProbeCoordinatorTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Triggers

    @Test func appStartRunsOnceAndPassesTheGenerationAsTheRunID() async throws {
        let harness = Harness()
        await harness.coordinator.start()
        await harness.waitUntilCompletedRuns(1)
        #expect(harness.probe.runIDs == [1])
        #expect(harness.events.values.first?.trigger == .startup)
        await harness.coordinator.stop()
    }

    @Test func openingThePopoverAloneNeverStartsARunEvenWithOneOverdue() async throws {
        let harness = Harness()
        await harness.startedAndIdle()
        // The clock jumps past the periodic interval without waking the tick.
        harness.clock.setNowWithoutWakingSleepers(Self.start.addingTimeInterval(3_600))
        await harness.coordinator.popoverOpened()
        await harness.other.waitUntilCallCount(2)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1)
        // A run really was overdue: the tick starts it, not the popover.
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)
        #expect(harness.events.values.last?.trigger == .periodic)
        await harness.coordinator.stop()
    }

    @Test func wakeAndConnectivityNeverStartARunEvenWithOneOverdue() async throws {
        let harness = Harness()
        await harness.startedAndIdle()
        let token = await harness.coordinator.recoveryRequestToken()
        harness.clock.setNowWithoutWakingSleepers(Self.start.addingTimeInterval(3_600))
        await token.submit(.wake)
        await harness.other.waitUntilCallCount(2)
        await token.submit(.connectivity)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1)
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)
        #expect(harness.events.values.last?.trigger == .periodic)
        await harness.coordinator.stop()
    }

    @Test func theFiveMinuteTimerStartsNoRunBeforeThePeriodicInterval() async throws {
        let harness = Harness()
        await harness.startedAndIdle()
        await harness.advance(minutes: 14)
        await harness.other.waitUntilCallCount(3) // Codex and Cursor keep their five-minute cadence.
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1)
        await harness.coordinator.stop()
    }

    @Test func aQuietPeriodStartsAPeriodicRunEveryFifteenMinutes() async throws {
        let harness = Harness()
        await harness.startedAndIdle()
        await harness.advance(minutes: 15)
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)
        await harness.advance(minutes: 14)
        await settle(watchingFor: { harness.probe.callCount > 2 })
        #expect(harness.probe.callCount == 2)
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(3)
        await harness.waitUntilCompletedRuns(3)
        #expect(harness.probe.startTimes.map { $0.timeIntervalSince(Self.start) } == [0, 900, 1_800])
        #expect(harness.probe.triggersSeen(in: harness.events) == [.startup, .periodic, .periodic])
        await harness.coordinator.stop()
    }

    @Test func aChangedUsageTotalStartsARunButTheFirstObservationDoesNot() async throws {
        let harness = Harness(claudeTotal: 100)
        await harness.startedAndIdle()
        await harness.waitUntilUsageApplied(100)
        await harness.coordinator.requestUsageRefresh()
        await harness.usage.waitUntilCallCount(2)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1, "an unchanged total is no trigger")

        harness.clock.setNowWithoutWakingSleepers(Self.start.addingTimeInterval(301))
        harness.usage.setClaudeTotal(250)
        await harness.coordinator.requestUsageRefresh()
        await harness.probe.waitUntilCallCount(2)
        #expect(harness.probe.triggersSeen(in: harness.events) == [.startup, .usageRecordsChanged])
        await harness.coordinator.stop()
    }

    @Test func aChangeInsideTheIntervalRunsWhenTheIntervalEnds() async throws {
        let harness = Harness(claudeTotal: 100)
        await harness.startedAndIdle()
        await harness.waitUntilUsageApplied(100)
        harness.usage.setClaudeTotal(250)
        await harness.coordinator.requestUsageRefresh()
        await harness.waitUntilUsageApplied(250)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1, "inside five minutes")

        await harness.advance(minutes: 4)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1)
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(2)
        #expect(harness.probe.startTimes.last == Self.start.addingTimeInterval(300))
        await harness.coordinator.stop()
    }

    @Test func passingADisplayedResetStartsOneRun() async throws {
        let reset = Self.start.addingTimeInterval(600)
        let harness = Harness()
        harness.probe.script(.result(try weeklyQuota(resetsAt: reset)))
        harness.probe.script(.result(try weeklyQuota(resetsAt: reset.addingTimeInterval(604_800))))
        await harness.startedAndIdle()
        await harness.advance(minutes: 9)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1)
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)
        #expect(harness.events.values.last?.trigger == .windowReset)
        // Nothing runs again until the periodic interval from this run: not the same reset.
        await harness.advance(minutes: 14)
        await settle(watchingFor: { harness.probe.callCount > 2 })
        #expect(harness.probe.callCount == 2)
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(3)
        await harness.waitUntilCompletedRuns(3)
        #expect(harness.probe.startTimes.last == reset.addingTimeInterval(900))
        #expect(harness.events.values.last?.trigger == .periodic)
        await harness.coordinator.stop()
    }

    // MARK: - Manual

    @Test func manualRefreshSkipsTheIntervalAndBackoff() async throws {
        let harness = Harness()
        harness.probe.script(.result(providerUnavailable()))
        await harness.startedAndIdle()
        await harness.coordinator.manualRefresh()
        await harness.probe.waitUntilCallCount(2)
        #expect(harness.probe.startTimes == [Self.start, Self.start])
        await harness.coordinator.stop()
    }

    @Test func manualRefreshJoinsARunInFlight() async throws {
        let harness = Harness()
        harness.probe.holdNext()
        await harness.coordinator.start()
        await harness.probe.waitUntilHeld()
        await harness.coordinator.manualRefresh()
        await harness.coordinator.manualRefresh()
        harness.probe.release()
        await harness.waitUntilCompletedRuns(1)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1)
        await harness.coordinator.stop()
    }

    // MARK: - One at a time, and independent of other providers

    @Test func otherProvidersKeepRefreshingWhileARunIsHeld() async throws {
        let harness = Harness()
        harness.probe.holdNext()
        await harness.coordinator.start()
        await harness.probe.waitUntilHeld()
        await harness.other.waitUntilCallCount(1)
        await harness.coordinator.manualRefresh()
        await harness.other.waitUntilCallCount(2)
        await pollUntil { await harness.store.snapshot(for: .codex).quota != nil }
        #expect(harness.probe.isHeld)
        #expect(harness.probe.callCount == 1)
        harness.probe.release()
        await harness.coordinator.stop()
    }

    // MARK: - Backoff

    @Test func retryableFailuresBackOffFiveTenTwentyThenThirtyAndSuccessResets() async throws {
        let harness = Harness()
        for _ in 0 ..< 5 { harness.probe.script(.result(providerUnavailable())) }
        harness.probe.script(.result(try weeklyQuota(resetsAt: Self.start.addingTimeInterval(9_000_000))))
        harness.probe.script(.result(providerUnavailable()))
        await harness.startedAndIdle()
        // The waits of 20 and 30 minutes cross the periodic interval: backoff holds it back.
        for (index, minutes) in [5, 10, 20, 30, 30].enumerated() {
            await harness.advance(minutes: minutes - 1)
            await settle(watchingFor: { harness.probe.callCount > index + 1 })
            #expect(harness.probe.callCount == index + 1, "still waiting before minute \(minutes)")
            await harness.advance(minutes: 1)
            await harness.probe.waitUntilCallCount(index + 2)
            await harness.waitUntilCompletedRuns(index + 2)
        }
        let offsets = harness.probe.startTimes.map { $0.timeIntervalSince(Self.start) }
        #expect(offsets == [0, 300, 900, 2_100, 3_900, 5_700])
        #expect(harness.probe.triggersSeen(in: harness.events)
            == [.startup, .backoffRetry, .backoffRetry, .backoffRetry, .backoffRetry, .backoffRetry])
        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == nil, "the last run succeeded")

        // Success clears the retry: the next run is the periodic one.
        await harness.advance(minutes: 14)
        await settle(watchingFor: { harness.probe.callCount > 6 })
        #expect(harness.probe.callCount == 6)
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(7)
        await harness.waitUntilCompletedRuns(7)
        #expect(harness.events.values.last?.trigger == .periodic)

        // Success also reset the count: this failure waits five minutes, not thirty.
        await harness.advance(minutes: 5)
        await harness.probe.waitUntilCallCount(8)
        #expect(harness.probe.startTimes.last == Self.start.addingTimeInterval(5_700 + 900 + 300))
        await harness.coordinator.stop()
    }

    @Test func notInstalledAndNoUsageRetryOnlyOnATriggerAndUnderBackoff() async throws {
        for code in ["notInstalled", "requiresAuthentication"] {
            let harness = Harness(claudeTotal: 100)
            harness.probe.script(.result(claudeError(code)))
            harness.probe.script(.result(claudeError(code)))
            await harness.startedAndIdle()
            await harness.waitUntilUsageApplied(100)
            // The five-minute backoff ends here and nothing retries by itself.
            await harness.advance(minutes: 14)
            await settle(watchingFor: { harness.probe.callCount > 1 })
            #expect(harness.probe.callCount == 1, "\(code) does not retry when backoff ends")

            await harness.advance(minutes: 1)
            await harness.probe.waitUntilCallCount(2)
            await harness.waitUntilCompletedRuns(2)
            #expect(harness.events.values.last?.trigger == .periodic, "\(code)")

            // The second failure backs off ten minutes, which also holds a real trigger.
            harness.usage.setClaudeTotal(250)
            await harness.coordinator.requestUsageRefresh()
            await harness.waitUntilUsageApplied(250)
            await harness.advance(minutes: 9)
            await settle(watchingFor: { harness.probe.callCount > 2 })
            #expect(harness.probe.callCount == 2, "\(code) waits for backoff")
            await harness.advance(minutes: 1)
            await harness.probe.waitUntilCallCount(3)
            #expect(harness.probe.startTimes.last == Self.start.addingTimeInterval(1_500), "\(code)")
            await harness.coordinator.stop()
        }
    }

    @Test func aFailedPeriodicRunKeepsTheReadingAsLastKnownAndBacksOff() async throws {
        let harness = Harness()
        harness.probe.script(.result(try weeklyQuota(resetsAt: Self.start.addingTimeInterval(9_000_000))))
        harness.probe.script(.result(providerUnavailable()))
        await harness.startedAndIdle()
        await harness.advance(minutes: 15)
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)
        #expect(harness.events.values.last?.trigger == .periodic)
        #expect(harness.events.values.last?.outcome == .failure)
        let selected = ClaudeQuotaPresentationSelector.select(
            snapshot: await harness.store.snapshot(for: .claude), now: harness.clock.now).sevenDay
        #expect(selected?.isLastKnown == true)
        #expect(selected?.remainingPercent == 26)
        #expect(selected?.observedAt == Self.start, "labelled with the time it was checked")

        await harness.advance(minutes: 5)
        await harness.probe.waitUntilCallCount(3)
        await harness.waitUntilCompletedRuns(3)
        #expect(harness.probe.startTimes.last == Self.start.addingTimeInterval(1_200))
        #expect(harness.events.values.last?.trigger == .backoffRetry)
        await harness.coordinator.stop()
    }

    // MARK: - Stop and generation

    @Test func stopCancelsTheRunInFlightAndDropsItsResult() async throws {
        let harness = Harness()
        harness.probe.holdNext()
        await harness.coordinator.start()
        await harness.probe.waitUntilHeld()
        await harness.coordinator.stop()
        #expect(harness.probe.cancelledThrough == [1])
        harness.probe.script(.result(try weeklyQuota(resetsAt: nil)))
        harness.probe.release()
        await settle(watchingFor: { harness.events.values.contains { $0.phase == .completed } })
        #expect(await harness.store.snapshot(for: .claude).quota == nil)
        #expect(harness.events.values.map(\.phase) == [.started, .invalidated])
    }

    @Test func stopWithNoRunInFlightCancelsNothing() async throws {
        let harness = Harness()
        await harness.startedAndIdle()
        await harness.coordinator.stop()
        #expect(harness.probe.cancelledThrough.isEmpty)
    }

    @Test func restartWaitsForTheOldPhysicalCallThenRunsOnce() async throws {
        let harness = Harness()
        harness.probe.holdNext()
        await harness.coordinator.start()
        await harness.probe.waitUntilHeld()
        await harness.coordinator.stop()
        await harness.coordinator.start()
        #expect(harness.probe.callCount == 1)
        harness.probe.release()
        await harness.probe.waitUntilCallCount(2)
        #expect(harness.probe.runIDs == [1, 3], "a stop and a start each advance the generation")
        await harness.coordinator.stop()
    }

    @Test func aThrownFailureMarksOnlyClaude() async throws {
        let harness = Harness()
        harness.probe.script(.failure(BridgeFailure.nullPointer))
        await harness.startedAndIdle()
        await pollUntil { await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == .couldNotUpdateQuota }
        await pollUntil { await harness.store.snapshot(for: .codex).quota != nil }
        #expect(await harness.store.snapshot(for: .codex).quotaStatus == .fresh)
        await harness.coordinator.stop()
    }

    @Test func aBackgroundBridgeFailureLeavesClaudeAlone() async throws {
        let harness = Harness()
        harness.other.scriptFailure(BridgeFailure.nullPointer)
        harness.probe.script(.result(try weeklyQuota(resetsAt: nil)))
        await harness.startedAndIdle()
        await pollUntil { await harness.store.snapshot(for: .codex).quotaStatus != .unavailable }
        let claude = await harness.store.snapshot(for: .claude)
        #expect(claude.quotaStatus == .fresh)
        #expect(claude.claudeQuotaFailureReason == nil)
        await harness.coordinator.stop()
    }

    // MARK: - What a run tells the schedule

    @Test func aStaleRunsFailureNeverTouchesTheScheduleOfTheRunAfterARestart() async throws {
        let harness = Harness()
        harness.probe.holdNext()
        harness.probe.script(.result(providerUnavailable()))
        await harness.coordinator.start()
        await harness.probe.waitUntilHeld()
        await harness.coordinator.stop()
        await harness.coordinator.start()
        harness.probe.release()
        // A recorded failure would put the new generation under backoff and refuse this run.
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(1)
        #expect(harness.probe.runIDs == [1, 3])
        #expect(harness.events.values.last?.outcome == .success)
        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == nil)

        // And it left no retry behind: the next run is the periodic one, not a backoff retry.
        await harness.advance(minutes: 14)
        await settle(watchingFor: { harness.probe.callCount > 2 })
        #expect(harness.probe.callCount == 2)
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(3)
        await harness.waitUntilCompletedRuns(2)
        #expect(harness.events.values.last?.trigger == .periodic)
        await harness.coordinator.stop()
    }

    @Test func aRunWithNeitherReadingNorErrorRecordsExactlyOneRetryableFailure() async throws {
        let harness = Harness()
        harness.probe.script(.result(.init(snapshots: [:], errors: [:])))
        harness.probe.script(.result(.init(snapshots: [:], errors: [:])))
        await harness.startedAndIdle()
        // One failure waits five minutes, a second ten. Counting one twice would make the first wait ten.
        await harness.advance(minutes: 4)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1)
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)
        await harness.advance(minutes: 9)
        await settle(watchingFor: { harness.probe.callCount > 2 })
        #expect(harness.probe.callCount == 2)
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(3)
        #expect(harness.probe.startTimes.map { $0.timeIntervalSince(Self.start) } == [0, 300, 900])
        #expect(harness.probe.triggersSeen(in: harness.events).prefix(3) == [.startup, .backoffRetry, .backoffRetry])
        await harness.coordinator.stop()
    }

    // MARK: - Diagnostics

    @Test func diagnosticsAreReadOncePerRunSharedWithTheReporterAndAddedToTheEvent() async throws {
        let harness = Harness()
        harness.probe.script(.result(claudeError("schemaChanged")))
        harness.diagnostics.script { now in
            diagnosticsRead(origin: "usageReportFormatChanged", lastAttemptAt: now)
        }
        await harness.startedAndIdle()
        #expect(harness.diagnostics.readCount == 1)
        #expect(harness.diagnostics.reportCount == 1)
        #expect(harness.events.values.last?.claudeUsageProbe == ClaudeUsageProbeDiagnostics(
            durationMs: 1_500, rowKinds: [.weeklyAll], unknownRowCount: 2, skippedRowCount: 1))
        #expect(harness.events.values.last?.outcome == .failure)
        await harness.coordinator.stop()
    }

    @Test func aBackgroundRefreshReadsNoClaudeDiagnosticsAndEmitsNoAttempt() async throws {
        let harness = Harness(claudeRepository: false)
        await harness.coordinator.start()
        await harness.other.waitUntilCallCount(1)
        await pollUntil { await harness.store.snapshot(for: .codex).quota != nil }
        await settle(watchingFor: { harness.diagnostics.readCount > 0 })
        #expect(harness.diagnostics.readCount == 0)
        #expect(harness.events.values.isEmpty)
        await harness.coordinator.stop()
    }

    @Test func withoutAClaudeRepositoryThereIsNoTick() async throws {
        let harness = Harness(claudeRepository: false)
        await harness.coordinator.start()
        await harness.clock.waitUntilSleeperCount(2)
        await settle(watchingFor: { harness.clock.sleeperCount > 2 })
        #expect(harness.clock.sleeperCount == 2)
        await harness.coordinator.stop()
    }

    @Test func noRawCanaryReachesTheStoreOrTheEvents() async throws {
        let harness = Harness()
        harness.probe.script(.result(claudeError("schemaChanged")))
        await harness.startedAndIdle()
        let reason = await harness.store.snapshot(for: .claude).claudeQuotaFailureReason
        let surfaces = "\(String(describing: reason)) \(harness.events.values)"
        #expect(!surfaces.contains(canaryMessage))
        await harness.coordinator.stop()
    }
}

// MARK: - Fixtures

private let canaryMessage = "RAW_OUTPUT_TOKEN_PATH_CANARY"

private func claudeError(_ code: String) -> QuotaRefreshResult {
    .init(snapshots: [:], errors: [.claude: .init(provider: "claude", code: code, message: canaryMessage, action: nil)])
}

private func providerUnavailable() -> QuotaRefreshResult { claudeError("providerUnavailable") }

private func weeklyQuota(resetsAt: Date?) throws -> QuotaRefreshResult {
    .init(snapshots: [.claude: QuotaSnapshot(windows: [
        try QuotaWindow(id: "claude.weekly", title: "Weekly", usedPercent: 74, resetsAt: resetsAt),
    ])], errors: [:])
}

private func diagnosticsRead(origin: String, lastAttemptAt: Date) -> ClaudeQuotaDiagnosticsRead {
    let attempt = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: floor(lastAttemptAt.timeIntervalSince1970)))
    let json = """
    {"schemaVersion":"needlbar.v1","ok":true,"generatedAt":"\(attempt)","data":{"providers":[{"provider":"claude","usageStatus":"available","quotaStatus":"error","usageSource":"local","quotaSource":"usageReport","lastAttemptAt":"\(attempt)","claudeQuotaFailureOrigin":"\(origin)","claudeUsageProbe":{"durationMs":1500,"rowKinds":["weeklyAll"],"unknownRowCount":2,"skippedRowCount":1}}]},"errors":[]}
    """
    return Result { try BridgeDecoder().decodeDiagnosticsEnvelope(Data(json.utf8)) }
}

private func usage(total: UInt64) -> UsageSnapshot {
    let period = UsagePeriod(inputTokens: total, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0,
                             totalTokens: total, estimatedCostUSD: 0)
    return UsageSnapshot(inputTokens: total, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0,
                         totalTokens: total, estimatedCostUSD: 0, today: period, last7Days: period, last30Days: period)
}

// MARK: - Test doubles

private struct Harness {
    let store: ProviderSnapshotStore
    let probe: ProbeRepository
    let other: BackgroundRepository
    let usage: ScriptedUsageRepository
    let diagnostics: FakeDiagnostics
    let clock: ManualClock
    let events = AttemptEvents()
    let coordinator: RefreshCoordinator

    init(claudeRepository: Bool = true, claudeTotal: UInt64 = 0) {
        let clock = ManualClock(now: ClaudeUsageProbeCoordinatorTests.start)
        let events = self.events
        let probe = ProbeRepository(clock: clock)
        let diagnostics = FakeDiagnostics(clock: clock)
        let other = BackgroundRepository()
        let usage = ScriptedUsageRepository(claudeTotal: claudeTotal)
        let store = ProviderSnapshotStore(now: { clock.now })
        self.store = store
        self.probe = probe
        self.other = other
        self.usage = usage
        self.diagnostics = diagnostics
        self.clock = clock
        coordinator = RefreshCoordinator(
            usageRepository: usage,
            quotaRepository: other,
            claudeUsageRepository: claudeRepository ? probe : nil,
            store: store,
            clock: clock,
            claudeQuotaDiagnostics: diagnostics.completion,
            quotaAttemptObserver: { events.record($0) }
        )
    }

    func startedAndIdle() async {
        await coordinator.start()
        await waitUntilCompletedRuns(1)
        await other.waitUntilCallCount(1)
    }

    /// `QuotaAttemptLedger.complete` is the last thing a run does before it
    /// frees its slot, with no suspension between them.
    func waitUntilCompletedRuns(_ expected: Int) async {
        await events.changes.wait { events.values.filter { $0.phase == .completed }.count >= expected }
    }

    func waitUntilUsageApplied(_ total: UInt64) async {
        await pollUntil { await store.snapshot(for: .claude).usage?.totalTokens == total }
    }

    /// Moves time a minute at a time, each minute only after every loop sleeps.
    func advance(minutes: Int) async {
        for _ in 0 ..< minutes {
            await clock.waitUntilSleeperCount(3)
            clock.advance(by: 60)
            await clock.waitUntilSleeperCount(3)
        }
    }
}

private final class AttemptEvents: @unchecked Sendable {
    private let lock = NSLock()
    let changes = ConditionWaiters()
    private var recorded: [QuotaAttemptEvent] = []
    var values: [QuotaAttemptEvent] { lock.withLock { recorded } }
    func record(_ event: QuotaAttemptEvent) {
        lock.withLock { recorded.append(event) }
        changes.signal()
    }
}

private final class ProbeRepository: QuotaRepository, @unchecked Sendable {
    enum Outcome {
        case result(QuotaRefreshResult)
        case failure(any Error)

        func get() throws -> QuotaRefreshResult {
            switch self {
            case .result(let result): return result
            case .failure(let error): throw error
            }
        }
    }

    private let clock: ManualClock
    private let lock = NSLock()
    private let changes = ConditionWaiters()
    private let gate = DispatchSemaphore(value: 0)
    private var outcomes: [Outcome] = []
    private var holds = false
    private var held = false
    private var recordedRunIDs: [UInt64] = []
    private var recordedStarts: [Date] = []
    private var recordedCancels: [UInt64] = []

    init(clock: ManualClock) { self.clock = clock }

    var callCount: Int { lock.withLock { recordedRunIDs.count } }
    var runIDs: [UInt64] { lock.withLock { recordedRunIDs } }
    var startTimes: [Date] { lock.withLock { recordedStarts } }
    var cancelledThrough: [UInt64] { lock.withLock { recordedCancels } }
    var isHeld: Bool { lock.withLock { held } }

    func script(_ outcome: Outcome) { lock.withLock { outcomes.append(outcome) } }
    func holdNext() { lock.withLock { holds = true } }
    func release() { gate.signal() }
    func waitUntilHeld() async { await changes.wait { self.isHeld } }
    func waitUntilCallCount(_ expected: Int) async { await changes.wait { self.callCount >= expected } }

    func triggersSeen(in events: AttemptEvents) -> [QuotaRefreshTrigger] {
        events.values.filter { $0.phase == .started }.map(\.trigger)
    }

    func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult {
        guard case .claudeUsageReport(let runID) = intent else { throw BridgeFailure.nullPointer }
        let hold = lock.withLock { () -> Bool in
            recordedRunIDs.append(runID)
            recordedStarts.append(clock.now)
            let hold = holds
            holds = false
            held = hold
            return hold
        }
        changes.signal()
        if hold {
            _ = gate.wait(timeout: .now() + .seconds(30))
            lock.withLock { held = false }
            changes.signal()
        }
        // With nothing scripted a run succeeds. An empty result would count as a
        // retryable failure and start a backoff retry at five minutes.
        let scripted = lock.withLock { outcomes.isEmpty ? nil : outcomes.removeFirst() }
        return try scripted?.get() ?? weeklyQuota(resetsAt: nil)
    }

    func cancelClaudeUsageReport(through runID: UInt64) {
        lock.withLock { recordedCancels.append(runID) }
    }
}

/// The Codex and Cursor refresh.
private final class BackgroundRepository: QuotaRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let changes = ConditionWaiters()
    private var calls = 0
    private var failure: (any Error)?

    var callCount: Int { lock.withLock { calls } }
    func scriptFailure(_ error: any Error) { lock.withLock { failure = error } }
    func waitUntilCallCount(_ expected: Int) async { await changes.wait { self.callCount >= expected } }

    func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult {
        guard intent == .backgroundAll else { throw BridgeFailure.nullPointer }
        let error = lock.withLock { () -> (any Error)? in
            calls += 1
            return failure
        }
        changes.signal()
        if let error { throw error }
        return .init(snapshots: [.codex: QuotaSnapshot(windows: [
            try QuotaWindow(id: "codex.primary", title: "Primary", usedPercent: 10, resetsAt: nil),
        ])], errors: [:])
    }
}

private final class ScriptedUsageRepository: UsageRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let changes = ConditionWaiters()
    private var total: UInt64
    private var calls = 0

    init(claudeTotal: UInt64) { total = claudeTotal }

    func setClaudeTotal(_ value: UInt64) { lock.withLock { total = value } }
    func waitUntilCallCount(_ expected: Int) async {
        await changes.wait { self.lock.withLock { self.calls } >= expected }
    }

    func refresh() throws -> UsageRefreshResult {
        let current = lock.withLock { () -> UInt64 in
            calls += 1
            return total
        }
        changes.signal()
        return .init(snapshots: [.claude: usage(total: current)], errors: [:])
    }
}

private final class FakeDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private let clock: ManualClock
    private var respond: @Sendable (Date) -> ClaudeQuotaDiagnosticsRead = { _ in .failure(BridgeFailure.nullPointer) }
    private var reads = 0
    private var reports = 0

    init(clock: ManualClock) { self.clock = clock }

    var readCount: Int { lock.withLock { reads } }
    var reportCount: Int { lock.withLock { reports } }

    func script(_ respond: @escaping @Sendable (Date) -> ClaudeQuotaDiagnosticsRead) {
        lock.withLock { self.respond = respond }
    }

    var completion: ClaudeQuotaCompletionDiagnostics {
        ClaudeQuotaCompletionDiagnostics(
            read: { [self] in
                let respond = lock.withLock { () -> @Sendable (Date) -> ClaudeQuotaDiagnosticsRead in
                    reads += 1
                    return self.respond
                }
                return respond(clock.now)
            },
            report: { [self] _ in lock.withLock { reports += 1 } }
        )
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
    private var sleepers: [UUID: Sleeper] = [:]

    init(now: Date) { date = now }

    var now: Date { lock.withLock { date } }
    var sleeperCount: Int { lock.withLock { sleepers.count } }

    func setNowWithoutWakingSleepers(_ value: Date) { lock.withLock { date = value } }

    func waitUntilSleeperCount(_ expected: Int) async {
        await changes.wait { self.sleeperCount >= expected }
    }

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        let id = UUID()
        let seconds = TimeInterval(duration.components.seconds)
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let cancelled = lock.withLock { () -> Bool in
                    if Task.isCancelled { return true }
                    sleepers[id] = .init(deadline: date.addingTimeInterval(seconds), continuation: continuation)
                    return false
                }
                if cancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    changes.signal()
                }
            }
        }, onCancel: {
            let sleeper = self.lock.withLock { self.sleepers.removeValue(forKey: id) }
            sleeper?.continuation.resume(throwing: CancellationError())
        })
    }

    func advance(by interval: TimeInterval) {
        let due = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            date = date.addingTimeInterval(interval)
            let ready = sleepers.filter { $0.value.deadline <= date }
            ready.keys.forEach { sleepers.removeValue(forKey: $0) }
            return ready.values.map(\.continuation)
        }
        due.forEach { $0.resume() }
    }
}
