import Foundation

public struct SnapshotExporter: Sendable {
    public init() {}

    public func encode(_ capture: ExportCapture) throws -> Data {
        let document = try SnapshotExportDocument(capture: capture)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom(SnapshotExportFormat.encodeTimestamp)
        var bytes = try encoder.encode(document)
        bytes.append(0x0A)
        return bytes
    }
}

public enum SnapshotExportError: Error, Sendable, Equatable {
    case invalidCapture
    case invalidProvider
    case invalidTimestamp
    case invalidDate
    case invalidUsageAmount
    case invalidQuotaWindow
    case cursorQuotaNotAllowed
}

enum SnapshotExportValidation {
    static func validateWindow(
        provider: ProviderID,
        id: String,
        usedPercent: Double,
        resetsAt: Date?
    ) throws {
        guard usedPercent.isFinite, (0 ... 100).contains(usedPercent) else {
            throw SnapshotExportError.invalidQuotaWindow
        }
        if let resetsAt {
            try validateTimestamp(resetsAt)
        }
        switch provider {
        case .claude:
            guard ["claude.session", "claude.weekly"].contains(id) else {
                throw SnapshotExportError.invalidQuotaWindow
            }
        case .codex:
            guard ["codex.primary", "codex.secondary"].contains(id) else {
                throw SnapshotExportError.invalidQuotaWindow
            }
        case .cursor:
            throw SnapshotExportError.invalidQuotaWindow
        }
    }

    static func validateTimestamp(_ date: Date) throws {
        guard date.timeIntervalSinceReferenceDate.isFinite,
              SnapshotExportFormat.isExactV1Timestamp(date)
        else {
            throw SnapshotExportError.invalidTimestamp
        }
    }

    static func validateCalendarDate(_ value: String) throws {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else {
            throw SnapshotExportError.invalidDate
        }
    }

    static func canonicalDecimal(_ value: Decimal) throws -> String {
        guard !value.isNaN, value >= .zero else {
            throw SnapshotExportError.invalidUsageAmount
        }
        var copy = value
        let raw = NSDecimalString(&copy, Locale(identifier: "en_US_POSIX"))
        return normalizeDecimal(raw)
    }

    private static func normalizeDecimal(_ value: String) -> String {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        let integer = String(parts[0].drop(while: { $0 == "0" }))
        let normalizedInteger = integer.isEmpty ? "0" : integer
        guard parts.count == 2 else { return normalizedInteger }
        let fraction = String(parts[1].reversed().drop(while: { $0 == "0" }).reversed())
        return fraction.isEmpty ? normalizedInteger : "\(normalizedInteger).\(fraction)"
    }
}

private struct SnapshotExportDocument: Encodable {
    let schemaVersion = 1
    let exportedAt: Date
    let providers: [SnapshotExportProvider]

    init(capture: ExportCapture) throws {
        try SnapshotExportValidation.validateTimestamp(capture.exportedAt)
        let expectedProviders = ProviderID.allCases
        guard capture.providers.count == expectedProviders.count else {
            throw SnapshotExportError.invalidCapture
        }
        for (state, expectedProvider) in zip(capture.providers, expectedProviders) {
            guard state.provider == expectedProvider else {
                throw SnapshotExportError.invalidProvider
            }
            try SnapshotExportValidation.validate(state)
        }

        self.exportedAt = capture.exportedAt
        self.providers = try capture.providers.map(SnapshotExportProvider.init)
    }
}

private extension SnapshotExportValidation {
    static func validate(_ state: ProviderExportState) throws {
        if let updatedAt = state.updatedAt {
            try validateTimestamp(updatedAt)
        }
        if let usageLastSuccessfulAt = state.usageLastSuccessfulAt {
            try validateTimestamp(usageLastSuccessfulAt)
        }
        if let quotaLastSuccessfulAt = state.quotaLastSuccessfulAt {
            try validateTimestamp(quotaLastSuccessfulAt)
        }
        if let usage = state.usage {
            try validate(usage)
        }
        if let quota = state.quota {
            guard state.provider != .cursor else {
                throw SnapshotExportError.cursorQuotaNotAllowed
            }
            for window in quota.windows {
                try validateWindow(
                    provider: state.provider,
                    id: window.id,
                    usedPercent: window.usedPercent,
                    resetsAt: window.resetsAt
                )
            }
        }
    }

    static func validate(_ usage: UsageSnapshot) throws {
        try validatePeriod(
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            cacheReadTokens: usage.cacheReadTokens,
            cacheWriteTokens: usage.cacheWriteTokens,
            totalTokens: usage.totalTokens,
            estimatedCostUSD: usage.estimatedCostUSD
        )
        try validate(usage.today)
        try validate(usage.last7Days)
        try validate(usage.last30Days)

        var priorDate: String?
        for point in usage.last7DaysDaily {
            try validateCalendarDate(point.date)
            if let priorDate, point.date <= priorDate {
                throw SnapshotExportError.invalidDate
            }
            priorDate = point.date
        }
    }

    static func validate(_ period: UsagePeriod) throws {
        try validatePeriod(
            inputTokens: period.inputTokens,
            outputTokens: period.outputTokens,
            cacheReadTokens: period.cacheReadTokens,
            cacheWriteTokens: period.cacheWriteTokens,
            totalTokens: period.totalTokens,
            estimatedCostUSD: period.estimatedCostUSD
        )
    }

    static func validatePeriod(
        inputTokens _: UInt64,
        outputTokens _: UInt64,
        cacheReadTokens _: UInt64,
        cacheWriteTokens _: UInt64,
        totalTokens _: UInt64,
        estimatedCostUSD: Decimal
    ) throws {
        _ = try canonicalDecimal(estimatedCostUSD)
    }
}

