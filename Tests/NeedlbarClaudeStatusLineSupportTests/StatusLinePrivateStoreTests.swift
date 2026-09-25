import Darwin
import Foundation
import Testing
@testable import NeedlbarClaudeStatusLineSupport

private func storeFixture() throws -> (URL, StatusLinePrivateStore, UUID) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("needlbar-statusline-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let store = try StatusLinePrivateStore(rootURL: root)
    let generation = UUID()
    try store.prepare(metadata: StatusLineConnectionMetadata(
        generation: generation,
        originalStatusLineJSON: Data(#"{"type":"command","command":"printf original"}"#.utf8),
        originalCommand: "printf original",
        ownedStatusLineJSON: Data(#"{"type":"command","command":"helper"}"#.utf8)
    ))
    try store.activate(generation: generation)
    return (root, store, generation)
}

private func record(_ generation: UUID, used: Double, receivedAt: Date = Date(timeIntervalSince1970: 1_790_000_000)) -> StatusLineQuotaRecord {
    StatusLineQuotaRecord(schemaVersion: 1, generation: generation,
        fiveHour: StatusLineWindowObservation(usedPercent: used, resetsAt: Date(timeIntervalSince1970: 1_790_323_200), receivedAt: receivedAt), sevenDay: nil)
}

@Test func storePublishesAndReadsOnlyActiveGeneration() throws {
    let (root, store, generation) = try storeFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(try store.publish(record(generation, used: 25)))
    #expect(try store.read(expectedGeneration: generation)?.fiveHour?.usedPercent == 25)
    #expect(try store.read(expectedGeneration: UUID()) == nil)
    #expect(try store.metadata(for: generation)?.originalCommand == "printf original")
}

@Test func storeRejectsOldGenerationAndRetainsItsCommandAfterDeactivation() throws {
    let (root, store, generation) = try storeFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(try store.publish(record(generation, used: 25)))
    try store.deactivate(generation: generation)
    #expect(try store.read(expectedGeneration: generation) == nil)
    #expect(try !store.publish(record(generation, used: 35)))
    #expect(try store.metadata(for: generation)?.originalCommand == "printf original")
}

@Test func deactivateFencesPublicationWhenCacheCleanupFails() throws {
    let (root, store, generation) = try storeFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let outside = root.deletingLastPathComponent().appendingPathComponent("needlbar-outside-\(UUID())")
    defer { try? FileManager.default.removeItem(at: outside) }
    try Data("outside".utf8).write(to: outside)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("quota.json"), withDestinationURL: outside)

    #expect(throws: Error.self) { try store.deactivate(generation: generation) }
    #expect(try store.activeGeneration() == nil)
    #expect(try !store.publish(record(generation, used: 25)))
    #expect(try store.metadata(for: generation)?.originalCommand == "printf original")
    #expect(try Data(contentsOf: outside) == Data("outside".utf8))
}

@Test func storeRejectsSymlinkedCacheAndUnsafeRootMode() throws {
    let (root, store, generation) = try storeFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let outside = root.deletingLastPathComponent().appendingPathComponent("needlbar-outside-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: outside) }
    try Data("outside".utf8).write(to: outside)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("quota.json"), withDestinationURL: outside)
    #expect(throws: Error.self) { try store.publish(record(generation, used: 25)) }
    #expect(try Data(contentsOf: outside) == Data("outside".utf8))
    chmod(root.path, 0o755)
    #expect(throws: Error.self) { _ = try StatusLinePrivateStore(rootURL: root) }
}

@Test func storeConcurrentWritersCannotRegressSameReset() throws {
    let (root, store, generation) = try storeFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let group = DispatchGroup()
    for used in [25.0, 35.0, 30.0, 10.0] {
        group.enter()
        DispatchQueue.global().async {
            _ = try? store.publish(record(generation, used: used))
            group.leave()
        }
    }
    group.wait()
    #expect(try store.read(expectedGeneration: generation)?.fiveHour?.usedPercent == 35)
}

@Test func storeDoesNotAcceptCacheRecordFromAnotherGeneration() throws {
    let (root, store, generation) = try storeFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(try store.publish(record(generation, used: 25)))
    let quota = root.appendingPathComponent("quota.json")
    let original = try String(contentsOf: quota, encoding: .utf8)
    let altered = original.replacingOccurrences(of: generation.uuidString, with: UUID().uuidString)
    try Data(altered.utf8).write(to: quota)
    #expect(throws: Error.self) { _ = try store.read(expectedGeneration: generation) }
}

@Test func storeKeepsPrivateModesAndStableLockInode() throws {
    let (root, store, generation) = try storeFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(try store.publish(record(generation, used: 25)))
    let names = ["lock", "active", "quota.json", "metadata-\(generation.uuidString).json"]
    for name in names {
        let mode = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(name).path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }
    let lockURL = root.appendingPathComponent("lock")
    let oldInode = try FileManager.default.attributesOfItem(atPath: lockURL.path)[.systemFileNumber] as? NSNumber
    try store.deactivate(generation: generation)
    try store.activate(generation: generation)
    let newInode = try FileManager.default.attributesOfItem(atPath: lockURL.path)[.systemFileNumber] as? NSNumber
    #expect(oldInode == newInode)
}

@Test func storeCanPrepareIdenticalMetadataRepeatedlyAcrossInstances() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("needlbar-metadata-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try StatusLinePrivateStore(rootURL: root)
    let generation = UUID()
    let same = StatusLineConnectionMetadata(generation: generation,
        originalStatusLineJSON: Data(#"{"command":"printf original","type":"command"}"#.utf8),
        originalCommand: "printf original", ownedStatusLineJSON: Data(#"{"command":"helper"}"#.utf8))
    try store.prepare(metadata: same)
    for _ in 0..<100 {
        let another = try StatusLinePrivateStore(rootURL: root)
        try another.prepare(metadata: same)
    }
    #expect(try store.metadata(for: generation) == same)
}

@Test func storeRejectsFIFOsAtActiveMetadataAndCacheWithoutBlocking() throws {
    for leaf in ["active", "metadata", "quota.json"] {
        let (root, store, generation) = try storeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let name = leaf == "metadata" ? "metadata-\(generation.uuidString).json" : leaf
        let path = root.appendingPathComponent(name).path
        if leaf != "quota.json" { try FileManager.default.removeItem(atPath: path) }
        #expect(mkfifo(path, 0o600) == 0)
        let completed = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            if leaf == "metadata" { _ = try? store.metadata(for: generation) }
            else { _ = try? store.read(expectedGeneration: generation) }
            completed.signal()
        }
        let returnedPromptly = completed.wait(timeout: .now() + 0.5) == .success
        if !returnedPromptly {
            let writer = open(path, O_RDWR | O_NONBLOCK)
            if writer >= 0 {
                _ = Darwin.write(writer, "x", 1)
                close(writer)
            }
            _ = completed.wait(timeout: .now() + 2)
        }
        #expect(returnedPromptly, "\(leaf) FIFO must be rejected before opening blocks")
    }
}
