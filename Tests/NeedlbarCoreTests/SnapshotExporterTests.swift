import Foundation
import Testing
@testable import NeedlbarCore

@Test func v1EncodingExactlyMatchesTheCompleteHandWrittenGoldenDocument() throws {
    let capture = try validExportCaptureWithPrivacyCanaries()
    let expected = Data(completeHandWrittenV1GoldenJSONWithFinalNewline.utf8)

    let first = try SnapshotExporter().encode(capture)
    let second = try SnapshotExporter().encode(capture)

    #expect(first == expected)
    #expect(second == expected)
    #expect(first == second)
}

@Test func canonicalJSONOrdersNumericLookingKeysByUTF8LexicalOrder() throws {
    let bytes = SnapshotCanonicalJSON.encode(
        .object([
            "last7Days": .string("seven"),
            "last30Days": .string("thirty"),
            "last7DaysDaily": .string("daily")
        ])
    )

    #expect(bytes == Data(#"{"last30Days":"thirty","last7Days":"seven","last7DaysDaily":"daily"}"#.utf8))
}

@Test func fableWindowIsOmittedFromV1ExportWithoutChangingCanonicalBytes() throws {
    let baseline = try validExportCaptureWithPrivacyCanaries()
    let claude = baseline.providers[0]
    let fable = try QuotaWindow(
        id: "claude.fable.weekly",
        title: "Fable weekly",
        usedPercent: 100,
        resetsAt: try date("2026-08-30T12:00:00.000Z")
    )
    let capture = replacingProvider(
        claude,
        quota: QuotaSnapshot(windows: (claude.quota?.windows ?? []) + [fable]),
        in: baseline
    )

    #expect(try SnapshotExporter().encode(capture) == Data(completeHandWrittenV1GoldenJSONWithFinalNewline.utf8))
}

@Test(arguments: invalidExportCaptures())
func invalidCaptureFailsBeforeWriting(_ capture: ExportCapture) {
    #expect(throws: SnapshotExportError.self) {
        _ = try SnapshotExporter().encode(capture)
    }
}

@Test func quotaValidationRejectsNonFiniteAndOutOfRangeRawValues() {
    #expect(throws: SnapshotExportError.self) {
        try SnapshotExportValidation.validateWindow(
            provider: .claude,
            id: "claude.session",
            usedPercent: .nan,
            resetsAt: nil
        )
    }
    #expect(throws: SnapshotExportError.self) {
        try SnapshotExportValidation.validateWindow(
            provider: .claude,
            id: "claude.session",
            usedPercent: 101,
            resetsAt: nil
        )
    }
}

@Test func encodingRejectsTimestampOutsideTheV1FourDigitYearShape() throws {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = 10_000
    components.month = 1
    components.day = 2
    components.hour = 3
    components.minute = 4
    components.second = 5
    let outOfRangeDate = try #require(components.date)
    let valid = try validExportCaptureWithPrivacyCanaries()
    let capture = ExportCapture(exportedAt: outOfRangeDate, providers: valid.providers)

    #expect(throws: SnapshotExportError.self) {
        _ = try SnapshotExporter().encode(capture)
    }
}

@Test func staleDataAndErrorStatusRetainOnlySafeExportFields() throws {
    let bytes = try SnapshotExporter().encode(try validExportCaptureWithPrivacyCanaries())
    let json = try #require(String(data: bytes, encoding: .utf8))

    #expect(json.contains("\"lastSuccessfulAt\":\"2026-08-29T10:00:00.000Z\""))
    #expect(json.contains("\"state\":\"stale\""))
    #expect(json.contains("\"errorCode\":\"refreshFailed\""))
    #expect(!json.contains("provider response body /Users/example/private"))
    #expect(!json.contains("CLAUDE-CANARY-SECRET"))
}

