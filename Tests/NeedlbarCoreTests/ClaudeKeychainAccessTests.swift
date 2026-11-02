import Foundation
import Testing
@testable import NeedlbarCore

// The explicit "Allow Keychain access" click. Every input is synthetic: a fake
// quota repository whose user-initiated read can be held open the way a macOS
// dialog holds it, fake diagnostics reads and a manual clock. Nothing here
// touches credentials, the Keychain, the network or the claude CLI.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ClaudeKeychainAccessTests {
    static let start = Date(timeIntervalSince1970: 1_793_000_000) // a whole second

    // MARK: - Copy

    @Test func onlyCredentialAccessUnavailableHasAnActionTitleAndItComesFromALocalizableKey() throws {
        #expect(ClaudeQuotaFailureReason.credentialAccessUnavailable.keychainAccessActionTitle == "Allow Keychain access")
        for reason in [ClaudeQuotaFailureReason.quotaAccessUnavailable, .connectionUnavailable,
                       .temporarilyLimited, .couldNotUpdateQuota, .claudeCodeAccessExpired] {
            #expect(reason.keychainAccessActionTitle == nil, "\(reason)")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("needlbar-keychain-access-\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let table = #""claudeQuota.action.allowKeychainAccess" = "ACTION-TRANSLATED";"#
        try Data(table.utf8).write(to: directory.appendingPathComponent("Localizable.strings"))
        let bundle = try #require(Bundle(url: directory))
        #expect(ClaudeQuotaFailureReason.credentialAccessUnavailable.localizedKeychainAccessActionTitle(bundle: bundle)
            == "ACTION-TRANSLATED")
    }

    // MARK: - The dialog does not stop anything else

    @Test func anOpenDialogDoesNotStopOtherProvidersFromRefreshing() async throws {
        let harness = try await Harness.startedInDeniedState()
        harness.quota.holdDialog()
        let click = Task { await harness.coordinator.requestClaudeKeychainAccess() }
        await harness.quota.waitUntilDialogIsOpen()

        // A background refresh arrives while the dialog is open. Rust reports
        // no Claude outcome for it (the Keychain read was busy).
        harness.quota.scriptBackground(.result(try codexQuota(usedPercent: 77)))
        await harness.coordinator.manualRefresh()
        await pollUntil { await harness.store.snapshot(for: .codex).quota?.windows.first?.usedPercent == 77 }

        #expect(harness.quota.dialogIsOpen, "Codex must update while the dialog is still open")
        #expect(await harness.store.snapshot(for: .codex).quota?.windows.first?.usedPercent == 77)
        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == .credentialAccessUnavailable)

        harness.quota.answerDialog(.result(try claudeQuota()))
        #expect(await click.valueUnlessCancelled == true)
        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == nil)
        await harness.coordinator.stop()
    }

    @Test func aPopoverOpenedWhileTheDialogIsOpenStillRefreshesOtherProviders() async throws {
        let harness = try await Harness.startedInDeniedState()
        harness.quota.holdDialog()
        let click = Task { await harness.coordinator.requestClaudeKeychainAccess() }
        await harness.quota.waitUntilDialogIsOpen()

        // Past the popover's 60-second threshold.
        harness.clock.setNowWithoutWakingSleepers(harness.clock.now.addingTimeInterval(61))
        harness.quota.scriptBackground(.result(try codexQuota(usedPercent: 12)))
        await harness.coordinator.popoverOpened()
        await pollUntil { await harness.store.snapshot(for: .codex).quota?.windows.first?.usedPercent == 12 }

        #expect(harness.quota.dialogIsOpen)
        harness.quota.answerDialog(.result(claudeDenied()))
        _ = await click.valueUnlessCancelled
        await harness.coordinator.stop()
    }

    @Test func aBackgroundAttemptOverlappingTheReadCannotOverwriteItsResult() async throws {
        // Started before the click, it read "denied"; it finishes after the
        // dialog was answered, so its Claude part is older than the answer.
        let harness = try await Harness.startedInDeniedState()
        harness.quota.holdNextBackground()
        harness.quota.scriptBackground(.result(claudeDenied(plus: try codexQuota(usedPercent: 33))))
        await harness.coordinator.manualRefresh()
        await harness.quota.waitUntilBackgroundIsHeld()

        harness.quota.scriptDialog(.result(try claudeQuota()))
        #expect(await harness.coordinator.requestClaudeKeychainAccess() == true)
        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == nil)
        let readsAfterClick = harness.diagnostics.readCount

        harness.quota.releaseBackground()
        await pollUntil { await harness.store.snapshot(for: .codex).quota?.windows.first?.usedPercent == 33 }
        let claude = await harness.store.snapshot(for: .claude)
        #expect(claude.claudeQuotaFailureReason == nil, "the older denied result must not return")
        #expect(claude.quotaStatus == .fresh)
        #expect(claude.quota != nil)
        #expect(harness.diagnostics.readCount == readsAfterClick, "a dropped Claude result has no diagnostics read")
        await harness.coordinator.stop()
    }

    @Test func aBackgroundAttemptStartedDuringTheDialogAndFinishingAfterItIsDropped() async throws {
        let harness = try await Harness.startedInDeniedState()
        harness.quota.holdDialog()
        let click = Task { await harness.coordinator.requestClaudeKeychainAccess() }
        await harness.quota.waitUntilDialogIsOpen()

        harness.quota.holdNextBackground()
        harness.quota.scriptBackground(.result(claudeDenied(plus: try codexQuota(usedPercent: 44))))
        await harness.coordinator.manualRefresh()
        await harness.quota.waitUntilBackgroundIsHeld()

        harness.quota.answerDialog(.result(try claudeQuota()))
        #expect(await click.valueUnlessCancelled == true)

        harness.quota.releaseBackground()
        await pollUntil { await harness.store.snapshot(for: .codex).quota?.windows.first?.usedPercent == 44 }
        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == nil)
        await harness.coordinator.stop()
    }

    @Test func aDroppedClaudeResultStillCompletesItsAttempt() async throws {
        let harness = try await Harness.startedInDeniedState()
        let events = harness.events
        harness.quota.holdDialog()
        let click = Task { await harness.coordinator.requestClaudeKeychainAccess() }
        await harness.quota.waitUntilDialogIsOpen()
        let eventsBefore = events.values.count

        harness.quota.scriptBackground(.result(claudeDenied(plus: try codexQuota(usedPercent: 21))))
        await harness.coordinator.manualRefresh()
        await pollUntil { events.values.count >= eventsBefore + 2 }

        #expect(events.values.suffix(2).map(\.phase) == [.started, .completed])
        #expect(events.values.last?.outcome == .unavailable, "a dropped Claude result is not a Claude failure")
        harness.quota.answerDialog(.result(claudeDenied()))
        _ = await click.valueUnlessCancelled
        await harness.coordinator.stop()
    }

    @Test func aWholeBridgeFailureDuringTheDialogLeavesClaudeAlone() async throws {
        let harness = try await Harness.startedInDeniedState()
        harness.quota.holdDialog()
        let click = Task { await harness.coordinator.requestClaudeKeychainAccess() }
        await harness.quota.waitUntilDialogIsOpen()

        harness.quota.scriptBackground(.failure(BridgeFailure.nullPointer))
        await harness.coordinator.manualRefresh()
        await pollUntil { await harness.store.snapshot(for: .codex).quotaStatus != .fresh }

        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == .credentialAccessUnavailable)
        harness.quota.answerDialog(.result(claudeDenied()))
        _ = await click.valueUnlessCancelled
        await harness.coordinator.stop()
    }

    // MARK: - One click, one read

    @Test func aClickRunsExactlyOneUserInitiatedRead() async throws {
        let harness = try await Harness.startedInDeniedState()
        harness.quota.scriptDialog(.result(try claudeQuota()))

        #expect(await harness.coordinator.requestClaudeKeychainAccess() == true)

        #expect(harness.quota.userInitiatedClaudeCallCount == 1)
        #expect(harness.quota.intents == [.backgroundAll, .userInitiated(provider: .claude)])
        await harness.coordinator.stop()
    }

    @Test func clicksWhileTheDialogIsOpenDoNotStackAnotherRead() async throws {
        let harness = try await Harness.startedInDeniedState()
        harness.quota.holdDialog()
        let click = Task { await harness.coordinator.requestClaudeKeychainAccess() }
        await harness.quota.waitUntilDialogIsOpen()

        for _ in 0 ..< 3 {
            #expect(await harness.coordinator.requestClaudeKeychainAccess() == false)
        }
        #expect(harness.quota.userInitiatedClaudeCallCount == 1)

        harness.quota.answerDialog(.result(try claudeQuota()))
        #expect(await click.valueUnlessCancelled == true)
        #expect(harness.quota.userInitiatedClaudeCallCount == 1)
        await harness.coordinator.stop()
    }

    @Test func theLoginVerificationPathNeverStacksADialogOnThisRead() async throws {
        let harness = try await Harness.startedInDeniedState()
        harness.quota.holdDialog()
        let click = Task { await harness.coordinator.requestClaudeKeychainAccess() }
        await harness.quota.waitUntilDialogIsOpen()

        #expect(await harness.coordinator.refreshQuota(afterUserAuthenticationFor: .claude) == false)
        #expect(harness.quota.userInitiatedClaudeCallCount == 1)

        harness.quota.answerDialog(.result(try claudeQuota()))
        #expect(await click.valueUnlessCancelled == true)
        await harness.coordinator.stop()
    }

    @Test func thisReadNeverStacksADialogOnTheLoginVerificationPath() async throws {
        let harness = try await Harness.startedInDeniedState()
        harness.quota.holdDialog()
        let verification = Task { await harness.coordinator.refreshQuota(afterUserAuthenticationFor: .claude) }
        await harness.quota.waitUntilDialogIsOpen()

        #expect(await harness.coordinator.requestClaudeKeychainAccess() == false)
        #expect(harness.quota.userInitiatedClaudeCallCount == 1)

        harness.quota.answerDialog(.result(try claudeQuota()))
        #expect(await verification.valueUnlessCancelled == true)
        await harness.coordinator.stop()
    }

    @Test func aFinishedReadAllowsALaterClick() async throws {
        let harness = try await Harness.startedInDeniedState()
        harness.quota.scriptDialog(.result(claudeDenied()))
        #expect(await harness.coordinator.requestClaudeKeychainAccess() == false)

        harness.quota.scriptDialog(.result(try claudeQuota()))
        #expect(await harness.coordinator.requestClaudeKeychainAccess() == true)

        #expect(harness.quota.userInitiatedClaudeCallCount == 2)
        await harness.coordinator.stop()
    }

    @Test func aStoppedCoordinatorRunsNoRead() async throws {
        let harness = Harness()
        #expect(await harness.coordinator.requestClaudeKeychainAccess() == false)
        #expect(harness.quota.intents.isEmpty)
    }

    @Test func aDialogLeftOpenAcrossARestartIsNotStackedAndItsResultIsDropped() async throws {
        let harness = try await Harness.startedInDeniedState()
        harness.quota.holdDialog()
        let click = Task { await harness.coordinator.requestClaudeKeychainAccess() }
        await harness.quota.waitUntilDialogIsOpen()

        await harness.coordinator.stop()
        harness.quota.scriptBackground(.result(claudeDenied()))
        await harness.coordinator.start()
        await pollUntil { harness.quota.backgroundCallCount >= 2 }

        // The first read is still blocked in macOS, so a second one would
        // show a second dialog right after it.
        #expect(await harness.coordinator.requestClaudeKeychainAccess() == false)
        #expect(harness.quota.userInitiatedClaudeCallCount == 1)

        harness.quota.answerDialog(.result(try claudeQuota()))
        #expect(await click.valueUnlessCancelled == false)
        #expect(await harness.store.snapshot(for: .claude).quota == nil, "the old run's result is dropped")

        harness.quota.scriptDialog(.result(try claudeQuota()))
        #expect(await harness.coordinator.requestClaudeKeychainAccess() == true)
        #expect(harness.quota.userInitiatedClaudeCallCount == 2)
        await harness.coordinator.stop()
    }

    // MARK: - Never automatic

    @Test func noAutomaticPathRequestsTheUserInitiatedRead() async throws {
        let harness = try await Harness.startedInDeniedState()
        await harness.quota.waitUntilBackgroundCallCount(1)
        let recovery = await harness.coordinator.recoveryRequestToken()

        // Timer. The quota and usage safety loops are both asleep first.
        await harness.clock.waitUntilSleeperCount(2)
        harness.quota.scriptBackground(.result(claudeDenied()))
        harness.clock.advance(by: 300)
        await harness.quota.waitUntilBackgroundCallCount(2)

        // Wake and connectivity recovery.
        await harness.waitUntilIdle()
        harness.quota.scriptBackground(.result(claudeDenied()))
        harness.clock.setNowWithoutWakingSleepers(harness.clock.now.addingTimeInterval(301))
        await recovery.submit(.wake)
        await harness.quota.waitUntilBackgroundCallCount(3)
        await harness.waitUntilIdle()
        harness.quota.scriptBackground(.result(claudeDenied()))
        harness.clock.setNowWithoutWakingSleepers(harness.clock.now.addingTimeInterval(301))
        await recovery.submit(.connectivity)
        await harness.quota.waitUntilBackgroundCallCount(4)

        // Popover, manual retry and a restart (startup refresh).
        await harness.waitUntilIdle()
        harness.quota.scriptBackground(.result(claudeDenied()))
        await harness.coordinator.popoverOpened()
        await harness.quota.waitUntilBackgroundCallCount(5)
        await harness.waitUntilIdle()
        harness.quota.scriptBackground(.result(claudeDenied()))
        await harness.coordinator.manualRefresh()
        await harness.quota.waitUntilBackgroundCallCount(6)
        await harness.waitUntilIdle()
        await harness.coordinator.stop()
        harness.quota.scriptBackground(.result(claudeDenied()))
        await harness.coordinator.start()
        await harness.quota.waitUntilBackgroundCallCount(7)
        await harness.waitUntilIdle()

        #expect(harness.quota.intents.allSatisfy { $0 == .backgroundAll }, "\(harness.quota.intents)")
        #expect(harness.quota.userInitiatedClaudeCallCount == 0)
        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == .credentialAccessUnavailable)
        await harness.coordinator.stop()
    }

    // MARK: - Outcomes

    @Test func successClearsTheFailureAndShowsQuota() async throws {
        let harness = try await Harness.startedInDeniedState()
        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == .credentialAccessUnavailable)

        harness.quota.scriptDialog(.result(try claudeQuota()))
        #expect(await harness.coordinator.requestClaudeKeychainAccess() == true)

        let claude = await harness.store.snapshot(for: .claude)
        #expect(claude.claudeQuotaFailureReason == nil)
        #expect(claude.quotaStatus == .fresh)
        #expect(claude.quota?.windows.first?.id == "claude.session")
        await harness.coordinator.stop()
    }

    @Test func cancellingOrDenyingKeepsTheReasonWithoutARetryAndTheNextRefreshStaysBackground() async throws {
        let harness = try await Harness.startedInDeniedState()
        harness.diagnostics.script { now in diagnosticsRead(origin: "credentialAccessDenied", lastAttemptAt: now) }

        harness.quota.scriptDialog(.result(claudeDenied()))
        #expect(await harness.coordinator.requestClaudeKeychainAccess() == false)
        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == .credentialAccessUnavailable)

        // No retry: the only read since the startup refresh is the click's.
        await settle(watchingFor: { harness.quota.intents.count > 2 })
        #expect(harness.quota.intents == [.backgroundAll, .userInitiated(provider: .claude)])

        harness.quota.scriptBackground(.result(claudeDenied()))
        await harness.coordinator.manualRefresh()
        await harness.quota.waitUntilBackgroundCallCount(2)
        #expect(harness.quota.intents.last == .backgroundAll)
        #expect(harness.quota.userInitiatedClaudeCallCount == 1)
        await harness.coordinator.stop()
    }

    @Test func aThrownFailureFromTheReadDoesNotCrashAndLeavesAnotherClickPossible() async throws {
        let harness = try await Harness.startedInDeniedState()
        harness.quota.scriptDialog(.failure(BridgeFailure.nullPointer))
        #expect(await harness.coordinator.requestClaudeKeychainAccess() == false)
        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == .couldNotUpdateQuota)
        #expect(await harness.store.snapshot(for: .codex).quotaStatus == .fresh, "only Claude is affected")

        harness.quota.scriptDialog(.result(try claudeQuota()))
        #expect(await harness.coordinator.requestClaudeKeychainAccess() == true)
        await harness.coordinator.stop()
    }

    @Test func anExpiredCredentialAfterASuccessfulReadShowsTheExpiredReason() async throws {
        let harness = try await Harness.startedInDeniedState()
        harness.diagnostics.script { now in diagnosticsRead(origin: "keychainCredentialExpired", lastAttemptAt: now) }

        harness.quota.scriptDialog(.result(claudeError("authenticationExpired")))
        #expect(await harness.coordinator.requestClaudeKeychainAccess() == false)

        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == .claudeCodeAccessExpired)
        #expect(harness.diagnostics.readCount == 2, "startup refresh and the click, once each")
        #expect(harness.diagnostics.reportCount == 2)
        await harness.coordinator.stop()
    }
}

