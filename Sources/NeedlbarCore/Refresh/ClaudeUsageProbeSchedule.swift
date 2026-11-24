import Foundation

/// When a `claude -p /usage` run may start. A value with no clock, process or
/// store, owned by `RefreshCoordinator`.
struct ClaudeUsageProbeSchedule: Sendable, Equatable {
    enum Action: Equatable, Sendable {
        case start
        /// Refused or joined. A refused startup request stays in
        /// `pendingTrigger`; a manual request joins the run in flight.
        case none
    }

    static let minimumInterval: TimeInterval = 5 * 60
    /// Keeps readings current, during use and in quiet periods alike (user
    /// decisions, 2026-11-03 and 2026-11-12).
    static let periodicInterval: TimeInterval = 15 * 60
    static let backoffSteps: [TimeInterval] = [5 * 60, 10 * 60, 20 * 60, 30 * 60]

    /// Off by default (spec 2026-11-16): while off, only a manual request starts a run.
    private(set) var automaticRunsEnabled: Bool
    private(set) var lastStartedAt: Date?
    private(set) var consecutiveAutomaticFailures = 0
    private(set) var backoffUntil: Date?
    private(set) var pendingTrigger: QuotaRefreshTrigger?
    private var retryPending = false

    init(automaticRunsEnabled: Bool = false) {
        self.automaticRunsEnabled = automaticRunsEnabled
    }

    /// Turning off drops every queued or delayed automatic run and keeps
    /// `lastStartedAt`, so the five-minute floor still holds after turning on again.
    /// A call that does not change the value does nothing.
    mutating func setAutomaticRunsEnabled(_ enabled: Bool) {
        guard enabled != automaticRunsEnabled else { return }
        automaticRunsEnabled = enabled
        guard !enabled else { return }
        pendingTrigger = nil
        retryPending = false
        backoffUntil = nil
        consecutiveAutomaticFailures = 0
    }

    mutating func request(_ trigger: QuotaRefreshTrigger, now: Date, inFlight: Bool) -> Action {
        if trigger == .manual { return inFlight ? .none : .start }
        // While off a refused request leaves nothing pending.
        guard automaticRunsEnabled else { return .none }
        guard !inFlight, automaticRunIsAllowed(now: now) else {
            // A refused resume is queued only when no run has started yet. Otherwise
            // the periodic run follows 15 minutes after the last start, so turning on
            // right after Check now starts no second run inside the floor.
            if trigger != .automaticResumed || lastStartedAt == nil {
                pendingTrigger = pendingTrigger ?? trigger
            }
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
        // `retryPending` stays: only an automatic result decides it, so a
        // manual run that starts or fails cannot cancel an automatic retry.
    }

    mutating func recordSuccess() {
        consecutiveAutomaticFailures = 0
        backoffUntil = nil
        retryPending = false
    }

    /// A manual failure changes nothing: it neither counts nor clears the
    /// automatic backoff, and it neither creates nor cancels an automatic retry.
    /// While automatic runs are off no failure does, so no backoff or retry can
    /// exist while off, even for an automatic run that was in flight at turn-off.
    mutating func recordFailure(trigger: QuotaRefreshTrigger, at date: Date, retriesWhenBackoffEnds: Bool) {
        guard trigger != .manual, automaticRunsEnabled else { return }
        retryPending = retriesWhenBackoffEnds
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
        guard automaticRunsEnabled else { return false }
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
