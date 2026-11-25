import Foundation
import Testing
@testable import NeedlbarCore

// The retry rule for a `/usage` run that finished without plan usage (spec
// 2026-11-20 §4). Kept apart from ClaudeUsageProbeCoordinatorTests so the two
// files change independently. Everything is synthetic: fake repositories and a
// manual clock. Nothing here touches a process, the network or credentials.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ClaudePlanUsageUnavailableRetryTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func planUsageUnavailableWaitsForThePeriodicRunAndKeepsItsBackoff() async throws {
        let harness = RetryHarness()
        for _ in 0 ..< 3 { harness.probe.script(.result(claudeFailure("requiresAuthentication"))) }
        await harness.startedAndIdle()
        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == .planUsageUnavailable)
        #expect(await harness.store.snapshot(for: .claude).quotaStatus == .requiresAuthentication,
                "with no earlier success")

        // The five-minute backoff ends at 300 s and nothing retries by itself.
        await harness.advance(minutes: 14)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1, "no backoff retry")
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)

        // The second failure backs off ten minutes, which ends before the next periodic run.
        await harness.advance(minutes: 14)
        await settle(watchingFor: { harness.probe.callCount > 2 })
        #expect(harness.probe.callCount == 2)
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(3)
        await harness.waitUntilCompletedRuns(3)

        // The third failure backs off twenty minutes, which holds the periodic run
        // due at 2,700 s until 3,000 s.
        await harness.advance(minutes: 19)
        await settle(watchingFor: { harness.probe.callCount > 3 })
        #expect(harness.probe.callCount == 3, "the periodic run waits for backoff")
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(4)
        await harness.waitUntilCompletedRuns(4)
        #expect(harness.probe.startTimes.map { $0.timeIntervalSince(Self.start) } == [0, 900, 1_800, 3_000])
        #expect(harness.probe.triggersSeen(in: harness.events) == [.startup, .periodic, .periodic, .periodic])
        await harness.coordinator.stop()
    }

    @Test(arguments: ["requiresAuthentication", "notInstalled"])
    func aThrownBridgeFailureWithTheCodeAlsoWaitsForThePeriodicRun(code: String) async throws {
        let harness = RetryHarness()
        harness.probe.script(.failure(BridgeFailure.bridgeFailed([
            BridgeError(provider: "claude", code: code, message: "fixture", action: nil),
        ])))
        await harness.startedAndIdle()
        await harness.advance(minutes: 14)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1, "\(code) does not retry when backoff ends")
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)
        #expect(harness.probe.triggersSeen(in: harness.events) == [.startup, .periodic])
        await harness.coordinator.stop()
    }

    @Test func aThrownBridgeFailureWithAnotherCodeStillRetriesUnderBackoff() async throws {
        let harness = RetryHarness()
        harness.probe.script(.failure(BridgeFailure.bridgeFailed([
            BridgeError(provider: "claude", code: "schemaChanged", message: "fixture", action: nil),
        ])))
        await harness.startedAndIdle()
        await harness.advance(minutes: 5)
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)
        #expect(harness.probe.triggersSeen(in: harness.events) == [.startup, .backoffRetry])
        await harness.coordinator.stop()
    }

    @Test func checkNowStillRunsAndTheSameReasonReturns() async throws {
        let harness = RetryHarness()
        harness.probe.script(.result(claudeFailure("requiresAuthentication")))
        harness.probe.script(.result(claudeFailure("requiresAuthentication")))
        await harness.startedAndIdle()
        await harness.coordinator.manualRefresh()
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)
        #expect(harness.probe.startTimes == [Self.start, Self.start])
        #expect(harness.probe.triggersSeen(in: harness.events) == [.startup, .manual])
        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == .planUsageUnavailable)
        await harness.coordinator.stop()
    }

    @Test func afterAnEarlierSuccessTheStatusIsAnErrorAndTheReadingIsKept() async throws {
        let harness = RetryHarness()
        harness.probe.script(.result(try weeklyReading()))
        harness.probe.script(.result(claudeFailure("requiresAuthentication")))
        await harness.startedAndIdle()
        await harness.advance(minutes: 15)
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)
        let snapshot = await harness.store.snapshot(for: .claude)
        #expect(snapshot.claudeQuotaFailureReason == .planUsageUnavailable)
        #expect(snapshot.quotaStatus == .error(message: "Authentication is required.", lastSuccessfulAt: Self.start))
        #expect(snapshot.quota != nil)
        #expect(snapshot.quotaLastSuccessfulAt == Self.start)
        await harness.coordinator.stop()
    }
}