// MARK: - Fixtures

private let canaryMessage = "RAW_ERROR_TOKEN_PATH_CANARY"

private func claudeError(_ code: String) -> QuotaRefreshResult {
    .init(snapshots: [:], errors: [.claude: .init(provider: "claude", code: code, message: canaryMessage, action: nil)])
}

private func claudeDenied(plus other: QuotaRefreshResult? = nil) -> QuotaRefreshResult {
    .init(snapshots: other?.snapshots ?? [:],
          errors: [.claude: .init(provider: "claude", code: "permissionDenied", message: canaryMessage, action: nil)])
}

private func claudeQuota() throws -> QuotaRefreshResult {
    let base = ClaudeKeychainAccessTests.start
    return .init(snapshots: [.claude: QuotaSnapshot(windows: [
        try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 30, resetsAt: base.addingTimeInterval(7_200)),
        try QuotaWindow(id: "claude.weekly", title: "Weekly", usedPercent: 40, resetsAt: base.addingTimeInterval(86_400)),
    ])], errors: [:])
}

private func codexQuota(usedPercent: Double) throws -> QuotaRefreshResult {
    let base = ClaudeKeychainAccessTests.start
    return .init(snapshots: [.codex: QuotaSnapshot(windows: [
        try QuotaWindow(id: "codex.primary", title: "Primary", usedPercent: usedPercent, resetsAt: base.addingTimeInterval(7_200)),
    ])], errors: [:])
}

