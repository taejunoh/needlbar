import Foundation

public enum WidgetProvider: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case cursor
}

public enum WidgetStreamState: String, Codable, Sendable {
    case fresh
    case stale
    case unavailable
}

public enum WidgetQuotaWindowID: String, Codable, Sendable, CaseIterable {
    case claudeSession = "claude.session"
    case claudeWeekly = "claude.weekly"
    case codexPrimary = "codex.primary"
    case codexSecondary = "codex.secondary"

    public var provider: WidgetProvider {
        rawValue.hasPrefix("claude.") ? .claude : .codex
    }

    public var categoryLabel: String {
        switch self {
        case .claudeSession: "Session"
        case .claudeWeekly: "Weekly"
        case .codexPrimary: "Primary"
        case .codexSecondary: "Secondary"
        }
    }
}

public struct WidgetQuotaHeadline: Codable, Sendable, Equatable {
    public let id: WidgetQuotaWindowID
    public let remainingPercent: Double
    public let resetsAt: Date?

    public init(id: WidgetQuotaWindowID, remainingPercent: Double, resetsAt: Date?) {
        self.id = id
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
    }
}

public struct WidgetQuotaRow: Codable, Sendable, Equatable {
    public let provider: WidgetProvider
    public let stream: WidgetStreamState
    public let lastSuccessfulAt: Date?
    public let headline: WidgetQuotaHeadline?

    public init(
        provider: WidgetProvider,
        stream: WidgetStreamState,
        lastSuccessfulAt: Date?,
        headline: WidgetQuotaHeadline?
    ) throws {
        guard provider != .cursor, headline.map({ $0.id.provider == provider }) ?? true else {
            throw WidgetProjectionError.invalidQuotaRow
        }
        self.provider = provider
        self.stream = stream
        self.lastSuccessfulAt = lastSuccessfulAt
        self.headline = headline
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case stream
        case lastSuccessfulAt
        case headline
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let provider = WidgetProvider(rawValue: try container.decode(String.self, forKey: .provider)),
              let stream = WidgetStreamState(rawValue: try container.decode(String.self, forKey: .stream)) else {
            throw WidgetProjectionError.invalidQuotaRow
        }
        let headline = try container.decodeIfPresent(WidgetQuotaHeadline.self, forKey: .headline)
        try self.init(
            provider: provider,
            stream: stream,
            lastSuccessfulAt: try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulAt),
            headline: headline
        )
    }
}

public struct WidgetUsageRow: Codable, Sendable, Equatable {
    public let provider: WidgetProvider
    public let stream: WidgetStreamState
    public let localDayKey: String?
    public let utcOffsetSeconds: Int?
    public let lastSuccessfulAt: Date?
    public let todayTokens: UInt64?
    public let todayCostUSD: Decimal?

    public init(
        provider: WidgetProvider,
        stream: WidgetStreamState,
        localDayKey: String?,
        utcOffsetSeconds: Int?,
        lastSuccessfulAt: Date?,
        todayTokens: UInt64?,
        todayCostUSD: Decimal?
    ) {
        self.provider = provider
        self.stream = stream
        self.localDayKey = localDayKey
        self.utcOffsetSeconds = utcOffsetSeconds
        self.lastSuccessfulAt = lastSuccessfulAt
        self.todayTokens = todayTokens
        self.todayCostUSD = todayCostUSD
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case stream
        case localDayKey
        case utcOffsetSeconds
        case lastSuccessfulAt
        case todayTokens
        case todayCostUSD
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let provider = WidgetProvider(rawValue: try container.decode(String.self, forKey: .provider)),
              let stream = WidgetStreamState(rawValue: try container.decode(String.self, forKey: .stream)) else {
            throw WidgetProjectionError.invalidUsageRow
        }
        self.init(
            provider: provider,
            stream: stream,
            localDayKey: try container.decodeIfPresent(String.self, forKey: .localDayKey),
            utcOffsetSeconds: try container.decodeIfPresent(Int.self, forKey: .utcOffsetSeconds),
            lastSuccessfulAt: try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulAt),
            todayTokens: try container.decodeIfPresent(UInt64.self, forKey: .todayTokens),
            todayCostUSD: try container.decodeIfPresent(Decimal.self, forKey: .todayCostUSD)
        )
    }
}

