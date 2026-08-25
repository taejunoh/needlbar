import Foundation

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

public actor RefreshCoordinator {
    public static let safetyInterval: Duration = .seconds(5 * 60)
    public static let popoverQuotaRefreshThreshold: TimeInterval = 60

    private let usageRepository: any UsageRepository
    private let quotaRepository: any QuotaRepository
    private let store: ProviderSnapshotStore
    private let clock: any ClockLike
    private let usageFileWatcher: (any UsageFileWatching)?
    private let quotaApplicationWillApply: (@Sendable () async -> Void)?

    private struct UserQuotaWaiter {
        let generation: UInt64
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var usageTask: Task<Void, Never>?
    private var quotaTask: Task<Void, Never>?
    private var usageSafetyTask: Task<Void, Never>?
    private var quotaSafetyTask: Task<Void, Never>?
    private var lastBackgroundQuotaSuccessfulAt: Date?
    private var isRunning = false
    private var usageRefreshRequestedWhileInFlight = false
    private var forceCursorSyncRequestedWhileInFlight = false
    private var usageQueuedGeneration: UInt64?
    private var usageTaskIsForced = false
    private var runGeneration: UInt64 = 0
    private var activeQuotaIntent: QuotaRefreshIntent?
    private var queuedBackgroundQuotaRefresh = false
    private var queuedUserInitiatedProviders: Set<ProviderID> = []
    private var userQuotaWaiters: [ProviderID: [UserQuotaWaiter]] = [:]
    private var completingUserQuotaWaiters: [ProviderID: [UserQuotaWaiter]] = [:]

    public init(
        usageRepository: any UsageRepository,
        quotaRepository: any QuotaRepository,
        store: ProviderSnapshotStore,
        clock: any ClockLike = SystemClock(),
        lastQuotaSuccessfulAt: Date? = nil,
        usageFileWatcher: (any UsageFileWatching)? = nil
    ) {
        self.init(
            usageRepository: usageRepository,
            quotaRepository: quotaRepository,
            store: store,
            clock: clock,
            lastQuotaSuccessfulAt: lastQuotaSuccessfulAt,
            usageFileWatcher: usageFileWatcher,
            quotaApplicationWillApply: nil
        )
    }

    init(
        usageRepository: any UsageRepository,
        quotaRepository: any QuotaRepository,
        store: ProviderSnapshotStore,
        clock: any ClockLike = SystemClock(),
        lastQuotaSuccessfulAt: Date? = nil,
        usageFileWatcher: (any UsageFileWatching)? = nil,
        quotaApplicationWillApply: (@Sendable () async -> Void)?
    ) {
        self.usageRepository = usageRepository
        self.quotaRepository = quotaRepository
        self.store = store
        self.clock = clock
        self.lastBackgroundQuotaSuccessfulAt = lastQuotaSuccessfulAt
        self.usageFileWatcher = usageFileWatcher
        self.quotaApplicationWillApply = quotaApplicationWillApply
    }

    deinit {
        usageTask?.cancel()
        quotaTask?.cancel()
        usageSafetyTask?.cancel()
        quotaSafetyTask?.cancel()
    }

    /// Starts refresh scheduling and installs a fresh generation-bound watcher receiver.
    public func start() async {
        guard !isRunning else { return }
        resumeAllUserQuotaWaiters(with: false)
        runGeneration &+= 1
        isRunning = true
        let generation = runGeneration
        if let usageFileWatcher {
            await usageFileWatcher.start(using: usageRefreshRequestToken(generation: generation))
            guard isRunning, generation == runGeneration else {
                return
            }
        }
        requestUsageRefresh()
        requestQuotaRefresh()
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
        beginUsageRefresh(forceCursorSync: false)
    }

    public func popoverOpened() {
        guard let lastBackgroundQuotaSuccessfulAt else {
            requestQuotaRefresh()
            return
        }
        guard clock.now.timeIntervalSince(lastBackgroundQuotaSuccessfulAt) > Self.popoverQuotaRefreshThreshold else {
            return
        }
        requestQuotaRefresh()
    }

    public func manualRefresh() async {
        let generation = runGeneration
        if let usageTask {
            var forceRequirementIsSatisfiedOrQueued = usageTaskIsForced || forceCursorSyncRequestedWhileInFlight
            if !forceRequirementIsSatisfiedOrQueued {
                forceCursorSyncRequestedWhileInFlight = true
                usageQueuedGeneration = generation
                forceRequirementIsSatisfiedOrQueued = true
            }
            await usageTask.value
            guard generation == runGeneration, isRunning else { return }
            // A manual caller that observed or queued the shared forced cycle has
            // met its usage requirement. The shared cycle may have completed while
            // this caller awaited the normal refresh, so it must not start another.
            if !forceRequirementIsSatisfiedOrQueued {
                beginUsageRefresh(forceCursorSync: true)
            }
        } else {
            beginUsageRefresh(forceCursorSync: true)
        }

        if let quotaTask {
            requestQuotaRefresh()
            await quotaTask.value
            guard generation == runGeneration, isRunning else { return }
        } else {
            requestQuotaRefresh()
        }
    }

    public func refreshQuota(afterUserAuthenticationFor provider: ProviderID) async -> Bool {
        guard isRunning, provider == .claude || provider == .codex else { return false }
        return await withCheckedContinuation { continuation in
            let waiter = UserQuotaWaiter(generation: runGeneration, continuation: continuation)
            if case .userInitiated(let activeProvider) = activeQuotaIntent,
               activeProvider == provider,
               completingUserQuotaWaiters[provider]?.contains(where: { $0.generation == runGeneration }) == true
            {
                completingUserQuotaWaiters[provider, default: []].append(waiter)
                return
            }
            let hadWaiter = userQuotaWaiters[provider]?.contains { $0.generation == runGeneration } ?? false
            userQuotaWaiters[provider, default: []].append(waiter)
            let intent = QuotaRefreshIntent.userInitiated(provider: provider)
            switch activeQuotaIntent {
            case nil:
                beginQuotaRefresh(intent: intent)
            case .userInitiated(let activeProvider) where activeProvider == provider && hadWaiter:
                break
            default:
                queuedUserInitiatedProviders.insert(provider)
            }
        }
    }

    /// Stops timers and invalidates the installed watcher receiver before a later restart.
    public func stop() async {
        runGeneration &+= 1
        isRunning = false
        usageTask?.cancel()
        quotaTask?.cancel()
        usageSafetyTask?.cancel()
        quotaSafetyTask?.cancel()
        usageSafetyTask = nil
        quotaSafetyTask = nil
        usageRefreshRequestedWhileInFlight = false
        forceCursorSyncRequestedWhileInFlight = false
        usageQueuedGeneration = nil
        queuedBackgroundQuotaRefresh = false
        queuedUserInitiatedProviders.removeAll()
        resumeAllUserQuotaWaiters(with: false)
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
                do {
                    try await clock.sleep(for: Self.safetyInterval)
                } catch is CancellationError {
                    break
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                await self?.requestQuotaRefresh(generation: generation)
            }
        }
    }

    private func usageRefreshRequestToken(generation: UInt64) -> UsageRefreshRequestToken {
        UsageRefreshRequestToken { [weak self] in
            await self?.requestUsageRefresh(generation: generation)
        }
    }

    private func requestQuotaRefresh(generation: UInt64? = nil) {
        if let generation, (!isRunning || generation != runGeneration) { return }
        guard quotaTask == nil else {
            queuedBackgroundQuotaRefresh = true
            return
        }
        beginQuotaRefresh(intent: .backgroundAll)
    }

    private func beginUsageRefresh(forceCursorSync: Bool) {
        guard usageTask == nil else { return }
        usageTaskIsForced = forceCursorSync
        let repository = usageRepository
        let generation = runGeneration
        usageTask = Task { [weak self, repository] in
            let result = Result { try repository.refresh(forceCursorSync: forceCursorSync) }
            await self?.finishUsageRefresh(result, applyResult: !Task.isCancelled, generation: generation)
        }
    }

    private func beginQuotaRefresh(intent: QuotaRefreshIntent) {
        guard quotaTask == nil else { return }
        activeQuotaIntent = intent
        let repository = quotaRepository
        let generation = runGeneration
        quotaTask = Task { [weak self, repository, intent] in
            let result = Result { try repository.refresh(intent: intent) }
            await self?.finishQuotaRefresh(result, intent: intent, applyResult: !Task.isCancelled, generation: generation)
        }
    }

    private func finishUsageRefresh(
        _ result: Result<UsageRefreshResult, Error>,
        applyResult: Bool,
        generation: UInt64
    ) async {
        defer {
            usageTask = nil
            usageTaskIsForced = false
            let requested = usageRefreshRequestedWhileInFlight
            let forceCursorSync = forceCursorSyncRequestedWhileInFlight
            let queuedGeneration = usageQueuedGeneration
            usageRefreshRequestedWhileInFlight = false
            forceCursorSyncRequestedWhileInFlight = false
            usageQueuedGeneration = nil
            if isRunning, queuedGeneration == runGeneration, (requested || forceCursorSync) {
                beginUsageRefresh(forceCursorSync: forceCursorSync)
            }
        }
        guard applyResult, generation == runGeneration else { return }
        switch result {
        case .success(let refresh):
            for (provider, usage) in refresh.snapshots {
                guard generation == runGeneration, applyResult else { return }
                await store.applyUsage(usage, for: provider, at: clock.now)
            }
            for (provider, error) in refresh.errors {
                guard generation == runGeneration, applyResult else { return }
                await store.markUsageFailure(for: provider, status: status(for: error), at: clock.now)
            }
        case .failure(let error):
            let status = DataStatus.error(message: String(describing: error), lastSuccessfulAt: nil)
            for provider in ProviderID.allCases {
                guard generation == runGeneration, applyResult else { return }
                await store.markUsageFailure(for: provider, status: status, at: clock.now)
            }
        }
    }

    private func finishQuotaRefresh(
        _ result: Result<QuotaRefreshResult, Error>,
        intent: QuotaRefreshIntent,
        applyResult: Bool,
        generation: UInt64
    ) async {
        var verificationSucceeded = false
        let verifiedProvider: ProviderID?
        if case .userInitiated(let provider) = intent {
            verifiedProvider = provider
            moveUserQuotaWaiters(for: provider, generation: generation)
        } else {
            verifiedProvider = nil
        }
        defer {
            if let verifiedProvider {
                resumeCompletingUserQuotaWaiters(
                    for: verifiedProvider,
                    generation: generation,
                    with: applyResult && generation == runGeneration ? verificationSucceeded : false
                )
            }
            quotaTask = nil
            activeQuotaIntent = nil
            drainQueuedQuotaRefreshes()
        }

        guard applyResult, generation == runGeneration else { return }
        switch result {
        case .success(let refresh):
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
                await store.markQuotaFailure(for: provider, status: status(for: error), at: refreshedAt)
            }
            if case .userInitiated(let provider) = intent {
                verificationSucceeded = refresh.snapshots[provider] != nil
            }
        case .failure(let error):
            if let bridgeFailure = error as? BridgeFailure,
               case .bridgeFailed(let bridgeErrors) = bridgeFailure
            {
                let requestedProviders: Set<ProviderID>
                if case .userInitiated(let provider) = intent {
                    requestedProviders = [provider]
                } else {
                    requestedProviders = Set(ProviderID.allCases)
                }
                let matchingErrors = bridgeErrors.filter {
                    guard let provider = $0.providerID else { return false }
                    return requestedProviders.contains(provider)
                }
                if !matchingErrors.isEmpty {
                    for error in matchingErrors {
                        guard let provider = error.providerID, generation == runGeneration, applyResult else { return }
                        await store.markQuotaFailure(for: provider, status: status(for: error), at: clock.now)
                    }
                    break
                }
            }
            let status = DataStatus.error(message: String(describing: error), lastSuccessfulAt: nil)
            let providers: [ProviderID]
            if case .userInitiated(let provider) = intent {
                providers = [provider]
            } else {
                providers = ProviderID.allCases
            }
            for provider in providers {
                guard generation == runGeneration, applyResult else { return }
                await store.markQuotaFailure(for: provider, status: status, at: clock.now)
            }
        }
    }

    private func drainQueuedQuotaRefreshes() {
        guard isRunning else { return }
        if let provider = ProviderID.allCases.first(where: { queuedUserInitiatedProviders.contains($0) }) {
            queuedUserInitiatedProviders.remove(provider)
            beginQuotaRefresh(intent: .userInitiated(provider: provider))
            return
        }
        if queuedBackgroundQuotaRefresh {
            queuedBackgroundQuotaRefresh = false
            beginQuotaRefresh(intent: .backgroundAll)
        }
    }

    private func resumeAllUserQuotaWaiters(with result: Bool) {
        let waiters = userQuotaWaiters.values.flatMap { $0 } + completingUserQuotaWaiters.values.flatMap { $0 }
        userQuotaWaiters.removeAll()
        completingUserQuotaWaiters.removeAll()
        waiters.forEach { $0.continuation.resume(returning: result) }
    }

    private func moveUserQuotaWaiters(for provider: ProviderID, generation: UInt64) {
        let waiters = userQuotaWaiters[provider] ?? []
        let captured = waiters.filter { $0.generation == generation }
        let remaining = waiters.filter { $0.generation != generation }
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
}