/// A read the way the bridge reports it: whole-second attempt time and a
/// closed origin.
private func diagnosticsRead(origin: String, lastAttemptAt: Date) -> ClaudeQuotaDiagnosticsRead {
    let formatter = ISO8601DateFormatter()
    let attempt = formatter.string(from: Date(timeIntervalSince1970: floor(lastAttemptAt.timeIntervalSince1970)))
    let json = """
    {"schemaVersion":"needlbar.v1","ok":true,"generatedAt":"\(attempt)","data":{"providers":[{"provider":"claude","usageStatus":"available","quotaStatus":"error","usageSource":"local","quotaSource":"oauth","lastAttemptAt":"\(attempt)","claudeQuotaFailureOrigin":"\(origin)"}]},"errors":[]}
    """
    return Result { try BridgeDecoder().decodeDiagnosticsEnvelope(Data(json.utf8)) }
}

// MARK: - Test doubles

private struct Harness {
    let store: ProviderSnapshotStore
    let quota: DialogQuotaRepository
    let diagnostics: FakeDiagnostics
    let clock: ManualClock
    let events = AttemptEvents()
    let coordinator: RefreshCoordinator

    init() {
        let clock = ManualClock(now: ClaudeKeychainAccessTests.start)
        let diagnostics = FakeDiagnostics(clock: clock)
        let events = self.events
        store = ProviderSnapshotStore(now: { clock.now })
        quota = DialogQuotaRepository()
        self.diagnostics = diagnostics
        self.clock = clock
        coordinator = RefreshCoordinator(
            usageRepository: EmptyUsageRepository(),
            quotaRepository: quota,
            store: store,
            clock: clock,
            claudeQuotaDiagnostics: diagnostics.completion,
            quotaAttemptObserver: { events.append($0) }
        )
    }