@Test func requiresAuthenticationStatusUsesTheExactSafeSchemaForIndependentStreams() throws {
    let bytes = try SnapshotExporter().encode(try captureWithRequiresAuthenticationStatuses())
    let json = try #require(String(data: bytes, encoding: .utf8))
    let document = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    let providers = try #require(document["providers"] as? [[String: Any]])
    let claude = try #require(providers.first { $0["provider"] as? String == "claude" })
    let usage = try #require(claude["usage"] as? [String: Any])
    let quota = try #require(claude["quota"] as? [String: Any])
    let usageStatus = try #require(usage["status"] as? [String: Any])
    let quotaStatus = try #require(quota["status"] as? [String: Any])

    #expect(usageStatus["state"] as? String == "requiresAuthentication")
    #expect(usageStatus["errorCode"] is NSNull)
    #expect(usageStatus["lastSuccessfulAt"] as? String == "2026-08-29T10:00:00.000Z")
    #expect(quotaStatus["state"] as? String == "requiresAuthentication")
    #expect(quotaStatus["errorCode"] is NSNull)
    #expect(quotaStatus["lastSuccessfulAt"] is NSNull)
    #expect(!json.contains("provider response body /Users/example/private"))
}

private let completeHandWrittenV1GoldenJSONWithFinalNewline = """
{"exportedAt":"2026-08-29T12:34:56.000Z","providers":[{"provider":"claude","quota":{"data":{"windows":[{"id":"claude.session","resetsAt":"2026-08-29T14:00:00.000Z","usedPercent":42.5}]},"status":{"errorCode":null,"lastSuccessfulAt":"2026-08-29T11:00:00.000Z","state":"fresh"}},"updatedAt":"2026-08-29T11:00:00.000Z","usage":{"data":{"allTime":{"cacheReadTokens":"3","cacheWriteTokens":"4","estimatedCostUSD":"12.34","inputTokens":"10","outputTokens":"20","totalTokens":"37"},"last30Days":{"cacheReadTokens":"0","cacheWriteTokens":"0","estimatedCostUSD":"0","inputTokens":"1","outputTokens":"2","totalTokens":"3"},"last7Days":{"cacheReadTokens":"1","cacheWriteTokens":"0","estimatedCostUSD":"1.2","inputTokens":"3","outputTokens":"4","totalTokens":"8"},"last7DaysDaily":[{"date":"2026-08-28","totalTokens":"0"},{"date":"2026-08-29","totalTokens":"8"}],"today":{"cacheReadTokens":"0","cacheWriteTokens":"1","estimatedCostUSD":"0.01","inputTokens":"2","outputTokens":"3","totalTokens":"6"}},"status":{"errorCode":null,"lastSuccessfulAt":"2026-08-29T10:00:00.000Z","state":"fresh"}}},{"provider":"codex","quota":{"data":{"windows":[{"id":"codex.primary","resetsAt":null,"usedPercent":25}]},"status":{"errorCode":"refreshFailed","lastSuccessfulAt":"2026-08-29T09:00:00.000Z","state":"error"}},"updatedAt":"2026-08-29T10:00:00.000Z","usage":{"data":{"allTime":{"cacheReadTokens":"0","cacheWriteTokens":"0","estimatedCostUSD":"0","inputTokens":"5","outputTokens":"6","totalTokens":"11"},"last30Days":{"cacheReadTokens":"0","cacheWriteTokens":"0","estimatedCostUSD":"0","inputTokens":"1","outputTokens":"2","totalTokens":"3"},"last7Days":{"cacheReadTokens":"0","cacheWriteTokens":"0","estimatedCostUSD":"0","inputTokens":"2","outputTokens":"3","totalTokens":"5"},"last7DaysDaily":[],"today":{"cacheReadTokens":"0","cacheWriteTokens":"0","estimatedCostUSD":"0","inputTokens":"1","outputTokens":"1","totalTokens":"2"}},"status":{"errorCode":null,"lastSuccessfulAt":"2026-08-29T10:00:00.000Z","state":"stale"}}},{"provider":"cursor","quota":{"data":null,"status":{"errorCode":null,"lastSuccessfulAt":null,"state":"unavailable"}},"updatedAt":null,"usage":{"data":null,"status":{"errorCode":null,"lastSuccessfulAt":null,"state":"unavailable"}}}],"schemaVersion":1}

"""

