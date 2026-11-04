import Foundation
import NeedlbarClaudeStatusLineSupport

public protocol ClockLike: Sendable {
    var now: Date { get }
    func sleep(for duration: Duration) async throws
}

public struct SystemClock: ClockLike {
    public init() {}

    public var now: Date { Date() }

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

public enum ClaudeLoginPreflightOutcome: Equatable, Sendable {
    case verified
    case requiresAuthentication
    case keychainPermissionRequired
    case verificationFailed
}

public actor RefreshCoordinator {
    public static let safetyInterval: Duration = .seconds(5 * 60)
    public static let popoverQuotaRefreshThreshold: TimeInterval = 60
    /// How often a passed reset, a deferred usage change, a backoff retry and the
    /// periodic run are checked. It reads only actor and store state.
    static let claudeUsageTickInterval: Duration = .seconds(60)

    private let usageRepository: any UsageRepository
    private let quotaRepository: any QuotaRepository
    private let claudeUsageRepository: (any QuotaRepository)?
    private let store: ProviderSnapshotStore
    private let clock: any ClockLike
    private let usageFileWatcher: (any UsageFileWatching)?
    private let quotaApplicationWillApply: (@Sendable () async -> Void)?
    private let quotaIntentRegistered: (@Sendable (QuotaRefreshIntent) -> Void)?
    private let statusLineApplicationWillApply: (@Sendable () async -> Void)?
    private let backgroundQuotaOperationCompleted: (@Sendable () async -> Void)?
    private let claudeQuotaOperationCompleted: (@Sendable () async -> Void)?
    private let claudeQuotaDiagnostics: ClaudeQuotaCompletionDiagnostics?
    private let widgetUsageDayCapture: any WidgetUsageDayCapturing
    private let statusLineRepository: (any ClaudeStatusLineCacheReading)?
    private let backgroundAttemptClock = BackgroundQuotaAttemptClock()
    private let quotaAttemptLedger: QuotaAttemptLedger
    /// Reports Claude runs. `quotaAttemptLedger` only gates the other refresh.
    private let claudeUsageAttemptLedger: QuotaAttemptLedger
    private var claudeUsageSchedule = ClaudeUsageProbeSchedule()
    /// Retained until the physical call returns, so runs never overlap across a restart.
    private var claudeUsageProbeTask: Task<Void, Never>?
    private var claudeUsageTickTask: Task<Void, Never>?
    private var lastClaudeUsageTotalTokens: UInt64?

    private struct UserQuotaWaiter {
        let generation: UInt64
        let backgroundTicket: UInt64?
        let continuation: CheckedContinuation<Bool, Never>
    }

    private struct ClaudePreflightWaiter {
        let generation: UInt64
        let continuation: CheckedContinuation<ClaudeLoginPreflightOutcome, Never>
    }

    private enum UserQuotaWaiterBatch {
        case all
        case beforeBackgroundTicket(UInt64)

        func contains(_ waiter: UserQuotaWaiter) -> Bool {
            switch self {
            case .all:
                true
            case .beforeBackgroundTicket:
                waiter.backgroundTicket == nil
            }
        }
    }

    private var usageTask: Task<Void, Never>?
    private var quotaTask: Task<Void, Never>?
    private var statusLineTask: Task<Void, Never>?
    private var statusLineReadRequestedWhileInFlight = false
    private var usageSafetyTask: Task<Void, Never>?
    private var quotaSafetyTask: Task<Void, Never>?
    private var lastBackgroundQuotaSuccessfulAt: Date?
    private var isRunning = false
    private var usageRefreshRequestedWhileInFlight = false
    private var usageQueuedGeneration: UInt64?
    private var runGeneration: UInt64 = 0
    private var activeQuotaIntent: QuotaRefreshIntent?
    private var activeQuotaUserWaiterBatch: UserQuotaWaiterBatch?
    private var queuedBackgroundQuotaRefresh = false
    private var queuedClaudePreflight = false
    private var queuedUserInitiatedProviders: Set<ProviderID> = []
    private var queuedUserInitiatedProvidersAheadOfBackground: Set<ProviderID>?
    private var queuedUserInitiatedProvidersAfterBackground: Set<ProviderID> = []
    private var queuedBackgroundTicket: UInt64?
    private var pendingBackgroundTrigger: QuotaRefreshTrigger?
    private var pendingScheduledDueAt: Date?
    private var nextQueuedBackgroundTicket: UInt64 = 0
    private var userQuotaWaiters: [ProviderID: [UserQuotaWaiter]] = [:]
    private var completingUserQuotaWaiters: [ProviderID: [UserQuotaWaiter]] = [:]
    private var claudePreflightWaiters: [ClaudePreflightWaiter] = []
    private var completingClaudePreflightWaiters: [ClaudePreflightWaiter] = []

    public init(
        usageRepository: any UsageRepository,
        quotaRepository: any QuotaRepository,
        claudeUsageRepository: (any QuotaRepository)? = nil,
        store: ProviderSnapshotStore,
        clock: any ClockLike = SystemClock(),
        lastQuotaSuccessfulAt: Date? = nil,
        usageFileWatcher: (any UsageFileWatching)? = nil,
        widgetUsageDayCapture: any WidgetUsageDayCapturing = SystemWidgetUsageDayCapture(),
        statusLineRepository: (any ClaudeStatusLineCacheReading)? = nil,
        claudeQuotaOperationCompleted: (@Sendable () async -> Void)? = nil,
        claudeQuotaDiagnostics: ClaudeQuotaCompletionDiagnostics? = nil,
        quotaAttemptObserver: (@Sendable (QuotaAttemptEvent) -> Void)? = nil
    ) {
        self.init(
            usageRepository: usageRepository,
            quotaRepository: quotaRepository,
            claudeUsageRepository: claudeUsageRepository,
            store: store,
            clock: clock,
            lastQuotaSuccessfulAt: lastQuotaSuccessfulAt,
            usageFileWatcher: usageFileWatcher,
            quotaApplicationWillApply: nil,
            quotaIntentRegistered: nil,
            statusLineApplicationWillApply: nil,
            widgetUsageDayCapture: widgetUsageDayCapture,
            statusLineRepository: statusLineRepository,
            backgroundQuotaOperationCompleted: nil,
            claudeQuotaOperationCompleted: claudeQuotaOperationCompleted,
            claudeQuotaDiagnostics: claudeQuotaDiagnostics,
            quotaAttemptObserver: quotaAttemptObserver
        )
    }

    init(
        usageRepository: any UsageRepository,
        quotaRepository: any QuotaRepository,
        claudeUsageRepository: (any QuotaRepository)? = nil,
        store: ProviderSnapshotStore,
        clock: any ClockLike = SystemClock(),
        lastQuotaSuccessfulAt: Date? = nil,
        usageFileWatcher: (any UsageFileWatching)? = nil,
        quotaApplicationWillApply: (@Sendable () async -> Void)? = nil,
        quotaIntentRegistered: (@Sendable (QuotaRefreshIntent) -> Void)? = nil,
        statusLineApplicationWillApply: (@Sendable () async -> Void)? = nil,
        widgetUsageDayCapture: any WidgetUsageDayCapturing = SystemWidgetUsageDayCapture(),
        statusLineRepository: (any ClaudeStatusLineCacheReading)? = nil,
        backgroundQuotaOperationCompleted: (@Sendable () async -> Void)? = nil,
        claudeQuotaOperationCompleted: (@Sendable () async -> Void)? = nil,
        claudeQuotaDiagnostics: ClaudeQuotaCompletionDiagnostics? = nil,
        quotaAttemptObserver: (@Sendable (QuotaAttemptEvent) -> Void)? = nil
    ) {
        self.usageRepository = usageRepository
        self.quotaRepository = quotaRepository
        self.store = store
        self.clock = clock
        self.lastBackgroundQuotaSuccessfulAt = lastQuotaSuccessfulAt
        self.usageFileWatcher = usageFileWatcher
        self.quotaApplicationWillApply = quotaApplicationWillApply
        self.quotaIntentRegistered = quotaIntentRegistered
        self.statusLineApplicationWillApply = statusLineApplicationWillApply
        self.widgetUsageDayCapture = widgetUsageDayCapture
        self.statusLineRepository = statusLineRepository
        self.claudeQuotaOperationCompleted = claudeQuotaOperationCompleted
        self.claudeQuotaDiagnostics = claudeQuotaDiagnostics
        self.claudeUsageRepository = claudeUsageRepository
        self.backgroundQuotaOperationCompleted = backgroundQuotaOperationCompleted
        self.quotaAttemptLedger = QuotaAttemptLedger(observer: nil)
        self.claudeUsageAttemptLedger = QuotaAttemptLedger(observer: quotaAttemptObserver)
    }

    deinit {
        usageTask?.cancel()
        quotaTask?.cancel()
        statusLineTask?.cancel()
        usageSafetyTask?.cancel()
        quotaSafetyTask?.cancel()
        claudeUsageProbeTask?.cancel()
        claudeUsageTickTask?.cancel()
    }

    /// Starts refresh scheduling and installs a fresh generation-bound watcher receiver.
    public func start() async {
        guard !isRunning else { return }
        resumeAllUserQuotaWaiters(with: false)
        // A popover may have started a cache read before scheduling began.
        statusLineTask?.cancel()
        statusLineTask = nil
        statusLineReadRequestedWhileInFlight = false
        runGeneration &+= 1
        quotaAttemptLedger.advance(to: runGeneration)
        claudeUsageAttemptLedger.advance(to: runGeneration)
        claudeUsageSchedule = ClaudeUsageProbeSchedule()
        lastClaudeUsageTotalTokens = nil
        isRunning = true
        let generation = runGeneration
        if let usageFileWatcher {
            await usageFileWatcher.start(using: usageRefreshRequestToken(generation: generation))
            guard isRunning, generation == runGeneration else {
                return
            }
        }
        requestUsageRefresh()
        requestStatusLineRead()
        requestClaudeUsageProbe(trigger: .startup)
        requestQuotaRefresh(trigger: .startup)
        scheduleSafetyRefreshes()
    }

    public func requestUsageRefresh(generation: UInt64? = nil) {
        guard isRunning else { return }
        if let generation, (!isRunning || generation != runGeneration) { return }
        guard usageTask == nil else {
            usageRefreshRequestedWhileInFlight = true
            usageQueuedGeneration = runGeneration
            return
        }
        beginUsageRefresh()
    }

    public func recoveryRequestToken() -> QuotaRecoveryRequestToken {
        let generation = runGeneration
        return QuotaRecoveryRequestToken { [weak self] trigger in
            await self?.recoverQuota(trigger: trigger, generation: generation)
        }
    }

    private func recoveryIsDue() -> Bool {
        guard let last = backgroundAttemptClock.latest else { return false }
        let age = clock.now.timeIntervalSince(last)
        return age.isFinite && age >= 300
    }

    private func recoverQuota(trigger: QuotaRefreshTrigger, generation: UInt64) {
        guard isRunning, generation == runGeneration else { return }
        requestStatusLineRead()
        guard recoveryIsDue() else { return }
        requestQuotaRefresh(trigger: trigger, generation: generation)
    }

    public func popoverOpened() {
        requestStatusLineRead()
        guard let lastBackgroundQuotaSuccessfulAt else {
            requestQuotaRefresh(trigger: .popover)
            return
        }
        guard clock.now.timeIntervalSince(lastBackgroundQuotaSuccessfulAt) > Self.popoverQuotaRefreshThreshold else {
            return
        }
        requestQuotaRefresh(trigger: .popover)
    }

    public func manualRefresh() async {
        let generation = runGeneration
        if let usageTask {
            requestUsageRefresh(generation: generation)
            await usageTask.value
            guard generation == runGeneration, isRunning else { return }
        } else {
            beginUsageRefresh()
        }

        requestStatusLineRead()
        requestClaudeUsageProbe(trigger: .manual)
        if let quotaTask {
            requestQuotaRefresh(trigger: .manual)
            await quotaTask.value
            guard generation == runGeneration, isRunning else { return }
        } else {
            requestQuotaRefresh(trigger: .manual)
        }
    }

    public func refreshQuota(afterUserAuthenticationFor provider: ProviderID) async -> Bool {
        guard isRunning, provider == .claude || provider == .codex else { return false }
        return await withCheckedContinuation { continuation in
            let intent = QuotaRefreshIntent.userInitiated(provider: provider)
            let waiter = UserQuotaWaiter(
                generation: runGeneration,
                backgroundTicket: queuedBackgroundTicket,
                continuation: continuation
            )
            if case .userInitiated(let activeProvider) = activeQuotaIntent,
               activeProvider == provider,
               waiter.backgroundTicket == nil,
               completingUserQuotaWaiters[provider]?.contains(where: { $0.generation == runGeneration }) == true
            {
                completingUserQuotaWaiters[provider, default: []].append(waiter)
                quotaIntentRegistered?(intent)
                return
            }
            if queuedBackgroundTicket != nil {
                userQuotaWaiters[provider, default: []].append(waiter)
                queuedUserInitiatedProvidersAfterBackground.insert(provider)
                quotaIntentRegistered?(intent)
                return
            }
            let hadWaiter = userQuotaWaiters[provider]?.contains { $0.generation == runGeneration } ?? false
            userQuotaWaiters[provider, default: []].append(waiter)
            quotaIntentRegistered?(intent)
            switch activeQuotaIntent {
            case nil:
                beginQuotaRefresh(intent: intent, trigger: .manual)
            case .userInitiated(let activeProvider) where activeProvider == provider && hadWaiter:
                break
            default:
                queuedUserInitiatedProviders.insert(provider)
            }
        }
    }

    /// Performs one serialized, Claude-only, no-UI quota check for an
    /// explicit connection click. The current response, never cached quota,
    /// determines the outcome used by the login coordinator.
    public func preflightClaudeLogin() async -> ClaudeLoginPreflightOutcome {
        guard isRunning else { return .verificationFailed }
        return await withCheckedContinuation { continuation in
            let waiter = ClaudePreflightWaiter(generation: runGeneration, continuation: continuation)
            if activeQuotaIntent == .claudePreflight {
                if completingClaudePreflightWaiters.contains(where: { $0.generation == runGeneration }) {
                    completingClaudePreflightWaiters.append(waiter)
                } else {
                    claudePreflightWaiters.append(waiter)
                }
                quotaIntentRegistered?(.claudePreflight)
                return
            }

            claudePreflightWaiters.append(waiter)
            quotaIntentRegistered?(.claudePreflight)
            if quotaTask == nil {
                beginQuotaRefresh(intent: .claudePreflight, trigger: .manual)
            } else {
                queuedClaudePreflight = true
            }
        }
    }

    /// Stops timers and invalidates the installed watcher receiver before a later restart.
    public func stop() async {
        let stoppedGeneration = runGeneration
        let probeInFlight = claudeUsageProbeTask != nil
        runGeneration &+= 1
        quotaAttemptLedger.advance(to: runGeneration)
        claudeUsageAttemptLedger.advance(to: runGeneration)
        if probeInFlight {
            claudeUsageProbeTask?.cancel()
            // A cancel by ID also reaches a run still on its way into the bridge.
            claudeUsageRepository?.cancelClaudeUsageReport(through: stoppedGeneration)
        }
        claudeUsageTickTask?.cancel()
        claudeUsageTickTask = nil
        isRunning = false
        usageTask?.cancel()
        quotaTask?.cancel()
        statusLineTask?.cancel()
        statusLineTask = nil
        statusLineReadRequestedWhileInFlight = false
        usageSafetyTask?.cancel()
        quotaSafetyTask?.cancel()
        usageSafetyTask = nil
        quotaSafetyTask = nil
        usageRefreshRequestedWhileInFlight = false
        usageQueuedGeneration = nil
        queuedBackgroundQuotaRefresh = false
        queuedClaudePreflight = false
        queuedUserInitiatedProviders.removeAll()
        queuedUserInitiatedProvidersAheadOfBackground = nil
        queuedUserInitiatedProvidersAfterBackground.removeAll()
        queuedBackgroundTicket = nil
        pendingBackgroundTrigger = nil
        pendingScheduledDueAt = nil
        resumeAllUserQuotaWaiters(with: false)
        resumeAllClaudePreflightWaiters(with: .verificationFailed)
        if let usageFileWatcher {
            await usageFileWatcher.stop()
        }
    }

    private func scheduleSafetyRefreshes() {
        let clock = clock
        let generation = runGeneration
        usageSafetyTask = Task { [weak self, clock, generation] in
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: Self.safetyInterval)
                } catch is CancellationError {
                    break
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                await self?.requestUsageRefresh(generation: generation)
            }
        }

