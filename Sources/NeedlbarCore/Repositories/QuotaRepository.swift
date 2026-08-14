public struct QuotaRefreshResult: Sendable {
    public let snapshots: [ProviderID: QuotaSnapshot]
    public let errors: [ProviderID: BridgeError]

    public init(snapshots: [ProviderID: QuotaSnapshot], errors: [ProviderID: BridgeError]) {
        self.snapshots = snapshots
        self.errors = errors
    }
}

public protocol QuotaRepository: Sendable {
    func refresh() throws -> QuotaRefreshResult
}

public struct RustQuotaRepository: QuotaRepository, Sendable {
    private let bridge: RustBridge

    public init(bridge: RustBridge = RustBridge()) {
        self.bridge = bridge
    }

    public func refresh() throws -> QuotaRefreshResult {
        let envelope = try bridge.quotaEnvelope()
        guard envelope.ok else {
            throw BridgeFailure.bridgeFailed(envelope.errors)
        }
        guard let payload = envelope.data else {
            throw BridgeFailure.missingData
        }

        var snapshots: [ProviderID: QuotaSnapshot] = [:]
        for snapshot in payload.providers {
            if let provider = snapshot.providerID {
                snapshots[provider] = snapshot.quota
            }
        }
        var errors: [ProviderID: BridgeError] = [:]
        for error in envelope.errors {
            if let provider = error.providerID {
                errors[provider] = error
            }
        }
        return QuotaRefreshResult(snapshots: snapshots, errors: errors)
    }
}
