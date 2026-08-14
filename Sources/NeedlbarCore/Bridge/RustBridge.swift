import CNeedlbar
import Darwin
import Foundation

public typealias BridgeJSONCall = @Sendable () -> UnsafePointer<CChar>?
public typealias BridgeStringFree = @Sendable (UnsafePointer<CChar>?) -> Void

public struct RustBridge: Sendable {
    private let usageCall: BridgeJSONCall
    private let forcedUsageCall: BridgeJSONCall
    private let quotaCall: BridgeJSONCall
    private let free: BridgeStringFree
    private let decoder: BridgeDecoder

    public init(
        usageCall: @escaping BridgeJSONCall = { needlbar_usage_snapshot_json() },
        forcedUsageCall: @escaping BridgeJSONCall = { needlbar_forced_usage_snapshot_json() },
        quotaCall: @escaping BridgeJSONCall = { needlbar_quota_snapshot_json() },
        free: @escaping BridgeStringFree = { pointer in needlbar_free_string(pointer) },
        decoder: BridgeDecoder = BridgeDecoder()
    ) {
        self.usageCall = usageCall
        self.forcedUsageCall = forcedUsageCall
        self.quotaCall = quotaCall
        self.free = free
        self.decoder = decoder
    }

    public func usageEnvelope(forceCursorSync: Bool = false) throws -> BridgeEnvelope<BridgeUsagePayload> {
        try decodeCString(forceCursorSync ? forcedUsageCall : usageCall, decode: decoder.decodeUsageEnvelope)
    }

    public func quotaEnvelope() throws -> BridgeEnvelope<BridgeQuotaPayload> {
        try decodeCString(quotaCall, decode: decoder.decodeQuotaEnvelope)
    }

    private func decodeCString<Payload: Sendable>(
        _ call: BridgeJSONCall,
        decode: (Data) throws -> BridgeEnvelope<Payload>
    ) throws -> BridgeEnvelope<Payload> {
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
