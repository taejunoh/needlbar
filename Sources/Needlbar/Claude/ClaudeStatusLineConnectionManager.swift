import CryptoKit
import Darwin
import Foundation
import NeedlbarClaudeStatusLineSupport

public enum ConnectionState: Equatable {
    case disconnected
    case waitingForData
    case connected(receivedAt: Date)
    case configurationChanged
    case unsupportedConfiguration
}

public struct ConnectionInspection: Equatable {
    public let revision: Data
    public let state: ConnectionState
}

public enum ConnectionError: Error, Equatable, LocalizedError {
    case configurationChanged
    case unsupportedStatusLine
    case unsafeSettingsFile

    public var errorDescription: String? {
        switch self {
        case .configurationChanged: "Claude Code settings changed. Review them before reconnecting."
        case .unsupportedStatusLine: "This Claude Code status-line configuration is not supported."
        case .unsafeSettingsFile: "Claude Code settings could not be read or updated safely."
        }
    }
}

/// Edits only the default user settings file, and only in response to an explicit Settings action.
/// Private metadata keeps the original command available to delayed Claude Code invocations.
@MainActor
public final class ClaudeStatusLineConnectionManager {
    private let configRootURL: URL
    private let injectedStore: StatusLinePrivateStore?
    private let helperURL: URL
    private let environment: [String: String]
    private let beforeAtomicReplace: (() -> Void)?

    public init(
        configRootURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude"),
        store: StatusLinePrivateStore? = nil,
        helperURL: URL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/NeedlbarClaudeStatusLine"),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        beforeAtomicReplace: (() -> Void)? = nil
    ) {
        self.configRootURL = configRootURL
        self.injectedStore = store
        self.helperURL = helperURL
        self.environment = environment
        self.beforeAtomicReplace = beforeAtomicReplace
    }

    public func inspect() throws -> ConnectionInspection {
        let bytes = try readSettings()
        let revision = Data(SHA256.hash(data: bytes))
        let store = try privateStore()
        let active = try store.activeGeneration()
        guard isDefaultConfiguration else {
            return ConnectionInspection(revision: revision,
                state: active == nil ? .unsupportedConfiguration : .configurationChanged)
        }
        guard let editor = try? SettingsJSONEditor(bytes) else {
            return ConnectionInspection(revision: revision,
                state: active == nil ? .unsupportedConfiguration : .configurationChanged)
        }
        guard editor.isSupported else {
            return ConnectionInspection(revision: revision,
                state: active == nil ? .unsupportedConfiguration : .configurationChanged)
        }
        guard let generation = active else {
            if let generation = ownedGeneration(in: editor),
               let metadata = try store.metadata(for: generation),
               editor.statusLineJSON == metadata.ownedStatusLineJSON {
                return ConnectionInspection(revision: revision, state: .configurationChanged)
            }
            return ConnectionInspection(revision: revision, state: .disconnected)
        }
        guard let metadata = try store.metadata(for: generation),
              editor.statusLineJSON == metadata.ownedStatusLineJSON else {
            return ConnectionInspection(revision: revision, state: .configurationChanged)
        }
        let record = try store.read(expectedGeneration: generation)
        if let receivedAt = [record?.fiveHour?.receivedAt, record?.sevenDay?.receivedAt].compactMap({ $0 }).max() {
            return ConnectionInspection(revision: revision, state: .connected(receivedAt: receivedAt))
        }
        return ConnectionInspection(revision: revision, state: .waitingForData)
    }