        quotaSafetyTask = Task { [weak self, clock, generation] in
            while !Task.isCancelled {
                let dueAt = clock.now.addingTimeInterval(300)
                do {
                    try await clock.sleep(for: Self.safetyInterval)
                } catch is CancellationError {
                    break
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                await self?.requestScheduledQuotaRefresh(dueAt: dueAt, generation: generation)
            }
        }

        guard claudeUsageRepository != nil else { return }
        claudeUsageTickTask = Task { [weak self, clock, generation] in
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: Self.claudeUsageTickInterval)
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                await self?.evaluateClaudeUsageProbeTriggers(generation: generation)
            }
        }
    }

    private func usageRefreshRequestToken(generation: UInt64) -> UsageRefreshRequestToken {
        UsageRefreshRequestToken { [weak self] in
            await self?.requestUsageRefresh(generation: generation)
        }
    }

    private func requestScheduledQuotaRefresh(dueAt: Date, generation: UInt64) {
        guard isRunning, generation == runGeneration else { return }
        requestStatusLineRead()
        requestQuotaRefresh(trigger: .scheduled, generation: generation, scheduledDueAt: dueAt)
    }

    private func backgroundRequestIsDue(trigger: QuotaRefreshTrigger, scheduledDueAt: Date?) -> Bool {
        switch trigger {
        case .wake, .connectivity:
            return recoveryIsDue()
        case .scheduled:
            guard let scheduledDueAt, let last = backgroundAttemptClock.latest else { return true }
            return last < scheduledDueAt
        case .startup, .manual, .popover, .usageRecordsChanged, .windowReset, .backoffRetry, .periodic:
            return true
        }
    }

    private func requestQuotaRefresh(
        trigger: QuotaRefreshTrigger,
        generation: UInt64? = nil,
        scheduledDueAt: Date? = nil
    ) {
        if let generation, (!isRunning || generation != runGeneration) { return }
        guard backgroundRequestIsDue(trigger: trigger, scheduledDueAt: scheduledDueAt) else { return }
        guard quotaTask == nil else {
            if !queuedBackgroundQuotaRefresh {
                queuedBackgroundQuotaRefresh = true
                pendingBackgroundTrigger = trigger
                pendingScheduledDueAt = scheduledDueAt
                nextQueuedBackgroundTicket &+= 1
                queuedBackgroundTicket = nextQueuedBackgroundTicket
                queuedUserInitiatedProvidersAheadOfBackground = queuedUserInitiatedProviders
                queuedUserInitiatedProviders.removeAll()
                quotaIntentRegistered?(.backgroundAll)
            } else if trigger == .startup || trigger == .manual || trigger == .popover {
                if pendingBackgroundTrigger == .scheduled || pendingBackgroundTrigger == .wake || pendingBackgroundTrigger == .connectivity {
                    pendingBackgroundTrigger = trigger
                    pendingScheduledDueAt = nil
                }
            }
            return
        }
        beginQuotaRefresh(intent: .backgroundAll, trigger: trigger)
    }

    private func beginUsageRefresh() {
        guard usageTask == nil else { return }
        let repository = usageRepository
        let generation = runGeneration
        let clock = clock
        let widgetUsageDayCapture = widgetUsageDayCapture
        let startedAt = clock.now
        let startedContext = widgetUsageDayCapture.capture(at: startedAt)
        usageTask = Task { [weak self, repository, clock, widgetUsageDayCapture] in
            let result = Result { try repository.refresh() }
            let endedAt = clock.now
            let proof = WidgetUsageDayProvenance(
                startedAt: startedAt,
                startedContext: startedContext,
                endedAt: endedAt,
                endedContext: widgetUsageDayCapture.capture(at: endedAt)
            )
            await self?.finishUsageRefresh(result, usageDayProvenance: proof, applyResult: !Task.isCancelled, generation: generation)
        }
    }

    private func beginQuotaRefresh(
        intent: QuotaRefreshIntent,
        trigger: QuotaRefreshTrigger,
        userWaiterBatch: UserQuotaWaiterBatch = .all
    ) {
        guard quotaTask == nil else { return }
        activeQuotaIntent = intent
        if case .userInitiated = intent {
            activeQuotaUserWaiterBatch = userWaiterBatch
        } else {
            activeQuotaUserWaiterBatch = nil
        }
        let repository = quotaRepository
        let generation = runGeneration
        let clock = clock
        let backgroundAttemptClock = backgroundAttemptClock
        let ledger = quotaAttemptLedger
        let id = UUID()
        ledger.reserve(id: id, generation: generation, trigger: trigger)
        quotaTask = Task { [weak self, repository, intent, clock, backgroundAttemptClock, ledger] in
            guard !Task.isCancelled, let attempt = ledger.claim(
                id: id, generation: generation, at: clock.now,
                backgroundClock: intent == .backgroundAll ? backgroundAttemptClock : nil
            ) else {
                await self?.finishQuotaRefresh(.failure(CancellationError()), intent: intent,
                                              applyResult: false, generation: generation, attempt: nil)
                return
            }
            let result = Result { try repository.refresh(intent: intent) }
            await self?.finishQuotaRefresh(result, intent: intent, applyResult: !Task.isCancelled,
                                          generation: generation, attempt: attempt)
        }
    }

    private func requestClaudeUsageProbe(trigger: QuotaRefreshTrigger) {
        guard isRunning, claudeUsageRepository != nil else { return }
        let action = claudeUsageSchedule.request(trigger, now: clock.now, inFlight: claudeUsageProbeTask != nil)
        if action == .start { beginClaudeUsageProbe(trigger: trigger) }
    }

    /// Starts the run that is due, if any: a deferred request, a displayed window
    /// whose reset has passed, a retry after backoff, or the periodic run.
    private func evaluateClaudeUsageProbeTriggers(generation: UInt64) async {
        guard isRunning, generation == runGeneration, claudeUsageRepository != nil else { return }
        let snapshot = await store.snapshot(for: .claude)
        guard isRunning, generation == runGeneration else { return }
        let now = clock.now
        let selection = ClaudeQuotaPresentationSelector.select(snapshot: snapshot, now: now)
        let resetTimes = [selection.fiveHour, selection.sevenDay, selection.fable].compactMap { $0?.resetsAt }
        if let trigger = claudeUsageSchedule.dueTrigger(
            resetTimes: resetTimes, now: now, inFlight: claudeUsageProbeTask != nil
        ) {
            beginClaudeUsageProbe(trigger: trigger)
        }
    }

    /// A run can take 30 seconds, so it uses a dispatch thread rather than a
    /// cooperative one, and its own slot rather than the Codex and Cursor one.
    private func beginClaudeUsageProbe(trigger: QuotaRefreshTrigger) {
        guard let repository = claudeUsageRepository, claudeUsageProbeTask == nil else { return }
        let generation = runGeneration
        let clock = clock
        let ledger = claudeUsageAttemptLedger
        let id = UUID()
        claudeUsageSchedule.recordStart(at: clock.now)
        ledger.reserve(id: id, generation: generation, trigger: trigger)
        claudeUsageProbeTask = Task { [weak self, repository, clock, ledger] in
            guard !Task.isCancelled, let attempt = ledger.claim(
                id: id, generation: generation, at: clock.now, backgroundClock: nil
            ) else {
                await self?.finishClaudeUsageProbe(.failure(CancellationError()), trigger: trigger,
                                                   applyResult: false, generation: generation, attempt: nil)
                return
            }
            let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<QuotaRefreshResult, Error>, Never>) in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(returning: Result {
                        try repository.refresh(intent: .claudeUsageReport(runID: generation))
                    })
                }
            }
            await self?.finishClaudeUsageProbe(result, trigger: trigger, applyResult: !Task.isCancelled,
                                               generation: generation, attempt: attempt)
        }
    }

    private func finishClaudeUsageProbe(
        _ result: Result<QuotaRefreshResult, Error>,
        trigger: QuotaRefreshTrigger,
        applyResult: Bool,
        generation: UInt64,
        attempt: QuotaAttemptEvent?
    ) async {
        defer {
            claudeUsageProbeTask = nil
            if let pending = claudeUsageSchedule.pendingTrigger {
                requestClaudeUsageProbe(trigger: pending)
            }
        }
        guard applyResult, generation == runGeneration else { return }
        recordClaudeUsageOutcome(result, trigger: trigger, at: clock.now)
        var application = QuotaApplication()
        await applyQuotaResult(result, intent: .claudeUsageReport(runID: generation), applyResult: true,
                               generation: generation, attempt: attempt,
                               claudeAttemptStartedAt: attempt?.startedAt,
                               into: &application)
    }

    private func recordClaudeUsageOutcome(
        _ result: Result<QuotaRefreshResult, Error>, trigger: QuotaRefreshTrigger, at date: Date
    ) {
        var retries = true
        if case .success(let refresh) = result {
            if refresh.errors[.claude] == nil, refresh.snapshots[.claude] != nil {
                claudeUsageSchedule.recordSuccess()
                return
            }
            // Not installed and no usage wait for the next trigger, which includes
            // the periodic run (spec §8).
            let code = refresh.errors[.claude]?.code
            retries = code != "notInstalled" && code != "requiresAuthentication"
        }
        claudeUsageSchedule.recordFailure(trigger: trigger, at: date, retriesWhenBackoffEnds: retries)
    }

    /// Compares the Claude total from the existing usage refresh. The first
    /// observation after start only sets the baseline, because start runs anyway.
    private func noteClaudeUsageRecords(_ total: UInt64?) {
        guard let total else { return }
        defer { lastClaudeUsageTotalTokens = total }
        guard let previous = lastClaudeUsageTotalTokens, previous != total else { return }
        requestClaudeUsageProbe(trigger: .usageRecordsChanged)
    }

    private func requestStatusLineRead() {
        guard let repository = statusLineRepository else { return }
        guard statusLineTask == nil else {
            statusLineReadRequestedWhileInFlight = true
            return
        }
        let generation = runGeneration
        statusLineTask = Task { [weak self, repository] in
            let connectionGeneration = repository.activeGeneration()
            let record = connectionGeneration.flatMap { repository.read(expectedGeneration: $0) }
            await self?.applyStatusLineRecord(record, expectedGeneration: connectionGeneration,
                                              repository: repository, runGeneration: generation)
            await self?.finishStatusLineRead(generation: generation)
        }
    }

    private func finishStatusLineRead(generation: UInt64) {
        guard generation == runGeneration else { return }
        statusLineTask = nil
        let requested = statusLineReadRequestedWhileInFlight
        statusLineReadRequestedWhileInFlight = false
        if isRunning, requested {
            requestStatusLineRead()
        }
    }

    private func applyStatusLineRecord(
        _ record: StatusLineQuotaRecord?,
        expectedGeneration: UUID?,
        repository: any ClaudeStatusLineCacheReading,
        runGeneration: UInt64
    ) async {
        guard runGeneration == self.runGeneration, !Task.isCancelled else { return }
        await statusLineApplicationWillApply?()
        guard runGeneration == self.runGeneration, !Task.isCancelled else { return }
        let validatedRecord = record?.generation == expectedGeneration ? record : nil
        await store.applyClaudeStatusLineQuota(validatedRecord, expectedGeneration: expectedGeneration,
                                               activeGeneration: { repository.activeGeneration() })
    }

    private func finishUsageRefresh(
        _ result: Result<UsageRefreshResult, Error>,
        usageDayProvenance: WidgetUsageDayProvenance,
        applyResult: Bool,
        generation: UInt64
    ) async {
        defer {
            usageTask = nil
            let requested = usageRefreshRequestedWhileInFlight
            let queuedGeneration = usageQueuedGeneration
            usageRefreshRequestedWhileInFlight = false
            usageQueuedGeneration = nil
            if isRunning, queuedGeneration == runGeneration, requested {
                beginUsageRefresh()
            }
        }
        guard applyResult, generation == runGeneration else { return }
        switch result {
        case .success(let refresh):
            for (provider, usage) in refresh.snapshots {
                guard generation == runGeneration, applyResult else { return }
                await store.applyUsage(
                    usage,
                    for: provider,
                    at: clock.now,
                    widgetDayProvenance: usageDayProvenance.provenContext == nil ? nil : usageDayProvenance
                )
            }
            for (provider, error) in refresh.errors {
                guard generation == runGeneration, applyResult else { return }
                await store.markUsageFailure(for: provider, status: status(for: error), at: clock.now)
            }
            // The last store call suspended: a stop and start in that gap must not set
            // the new generation's baseline from this old result.
            guard generation == runGeneration, applyResult else { return }
            noteClaudeUsageRecords(refresh.snapshots[.claude]?.totalTokens)
        case .failure(let error):
            let status = DataStatus.error(message: String(describing: error), lastSuccessfulAt: nil)
            for provider in ProviderID.allCases {
                guard generation == runGeneration, applyResult else { return }
                await store.markUsageFailure(for: provider, status: status, at: clock.now)
            }
        }
    }

    /// What applying a quota result tells the waiters of that attempt.
    private struct QuotaApplication {
        var verificationSucceeded = false
        var preflightOutcome: ClaudeLoginPreflightOutcome = .verificationFailed
    }

    private func finishQuotaRefresh(
        _ result: Result<QuotaRefreshResult, Error>,
        intent: QuotaRefreshIntent,
        applyResult: Bool,
        generation: UInt64,
        attempt: QuotaAttemptEvent?
    ) async {
        var application = QuotaApplication()
        let verifiedProvider: ProviderID?
        let verifiedProviderWaiterBatch: UserQuotaWaiterBatch?
        if case .userInitiated(let provider) = intent {
            verifiedProvider = provider
            verifiedProviderWaiterBatch = activeQuotaUserWaiterBatch
            moveUserQuotaWaiters(
                for: provider,
                generation: generation,
                matching: verifiedProviderWaiterBatch ?? .all
            )
        } else {
            verifiedProvider = nil
            verifiedProviderWaiterBatch = nil
        }
        let isClaudePreflight = intent == .claudePreflight
        if isClaudePreflight {
            moveClaudePreflightWaiters(generation: generation)
        }
        defer {
            if let verifiedProvider {
                resumeCompletingUserQuotaWaiters(
                    for: verifiedProvider,
                    generation: generation,
                    with: applyResult && generation == runGeneration ? application.verificationSucceeded : false
                )
            }
            if isClaudePreflight {
                resumeCompletingClaudePreflightWaiters(
                    generation: generation,
                    with: applyResult && generation == runGeneration ? application.preflightOutcome : .verificationFailed
                )
            }
            quotaTask = nil
            activeQuotaIntent = nil
            activeQuotaUserWaiterBatch = nil
            drainQueuedQuotaRefreshes()
        }

        await applyQuotaResult(result, intent: intent, applyResult: applyResult, generation: generation,
                               attempt: attempt, claudeAttemptStartedAt: attempt?.startedAt,
                               into: &application)
    }

    /// Stores one attempt's result. `attempt` is the ledger's record of it.
    private func applyQuotaResult(
        _ result: Result<QuotaRefreshResult, Error>,
        intent: QuotaRefreshIntent,
        applyResult: Bool,
        generation: UInt64,
        attempt: QuotaAttemptEvent?,
        claudeAttemptStartedAt: Date?,
        into application: inout QuotaApplication
    ) async {
        guard applyResult, generation == runGeneration else { return }
        let includesClaude = intent.includesClaude
        // Read the bridge diagnostics record once for this Claude operation,
        // before storing its reason, and share that read with the reporter.
        var claudeDiagnosticsRead: ClaudeQuotaDiagnosticsRead?
        if includesClaude, let claudeQuotaDiagnostics {
            let read = await claudeQuotaDiagnostics.read()
            guard generation == runGeneration else { return }
            claudeDiagnosticsRead = read
        }
        let claudeFailureOrigin = claudeAttemptStartedAt.flatMap { startedAt in
            ClaudeQuotaFailureOriginAssociation.origin(
                in: claudeDiagnosticsRead,
                attemptStartedAt: startedAt,
                attemptGeneration: generation,
                currentGeneration: runGeneration,
                claudeResultFailed: claudeResultFailed(result)
            )
        }
        switch result {
        case .success(let refresh):
            if intent == .claudePreflight {
                application.preflightOutcome = claudePreflightOutcome(for: refresh)
            }
            let refreshedAt = clock.now
            if case .backgroundAll = intent, !refresh.snapshots.isEmpty {
                lastBackgroundQuotaSuccessfulAt = refreshedAt
            }
            for (provider, quota) in refresh.snapshots {
                guard generation == runGeneration, applyResult else { return }
                if let quotaApplicationWillApply {
                    await quotaApplicationWillApply()
                }
                guard generation == runGeneration, applyResult else { return }
                await store.applyQuota(quota, for: provider, at: refreshedAt)
            }
            for (provider, error) in refresh.errors {
                guard generation == runGeneration, applyResult else { return }
                await store.markQuotaFailure(
                    for: provider,
                    status: quotaStatus(for: error),
                    claudeFailureReason: provider == .claude
                        ? ClaudeQuotaFailureReason(errorCode: error.code, associatedOrigin: claudeFailureOrigin) : nil,
                    at: refreshedAt
                )
            }
            if case .userInitiated(let provider) = intent {
                application.verificationSucceeded = refresh.snapshots[provider] != nil
            }
        case .failure(let error):
            if intent == .claudePreflight {
                application.preflightOutcome = claudePreflightOutcome(for: error)
            }
            if let bridgeFailure = error as? BridgeFailure,
               case .bridgeFailed(let bridgeErrors) = bridgeFailure
            {
                let requested = Set(requestedProviders(for: intent))
                let matchingErrors = bridgeErrors.filter {
                    guard let provider = $0.providerID else { return false }
                    return requested.contains(provider)
                }
                if !matchingErrors.isEmpty {
                    for error in matchingErrors {
                        guard let provider = error.providerID, generation == runGeneration, applyResult else { return }
                        await store.markQuotaFailure(
                            for: provider,
                            status: quotaStatus(for: error),
                            claudeFailureReason: provider == .claude
                                ? ClaudeQuotaFailureReason(errorCode: error.code, associatedOrigin: claudeFailureOrigin) : nil,
                            at: clock.now
                        )
                    }
                    break
                }
            }
            let status = DataStatus.error(message: String(describing: error), lastSuccessfulAt: nil)
            for provider in requestedProviders(for: intent) {
                guard generation == runGeneration, applyResult else { return }
                await store.markQuotaFailure(
                    for: provider,
                    status: status,
                    claudeFailureReason: provider == .claude ? .couldNotUpdateQuota : nil,
                    at: clock.now
                )
            }
        }
        guard applyResult, generation == runGeneration else { return }
        if includesClaude {
            if let claudeDiagnosticsRead { await claudeQuotaDiagnostics?.report(claudeDiagnosticsRead) }
            await claudeQuotaOperationCompleted?()
        } else if case .backgroundAll = intent {
            await backgroundQuotaOperationCompleted?()
        }
        guard generation == runGeneration, isRunning, !Task.isCancelled, let attempt else { return }
        guard case .claudeUsageReport = intent else {
            quotaAttemptLedger.complete(attempt)
            return
        }
        let snapshot = await store.snapshot(for: .claude)
        guard generation == runGeneration, isRunning, !Task.isCancelled else { return }
        let completedAt = clock.now
        let selection = ClaudeQuotaPresentationSelector.select(snapshot: snapshot, now: completedAt)
        let outcome = quotaAttemptOutcome(for: result, intent: intent)
        claudeUsageAttemptLedger.complete(QuotaAttemptEvent(
            id: attempt.id, generation: generation, trigger: attempt.trigger, phase: .completed,
            startedAt: attempt.startedAt, completedAt: completedAt, outcome: outcome,
            directLastSuccessfulAt: snapshot.quotaLastSuccessfulAt,
            failureAttemptAt: outcome == .success ? nil : attempt.startedAt,
            fiveHourSource: observationSource(selection.fiveHour),
            sevenDaySource: observationSource(selection.sevenDay),
            fableSource: observationSource(selection.fable),
            fiveHourReceiptAt: snapshot.claudeStatusLineQuota?.fiveHour?.receivedAt,
            sevenDayReceiptAt: snapshot.claudeStatusLineQuota?.sevenDay?.receivedAt,
            claudeUsageProbe: claudeUsageProbe(in: claudeDiagnosticsRead)))
    }

    private func claudeUsageProbe(in read: ClaudeQuotaDiagnosticsRead?) -> ClaudeUsageProbeDiagnostics? {
        guard case .success(let envelope)? = read else { return nil }
        return envelope.data?.providers.first { $0.provider == .claude }?.claudeUsageProbe
    }

    private func requestedProviders(for intent: QuotaRefreshIntent) -> [ProviderID] {
        switch intent {
        case .userInitiated(let provider): [provider]
        case .claudeUsageReport, .claudePreflight: [.claude]
        case .backgroundAll: [.codex, .cursor]
        }
    }

    private func quotaAttemptOutcome(for result: Result<QuotaRefreshResult, Error>,
                                     intent: QuotaRefreshIntent) -> QuotaAttemptOutcome {
        let provider: ProviderID
        if case .userInitiated(let requested) = intent { provider = requested } else { provider = .claude }
        switch result {
        case .failure: return .failure
        case .success(let refresh):
            if refresh.errors[provider] != nil { return .failure }
            return refresh.snapshots[provider] == nil ? .unavailable : .success
        }
    }

    private func observationSource(_ window: DisplayedClaudeWindow?) -> QuotaObservationSource {
        switch window?.source {
        case .direct: .direct
        case .claudeCodeStatusLine: .statusLine
        case nil: .unavailable
        }
    }

    private func drainQueuedQuotaRefreshes() {
        guard isRunning else { return }
        if queuedClaudePreflight {
            queuedClaudePreflight = false
            beginQuotaRefresh(intent: .claudePreflight, trigger: .manual)
            return
        }
        if let ticket = queuedBackgroundTicket {
            if let provider = ProviderID.allCases.first(where: {
                queuedUserInitiatedProvidersAheadOfBackground?.contains($0) == true
            }) {
                queuedUserInitiatedProvidersAheadOfBackground?.remove(provider)
                beginQuotaRefresh(
                    intent: .userInitiated(provider: provider),
                    trigger: .manual,
                    userWaiterBatch: .beforeBackgroundTicket(ticket)
                )
                return
            }
            queuedUserInitiatedProvidersAheadOfBackground = nil
            queuedBackgroundTicket = nil
            queuedBackgroundQuotaRefresh = false
            queuedUserInitiatedProviders.formUnion(queuedUserInitiatedProvidersAfterBackground)
            queuedUserInitiatedProvidersAfterBackground.removeAll()
            let trigger = pendingBackgroundTrigger
            let dueAt = pendingScheduledDueAt
            pendingBackgroundTrigger = nil
            pendingScheduledDueAt = nil
            if let trigger, backgroundRequestIsDue(trigger: trigger, scheduledDueAt: dueAt) {
                beginQuotaRefresh(intent: .backgroundAll, trigger: trigger)
                return
            }
        }
        if let provider = ProviderID.allCases.first(where: { queuedUserInitiatedProviders.contains($0) }) {
            queuedUserInitiatedProviders.remove(provider)
            beginQuotaRefresh(intent: .userInitiated(provider: provider), trigger: .manual)
            return
        }
        if queuedBackgroundQuotaRefresh {
            queuedBackgroundQuotaRefresh = false
            let trigger = pendingBackgroundTrigger
            let dueAt = pendingScheduledDueAt
            pendingBackgroundTrigger = nil
            pendingScheduledDueAt = nil
            if let trigger, backgroundRequestIsDue(trigger: trigger, scheduledDueAt: dueAt) {
                beginQuotaRefresh(intent: .backgroundAll, trigger: trigger)
            }
        }
    }

    private func resumeAllUserQuotaWaiters(with result: Bool) {
        let waiters = userQuotaWaiters.values.flatMap { $0 } + completingUserQuotaWaiters.values.flatMap { $0 }
        userQuotaWaiters.removeAll()
        completingUserQuotaWaiters.removeAll()
        waiters.forEach { $0.continuation.resume(returning: result) }
    }

    private func moveClaudePreflightWaiters(generation: UInt64) {
        let captured = claudePreflightWaiters.filter { $0.generation == generation }
        claudePreflightWaiters.removeAll { $0.generation == generation }
        completingClaudePreflightWaiters.append(contentsOf: captured)
    }

    private func resumeCompletingClaudePreflightWaiters(
        generation: UInt64,
        with result: ClaudeLoginPreflightOutcome
    ) {
        let completed = completingClaudePreflightWaiters.filter { $0.generation == generation }
        completingClaudePreflightWaiters.removeAll { $0.generation == generation }
        completed.forEach { $0.continuation.resume(returning: result) }
    }

    private func resumeAllClaudePreflightWaiters(with result: ClaudeLoginPreflightOutcome) {
        let waiters = claudePreflightWaiters + completingClaudePreflightWaiters
        claudePreflightWaiters.removeAll()
        completingClaudePreflightWaiters.removeAll()
        waiters.forEach { $0.continuation.resume(returning: result) }
    }

    private func claudePreflightOutcome(for refresh: QuotaRefreshResult) -> ClaudeLoginPreflightOutcome {
        if let error = refresh.errors[.claude] {
            return claudePreflightOutcome(forCode: error.code)
        }
        return refresh.snapshots[.claude] == nil ? .verificationFailed : .verified
    }

    private func claudePreflightOutcome(for error: Error) -> ClaudeLoginPreflightOutcome {
        guard let bridgeFailure = error as? BridgeFailure,
              case let .bridgeFailed(errors) = bridgeFailure
        else { return .verificationFailed }
        let claudeErrors = errors.filter { $0.providerID == .claude }
        guard claudeErrors.count == 1 else { return .verificationFailed }
        return claudePreflightOutcome(forCode: claudeErrors[0].code)
    }

    private func claudePreflightOutcome(forCode code: String) -> ClaudeLoginPreflightOutcome {
        switch code {
        case "requiresAuthentication", "authenticationExpired": .requiresAuthentication
        case "permissionDenied": .keychainPermissionRequired
        default: .verificationFailed
        }
    }

    private func moveUserQuotaWaiters(
        for provider: ProviderID,
        generation: UInt64,
        matching batch: UserQuotaWaiterBatch
    ) {
        let waiters = userQuotaWaiters[provider] ?? []
        let captured = waiters.filter { $0.generation == generation && batch.contains($0) }
        let remaining = waiters.filter { $0.generation != generation || !batch.contains($0) }
        if remaining.isEmpty {
            userQuotaWaiters.removeValue(forKey: provider)
        } else {
            userQuotaWaiters[provider] = remaining
        }
        if !captured.isEmpty {
            completingUserQuotaWaiters[provider, default: []].append(contentsOf: captured)
        }
    }

    private func resumeCompletingUserQuotaWaiters(
        for provider: ProviderID,
        generation: UInt64,
        with result: Bool
    ) {
        let waiters = completingUserQuotaWaiters[provider] ?? []
        let completed = waiters.filter { $0.generation == generation }
        let remaining = waiters.filter { $0.generation != generation }
        if remaining.isEmpty {
            completingUserQuotaWaiters.removeValue(forKey: provider)
        } else {
            completingUserQuotaWaiters[provider] = remaining
        }
        completed.forEach { $0.continuation.resume(returning: result) }
    }

    private func status(for error: BridgeError) -> DataStatus {
        switch error.code {
        case "requiresAuthentication", "authenticationExpired":
            return .requiresAuthentication
        case "noUsageData", "unavailable":
            return .unavailable
        default:
            return .error(message: error.message, lastSuccessfulAt: nil)
        }
    }

    private func quotaStatus(for error: BridgeError) -> DataStatus {
        if error.provider == ProviderID.cursor.rawValue, error.code == "providerUnavailable" {
            return .unavailable
        }
        return status(for: error)
    }

    private func claudeResultFailed(_ result: Result<QuotaRefreshResult, Error>) -> Bool {
        switch result {
        case .success(let refresh): refresh.errors[.claude] != nil
        case .failure: true
        }
    }
}
