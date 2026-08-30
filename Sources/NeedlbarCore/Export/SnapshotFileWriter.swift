import Darwin
import Foundation

public protocol SnapshotFileWriter: Sendable {
    func writeAtomically(_ bytes: Data, to destination: URL) throws -> AtomicWriteResult
}

public enum AtomicWriteResult: Sendable, Equatable {
    case committed
    case committedWithDurabilityWarning
}

public enum SnapshotFileWriteError: Error, Sendable, Equatable {
    case invalidDestination
    case writeFailed
    case cleanupPending
}

protocol SnapshotPOSIXOperations: Sendable {
    func openExclusive(path: String, mode: Int32) throws -> Int32
    func fchmod(descriptor: Int32, mode: Int32) throws
    func write(descriptor: Int32, bytes: Data, offset: Int) throws -> Int
    func sync(descriptor: Int32) throws
    func close(descriptor: Int32) throws
    func rename(from source: String, to destination: String) throws
    func openDirectory(path: String) throws -> Int32
    func unlink(path: String) throws
}

enum SnapshotPOSIXOperationError: Error, Sendable {
    case alreadyExists
    case failed
}

public struct POSIXSnapshotFileWriter: SnapshotFileWriter {
    private static let privateMode: Int32 = 0o600
    private static let maximumExclusiveCreateAttempts = 16

    private let operations: any SnapshotPOSIXOperations
    private let uuid: @Sendable () -> UUID

    public init() {
        operations = SystemSnapshotPOSIXOperations()
        uuid = { UUID() }
    }

    init(
        operations: any SnapshotPOSIXOperations,
        uuid: @escaping @Sendable () -> UUID
    ) {
        self.operations = operations
        self.uuid = uuid
    }

    public func writeAtomically(_ bytes: Data, to destination: URL) throws -> AtomicWriteResult {
        guard destination.isFileURL,
              destination.host == nil || destination.host == "localhost",
              !destination.lastPathComponent.isEmpty
        else {
            throw SnapshotFileWriteError.invalidDestination
        }

        let parentDirectory = destination.deletingLastPathComponent()
        var temporaryPath: String?

        do {
            let (path, descriptor) = try createTemporarySibling(for: destination)
            temporaryPath = path
            var temporaryDescriptorOpen = true
            defer {
                if temporaryDescriptorOpen {
                    try? operations.close(descriptor: descriptor)
                }
            }

            try operations.fchmod(descriptor: descriptor, mode: Self.privateMode)
            try writeAll(bytes, to: descriptor)
            try operations.sync(descriptor: descriptor)
            do {
                try operations.close(descriptor: descriptor)
                temporaryDescriptorOpen = false
            } catch {
                // A failed close leaves descriptor state unspecified, so it must not be retried.
                temporaryDescriptorOpen = false
                throw error
            }
            try operations.rename(from: path, to: destination.path)
        } catch {
            if let temporaryPath {
                do {
                    try operations.unlink(path: temporaryPath)
                } catch {
                    throw SnapshotFileWriteError.cleanupPending
                }
            }
            throw SnapshotFileWriteError.writeFailed
        }

        return finalizeParentDirectory(parentDirectory.path)
    }

    private func createTemporarySibling(for destination: URL) throws -> (String, Int32) {
        let parentDirectory = destination.deletingLastPathComponent()
        for _ in 0 ..< Self.maximumExclusiveCreateAttempts {
            let path = parentDirectory
                .appendingPathComponent(".\(destination.lastPathComponent).\(uuid().uuidString).tmp")
                .path
            do {
                return (path, try operations.openExclusive(path: path, mode: Self.privateMode))
            } catch SnapshotPOSIXOperationError.alreadyExists {
                continue
            } catch {
                throw SnapshotFileWriteError.writeFailed
            }
        }
        throw SnapshotFileWriteError.writeFailed
    }

    private func writeAll(_ bytes: Data, to descriptor: Int32) throws {
        var offset = 0
        while offset < bytes.count {
            let count = try operations.write(descriptor: descriptor, bytes: bytes, offset: offset)
            guard count > 0, count <= bytes.count - offset else {
                throw SnapshotFileWriteError.writeFailed
            }
            offset += count
        }
    }