// MARK: - Fixtures

private func claudeFailure(_ code: String) -> QuotaRefreshResult {
    .init(snapshots: [:], errors: [.claude: .init(provider: "claude", code: code, message: "fixture", action: nil)])
}

private func weeklyReading() throws -> QuotaRefreshResult {
    .init(snapshots: [.claude: QuotaSnapshot(windows: [
        try QuotaWindow(id: "claude.weekly", title: "Weekly", usedPercent: 74, resetsAt: nil),
    ])], errors: [:])
}

// MARK: - Test doubles

private struct RetryHarness {
    let store: ProviderSnapshotStore
    let probe: RetryProbeRepository
    let other: RetryBackgroundRepository
    let clock: RetryManualClock
    let events = RetryAttemptEvents()
    let coordinator: RefreshCoordinator

    init() {
        let clock = RetryManualClock(now: ClaudePlanUsageUnavailableRetryTests.start)
        let events = self.events
        let probe = RetryProbeRepository(clock: clock)
        let other = RetryBackgroundRepository()
        let store = ProviderSnapshotStore(now: { clock.now })
        self.store = store
        self.probe = probe
        self.other = other
        self.clock = clock
        coordinator = RefreshCoordinator(
            usageRepository: RetryUsageRepository(),
            quotaRepository: other,
            claudeUsageRepository: probe,
            claudeAutomaticRunsAllowed: true,
            store: store,
            clock: clock,
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

    /// Moves time a minute at a time, each minute only after every loop sleeps.
    func advance(minutes: Int) async {
        for _ in 0 ..< minutes {
            await clock.waitUntilSleeperCount(3)
            clock.advance(by: 60)
            await clock.waitUntilSleeperCount(3)
        }
    }
}

private final class RetryAttemptEvents: @unchecked Sendable {
    private let lock = NSLock()
    let changes = ConditionWaiters()
    private var recorded: [QuotaAttemptEvent] = []
    var values: [QuotaAttemptEvent] { lock.withLock { recorded } }
    func record(_ event: QuotaAttemptEvent) {
        lock.withLock { recorded.append(event) }
        changes.signal()
    }
}

private final class RetryProbeRepository: QuotaRepository, @unchecked Sendable {
    enum Outcome {
        case result(QuotaRefreshResult)
        case failure(any Error)
    }

    private let clock: RetryManualClock
    private let lock = NSLock()
    private let changes = ConditionWaiters()
    private var outcomes: [Outcome] = []
    private var recordedStarts: [Date] = []

    init(clock: RetryManualClock) { self.clock = clock }

    var callCount: Int { lock.withLock { recordedStarts.count } }
    var startTimes: [Date] { lock.withLock { recordedStarts } }

    func script(_ outcome: Outcome) { lock.withLock { outcomes.append(outcome) } }
    func waitUntilCallCount(_ expected: Int) async { await changes.wait { self.callCount >= expected } }

    func triggersSeen(in events: RetryAttemptEvents) -> [QuotaRefreshTrigger] {
        events.values.filter { $0.phase == .started }.map(\.trigger)
    }

    func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult {
        guard case .claudeUsageReport = intent else { throw BridgeFailure.nullPointer }
        let scripted = lock.withLock { () -> Outcome? in
            recordedStarts.append(clock.now)
            return outcomes.isEmpty ? nil : outcomes.removeFirst()
        }
        changes.signal()
        // With nothing scripted a run succeeds.
        switch scripted {
        case .result(let result)?: return result
        case .failure(let error)?: throw error
        case nil: return try weeklyReading()
        }
    }

    func cancelClaudeUsageReport(through runID: UInt64) {}
}

/// The Codex and Cursor refresh.
private final class RetryBackgroundRepository: QuotaRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let changes = ConditionWaiters()
    private var calls = 0

    var callCount: Int { lock.withLock { calls } }
    func waitUntilCallCount(_ expected: Int) async { await changes.wait { self.callCount >= expected } }

    func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult {
        guard intent == .backgroundAll else { throw BridgeFailure.nullPointer }
        lock.withLock { calls += 1 }
        changes.signal()
        return .init(snapshots: [.codex: QuotaSnapshot(windows: [
            try QuotaWindow(id: "codex.primary", title: "Primary", usedPercent: 10, resetsAt: nil),
        ])], errors: [:])
    }
}

private final class RetryUsageRepository: UsageRepository, @unchecked Sendable {
    func refresh() throws -> UsageRefreshResult {
        .init(snapshots: [:], errors: [:])
    }
}

private final class RetryManualClock: ClockLike, @unchecked Sendable {
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
