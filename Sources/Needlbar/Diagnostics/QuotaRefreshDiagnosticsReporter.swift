import Foundation
import NeedlbarCore
import OSLog

final class QuotaRefreshDiagnosticsReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: QuotaAttemptEvent?
    private let sink: @Sendable (QuotaAttemptEvent) -> Void

    init(sink: @escaping @Sendable (QuotaAttemptEvent) -> Void = QuotaRefreshDiagnosticsReporter.productionSink) {
        self.sink = sink
    }

    func record(_ event: QuotaAttemptEvent) {
        let recorded = lock.withLock {
            let recorded: QuotaAttemptEvent
            if event.phase == .started, let previous = latest {
                recorded = QuotaAttemptEvent(
                    id: event.id, generation: event.generation, trigger: event.trigger, phase: event.phase,
                    startedAt: event.startedAt, completedAt: nil, outcome: nil,
                    directLastSuccessfulAt: event.directLastSuccessfulAt ?? previous.directLastSuccessfulAt,
                    failureAttemptAt: event.failureAttemptAt ?? previous.failureAttemptAt,
                    fiveHourSource: event.fiveHourSource == .unavailable ? previous.fiveHourSource : event.fiveHourSource,
                    sevenDaySource: event.sevenDaySource == .unavailable ? previous.sevenDaySource : event.sevenDaySource,
                    fableSource: event.fableSource == .unavailable ? previous.fableSource : event.fableSource,
                    fiveHourReceiptAt: event.fiveHourReceiptAt ?? previous.fiveHourReceiptAt,
                    sevenDayReceiptAt: event.sevenDayReceiptAt ?? previous.sevenDayReceiptAt)
            } else {
                recorded = event
            }
            latest = recorded
            return recorded
        }
        sink(recorded)
    }

    func latestEvent() -> QuotaAttemptEvent? { lock.withLock { latest } }

    private static func productionSink(_ event: QuotaAttemptEvent) {
        func timestamp(_ date: Date?) -> String {
            guard let date, date.timeIntervalSince1970.isFinite else { return "-" }
            return ISO8601DateFormatter().string(from: date)
        }
        let logger = Logger(subsystem: "com.taejunoh.needlbar", category: "QuotaRefreshDiagnostic")
        let fields = "trigger=\(event.trigger.rawValue) phase=\(event.phase.rawValue) outcome=\(event.outcome?.rawValue ?? "-")"
            + " start=\(timestamp(event.startedAt)) complete=\(timestamp(event.completedAt))"
            + " directSuccess=\(timestamp(event.directLastSuccessfulAt)) failureAttempt=\(timestamp(event.failureAttemptAt))"
            + " fiveHour=\(event.fiveHourSource.rawValue) sevenDay=\(event.sevenDaySource.rawValue) fable=\(event.fableSource.rawValue)"
            + " fiveHourReceipt=\(timestamp(event.fiveHourReceiptAt)) sevenDayReceipt=\(timestamp(event.sevenDayReceiptAt))"
        logger.notice("quotaRefresh \(fields, privacy: .public)")
    }
}
