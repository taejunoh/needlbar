#if NEEDLBAR_ACCEPTANCE_DRIVER
import Foundation
import NeedlbarCore

public enum AcceptanceFixtureErrorCode: String, Sendable {
    case fixturePathInvalid
    case fixtureReadFailed
    case fixtureTooLarge
    case fixtureMalformedJSON
    case fixtureUnknownKey
    case fixtureDuplicateKey
    case fixtureInvalidValue
    case fixtureUnknownID
    case fixtureCanaryDetected
}

public struct AcceptanceFixtureFailure: Error, Sendable, Equatable, CustomStringConvertible {
    public let code: AcceptanceFixtureErrorCode
    public let eventIndex: Int?

    public init(code: AcceptanceFixtureErrorCode, eventIndex: Int?) {
        self.code = code
        self.eventIndex = eventIndex
    }

    public static let fixturePathInvalid = Self(code: .fixturePathInvalid, eventIndex: nil)

    public var description: String {
        eventIndex.map { "\(code.rawValue): event \($0)" } ?? code.rawValue
    }
}

public struct AcceptanceFixture: Sendable {
    public static let maximumBytes = 256 * 1024
    public static let maximumEvents = 32
    let timeZone: TimeZone
    let startAt: Date
    let events: [AcceptanceFixtureEvent]
}

struct AcceptanceFixtureEvent: Sendable {
    let delay: Duration
    let localDay: String
    let usage: [ProviderID: UsageSnapshot]
    let quota: [ProviderID: QuotaSnapshot]
    let eventDate: Date
}

enum AcceptanceFixturePath {
    static func validate(_ path: URL, beneath root: URL, fileManager: FileManager = .default) throws -> URL {
        guard path.isFileURL, root.isFileURL, path.path.hasPrefix("/") else {
            throw AcceptanceFixtureFailure.fixturePathInvalid
        }
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let canonicalPath = path.resolvingSymlinksInPath().standardizedFileURL
        guard canonicalPath.path.hasPrefix(canonicalRoot.path + "/"),
              (try? canonicalPath.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              fileManager.fileExists(atPath: canonicalRoot.path) else {
            throw AcceptanceFixtureFailure.fixturePathInvalid
        }
        return canonicalPath
    }
}

enum AcceptanceFixtureParser {
    static func readAndParse(path: URL, beneath root: URL) throws -> AcceptanceFixture {
        let file = try AcceptanceFixturePath.validate(path, beneath: root)
        guard let bytes = try? Data(contentsOf: file, options: [.mappedIfSafe]), !bytes.isEmpty else {
            throw AcceptanceFixtureFailure(code: .fixtureReadFailed, eventIndex: nil)
        }
        guard bytes.count <= AcceptanceFixture.maximumBytes else {
            throw AcceptanceFixtureFailure(code: .fixtureTooLarge, eventIndex: nil)
        }
        return try parse(data: bytes)
    }

    static func parse(data: Data) throws -> AcceptanceFixture {
        guard data.count <= AcceptanceFixture.maximumBytes else {
            throw AcceptanceFixtureFailure(code: .fixtureTooLarge, eventIndex: nil)
        }
        guard let source = String(data: data, encoding: .utf8),
              !source.unicodeScalars.contains(where: { scalar in
                  scalar.value < 0x20 && scalar != "\n" && scalar != "\r" && scalar != "\t"
              }) else {
            throw AcceptanceFixtureFailure(code: .fixtureMalformedJSON, eventIndex: nil)
        }
        let root = try AcceptanceJSONScanner.parseObject(source)
        try AcceptanceFixtureValidation.rejectCanaries(in: .object(root), eventIndex: nil)
        return try AcceptanceFixtureValidation.fixture(from: root)
    }
}

private enum AcceptanceJSONValue: Equatable {
    case object([String: AcceptanceJSONValue])
    case array([AcceptanceJSONValue])
    case string(String)
    case number(Decimal)
    case bool(Bool)
    case null
}

private enum AcceptanceJSONScanner {
    static func parseObject(_ source: String) throws -> [String: AcceptanceJSONValue] {
        var parser = Parser(bytes: Array(source.utf8))
        guard case let .object(object) = try parser.value(), parser.isAtEnd else {
            throw malformed()
        }
        return object
    }

