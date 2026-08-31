import Foundation
import Testing
@testable import NeedlbarWidgetSupport

@Suite
struct WidgetProjectionTests {
    @Test
    func rejectsUnknownSchemaAndUnsafeQuotaIdentity() {
        let bytes = Data("{\"schemaVersion\":2,\"quotaRows\":[],\"usageRows\":[],\"today\":null}".utf8)
        #expect(throws: WidgetProjectionError.unsupportedSchema) {
            try WidgetProjection.decode(bytes, referenceDate: Date(timeIntervalSince1970: 1_800_000_000))
        }
        #expect(throws: WidgetProjectionError.invalidQuotaRow) {
            try WidgetQuotaRow(
                provider: .cursor,
                stream: .unavailable,
                lastSuccessfulAt: nil,
                headline: nil
            )
        }
    }

    @Test
    func rejectsForeignNestedProviderAndWindowIdentitiesAtDocumentBoundary() {
        let foreignProvider = Data("""
        {"schemaVersion":1,"quotaRows":[{"provider":"evil","stream":"fresh","lastSuccessfulAt":null,"headline":null},{"provider":"codex","stream":"unavailable","lastSuccessfulAt":null,"headline":null}],"usageRows":[],"today":{"completeness":"unavailable","totalTokens":null,"estimatedCostUSD":null}}
        """.utf8)
        let foreignWindow = Data("""
        {"schemaVersion":1,"quotaRows":[{"provider":"claude","stream":"fresh","lastSuccessfulAt":null,"headline":{"id":"evil.window","remainingPercent":10,"resetsAt":null}},{"provider":"codex","stream":"unavailable","lastSuccessfulAt":null,"headline":null}],"usageRows":[],"today":{"completeness":"unavailable","totalTokens":null,"estimatedCostUSD":null}}
        """.utf8)

        #expect(throws: WidgetProjectionError.invalidQuotaRow) {
            try WidgetProjection.decode(foreignProvider, referenceDate: referenceDate)
        }
        #expect(throws: WidgetProjectionError.invalidQuotaRow) {
            try WidgetProjection.decode(foreignWindow, referenceDate: referenceDate)
        }

        let foreignUsage = Data("""
        {"schemaVersion":1,"quotaRows":[{"provider":"claude","stream":"unavailable","lastSuccessfulAt":null,"headline":null},{"provider":"codex","stream":"unavailable","lastSuccessfulAt":null,"headline":null}],"usageRows":[{"provider":"evil","stream":"unavailable","localDayKey":null,"utcOffsetSeconds":null,"lastSuccessfulAt":null,"todayTokens":null,"todayCostUSD":null},{"provider":"codex","stream":"unavailable","localDayKey":null,"utcOffsetSeconds":null,"lastSuccessfulAt":null,"todayTokens":null,"todayCostUSD":null},{"provider":"cursor","stream":"unavailable","localDayKey":null,"utcOffsetSeconds":null,"lastSuccessfulAt":null,"todayTokens":null,"todayCostUSD":null}],"today":{"completeness":"unavailable","totalTokens":null,"estimatedCostUSD":null}}
        """.utf8)
        #expect(throws: WidgetProjectionError.invalidUsageRow) {
            try WidgetProjection.decode(foreignUsage, referenceDate: referenceDate)
        }
    }

    @Test
    func enforcesFixedProviderOrderAndUsageIdentity() throws {
        let projection = try makeProjection()
        #expect(projection.quotaRows.map(\.provider) == [.claude, .codex])
        #expect(projection.usageRows.map(\.provider) == WidgetProvider.allCases)

        let reordered = Data("""
        {"schemaVersion":1,"quotaRows":[{"provider":"codex","stream":"unavailable","lastSuccessfulAt":null,"headline":null},{"provider":"claude","stream":"unavailable","lastSuccessfulAt":null,"headline":null}],"usageRows":[{"provider":"claude","stream":"unavailable","localDayKey":null,"utcOffsetSeconds":null,"lastSuccessfulAt":null,"todayTokens":null,"todayCostUSD":null},{"provider":"codex","stream":"unavailable","localDayKey":null,"utcOffsetSeconds":null,"lastSuccessfulAt":null,"todayTokens":null,"todayCostUSD":null},{"provider":"cursor","stream":"unavailable","localDayKey":null,"utcOffsetSeconds":null,"lastSuccessfulAt":null,"todayTokens":null,"todayCostUSD":null}],"today":{"completeness":"unavailable","totalTokens":null,"estimatedCostUSD":null}}
        """.utf8)
        #expect(throws: WidgetProjectionError.invalidProviderOrder) {
            try WidgetProjection.decode(reordered, referenceDate: referenceDate)
        }
    }

    @Test
    func rejectsInvalidQuotaPercentageAndFutureTimestamp() {
        let now = referenceDate
        let invalidPercent = try? WidgetQuotaRow(
            provider: .claude,
            stream: .fresh,
            lastSuccessfulAt: now,
            headline: WidgetQuotaHeadline(id: .claudeSession, remainingPercent: 101, resetsAt: nil)
        )
        let validCodex = try? WidgetQuotaRow(provider: .codex, stream: .unavailable, lastSuccessfulAt: nil, headline: nil)
        let usage = makeUnavailableUsageRows()
        #expect(throws: WidgetProjectionError.invalidQuotaRow) {
            try WidgetProjection(
                quotaRows: [try #require(invalidPercent), try #require(validCodex)],
                usageRows: usage,
                today: unavailableToday
            )
        }

        let future = Data("""
        {"schemaVersion":1,"quotaRows":[{"provider":"claude","stream":"fresh","lastSuccessfulAt":"2027-01-15T08:00:01Z","headline":null},{"provider":"codex","stream":"unavailable","lastSuccessfulAt":null,"headline":null}],"usageRows":[{"provider":"claude","stream":"unavailable","localDayKey":null,"utcOffsetSeconds":null,"lastSuccessfulAt":null,"todayTokens":null,"todayCostUSD":null},{"provider":"codex","stream":"unavailable","localDayKey":null,"utcOffsetSeconds":null,"lastSuccessfulAt":null,"todayTokens":null,"todayCostUSD":null},{"provider":"cursor","stream":"unavailable","localDayKey":null,"utcOffsetSeconds":null,"lastSuccessfulAt":null,"todayTokens":null,"todayCostUSD":null}],"today":{"completeness":"unavailable","totalTokens":null,"estimatedCostUSD":null}}
        """.utf8)
        #expect(throws: WidgetProjectionError.invalidTimestamp) {
            try WidgetProjection.decode(future, referenceDate: now)
        }
    }

    @Test
    func rejectsInvalidUsageDayOffsetAndCost() throws {
        let invalidDay = WidgetUsageRow(provider: .claude, stream: .fresh, localDayKey: "2027-02-30", utcOffsetSeconds: 0, lastSuccessfulAt: referenceDate, todayTokens: 1, todayCostUSD: Decimal(string: "1")!)
        #expect(throws: WidgetProjectionError.invalidDay) {
            try WidgetProjection(quotaRows: try makeQuotaRows(), usageRows: [invalidDay, unavailableUsage(.codex), unavailableUsage(.cursor)], today: partialToday(tokens: 1, cost: "1"))
        }

        let invalidOffset = WidgetUsageRow(provider: .claude, stream: .fresh, localDayKey: "2027-01-15", utcOffsetSeconds: 50_401, lastSuccessfulAt: referenceDate, todayTokens: 1, todayCostUSD: Decimal(string: "1")!)
        #expect(throws: WidgetProjectionError.invalidUsageRow) {
            try WidgetProjection(quotaRows: try makeQuotaRows(), usageRows: [invalidOffset, unavailableUsage(.codex), unavailableUsage(.cursor)], today: partialToday(tokens: 1, cost: "1"))
        }

        let invalidCost = WidgetUsageRow(provider: .claude, stream: .fresh, localDayKey: "2027-01-15", utcOffsetSeconds: 0, lastSuccessfulAt: referenceDate, todayTokens: 1, todayCostUSD: Decimal(string: "-0.01")!)
        #expect(throws: WidgetProjectionError.invalidUsageRow) {
            try WidgetProjection(quotaRows: try makeQuotaRows(), usageRows: [invalidCost, unavailableUsage(.codex), unavailableUsage(.cursor)], today: partialToday(tokens: 1, cost: "-0.01"))
        }
    }

    @Test
    func enforcesCheckedAggregateAndDistinguishesUnavailableFromRealZero() throws {
        let zero = try WidgetProjection(
            quotaRows: try makeQuotaRows(),
            usageRows: [usage(.claude, tokens: 0, cost: "0"), unavailableUsage(.codex), unavailableUsage(.cursor)],
            today: partialToday(tokens: 0, cost: "0")
        )
        #expect(zero.today.totalTokens == 0)
        #expect(zero.today.estimatedCostUSD == Decimal.zero)

        let unavailable = try makeProjection()
        #expect(unavailable.today.completeness == .unavailable)
        #expect(unavailable.today.totalTokens == nil)

        #expect(throws: WidgetProjectionError.invalidTodaySummary) {
            try WidgetProjection(
                quotaRows: try makeQuotaRows(),
                usageRows: [usage(.claude, tokens: .max), usage(.codex, tokens: 1), unavailableUsage(.cursor)],
                today: WidgetTodaySummary(completeness: .partial, totalTokens: nil, estimatedCostUSD: nil)
            )
        }

        let decimalAggregate = try WidgetProjection(
            quotaRows: try makeQuotaRows(),
            usageRows: [
                usage(.claude, tokens: 1, cost: "1.25"),
                usage(.codex, tokens: 1, cost: "2.50"),
                unavailableUsage(.cursor),
            ],
            today: partialToday(tokens: 2, cost: "3.75")
        )
        #expect(decimalAggregate.today.estimatedCostUSD == Decimal(string: "3.75"))
    }

    @Test
    func rejectsOversizeDocumentsAndKeepsStableSanitizedEncoding() throws {
        let oversize = Data(repeating: 0x20, count: WidgetProjection.maximumEncodedBytes + 1)
        #expect(throws: WidgetProjectionError.tooLarge) {
            try WidgetProjection.decode(oversize, referenceDate: referenceDate)
        }

        let projection = try WidgetProjection(
            quotaRows: try makeQuotaRows(),
            usageRows: [usage(.claude, tokens: 12, cost: "1.25"), unavailableUsage(.codex), unavailableUsage(.cursor)],
            today: partialToday(tokens: 12, cost: "1.25")
        )
        let first = try WidgetProjection.encode(projection)
        let second = try WidgetProjection.encode(projection)
        #expect(first == second)
        let encoded = String(decoding: first, as: UTF8.self)
        for forbidden in ["title", "message", "accountId", "prompt", "response", "sourceCode", "cookie", "credential", "path"] {
            #expect(!encoded.contains(forbidden))
        }
    }

    @Test
    func exactlyFifteenMinutesOldFreshValueIsStale() {
        let now = referenceDate
        #expect(WidgetPresentation.freshness(.fresh, lastSuccessfulAt: now.addingTimeInterval(-WidgetPresentation.freshnessHorizon), now: now) == .stale)
        #expect(WidgetPresentation.freshness(.fresh, lastSuccessfulAt: now.addingTimeInterval(-WidgetPresentation.freshnessHorizon + 1), now: now) == .fresh)
        #expect(WidgetPresentation.freshness(.fresh, lastSuccessfulAt: nil, now: now) == .unavailable)
    }

    @Test
    func passedResetUsesFixedAwaitingFreshReadingLabel() {
        let formatter = DateFormatter()
        #expect(WidgetPresentation.resetLabel(referenceDate.addingTimeInterval(-1), now: referenceDate, formatter: formatter) == "Awaiting fresh reading")
        #expect(WidgetPresentation.resetLabel(nil, now: referenceDate, formatter: formatter) == nil)
    }

    @Test
    func todayIsCurrentRejectsPreviousLocalGregorianDay() {
        let previous = Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: referenceDate)!
        let (day, offset) = currentWidgetDayAndOffset(previous)
        let row = WidgetUsageRow(provider: .claude, stream: .fresh, localDayKey: day, utcOffsetSeconds: offset, lastSuccessfulAt: referenceDate, todayTokens: 4, todayCostUSD: Decimal(string: "1.00"))
        #expect(!WidgetPresentation.todayIsCurrent(row, now: referenceDate))
    }

    @Test
    func todayIsCurrentAcceptsCurrentLocalGregorianDayAndOffset() {
        let (day, offset) = currentWidgetDayAndOffset(referenceDate)
        let row = WidgetUsageRow(provider: .claude, stream: .fresh, localDayKey: day, utcOffsetSeconds: offset, lastSuccessfulAt: referenceDate, todayTokens: 4, todayCostUSD: Decimal(string: "1.00"))
        #expect(WidgetPresentation.todayIsCurrent(row, now: referenceDate))
    }

    @Test
    func staleContributorRemainsInPartialTodayAggregate() throws {
        let projection = try WidgetProjection(
            quotaRows: try makeQuotaRows(),
            usageRows: [usage(.claude, tokens: 10, stream: .stale), unavailableUsage(.codex), unavailableUsage(.cursor)],
            today: partialToday(tokens: 10, cost: "1.00")
        )
        #expect(projection.today.totalTokens == 10)
        #expect(WidgetPresentation.freshness(.stale, lastSuccessfulAt: referenceDate, now: referenceDate) == .stale)
    }
}

