import Foundation

public struct WidgetUsageDayContext: Sendable, Equatable {
    public let dayKey: String
    public let timeZoneIdentifier: String
    public let utcOffsetSeconds: Int

    public init(dayKey: String, timeZoneIdentifier: String, utcOffsetSeconds: Int) {
        self.dayKey = dayKey
        self.timeZoneIdentifier = timeZoneIdentifier
        self.utcOffsetSeconds = utcOffsetSeconds
    }
}

public struct WidgetUsageDayProvenance: Sendable, Equatable {
    public static let maximumInterval: TimeInterval = 5 * 60
    public let startedAt: Date
    public let startedContext: WidgetUsageDayContext
    public let endedAt: Date
    public let endedContext: WidgetUsageDayContext

    public init(startedAt: Date, startedContext: WidgetUsageDayContext, endedAt: Date, endedContext: WidgetUsageDayContext) {
        self.startedAt = startedAt
        self.startedContext = startedContext
        self.endedAt = endedAt
        self.endedContext = endedContext
    }

    public var provenContext: WidgetUsageDayContext? {
        guard endedAt >= startedAt,
              endedAt.timeIntervalSince(startedAt) <= Self.maximumInterval,
              startedContext == endedContext else { return nil }
        return startedContext
    }
}

public protocol WidgetUsageDayCapturing: Sendable {
    func capture(at date: Date) -> WidgetUsageDayContext
}

public struct SystemWidgetUsageDayCapture: WidgetUsageDayCapturing {
    public init() {}

    public func capture(at date: Date) -> WidgetUsageDayContext {
        let zone = TimeZone.current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd"
        return .init(
            dayKey: formatter.string(from: date),
            timeZoneIdentifier: zone.identifier,
            utcOffsetSeconds: zone.secondsFromGMT(for: date)
        )
    }
}

public struct WidgetStoreCapture: Sendable, Equatable {
    public let exportedAt: Date
    public let providers: [WidgetProviderCapture]

    public init(exportedAt: Date, providers: [WidgetProviderCapture]) {
        self.exportedAt = exportedAt
        self.providers = providers
    }
}

public struct WidgetProviderCapture: Sendable, Equatable {
    public let provider: ProviderID
    public let usage: UsageSnapshot?
    public let quota: QuotaSnapshot?
    public let usageStatus: DataStatus
    public let quotaStatus: DataStatus
    public let usageLastSuccessfulAt: Date?
    public let quotaLastSuccessfulAt: Date?
    public let usageDayProvenance: WidgetUsageDayProvenance?

    public init(provider: ProviderID, usage: UsageSnapshot?, quota: QuotaSnapshot?, usageStatus: DataStatus, quotaStatus: DataStatus, usageLastSuccessfulAt: Date?, quotaLastSuccessfulAt: Date?, usageDayProvenance: WidgetUsageDayProvenance?) {
        self.provider = provider
        self.usage = usage
        self.quota = quota
        self.usageStatus = usageStatus
        self.quotaStatus = quotaStatus
        self.usageLastSuccessfulAt = usageLastSuccessfulAt
        self.quotaLastSuccessfulAt = quotaLastSuccessfulAt
        self.usageDayProvenance = usageDayProvenance
    }
}
