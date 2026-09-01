import Foundation

public actor AnalyticsSnapshotStore {
    private var currentState: AnalyticsRefreshState = .idle
    private var lastGood: AnalyticsSnapshot?
    private var inFlight: Task<AnalyticsSnapshot, Error>?

    public init() {}

    public var state: AnalyticsRefreshState { currentState }

    public func refresh(using repository: AnalyticsRepository) async -> AnalyticsSnapshot? {
        if let inFlight {
            return try? await inFlight.value
        }
        currentState = .loading
        let task = Task.detached(priority: nil) { try await repository.refreshAnalytics() }
        inFlight = task
        do {
            let snapshot = try await task.value
            lastGood = snapshot
            currentState = .fresh(snapshot)
            inFlight = nil
            return snapshot
        } catch {
            inFlight = nil
            if let lastGood { currentState = .stale(lastGood) } else { currentState = .unavailable }
            return nil
        }
    }
}
