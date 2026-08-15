import Foundation

public struct DailyUsagePoint: Codable, Sendable, Equatable {
    public let date: String
    public let totalTokens: UInt64

    public init(date: String, totalTokens: UInt64) {
        self.date = date
        self.totalTokens = totalTokens
    }
}

public struct UsagePeriod: Codable, Sendable, Equatable {
    public let inputTokens: UInt64
    public let outputTokens: UInt64
    public let cacheReadTokens: UInt64
    public let cacheWriteTokens: UInt64
    public let totalTokens: UInt64
    public let estimatedCostUSD: Decimal

    public init(
        inputTokens: UInt64,
        outputTokens: UInt64,
        cacheReadTokens: UInt64,
        cacheWriteTokens: UInt64,
        totalTokens: UInt64,
        estimatedCostUSD: Decimal
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.totalTokens = totalTokens
        self.estimatedCostUSD = estimatedCostUSD
    }

    private enum CodingKeys: String, CodingKey {
        case inputTokens, outputTokens, cacheReadTokens, cacheWriteTokens, totalTokens, estimatedCostUSD
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try container.decode(UInt64.self, forKey: .inputTokens)
        outputTokens = try container.decode(UInt64.self, forKey: .outputTokens)
        cacheReadTokens = try container.decode(UInt64.self, forKey: .cacheReadTokens)
        cacheWriteTokens = try container.decode(UInt64.self, forKey: .cacheWriteTokens)
        totalTokens = try container.decode(UInt64.self, forKey: .totalTokens)
        estimatedCostUSD = try container.decodeExactDecimal(forKey: .estimatedCostUSD)
    }
}

public struct UsageSnapshot: Codable, Sendable, Equatable {
    public let inputTokens: UInt64
    public let outputTokens: UInt64
    public let cacheReadTokens: UInt64
    public let cacheWriteTokens: UInt64
    public let totalTokens: UInt64
    public let estimatedCostUSD: Decimal
    public let today: UsagePeriod
    public let last7Days: UsagePeriod
    public let last7DaysDaily: [DailyUsagePoint]
    public let last30Days: UsagePeriod

    public init(
        inputTokens: UInt64,
        outputTokens: UInt64,
        cacheReadTokens: UInt64,
        cacheWriteTokens: UInt64,
        totalTokens: UInt64,
        estimatedCostUSD: Decimal,
        today: UsagePeriod,
        last7Days: UsagePeriod,
        last7DaysDaily: [DailyUsagePoint] = [],
        last30Days: UsagePeriod
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.totalTokens = totalTokens
        self.estimatedCostUSD = estimatedCostUSD
        self.today = today
        self.last7Days = last7Days
        self.last7DaysDaily = last7DaysDaily
        self.last30Days = last30Days
    }

    private enum CodingKeys: String, CodingKey {
        case inputTokens, outputTokens, cacheReadTokens, cacheWriteTokens, totalTokens, estimatedCostUSD
        case today, last7Days, last7DaysDaily, last30Days
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try container.decode(UInt64.self, forKey: .inputTokens)
        outputTokens = try container.decode(UInt64.self, forKey: .outputTokens)
        cacheReadTokens = try container.decode(UInt64.self, forKey: .cacheReadTokens)
        cacheWriteTokens = try container.decode(UInt64.self, forKey: .cacheWriteTokens)
        totalTokens = try container.decode(UInt64.self, forKey: .totalTokens)
        estimatedCostUSD = try container.decodeExactDecimal(forKey: .estimatedCostUSD)
        today = try container.decode(UsagePeriod.self, forKey: .today)
        last7Days = try container.decode(UsagePeriod.self, forKey: .last7Days)
        last7DaysDaily = try container.decodeIfPresent([DailyUsagePoint].self, forKey: .last7DaysDaily) ?? []
        last30Days = try container.decode(UsagePeriod.self, forKey: .last30Days)
    }
}

private extension KeyedDecodingContainer {
    func decodeExactDecimal(forKey key: Key) throws -> Decimal {
        if let string = try? decode(String.self, forKey: key) {
            guard let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: self,
                    debugDescription: "Expected a decimal string."
                )
            }
            return value
        }

        // Rust currently writes a JSON number. Decode it directly as Decimal
        // so no binary Double round-trip is introduced in Swift.
        return try decode(Decimal.self, forKey: key)
    }
}