    @discardableResult
    public func connect(expectedRevision: Data) throws -> ConnectionState {
        guard isDefaultConfiguration else { throw ConnectionError.unsupportedStatusLine }
        let originalBytes = try readSettings()
        guard Data(SHA256.hash(data: originalBytes)) == expectedRevision else {
            throw ConnectionError.configurationChanged
        }
        let editor = try SettingsJSONEditor(originalBytes)
        guard editor.isSupported else { throw ConnectionError.unsupportedStatusLine }
        let store = try privateStore()
        if let staleGeneration = ownedGeneration(in: editor),
           let metadata = try store.metadata(for: staleGeneration),
           editor.statusLineJSON == metadata.ownedStatusLineJSON,
           try store.activeGeneration() != staleGeneration {
            throw ConnectionError.configurationChanged
        }
        if let active = try store.activeGeneration() {
            if let metadata = try store.metadata(for: active), editor.statusLineJSON == metadata.ownedStatusLineJSON {
                return try inspect().state
            }
            // The user replaced our entry. Fence the old generation before explicitly reconnecting.
            try store.deactivate(generation: active)
        }
        let generation = UUID()
        try validateHelper()
        do { try store.installHelper(from: helperURL) }
        catch { throw ConnectionError.unsafeSettingsFile }
        let command = "\(shellQuoted(stableHelperURL.path)) \(generation.uuidString)"
        let ownedObject = try editor.ownedObject(withCommand: command)
        let metadata = StatusLineConnectionMetadata(
            generation: generation,
            originalStatusLineJSON: editor.statusLineJSON,
            originalCommand: editor.originalCommand,
            ownedStatusLineJSON: ownedObject
        )
        try store.prepare(metadata: metadata)
        let replacement = editor.replacingStatusLine(with: ownedObject)
        try atomicReplace(replacement, expecting: originalBytes)
        do {
            try store.activate(generation: generation)
        } catch {
            // The installed wrapper can still run the original command from immutable metadata.
            // The next explicit action can restore it; never hide the partial connection.
            throw ConnectionError.unsafeSettingsFile
        }
        return .waitingForData
    }

    /// Refreshes only an already owned, active connection after an app update.
    /// It never changes Claude Code settings or creates a connection.
    @discardableResult
    public func refreshEnabledHelper() throws -> Bool {
        guard isDefaultConfiguration else { return false }
        let store = try privateStore()
        guard let active = try store.activeGeneration(),
              let editor = try? SettingsJSONEditor(readSettings()), editor.isSupported,
              let metadata = try store.metadata(for: active),
              editor.statusLineJSON == metadata.ownedStatusLineJSON,
              ownedGeneration(in: editor) == active else { return false }
        try validateHelper()
        do { try store.installHelper(from: helperURL) }
        catch { throw ConnectionError.unsafeSettingsFile }
        return true
    }

    @discardableResult
    public func disconnect() throws -> ConnectionState {
        let store = try privateStore()
        let active = try store.activeGeneration()
        if let active { try store.deactivate(generation: active) }
        let bytes = try readSettings()
        guard let editor = try? SettingsJSONEditor(bytes) else {
            return .configurationChanged
        }
        let generation = active ?? ownedGeneration(in: editor)
        guard let generation, let metadata = try store.metadata(for: generation) else {
            return .disconnected
        }
        // Publication is already fenced, even if settings were edited or malformed.
        guard editor.statusLineJSON == metadata.ownedStatusLineJSON else {
            return .configurationChanged
        }
        let restoration = editor.replacingStatusLine(with: metadata.originalStatusLineJSON)
        try atomicReplace(restoration, expecting: bytes)
        return .disconnected
    }

    /// Reconciles state only; it never writes Claude Code settings.
    public func recover() -> ConnectionState {
        do { return try inspect().state }
        catch {
            if let store = try? privateStore(), (try? store.activeGeneration()) != nil {
                return .configurationChanged
            }
            return .unsupportedConfiguration
        }
    }

    private var isDefaultConfiguration: Bool {
        guard let override = environment["CLAUDE_CONFIG_DIR"], !override.isEmpty else { return true }
        return URL(fileURLWithPath: override).standardizedFileURL == configRootURL.standardizedFileURL
    }

    private func privateStore() throws -> StatusLinePrivateStore {
        do { return try injectedStore ?? StatusLinePrivateStore() }
        catch { throw ConnectionError.unsafeSettingsFile }
    }

