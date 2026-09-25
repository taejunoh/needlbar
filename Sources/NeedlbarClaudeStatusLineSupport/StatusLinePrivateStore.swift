import Darwin
import Foundation

public struct StatusLineConnectionMetadata: Codable, Equatable, Sendable {
    public let generation: UUID
    public let originalStatusLineJSON: Data?
    public let originalCommand: String?
    public let ownedStatusLineJSON: Data

    public init(generation: UUID, originalStatusLineJSON: Data?, originalCommand: String?, ownedStatusLineJSON: Data) {
        self.generation = generation
        self.originalStatusLineJSON = originalStatusLineJSON
        self.originalCommand = originalCommand
        self.ownedStatusLineJSON = ownedStatusLineJSON
    }
}

public enum StatusLineStoreError: Error {
    case unsafeFile
    case invalidRecord
    case missingMetadata
    case system(Int32)
}

/// All mutable files are accessed relative to a verified private directory.
/// `lock` is never replaced or removed, including when a generation is deactivated.
public final class StatusLinePrivateStore: @unchecked Sendable {
    public static var defaultRootURL: URL {
        #if DEBUG
        if let testRoot = ProcessInfo.processInfo.environment["NEEDLBAR_STATUSLINE_TEST_ROOT"], testRoot.hasPrefix("/") {
            return URL(fileURLWithPath: testRoot, isDirectory: true)
        }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Needlbar-StatusLine", isDirectory: true)
    }

    private let rootURL: URL
    private let maximumRecordBytes = 16 * 1024
    private let maximumMetadataBytes = 1024 * 1024
    private let maximumHelperBytes = 64 * 1024 * 1024

    public var stableHelperURL: URL {
        rootURL.appendingPathComponent("NeedlbarClaudeStatusLine", isDirectory: false)
    }

    public init(rootURL: URL = StatusLinePrivateStore.defaultRootURL) throws {
        self.rootURL = rootURL
        if mkdir(rootURL.path, 0o700) != 0 && errno != EEXIST { throw StatusLineStoreError.system(errno) }
        let directory = try openDirectory()
        close(directory)
    }