private func validExportCaptureWithPrivacyCanaries() throws -> ExportCapture {
    let exportedAt = try date("2026-08-29T12:34:56.000Z")
    let usageAt = try date("2026-08-29T10:00:00.000Z")
    let quotaAt = try date("2026-08-29T11:00:00.000Z")
    let errorAt = try date("2026-08-29T09:00:00.000Z")
    return ExportCapture(
        exportedAt: exportedAt,
        providers: [
            ProviderExportState(
                provider: .claude,
                usage: claudeUsage(),
                quota: QuotaSnapshot(windows: [
                    try QuotaWindow(
                        id: "claude.session",
                        title: "CLAUDE-CANARY-SECRET",
                        usedPercent: 42.5,
                        resetsAt: try date("2026-08-29T14:00:00.000Z")
                    )
                ]),
                usageStatus: .fresh,
                quotaStatus: .fresh,
                usageLastSuccessfulAt: usageAt,
                quotaLastSuccessfulAt: quotaAt,
                everUpdated: true,
                updatedAt: quotaAt
            ),
            ProviderExportState(
                provider: .codex,
                usage: codexUsage(),
                quota: QuotaSnapshot(windows: [
                    try QuotaWindow(id: "codex.primary", title: "Primary", usedPercent: 25, resetsAt: nil)
                ]),
                usageStatus: .stale(lastSuccessfulAt: usageAt),
                quotaStatus: .error(
                    message: "provider response body /Users/example/private",
                    lastSuccessfulAt: errorAt
                ),
                usageLastSuccessfulAt: usageAt,
                quotaLastSuccessfulAt: errorAt,
                everUpdated: true,
                updatedAt: usageAt
            ),
            ProviderExportState(
                provider: .cursor,
                usage: nil,
                quota: nil,
                usageStatus: .unavailable,
                quotaStatus: .unavailable,
                usageLastSuccessfulAt: nil,
                quotaLastSuccessfulAt: nil,
                everUpdated: false,
                updatedAt: nil
            )
        ]
    )
}

private func captureWithRequiresAuthenticationStatuses() throws -> ExportCapture {
    let valid = try validExportCaptureWithPrivacyCanaries()
    let claude = valid.providers[0]
    let requiresAuthentication = ProviderExportState(
        provider: claude.provider,
        usage: claude.usage,
        quota: claude.quota,
        usageStatus: .requiresAuthentication,
        quotaStatus: .requiresAuthentication,
        usageLastSuccessfulAt: claude.usageLastSuccessfulAt,
        quotaLastSuccessfulAt: nil,
        everUpdated: claude.everUpdated,
        updatedAt: claude.updatedAt
    )
    return ExportCapture(
        exportedAt: valid.exportedAt,
        providers: [requiresAuthentication, valid.providers[1], valid.providers[2]]
    )
}

private func invalidExportCaptures() -> [ExportCapture] {
    let valid = try! validExportCaptureWithPrivacyCanaries()
    let claude = valid.providers[0]
    let codex = valid.providers[1]
    let cursor = valid.providers[2]
    let duplicateDaily = replacingClaudeUsage(in: valid, daily: [
        DailyUsagePoint(date: "2026-08-28", totalTokens: 0),
        DailyUsagePoint(date: "2026-08-28", totalTokens: 8)
    ])
    let outOfOrderDaily = replacingClaudeUsage(in: valid, daily: [
        DailyUsagePoint(date: "2026-08-29", totalTokens: 8),
        DailyUsagePoint(date: "2026-08-28", totalTokens: 0)
    ])
    let invalidDate = replacingClaudeUsage(in: valid, daily: [
        DailyUsagePoint(date: "2026-02-30", totalTokens: 0)
    ])
    let negativeCost = replacingClaudeUsage(in: valid, cost: Decimal(-1))
    let unknownQuota = replacingProvider(
        claude,
        quota: QuotaSnapshot(windows: [try! QuotaWindow(id: "unknown.window", title: "Unknown", usedPercent: 1, resetsAt: nil)]),
        in: valid
    )
    let mismatchedQuota = replacingProvider(
        codex,
        quota: QuotaSnapshot(windows: [try! QuotaWindow(id: "claude.session", title: "Wrong", usedPercent: 1, resetsAt: nil)]),
        in: valid
    )
    let cursorQuota = replacingProvider(
        cursor,
        quota: QuotaSnapshot(windows: []),
        in: valid
    )
    let outOfOrderProviders = ExportCapture(
        exportedAt: valid.exportedAt,
        providers: [codex, claude, cursor]
    )
    return [
        duplicateDaily,
        outOfOrderDaily,
        invalidDate,
        negativeCost,
        unknownQuota,
        mismatchedQuota,
        cursorQuota,
        outOfOrderProviders
    ]
}

