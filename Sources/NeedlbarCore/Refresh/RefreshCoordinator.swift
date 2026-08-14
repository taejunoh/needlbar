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
    private let forceCursorSync: (@Sendable () async -> Void)?

    private var usageTask: Task<Void, Never>?
    private var quotaTask: Task<Void, Never>?
    private var usageSafetyTask: Task<Void, Never>?
    private var quotaSafetyTask: Task<Void, Never>?
    private var lastQuotaSuccessfulAt: Date?
    private var isRunning = false
    private var usageRefreshRequestedWhileInFlight = false
    private var forceCursorSyncRequestedWhileInFlight = false
    private var quotaRefreshRequestedWhileInFlight = false

    public init(
        usageRepository: any UsageRepository,
        quotaRepository: any QuotaRepository,
        store: ProviderSnapshotStore,
        clock: any ClockLike = SystemClock(),
        lastQuotaSuccessfulAt: Date? = nil,
        forceCursorSync: (@Sendable () async -> Void)? = nil
    ) {
        self.usageRepository = usageRepository
        self.quotaRepository = quotaRepository
        self.store = store
        self.clock = clock
        self.lastQuotaSuccessfulAt = lastQuotaSuccessfulAt
        self.forceCursorSync = forceCursorSync
    }

    deinit {
        usageTask?.cancel()
        quotaTask?.cancel()
        usageSafetyTask?.cancel()
        quotaSafetyTask?.cancel()
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        requestUsageRefresh()
        requestQuotaRefresh()
        scheduleSafetyRefreshes()
    }

    public func requestUsageRefresh() {
        guard usageTask == nil else {
            usageRefreshRequestedWhileInFlight = true
            return
        }
        beginUsageRefresh(forceCursorSync: false)
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
        if let usageTask {
            forceCursorSyncRequestedWhileInFlight = true
            await usageTask.value
            if !isRunning {
                beginUsageRefresh(forceCursorSync: true)
            }
        } else {
            beginUsageRefresh(forceCursorSync: true)
        }

        if let quotaTask {
            await quotaTask.value
        } else {
            beginQuotaRefresh()
        }
    }

    public func stop() {
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
    }

    private func scheduleSafetyRefreshes() {
        let clock = clock
        usageSafetyTask = Task { [weak self, clock] in
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: Self.safetyInterval)
                } catch is CancellationError {
                    break
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                await self?.requestUsageRefresh()
            }
        }

        quotaSafetyTask = Task { [weak self, clock] in
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: Self.safetyInterval)
                } catch is CancellationError {
                    break
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                await self?.requestQuotaRefresh()
            }
        }
    }

    private func requestQuotaRefresh() {
        guard quotaTask == nil else {
            quotaRefreshRequestedWhileInFlight = true
            return
        }
        beginQuotaRefresh()
    }

    private func beginUsageRefresh(forceCursorSync: Bool) {
        guard usageTask == nil else { return }
        let repository = usageRepository
        let forceSync = self.forceCursorSync
        usageTask = Task { [weak self, repository, forceSync] in
            if forceCursorSync {
                await forceSync?()
            }
            let result = Result { try repository.refresh() }
            await self?.finishUsageRefresh(result, applyResult: !Task.isCancelled)
        }
    }

    private func beginQuotaRefresh() {
        guard quotaTask == nil else { return }
        let repository = quotaRepository
        quotaTask = Task { [weak self, repository] in
            guard !Task.isCancelled else { return }
            let result = Result { try repository.refresh() }
            await self?.finishQuotaRefresh(result, applyResult: !Task.isCancelled)
        }
    }

    private func finishUsageRefresh(
        _ result: Result<UsageRefreshResult, Error>,
        applyResult: Bool
    ) async {
        defer {
            usageTask = nil
            let requested = usageRefreshRequestedWhileInFlight
            let forceCursorSync = forceCursorSyncRequestedWhileInFlight
            usageRefreshRequestedWhileInFlight = false
            forceCursorSyncRequestedWhileInFlight = false
            if isRunning && (requested || forceCursorSync) {
                beginUsageRefresh(forceCursorSync: forceCursorSync)
            }
        }
        guard applyResult else { return }
        switch result {
        case .success(let refresh):
            for (provider, usage) in refresh.snapshots {
                await store.applyUsage(usage, for: provider, at: clock.now)
            }
            for (provider, error) in refresh.errors {
                await store.markUsageFailure(for: provider, status: status(for: error), at: clock.now)
            }
        case .failure(let error):
            let status = DataStatus.error(message: String(describing: error), lastSuccessfulAt: nil)
            for provider in ProviderID.allCases {
                await store.markUsageFailure(for: provider, status: status, at: clock.now)
            }
        }
    }

    private func finishQuotaRefresh(
        _ result: Result<QuotaRefreshResult, Error>,
        applyResult: Bool
    ) async {
        defer {
            quotaTask = nil
            let requested = quotaRefreshRequestedWhileInFlight
            quotaRefreshRequestedWhileInFlight = false
            if isRunning && requested {
                beginQuotaRefresh()
            }
        }
        guard applyResult else { return }
        switch result {
        case .success(let refresh):
            let refreshedAt = clock.now
            lastQuotaSuccessfulAt = refreshedAt
            for (provider, quota) in refresh.snapshots {
                await store.applyQuota(quota, for: provider, at: refreshedAt)
            }
            for (provider, error) in refresh.errors {
                await store.markQuotaFailure(for: provider, status: status(for: error), at: refreshedAt)
            }
        case .failure(let error):
            let status = DataStatus.error(message: String(describing: error), lastSuccessfulAt: nil)
            for provider in ProviderID.allCases {
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
