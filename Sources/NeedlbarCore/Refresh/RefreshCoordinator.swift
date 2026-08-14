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

    private var usageTask: Task<Void, Never>?
    private var quotaTask: Task<Void, Never>?
    private var usageSafetyTask: Task<Void, Never>?
    private var quotaSafetyTask: Task<Void, Never>?
    private var lastQuotaSuccessfulAt: Date?
    private var isRunning = false
    private var usageRefreshRequestedWhileInFlight = false
    private var forceCursorSyncRequestedWhileInFlight = false
    private var quotaRefreshRequestedWhileInFlight = false
    private var usageQueuedGeneration: UInt64?
    private var quotaQueuedGeneration: UInt64?
    private var usageTaskIsForced = false
    private var runGeneration: UInt64 = 0

    public init(
        usageRepository: any UsageRepository,
        quotaRepository: any QuotaRepository,
        store: ProviderSnapshotStore,
        clock: any ClockLike = SystemClock(),
        lastQuotaSuccessfulAt: Date? = nil
    ) {
        self.usageRepository = usageRepository
        self.quotaRepository = quotaRepository
        self.store = store
        self.clock = clock
        self.lastQuotaSuccessfulAt = lastQuotaSuccessfulAt
    }

    deinit {
        usageTask?.cancel()
        quotaTask?.cancel()
        usageSafetyTask?.cancel()
        quotaSafetyTask?.cancel()
    }

    public func start() {
        guard !isRunning else { return }
        runGeneration &+= 1
        isRunning = true
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

    public func usageRefreshRequestHandler() -> @Sendable () async -> Void {
        let generation = runGeneration
        return { [weak self] in
            await self?.requestUsageRefresh(generation: generation)
        }
    }

    public func popoverOpened() {
        guard let lastQuotaSuccessfulAt else {
            beginQuotaRefresh()
            return
        }
        guard clock.now.timeIntervalSince(lastQuotaSuccessfulAt) > Self.popoverQuotaRefreshThreshold else {
            return
        }
        beginQuotaRefresh()
    }

    public func manualRefresh() async {
        let generation = runGeneration
        if let usageTask {
            let existingTaskIsForced = usageTaskIsForced
            if !existingTaskIsForced {
                forceCursorSyncRequestedWhileInFlight = true
                usageQueuedGeneration = generation
            }
            await usageTask.value
            guard generation == runGeneration, isRunning else { return }
            if !existingTaskIsForced, usageTask == nil {
                beginUsageRefresh(forceCursorSync: true)
            }
        } else {
            beginUsageRefresh(forceCursorSync: true)
        }

        if let quotaTask {
            await quotaTask.value
            guard generation == runGeneration, isRunning else { return }
        } else {
            beginQuotaRefresh()
        }
    }

    public func stop() {
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
        quotaRefreshRequestedWhileInFlight = false
        usageQueuedGeneration = nil
        quotaQueuedGeneration = nil
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

    private func requestQuotaRefresh(generation: UInt64? = nil) {
        if let generation, (!isRunning || generation != runGeneration) { return }
        guard quotaTask == nil else {
            quotaRefreshRequestedWhileInFlight = true
            quotaQueuedGeneration = runGeneration
            return
        }
        beginQuotaRefresh()
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

    private func beginQuotaRefresh() {
        guard quotaTask == nil else { return }
        let repository = quotaRepository
        let generation = runGeneration
        quotaTask = Task { [weak self, repository] in
            let result = Result { try repository.refresh() }
            await self?.finishQuotaRefresh(result, applyResult: !Task.isCancelled, generation: generation)
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
        applyResult: Bool,
        generation: UInt64
    ) async {
        defer {
            quotaTask = nil
            let requested = quotaRefreshRequestedWhileInFlight
            let queuedGeneration = quotaQueuedGeneration
            quotaRefreshRequestedWhileInFlight = false
            quotaQueuedGeneration = nil
            if isRunning, queuedGeneration == runGeneration, requested {
                beginQuotaRefresh()
            }
        }
        guard applyResult, generation == runGeneration else { return }
        switch result {
        case .success(let refresh):
            let refreshedAt = clock.now
            if !refresh.snapshots.isEmpty {
                lastQuotaSuccessfulAt = refreshedAt
            }
            for (provider, quota) in refresh.snapshots {
                guard generation == runGeneration, applyResult else { return }
                await store.applyQuota(quota, for: provider, at: refreshedAt)
            }
            for (provider, error) in refresh.errors {
                guard generation == runGeneration, applyResult else { return }
                await store.markQuotaFailure(for: provider, status: status(for: error), at: refreshedAt)
            }
        case .failure(let error):
            let status = DataStatus.error(message: String(describing: error), lastSuccessfulAt: nil)
            for provider in ProviderID.allCases {
                guard generation == runGeneration, applyResult else { return }
                await store.markQuotaFailure(for: provider, status: status, at: clock.now)
            }
        }
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