    private func ownedGeneration(in editor: SettingsJSONEditor) -> UUID? {
        guard let command = editor.originalCommand else { return nil }
        let prefix = shellQuoted(stableHelperURL.path) + " "
        guard command.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(command.dropFirst(prefix.count)))
    }

    private var stableHelperURL: URL {
        injectedStore?.stableHelperURL ?? StatusLinePrivateStore.defaultRootURL
            .appendingPathComponent("NeedlbarClaudeStatusLine", isDirectory: false)
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func validateHelper() throws {
        var info = stat()
        guard lstat(helperURL.path, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              (info.st_uid == getuid() || info.st_uid == 0),
              (info.st_mode & 0o022) == 0,
              (info.st_mode & 0o111) != 0 else { throw ConnectionError.unsafeSettingsFile }
    }

    private func readSettings() throws -> Data {
        let directory = try openConfigDirectory()
        defer { close(directory) }
        let file = openat(directory, "settings.json", O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        if file < 0 {
            if errno == ENOENT { return Data("{}".utf8) }
            throw ConnectionError.unsafeSettingsFile
        }
        defer { close(file) }
        try validateSettingsFile(file)
        var result = Data()
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = Darwin.read(file, &chunk, chunk.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw ConnectionError.unsafeSettingsFile
            }
            if count == 0 { break }
            guard result.count + count <= 1024 * 1024 else { throw ConnectionError.unsupportedStatusLine }
            result.append(contentsOf: chunk.prefix(count))
        }
        return result
    }

    private func openConfigDirectory() throws -> Int32 {
        var before = stat()
        guard lstat(configRootURL.path, &before) == 0,
              (before.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              before.st_uid == getuid(), (before.st_mode & 0o022) == 0 else {
            throw ConnectionError.unsafeSettingsFile
        }
        let descriptor = open(configRootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ConnectionError.unsafeSettingsFile }
        var after = stat()
        guard fstat(descriptor, &after) == 0,
              after.st_dev == before.st_dev, after.st_ino == before.st_ino else {
            close(descriptor)
            throw ConnectionError.unsafeSettingsFile
        }
        return descriptor
    }

    private func validateSettingsFile(_ descriptor: Int32) throws {
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_uid == getuid(), info.st_nlink == 1,
              (info.st_mode & 0o022) == 0 else { throw ConnectionError.unsafeSettingsFile }
    }

    private func atomicReplace(_ bytes: Data, expecting expected: Data) throws {
        let directory = try openConfigDirectory()
        defer { close(directory) }
        let temporary = ".needlbar-settings-\(UUID().uuidString)"
        let descriptor = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw ConnectionError.unsafeSettingsFile }
        defer { close(descriptor); _ = unlinkat(directory, temporary, 0) }
        try bytes.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(descriptor, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw ConnectionError.unsafeSettingsFile
                }
                offset += count
            }
        }
        guard fsync(descriptor) == 0 else { throw ConnectionError.unsafeSettingsFile }
        beforeAtomicReplace?()
        guard try readSettings() == expected else { throw ConnectionError.configurationChanged }
        guard renameat(directory, temporary, directory, "settings.json") == 0,
              fsync(directory) == 0 else { throw ConnectionError.unsafeSettingsFile }
        guard try readSettings() == bytes else { throw ConnectionError.configurationChanged }
    }
}

/// Byte-range editor keeps every unrelated top-level member and the original entry intact.
private struct SettingsJSONEditor {
    private let bytes: Data
    private let object: JSONObjectRange
    private let statusLine: JSONMemberRange?
    let originalCommand: String?
    let isSupported: Bool

    init(_ bytes: Data) throws {
        self.bytes = bytes
        var scanner = JSONRangeScanner(bytes: Array(bytes))
        object = try scanner.scanRootObject()
        statusLine = object.members.first { $0.key == "statusLine" }
        if let statusLine {
            let raw = bytes.subdata(in: statusLine.valueRange)
            guard let dictionary = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
                  dictionary["type"] as? String == "command",
                  let command = dictionary["command"] as? String else {
                originalCommand = nil
                isSupported = false
                return
            }
            originalCommand = command
            isSupported = true
        } else {
            originalCommand = nil
            isSupported = true
        }
    }

    var statusLineJSON: Data? { statusLine.map { bytes.subdata(in: $0.valueRange) } }

    func ownedObject(withCommand command: String) throws -> Data {
        let quoted = try JSONSerialization.data(withJSONObject: command, options: [.fragmentsAllowed])
        if let statusLine {
            let raw = bytes.subdata(in: statusLine.valueRange)
            var scanner = JSONRangeScanner(bytes: Array(raw))
            let inner = try scanner.scanRootObject()
            guard let commandMember = inner.members.first(where: { $0.key == "command" }) else {
                throw ConnectionError.unsupportedStatusLine
            }
            var result = raw
            result.replaceSubrange(commandMember.valueRange, with: quoted)
            return result
        }
        return Data("{\"type\":\"command\",\"command\":".utf8) + quoted + Data("}".utf8)
    }

    func replacingStatusLine(with replacement: Data?) -> Data {
        var result = bytes
        if let statusLine, let replacement {
            result.replaceSubrange(statusLine.valueRange, with: replacement)
        } else if let statusLine {
            if let commaBefore = statusLine.commaBefore {
                result.removeSubrange(commaBefore..<statusLine.valueRange.upperBound)
            } else if let commaAfter = statusLine.commaAfter {
                result.removeSubrange(statusLine.keyRange.lowerBound..<(commaAfter + 1))
            } else {
                result.removeSubrange(statusLine.keyRange.lowerBound..<statusLine.valueRange.upperBound)
            }
        } else if let replacement {
            let insertion = Data((object.members.isEmpty ? "\"statusLine\":" : ",\"statusLine\":").utf8) + replacement
            result.replaceSubrange(object.closingBrace..<object.closingBrace, with: insertion)
        }
        return result
    }
}

