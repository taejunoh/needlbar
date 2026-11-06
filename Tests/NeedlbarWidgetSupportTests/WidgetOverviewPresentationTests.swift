import Foundation
import Testing
@testable import NeedlbarWidgetSupport

@Suite
struct WidgetOverviewPresentationTests {
    // MARK: Formatting

    @Test
    func theCountdownRoundsDownToWholeDaysThenWholeHours() {
        func text(_ seconds: TimeInterval) -> String? {
            WidgetPresentation.countdown(until: referenceDate.addingTimeInterval(seconds), now: referenceDate)?.text
        }
        #expect(text(6 * day + 23 * hour + 59 * minute) == "6d")
        #expect(text(day) == "1d")
        #expect(text(day - 1) == "23h")
        #expect(text(5 * hour + 59 * minute) == "5h")
        #expect(text(hour) == "1h")
        #expect(text(hour - 1) == "<1h")
        #expect(text(1) == "<1h")
        #expect(text(0) == nil)
        #expect(text(-1) == nil)
    }

    @Test
    func theCountdownIsSpokenInWords() {
        #expect(WidgetCountdown.days(1).spokenText == "1 day")
        #expect(WidgetCountdown.days(6).spokenText == "6 days")
        #expect(WidgetCountdown.hours(1).spokenText == "1 hour")
        #expect(WidgetCountdown.hours(5).spokenText == "5 hours")
        #expect(WidgetCountdown.underOneHour.spokenText == "less than 1 hour")
    }

    @Test
    func aResetTooFarAwayHasNoCountdownInsteadOfTrapping() {
        let far = Date(timeIntervalSinceReferenceDate: 1e300)
        #expect(WidgetPresentation.countdown(until: far, now: referenceDate) == nil)
    }

    @Test
    func tokensUseOneDecimalBelowOneHundredUnitsAndRoundDown() {
        let cases: [(UInt64, String)] = [
            (0, "0"), (999, "999"), (1_000, "1.0K"), (1_250, "1.2K"), (99_999, "99.9K"),
            (100_000, "100K"), (999_999, "999K"), (1_000_000, "1.0M"), (878_000_000, "878M"),
            (1_400_000_000, "1.4B"), (999_999_999_999, "999B"), (1_000_000_000_000, "1.0T"),
            (.max, "18446744T"),
        ]
        for (value, expected) in cases {
            #expect(WidgetPresentation.compactTokens(value) == expected)
        }
    }

    @Test
    func costShowsTwoDecimalPlacesWithADollarSign() {
        let cases: [(String, String)] = [
            ("0", "$0.00"), ("1.5", "$1.50"), ("3.75", "$3.75"), ("2.345", "$2.35"),
            ("0.004", "$0.00"), ("226.27", "$226.27"), ("1234.5", "$1234.50"),
        ]
        for (value, expected) in cases {
            #expect(WidgetPresentation.costText(Decimal(string: value)!) == expected)
        }
    }

    @Test
    func theColourLevelChangesBelowTwentyAndBelowTenPercent() {
        #expect(WidgetPresentation.remainingLevel(percent: 100) == .normal)
        #expect(WidgetPresentation.remainingLevel(percent: 20) == .normal)
        #expect(WidgetPresentation.remainingLevel(percent: 19) == .low)
        #expect(WidgetPresentation.remainingLevel(percent: 10) == .low)
        #expect(WidgetPresentation.remainingLevel(percent: 9) == .critical)
        #expect(WidgetPresentation.remainingLevel(percent: 0) == .critical)
    }

    // MARK: Columns

