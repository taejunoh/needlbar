import Foundation
import NeedlbarCore
import OSLog

struct ClaudeQuotaFailureDiagnosticEvent: Equatable, Sendable {
    let origin: ClaudeQuotaFailureOrigin
    let attemptAt: String
}

final class ClaudeQuotaFailureDiagnosticsReporter: @unchecked Sendable {
    private let readDiagnostics: @Sendable () throws -> BridgeEnvelope<DiagnosticsSnapshot>
    private let sink: @Sendable (ClaudeQuotaFailureDiagnosticEvent) -> Void

    convenience init(bridge: RustBridge) {
        self.init(
            readDiagnostics: bridge.diagnosticsEnvelope,
            sink: Self.productionSink
        )
    }

    init(
        readDiagnostics: @escaping @Sendable () throws -> BridgeEnvelope<DiagnosticsSnapshot>,
        sink: @escaping @Sendable (ClaudeQuotaFailureDiagnosticEvent) -> Void
    ) {
        self.readDiagnostics = readDiagnostics
        self.sink = sink
    }

    /// The coordinator reads through this once per completed Claude operation
    /// and passes the same read back to `report`, so the record is read once.
    var completionDiagnostics: ClaudeQuotaCompletionDiagnostics {
        ClaudeQuotaCompletionDiagnostics(
            read: { [self] in readOnce() },
            report: { [self] read in report(read) }
        )
    }

    func reportLatestClaudeQuotaFailure() {
        report(readOnce())
    }

    func report(_ read: ClaudeQuotaDiagnosticsRead) {
        guard let event = Self.event(from: read) else { return }
        sink(event)
    }

    private func readOnce() -> ClaudeQuotaDiagnosticsRead {
        Result { try readDiagnostics() }
    }

    static func event(from read: ClaudeQuotaDiagnosticsRead) -> ClaudeQuotaFailureDiagnosticEvent? {
        guard case .success(let envelope) = read else { return nil }
        guard let provider = envelope.data?.providers.first(where: { $0.provider == .claude }) else {
            return nil
        }
        guard provider.quotaStatus != .available else { return nil }
        guard let attemptAt = provider.lastAttemptAt else {
            return nil
        }
        guard let origin = provider.claudeQuotaFailureOrigin else {
            return nil
        }
        return ClaudeQuotaFailureDiagnosticEvent(
            origin: origin,
            attemptAt: ISO8601DateFormatter().string(from: attemptAt)
        )
    }

    private static func productionSink(_ event: ClaudeQuotaFailureDiagnosticEvent) {
        let logger = Logger(subsystem: "com.taejunoh.needlbar", category: "ClaudeQuotaFailureDiagnostic")
        logger.notice("claudeQuotaFailure origin=\(event.origin.rawValue, privacy: .public) attempt=\(event.attemptAt, privacy: .public)")
    }
}
