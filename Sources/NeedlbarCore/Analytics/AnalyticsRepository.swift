import Foundation

public protocol AnalyticsRepository: Sendable {
    func refreshAnalytics() async throws -> AnalyticsSnapshot
}

public struct RustAnalyticsRepository: AnalyticsRepository, Sendable {
    private let bridge: RustBridge
    public init(bridge: RustBridge = RustBridge()) { self.bridge = bridge }

    public func refreshAnalytics() async throws -> AnalyticsSnapshot {
        let bridge = self.bridge
        return try await Task.detached(priority: nil) {
            try bridge.analyticsEnvelope()
        }.value
    }
}
