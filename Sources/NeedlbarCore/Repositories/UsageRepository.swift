public struct UsageRefreshResult: Sendable {
    public let snapshots: [ProviderID: UsageSnapshot]
    public let errors: [ProviderID: BridgeError]

    public init(snapshots: [ProviderID: UsageSnapshot], errors: [ProviderID: BridgeError]) {
        self.snapshots = snapshots
        self.errors = errors
    }
}

public protocol UsageRepository: Sendable {
    func refresh() throws -> UsageRefreshResult
    func refresh(forceCursorSync: Bool) throws -> UsageRefreshResult
}

public extension UsageRepository {
    func refresh(forceCursorSync: Bool) throws -> UsageRefreshResult {
        try refresh()
    }
}

public struct RustUsageRepository: UsageRepository, Sendable {
    private let bridge: RustBridge

    public init(bridge: RustBridge = RustBridge()) {
        self.bridge = bridge
    }

    public func refresh() throws -> UsageRefreshResult {
        try refresh(forceCursorSync: false)
    }

    public func refresh(forceCursorSync: Bool) throws -> UsageRefreshResult {
        let envelope = try bridge.usageEnvelope(forceCursorSync: forceCursorSync)
        guard envelope.ok else {
            throw BridgeFailure.bridgeFailed(envelope.errors)
        }
        guard let payload = envelope.data else {
            throw BridgeFailure.missingData
        }

        var snapshots: [ProviderID: UsageSnapshot] = [:]
        for snapshot in payload.providers {
            if let provider = snapshot.providerID {
                snapshots[provider] = snapshot.usage
            }
        }
        var errors: [ProviderID: BridgeError] = [:]
        for error in envelope.errors {
            if let provider = error.providerID {
                errors[provider] = error
            }
        }
        return UsageRefreshResult(snapshots: snapshots, errors: errors)
    }
}
