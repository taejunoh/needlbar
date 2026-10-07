import Foundation
import NeedlbarCore
import Testing
@testable import NeedlbarApp

@Suite("QuotaRefreshDiagnosticsReporterTests")
struct QuotaRefreshDiagnosticsReporterTests {
    @Test func startedIsReadableSynchronouslyWithoutCompletionOrExternalActions() throws {
        let sink = SafeAttemptSink()
        let reporter = QuotaRefreshDiagnosticsReporter(sink: { sink.record($0) })
        let started = event(phase: .started)
        reporter.record(started)
        #expect(reporter.latestEvent() == started)
        #expect(sink.values == [started])
        #expect(reporter.latestEvent()?.completedAt == nil)
        #expect(reporter.latestEvent()?.outcome == nil)
        // The reporter has no repository, auth, configuration or bridge dependency to invoke.
        for _ in 0..<100 { #expect(reporter.latestEvent() == started) }
        #expect(sink.values.count == 1)
    }

    @Test func invalidationRetainsStartAndDoesNotFabricateSuccessOrTimeout() {
        let sink = SafeAttemptSink()
        let reporter = QuotaRefreshDiagnosticsReporter(sink: { sink.record($0) })
        let invalidated = event(phase: .invalidated)
        reporter.record(invalidated)
        #expect(reporter.latestEvent() == invalidated)
        #expect(sink.values == [invalidated])
        #expect(reporter.latestEvent()?.startedAt == Date(timeIntervalSince1970: 100))
        #expect(reporter.latestEvent()?.completedAt == nil)
        #expect(reporter.latestEvent()?.outcome == nil)
    }

    @Test func safeFailureAndNextStartPreserveSeparateSuccessAndReceipts() {
        let sink = SafeAttemptSink()
        let reporter = QuotaRefreshDiagnosticsReporter(sink: { sink.record($0) })
        let failure = event(phase: .completed, outcome: .failure, projection: true)
        reporter.record(failure)
        #expect(reporter.latestEvent() == failure)
        reporter.record(event(phase: .started))
        let latest = reporter.latestEvent()
        #expect(latest?.phase == .started)
        #expect(latest?.outcome == nil)
        #expect(latest?.directLastSuccessfulAt == Date(timeIntervalSince1970: 10))
        #expect(latest?.failureAttemptAt == Date(timeIntervalSince1970: 100))
        #expect(latest?.fiveHourReceiptAt == Date(timeIntervalSince1970: 70))
        #expect(latest?.sevenDayReceiptAt == Date(timeIntervalSince1970: 80))
        #expect(latest?.fiveHourSource == .statusLine)
        #expect(latest?.sevenDaySource == .statusLine)
        #expect(latest?.fableSource == .direct)
        #expect(sink.values.count == 2)
        #expect(!String(describing: sink.values).contains("RAW_ERROR_TOKEN_PATH_CANARY"))
    }

    private func event(phase: QuotaAttemptPhase, outcome: QuotaAttemptOutcome? = nil,
                       projection: Bool = false) -> QuotaAttemptEvent {
        .init(id: UUID(), generation: 3, trigger: .wake, phase: phase,
              startedAt: Date(timeIntervalSince1970: 100),
              completedAt: phase == .completed ? Date(timeIntervalSince1970: 120) : nil,
              outcome: outcome, directLastSuccessfulAt: projection ? Date(timeIntervalSince1970: 10) : nil,
              failureAttemptAt: projection ? Date(timeIntervalSince1970: 100) : nil,
              fiveHourSource: projection ? .statusLine : .unavailable,
              sevenDaySource: projection ? .statusLine : .unavailable,
              fableSource: projection ? .direct : .unavailable,
              fiveHourReceiptAt: projection ? Date(timeIntervalSince1970: 70) : nil,
              sevenDayReceiptAt: projection ? Date(timeIntervalSince1970: 80) : nil)
    }
}

private final class SafeAttemptSink: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [QuotaAttemptEvent] = []
    var values: [QuotaAttemptEvent] { lock.withLock { events } }
    func record(_ event: QuotaAttemptEvent) { lock.withLock { events.append(event) } }
}
