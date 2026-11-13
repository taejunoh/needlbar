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
    func rejectsQuotaHeadlineWithoutLastGoodTimestamp() {
        let incoherent = Data("""
        {"schemaVersion":1,"quotaRows":[{"provider":"claude","stream":"unavailable","lastSuccessfulAt":null,"headline":{"id":"claude.session","remainingPercent":50,"resetsAt":null}},{"provider":"codex","stream":"unavailable","lastSuccessfulAt":null,"headline":null}],"usageRows":[{"provider":"claude","stream":"unavailable","localDayKey":null,"utcOffsetSeconds":null,"lastSuccessfulAt":null,"todayTokens":null,"todayCostUSD":null},{"provider":"codex","stream":"unavailable","localDayKey":null,"utcOffsetSeconds":null,"lastSuccessfulAt":null,"todayTokens":null,"todayCostUSD":null},{"provider":"cursor","stream":"unavailable","localDayKey":null,"utcOffsetSeconds":null,"lastSuccessfulAt":null,"todayTokens":null,"todayCostUSD":null}],"today":{"completeness":"unavailable","totalTokens":null,"estimatedCostUSD":null}}
        """.utf8)

        #expect(throws: WidgetProjectionError.invalidQuotaRow) {
            try WidgetProjection.decode(incoherent, referenceDate: referenceDate)
        }

        let staleLastGood = Data("""
        {"schemaVersion":1,"quotaRows":[{"provider":"claude","stream":"stale","lastSuccessfulAt":"2027-01-15T08:00:00Z","headline":{"id":"claude.session","remainingPercent":50,"resetsAt":null}},{"provider":"codex","stream":"unavailable","lastSuccessfulAt":null,"headline":null}],"usageRows":[{"provider":"claude","stream":"unavailable","localDayKey":null,"utcOffsetSeconds":null,"lastSuccessfulAt":null,"todayTokens":null,"todayCostUSD":null},{"provider":"codex","stream":"unavailable","localDayKey":null,"utcOffsetSeconds":null,"lastSuccessfulAt":null,"todayTokens":null,"todayCostUSD":null},{"provider":"cursor","stream":"unavailable","localDayKey":null,"utcOffsetSeconds":null,"lastSuccessfulAt":null,"todayTokens":null,"todayCostUSD":null}],"today":{"completeness":"unavailable","totalTokens":null,"estimatedCostUSD":null}}
        """.utf8)
        let projection = try? WidgetProjection.decode(staleLastGood, referenceDate: referenceDate)
        #expect(projection?.quotaRows[0].headline?.remainingPercent == 50)
        #expect(projection?.quotaRows[0].lastSuccessfulAt == referenceDate)
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
    func fractionalRFC3339DatesRoundTripAtTheExactFreshnessBoundary() throws {
        let successfulAt = Date(timeIntervalSince1970: 1_800_000_000.123_456_7)
        let resetsAt = Date(timeIntervalSince1970: 1_800_003_600.765_432_1)
        let projection = try WidgetProjection(
            quotaRows: [
                try WidgetQuotaRow(
                    provider: .claude,
                    stream: .fresh,
                    lastSuccessfulAt: successfulAt,
                    headline: WidgetQuotaHeadline(id: .claudeSession, remainingPercent: 50, resetsAt: resetsAt)
                ),
                try WidgetQuotaRow(provider: .codex, stream: .unavailable, lastSuccessfulAt: nil, headline: nil),
            ],
            usageRows: makeUnavailableUsageRows(),
            today: unavailableToday
        )

        let encoded = try WidgetProjection.encode(projection)
        let exactBoundary = successfulAt.addingTimeInterval(WidgetPresentation.freshnessHorizon)
        let decoded = try WidgetProjection.decode(encoded, referenceDate: exactBoundary)
        let decodedHeadline = try #require(decoded.quotaRows[0].headline)

        #expect(decoded.quotaRows[0].lastSuccessfulAt == successfulAt)
        #expect(decodedHeadline.resetsAt == resetsAt)
        #expect(WidgetPresentation.freshness(.fresh, lastSuccessfulAt: decoded.quotaRows[0].lastSuccessfulAt, now: exactBoundary.addingTimeInterval(-0.001)) == .fresh)
        #expect(WidgetPresentation.freshness(.fresh, lastSuccessfulAt: decoded.quotaRows[0].lastSuccessfulAt, now: exactBoundary) == .stale)
    }

    @Test
    func exactlyFifteenMinutesOldFreshValueIsStale() {
        let now = referenceDate
        #expect(WidgetPresentation.freshness(.fresh, lastSuccessfulAt: now.addingTimeInterval(-WidgetPresentation.freshnessHorizon), now: now) == .stale)
        #expect(WidgetPresentation.freshness(.fresh, lastSuccessfulAt: now.addingTimeInterval(-WidgetPresentation.freshnessHorizon + 1), now: now) == .fresh)
        #expect(WidgetPresentation.freshness(.fresh, lastSuccessfulAt: nil, now: now) == .unavailable)
    }

    @Test
    func aClaudeQuotaRowStaysFreshForTwentyMinutesAndOthersForFifteen() throws {
        let now = referenceDate
        func quotaRow(_ provider: WidgetProvider, age: TimeInterval) throws -> WidgetQuotaRow {
            try WidgetQuotaRow(provider: provider, stream: .fresh, lastSuccessfulAt: now.addingTimeInterval(-age), headline: nil)
        }
        #expect(WidgetPresentation.freshness(try quotaRow(.claude, age: 1_199), now: now) == .fresh)
        #expect(WidgetPresentation.freshness(try quotaRow(.claude, age: 1_200), now: now) == .stale)
        #expect(WidgetPresentation.freshness(try quotaRow(.codex, age: 899), now: now) == .fresh)
        #expect(WidgetPresentation.freshness(try quotaRow(.codex, age: 900), now: now) == .stale)
    }

    @Test
    func theNextDeadlineUsesTheClaudeQuotaRowsOwnHorizon() throws {
        let projection = try WidgetProjection(
            quotaRows: [
                try WidgetQuotaRow(provider: .claude, stream: .fresh, lastSuccessfulAt: referenceDate, headline: nil),
                try WidgetQuotaRow(provider: .codex, stream: .unavailable, lastSuccessfulAt: nil, headline: nil),
            ],
            usageRows: makeUnavailableUsageRows(),
            today: unavailableToday
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(WidgetPresentation.nextDeadline(after: referenceDate, projection: projection, calendar: calendar)
            == referenceDate.addingTimeInterval(1_200))
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

    // MARK: Fable reading

    @Test
    func aFableReadingRoundTripsWithAndWithoutAReset() throws {
        let readings = [
            WidgetFableReading(remainingPercent: 71.5, resetsAt: referenceDate.addingTimeInterval(3_600)),
            WidgetFableReading(remainingPercent: 71.5, resetsAt: nil),
        ]
        for reading in readings {
            let projection = try fableProjection(claude: claudeRow(fable: reading))
            let decoded = try WidgetProjection.decode(WidgetProjection.encode(projection), referenceDate: referenceDate)
            #expect(decoded == projection)
            #expect(decoded.quotaRows[0].fable == reading)
            #expect(decoded.quotaRows[1].fable == nil)

            // The row's own coding, which the projection decoder does not use.
            let row = try JSONDecoder().decode(WidgetQuotaRow.self, from: JSONEncoder().encode(projection.quotaRows[0]))
            #expect(row.fable == reading)
        }
    }

    @Test
    func aFileWithoutFableOrWithANullFableDecodesAsNoValue() throws {
        let withoutKey = try WidgetProjection.decode(document(), referenceDate: referenceDate)
        #expect(withoutKey.quotaRows[0].fable == nil)
        #expect(withoutKey.quotaRows[0].headline?.remainingPercent == 77)

        let null = try WidgetProjection.decode(document(claude: claudeRowJSON + ",\"fable\":null"), referenceDate: referenceDate)
        #expect(null.quotaRows[0].fable == nil)

        let present = try WidgetProjection.decode(document(claude: claudeRowJSON + fableJSON), referenceDate: referenceDate)
        #expect(present.quotaRows[0].fable
            == WidgetFableReading(remainingPercent: 71, resetsAt: referenceDate.addingTimeInterval(3_600)))
    }

    /// Schema version 1 is kept on the strength of this: a reader ignores a key it does not know.
    @Test
    func anUnknownKeyOnAQuotaRowIsIgnored() throws {
        let extraKeys = ",\"later\":{\"remainingPercent\":5},\"fable\":{\"remainingPercent\":71,\"resetsAt\":null,\"label\":\"x\"}"
        let decoded = try WidgetProjection.decode(document(claude: claudeRowJSON + extraKeys), referenceDate: referenceDate)
        #expect(decoded.quotaRows[0].headline?.remainingPercent == 77)
        #expect(decoded.quotaRows[0].fable == WidgetFableReading(remainingPercent: 71, resetsAt: nil))

        let row = try JSONDecoder().decode(
            WidgetQuotaRow.self,
            from: Data(#"{"provider":"claude","stream":"fresh","lastSuccessfulAt":0,"later":1,"fable":{"remainingPercent":71,"label":"x"}}"#.utf8)
        )
        #expect(row.fable == WidgetFableReading(remainingPercent: 71, resetsAt: nil))
    }

    @Test
    func aProjectionWithoutFableEncodesExactlyAsBefore() throws {
        let projection = try fableProjection(claude: claudeRow(fable: nil))
        let encoded = String(decoding: try WidgetProjection.encode(projection), as: UTF8.self)
        #expect(!encoded.contains("fable"))
        // The bytes the code before this change wrote for the same projection.
        #expect(encoded == #"{"quotaRows":[{"headline":{"id":"claude.weekly","remainingPercent":77},"lastSuccessfulAt":"2027-01-15T08:00:00Z","provider":"claude","stream":"fresh"},{"provider":"codex","stream":"unavailable"}],"schemaVersion":1,"today":{"completeness":"unavailable"},"usageRows":[{"provider":"claude","stream":"unavailable"},{"provider":"codex","stream":"unavailable"},{"provider":"cursor","stream":"unavailable"}]}"#)

        let withFable = try fableProjection(claude: claudeRow(fable: WidgetFableReading(remainingPercent: 71, resetsAt: nil)))
        #expect(String(decoding: try WidgetProjection.encode(withFable), as: UTF8.self)
            .contains(#""fable":{"remainingPercent":71},"headline""#))
    }

    @Test
    func fableIsRejectedOffTheClaudeRowOutOfRangeOrWithoutALastSuccessfulTime() {
        let valid = WidgetFableReading(remainingPercent: 71, resetsAt: nil)
        #expect(throws: WidgetProjectionError.invalidQuotaRow) {
            try WidgetQuotaRow(provider: .codex, stream: .fresh, lastSuccessfulAt: referenceDate, headline: nil, fable: valid)
        }
        #expect(throws: WidgetProjectionError.invalidQuotaRow) {
            try WidgetQuotaRow(provider: .claude, stream: .unavailable, lastSuccessfulAt: nil, headline: nil, fable: valid)
        }
        for percent in [101, -1, Double.nan, .infinity] {
            #expect(throws: WidgetProjectionError.invalidQuotaRow) {
                try claudeRow(fable: WidgetFableReading(remainingPercent: percent, resetsAt: nil))
            }
        }
        for reset in [Double.nan, .infinity, -.infinity] {
            #expect(throws: WidgetProjectionError.invalidQuotaRow) {
                try claudeRow(fable: WidgetFableReading(remainingPercent: 71, resetsAt: Date(timeIntervalSinceReferenceDate: reset)))
            }
        }
    }

    @Test
    func aFileWithAnInvalidFableIsRejectedLikeAnyOtherInvalidRow() {
        let onCodex = document(codex: codexRowJSON + fableJSON)
        let tooHigh = document(claude: claudeRowJSON + ",\"fable\":{\"remainingPercent\":101,\"resetsAt\":null}")
        let negative = document(claude: claudeRowJSON + ",\"fable\":{\"remainingPercent\":-1,\"resetsAt\":null}")
        let withoutLastSuccess = document(
            claude: #""provider":"claude","stream":"unavailable","lastSuccessfulAt":null,"headline":null"# + fableJSON
        )
        for bytes in [onCodex, tooHigh, negative, withoutLastSuccess] {
            #expect(throws: WidgetProjectionError.invalidQuotaRow) {
                try WidgetProjection.decode(bytes, referenceDate: referenceDate)
            }
        }
    }

    @Test
    func aStaleRowKeepsItsFable() throws {
        let reading = WidgetFableReading(remainingPercent: 0, resetsAt: referenceDate.addingTimeInterval(-60))
        let projection = try fableProjection(claude: claudeRow(stream: .stale, fable: reading))
        let decoded = try WidgetProjection.decode(WidgetProjection.encode(projection), referenceDate: referenceDate)
        #expect(decoded.quotaRows[0].stream == .stale)
        #expect(decoded.quotaRows[0].fable == reading)
        #expect(WidgetFableReading(remainingPercent: 100, resetsAt: nil).isValid(for: .claude, lastSuccessfulAt: referenceDate))
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

private func claudeRow(stream: WidgetStreamState = .fresh, fable: WidgetFableReading?) throws -> WidgetQuotaRow {
    try WidgetQuotaRow(
        provider: .claude,
        stream: stream,
        lastSuccessfulAt: referenceDate,
        headline: WidgetQuotaHeadline(id: .claudeWeekly, remainingPercent: 77, resetsAt: nil),
        fable: fable
    )
}

private func fableProjection(claude: WidgetQuotaRow) throws -> WidgetProjection {
    try WidgetProjection(
        quotaRows: [claude, try WidgetQuotaRow(provider: .codex, stream: .unavailable, lastSuccessfulAt: nil, headline: nil)],
        usageRows: makeUnavailableUsageRows(),
        today: unavailableToday
    )
}

// `referenceDate` is 2027-01-15T08:00:00Z.
private let claudeRowJSON = #""provider":"claude","stream":"fresh","lastSuccessfulAt":"2027-01-15T08:00:00Z","headline":{"id":"claude.weekly","remainingPercent":77,"resetsAt":null}"#
private let codexRowJSON = #""provider":"codex","stream":"fresh","lastSuccessfulAt":"2027-01-15T08:00:00Z","headline":{"id":"codex.primary","remainingPercent":85,"resetsAt":null}"#
private let fableJSON = #","fable":{"remainingPercent":71,"resetsAt":"2027-01-15T09:00:00Z"}"#

/// A whole projection file whose two quota rows are the given JSON members, without braces.
private func document(claude: String = claudeRowJSON, codex: String = codexRowJSON) -> Data {
    let usage = ["claude", "codex", "cursor"].map {
        "{\"provider\":\"\($0)\",\"stream\":\"unavailable\",\"localDayKey\":null,\"utcOffsetSeconds\":null,\"lastSuccessfulAt\":null,\"todayTokens\":null,\"todayCostUSD\":null}"
    }.joined(separator: ",")
    let text = "{\"schemaVersion\":1,\"quotaRows\":[{" + claude + "},{" + codex + "}],\"usageRows\":[" + usage
        + "],\"today\":{\"completeness\":\"unavailable\",\"totalTokens\":null,\"estimatedCostUSD\":null}}"
    return Data(text.utf8)
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
