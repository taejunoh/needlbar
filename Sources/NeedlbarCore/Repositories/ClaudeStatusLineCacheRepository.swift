import Foundation
import NeedlbarClaudeStatusLineSupport

/// Local-only access to the generation-fenced status-line cache.
public protocol ClaudeStatusLineCacheReading: Sendable {
    func activeGeneration() -> UUID?
    func read(expectedGeneration: UUID) -> StatusLineQuotaRecord?
}

public struct ClaudeStatusLineCacheRepository: ClaudeStatusLineCacheReading {
    private let injectedStore: StatusLinePrivateStore?

    public init(store: StatusLinePrivateStore? = nil) {
        self.injectedStore = store
    }

    public func activeGeneration() -> UUID? {
        guard let store = resolveStore() else { return nil }
        return try? store.activeGeneration()
    }

    public func read(expectedGeneration: UUID) -> StatusLineQuotaRecord? {
        guard let store = resolveStore(),
              let record = try? store.read(expectedGeneration: expectedGeneration),
              record.generation == expectedGeneration,
              record.schemaVersion == StatusLineQuotaRecord.currentSchemaVersion else { return nil }
        return record
    }

    private func resolveStore() -> StatusLinePrivateStore? {
        if let injectedStore { return injectedStore }
        return try? StatusLinePrivateStore()
    }
}
