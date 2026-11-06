import Foundation

public enum WidgetDisplayFreshness: Equatable, Sendable {
    case fresh
    case stale
    case unavailable
}

/// A reset countdown, rounded down: whole days from one day, whole hours from one hour.
public enum WidgetCountdown: Equatable, Sendable {
    case days(Int)
    case hours(Int)
    case underOneHour

    public var text: String {
        switch self {
        case .days(let days): "\(days)d"
        case .hours(let hours): "\(hours)h"
        case .underOneHour: "<1h"
        }
    }

    public var spokenText: String {
        switch self {
        case .days(let days): days == 1 ? "1 day" : "\(days) days"
        case .hours(let hours): hours == 1 ? "1 hour" : "\(hours) hours"
        case .underOneHour: "less than 1 hour"
        }
    }
}

/// The colour of a shown percent. A column without a value has no level and no colour.
public enum WidgetRemainingLevel: Equatable, Sendable {
    case normal
    /// Below 20 percent: system orange.
    case low
    /// Below 10 percent: system red.
    case critical
}


/// What a quota column shows, before any text is made.
public enum WidgetQuotaStatus: Equatable, Sendable {
    case fresh(WidgetQuotaHeadline)
    case stale(WidgetQuotaHeadline, lastCheckedAt: Date)
    case awaitingFreshReading(WidgetQuotaHeadline)
    case unavailable
}

/// Everything the widget draws for one provider column.
public struct WidgetQuotaColumn: Equatable, Sendable {
    public let title: String
    public let figure: String
    /// Bar fill from 0 to 1. `nil` draws an empty track.
    public let fraction: Double?
    /// `nil` means no colour.
    public let level: WidgetRemainingLevel?
    public let isDimmed: Bool
    public let detail: String
    public let accessibilityLabel: String
}

public struct WidgetTodayFooter: Equatable, Sendable {
    public let tokens: String
    public let cost: String
}

public enum WidgetPresentation {
    public static let freshnessHorizon: TimeInterval = 15 * 60
    /// Claude quota can refresh only every 15 minutes, while Codex and usage refresh
    /// every 5, so its row keeps the app's 20-minute window.
    public static let claudeQuotaFreshnessHorizon: TimeInterval = 20 * 60

    private static let secondsPerDay: TimeInterval = 86_400
    private static let secondsPerHour: TimeInterval = 3_600

    private static func quotaHorizon(for provider: WidgetProvider) -> TimeInterval {
        provider == .claude ? claudeQuotaFreshnessHorizon : freshnessHorizon
    }

    public static func freshness(
        _ state: WidgetStreamState,
        lastSuccessfulAt: Date?,
        now: Date,
        horizon: TimeInterval = freshnessHorizon
    ) -> WidgetDisplayFreshness {
        guard let timestamp = lastSuccessfulAt, timestamp <= now else {
            return .unavailable
        }
        return state == .fresh && now.timeIntervalSince(timestamp) < horizon ? .fresh : .stale
    }

