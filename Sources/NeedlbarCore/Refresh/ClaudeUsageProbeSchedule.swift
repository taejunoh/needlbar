import Foundation

/// When a `claude -p /usage` run may start. A value with no clock, process or
/// store, owned by `RefreshCoordinator`.
struct ClaudeUsageProbeSchedule: Sendable, Equatable {
    enum Action: Equatable, Sendable {
        case start
        /// Refused or joined. A refused startup or usage change stays in
        /// `pendingTrigger`; a manual request joins the run in flight.
        case none
    }

    static let minimumInterval: TimeInterval = 5 * 60
    /// Keeps readings current during quiet periods (user decision, 2026-11-03).
    static let periodicInterval: TimeInterval = 15 * 60
    static let backoffSteps: [TimeInterval] = [5 * 60, 10 * 60, 20 * 60, 30 * 60]

    private(set) var lastStartedAt: Date?
    private(set) var consecutiveAutomaticFailures = 0
    private(set) var backoffUntil: Date?
    private(set) var pendingTrigger: QuotaRefreshTrigger?
    private var retryPending = false

    mutating func request(_ trigger: QuotaRefreshTrigger, now: Date, inFlight: Bool) -> Action {
        if trigger == .manual { return inFlight ? .none : .start }
        guard !inFlight, automaticRunIsAllowed(now: now) else {
            pendingTrigger = pendingTrigger ?? trigger
            return .none
        }
        return .start
    }

    /// The automatic run that is due now, if any. A pending request comes
    /// first, then a passed reset, then a retry after backoff, then the periodic run.
    func dueTrigger(resetTimes: [Date], now: Date, inFlight: Bool) -> QuotaRefreshTrigger? {
        guard !inFlight, automaticRunIsAllowed(now: now) else { return nil }
        if let pendingTrigger { return pendingTrigger }
        let resetPassed = resetTimes.contains { reset in
            reset <= now && (lastStartedAt.map { $0 < reset } ?? true)
        }
        if resetPassed { return .windowReset }
        if retryPending { return .backoffRetry }
        return periodicRunIsDue(now: now) ? .periodic : nil
    }

    mutating func recordStart(at date: Date) {
        lastStartedAt = date
        pendingTrigger = nil
        retryPending = false
    }

    mutating func recordSuccess() {
        consecutiveAutomaticFailures = 0
        backoffUntil = nil
        retryPending = false
    }

    /// A manual failure neither counts nor clears the automatic backoff.
    mutating func recordFailure(trigger: QuotaRefreshTrigger, at date: Date, retriesWhenBackoffEnds: Bool) {
        retryPending = retriesWhenBackoffEnds
        guard trigger != .manual else { return }
        let step = Self.backoffSteps[min(consecutiveAutomaticFailures, Self.backoffSteps.count - 1)]
        consecutiveAutomaticFailures += 1
        backoffUntil = date.addingTimeInterval(step)
    }

    /// A negative age means the clock was set back, so it never makes this due.
    private func periodicRunIsDue(now: Date) -> Bool {
        guard let lastStartedAt else { return false }
        return now.timeIntervalSince(lastStartedAt) >= Self.periodicInterval
    }

    private func automaticRunIsAllowed(now: Date) -> Bool {
        if let lastStartedAt {
            let age = now.timeIntervalSince(lastStartedAt)
            // A negative age means the clock was set back, not that a run just started.
            if age >= 0, age < Self.minimumInterval { return false }
        }
        if let backoffUntil {
            let remaining = backoffUntil.timeIntervalSince(now)
            if remaining > 0, remaining <= Self.backoffSteps[Self.backoffSteps.count - 1] { return false }
        }
        return true
    }
}
