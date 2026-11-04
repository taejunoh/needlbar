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
