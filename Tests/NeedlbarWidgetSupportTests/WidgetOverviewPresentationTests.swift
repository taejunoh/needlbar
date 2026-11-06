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
}

private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
private let minute: TimeInterval = 60
private let hour: TimeInterval = 3_600
private let day: TimeInterval = 86_400
