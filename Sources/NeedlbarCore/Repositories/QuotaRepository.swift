public struct QuotaRefreshResult: Sendable {
    public let snapshots: [ProviderID: QuotaSnapshot]
    public let errors: [ProviderID: BridgeError]

    public init(snapshots: [ProviderID: QuotaSnapshot], errors: [ProviderID: BridgeError]) {
        self.snapshots = snapshots
        self.errors = errors
    }
}

public enum QuotaRefreshIntent: Equatable, Sendable {
    case backgroundAll
    case userInitiated(provider: ProviderID)
}

public protocol QuotaRepository: Sendable {
    func refresh() throws -> QuotaRefreshResult
    func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult
}

public extension QuotaRepository {
    func refresh() throws -> QuotaRefreshResult {
        try refresh(intent: .backgroundAll)
    }

    func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult {
        try refresh()
    }
}

public struct RustQuotaRepository: QuotaRepository, Sendable {
    private let bridge: RustBridge

    public init(bridge: RustBridge = RustBridge()) {
        self.bridge = bridge
    }

    public func refresh() throws -> QuotaRefreshResult {
        try refresh(intent: .backgroundAll)
    }

    public func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult {
        switch intent {
        case .backgroundAll:
            return try refresh(bridge.quotaEnvelope(), expectingOnly: nil)
        case .userInitiated(provider: .claude):
            return try refresh(bridge.claudeUserInitiatedQuotaEnvelope(), expectingOnly: .claude)
        case .userInitiated(provider: .codex):
            return try refresh(bridge.codexQuotaEnvelope(), expectingOnly: .codex)
        case .userInitiated(provider: .cursor):
            throw safeFailure(provider: .cursor, code: "unsupportedProvider", message: "Cursor quota verification is managed by its connection controller.")
        }
    }

    private func refresh(
        _ envelope: BridgeEnvelope<BridgeQuotaPayload>,
        expectingOnly expectedProvider: ProviderID?
    ) throws -> QuotaRefreshResult {
        guard envelope.ok else {
            throw BridgeFailure.bridgeFailed(envelope.errors)
        }
        guard let payload = envelope.data else {
            throw BridgeFailure.missingData
        }

        var snapshots: [ProviderID: QuotaSnapshot] = [:]
        for snapshot in payload.providers {
            if let expectedProvider, snapshot.providerID != expectedProvider {
                throw safeFailure(provider: expectedProvider, code: "unexpectedProvider", message: "Provider verification returned an unexpected provider.")
            }
            if let provider = snapshot.providerID {
                snapshots[provider] = snapshot.quota
            }
        }
        var errors: [ProviderID: BridgeError] = [:]
        for error in envelope.errors {
            if let expectedProvider, error.providerID != nil, error.providerID != expectedProvider {
                throw safeFailure(provider: expectedProvider, code: "unexpectedProvider", message: "Provider verification returned an unexpected provider.")
            }
            if let provider = error.providerID {
                errors[provider] = error
            }
        }
        return QuotaRefreshResult(snapshots: snapshots, errors: errors)
    }

    private func safeFailure(provider: ProviderID, code: String, message: String) -> BridgeFailure {
        .bridgeFailed([BridgeError(provider: provider.rawValue, code: code, message: message, action: nil)])
    }
}
