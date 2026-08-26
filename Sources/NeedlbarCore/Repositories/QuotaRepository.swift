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
    func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult
}

public extension QuotaRepository {
    func refresh() throws -> QuotaRefreshResult {
        try refresh(intent: .backgroundAll)
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
            return try refreshAggregate(bridge.quotaEnvelope())
        case .userInitiated(provider: .claude):
            return try refreshDedicated(bridge.claudeUserInitiatedQuotaEnvelope(), for: .claude)
        case .userInitiated(provider: .codex):
            return try refreshDedicated(bridge.codexQuotaEnvelope(), for: .codex)
        case .userInitiated(provider: .cursor):
            throw safeFailure(provider: .cursor, code: "unsupportedProvider", message: "Cursor quota is unavailable in Needlbar. Use Cursor Spending for quota details.")
        }
    }

    private func refreshAggregate(_ envelope: BridgeEnvelope<BridgeQuotaPayload>) throws -> QuotaRefreshResult {
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

    private func refreshDedicated(
        _ envelope: BridgeEnvelope<BridgeQuotaPayload>,
        for expectedProvider: ProviderID
    ) throws -> QuotaRefreshResult {
        let errors = try normalizedDedicatedErrors(envelope.errors, for: expectedProvider)
        guard envelope.ok else {
            guard !errors.isEmpty else {
                throw invalidDedicatedResponse(for: expectedProvider)
            }
            throw BridgeFailure.bridgeFailed(Array(errors.values))
        }
        guard let payload = envelope.data else {
            throw invalidDedicatedResponse(for: expectedProvider)
        }

        var snapshots: [ProviderID: QuotaSnapshot] = [:]
        for snapshot in payload.providers {
            guard snapshot.providerID == expectedProvider, snapshots[expectedProvider] == nil else {
                throw unexpectedProviderFailure(for: expectedProvider)
            }
            snapshots[expectedProvider] = snapshot.quota
        }
        guard snapshots.count == 1 || !errors.isEmpty else {
            throw invalidDedicatedResponse(for: expectedProvider)
        }
        guard snapshots.isEmpty || errors.isEmpty else {
            throw invalidDedicatedResponse(for: expectedProvider)
        }
        return QuotaRefreshResult(snapshots: snapshots, errors: errors)
    }

    private func normalizedDedicatedErrors(
        _ bridgeErrors: [BridgeError],
        for expectedProvider: ProviderID
    ) throws -> [ProviderID: BridgeError] {
        var errors: [ProviderID: BridgeError] = [:]
        for error in bridgeErrors {
            if let rawProvider = error.provider, ProviderID(rawValue: rawProvider) != expectedProvider {
                throw unexpectedProviderFailure(for: expectedProvider)
            }
            let normalized = BridgeError(
                provider: expectedProvider.rawValue,
                code: error.code,
                message: error.message,
                action: error.action
            )
            errors[expectedProvider] = normalized
        }
        return errors
    }

    private func unexpectedProviderFailure(for provider: ProviderID) -> BridgeFailure {
        safeFailure(provider: provider, code: "unexpectedProvider", message: "Provider verification returned an unexpected provider.")
    }

    private func invalidDedicatedResponse(for provider: ProviderID) -> BridgeFailure {
        safeFailure(provider: provider, code: "invalidResponse", message: "Provider verification returned no result.")
    }

    private func safeFailure(provider: ProviderID, code: String, message: String) -> BridgeFailure {
        .bridgeFailed([BridgeError(provider: provider.rawValue, code: code, message: message, action: nil)])
    }
}