    private static func malformed() -> AcceptanceFixtureFailure {
        AcceptanceFixtureFailure(code: .fixtureMalformedJSON, eventIndex: nil)
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        mutating func value() throws -> AcceptanceJSONValue {
            skipWhitespace()
            guard index < bytes.count else { throw AcceptanceJSONScanner.malformed() }
            switch bytes[index] {
            case 0x7B: return try object()
            case 0x5B: return try array()
            case 0x22: return .string(try string())
            case 0x2D, 0x30...0x39: return .number(try number())
            case 0x74: try literal("true"); return .bool(true)
            case 0x66: try literal("false"); return .bool(false)
            case 0x6E: try literal("null"); return .null
            default: throw AcceptanceJSONScanner.malformed()
            }
        }

        var isAtEnd: Bool {
            var copy = self
            copy.skipWhitespace()
            return copy.index == copy.bytes.count
        }

        mutating private func object() throws -> AcceptanceJSONValue {
            index += 1
            var result: [String: AcceptanceJSONValue] = [:]
            var keys = Set<String>()
            skipWhitespace()
            if consume(0x7D) { return .object(result) }
            while true {
                skipWhitespace()
                guard index < bytes.count, bytes[index] == 0x22 else { throw AcceptanceJSONScanner.malformed() }
                let key = try string()
                guard keys.insert(key).inserted else {
                    throw AcceptanceFixtureFailure(code: .fixtureDuplicateKey, eventIndex: nil)
                }
                skipWhitespace()
                guard consume(0x3A) else { throw AcceptanceJSONScanner.malformed() }
                result[key] = try value()
                skipWhitespace()
                if consume(0x7D) { return .object(result) }
                guard consume(0x2C) else { throw AcceptanceJSONScanner.malformed() }
            }
        }

        mutating private func array() throws -> AcceptanceJSONValue {
            index += 1
            var result: [AcceptanceJSONValue] = []
            skipWhitespace()
            if consume(0x5D) { return .array(result) }
            while true {
                result.append(try value())
                skipWhitespace()
                if consume(0x5D) { return .array(result) }
                guard consume(0x2C) else { throw AcceptanceJSONScanner.malformed() }
            }
        }

        mutating private func string() throws -> String {
            guard consume(0x22) else { throw AcceptanceJSONScanner.malformed() }
            var scalars: [UnicodeScalar] = []
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                switch byte {
                case 0x22:
                    return String(String.UnicodeScalarView(scalars))
                case 0x5C:
                    guard index < bytes.count else { throw AcceptanceJSONScanner.malformed() }
                    let escape = bytes[index]
                    index += 1
                    switch escape {
                    case 0x22: scalars.append("\"")
                    case 0x5C: scalars.append("\\")
                    case 0x2F: scalars.append("/")
                    case 0x62: scalars.append("\u{8}")
                    case 0x66: scalars.append("\u{c}")
                    case 0x6E: scalars.append("\n")
                    case 0x72: scalars.append("\r")
                    case 0x74: scalars.append("\t")
                    case 0x75:
                        let scalar = try unicodeScalar()
                        scalars.append(scalar)
                    default: throw AcceptanceJSONScanner.malformed()
                    }
                case 0...0x1F:
                    throw AcceptanceJSONScanner.malformed()
                default:
                    guard byte < 0x80 else { throw AcceptanceJSONScanner.malformed() }
                    scalars.append(UnicodeScalar(byte))
                }
            }
            throw AcceptanceJSONScanner.malformed()
        }

        mutating private func unicodeScalar() throws -> UnicodeScalar {
            guard index + 4 <= bytes.count else { throw AcceptanceJSONScanner.malformed() }
            let hex = bytes[index..<(index + 4)]
            index += 4
            var value: UInt32 = 0
            for byte in hex {
                value <<= 4
                switch byte {
                case 0x30...0x39: value += UInt32(byte - 0x30)
                case 0x41...0x46: value += UInt32(byte - 0x41 + 10)
                case 0x61...0x66: value += UInt32(byte - 0x61 + 10)
                default: throw AcceptanceJSONScanner.malformed()
                }
            }
            guard let scalar = UnicodeScalar(value), !(0xD800...0xDFFF).contains(value) else {
                throw AcceptanceJSONScanner.malformed()
            }
            return scalar
        }

        mutating private func number() throws -> Decimal {
            let start = index
            if consume(0x2D) {}
            if consume(0x30) {
                if index < bytes.count, (0x30...0x39).contains(bytes[index]) { throw AcceptanceJSONScanner.malformed() }
            } else {
                guard index < bytes.count, (0x31...0x39).contains(bytes[index]) else { throw AcceptanceJSONScanner.malformed() }
                while index < bytes.count, (0x30...0x39).contains(bytes[index]) { index += 1 }
            }
            if consume(0x2E) {
                guard index < bytes.count, (0x30...0x39).contains(bytes[index]) else { throw AcceptanceJSONScanner.malformed() }
                while index < bytes.count, (0x30...0x39).contains(bytes[index]) { index += 1 }
            }
            if index < bytes.count, bytes[index] == 0x65 || bytes[index] == 0x45 {
                throw AcceptanceJSONScanner.malformed()
            }
            let text = String(decoding: bytes[start..<index], as: UTF8.self)
            guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
                throw AcceptanceJSONScanner.malformed()
            }
            return value
        }

