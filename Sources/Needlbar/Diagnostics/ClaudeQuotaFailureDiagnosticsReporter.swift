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

    func reportLatestClaudeQuotaFailure() {
        guard let event = latestEvent() else { return }
        sink(event)
    }

    func latestEvent() -> ClaudeQuotaFailureDiagnosticEvent? {
        let envelope: BridgeEnvelope<DiagnosticsSnapshot>
        do {
            envelope = try readDiagnostics()
        } catch {
            return nil
        }
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
