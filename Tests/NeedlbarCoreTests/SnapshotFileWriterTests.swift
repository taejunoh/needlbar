import Darwin
import Foundation
import Testing
@testable import NeedlbarCore

@Test func writerCreatesPrivateSiblingThenCommitsByRenameAndDirectorySync() throws {
    let operations = RecordingPOSIXOperations()
    let writer = POSIXSnapshotFileWriter(operations: operations, uuid: { fixedUUID })
    let destination = URL(fileURLWithPath: "/private/export/snapshot.json")
    let temporaryPath = temporaryPath(for: destination, uuid: fixedUUID)

    #expect(try writer.writeAtomically(Data("{}\n".utf8), to: destination) == .committed)
    #expect(operations.events == [
        .openExclusive(temporaryPath, 0o600),
        .fchmod(RecordingPOSIXOperations.temporaryFD, 0o600),
        .write(RecordingPOSIXOperations.temporaryFD),
        .sync(RecordingPOSIXOperations.temporaryFD),
        .close(RecordingPOSIXOperations.temporaryFD),
        .rename(temporaryPath, destination.path),
        .openDirectory(destination.deletingLastPathComponent().path),
        .sync(RecordingPOSIXOperations.parentFD),
        .close(RecordingPOSIXOperations.parentFD),
    ])
    #expect(operations.directDestinationWrites.isEmpty)
    #expect(operations.crossDirectoryRenames.isEmpty)
}

@Test func preRenameFailurePreservesExistingDestinationAndOnlyUnlinksExactTemporaryPath() throws {
    let operations = RecordingPOSIXOperations(failing: .syncTemporaryFile)
    let writer = POSIXSnapshotFileWriter(operations: operations, uuid: { fixedUUID })
    let destination = URL(fileURLWithPath: "/private/export/snapshot.json")
    let temporaryPath = temporaryPath(for: destination, uuid: fixedUUID)

    #expect(throws: SnapshotFileWriteError.self) {
        _ = try writer.writeAtomically(Data("new".utf8), to: destination)
    }
    #expect(operations.renames.isEmpty)
    #expect(operations.unlinkedPaths == [temporaryPath])
    #expect(operations.directDestinationWrites.isEmpty)
}

@Test func writerRejectsNonFileURLsBeforeCreatingAnyTemporaryFile() {
    let operations = RecordingPOSIXOperations()
    let writer = POSIXSnapshotFileWriter(operations: operations, uuid: { fixedUUID })

    #expect(throws: SnapshotFileWriteError.self) {
        _ = try writer.writeAtomically(Data("new".utf8), to: URL(string: "https://example.com/snapshot.json")!)
    }
    #expect(operations.events.isEmpty)
}

@Test func writerRejectsRemoteFileURLsBeforeCreatingAnyTemporaryFile() {
    let operations = RecordingPOSIXOperations()
    let writer = POSIXSnapshotFileWriter(operations: operations, uuid: { fixedUUID })

    #expect(throws: SnapshotFileWriteError.self) {
        _ = try writer.writeAtomically(Data("new".utf8), to: URL(string: "file://remote.example/snapshot.json")!)
    }
    #expect(operations.events.isEmpty)
}

@Test func exclusiveCreateCollisionRetriesWithANewSiblingName() throws {
    let first = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let second = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    let uuid = UUIDSequence([first, second])
    let operations = RecordingPOSIXOperations(failing: .firstExclusiveCreateCollision)
    let writer = POSIXSnapshotFileWriter(operations: operations, uuid: { uuid.next() })
    let destination = URL(fileURLWithPath: "/private/export/snapshot.json")

    #expect(try writer.writeAtomically(Data("new".utf8), to: destination) == .committed)
    #expect(operations.exclusiveCreatePaths == [
        temporaryPath(for: destination, uuid: first),
        temporaryPath(for: destination, uuid: second),
    ])
    #expect(operations.renames == [
        .init(source: temporaryPath(for: destination, uuid: second), destination: destination.path),
    ])
}

@Test func writerWritesEveryByteBeforeItSyncsTheTemporaryFile() throws {
    let operations = RecordingPOSIXOperations(writeCounts: [1, 3])
    let writer = POSIXSnapshotFileWriter(operations: operations, uuid: { fixedUUID })
    let destination = URL(fileURLWithPath: "/private/export/snapshot.json")

    #expect(try writer.writeAtomically(Data("four".utf8), to: destination) == .committed)
    #expect(operations.events.prefix(5) == [
        .openExclusive(temporaryPath(for: destination, uuid: fixedUUID), 0o600),
        .fchmod(RecordingPOSIXOperations.temporaryFD, 0o600),
        .write(RecordingPOSIXOperations.temporaryFD),
        .write(RecordingPOSIXOperations.temporaryFD),
        .sync(RecordingPOSIXOperations.temporaryFD),
    ])
}