    @Test
    func aFreshColumnShowsTheWindowAndTheCountdown() throws {
        let projection = try overview(claude: quota(.claude, age: minute, headline: weekly(77, resetIn: 6 * day + 3 * hour)))
        #expect(column(.claude, projection) == WidgetQuotaColumn(
            title: "Claude",
            figure: "77%",
            fraction: 0.77,
            level: .normal,
            isDimmed: false,
            detail: "Weekly · resets in 6d",
            accessibilityLabel: "Claude, 77 percent remaining, weekly, resets in 6 days"
        ))
    }

    @Test
    func aFreshColumnWithoutAResetShowsTheWindowAlone() throws {
        let projection = try overview(codex: quota(.codex, age: minute, headline: primary(85, resetIn: nil)))
        #expect(column(.codex, projection) == WidgetQuotaColumn(
            title: "Codex",
            figure: "85%",
            fraction: 0.85,
            level: .normal,
            isDimmed: false,
            detail: "Primary",
            accessibilityLabel: "Codex, 85 percent remaining, primary"
        ))
    }

    @Test
    func aStaleColumnShowsWhenItWasLastCheckedWithTheTimeOnlyToday() throws {
        let claudeAge = 20 * minute
        let projection = try overview(
            claude: quota(.claude, age: claudeAge, headline: weekly(77, resetIn: day)),
            codex: quota(.codex, age: 15 * minute, headline: primary(85, resetIn: day))
        )
        let time = shortText(referenceDate.addingTimeInterval(-claudeAge), includingDate: false)
        #expect(column(.claude, projection) == WidgetQuotaColumn(
            title: "Claude",
            figure: "77%",
            fraction: 0.77,
            level: .normal,
            isDimmed: false,
            detail: "Last checked \(time)",
            accessibilityLabel: "Claude, 77 percent remaining, last checked \(time)"
        ))
        #expect(column(.codex, projection).detail.hasPrefix("Last checked "))

        let justFresh = try overview(codex: quota(.codex, age: 15 * minute - 1, headline: primary(85, resetIn: day)))
        #expect(column(.codex, justFresh).detail == "Primary · resets in 1d")

        let staleStream = try overview(claude: quota(.claude, age: minute, stream: .stale, headline: weekly(77, resetIn: day)))
        #expect(column(.claude, staleStream).detail.hasPrefix("Last checked "))
    }

    @Test
    func aStaleColumnFromAnEarlierDayShowsTheDateAndTime() throws {
        let checkedAt = referenceDate.addingTimeInterval(-9 * hour)
        let projection = try overview(claude: quota(.claude, age: 9 * hour, headline: weekly(77, resetIn: day)))
        let expected = shortText(checkedAt, includingDate: true)
        #expect(expected != shortText(checkedAt, includingDate: false))
        #expect(column(.claude, projection).detail == "Last checked \(expected)")
    }

    @Test
    func aPassedResetDimsTheFigureAndAwaitsAFreshReading() throws {
        let expected = WidgetQuotaColumn(
            title: "Claude",
            figure: "77%",
            fraction: 0.77,
            level: .normal,
            isDimmed: true,
            detail: "Awaiting fresh reading",
            accessibilityLabel: "Claude, 77 percent remaining, awaiting fresh reading"
        )
        let fresh = try overview(claude: quota(.claude, age: minute, headline: weekly(77, resetIn: -1)))
        #expect(column(.claude, fresh) == expected)
        let stale = try overview(claude: quota(.claude, age: hour, headline: weekly(77, resetIn: -1)))
        #expect(column(.claude, stale) == expected)
    }

    @Test
    func noDisplayableValueShowsADashNeverZero() throws {
        let expected = WidgetQuotaColumn(
            title: "Claude",
            figure: "—",
            fraction: nil,
            level: nil,
            isDimmed: false,
            detail: "Quota unavailable",
            accessibilityLabel: "Claude, quota unavailable"
        )
        #expect(column(.claude, nil) == expected)
        #expect(column(.claude, try overview()) == expected)
        let withoutHeadline = try overview(claude: quota(.claude, age: minute, headline: nil))
        #expect(column(.claude, withoutHeadline) == expected)
        let future = try overview(claude: quota(.claude, age: -minute, headline: weekly(77, resetIn: day)))
        #expect(column(.claude, future) == expected)
    }

    @Test
    func theColourLevelFollowsTheShownWholePercent() throws {
        func shown(_ remaining: Double) throws -> (String, WidgetRemainingLevel?) {
            let projection = try overview(claude: quota(.claude, age: minute, headline: weekly(remaining, resetIn: day)))
            let value = column(.claude, projection)
            return (value.figure, value.level)
        }
        #expect(try shown(19.6) == ("20%", .normal))
        #expect(try shown(19.4) == ("19%", .low))
        #expect(try shown(9.5) == ("10%", .low))
        #expect(try shown(9.4) == ("9%", .critical))
    }

    @Test
    func aNonFiniteValueIsUnavailableWithoutReachingTheConversion() throws {
        // A validated projection never carries these, so the row is built directly.
        for bad in [Double.nan, .infinity, -.infinity] {
            let row = try quota(.claude, age: minute, headline: weekly(bad, resetIn: day))
            #expect(WidgetPresentation.quotaStatus(row, now: referenceDate) == .unavailable)
        }
        let over = try quota(.claude, age: minute, headline: weekly(150, resetIn: day))
        #expect(WidgetPresentation.quotaStatus(over, now: referenceDate) == .fresh(weekly(150, resetIn: day)))
    }

    @Test
    func theShownWholePercentIsRoundedAndClampedToZeroThroughOneHundred() {
        #expect(WidgetPresentation.wholePercent(.nan) == nil)
        #expect(WidgetPresentation.wholePercent(.infinity) == nil)
        #expect(WidgetPresentation.wholePercent(-.infinity) == nil)
        #expect(WidgetPresentation.wholePercent(150) == 100)
        #expect(WidgetPresentation.wholePercent(100.4) == 100)
        #expect(WidgetPresentation.wholePercent(-5) == 0)
        #expect(WidgetPresentation.wholePercent(19.6) == 20)
        #expect(WidgetPresentation.wholePercent(9.5) == 10)
        #expect(WidgetPresentation.wholePercent(0) == 0)
    }

    // MARK: Footer

    @Test
    func theFooterSumsOnlyProvidersWhoseTodayIsCurrent() throws {
        let projection = try overview(
            usage: [
                todayUsage(.claude, tokens: 1_234, cost: "1.25"),
                todayUsage(.codex, tokens: 878, cost: "2.50"),
                todayUsage(.cursor, tokens: 5_000, cost: "9.00", on: referenceDate.addingTimeInterval(-day)),
            ],
            today: WidgetTodaySummary(completeness: .complete, totalTokens: 7_112, estimatedCostUSD: Decimal(string: "12.75"))
        )
        #expect(WidgetPresentation.todayFooter(projection, now: referenceDate)
            == WidgetTodayFooter(tokens: "Today 2.1K tokens", cost: "$3.75"))
    }

    @Test
    func theFooterIsHiddenWithoutACurrentContributor() throws {
        #expect(WidgetPresentation.todayFooter(nil, now: referenceDate) == nil)
        #expect(WidgetPresentation.todayFooter(try overview(), now: referenceDate) == nil)
        let yesterdayOnly = try overview(
            usage: [
                todayUsage(.claude, tokens: 10, cost: "1.00", on: referenceDate.addingTimeInterval(-day)),
                noUsage(.codex),
                noUsage(.cursor),
            ],
            today: WidgetTodaySummary(completeness: .partial, totalTokens: 10, estimatedCostUSD: Decimal(string: "1.00"))
        )
        #expect(WidgetPresentation.todayFooter(yesterdayOnly, now: referenceDate) == nil)
    }
}