private struct SnapshotExportProvider: Encodable {
    let provider: String
    let usage: SnapshotExportStream<SnapshotExportUsage>
    let quota: SnapshotExportStream<SnapshotExportQuota>
    let updatedAt: Date?

    init(_ state: ProviderExportState) throws {
        provider = state.provider.rawValue
        usage = try .init(
            data: state.usage.map(SnapshotExportUsage.init),
            status: .init(state.usageStatus, lastSuccessfulAt: state.usageLastSuccessfulAt)
        )
        quota = try .init(
            data: state.quota.map(SnapshotExportQuota.init),
            status: .init(state.quotaStatus, lastSuccessfulAt: state.quotaLastSuccessfulAt)
        )
        updatedAt = state.updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case provider, usage, quota, updatedAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(usage, forKey: .usage)
        try container.encode(quota, forKey: .quota)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

private struct SnapshotExportStream<DataValue: Encodable>: Encodable {
    let data: DataValue?
    let status: SnapshotExportStatus

    private enum CodingKeys: String, CodingKey {
        case data, status
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        try container.encode(status, forKey: .status)
    }
}

private struct SnapshotExportStatus: Encodable {
    let state: String
    let lastSuccessfulAt: Date?
    let errorCode: String?

    init(_ status: DataStatus, lastSuccessfulAt: Date?) {
        self.lastSuccessfulAt = lastSuccessfulAt
        switch status {
        case .fresh:
            state = "fresh"
            errorCode = nil
        case .stale:
            state = "stale"
            errorCode = nil
        case .unavailable:
            state = "unavailable"
            errorCode = nil
        case .requiresAuthentication:
            state = "requiresAuthentication"
            errorCode = nil
        case .error:
            state = "error"
            errorCode = "refreshFailed"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case state, lastSuccessfulAt, errorCode
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encode(lastSuccessfulAt, forKey: .lastSuccessfulAt)
        try container.encode(errorCode, forKey: .errorCode)
    }
}

private struct SnapshotExportUsage: Encodable {
    let allTime: SnapshotExportUsagePeriod
    let today: SnapshotExportUsagePeriod
    let last7Days: SnapshotExportUsagePeriod
    let last7DaysDaily: [SnapshotExportDailyUsage]
    let last30Days: SnapshotExportUsagePeriod

    init(_ usage: UsageSnapshot) throws {
        allTime = try .init(
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            cacheReadTokens: usage.cacheReadTokens,
            cacheWriteTokens: usage.cacheWriteTokens,
            totalTokens: usage.totalTokens,
            estimatedCostUSD: usage.estimatedCostUSD
        )
        today = try .init(usage.today)
        last7Days = try .init(usage.last7Days)
        last7DaysDaily = usage.last7DaysDaily.map(SnapshotExportDailyUsage.init)
        last30Days = try .init(usage.last30Days)
    }
}

private struct SnapshotExportUsagePeriod: Encodable {
    let inputTokens: String
    let outputTokens: String
    let cacheReadTokens: String
    let cacheWriteTokens: String
    let totalTokens: String
    let estimatedCostUSD: String

    init(
        inputTokens: UInt64,
        outputTokens: UInt64,
        cacheReadTokens: UInt64,
        cacheWriteTokens: UInt64,
        totalTokens: UInt64,
        estimatedCostUSD: Decimal
    ) throws {
        self.inputTokens = String(inputTokens)
        self.outputTokens = String(outputTokens)
        self.cacheReadTokens = String(cacheReadTokens)
        self.cacheWriteTokens = String(cacheWriteTokens)
        self.totalTokens = String(totalTokens)
        self.estimatedCostUSD = try SnapshotExportValidation.canonicalDecimal(estimatedCostUSD)
    }

    init(_ period: UsagePeriod) throws {
        try self.init(
            inputTokens: period.inputTokens,
            outputTokens: period.outputTokens,
            cacheReadTokens: period.cacheReadTokens,
            cacheWriteTokens: period.cacheWriteTokens,
            totalTokens: period.totalTokens,
            estimatedCostUSD: period.estimatedCostUSD
        )
    }
}

private struct SnapshotExportDailyUsage: Encodable {
    let date: String
    let totalTokens: String

    init(_ point: DailyUsagePoint) {
        date = point.date
        totalTokens = String(point.totalTokens)
    }
}

private struct SnapshotExportQuota: Encodable {
    let windows: [SnapshotExportQuotaWindow]

    init(_ quota: QuotaSnapshot) throws {
        windows = quota.windows.map(SnapshotExportQuotaWindow.init)
    }
}

private struct SnapshotExportQuotaWindow: Encodable {
    let id: String
    let usedPercent: Double
    let resetsAt: Date?

    init(_ window: QuotaWindow) {
        id = window.id
        usedPercent = window.usedPercent
        resetsAt = window.resetsAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, usedPercent, resetsAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(usedPercent, forKey: .usedPercent)
        try container.encode(resetsAt, forKey: .resetsAt)
    }
}

private enum SnapshotExportFormat {
    static func encodeTimestamp(_ date: Date, to encoder: Encoder) throws {
        try SnapshotExportValidation.validateTimestamp(date)
        var container = encoder.singleValueContainer()
        try container.encode(timestampString(date))
    }

    static func isExactV1Timestamp(_ date: Date) -> Bool {
        let value = timestampString(date)
        guard value.utf8.count == 24 else { return false }
        let formatter = timestampFormatter()
        formatter.isLenient = false
        guard let parsed = formatter.date(from: value) else { return false }
        return formatter.string(from: parsed) == value
    }

    static func timestampString(_ date: Date) -> String {
        timestampFormatter().string(from: date)
    }

    static func timestampFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter
    }
}