    /// Started, with its startup refresh applied: Codex fresh, Claude showing
    /// "Credential access unavailable".
    static func startedInDeniedState() async throws -> Harness {
        let harness = Harness()
        harness.quota.scriptBackground(.result(claudeDenied(plus: try codexQuota(usedPercent: 10))))
        await harness.coordinator.start()
        await pollUntil { await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == .credentialAccessUnavailable }
        await pollUntil { await harness.store.snapshot(for: .codex).quota != nil }
        await harness.waitUntilIdle()
        return harness
    }

    /// Returns once every started background attempt has completed. The
    /// coordinator frees its quota slot without suspending after the completed
    /// event, so the next request reaching the actor starts at once.
    func waitUntilIdle() async {
        await pollUntil {
            let phases = events.values.map(\.phase)
            return !phases.isEmpty
                && phases.filter { $0 == .started }.count == phases.filter { $0 != .started }.count
        }
    }
}

private final class AttemptEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [QuotaAttemptEvent] = []
    var values: [QuotaAttemptEvent] { lock.withLock { recorded } }
    func append(_ event: QuotaAttemptEvent) { lock.withLock { recorded.append(event) } }
}

private struct EmptyUsageRepository: UsageRepository {
    func refresh() throws -> UsageRefreshResult { .init(snapshots: [:], errors: [:]) }
}

