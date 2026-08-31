import Foundation
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

@Suite("QuotaNotificationServiceTests", .serialized)
struct QuotaNotificationServiceTests {
    @MainActor @Test func deniedProvisionalAndRevokedAuthorizationNeverSubmit() async throws {
        for status in [QuotaNotificationAuthorization.denied, .provisional, .notDetermined] {
            let fixture = try NotificationFixture(status: status)
            await fixture.startEnabledAndCrossTwenty()

            #expect(await fixture.client.submissionCount == 0)
            #expect(fixture.preferences.state == .unavailable)
        }
    }

    @MainActor @Test func disablingAndReenablingRequiresANewBaselineAndInvalidatesOldAdmission() async throws {
        let fixture = try NotificationFixture(status: .authorized)
        await fixture.service.start()
        await fixture.service.setEnabledFromSettings(true)
        await fixture.applyQuota(remaining: 80, for: .claude)
        await fixture.service.reconcileLatestForTesting()
        await fixture.service.waitUntilIdle()

        await fixture.client.pauseNextStatus()
        await fixture.applyQuota(remaining: 20, for: .claude)
        await fixture.service.reconcileLatestForTesting()
        guard await fixture.client.waitUntilStatusPending() else {
            Issue.record("status read did not reach the deterministic checkpoint")
            return
        }
        await fixture.service.setEnabledFromSettings(false)
        await fixture.client.resumeStatus()
        await fixture.service.waitUntilIdle()
        #expect(await fixture.client.submissionCount == 0)

        await fixture.applyQuota(remaining: 80, for: .claude)
        await fixture.service.setEnabledFromSettings(true)
        await fixture.service.reconcileLatestForTesting()
        await fixture.service.waitUntilIdle()
        await fixture.applyQuota(remaining: 20, for: .claude)
        await fixture.service.reconcileLatestForTesting()
        await fixture.service.waitUntilIdle()

        #expect(await fixture.client.submissionCount == 1)
    }

    @MainActor @Test func currentFailureInvalidatesQueuedFreshSampleBeforeReservation() async throws {
        let fixture = try NotificationFixture(status: .authorized)
        await fixture.service.start()
        await fixture.service.setEnabledFromSettings(true)
        await fixture.applyQuota(remaining: 80, for: .codex)
        await fixture.service.reconcileLatestForTesting()
        await fixture.service.waitUntilIdle()

        await fixture.client.pauseNextStatus()
        await fixture.applyQuota(remaining: 20, for: .codex)
        await fixture.service.reconcileLatestForTesting()
        guard await fixture.client.waitUntilStatusPending() else {
            Issue.record("status read did not reach the deterministic checkpoint")
            return
        }
        await fixture.store.markQuotaFailure(
            for: .codex,
            status: .stale(lastSuccessfulAt: fixture.clock.now),
            at: fixture.advanceClock()
        )
        await fixture.client.resumeStatus()
        await fixture.service.reconcileLatestForTesting()
        await fixture.service.waitUntilIdle()

        #expect(await fixture.client.submissionCount == 0)
    }

    @MainActor @Test func newerQuotaInvalidatesQueuedFreshSampleAndSubmitsTheCurrentTenPercentCrossing() async throws {
        let fixture = try NotificationFixture(status: .authorized)
        await fixture.service.start()
        await fixture.service.setEnabledFromSettings(true)
        await fixture.applyQuota(remaining: 80, for: .codex)
        await fixture.service.reconcileLatestForTesting()
        await fixture.service.waitUntilIdle()

        await fixture.client.pauseNextStatus()
        await fixture.applyQuota(remaining: 20, for: .codex)
        await fixture.service.reconcileLatestForTesting()
        guard await fixture.client.waitUntilStatusPending() else {
            Issue.record("status read did not reach the deterministic checkpoint")
            return
        }
        await fixture.applyQuota(remaining: 10, for: .codex)
        await fixture.client.resumeStatus()
        await fixture.service.reconcileLatestForTesting()
        await fixture.service.waitUntilIdle()

        #expect(await fixture.client.submissions == ["Codex quota: 10% or less remaining."])
    }

