import CNeedlbar
import Darwin
import Foundation

public typealias BridgeJSONCall = @Sendable () -> UnsafePointer<CChar>?
public typealias BridgeStringFree = @Sendable (UnsafePointer<CChar>?) -> Void

public struct RustBridge: Sendable {
    private let usageCall: BridgeJSONCall
    private let quotaCall: BridgeJSONCall
    private let analyticsCall: BridgeJSONCall
    private let claudeUsageReportQuotaCall: @Sendable (UInt64) -> UnsafePointer<CChar>?
    private let claudeUsageReportCancelCall: @Sendable (UInt64) -> Void
    private let codexQuotaCall: BridgeJSONCall
    private let diagnosticsCall: BridgeJSONCall
    private let free: BridgeStringFree
    private let decoder: BridgeDecoder

    public init(
        usageCall: @escaping BridgeJSONCall = { needlbar_usage_snapshot_json() },
        quotaCall: @escaping BridgeJSONCall = { needlbar_quota_snapshot_json() },
        analyticsCall: @escaping BridgeJSONCall = { needlbar_analytics_snapshot_json() },
        claudeUsageReportQuotaCall: @escaping @Sendable (UInt64) -> UnsafePointer<CChar>? = { needlbar_claude_usage_report_quota_snapshot_json($0) },
        claudeUsageReportCancelCall: @escaping @Sendable (UInt64) -> Void = { needlbar_claude_usage_report_cancel_through($0) },
        codexQuotaCall: @escaping BridgeJSONCall = { needlbar_codex_quota_snapshot_json() },
        diagnosticsCall: @escaping BridgeJSONCall = { needlbar_diagnostics_json() },
        free: @escaping BridgeStringFree = { pointer in needlbar_free_string(pointer) },
        decoder: BridgeDecoder = BridgeDecoder()
    ) {
        self.usageCall = usageCall
        self.quotaCall = quotaCall
        self.analyticsCall = analyticsCall
        self.claudeUsageReportQuotaCall = claudeUsageReportQuotaCall
        self.claudeUsageReportCancelCall = claudeUsageReportCancelCall
        self.codexQuotaCall = codexQuotaCall
        self.diagnosticsCall = diagnosticsCall
        self.free = free
        self.decoder = decoder
    }

    public func usageEnvelope() throws -> BridgeEnvelope<BridgeUsagePayload> {
        try decodeCString(usageCall, decode: decoder.decodeUsageEnvelope)
    }

    public func quotaEnvelope() throws -> BridgeEnvelope<BridgeQuotaPayload> {
        try decodeCString(quotaCall, decode: decoder.decodeQuotaEnvelope)
    }

    /// Blocks for the whole run, so call it off the cooperative pool.
    public func claudeUsageReportEnvelope(runID: UInt64) throws -> BridgeEnvelope<BridgeQuotaPayload> {
        let call = claudeUsageReportQuotaCall
        return try decodeCString({ call(runID) }, decode: decoder.decodeQuotaEnvelope)
    }

    public func cancelClaudeUsageReport(through runID: UInt64) {
        claudeUsageReportCancelCall(runID)
    }

    public func codexQuotaEnvelope() throws -> BridgeEnvelope<BridgeQuotaPayload> {
        try decodeCString(codexQuotaCall, decode: decoder.decodeQuotaEnvelope)
    }

    public func analyticsEnvelope() throws -> AnalyticsSnapshot {
        try decodeCString(analyticsCall, decode: AnalyticsBridgeDecoder().decodeSnapshot)
    }

    public func diagnosticsEnvelope() throws -> BridgeEnvelope<DiagnosticsSnapshot> {
        try decodeCString(diagnosticsCall, decode: decoder.decodeDiagnosticsEnvelope)
    }

    private func decodeCString<Result: Sendable>(
        _ call: BridgeJSONCall,
        decode: (Data) throws -> Result
    ) throws -> Result {
        guard let pointer = call() else {
            throw BridgeFailure.nullPointer
        }
        defer { free(pointer) }

        let bytes = Data(bytes: pointer, count: Int(strlen(pointer)))
        guard String(data: bytes, encoding: .utf8) != nil else {
            throw BridgeFailure.invalidUTF8
        }

        return try decode(bytes)
    }
}
