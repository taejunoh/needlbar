import Foundation

public enum QuotaRefreshTrigger: String, Sendable, Equatable {
    case startup, scheduled, wake, connectivity, popover, manual
}

public struct QuotaRecoveryRequestToken: Sendable {
    private let action: @Sendable (QuotaRefreshTrigger) async -> Void

    public init(_ action: @escaping @Sendable (QuotaRefreshTrigger) async -> Void) {
        self.action = action
    }

    public func submit(_ trigger: QuotaRefreshTrigger) async {
        guard trigger == .wake || trigger == .connectivity else { return }
        await action(trigger)
    }
}

final class BackgroundQuotaAttemptClock: @unchecked Sendable {
    private let lock = NSLock()
    private var lastStartedAt: Date?

    func record(_ date: Date) { lock.withLock { lastStartedAt = date } }
    var latest: Date? { lock.withLock { lastStartedAt } }
}
