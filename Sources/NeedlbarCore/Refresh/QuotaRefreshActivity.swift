import Foundation

public enum QuotaAttemptPhase: String, Sendable { case started, completed, invalidated }
public enum QuotaAttemptOutcome: String, Sendable { case success, failure, unavailable }
public enum QuotaObservationSource: String, Sendable { case direct, statusLine, unavailable }

public struct QuotaAttemptEvent: Sendable, Equatable {
    public let id: UUID
    public let generation: UInt64
    public let trigger: QuotaRefreshTrigger
    public let phase: QuotaAttemptPhase
    public let startedAt: Date
    public let completedAt: Date?
    public let outcome: QuotaAttemptOutcome?
    public let directLastSuccessfulAt: Date?
    public let failureAttemptAt: Date?
    public let fiveHourSource: QuotaObservationSource
    public let sevenDaySource: QuotaObservationSource
    public let fableSource: QuotaObservationSource
    public let fiveHourReceiptAt: Date?
    public let sevenDayReceiptAt: Date?

    public init(
        id: UUID, generation: UInt64, trigger: QuotaRefreshTrigger, phase: QuotaAttemptPhase,
        startedAt: Date, completedAt: Date?, outcome: QuotaAttemptOutcome?,
        directLastSuccessfulAt: Date?, failureAttemptAt: Date?,
        fiveHourSource: QuotaObservationSource, sevenDaySource: QuotaObservationSource,
        fableSource: QuotaObservationSource, fiveHourReceiptAt: Date?, sevenDayReceiptAt: Date?
    ) {
        self.id = id
        self.generation = generation
        self.trigger = trigger
        self.phase = phase
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.outcome = outcome
        self.directLastSuccessfulAt = directLastSuccessfulAt
        self.failureAttemptAt = failureAttemptAt
        self.fiveHourSource = fiveHourSource
        self.sevenDaySource = sevenDaySource
        self.fableSource = fableSource
        self.fiveHourReceiptAt = fiveHourReceiptAt
        self.sevenDayReceiptAt = sevenDayReceiptAt
    }
}

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

/// Serializes the worker's permission to enter synchronous FFI with lifecycle
/// invalidation. The coordinator retains the physical slot until the call returns.
final class QuotaAttemptLedger: @unchecked Sendable {
    private let lock = NSLock()
    private let observer: (@Sendable (QuotaAttemptEvent) -> Void)?
    private var generation: UInt64 = 0
    private var reservation: (id: UUID, generation: UInt64, trigger: QuotaRefreshTrigger)?
    private var active: QuotaAttemptEvent?
    private var latest: QuotaAttemptEvent?

    init(observer: (@Sendable (QuotaAttemptEvent) -> Void)?) { self.observer = observer }

    func advance(to generation: UInt64) {
        lock.withLock {
            self.generation = generation
            reservation = nil
            if let active {
                let event = activity(id: active.id, generation: active.generation, trigger: active.trigger,
                                     phase: .invalidated, startedAt: active.startedAt, previous: active)
                self.active = nil
                latest = event
                observer?(event)
            }
        }
    }

    func reserve(id: UUID, generation: UInt64, trigger: QuotaRefreshTrigger) {
        lock.withLock { reservation = (id, generation, trigger) }
    }

    func claim(id: UUID, generation: UInt64, at startedAt: Date,
               backgroundClock: BackgroundQuotaAttemptClock?) -> QuotaAttemptEvent? {
        lock.withLock {
            guard self.generation == generation, let reservation,
                  reservation.id == id, reservation.generation == generation else { return nil }
            backgroundClock?.record(startedAt)
            let event = activity(id: id, generation: generation, trigger: reservation.trigger,
                                 phase: .started, startedAt: startedAt, previous: latest)
            active = event
            latest = event
            observer?(event)
            return event
        }
    }

    func complete(_ event: QuotaAttemptEvent) {
        lock.withLock {
            guard generation == event.generation, active?.id == event.id else { return }
            active = nil
            reservation = nil
            latest = event
            observer?(event)
        }
    }

    private func activity(id: UUID, generation: UInt64, trigger: QuotaRefreshTrigger,
                          phase: QuotaAttemptPhase, startedAt: Date, previous: QuotaAttemptEvent?) -> QuotaAttemptEvent {
        QuotaAttemptEvent(
            id: id, generation: generation, trigger: trigger, phase: phase, startedAt: startedAt,
            completedAt: nil, outcome: nil, directLastSuccessfulAt: previous?.directLastSuccessfulAt,
            failureAttemptAt: previous?.failureAttemptAt,
            fiveHourSource: previous?.fiveHourSource ?? .unavailable,
            sevenDaySource: previous?.sevenDaySource ?? .unavailable,
            fableSource: previous?.fableSource ?? .unavailable,
            fiveHourReceiptAt: previous?.fiveHourReceiptAt, sevenDayReceiptAt: previous?.sevenDayReceiptAt)
    }
}