/// Answers background refreshes from a script, and can hold a user-initiated
/// Claude read open until the test answers it, as a macOS dialog would. Every
/// hold is bounded so a failing test frees its thread instead of stalling.
private final class DialogQuotaRepository: QuotaRepository, @unchecked Sendable {
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

    private static let holdTimeout: DispatchTimeInterval = .seconds(40)

    private let lock = NSLock()
    private let changes = ConditionWaiters()
    private var recorded: [QuotaRefreshIntent] = []
    private var backgroundOutcomes: [Outcome] = []
    private var dialogOutcomes: [Outcome] = []
    private var holdsDialog = false
    private var dialogOpen = false
    private var holdsBackground = false
    private var backgroundHeld = false
    private let dialogAnswer = DispatchSemaphore(value: 0)
    private let backgroundRelease = DispatchSemaphore(value: 0)

    var intents: [QuotaRefreshIntent] { lock.withLock { recorded } }
    var dialogIsOpen: Bool { lock.withLock { dialogOpen } }
    var backgroundCallCount: Int { lock.withLock { recorded.filter { $0 == .backgroundAll }.count } }
    var userInitiatedClaudeCallCount: Int {
        lock.withLock { recorded.filter { $0 == .userInitiated(provider: .claude) }.count }
    }

    func scriptBackground(_ outcome: Outcome) { lock.withLock { backgroundOutcomes.append(outcome) } }
    func scriptDialog(_ outcome: Outcome) { lock.withLock { dialogOutcomes.append(outcome) } }
    func holdDialog() { lock.withLock { holdsDialog = true } }
    func holdNextBackground() { lock.withLock { holdsBackground = true } }