@Test(arguments: [
    RecordingPOSIXOperations.Failure.fchmodTemporary,
    .writeTemporary,
    .syncTemporaryFile,
    .closeTemporary,
    .rename,
])
private func everyPreRenameFailurePreservesTheDestinationAndCleansOnlyItsTemporarySibling(
    _ failure: RecordingPOSIXOperations.Failure
) throws {
    let operations = RecordingPOSIXOperations(failing: failure)
    let writer = POSIXSnapshotFileWriter(operations: operations, uuid: { fixedUUID })
    let destination = URL(fileURLWithPath: "/private/export/snapshot.json")
    let temporaryPath = temporaryPath(for: destination, uuid: fixedUUID)

    #expect(throws: SnapshotFileWriteError.self) {
        _ = try writer.writeAtomically(Data("new".utf8), to: destination)
    }
    #expect(operations.renames.isEmpty)
    #expect(operations.unlinkedPaths == [temporaryPath])
    #expect(operations.directDestinationWrites.isEmpty)
}

@Test func writerUsesOneSameDirectoryRenameWithoutACopyFallback() throws {
    let operations = RecordingPOSIXOperations()
    let writer = POSIXSnapshotFileWriter(operations: operations, uuid: { fixedUUID })
    let destination = URL(fileURLWithPath: "/private/export/snapshot.json")

    #expect(try writer.writeAtomically(Data("new".utf8), to: destination) == .committed)
    #expect(operations.renames.count == 1)
    #expect(operations.crossDirectoryRenames.isEmpty)
    #expect(operations.directDestinationWrites.isEmpty)
}

@Test func cleanupFailureRecordsOnlyTheExactTemporaryPathAndPreservesDestination() throws {
    let operations = RecordingPOSIXOperations(failing: .syncTemporaryFile, cleanupFails: true)
    let writer = POSIXSnapshotFileWriter(operations: operations, uuid: { fixedUUID })
    let destination = URL(fileURLWithPath: "/private/export/snapshot.json")
    let temporaryPath = temporaryPath(for: destination, uuid: fixedUUID)

    #expect(throws: SnapshotFileWriteError.self) {
        _ = try writer.writeAtomically(Data("new".utf8), to: destination)
    }
    #expect(operations.unlinkedPaths == [temporaryPath])
    #expect(operations.renames.isEmpty)
    #expect(operations.directDestinationWrites.isEmpty)
}

@Test(arguments: [
    RecordingPOSIXOperations.Failure.openDirectory,
    .syncDirectory,
    .closeDirectory,
])
private func parentDirectoryFinalizationFailuresRemainCommitted(_ failure: RecordingPOSIXOperations.Failure) throws {
    let operations = RecordingPOSIXOperations(failing: failure)
    let writer = POSIXSnapshotFileWriter(operations: operations, uuid: { fixedUUID })
    let destination = URL(fileURLWithPath: "/private/export/snapshot.json")

    #expect(try writer.writeAtomically(Data("new".utf8), to: destination) == .committedWithDurabilityWarning)
    #expect(operations.renames.count == 1)
    #expect(operations.unlinkedPaths.isEmpty)
}

@Test func writerReplacesAnExistingFileWithPrivateModeOnTheRealFilesystem() throws {
    let fileManager = FileManager.default
    let directory = fileManager.temporaryDirectory.appendingPathComponent("needlbar-writer-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? fileManager.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("snapshot.json")
    try Data("old".utf8).write(to: destination)

    #expect(try POSIXSnapshotFileWriter().writeAtomically(Data("new".utf8), to: destination) == .committed)
    #expect(try Data(contentsOf: destination) == Data("new".utf8))
    var metadata = stat()
    let statResult = destination.path.withCString { Darwin.lstat($0, &metadata) }
    #expect(statResult == 0)
    #expect(Int(metadata.st_mode & 0o777) == 0o600)
}

@Test func coreExportActionEncodesBeforeItInvokesTheWriterAndForwardsCommitResults() async throws {
    let destination = URL(fileURLWithPath: "/private/export/snapshot.json")

    for expected in [AtomicWriteResult.committed, .committedWithDurabilityWarning] {
        let writer = RecordingSnapshotFileWriter(result: expected)
        let action = DefaultCoreExportAction(writer: writer)

        #expect(try await action.export(validCapture(), to: destination) == expected)
        #expect(writer.destinations == [destination])
        #expect(writer.bytes.count == 1)
        #expect(writer.bytes[0].last == 0x0A)
    }

    let invalidWriter = RecordingSnapshotFileWriter(result: .committed)
    let invalidAction = DefaultCoreExportAction(writer: invalidWriter)
    await #expect(throws: SnapshotExportError.self) {
        _ = try await invalidAction.export(ExportCapture(exportedAt: Date(), providers: []), to: destination)
    }
    #expect(invalidWriter.bytes.isEmpty)
}

private let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

private func temporaryPath(for destination: URL, uuid: UUID) -> String {
    destination.deletingLastPathComponent()
        .appendingPathComponent(".\(destination.lastPathComponent).\(uuid.uuidString).tmp")
        .path
}

