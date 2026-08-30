import Foundation

public struct SnapshotExporter: Sendable {
    public init() {}

    public func encode(_ capture: ExportCapture) throws -> Data {
        let document = try SnapshotExportDocument(capture: capture)
        var bytes = SnapshotCanonicalJSON.encode(document.canonicalJSONValue)
        bytes.append(0x0A)
        return bytes
    }
}

enum SnapshotCanonicalJSON {
    indirect enum Value: Sendable {
        case null
        case number(String)
        case string(String)
        case array([Value])
        case object([String: Value])
    }

    static func encode(_ value: Value) -> Data {
        var bytes: [UInt8] = []
        append(value, to: &bytes)
        return Data(bytes)
    }

    private static func append(_ value: Value, to bytes: inout [UInt8]) {
        switch value {
        case .null:
            bytes.append(contentsOf: "null".utf8)
        case let .number(value):
            bytes.append(contentsOf: value.utf8)
        case let .string(value):
            appendString(value, to: &bytes)
        case let .array(values):
            bytes.append(0x5B)
            for (index, value) in values.enumerated() {
                if index > 0 {
                    bytes.append(0x2C)
                }
                append(value, to: &bytes)
            }
            bytes.append(0x5D)
        case let .object(values):
            bytes.append(0x7B)
            for (index, key) in values.keys.sorted(by: utf8LexicographicallyPrecedes).enumerated() {
                if index > 0 {
                    bytes.append(0x2C)
                }
                appendString(key, to: &bytes)
                bytes.append(0x3A)
                append(values[key]!, to: &bytes)
            }
            bytes.append(0x7D)
        }
    }

    private static func utf8LexicographicallyPrecedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }

    private static func appendString(_ value: String, to bytes: inout [UInt8]) {
        bytes.append(0x22)
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x08:
                bytes.append(contentsOf: "\\b".utf8)
            case 0x09:
                bytes.append(contentsOf: "\\t".utf8)
            case 0x0A:
                bytes.append(contentsOf: "\\n".utf8)
            case 0x0C:
                bytes.append(contentsOf: "\\f".utf8)
            case 0x0D:
                bytes.append(contentsOf: "\\r".utf8)
            case 0x22:
                bytes.append(contentsOf: "\\\"".utf8)
            case 0x5C:
                bytes.append(contentsOf: "\\\\".utf8)
            case 0 ... 0x1F:
                bytes.append(contentsOf: "\\u00".utf8)
                let hexadecimal = String(scalar.value, radix: 16, uppercase: true)
                if hexadecimal.utf8.count == 1 {
                    bytes.append(0x30)
                }
                bytes.append(contentsOf: hexadecimal.utf8)
            default:
                bytes.append(contentsOf: String(scalar).utf8)
            }
        }
        bytes.append(0x22)
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

private struct SnapshotExportDocument {
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

    var canonicalJSONValue: SnapshotCanonicalJSON.Value {
        .object([
            "schemaVersion": .number("1"),
            "exportedAt": .string(SnapshotExportFormat.timestampString(exportedAt)),
            "providers": .array(providers.map(\.canonicalJSONValue))
        ])
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

private struct SnapshotExportProvider {
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

    var canonicalJSONValue: SnapshotCanonicalJSON.Value {
        .object([
            "provider": .string(provider),
            "usage": usage.canonicalJSONValue,
            "quota": quota.canonicalJSONValue,
            "updatedAt": updatedAt.map { .string(SnapshotExportFormat.timestampString($0)) } ?? .null
        ])
    }
}

private struct SnapshotExportStream<DataValue> {
    let data: DataValue?
    let status: SnapshotExportStatus
}

private extension SnapshotExportStream where DataValue == SnapshotExportUsage {
    var canonicalJSONValue: SnapshotCanonicalJSON.Value {
        .object([
            "data": data.map(\.canonicalJSONValue) ?? .null,
            "status": status.canonicalJSONValue
        ])
    }
}

private extension SnapshotExportStream where DataValue == SnapshotExportQuota {
    var canonicalJSONValue: SnapshotCanonicalJSON.Value {
        .object([
            "data": data.map(\.canonicalJSONValue) ?? .null,
            "status": status.canonicalJSONValue
        ])
    }
}

private struct SnapshotExportStatus {
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

    var canonicalJSONValue: SnapshotCanonicalJSON.Value {
        .object([
            "state": .string(state),
            "lastSuccessfulAt": lastSuccessfulAt.map { .string(SnapshotExportFormat.timestampString($0)) } ?? .null,
            "errorCode": errorCode.map(SnapshotCanonicalJSON.Value.string) ?? .null
        ])
    }
}

private struct SnapshotExportUsage {
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

    var canonicalJSONValue: SnapshotCanonicalJSON.Value {
        .object([
            "allTime": allTime.canonicalJSONValue,
            "today": today.canonicalJSONValue,
            "last7Days": last7Days.canonicalJSONValue,
            "last7DaysDaily": .array(last7DaysDaily.map(\.canonicalJSONValue)),
            "last30Days": last30Days.canonicalJSONValue
        ])
    }
}

private struct SnapshotExportUsagePeriod {
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

    var canonicalJSONValue: SnapshotCanonicalJSON.Value {
        .object([
            "inputTokens": .string(inputTokens),
            "outputTokens": .string(outputTokens),
            "cacheReadTokens": .string(cacheReadTokens),
            "cacheWriteTokens": .string(cacheWriteTokens),
            "totalTokens": .string(totalTokens),
            "estimatedCostUSD": .string(estimatedCostUSD)
        ])
    }
}

private struct SnapshotExportDailyUsage {
    let date: String
    let totalTokens: String

    init(_ point: DailyUsagePoint) {
        date = point.date
        totalTokens = String(point.totalTokens)
    }

    var canonicalJSONValue: SnapshotCanonicalJSON.Value {
        .object([
            "date": .string(date),
            "totalTokens": .string(totalTokens)
        ])
    }
}

private struct SnapshotExportQuota {
    let windows: [SnapshotExportQuotaWindow]

    init(_ quota: QuotaSnapshot) throws {
        windows = quota.windows.map(SnapshotExportQuotaWindow.init)
    }

    var canonicalJSONValue: SnapshotCanonicalJSON.Value {
        .object(["windows": .array(windows.map(\.canonicalJSONValue))])
    }
}

private struct SnapshotExportQuotaWindow {
    let id: String
    let usedPercent: Double
    let resetsAt: Date?

    init(_ window: QuotaWindow) {
        id = window.id
        usedPercent = window.usedPercent
        resetsAt = window.resetsAt
    }

    var canonicalJSONValue: SnapshotCanonicalJSON.Value {
        .object([
            "id": .string(id),
            "usedPercent": .number(SnapshotExportFormat.canonicalPercent(usedPercent)),
            "resetsAt": resetsAt.map { .string(SnapshotExportFormat.timestampString($0)) } ?? .null
        ])
    }
}

private enum SnapshotExportFormat {
    static func canonicalPercent(_ value: Double) -> String {
        guard value != 0 else { return "0" }
        return String(format: "%.17g", locale: Locale(identifier: "en_US_POSIX"), value)
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