    @MainActor @Test func authorizationRevokedBeforeSubmitNeverSubmits() async throws {
        let fixture = try NotificationFixture(status: .authorized)
        await fixture.service.start()
        await fixture.service.setEnabledFromSettings(true)
        await fixture.applyQuota(remaining: 80, for: .claude)
        await fixture.service.reconcileLatestForTesting()
        await fixture.service.waitUntilIdle()

        await fixture.client.pauseNextStatus()
        await fixture.applyQuota(remaining: 20, for: .claude)
        await fixture.service.reconcileLatestForTesting()
        guard await fixture.client.waitUntilStatusPending() else {
            Issue.record("status read did not reach the deterministic checkpoint")
            return
        }
        await fixture.client.setStatus(.denied)
        await fixture.client.resumeStatus()
        await fixture.service.waitUntilIdle()

        #expect(await fixture.client.submissionCount == 0)
        #expect(fixture.preferences.state == .unavailable)
    }

    @MainActor @Test func stoppingDuringLedgerLoadInvalidatesStartupBeforeObservation() async throws {
        let fixture = try NotificationFixture(status: .authorized, pauseLedgerLoad: true)
        let start = Task { await fixture.service.start() }
        guard await fixture.ledger.waitUntilLoadPending() else {
            Issue.record("ledger load did not reach the deterministic checkpoint")
            return
        }
        fixture.service.stop()
        await fixture.ledger.resumeLoad()
        await start.value

        await fixture.applyQuota(remaining: 20, for: .claude)
        await fixture.service.reconcileLatestForTesting()
        await fixture.service.waitUntilIdle()

        #expect(await fixture.client.submissionCount == 0)
    }

    @MainActor @Test func persistedReservationPrecedesOneImmediateGenericSubmissionAndNeverRetries() async throws {
        let fixture = try NotificationFixture(status: .authorized, submissionResult: .failed)
        await fixture.startEnabledAndCrossTwenty()
        await fixture.service.waitUntilIdle()

        #expect(await fixture.ledger.saveCount == 2)
        #expect(await fixture.client.submissions == ["Claude quota: 20% or less remaining."])
        #expect(await fixture.ledger.lastSaved?.records.first?.reservedStages == [.twenty])
        #expect(await fixture.events.snapshot().suffix(2) == ["save", "submit"])
    }

    @MainActor @Test func ledgerWriteFailureSuppressesSubmissionAndReloadsLastDurableLedger() async throws {
        let fixture = try NotificationFixture(status: .authorized, ledgerSaveResult: .failure(.writeFailed))
        await fixture.startEnabledAndCrossTwenty()
        await fixture.service.waitUntilIdle()

        #expect(await fixture.client.submissionCount == 0)
        #expect(await fixture.ledger.loadCount > 1)
    }

    @MainActor @Test func allowlistedWindowsAreIndependentAndProcessedInStableIDOrder() async throws {
        let fixture = try NotificationFixture(status: .authorized)
        await fixture.service.start()
        await fixture.service.setEnabledFromSettings(true)
        await fixture.applyQuota(windows: [("claude.session", 80), ("claude.weekly", 80)], for: .claude)
        await fixture.applyQuota(windows: [("codex.primary", 80)], for: .codex)
        await fixture.service.reconcileLatestForTesting()
        await fixture.service.waitUntilIdle()

        await fixture.applyQuota(windows: [("claude.session", 20), ("claude.weekly", 10)], for: .claude)
        await fixture.applyQuota(windows: [("codex.primary", 20)], for: .codex)
        await fixture.service.reconcileLatestForTesting()
        await fixture.service.waitUntilIdle()

        let submissions = await fixture.client.submissions
        #expect(submissions.filter { $0.hasPrefix("Claude quota:") } == [
            "Claude quota: 20% or less remaining.",
            "Claude quota: 10% or less remaining.",
        ])
        #expect(submissions.filter { $0.hasPrefix("Codex quota:") } == [
            "Codex quota: 20% or less remaining.",
        ])
    }

    @MainActor @Test func restartRetainsDurableReservationAndDoesNotSubmitTheRecordedStageAgain() async throws {
        let fixture = try NotificationFixture(status: .authorized)
        await fixture.startEnabledAndCrossTwenty()
        await fixture.service.stop()

        let restarted = fixture.restartedService()
        await restarted.service.start()
        await restarted.service.setEnabledFromSettings(true)
        await restarted.applyQuota(remaining: 10, for: .claude)
        await restarted.service.reconcileLatestForTesting()
        await restarted.service.waitUntilIdle()

        #expect(await restarted.client.submissions == ["Claude quota: 20% or less remaining."])
    }
}