private func validCapture() -> ExportCapture {
    ExportCapture(
        exportedAt: Date(timeIntervalSince1970: 1_772_473_296),
        providers: ProviderID.allCases.map {
            ProviderExportState(
                provider: $0,
                usage: nil,
                quota: nil,
                usageStatus: .unavailable,
                quotaStatus: .unavailable,
                usageLastSuccessfulAt: nil,
                quotaLastSuccessfulAt: nil,
                everUpdated: false,
                updatedAt: nil
            )
        }
    )
}

private final class UUIDSequence: @unchecked Sendable {
    private var values: [UUID]

    init(_ values: [UUID]) {
        self.values = values
    }

    func next() -> UUID {
        values.removeFirst()
    }
}

private final class RecordingSnapshotFileWriter: SnapshotFileWriter, @unchecked Sendable {
    let result: AtomicWriteResult
    private(set) var bytes: [Data] = []
    private(set) var destinations: [URL] = []

    init(result: AtomicWriteResult) {
        self.result = result
    }

    func writeAtomically(_ bytes: Data, to destination: URL) throws -> AtomicWriteResult {
        self.bytes.append(bytes)
        destinations.append(destination)
        return result
    }
}

final class RecordingPOSIXOperations: SnapshotPOSIXOperations, @unchecked Sendable {
    enum Failure: Sendable, Equatable {
        case firstExclusiveCreateCollision
        case fchmodTemporary
        case writeTemporary
        case syncTemporaryFile
        case closeTemporary
        case rename
        case openDirectory
        case syncDirectory
        case closeDirectory
    }

    enum Event: Equatable {
        case openExclusive(String, Int32)
        case fchmod(Int32, Int32)
        case write(Int32)
        case sync(Int32)
        case close(Int32)
        case rename(String, String)
        case openDirectory(String)
        case unlink(String)
    }

    static let temporaryFD: Int32 = 41
    static let parentFD: Int32 = 42

    private let failing: Failure?
    private let cleanupFails: Bool
    private var collisionConsumed = false
    private var writeCounts: [Int]
    private(set) var events: [Event] = []
    private(set) var exclusiveCreatePaths: [String] = []
    struct Rename: Equatable {
        let source: String
        let destination: String
    }

    private(set) var renames: [Rename] = []
    private(set) var unlinkedPaths: [String] = []
    private(set) var directDestinationWrites: [Int32] = []
    private(set) var crossDirectoryRenames: [Rename] = []

    init(failing: Failure? = nil, cleanupFails: Bool = false, writeCounts: [Int] = []) {
        self.failing = failing
        self.cleanupFails = cleanupFails
        self.writeCounts = writeCounts
    }

    func openExclusive(path: String, mode: Int32) throws -> Int32 {
        events.append(.openExclusive(path, mode))
        exclusiveCreatePaths.append(path)
        if failing == .firstExclusiveCreateCollision, !collisionConsumed {
            collisionConsumed = true
            throw SnapshotPOSIXOperationError.alreadyExists
        }
        return Self.temporaryFD
    }

    func fchmod(descriptor: Int32, mode: Int32) throws {
        events.append(.fchmod(descriptor, mode))
        if failing == .fchmodTemporary { throw SnapshotPOSIXOperationError.failed }
    }

    func write(descriptor: Int32, bytes: Data, offset: Int) throws -> Int {
        events.append(.write(descriptor))
        if descriptor != Self.temporaryFD { directDestinationWrites.append(descriptor) }
        if failing == .writeTemporary { throw SnapshotPOSIXOperationError.failed }
        if writeCounts.isEmpty { return bytes.count - offset }
        return writeCounts.removeFirst()
    }

    func sync(descriptor: Int32) throws {
        events.append(.sync(descriptor))
        if descriptor == Self.temporaryFD, failing == .syncTemporaryFile { throw SnapshotPOSIXOperationError.failed }
        if descriptor == Self.parentFD, failing == .syncDirectory { throw SnapshotPOSIXOperationError.failed }
    }

    func close(descriptor: Int32) throws {
        events.append(.close(descriptor))
        if descriptor == Self.temporaryFD, failing == .closeTemporary { throw SnapshotPOSIXOperationError.failed }
        if descriptor == Self.parentFD, failing == .closeDirectory { throw SnapshotPOSIXOperationError.failed }
    }

    func rename(from source: String, to destination: String) throws {
        events.append(.rename(source, destination))
        if failing == .rename { throw SnapshotPOSIXOperationError.failed }
        let rename = Rename(source: source, destination: destination)
        renames.append(rename)
        if URL(fileURLWithPath: source).deletingLastPathComponent() != URL(fileURLWithPath: destination).deletingLastPathComponent() {
            crossDirectoryRenames.append(rename)
        }
    }

    func openDirectory(path: String) throws -> Int32 {
        events.append(.openDirectory(path))
        if failing == .openDirectory { throw SnapshotPOSIXOperationError.failed }
        return Self.parentFD
    }

    func unlink(path: String) throws {
        events.append(.unlink(path))
        unlinkedPaths.append(path)
        if cleanupFails { throw SnapshotPOSIXOperationError.failed }
    }
}
