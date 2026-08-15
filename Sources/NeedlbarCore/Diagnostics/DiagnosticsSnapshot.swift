import Foundation

public struct DiagnosticsSnapshot: Decodable, Sendable, Equatable {
    public let providers: [ProviderDiagnostics]
}

public struct ProviderDiagnostics: Decodable, Sendable, Equatable {
    public let provider: ProviderID
    public let usageStatus: DiagnosticsStatus
    public let quotaStatus: DiagnosticsStatus
    public let usageSource: UsageDiagnosticsSource
    public let quotaSource: QuotaDiagnosticsSource
    public let lastUsageAt: Date?
    public let lastQuotaAt: Date?
    public let usageErrorCode: DiagnosticsErrorCode?
    public let quotaErrorCode: DiagnosticsErrorCode?

    private enum CodingKeys: String, CodingKey {
        case provider, usageStatus, quotaStatus, usageSource, quotaSource
        case lastUsageAt, lastQuotaAt, usageErrorCode, quotaErrorCode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let providerName = try container.decode(String.self, forKey: .provider)
        guard let provider = ProviderID(rawValue: providerName) else {
            throw DecodingError.dataCorruptedError(
                forKey: .provider,
                in: container,
                debugDescription: "Expected a supported Needlbar provider."
            )
        }
        self.provider = provider
        usageStatus = try container.decode(DiagnosticsStatus.self, forKey: .usageStatus)
        quotaStatus = try container.decode(DiagnosticsStatus.self, forKey: .quotaStatus)
        usageSource = try container.decode(UsageDiagnosticsSource.self, forKey: .usageSource)
        quotaSource = try container.decode(QuotaDiagnosticsSource.self, forKey: .quotaSource)
        lastUsageAt = try container.decodeIfPresent(Date.self, forKey: .lastUsageAt)
        lastQuotaAt = try container.decodeIfPresent(Date.self, forKey: .lastQuotaAt)
        usageErrorCode = try container.decodeIfPresent(DiagnosticsErrorCode.self, forKey: .usageErrorCode)
        quotaErrorCode = try container.decodeIfPresent(DiagnosticsErrorCode.self, forKey: .quotaErrorCode)
    }
}

public enum DiagnosticsStatus: String, Decodable, Sendable, Equatable {
    case available
    case unavailable
    case requiresAuthentication
    case error
}

public enum UsageDiagnosticsSource: String, Decodable, Sendable, Equatable {
    case local
    case cursorExport
}

public enum QuotaDiagnosticsSource: String, Decodable, Sendable, Equatable {
    case oauth
    case session
}

public enum DiagnosticsErrorCode: String, Decodable, Sendable, Equatable {
    case notInstalled
    case requiresAuthentication
    case authenticationExpired
    case rateLimited
    case networkUnavailable
    case providerUnavailable
    case schemaChanged
    case noUsageData
    case cursorSyncFailed
    case usageRuntimeUnavailable
    case usageReportUnavailable
    case invalidUsageDate
    case invalidUsageData
    case internalError
}

public extension BridgeDecoder {
    func decodeDiagnosticsEnvelope(_ data: Data) throws -> BridgeEnvelope<DiagnosticsSnapshot> {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = Self.date(value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected an RFC3339 timestamp."
                )
            }
            return date
        }
        let envelope = try decoder.decode(BridgeEnvelope<DiagnosticsSnapshot>.self, from: data)
        guard envelope.schemaVersion == "needlbar.v1" else {
            throw BridgeFailure.unsupportedSchemaVersion(envelope.schemaVersion)
        }
        return envelope
    }
}