private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

private var unavailableToday: WidgetTodaySummary {
    WidgetTodaySummary(completeness: .unavailable, totalTokens: nil, estimatedCostUSD: nil)
}

private func makeProjection() throws -> WidgetProjection {
    try WidgetProjection(quotaRows: makeQuotaRows(), usageRows: makeUnavailableUsageRows(), today: unavailableToday)
}

private func makeQuotaRows() throws -> [WidgetQuotaRow] {
    [
        try WidgetQuotaRow(provider: .claude, stream: .unavailable, lastSuccessfulAt: nil, headline: nil),
        try WidgetQuotaRow(provider: .codex, stream: .unavailable, lastSuccessfulAt: nil, headline: nil),
    ]
}

private func makeUnavailableUsageRows() -> [WidgetUsageRow] {
    [.init(provider: .claude, stream: .unavailable, localDayKey: nil, utcOffsetSeconds: nil, lastSuccessfulAt: nil, todayTokens: nil, todayCostUSD: nil), unavailableUsage(.codex), unavailableUsage(.cursor)]
}

private func unavailableUsage(_ provider: WidgetProvider) -> WidgetUsageRow {
    WidgetUsageRow(provider: provider, stream: .unavailable, localDayKey: nil, utcOffsetSeconds: nil, lastSuccessfulAt: nil, todayTokens: nil, todayCostUSD: nil)
}

private func usage(_ provider: WidgetProvider, tokens: UInt64, cost: String = "1.00", stream: WidgetStreamState = .fresh) -> WidgetUsageRow {
    WidgetUsageRow(provider: provider, stream: stream, localDayKey: "2027-01-15", utcOffsetSeconds: 0, lastSuccessfulAt: referenceDate, todayTokens: tokens, todayCostUSD: Decimal(string: cost))
}

private func partialToday(tokens: UInt64, cost: String) -> WidgetTodaySummary {
    WidgetTodaySummary(completeness: .partial, totalTokens: tokens, estimatedCostUSD: Decimal(string: cost))
}

private func currentWidgetDayAndOffset(_ date: Date) -> (String, Int) {
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