        mutating private func literal(_ literal: String) throws {
            let bytes = Array(literal.utf8)
            guard index + bytes.count <= self.bytes.count, self.bytes[index..<(index + bytes.count)] == bytes[...] else {
                throw AcceptanceJSONScanner.malformed()
            }
            index += bytes.count
        }

        mutating private func consume(_ byte: UInt8) -> Bool {
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1
            return true
        }

        mutating private func skipWhitespace() {
            while index < bytes.count, bytes[index] == 0x20 || bytes[index] == 0x09 || bytes[index] == 0x0A || bytes[index] == 0x0D {
                index += 1
            }
        }
    }
}

private enum AcceptanceFixtureValidation {
    static let rootKeys: Set<String> = ["schemaVersion", "timeZone", "startAt", "events"]
    static let eventKeys: Set<String> = ["delaySeconds", "localDay", "usage", "quota"]
    static let usageKeys: Set<String> = ["tokens", "costUSD"]
    static let quotaKeys: Set<String> = ["id", "remainingPercent", "resetsAt"]
    static let quotaIDs: [ProviderID: Set<String>] = [
        .claude: ["claude.session", "claude.weekly"],
        .codex: ["codex.primary", "codex.secondary"],
    ]

    static func fixture(from root: [String: AcceptanceJSONValue]) throws -> AcceptanceFixture {
        try requireExactKeys(root, expected: rootKeys, eventIndex: nil)
        guard case let .number(version) = root["schemaVersion"], version == 1,
              case let .string(zoneID) = root["timeZone"], let zone = TimeZone(identifier: zoneID),
              case let .string(startText) = root["startAt"], let startAt = parseDate(startText),
              case let .array(eventsValue) = root["events"], eventsValue.count <= AcceptanceFixture.maximumEvents else {
            throw invalid(nil)
        }
        guard startAt <= Date() else { throw invalid(nil) }
        var events: [AcceptanceFixtureEvent] = []
        var elapsed: Int64 = 0
        for (index, value) in eventsValue.enumerated() {
            guard case let .object(event) = value else { throw invalid(index) }
            try requireExactKeys(event, expected: eventKeys, eventIndex: index)
            guard case let .number(delayNumber) = event["delaySeconds"],
                  delayNumber.isFinite, isIntegral(delayNumber),
                  delayNumber >= 0, delayNumber <= 900,
                  let delay = Int64(decimal: delayNumber),
                  case let .string(localDay) = event["localDay"],
                  case let .object(usageObject) = event["usage"],
                  case let .object(quotaObject) = event["quota"] else { throw invalid(index) }
            elapsed += delay
            let eventDate = startAt.addingTimeInterval(TimeInterval(elapsed))
            guard eventDate <= Date(), canonicalDay(for: eventDate, zone: zone) == localDay else { throw invalid(index) }
            let usage = try parseUsage(usageObject, eventIndex: index, localDay: localDay)
            let quota = try parseQuota(quotaObject, eventIndex: index)
            events.append(AcceptanceFixtureEvent(delay: .seconds(delay), localDay: localDay, usage: usage, quota: quota, eventDate: eventDate))
        }
        return AcceptanceFixture(timeZone: zone, startAt: startAt, events: events)
    }

    static func rejectCanaries(in value: AcceptanceJSONValue, eventIndex: Int?) throws {
        let canaries = ["access_token", "refresh_token", "secret", "password", "cookie", "authorization", "apikey", "api_key", "bearer", "keychain", "http://", "https://", "/users/", "/private/", "prompt", "response", "source", "repository", "file://"]
        func scan(_ value: AcceptanceJSONValue) -> Bool {
            switch value {
            case let .string(string): return canaries.contains { string.lowercased().contains($0) }
            case let .object(object): return object.contains { key, value in canaries.contains { key.lowercased().contains($0) } || scan(value) }
            case let .array(array): return array.contains(where: scan)
            default: return false
            }
        }
        if case let .object(object) = value,
           case let .array(events) = object["events"] {
            for (index, event) in events.enumerated() where scan(event) {
                throw AcceptanceFixtureFailure(code: .fixtureCanaryDetected, eventIndex: index)
            }
        }
        if scan(value) { throw AcceptanceFixtureFailure(code: .fixtureCanaryDetected, eventIndex: eventIndex) }
    }