    public static func freshness(_ row: WidgetQuotaRow, now: Date) -> WidgetDisplayFreshness {
        freshness(row.stream, lastSuccessfulAt: row.lastSuccessfulAt, now: now, horizon: quotaHorizon(for: row.provider))
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

    // MARK: Formatting

    /// `nil` when the reset is not in the future or is too far away to count.
    public static func countdown(until reset: Date, now: Date) -> WidgetCountdown? {
        let remaining = reset.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        if remaining >= secondsPerDay {
            return Int(exactly: (remaining / secondsPerDay).rounded(.down)).map(WidgetCountdown.days)
        }
        if remaining >= secondsPerHour {
            return .hours(Int((remaining / secondsPerHour).rounded(.down)))
        }
        return .underOneHour
    }

    /// Whole tokens below 1,000; otherwise K, M, B or T with one decimal place below 100
    /// units. Rounded down, so a value never reads as the next unit up.
    public static func compactTokens(_ value: UInt64) -> String {
        let units: [(size: UInt64, suffix: String)] = [
            (1_000_000_000_000, "T"),
            (1_000_000_000, "B"),
            (1_000_000, "M"),
            (1_000, "K"),
        ]
        for unit in units where value >= unit.size {
            let tenths = value / (unit.size / 10)
            return tenths < 1_000
                ? "\(tenths / 10).\(tenths % 10)\(unit.suffix)"
                : "\(value / unit.size)\(unit.suffix)"
        }
        return "\(value)"
    }

    /// Two decimal places with a dollar sign, rounded half up.
    public static func costText(_ cost: Decimal) -> String {
        var value = cost
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        let parts = NSDecimalNumber(decimal: rounded).stringValue
            .split(separator: ".", omittingEmptySubsequences: false)
        let fraction = parts.count > 1 ? String(parts[1]) : ""
        return "$\(parts[0]).\(fraction.padding(toLength: 2, withPad: "0", startingAt: 0))"
    }

    /// Thresholds apply to the whole percent shown, so the colour never disagrees with it.
    public static func remainingLevel(percent: Int) -> WidgetRemainingLevel {
        if percent < 10 { return .critical }
        if percent < 20 { return .low }
        return .normal
    }


    // MARK: Columns and footer

    public static func providerTitle(_ provider: WidgetProvider) -> String {
        switch provider {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }

    public static func quotaStatus(_ row: WidgetQuotaRow?, now: Date) -> WidgetQuotaStatus {
        guard let row,
              let headline = row.headline,
              headline.remainingPercent.isFinite,
              let checkedAt = row.lastSuccessfulAt else {
            return .unavailable
        }
        let state = freshness(row, now: now)
        guard state != .unavailable else { return .unavailable }
        if let reset = headline.resetsAt, reset <= now {
            return .awaitingFreshReading(headline)
        }
        return state == .fresh ? .fresh(headline) : .stale(headline, lastCheckedAt: checkedAt)
    }

    public static func quotaColumn(
        for provider: WidgetProvider,
        in projection: WidgetProjection?,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> WidgetQuotaColumn {
        let title = providerTitle(provider)
        let row = projection?.quotaRows.first { $0.provider == provider }
        let headline: WidgetQuotaHeadline
        let detail: String
        let spokenDetail: String
        var isDimmed = false
        switch quotaStatus(row, now: now) {
        case .unavailable:
            return WidgetQuotaColumn(
                title: title,
                figure: "—",
                fraction: nil,
                level: nil,
                isDimmed: false,
                detail: "Quota unavailable",
                accessibilityLabel: "\(title), quota unavailable"
            )
        case .fresh(let value):
            headline = value
            let window = value.id.categoryLabel
            if let reset = value.resetsAt, let countdown = countdown(until: reset, now: now) {
                detail = "\(window) · resets in \(countdown.text)"
                spokenDetail = "\(window.lowercased()), resets in \(countdown.spokenText)"
            } else {
                detail = window
                spokenDetail = window.lowercased()
            }
        case .stale(let value, let checkedAt):
            headline = value
            let time = lastCheckedTime(checkedAt, now: now, calendar: calendar, locale: locale)
            detail = "Last checked \(time)"
            spokenDetail = "last checked \(time)"
        case .awaitingFreshReading(let value):
            headline = value
            isDimmed = true
            detail = "Awaiting fresh reading"
            spokenDetail = "awaiting fresh reading"
        }
        // `quotaStatus` has already refused a value that is not finite.
        let percent = wholePercent(headline.remainingPercent) ?? 0
        return WidgetQuotaColumn(
            title: title,
            figure: "\(percent)%",
            fraction: min(max(headline.remainingPercent, 0), 100) / 100,
            level: remainingLevel(percent: percent),
            isDimmed: isDimmed,
            detail: detail,
            accessibilityLabel: "\(title), \(percent) percent remaining, \(spokenDetail)"
        )
    }

    /// The whole percent to show, clamped to 0 through 100. `nil` for a value that is not finite.
    static func wholePercent(_ value: Double) -> Int? {
        guard value.isFinite else { return nil }
        return Int(min(max(value, 0), 100).rounded())
    }

    /// The time only when it is the same day as `now`, otherwise the short date and time.
    static func lastCheckedTime(_ checkedAt: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateStyle = calendar.isDate(checkedAt, inSameDayAs: now) ? .none : .short
        formatter.timeStyle = .short
        return formatter.string(from: checkedAt)
    }

    /// Sums the providers whose today total is current. `nil` hides the footer.
    public static func todayFooter(_ projection: WidgetProjection?, now: Date) -> WidgetTodayFooter? {
        guard let projection else { return nil }
        var tokens: UInt64 = 0
        var cost = Decimal.zero
        var contributors = 0
        for row in projection.usageRows where todayIsCurrent(row, now: now) {
            guard let rowTokens = row.todayTokens, let rowCost = row.todayCostUSD else { continue }
            let (next, overflow) = tokens.addingReportingOverflow(rowTokens)
            guard !overflow else { return nil }
            var left = cost
            var right = rowCost
            var sum = Decimal()
            guard NSDecimalAdd(&sum, &left, &right, .plain) == .noError else { return nil }
            tokens = next
            cost = sum
            contributors += 1
        }
        guard contributors > 0 else { return nil }
        return WidgetTodayFooter(tokens: "Today \(compactTokens(tokens)) tokens", cost: costText(cost))
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
        let stale = projection.quotaRows.compactMap { row in
            row.lastSuccessfulAt?.addingTimeInterval(quotaHorizon(for: row.provider))
        } + projection.usageRows.compactMap { $0.lastSuccessfulAt?.addingTimeInterval(freshnessHorizon) }
        let reset = projection.quotaRows.compactMap(\.headline?.resetsAt).filter { $0 > now }
        let midnight = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0),
            matchingPolicy: .nextTime
        )!
        return (stale + reset + [midnight]).filter { $0 > now }.min()!
    }
}
