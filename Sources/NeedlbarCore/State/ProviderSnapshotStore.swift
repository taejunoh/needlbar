import Foundation

public struct QuotaAlertSample: Sendable, Equatable {
    public let provider: ProviderID
    public let quota: QuotaSnapshot?
    public let status: DataStatus
    public let lastSuccessfulAt: Date?
    public let revision: UInt64

    public init(
        provider: ProviderID,
        quota: QuotaSnapshot?,
        status: DataStatus,
        lastSuccessfulAt: Date?,
        revision: UInt64
    ) {
        self.provider = provider
        self.quota = quota
        self.status = status
        self.lastSuccessfulAt = lastSuccessfulAt
        self.revision = revision
    }
}

public actor ProviderSnapshotStore {
    private struct StreamState<Value: Sendable>: Sendable {
        var value: Value?
        var lastSuccessfulAt: Date?
        var latestFailure: DataStatus?
        var usageDayProvenance: WidgetUsageDayProvenance?
    }

    private struct State: Sendable {
        var usage = StreamState<UsageSnapshot>()
        var quota = StreamState<QuotaSnapshot>()
        var quotaRevision: UInt64 = 0
        var everUpdated = false
        var updatedAt: Date
    }

    private var states: [ProviderID: State] = [:]
    private let now: @Sendable () -> Date
    private var updateContinuations: [UUID: AsyncStream<[ProviderSnapshot]>.Continuation] = [:]
    private var quotaAlertContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public func applyUsage(
        _ usage: UsageSnapshot,
        for provider: ProviderID,
        at date: Date? = nil,
        widgetDayProvenance: WidgetUsageDayProvenance? = nil
    ) {
        let timestamp = date ?? now()
        var state = state(for: provider, timestamp: timestamp)
        state.usage.value = usage
        state.usage.lastSuccessfulAt = timestamp
        state.usage.latestFailure = nil
        state.usage.usageDayProvenance = widgetDayProvenance
        state.everUpdated = true
        state.updatedAt = timestamp
        states[provider] = state
        publishUpdates()
    }

    public func applyQuota(_ quota: QuotaSnapshot, for provider: ProviderID, at date: Date? = nil) {
        let timestamp = date ?? now()
        var state = state(for: provider, timestamp: timestamp)
        state.quota.value = quota
        state.quota.lastSuccessfulAt = timestamp
        state.quota.latestFailure = nil
        state.quotaRevision &+= 1
        state.everUpdated = true
        state.updatedAt = timestamp
        states[provider] = state
        publishUpdates()
        publishQuotaAlertChange()
    }

    public func markUsageFailure(for provider: ProviderID, status: DataStatus, at date: Date? = nil) {
        let timestamp = date ?? now()
        var state = state(for: provider, timestamp: timestamp)
        state.usage.latestFailure = normalizedFailure(status, lastSuccessfulAt: state.usage.lastSuccessfulAt)
        state.everUpdated = true
        state.updatedAt = timestamp
        states[provider] = state
        publishUpdates()
    }

    public func markQuotaFailure(for provider: ProviderID, status: DataStatus, at date: Date? = nil) {
        let timestamp = date ?? now()
        var state = state(for: provider, timestamp: timestamp)
        state.quota.latestFailure = normalizedFailure(status, lastSuccessfulAt: state.quota.lastSuccessfulAt)
        state.everUpdated = true
        state.updatedAt = timestamp
        states[provider] = state
        publishUpdates()
    }

    public func snapshot(for provider: ProviderID) -> ProviderSnapshot {
        let state = states[provider] ?? State(updatedAt: now())
        return ProviderSnapshot(
            provider: provider,
            usage: state.usage.value,
            quota: state.quota.value,
            usageStatus: status(for: state.usage),
            quotaStatus: status(for: state.quota),
            updatedAt: state.updatedAt
        )
    }

    public func snapshots() -> [ProviderSnapshot] {
        ProviderID.allCases.map { snapshot(for: $0) }
    }

    public func captureForExport(exportedAt: Date) -> ExportCapture {
        ExportCapture(
            exportedAt: exportedAt,
            providers: ProviderID.allCases.map { provider in
                let state = states[provider] ?? State(updatedAt: exportedAt)
                return ProviderExportState(
                    provider: provider,
                    usage: state.usage.value,
                    quota: state.quota.value,
                    usageStatus: status(for: state.usage),
                    quotaStatus: status(for: state.quota),
                    usageLastSuccessfulAt: state.usage.lastSuccessfulAt,
                    quotaLastSuccessfulAt: state.quota.lastSuccessfulAt,
                    everUpdated: state.everUpdated,
                    updatedAt: state.everUpdated ? state.updatedAt : nil
                )
            }
        )
    }

    public func captureForWidget(exportedAt: Date) -> WidgetStoreCapture {
        WidgetStoreCapture(exportedAt: exportedAt, providers: ProviderID.allCases.map { provider in
            let state = states[provider] ?? State(updatedAt: exportedAt)
            return WidgetProviderCapture(
                provider: provider,
                usage: state.usage.value,
                quota: state.quota.value,
                usageStatus: status(for: state.usage),
                quotaStatus: status(for: state.quota),
                usageLastSuccessfulAt: state.usage.lastSuccessfulAt,
                quotaLastSuccessfulAt: state.quota.lastSuccessfulAt,
                usageDayProvenance: state.usage.usageDayProvenance
            )
        })
    }

    public func quotaAlertCapture() -> [QuotaAlertSample] {
        ProviderID.allCases.map { currentQuotaAlertSample(for: $0) }
    }

    public func currentQuotaAlertSample(for provider: ProviderID) -> QuotaAlertSample {
        let state = states[provider] ?? State(updatedAt: now())
        return QuotaAlertSample(
            provider: provider,
            quota: state.quota.value,
            status: status(for: state.quota),
            lastSuccessfulAt: state.quota.lastSuccessfulAt,
            revision: state.quotaRevision
        )
    }

    public func quotaAlertChangeSignals() -> AsyncStream<Void> {
        let identifier = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            quotaAlertContinuations[identifier] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeQuotaAlertContinuation(identifier) }
            }
        }
    }

    public func updates() -> AsyncStream<[ProviderSnapshot]> {
        let identifier = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            updateContinuations[identifier] = continuation
            continuation.yield(snapshots())
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeUpdateContinuation(identifier)
                }
            }
        }
    }

    private func state(for provider: ProviderID, timestamp: Date) -> State {
        states[provider] ?? State(updatedAt: timestamp)
    }

    private func publishUpdates() {
        let snapshots = snapshots()
        for continuation in updateContinuations.values {
            continuation.yield(snapshots)
        }
    }

    private func publishQuotaAlertChange() {
        for continuation in quotaAlertContinuations.values {
            continuation.yield()
        }
    }

    private func removeUpdateContinuation(_ identifier: UUID) {
        updateContinuations.removeValue(forKey: identifier)
    }

    private func removeQuotaAlertContinuation(_ identifier: UUID) {
        quotaAlertContinuations.removeValue(forKey: identifier)
    }

    private func normalizedFailure(_ status: DataStatus, lastSuccessfulAt: Date?) -> DataStatus {
        switch status {
        case .fresh:
            return .error(message: "Refresh failed.", lastSuccessfulAt: lastSuccessfulAt)
        case .stale:
            if let lastSuccessfulAt {
                return .stale(lastSuccessfulAt: lastSuccessfulAt)
            }
            return .unavailable
        case .unavailable:
            return .unavailable
        case .requiresAuthentication:
            return .requiresAuthentication
        case .error(let message, _):
            return .error(message: message, lastSuccessfulAt: lastSuccessfulAt)
        }
    }

    private func status<Value: Sendable>(for stream: StreamState<Value>) -> DataStatus {
        guard let failure = stream.latestFailure else {
            return stream.value == nil ? .unavailable : .fresh
        }

        switch failure {
        case .requiresAuthentication where stream.value == nil:
            return .requiresAuthentication
        case .unavailable where stream.value == nil:
            return .unavailable
        case .stale(let lastSuccessfulAt):
            return .stale(lastSuccessfulAt: lastSuccessfulAt)
        case .requiresAuthentication:
            return .error(
                message: "Authentication is required.",
                lastSuccessfulAt: stream.lastSuccessfulAt
            )
        case .unavailable:
            return .error(message: "Data is unavailable.", lastSuccessfulAt: stream.lastSuccessfulAt)
        case .error(let message, _):
            return .error(message: message, lastSuccessfulAt: stream.lastSuccessfulAt)
        case .fresh:
            return stream.value == nil ? .unavailable : .fresh
        }
    }
}

extension ProviderSnapshotStore: ExportCaptureProviding {}