private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
private let minute: TimeInterval = 60
private let hour: TimeInterval = 3_600
private let day: TimeInterval = 86_400

private let posix = Locale(identifier: "en_US_POSIX")

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func weekly(_ remaining: Double, resetIn seconds: TimeInterval?) -> WidgetQuotaHeadline {
    WidgetQuotaHeadline(id: .claudeWeekly, remainingPercent: remaining, resetsAt: seconds.map { referenceDate.addingTimeInterval($0) })
}

private func primary(_ remaining: Double, resetIn seconds: TimeInterval?) -> WidgetQuotaHeadline {
    WidgetQuotaHeadline(id: .codexPrimary, remainingPercent: remaining, resetsAt: seconds.map { referenceDate.addingTimeInterval($0) })
}

private func quota(
    _ provider: WidgetProvider,
    age: TimeInterval,
    stream: WidgetStreamState = .fresh,
    headline: WidgetQuotaHeadline?
) throws -> WidgetQuotaRow {
    try WidgetQuotaRow(provider: provider, stream: stream, lastSuccessfulAt: referenceDate.addingTimeInterval(-age), headline: headline)
}

private func noUsage(_ provider: WidgetProvider) -> WidgetUsageRow {
    WidgetUsageRow(provider: provider, stream: .unavailable, localDayKey: nil, utcOffsetSeconds: nil, lastSuccessfulAt: nil, todayTokens: nil, todayCostUSD: nil)
}

private func todayUsage(_ provider: WidgetProvider, tokens: UInt64, cost: String, on date: Date = referenceDate) -> WidgetUsageRow {
    let (dayKey, offset) = currentDayAndOffset(date)
    return WidgetUsageRow(provider: provider, stream: .fresh, localDayKey: dayKey, utcOffsetSeconds: offset, lastSuccessfulAt: referenceDate, todayTokens: tokens, todayCostUSD: Decimal(string: cost))
}

private func overview(
    claude: WidgetQuotaRow? = nil,
    codex: WidgetQuotaRow? = nil,
    usage: [WidgetUsageRow]? = nil,
    today: WidgetTodaySummary? = nil
) throws -> WidgetProjection {
    try WidgetProjection(
        quotaRows: [
            try claude ?? WidgetQuotaRow(provider: .claude, stream: .unavailable, lastSuccessfulAt: nil, headline: nil),
            try codex ?? WidgetQuotaRow(provider: .codex, stream: .unavailable, lastSuccessfulAt: nil, headline: nil),
        ],
        usageRows: usage ?? [noUsage(.claude), noUsage(.codex), noUsage(.cursor)],
        today: today ?? WidgetTodaySummary(completeness: .unavailable, totalTokens: nil, estimatedCostUSD: nil)
    )
}

private func column(_ provider: WidgetProvider, _ projection: WidgetProjection?) -> WidgetQuotaColumn {
    WidgetPresentation.quotaColumn(for: provider, in: projection, now: referenceDate, calendar: utc, locale: posix)
}

private func shortText(_ date: Date, includingDate: Bool) -> String {
    let formatter = DateFormatter()
    formatter.calendar = utc
    formatter.timeZone = utc.timeZone
    formatter.locale = posix
    formatter.dateStyle = includingDate ? .short : .none
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

private func currentDayAndOffset(_ date: Date) -> (String, Int) {
    let zone = TimeZone.current
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = zone
    formatter.dateFormat = "yyyy-MM-dd"
    return (formatter.string(from: date), zone.secondsFromGMT(for: date))
}