@MainActor
private final class NotificationFixture {
    let store: ProviderSnapshotStore
    let client: FakeQuotaNotificationClient
    let ledger: RecordingLedgerStore
    let events: NotificationEventLog
    let preferences: QuotaNotificationPreferences
    let service: QuotaNotificationService
    let clock: NotificationFixtureClock

    init(
        status: QuotaNotificationAuthorization,
        pauseLedgerLoad: Bool = false,
        submissionResult: QuotaNotificationSubmission = .submitted,
        ledgerSaveResult: Result<Void, QuotaAlertLedgerStoreError> = .success(())
    ) throws {
        let initialNow = try #require(BridgeDecoder.date("2026-08-31T12:00:00Z"))
        let clock = NotificationFixtureClock(now: initialNow)
        self.clock = clock
        store = ProviderSnapshotStore(now: { initialNow })
        let events = NotificationEventLog()
        self.events = events
        client = FakeQuotaNotificationClient(status: status, submissionResult: submissionResult, events: events)
        ledger = RecordingLedgerStore(pauseNextLoad: pauseLedgerLoad, saveResult: ledgerSaveResult, events: events)
        let suiteName = "QuotaNotificationServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        preferences = QuotaNotificationPreferences(defaults: defaults)
        service = QuotaNotificationService(
            store: store,
            preferences: preferences,
            client: client,
            ledgerStore: ledger,
            now: { clock.now }
        )
    }

    private init(
        store: ProviderSnapshotStore,
        client: FakeQuotaNotificationClient,
        ledger: RecordingLedgerStore,
        events: NotificationEventLog,
        preferences: QuotaNotificationPreferences,
        clock: NotificationFixtureClock
    ) {
        self.store = store
        self.client = client
        self.ledger = ledger
        self.events = events
        self.preferences = preferences
        self.clock = clock
        service = QuotaNotificationService(
            store: store,
            preferences: preferences,
            client: client,
            ledgerStore: ledger,
            now: { clock.now }
        )
    }

    func restartedService() -> NotificationFixture {
        NotificationFixture(
            store: store,
            client: client,
            ledger: ledger,
            events: events,
            preferences: preferences,
            clock: clock
        )
    }

    @discardableResult
    func advanceClock() -> Date {
        clock.advance()
    }

    func applyQuota(remaining: Double, for provider: ProviderID) async {
        await store.applyQuota(quota(provider: provider, windows: [(defaultWindowID(for: provider), remaining)]), for: provider, at: advanceClock())
    }

    func applyQuota(windows: [(String, Double)], for provider: ProviderID) async {
        await store.applyQuota(quota(provider: provider, windows: windows), for: provider, at: advanceClock())
    }

    func startEnabledAndCrossTwenty() async {
        await service.start()
        await service.setEnabledFromSettings(true)
        await applyQuota(remaining: 80, for: .claude)
        await service.reconcileLatestForTesting()
        await service.waitUntilIdle()
        await store.applyUsage(makeFixtureUsage(), for: .claude, at: clock.now)
        await service.waitUntilIdle()
        #expect(await client.submissionCount == 0)
        await applyQuota(remaining: 20, for: .claude)
        await service.reconcileLatestForTesting()
        await service.waitUntilIdle()
    }

    private func quota(provider: ProviderID, windows: [(String, Double)]) -> QuotaSnapshot {
        QuotaSnapshot(windows: windows.map {
            try! QuotaWindow(
                id: $0.0,
                title: "private fixture title",
                usedPercent: 100 - $0.1,
                resetsAt: clock.now.addingTimeInterval(3_600)
            )
        })
    }

    private func defaultWindowID(for provider: ProviderID) -> String {
        provider == .claude ? "claude.session" : "codex.primary"
    }
}

@MainActor
private final class NotificationFixtureClock {
    private(set) var now: Date

    init(now: Date) {
        self.now = now
    }

    func advance(by interval: TimeInterval = 1) -> Date {
        now = now.addingTimeInterval(interval)
        return now
    }
}

