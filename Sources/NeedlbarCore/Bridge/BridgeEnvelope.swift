import Foundation

public struct BridgeEnvelope<Payload: Decodable>: Decodable, Sendable where Payload: Sendable {
    public let schemaVersion: String
    public let ok: Bool
    public let generatedAt: Date
    public let data: Payload?
    public let errors: [BridgeError]
}

public struct BridgeError: Codable, Sendable, Equatable {
    public let provider: String?
    public let code: String
    public let message: String
    public let action: BridgeAction?

    public var providerID: ProviderID? {
        provider.flatMap(ProviderID.init(rawValue:))
    }
}

public enum BridgeAction: Sendable, Equatable {
    case connectCursor
    case unknown(String)
}

extension BridgeAction: Codable {
    public init(from decoder: Decoder) throws {
        let action = try decoder.singleValueContainer().decode(String.self)
        self = action == "connectCursor" ? .connectCursor : .unknown(action)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .connectCursor:
            try container.encode("connectCursor")
        case .unknown(let action):
            try container.encode(action)
        }
    }
}

public struct BridgeUsagePayload: Decodable, Sendable {
    public let providers: [BridgeUsageProviderSnapshot]
}

public struct BridgeUsageProviderSnapshot: Decodable, Sendable {
    public let providerName: String
    public let usage: UsageSnapshot

    public var providerID: ProviderID? {
        ProviderID(rawValue: providerName)
    }

    private enum CodingKeys: String, CodingKey {
        case provider
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerName = try container.decode(String.self, forKey: .provider)
        usage = try UsageSnapshot(from: decoder)
    }
}

public struct BridgeQuotaPayload: Decodable, Sendable {
    public let providers: [BridgeQuotaProviderSnapshot]
}

public struct BridgeQuotaProviderSnapshot: Decodable, Sendable {
    public let providerName: String
    public let quota: QuotaSnapshot

    public var providerID: ProviderID? {
        ProviderID(rawValue: providerName)
    }

    private enum CodingKeys: String, CodingKey {
        case provider, windows
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerName = try container.decode(String.self, forKey: .provider)
        quota = QuotaSnapshot(windows: try container.decode([QuotaWindow].self, forKey: .windows))
    }
}

public enum BridgeFailure: Error, Sendable, Equatable {
    case nullPointer
    case invalidUTF8
    case unsupportedSchemaVersion(String)
    case missingData
    case bridgeFailed([BridgeError])
}

public struct BridgeDecoder: Sendable {
    public init() {}

    public func decodeUsageEnvelope(_ data: Data) throws -> BridgeEnvelope<BridgeUsagePayload> {
        try decodeEnvelope(data, as: BridgeUsagePayload.self)
    }

    public func decodeQuotaEnvelope(_ data: Data) throws -> BridgeEnvelope<BridgeQuotaPayload> {
        try decodeEnvelope(data, as: BridgeQuotaPayload.self)
    }

    public static func date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let wholeSeconds = ISO8601DateFormatter()
        wholeSeconds.formatOptions = [.withInternetDateTime]
        return wholeSeconds.date(from: value)
    }

    private func decodeEnvelope<Payload: Decodable & Sendable>(
        _ data: Data,
        as type: Payload.Type
    ) throws -> BridgeEnvelope<Payload> {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let date = Self.date(value) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Expected an RFC3339 timestamp."
                )
            }
            return date
        }
        let envelope = try decoder.decode(BridgeEnvelope<Payload>.self, from: data)
        guard envelope.schemaVersion == "needlbar.v1" else {
            throw BridgeFailure.unsupportedSchemaVersion(envelope.schemaVersion)
        }
        return envelope
    }
}