    /// Atomically replaces the private executable. Existing invocations keep
    /// their open inode, while later Claude Code events use the new binary.
    public func installHelper(from sourceURL: URL) throws {
        let source = open(sourceURL.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard source >= 0 else { throw StatusLineStoreError.unsafeFile }
        defer { close(source) }
        var sourceInfo = stat()
        guard fstat(source, &sourceInfo) == 0,
              (sourceInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              (sourceInfo.st_uid == getuid() || sourceInfo.st_uid == 0),
              sourceInfo.st_nlink == 1,
              (sourceInfo.st_mode & 0o022) == 0,
              (sourceInfo.st_mode & 0o111) != 0,
              sourceInfo.st_size > 0,
              sourceInfo.st_size <= maximumHelperBytes else { throw StatusLineStoreError.unsafeFile }

        try withExclusiveLock { directory in
            try validateInstalledHelperIfPresent(in: directory)
            let temporary = ".helper-\(UUID().uuidString)"
            let output = temporary.withCString {
                openat(directory, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o700)
            }
            guard output >= 0 else { throw StatusLineStoreError.system(errno) }
            defer { close(output); temporary.withCString { _ = unlinkat(directory, $0, 0) } }
            guard fchmod(output, 0o700) == 0 else { throw StatusLineStoreError.system(errno) }
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            var total = 0
            while true {
                let count = Darwin.read(source, &buffer, buffer.count)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw StatusLineStoreError.system(errno)
                }
                if count == 0 { break }
                total += count
                guard total <= maximumHelperBytes else { throw StatusLineStoreError.unsafeFile }
                var offset = 0
                while offset < count {
                    let written = buffer.withUnsafeBytes { raw in
                        Darwin.write(output, raw.baseAddress!.advanced(by: offset), count - offset)
                    }
                    if written < 0 {
                        if errno == EINTR { continue }
                        throw StatusLineStoreError.system(errno)
                    }
                    guard written > 0 else { throw StatusLineStoreError.unsafeFile }
                    offset += written
                }
            }
            guard total == sourceInfo.st_size, fsync(output) == 0 else {
                throw StatusLineStoreError.unsafeFile
            }
            try validateInstalledHelperIfPresent(in: directory)
            let renamed = temporary.withCString { old in
                "NeedlbarClaudeStatusLine".withCString { new in
                    renameat(directory, old, directory, new)
                }
            }
            guard renamed == 0, fsync(directory) == 0 else { throw StatusLineStoreError.system(errno) }
        }
    }

    private func validateInstalledHelperIfPresent(in directory: Int32) throws {
        let file = openat(directory, "NeedlbarClaudeStatusLine", O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        if file < 0 {
            if errno == ENOENT { return }
            throw StatusLineStoreError.unsafeFile
        }
        defer { close(file) }
        var info = stat()
        guard fstat(file, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_uid == getuid(), info.st_nlink == 1,
              (info.st_mode & 0o777) == 0o700 else { throw StatusLineStoreError.unsafeFile }
    }

    public func prepare(metadata: StatusLineConnectionMetadata) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(metadata)
        guard encoded.count <= maximumMetadataBytes else { throw StatusLineStoreError.invalidRecord }
        try withExclusiveLock { directory in
            let name = metadataName(metadata.generation)
            if let existing = try readFile(name, limit: maximumMetadataBytes, from: directory) {
                guard (try? JSONDecoder().decode(StatusLineConnectionMetadata.self, from: existing)) == metadata else {
                    throw StatusLineStoreError.unsafeFile
                }
                return
            }
            try atomicWrite(encoded, named: name, in: directory)
        }
    }

    public func metadata(for generation: UUID) throws -> StatusLineConnectionMetadata? {
        try withExclusiveLock { directory in
            guard let data = try readFile(metadataName(generation), limit: maximumMetadataBytes, from: directory),
                  let metadata = try? JSONDecoder().decode(StatusLineConnectionMetadata.self, from: data),
                  metadata.generation == generation
            else { return nil }
            return metadata
        }
    }

    public func activeGeneration() throws -> UUID? {
        try withExclusiveLock { directory in
            try activeGeneration(in: directory)
        }
    }

    public func activate(generation: UUID) throws {
        try withExclusiveLock { directory in
            guard try readFile(metadataName(generation), limit: maximumMetadataBytes, from: directory) != nil else {
                throw StatusLineStoreError.missingMetadata
            }
            try validateIfPresent("quota.json", in: directory)
            try removeIfPresent("quota.json", from: directory)
            try atomicWrite(Data(generation.uuidString.utf8), named: "active", in: directory)
        }
    }

    public func deactivate(generation: UUID) throws {
        try withExclusiveLock { directory in
            guard try activeGeneration(in: directory) == generation else { return }
            // Fence publication first. If the process exits before cache removal,
            // readers and delayed writers still reject this generation.
            try removeIfPresent("active", from: directory)
            try validateIfPresent("quota.json", in: directory)
            try removeIfPresent("quota.json", from: directory)
        }
    }

    public func publish(_ incoming: StatusLineQuotaRecord) throws -> Bool {
        guard incoming.schemaVersion == StatusLineQuotaRecord.currentSchemaVersion,
              isValid(incoming) else { throw StatusLineStoreError.invalidRecord }
        return try withExclusiveLock { directory in
            guard try activeGeneration(in: directory) == incoming.generation else { return false }
            let existing = try readRecord(in: directory)
            guard existing?.generation == incoming.generation || existing == nil else {
                throw StatusLineStoreError.invalidRecord
            }
            let merged = existing.map { StatusLineQuotaMerger.merge(existing: $0, incoming: incoming) } ?? incoming
            let data = try JSONEncoder().encode(StoredRecord(merged))
            guard data.count <= maximumRecordBytes else { throw StatusLineStoreError.invalidRecord }
            try atomicWrite(data, named: "quota.json", in: directory)
            return true
        }
    }

    public func read(expectedGeneration: UUID) throws -> StatusLineQuotaRecord? {
        try withExclusiveLock { directory in
            guard try activeGeneration(in: directory) == expectedGeneration else { return nil }
            let record = try readRecord(in: directory)
            guard record?.generation == expectedGeneration || record == nil else {
                throw StatusLineStoreError.invalidRecord
            }
            return record
        }
    }

    private func readRecord(in directory: Int32) throws -> StatusLineQuotaRecord? {
        guard let data = try readFile("quota.json", limit: maximumRecordBytes, from: directory) else { return nil }
        guard let stored = try? JSONDecoder().decode(StoredRecord.self, from: data),
              let record = stored.record,
              record.schemaVersion == StatusLineQuotaRecord.currentSchemaVersion,
              isValid(record)
        else { throw StatusLineStoreError.invalidRecord }
        return record
    }

    private func isValid(_ record: StatusLineQuotaRecord) -> Bool {
        for window in [record.fiveHour, record.sevenDay].compactMap({ $0 }) {
            if !window.usedPercent.isFinite || !(0...100).contains(window.usedPercent) ||
                !window.receivedAt.timeIntervalSince1970.isFinite ||
                !(window.resetsAt?.timeIntervalSince1970.isFinite ?? true) { return false }
        }
        return true
    }

    private func activeGeneration(in directory: Int32) throws -> UUID? {
        guard let bytes = try readFile("active", limit: 64, from: directory),
              let string = String(data: bytes, encoding: .utf8) else { return nil }
        return UUID(uuidString: string)
    }

    private func metadataName(_ generation: UUID) -> String { "metadata-\(generation.uuidString).json" }

    private func openDirectory() throws -> Int32 {
        var info = stat()
        guard lstat(rootURL.path, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              info.st_uid == getuid(),
              (info.st_mode & 0o777) == 0o700 else { throw StatusLineStoreError.unsafeFile }
        let descriptor = open(rootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw StatusLineStoreError.system(errno) }
        var opened = stat()
        guard fstat(descriptor, &opened) == 0,
              opened.st_dev == info.st_dev, opened.st_ino == info.st_ino else {
            close(descriptor)
            throw StatusLineStoreError.unsafeFile
        }
        return descriptor
    }

    private func withExclusiveLock<T>(_ body: (Int32) throws -> T) throws -> T {
        let directory = try openDirectory()
        defer { close(directory) }
        let lock: Int32 = "lock".withCString { name in
            openat(directory, name, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        }
        guard lock >= 0 else { throw StatusLineStoreError.system(errno) }
        defer { close(lock) }
        try validateFile(lock)
        guard flock(lock, LOCK_EX) == 0 else { throw StatusLineStoreError.system(errno) }
        defer { flock(lock, LOCK_UN) }
        // The inode must still be the one named `lock`; replacement would split writers.
        var named = stat()
        var opened = stat()
        guard fstatat(directory, "lock", &named, AT_SYMLINK_NOFOLLOW) == 0,
              fstat(lock, &opened) == 0,
              named.st_dev == opened.st_dev, named.st_ino == opened.st_ino else {
            throw StatusLineStoreError.unsafeFile
        }
        return try body(directory)
    }

    private func validateFile(_ descriptor: Int32) throws {
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_uid == getuid(), (info.st_mode & 0o777) == 0o600,
              info.st_nlink == 1 else { throw StatusLineStoreError.unsafeFile }
    }

    private func validateIfPresent(_ name: String, in directory: Int32) throws {
        let fd = name.withCString { openat(directory, $0, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC) }
        if fd < 0 {
            if errno == ENOENT { return }
            throw StatusLineStoreError.unsafeFile
        }
        defer { close(fd) }
        try validateFile(fd)
    }

    private func readFile(_ name: String, limit: Int, from directory: Int32) throws -> Data? {
        let fd = name.withCString { openat(directory, $0, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC) }
        if fd < 0 {
            if errno == ENOENT { return nil }
            throw StatusLineStoreError.unsafeFile
        }
        defer { close(fd) }
        try validateFile(fd)
        var bytes = [UInt8](repeating: 0, count: limit + 1)
        var offset = 0
        while offset < bytes.count {
            let remaining = bytes.count - offset
            let n = bytes.withUnsafeMutableBytes { buffer in
                Darwin.read(fd, buffer.baseAddress!.advanced(by: offset), remaining)
            }
            if n < 0 {
                if errno == EINTR { continue }
                throw StatusLineStoreError.system(errno)
            }
            if n == 0 { break }
            offset += n
        }
        guard offset <= limit else { throw StatusLineStoreError.invalidRecord }
        return Data(bytes.prefix(offset))
    }

    private func atomicWrite(_ data: Data, named name: String, in directory: Int32) throws {
        try validateIfPresent(name, in: directory)
        let temporary = ".temporary-\(UUID().uuidString)"
        let fd = temporary.withCString { openat(directory, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600) }
        guard fd >= 0 else { throw StatusLineStoreError.system(errno) }
        defer { close(fd); temporary.withCString { _ = unlinkat(directory, $0, 0) } }
        try validateFile(fd)
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw StatusLineStoreError.system(errno)
                }
                offset += n
            }
        }
        guard fsync(fd) == 0 else { throw StatusLineStoreError.system(errno) }
        try validateIfPresent(name, in: directory)
        let renameResult = temporary.withCString { source in
            name.withCString { target in renameat(directory, source, directory, target) }
        }
        guard renameResult == 0 else { throw StatusLineStoreError.system(errno) }
        guard fsync(directory) == 0 else { throw StatusLineStoreError.system(errno) }
    }

    private func removeIfPresent(_ name: String, from directory: Int32) throws {
        try validateIfPresent(name, in: directory)
        let result = name.withCString { unlinkat(directory, $0, 0) }
        if result != 0 && errno != ENOENT { throw StatusLineStoreError.system(errno) }
        guard fsync(directory) == 0 else { throw StatusLineStoreError.system(errno) }
    }
}

private struct StoredWindow: Codable {
    let usedPercent: Double
    let resetsAt: Date?
    let receivedAt: Date

    init(_ value: StatusLineWindowObservation) {
        usedPercent = value.usedPercent
        resetsAt = value.resetsAt
        receivedAt = value.receivedAt
    }

    var observation: StatusLineWindowObservation {
        StatusLineWindowObservation(usedPercent: usedPercent, resetsAt: resetsAt, receivedAt: receivedAt)
    }
}

private struct StoredRecord: Codable {
    let schemaVersion: Int
    let generation: UUID
    let fiveHour: StoredWindow?
    let sevenDay: StoredWindow?

    init(_ value: StatusLineQuotaRecord) {
        schemaVersion = value.schemaVersion
        generation = value.generation
        fiveHour = value.fiveHour.map(StoredWindow.init)
        sevenDay = value.sevenDay.map(StoredWindow.init)
    }

    var record: StatusLineQuotaRecord? {
        guard schemaVersion == StatusLineQuotaRecord.currentSchemaVersion else { return nil }
        return StatusLineQuotaRecord(schemaVersion: schemaVersion, generation: generation,
            fiveHour: fiveHour?.observation, sevenDay: sevenDay?.observation)
    }
}