    func answerDialog(_ outcome: Outcome) {
        scriptDialog(outcome)
        dialogAnswer.signal()
    }

    func releaseBackground() { backgroundRelease.signal() }

    func waitUntilDialogIsOpen() async { await changes.wait { self.dialogIsOpen } }
    func waitUntilBackgroundIsHeld() async { await changes.wait { self.lock.withLock { self.backgroundHeld } } }
    func waitUntilBackgroundCallCount(_ expected: Int) async {
        await changes.wait { self.backgroundCallCount >= expected }
    }

    func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult {
        let (hold, isDialog) = lock.withLock { () -> (Bool, Bool) in
            recorded.append(intent)
            if intent == .userInitiated(provider: .claude) {
                let hold = holdsDialog
                holdsDialog = false
                dialogOpen = hold
                return (hold, true)
            }
            let hold = holdsBackground
            holdsBackground = false
            backgroundHeld = hold
            return (hold, false)
        }
        changes.signal()
        if isDialog {
            if hold {
                _ = dialogAnswer.wait(timeout: .now() + Self.holdTimeout)
                lock.withLock { dialogOpen = false }
                changes.signal()
            }
            return try lock.withLock { () -> Outcome in
                dialogOutcomes.isEmpty ? .result(.init(snapshots: [:], errors: [:])) : dialogOutcomes.removeFirst()
            }.get()
        }
        if hold { _ = backgroundRelease.wait(timeout: .now() + Self.holdTimeout) }
        return try lock.withLock { () -> Outcome in
            backgroundOutcomes.isEmpty ? .result(.init(snapshots: [:], errors: [:])) : backgroundOutcomes.removeFirst()
        }.get()
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