private struct JSONObjectRange {
    let members: [JSONMemberRange]
    let closingBrace: Int
}

private struct JSONMemberRange {
    let key: String
    let keyRange: Range<Int>
    let valueRange: Range<Int>
    let commaBefore: Int?
    let commaAfter: Int?
}

private struct JSONRangeScanner {
    let bytes: [UInt8]
    private var cursor = 0
    private var depth = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func scanRootObject() throws -> JSONObjectRange {
        skipWhitespace()
        let result = try scanObject()
        skipWhitespace()
        guard cursor == bytes.count,
              (try? JSONSerialization.jsonObject(with: Data(bytes))) is [String: Any] else {
            throw ConnectionError.unsupportedStatusLine
        }
        return result
    }

    private mutating func scanObject() throws -> JSONObjectRange {
        guard depth < 64, consume(0x7B) else { throw ConnectionError.unsupportedStatusLine }
        depth += 1; defer { depth -= 1 }
        skipWhitespace()
        if consume(0x7D) { return JSONObjectRange(members: [], closingBrace: cursor - 1) }
        var members: [JSONMemberRange] = []
        var keys = Set<String>()
        var previousComma: Int?
        while true {
            skipWhitespace()
            let keyStart = cursor
            let key = try scanString()
            guard keys.insert(key).inserted else { throw ConnectionError.unsupportedStatusLine }
            let keyEnd = cursor
            skipWhitespace()
            guard consume(0x3A) else { throw ConnectionError.unsupportedStatusLine }
            skipWhitespace()
            let valueStart = cursor
            try scanValue()
            let valueEnd = cursor
            skipWhitespace()
            let commaAfter = peek() == 0x2C ? cursor : nil
            members.append(JSONMemberRange(key: key, keyRange: keyStart..<keyEnd,
                valueRange: valueStart..<valueEnd, commaBefore: previousComma, commaAfter: commaAfter))
            if consume(0x7D) { return JSONObjectRange(members: members, closingBrace: cursor - 1) }
            guard let commaAfter, consume(0x2C) else { throw ConnectionError.unsupportedStatusLine }
            previousComma = commaAfter
        }
    }

    private mutating func scanValue() throws {
        guard let first = peek() else { throw ConnectionError.unsupportedStatusLine }
        switch first {
        case 0x7B: _ = try scanObject()
        case 0x5B:
            guard depth < 64, consume(0x5B) else { throw ConnectionError.unsupportedStatusLine }
            depth += 1; defer { depth -= 1 }
            skipWhitespace()
            if consume(0x5D) { return }
            while true {
                skipWhitespace(); try scanValue(); skipWhitespace()
                if consume(0x5D) { return }
                guard consume(0x2C) else { throw ConnectionError.unsupportedStatusLine }
            }
        case 0x22: _ = try scanString()
        default:
            let start = cursor
            while let byte = peek(), ![0x2C, 0x5D, 0x7D, 0x20, 0x09, 0x0A, 0x0D].contains(byte) {
                cursor += 1
            }
            guard cursor > start else { throw ConnectionError.unsupportedStatusLine }
        }
    }

    private mutating func scanString() throws -> String {
        let start = cursor
        guard consume(0x22) else { throw ConnectionError.unsupportedStatusLine }
        while let byte = peek() {
            cursor += 1
            if byte == 0x5C {
                guard peek() != nil else { throw ConnectionError.unsupportedStatusLine }
                cursor += 1
            } else if byte == 0x22 {
                let raw = Data(bytes[start..<cursor])
                guard let decoded = try? JSONSerialization.jsonObject(with: raw, options: [.fragmentsAllowed]) as? String else {
                    throw ConnectionError.unsupportedStatusLine
                }
                return decoded
            }
        }
        throw ConnectionError.unsupportedStatusLine
    }

    private mutating func skipWhitespace() {
        while let byte = peek(), [0x20, 0x09, 0x0A, 0x0D].contains(byte) { cursor += 1 }
    }

    private func peek() -> UInt8? { cursor < bytes.count ? bytes[cursor] : nil }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard peek() == byte else { return false }
        cursor += 1
        return true
    }
}