    private static func parseUsage(_ object: [String: AcceptanceJSONValue], eventIndex: Int, localDay: String) throws -> [ProviderID: UsageSnapshot] {
        var result: [ProviderID: UsageSnapshot] = [:]
        for (rawID, value) in object {
            guard let provider = ProviderID(rawValue: rawID) else { throw unknownID(eventIndex) }
            guard case let .object(fields) = value else { throw invalid(eventIndex) }
            try requireExactKeys(fields, expected: usageKeys, eventIndex: eventIndex)
            guard case let .number(tokensNumber) = fields["tokens"], let tokens = UInt64(decimal: tokensNumber),
                  case let .string(costText) = fields["costUSD"], let cost = canonicalDecimal(costText), cost >= 0 else { throw invalid(eventIndex) }
            let period = UsagePeriod(inputTokens: tokens, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, totalTokens: tokens, estimatedCostUSD: cost)
            result[provider] = UsageSnapshot(inputTokens: tokens, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, totalTokens: tokens, estimatedCostUSD: cost, today: period, last7Days: period, last7DaysDaily: [DailyUsagePoint(date: localDay, totalTokens: tokens)], last30Days: period)
        }
        return result
    }

    private static func parseQuota(_ object: [String: AcceptanceJSONValue], eventIndex: Int) throws -> [ProviderID: QuotaSnapshot] {
        var result: [ProviderID: QuotaSnapshot] = [:]
        for (rawID, value) in object {
            guard let provider = ProviderID(rawValue: rawID), provider != .cursor else { throw unknownID(eventIndex) }
            guard let allowed = quotaIDs[provider], case let .array(rows) = value else { throw invalid(eventIndex) }
            var windows: [QuotaWindow] = []
            var ids = Set<String>()
            for row in rows {
                guard case let .object(fields) = row else { throw invalid(eventIndex) }
                try requireExactKeys(fields, expected: quotaKeys, eventIndex: eventIndex)
                guard case let .string(id) = fields["id"], allowed.contains(id), ids.insert(id).inserted,
                      case let .number(remaining) = fields["remainingPercent"], remaining.isFinite, remaining >= 0, remaining <= 100,
                      case let .string(resetText) = fields["resetsAt"], let resetsAt = parseDate(resetText) else {
                    throw unknownID(eventIndex)
                }
                let title: String
                switch id {
                case "claude.session": title = "Session"
                case "claude.weekly": title = "Weekly"
                case "codex.primary": title = "Primary"
                case "codex.secondary": title = "Secondary"
                default: throw unknownID(eventIndex)
                }
                do { windows.append(try QuotaWindow(id: id, title: title, usedPercent: 100 - remaining.doubleValue, resetsAt: resetsAt)) }
                catch { throw invalid(eventIndex) }
            }
            result[provider] = QuotaSnapshot(windows: windows)
        }
        return result
    }

    private static func requireExactKeys(_ object: [String: AcceptanceJSONValue], expected: Set<String>, eventIndex: Int?) throws {
        guard Set(object.keys).isSubset(of: expected) else { throw AcceptanceFixtureFailure(code: .fixtureUnknownKey, eventIndex: eventIndex) }
        guard Set(object.keys) == expected else { throw invalid(eventIndex) }
    }

    private static func parseDate(_ value: String) -> Date? {
        guard value.contains(".") else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private static func canonicalDay(for date: Date, zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func canonicalDecimal(_ text: String) -> Decimal? {
        guard text.range(of: #"^(0|[1-9][0-9]*)(\.[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func invalid(_ index: Int?) -> AcceptanceFixtureFailure {
        AcceptanceFixtureFailure(code: .fixtureInvalidValue, eventIndex: index)
    }

    private static func unknownID(_ index: Int?) -> AcceptanceFixtureFailure {
        AcceptanceFixtureFailure(code: .fixtureUnknownID, eventIndex: index)
    }
}

private extension UInt64 {
    init?(decimal: Decimal) {
        guard decimal.isFinite, decimal >= 0, isIntegral(decimal) else { return nil }
        let number = NSDecimalNumber(decimal: decimal)
        guard number.compare(NSDecimalNumber(value: UInt64.max)) != .orderedDescending else { return nil }
        self = number.uint64Value
    }
}

private func isIntegral(_ value: Decimal) -> Bool {
    var source = value
    var rounded = Decimal()
    NSDecimalRound(&rounded, &source, 0, .plain)
    return value == rounded
}

private extension Int64 {
    init?(decimal: Decimal) {
        guard let value = UInt64(decimal: decimal), value <= UInt64(Int64.max) else { return nil }
        self = Int64(value)
    }
}

private extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
#endif
