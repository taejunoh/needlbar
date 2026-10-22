import Foundation

/// The bridge diagnostics record, read once after a completed Claude quota
/// operation. A failed read or decode is a value too, so it is never retried.
public typealias ClaudeQuotaDiagnosticsRead = Result<BridgeEnvelope<DiagnosticsSnapshot>, any Error>

/// Reads the existing diagnostics record once per completed Claude quota
/// operation and hands that same read to the local diagnostics reporter. The
/// coordinator uses it to associate a failure origin with the attempt it is
/// completing; neither side reads the bridge again or makes a quota call.
public struct ClaudeQuotaCompletionDiagnostics: Sendable {
    public let read: @Sendable () async -> ClaudeQuotaDiagnosticsRead
    public let report: @Sendable (ClaudeQuotaDiagnosticsRead) async -> Void

    public init(
        read: @escaping @Sendable () async -> ClaudeQuotaDiagnosticsRead,
        report: @escaping @Sendable (ClaudeQuotaDiagnosticsRead) async -> Void = { _ in }
    ) {
        self.read = read
        self.report = report
    }
}

enum ClaudeQuotaFailureOriginAssociation {
    /// Returns the record's closed origin only when it describes the attempt
    /// being completed. The bridge writes `lastAttemptAt` in whole seconds when
    /// the operation begins, so the attempt start is truncated before comparing.
    /// Any mismatch, missing field, or failed read yields `nil`, which keeps the
    /// code-based reason. Nothing is inferred from elapsed time or UI state.
    static func origin(
        in read: ClaudeQuotaDiagnosticsRead?,
        attemptStartedAt: Date,
        attemptGeneration: UInt64,
        currentGeneration: UInt64,
        claudeResultFailed: Bool
    ) -> ClaudeQuotaFailureOrigin? {
        guard claudeResultFailed,
              attemptGeneration == currentGeneration,
              case .success(let envelope)? = read,
              let record = envelope.data?.providers.first(where: { $0.provider == .claude }),
              record.quotaStatus != .available,
              let origin = record.claudeQuotaFailureOrigin,
              let recordedAttemptAt = record.lastAttemptAt,
              attemptStartedAt.timeIntervalSince1970.isFinite
        else { return nil }
        let attemptSecond = Date(timeIntervalSince1970: attemptStartedAt.timeIntervalSince1970.rounded(.down))
        return recordedAttemptAt >= attemptSecond ? origin : nil
    }
}
