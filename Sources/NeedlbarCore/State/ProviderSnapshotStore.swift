import Foundation

public actor ProviderSnapshotStore {
    private struct StreamState<Value: Sendable>: Sendable {
        var value: Value?
        var lastSuccessfulAt: Date?
        var latestFailure: DataStatus?
    }

    private struct State: Sendable {
        var usage = StreamState<UsageSnapshot>()
        var quota = StreamState<QuotaSnapshot>()
        var updatedAt: Date
    }

    private var states: [ProviderID: State] = [:]
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public func applyUsage(_ usage: UsageSnapshot, for provider: ProviderID, at date: Date? = nil) {
        let timestamp = date ?? now()
        var state = state(for: provider, timestamp: timestamp)
        state.usage.value = usage
        state.usage.lastSuccessfulAt = timestamp
        state.usage.latestFailure = nil
        state.updatedAt = timestamp
        states[provider] = state
    }

    public func applyQuota(_ quota: QuotaSnapshot, for provider: ProviderID, at date: Date? = nil) {
        let timestamp = date ?? now()
        var state = state(for: provider, timestamp: timestamp)
        state.quota.value = quota
        state.quota.lastSuccessfulAt = timestamp
        state.quota.latestFailure = nil
        state.updatedAt = timestamp
        states[provider] = state
    }

    public func markUsageFailure(for provider: ProviderID, status: DataStatus, at date: Date? = nil) {
        let timestamp = date ?? now()
        var state = state(for: provider, timestamp: timestamp)
        state.usage.latestFailure = normalizedFailure(status, lastSuccessfulAt: state.usage.lastSuccessfulAt)
        state.updatedAt = timestamp
        states[provider] = state
    }

    public func markQuotaFailure(for provider: ProviderID, status: DataStatus, at date: Date? = nil) {
        let timestamp = date ?? now()
        var state = state(for: provider, timestamp: timestamp)
        state.quota.latestFailure = normalizedFailure(status, lastSuccessfulAt: state.quota.lastSuccessfulAt)
        state.updatedAt = timestamp
        states[provider] = state
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

    private func state(for provider: ProviderID, timestamp: Date) -> State {
        states[provider] ?? State(updatedAt: timestamp)
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