private actor FakeQuotaNotificationClient: QuotaNotificationClient {
    private var status: QuotaNotificationAuthorization
    private var pauseNextStatusRead = false
    private let submissionResult: QuotaNotificationSubmission
    private let events: NotificationEventLog
    private var statusContinuations: [CheckedContinuation<QuotaNotificationAuthorization, Never>] = []
    private var statusPendingWaiters: [CheckedContinuation<Bool, Never>] = []
    private(set) var submissions: [String] = []

    init(status: QuotaNotificationAuthorization, submissionResult: QuotaNotificationSubmission, events: NotificationEventLog) {
        self.status = status
        self.submissionResult = submissionResult
        self.events = events
    }

    var submissionCount: Int { submissions.count }

    func setStatus(_ status: QuotaNotificationAuthorization) {
        self.status = status
    }

    func pauseNextStatus() {
        pauseNextStatusRead = true
    }

    func waitUntilStatusPending() async -> Bool {
        if !statusContinuations.isEmpty { return true }
        return await withCheckedContinuation { statusPendingWaiters.append($0) }
    }

    func requestAuthorization() async -> QuotaNotificationAuthorization {
        status
    }

    func currentAuthorization() async -> QuotaNotificationAuthorization {
        guard pauseNextStatusRead else { return status }
        pauseNextStatusRead = false
        let waiters = statusPendingWaiters
        statusPendingWaiters.removeAll()
        waiters.forEach { $0.resume(returning: true) }
        return await withCheckedContinuation { statusContinuations.append($0) }
    }

    func resumeStatus() {
        let continuations = statusContinuations
        statusContinuations.removeAll()
        continuations.forEach { $0.resume(returning: status) }
    }

    func submit(body: String) async -> QuotaNotificationSubmission {
        submissions.append(body)
        await events.append("submit")
        return submissionResult
    }
}

private actor RecordingLedgerStore: QuotaAlertLedgerStoring {
    private var pauseNextLoad: Bool
    private let saveResult: Result<Void, QuotaAlertLedgerStoreError>
    private(set) var saveCount = 0
    private(set) var loadCount = 0
    private(set) var lastSaved: QuotaAlertLedger?
    private let events: NotificationEventLog
    private var loadContinuations: [CheckedContinuation<QuotaAlertLedger, Never>] = []
    private var loadPendingWaiters: [CheckedContinuation<Bool, Never>] = []

    init(pauseNextLoad: Bool, saveResult: Result<Void, QuotaAlertLedgerStoreError>, events: NotificationEventLog) {
        self.pauseNextLoad = pauseNextLoad
        self.saveResult = saveResult
        self.events = events
    }

    func waitUntilLoadPending() async -> Bool {
        if !loadContinuations.isEmpty { return true }
        return await withCheckedContinuation { loadPendingWaiters.append($0) }
    }

    func load() async throws -> QuotaAlertLedger {
        loadCount += 1
        guard pauseNextLoad else { return lastSaved ?? .empty }
        pauseNextLoad = false
        let waiters = loadPendingWaiters
        loadPendingWaiters.removeAll()
        waiters.forEach { $0.resume(returning: true) }
        return await withCheckedContinuation { loadContinuations.append($0) }
    }

    func resumeLoad() {
        let continuations = loadContinuations
        loadContinuations.removeAll()
        let ledger = lastSaved ?? .empty
        continuations.forEach { $0.resume(returning: ledger) }
    }

    func save(_ ledger: QuotaAlertLedger) async throws {
        saveCount += 1
        try saveResult.get()
        lastSaved = ledger
        await events.append("save")
    }
}

private actor NotificationEventLog {
    private var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func snapshot() -> [String] {
        values
    }
}

private func makeFixtureUsage(totalTokens: UInt64 = 99) -> UsageSnapshot {
    let period = UsagePeriod(
        inputTokens: totalTokens,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheWriteTokens: 0,
        totalTokens: totalTokens,
        estimatedCostUSD: Decimal(string: "1.00")!
    )
    return UsageSnapshot(
        inputTokens: totalTokens,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheWriteTokens: 0,
        totalTokens: totalTokens,
        estimatedCostUSD: Decimal(string: "1.00")!,
        today: period,
        last7Days: period,
        last30Days: period
    )
}