public struct WidgetTodaySummary: Codable, Sendable, Equatable {
    public enum Completeness: String, Codable, Sendable {
        case unavailable
        case partial
        case complete
    }

    public let completeness: Completeness
    public let totalTokens: UInt64?
    public let estimatedCostUSD: Decimal?

    public init(completeness: Completeness, totalTokens: UInt64?, estimatedCostUSD: Decimal?) {
        self.completeness = completeness
        self.totalTokens = totalTokens
        self.estimatedCostUSD = estimatedCostUSD
    }
}

public enum WidgetProjectionError: Error, Equatable, Sendable {
    case unsupportedSchema
    case tooLarge
    case invalidProviderOrder
    case invalidQuotaRow
    case invalidUsageRow
    case invalidTimestamp
    case invalidDay
    case invalidTodaySummary
}

public struct WidgetProjection: Codable, Sendable, Equatable {
    public static let schemaVersion = 1
    public static let maximumEncodedBytes = 64 * 1024

    public let schemaVersion: Int
    public let quotaRows: [WidgetQuotaRow]
    public let usageRows: [WidgetUsageRow]
    public let today: WidgetTodaySummary

    public init(
        quotaRows: [WidgetQuotaRow],
        usageRows: [WidgetUsageRow],
        today: WidgetTodaySummary
    ) throws {
        self.schemaVersion = Self.schemaVersion
        self.quotaRows = quotaRows
        self.usageRows = usageRows
        self.today = today
        try Self.validate(self, referenceDate: nil)
    }

    public static func encode(_ value: WidgetProjection) throws -> Data {
        try validate(value, referenceDate: nil)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(value)
        guard bytes.count <= maximumEncodedBytes else {
            throw WidgetProjectionError.tooLarge
        }
        return bytes
    }

    public static func decode(_ bytes: Data, referenceDate: Date) throws -> WidgetProjection {
        guard bytes.count <= maximumEncodedBytes else {
            throw WidgetProjectionError.tooLarge
        }

        struct Header: Decodable {
            let schemaVersion: Int
        }

        let headerDecoder = JSONDecoder()
        guard try headerDecoder.decode(Header.self, from: bytes).schemaVersion == schemaVersion else {
            throw WidgetProjectionError.unsupportedSchema
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let value = try decoder.decode(WidgetProjection.self, from: bytes)
            try validate(value, referenceDate: referenceDate)
            return value
        } catch let error as WidgetProjectionError {
            throw error
        } catch {
            throw WidgetProjectionError.invalidProviderOrder
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case quotaRows
        case usageRows
        case today
    }

    private struct RawQuotaHeadline: Decodable {
        let id: String
        let remainingPercent: Double
        let resetsAt: Date?
    }

    private struct RawQuotaRow: Decodable {
        let provider: String
        let stream: String
        let lastSuccessfulAt: Date?
        let headline: RawQuotaHeadline?
    }

    private struct RawUsageRow: Decodable {
        let provider: String
        let stream: String
        let localDayKey: String?
        let utcOffsetSeconds: Int?
        let lastSuccessfulAt: Date?
        let todayTokens: UInt64?
        let todayCostUSD: Decimal?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw WidgetProjectionError.unsupportedSchema
        }

        let rawQuotaRows = try container.decode([RawQuotaRow].self, forKey: .quotaRows)
        let rawUsageRows = try container.decode([RawUsageRow].self, forKey: .usageRows)
        let today = try container.decode(WidgetTodaySummary.self, forKey: .today)

        let quotaRows = try rawQuotaRows.map { row in
            guard let provider = WidgetProvider(rawValue: row.provider),
                  let stream = WidgetStreamState(rawValue: row.stream) else {
                throw WidgetProjectionError.invalidQuotaRow
            }
            let headline = try row.headline.map { raw in
                guard let id = WidgetQuotaWindowID(rawValue: raw.id) else {
                    throw WidgetProjectionError.invalidQuotaRow
                }
                return WidgetQuotaHeadline(id: id, remainingPercent: raw.remainingPercent, resetsAt: raw.resetsAt)
            }
            return try WidgetQuotaRow(
                provider: provider,
                stream: stream,
                lastSuccessfulAt: row.lastSuccessfulAt,
                headline: headline
            )
        }

        let usageRows = try rawUsageRows.map { row in
            guard let provider = WidgetProvider(rawValue: row.provider),
                  let stream = WidgetStreamState(rawValue: row.stream) else {
                throw WidgetProjectionError.invalidUsageRow
            }
            return WidgetUsageRow(
                provider: provider,
                stream: stream,
                localDayKey: row.localDayKey,
                utcOffsetSeconds: row.utcOffsetSeconds,
                lastSuccessfulAt: row.lastSuccessfulAt,
                todayTokens: row.todayTokens,
                todayCostUSD: row.todayCostUSD
            )
        }

        try self.init(quotaRows: quotaRows, usageRows: usageRows, today: today)
    }