private func replacingClaudeUsage(
    in capture: ExportCapture,
    daily: [DailyUsagePoint]? = nil,
    cost: Decimal? = nil
) -> ExportCapture {
    let claude = capture.providers[0]
    let usage = claude.usage!
    let replacement = UsageSnapshot(
        inputTokens: usage.inputTokens,
        outputTokens: usage.outputTokens,
        cacheReadTokens: usage.cacheReadTokens,
        cacheWriteTokens: usage.cacheWriteTokens,
        totalTokens: usage.totalTokens,
        estimatedCostUSD: cost ?? usage.estimatedCostUSD,
        today: usage.today,
        last7Days: usage.last7Days,
        last7DaysDaily: daily ?? usage.last7DaysDaily,
        last30Days: usage.last30Days
    )
    let provider = ProviderExportState(
        provider: claude.provider,
        usage: replacement,
        quota: claude.quota,
        usageStatus: claude.usageStatus,
        quotaStatus: claude.quotaStatus,
        usageLastSuccessfulAt: claude.usageLastSuccessfulAt,
        quotaLastSuccessfulAt: claude.quotaLastSuccessfulAt,
        everUpdated: claude.everUpdated,
        updatedAt: claude.updatedAt
    )
    return replacingProvider(provider, in: capture)
}

private func replacingProvider(
    _ original: ProviderExportState,
    usage: UsageSnapshot? = nil,
    quota: QuotaSnapshot? = nil,
    in capture: ExportCapture
) -> ExportCapture {
    let provider = ProviderExportState(
        provider: original.provider,
        usage: usage ?? original.usage,
        quota: quota ?? original.quota,
        usageStatus: original.usageStatus,
        quotaStatus: original.quotaStatus,
        usageLastSuccessfulAt: original.usageLastSuccessfulAt,
        quotaLastSuccessfulAt: original.quotaLastSuccessfulAt,
        everUpdated: original.everUpdated,
        updatedAt: original.updatedAt
    )
    return ExportCapture(
        exportedAt: capture.exportedAt,
        providers: capture.providers.map { $0.provider == provider.provider ? provider : $0 }
    )
}

private func claudeUsage() -> UsageSnapshot {
    UsageSnapshot(
        inputTokens: 10,
        outputTokens: 20,
        cacheReadTokens: 3,
        cacheWriteTokens: 4,
        totalTokens: 37,
        estimatedCostUSD: decimal("12.3400"),
        today: period(input: 2, output: 3, cacheRead: 0, cacheWrite: 1, total: 6, cost: "0.0100"),
        last7Days: period(input: 3, output: 4, cacheRead: 1, cacheWrite: 0, total: 8, cost: "1.200"),
        last7DaysDaily: [
            DailyUsagePoint(date: "2026-08-28", totalTokens: 0),
            DailyUsagePoint(date: "2026-08-29", totalTokens: 8)
        ],
        last30Days: period(input: 1, output: 2, cacheRead: 0, cacheWrite: 0, total: 3, cost: "0")
    )
}

private func codexUsage() -> UsageSnapshot {
    UsageSnapshot(
        inputTokens: 5,
        outputTokens: 6,
        cacheReadTokens: 0,
        cacheWriteTokens: 0,
        totalTokens: 11,
        estimatedCostUSD: decimal("0"),
        today: period(input: 1, output: 1, cacheRead: 0, cacheWrite: 0, total: 2, cost: "0"),
        last7Days: period(input: 2, output: 3, cacheRead: 0, cacheWrite: 0, total: 5, cost: "0"),
        last7DaysDaily: [],
        last30Days: period(input: 1, output: 2, cacheRead: 0, cacheWrite: 0, total: 3, cost: "0")
    )
}

private func period(input: UInt64, output: UInt64, cacheRead: UInt64, cacheWrite: UInt64, total: UInt64, cost: String) -> UsagePeriod {
    UsagePeriod(
        inputTokens: input,
        outputTokens: output,
        cacheReadTokens: cacheRead,
        cacheWriteTokens: cacheWrite,
        totalTokens: total,
        estimatedCostUSD: decimal(cost)
    )
}

private func decimal(_ value: String) -> Decimal {
    Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
}

private func date(_ value: String) throws -> Date {
    try #require(BridgeDecoder.date(value))
}
