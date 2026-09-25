import Foundation
import NeedlbarClaudeStatusLineSupport
import Testing
@testable import NeedlbarCore

@Test func cacheRepositoryReadsOnlyTheCurrentlyActiveGeneration() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("needlbar-core-cache-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try StatusLinePrivateStore(rootURL: root)
    let generation = UUID()
    let metadata = StatusLineConnectionMetadata(
        generation: generation,
        originalStatusLineJSON: nil,
        originalCommand: nil,
        ownedStatusLineJSON: Data(#"{"type":"command","command":"helper"}"#.utf8)
    )
    try store.prepare(metadata: metadata)
    try store.activate(generation: generation)
    let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let record = StatusLineQuotaRecord(
        schemaVersion: StatusLineQuotaRecord.currentSchemaVersion,
        generation: generation,
        fiveHour: .init(usedPercent: 25, resetsAt: nil, receivedAt: observedAt),
        sevenDay: nil
    )
    #expect(try store.publish(record))
    let repository = ClaudeStatusLineCacheRepository(store: store)
    #expect(repository.activeGeneration() == generation)
    #expect(repository.read(expectedGeneration: generation)?.fiveHour?.usedPercent == 25)
    #expect(repository.read(expectedGeneration: UUID()) == nil)

    try store.deactivate(generation: generation)
    #expect(repository.activeGeneration() == nil)
    #expect(repository.read(expectedGeneration: generation) == nil)
}