    private static func validate(_ value: WidgetProjection, referenceDate: Date?) throws {
        guard value.schemaVersion == schemaVersion,
              value.quotaRows.map(\.provider) == [.claude, .codex],
              value.usageRows.map(\.provider) == WidgetProvider.allCases else {
            throw WidgetProjectionError.invalidProviderOrder
        }

        for row in value.quotaRows {
            guard row.provider != .cursor,
                  row.headline.map({
                      $0.id.provider == row.provider
                          && $0.remainingPercent.isFinite
                          && (0...100).contains($0.remainingPercent)
                  }) ?? true else {
                throw WidgetProjectionError.invalidQuotaRow
            }
            try validateTimestamp(row.lastSuccessfulAt, referenceDate)
            if let reset = row.headline?.resetsAt, !reset.timeIntervalSinceReferenceDate.isFinite {
                throw WidgetProjectionError.invalidQuotaRow
            }
        }

        var tokens: UInt64 = 0
        var cost = Decimal.zero
        var contributors = 0
        for row in value.usageRows {
            try validateTimestamp(row.lastSuccessfulAt, referenceDate)
            guard (row.todayTokens == nil) == (row.todayCostUSD == nil),
                  row.utcOffsetSeconds.map({ (-50_400...50_400).contains($0) }) ?? true else {
                throw WidgetProjectionError.invalidUsageRow
            }
            if let day = row.localDayKey {
                try validateDay(day)
            }
            if let rowTokens = row.todayTokens, let rowCost = row.todayCostUSD {
                guard row.localDayKey != nil,
                      row.utcOffsetSeconds != nil,
                      row.lastSuccessfulAt != nil,
                      !rowCost.isNaN,
                      rowCost >= .zero else {
                    throw WidgetProjectionError.invalidUsageRow
                }
                let (next, overflow) = tokens.addingReportingOverflow(rowTokens)
                guard !overflow else {
                    throw WidgetProjectionError.invalidTodaySummary
                }
                tokens = next
                cost = try decimalAdd(cost, rowCost)
                contributors += 1
            }
        }

        let expected: WidgetTodaySummary.Completeness = contributors == 0
            ? .unavailable
            : (contributors == 3 ? .complete : .partial)
        guard value.today.completeness == expected else {
            throw WidgetProjectionError.invalidTodaySummary
        }
        guard (contributors == 0 && value.today.totalTokens == nil && value.today.estimatedCostUSD == nil)
            || (contributors > 0
                && value.today.totalTokens == tokens
                && value.today.estimatedCostUSD == cost) else {
            throw WidgetProjectionError.invalidTodaySummary
        }
    }

    private static func validateTimestamp(_ value: Date?, _ reference: Date?) throws {
        guard let value else { return }
        guard value.timeIntervalSinceReferenceDate.isFinite,
              reference.map({ value <= $0 }) ?? true else {
            throw WidgetProjectionError.invalidTimestamp
        }
    }

    private static func validateDay(_ value: String) throws {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else {
            throw WidgetProjectionError.invalidDay
        }
    }

    private static func decimalAdd(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        var left = lhs
        var right = rhs
        var result = Decimal()
        guard NSDecimalAdd(&result, &left, &right, .plain) == .noError,
              !result.isNaN,
              result >= .zero else {
            throw WidgetProjectionError.invalidTodaySummary
        }
        return result
    }
}
