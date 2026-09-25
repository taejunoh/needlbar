import Foundation
import Testing
@testable import NeedlbarClaudeStatusLineSupport

private let fixedDate = Date(timeIntervalSince1970: 1_790_000_000)
private let generation = UUID(uuidString: "B5F9A622-06B1-4D3D-8FA0-83616B10E3C7")!

private func parse(_ json: String, receivedAt: Date = fixedDate) -> StatusLineQuotaRecord? {
    StatusLineQuotaParser.parse(Data(json.utf8), generation: generation, receivedAt: receivedAt)
}

private func fiveHour(_ used: String, reset: String? = "1790323200") -> String {
    let resetField = reset.map { ",\"resets_at\":\($0)" } ?? ""
    return "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":\(used)\(resetField)}}}"
}

@Test func parserReadsAllowlistedQuotaWindowsAndReceiptTime() {
    let input = Data(#"{"rate_limits":{"five_hour":{"used_percentage":25,"resets_at":1790323200},"seven_day":{"used_percentage":60,"resets_at":1790841600},"fable":{"used_percentage":99}}}"#.utf8)

    let parsed = StatusLineQuotaParser.parse(input, generation: generation, receivedAt: fixedDate)

    #expect(parsed?.fiveHour?.usedPercent == 25)
    #expect(parsed?.sevenDay?.usedPercent == 60)
    #expect(parsed?.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_790_323_200))
    #expect(parsed?.fiveHour?.receivedAt == fixedDate)
    #expect(parsed?.sevenDay?.receivedAt == fixedDate)
    #expect(parsed?.schemaVersion == 1)
    #expect(parsed?.generation == generation)
}

@Test func parserTreatsMissingFableAndQuotaWindowsAsUnavailable() {
    let parsed = parse(#"{"rate_limits":{"five_hour":{"used_percentage":10}}}"#)

    #expect(parsed?.fiveHour?.usedPercent == 10)
    #expect(parsed?.fiveHour?.resetsAt == nil)
    #expect(parsed?.sevenDay == nil)
}

@Test func parserRejectsNullMalformedAndOutOfRangePercentages() {
    let invalidValues = ["null", #""bad""#, "NaN", "1e400", "-0.1", "100.1", "true", "{}"]

    for value in invalidValues {
        #expect(parse(fiveHour(value))?.fiveHour == nil, "Expected unavailable window for used_percentage=\(value)")
    }
}

@Test func parserRejectsMalformedResetSecondsWithoutDiscardingOtherWindow() {
    let malformedResets = [#""1790323200""#, "1790323200.5", "true", "null"]

    for reset in malformedResets {
        let input = Data("{\"rate_limits\":{\"five_hour\":{\"used_percentage\":25,\"resets_at\":\(reset)},\"seven_day\":{\"used_percentage\":60,\"resets_at\":1790841600}}}".utf8)
        let parsed = StatusLineQuotaParser.parse(input, generation: generation, receivedAt: fixedDate)
        #expect(parsed?.fiveHour == nil, "Expected five-hour rejection for resets_at=\(reset)")
        #expect(parsed?.sevenDay?.usedPercent == 60)
    }
}

@Test func parserRejectsInputLargerThan256KiB() {
    let input = Data(repeating: 0x20, count: 256 * 1024 + 1)

    #expect(StatusLineQuotaParser.parse(input, generation: generation, receivedAt: fixedDate) == nil)
}

@Test func mergerAppliesFiveHourOnlyUpdatesWithoutChangingSevenDayTimestamp() {
    let existing = parse(#"{"rate_limits":{"five_hour":{"used_percentage":25,"resets_at":1790323200},"seven_day":{"used_percentage":60,"resets_at":1790841600}}}"#)!
    let later = fixedDate.addingTimeInterval(30)
    let incoming = parse(#"{"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":1790323200}}}"#, receivedAt: later)!

    let merged = StatusLineQuotaMerger.merge(existing: existing, incoming: incoming)

    #expect(merged.fiveHour?.usedPercent == 30)
    #expect(merged.fiveHour?.receivedAt == later)
    #expect(merged.sevenDay == existing.sevenDay)
}

@Test func mergerIdenticalReplayDoesNotAdvanceReceiptTime() {
    let existing = parse(fiveHour("25"))!
    let incoming = parse(fiveHour("25"), receivedAt: fixedDate.addingTimeInterval(60))!

    let merged = StatusLineQuotaMerger.merge(existing: existing, incoming: incoming)

    #expect(merged.fiveHour == existing.fiveHour)
}

@Test func mergerRejectsOlderReset() {
    let existing = parse(fiveHour("25", reset: "1790323200"))!
    let incoming = parse(fiveHour("90", reset: "1790323199"), receivedAt: fixedDate.addingTimeInterval(60))!

    let merged = StatusLineQuotaMerger.merge(existing: existing, incoming: incoming)

    #expect(merged.fiveHour == existing.fiveHour)
}

@Test func mergerRejectsSmallerUsedPercentageAtSameReset() {
    let existing = parse(fiveHour("25"))!
    let incoming = parse(fiveHour("20"), receivedAt: fixedDate.addingTimeInterval(60))!

    let merged = StatusLineQuotaMerger.merge(existing: existing, incoming: incoming)

    #expect(merged.fiveHour == existing.fiveHour)
}

@Test func mergerAcceptsChangedNonregressingObservationWithNewReceiptTime() {
    let existing = parse(fiveHour("25"))!
    let later = fixedDate.addingTimeInterval(60)
    let incoming = parse(fiveHour("30"), receivedAt: later)!

    let merged = StatusLineQuotaMerger.merge(existing: existing, incoming: incoming)

    #expect(merged.fiveHour?.usedPercent == 30)
    #expect(merged.fiveHour?.receivedAt == later)
}

@Test func mergerTreatsUndatedWindowsConservatively() {
    let existing = parse(fiveHour("25", reset: nil))!
    let later = fixedDate.addingTimeInterval(60)
    let smaller = parse(fiveHour("20", reset: nil), receivedAt: later)!
    let larger = parse(fiveHour("30", reset: nil), receivedAt: later)!

    let rejected = StatusLineQuotaMerger.merge(existing: existing, incoming: smaller)
    let accepted = StatusLineQuotaMerger.merge(existing: existing, incoming: larger)

    #expect(rejected.fiveHour == existing.fiveHour)
    #expect(accepted.fiveHour?.usedPercent == 30)
    #expect(accepted.fiveHour?.receivedAt == later)
}

@Test func mergerAcceptsAResetAdvanceEvenWhenUsedPercentageFalls() {
    let existing = parse(fiveHour("80", reset: "1790323200"))!
    let later = fixedDate.addingTimeInterval(60)
    let incoming = parse(fiveHour("10", reset: "1790323201"), receivedAt: later)!

    let merged = StatusLineQuotaMerger.merge(existing: existing, incoming: incoming)

    #expect(merged.fiveHour?.usedPercent == 10)
    #expect(merged.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_790_323_201))
    #expect(merged.fiveHour?.receivedAt == later)
}
