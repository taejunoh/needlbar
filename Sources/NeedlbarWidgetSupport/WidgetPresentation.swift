import Foundation

public enum WidgetDisplayFreshness: Equatable, Sendable {
    case fresh
    case stale
    case unavailable
}

public enum WidgetPresentation {
    public static let freshnessHorizon: TimeInterval = 15 * 60

    public static func freshness(
        _ state: WidgetStreamState,
        lastSuccessfulAt: Date?,
        now: Date
    ) -> WidgetDisplayFreshness {
        guard let timestamp = lastSuccessfulAt, timestamp <= now else {
            return .unavailable
        }
        return state == .fresh && now.timeIntervalSince(timestamp) < freshnessHorizon ? .fresh : .stale
    }

    public static func todayIsCurrent(_ row: WidgetUsageRow, now: Date) -> Bool {
        guard let dayKey = row.localDayKey,
              let offset = row.utcOffsetSeconds,
              offset == TimeZone.current.secondsFromGMT(for: now) else {
            return false
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now) == dayKey
    }

    public static func resetLabel(_ reset: Date?, now: Date, formatter: DateFormatter) -> String? {
        guard let reset else { return nil }
        return reset <= now ? "Awaiting fresh reading" : formatter.string(from: reset)
    }

    public static func nextDeadline(
        after now: Date,
        projection: WidgetProjection,
        calendar: Calendar
    ) -> Date {
        let stale = (projection.quotaRows.map(\.lastSuccessfulAt) + projection.usageRows.map(\.lastSuccessfulAt))
            .compactMap { $0?.addingTimeInterval(freshnessHorizon) }
        let reset = projection.quotaRows.compactMap(\.headline?.resetsAt).filter { $0 > now }
        let midnight = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0),
            matchingPolicy: .nextTime
        )!
        return (stale + reset + [midnight]).filter { $0 > now }.min()!
    }
}
