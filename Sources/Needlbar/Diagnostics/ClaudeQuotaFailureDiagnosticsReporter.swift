import Foundation
import NeedlbarCore
import OSLog

/// The closed allowlist of Claude quota error codes the failure diagnostic may
/// log: the codes the bridge can record for a Claude quota error, which are the
/// Rust `QuotaErrorCode` values after the bridge folds `serviceUnavailable`
/// (HTTP 5xx) into `providerUnavailable`. An absent code, or a record code that
/// is not a quota code, logs as `unknown`.
enum ClaudeQuotaFailureDiagnosticCode: String, Equatable, Sendable {
    case notInstalled
    case requiresAuthentication
    case authenticationExpired
    case permissionDenied
    case rateLimited
    case networkUnavailable
    case providerUnavailable
    case schemaChanged
    case unknown

    /// Exhaustive on purpose: a new record code must be placed deliberately.
    init(recordCode: DiagnosticsErrorCode?) {
        switch recordCode {
        case .notInstalled?: self = .notInstalled
        case .requiresAuthentication?: self = .requiresAuthentication
        case .authenticationExpired?: self = .authenticationExpired
        case .permissionDenied?: self = .permissionDenied
        case .rateLimited?: self = .rateLimited
        case .networkUnavailable?: self = .networkUnavailable
        case .providerUnavailable?: self = .providerUnavailable
        case .schemaChanged?: self = .schemaChanged
        case .noUsageData?, .usageRuntimeUnavailable?, .usageReportUnavailable?,
             .invalidUsageDate?, .invalidUsageData?, .internalError?, nil:
            self = .unknown
        }
    }
}

struct ClaudeQuotaFailureDiagnosticEvent: Equatable, Sendable {
    let origin: ClaudeQuotaFailureOrigin
    let code: ClaudeQuotaFailureDiagnosticCode
    let attemptAt: String

    /// The whole OSLog line, built only from the two closed values and the
    /// formatted attempt time.
    var message: String {
        "claudeQuotaFailure origin=\(origin.rawValue) code=\(code.rawValue) attempt=\(attemptAt)"
    }
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
            code: ClaudeQuotaFailureDiagnosticCode(recordCode: provider.quotaErrorCode),
            attemptAt: ISO8601DateFormatter().string(from: attemptAt)
        )
    }

    private static func productionSink(_ event: ClaudeQuotaFailureDiagnosticEvent) {
        let logger = Logger(subsystem: "com.taejunoh.needlbar", category: "ClaudeQuotaFailureDiagnostic")
        logger.notice("\(event.message, privacy: .public)")
    }
}