    private func finalizeParentDirectory(_ path: String) -> AtomicWriteResult {
        let descriptor: Int32
        do {
            descriptor = try operations.openDirectory(path: path)
        } catch {
            return .committedWithDurabilityWarning
        }

        var directoryDescriptorOpen = true
        defer {
            if directoryDescriptorOpen {
                try? operations.close(descriptor: descriptor)
            }
        }

        do {
            try operations.sync(descriptor: descriptor)
        } catch {
            return .committedWithDurabilityWarning
        }
        do {
            try operations.close(descriptor: descriptor)
            directoryDescriptorOpen = false
        } catch {
            // As above, a failed close has unspecified descriptor ownership.
            directoryDescriptorOpen = false
            return .committedWithDurabilityWarning
        }
        return .committed
    }
}

public protocol CoreExportAction: Sendable {
    func export(_ capture: ExportCapture, to destination: URL) async throws -> AtomicWriteResult
}

public struct DefaultCoreExportAction: CoreExportAction {
    private let exporter: SnapshotExporter
    private let writer: any SnapshotFileWriter

    public init(
        exporter: SnapshotExporter = SnapshotExporter(),
        writer: any SnapshotFileWriter = POSIXSnapshotFileWriter()
    ) {
        self.exporter = exporter
        self.writer = writer
    }

    public func export(_ capture: ExportCapture, to destination: URL) async throws -> AtomicWriteResult {
        let bytes = try exporter.encode(capture)
        return try await Task.detached { [writer] in
            try writer.writeAtomically(bytes, to: destination)
        }.value
    }
}

private struct SystemSnapshotPOSIXOperations: SnapshotPOSIXOperations {
    func openExclusive(path: String, mode: Int32) throws -> Int32 {
        while true {
            let descriptor = Darwin.open(path, O_CREAT | O_EXCL | O_WRONLY, mode_t(mode))
            if descriptor >= 0 { return descriptor }
            if errno == EINTR { continue }
            if errno == EEXIST { throw SnapshotPOSIXOperationError.alreadyExists }
            throw SnapshotPOSIXOperationError.failed
        }
    }

    func fchmod(descriptor: Int32, mode: Int32) throws {
        while true {
            if Darwin.fchmod(descriptor, mode_t(mode)) == 0 { return }
            if errno == EINTR { continue }
            throw SnapshotPOSIXOperationError.failed
        }
    }

    func write(descriptor: Int32, bytes: Data, offset: Int) throws -> Int {
        try bytes.withUnsafeBytes { buffer in
            while true {
                let count = Darwin.write(
                    descriptor,
                    buffer.baseAddress!.advanced(by: offset),
                    bytes.count - offset
                )
                if count >= 0 { return count }
                if errno == EINTR { continue }
                throw SnapshotPOSIXOperationError.failed
            }
        }
    }

    func sync(descriptor: Int32) throws {
        while true {
            if Darwin.fsync(descriptor) == 0 { return }
            if errno == EINTR { continue }
            throw SnapshotPOSIXOperationError.failed
        }
    }

    func close(descriptor: Int32) throws {
        if Darwin.close(descriptor) != 0 {
            throw SnapshotPOSIXOperationError.failed
        }
    }

    func rename(from source: String, to destination: String) throws {
        while true {
            if Darwin.rename(source, destination) == 0 { return }
            if errno == EINTR { continue }
            throw SnapshotPOSIXOperationError.failed
        }
    }

    func openDirectory(path: String) throws -> Int32 {
        while true {
            let descriptor = Darwin.open(path, O_RDONLY | O_DIRECTORY)
            if descriptor >= 0 { return descriptor }
            if errno == EINTR { continue }
            throw SnapshotPOSIXOperationError.failed
        }
    }

    func unlink(path: String) throws {
        while true {
            if Darwin.unlink(path) == 0 { return }
            if errno == EINTR { continue }
            throw SnapshotPOSIXOperationError.failed
        }
    }
}
