import Foundation
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore
import NeedlbarClaudeStatusLineSupport

@Test func freshUsageAndQuotaRenderKnownValues() throws {
    let now = Date()
    let presentation = ProviderPopoverPresentation(snapshot: snapshot(
        provider: .claude,
        usage: usage(totalTokens: 1_420, cacheWriteTokens: 80),
        quota: quota(usedPercent: 35),
        usageStatus: .fresh,
        quotaStatus: .fresh,
        updatedAt: now,
        quotaLastSuccessfulAt: now
    ), now: now)

    #expect(presentation.tokensToday == "1.42K")
    #expect(presentation.estimatedCostToday == "$2.50")
    #expect(presentation.quotaWindows.count == 1)
    #expect(presentation.usageFreshness == .fresh)
    #expect(presentation.quotaFreshness == .fresh)
    #expect(presentation.freshnessSummary == "Usage: Fresh · Quota: Fresh")
    #expect(presentation.cacheWriteTokens == "80")
}

@Test func freshUsageWithAuthenticationRequiredQuotaDoesNotInventAQuotaValue() {
    let presentation = ProviderPopoverPresentation(snapshot: snapshot(
        provider: .codex,
        usage: usage(totalTokens: 500, cacheWriteTokens: 0),
        quota: nil,
        usageStatus: .fresh,
        quotaStatus: .requiresAuthentication
    ))

    #expect(presentation.tokensToday == "500")
    #expect(presentation.quotaWindows.isEmpty)
    #expect(presentation.headlineQuotaRemaining == nil)
    #expect(presentation.requiresProviderSignIn)
    #expect(presentation.freshnessSummary == "Usage: Fresh · Quota: Authentication required")
    #expect(presentation.cacheWriteTokens == "0")
}

@Test func ClaudeQuotaFallbackUsesTheOfficialUsageActionWhileOtherProviderActionsRemainUnchanged() {
    #expect(ProviderPopoverPresentation(snapshot: snapshot(
        provider: .claude,
        usage: nil,
        quota: nil,
        usageStatus: .unavailable,
        quotaStatus: .requiresAuthentication,
        claudeQuotaFailureReason: .quotaAccessUnavailable
    )).authenticationAction == .openClaudeUsage(title: "View Claude usage"))

    #expect(ProviderPopoverPresentation(snapshot: snapshot(
        provider: .codex,
        usage: nil,
        quota: nil,
        usageStatus: .unavailable,
        quotaStatus: .requiresAuthentication
    )).authenticationAction == .browserLogin(title: "Sign in with ChatGPT"))

    #expect(ProviderPopoverPresentation(snapshot: snapshot(
        provider: .cursor,
        usage: usage(totalTokens: 900),
        quota: nil,
        usageStatus: .fresh,
        quotaStatus: .unavailable
    )).authenticationAction == .openCursorSpending(title: "Open Cursor Spending"))
}

@Test func everySafeClaudeQuotaReasonRendersItsExactAllowlistedText() {
    let cases: [(ClaudeQuotaFailureReason, String)] = [
        (.quotaAccessUnavailable, "Quota access unavailable"),
        (.credentialAccessUnavailable, "Credential access unavailable"),
        (.connectionUnavailable, "Connection unavailable"),
        (.temporarilyLimited, "Temporarily limited"),
        (.couldNotUpdateQuota, "Could not update quota"),
    ]

    for (reason, expectedText) in cases {
        let presentation = ProviderPopoverPresentation(snapshot: snapshot(
            provider: .claude,
            usage: nil,
            quota: nil,
            usageStatus: .unavailable,
            quotaStatus: .error(message: "untrusted raw detail", lastSuccessfulAt: nil),
            claudeQuotaFailureReason: reason
        ))
        #expect(presentation.quotaFailureReasonText == expectedText)
        #expect(presentation.freshnessSummary == "Usage: Unavailable")
    }
}

@Test func ClaudeQuotaFallbackUsesOnlyLastSuccessfulObservationAndOneSafeReason() throws {
    let successfulAt = try #require(BridgeDecoder.date("2026-09-15T10:00:00Z"))
    let attemptedAt = try #require(BridgeDecoder.date("2026-09-15T11:00:00Z"))
    let presentation = ProviderPopoverPresentation(snapshot: snapshot(
        provider: .claude,
        usage: nil,
        quota: quota(usedPercent: 35),
        usageStatus: .unavailable,
        quotaStatus: .error(message: "untrusted raw detail", lastSuccessfulAt: successfulAt),
        updatedAt: attemptedAt,
        claudeQuotaFailureReason: .connectionUnavailable,
        quotaLastSuccessfulAt: successfulAt
    ))

    #expect(presentation.quotaIsLastKnown)
    #expect(presentation.lastKnownQuotaRemaining == "65%")
    #expect(presentation.quotaFailureReasonText == "Connection unavailable")
    #expect(presentation.quotaLastCheckedText != nil)
    #expect(presentation.quotaLastCheckedText != MetricFormatter.reset(attemptedAt))
    #expect(presentation.authenticationAction == .openClaudeUsage(title: "View Claude usage"))
}

@Test func initialClaudeQuotaFallbackIsUnavailableWithoutTimeOrReset() {
    let presentation = ProviderPopoverPresentation(snapshot: snapshot(
        provider: .claude,
        usage: nil,
        quota: nil,
        usageStatus: .unavailable,
        quotaStatus: .error(message: "untrusted raw detail", lastSuccessfulAt: nil),
        claudeQuotaFailureReason: .couldNotUpdateQuota
    ))

    #expect(presentation.quotaWindows.isEmpty)
    #expect(presentation.quotaUnavailable)
    #expect(presentation.quotaLastCheckedText == nil)
    #expect(presentation.quotaFailureReasonText == "Could not update quota")
}

@Test func nonAuthenticationQuotaStatesOfferClaudeUsageWithoutInventingSignIn() {
    let statuses: [DataStatus] = [
        .fresh,
        .stale(lastSuccessfulAt: .distantPast),
        .unavailable,
        .error(message: "rate limited", lastSuccessfulAt: nil),
        .error(message: "network unavailable", lastSuccessfulAt: nil),
        .error(message: "schema changed", lastSuccessfulAt: nil),
    ]

    for status in statuses {
        let presentation = ProviderPopoverPresentation(snapshot: snapshot(
            provider: .claude,
            usage: nil,
            quota: nil,
            usageStatus: .unavailable,
            quotaStatus: status
        ))
        #expect(presentation.authenticationAction == .openClaudeUsage(title: "View Claude usage"))
    }
}

@Test func resetExpiredDirectClaudeQuotaRetainsValueAndUsageAction() throws {
    let now = Date(timeIntervalSince1970: 100_000)
    let direct = QuotaSnapshot(windows: [
        try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 80,
                        resetsAt: now.addingTimeInterval(-1)),
    ])
    let presentation = ProviderPopoverPresentation(snapshot: snapshot(provider: .claude, usage: nil, quota: direct,
        usageStatus: .unavailable, quotaStatus: .fresh, updatedAt: now,
        quotaLastSuccessfulAt: now.addingTimeInterval(-3_600)), now: now)

    #expect(presentation.headlineQuotaRemaining == nil)
    #expect(presentation.lastKnownQuotaRemaining == "20%")
    #expect(presentation.claudeFiveHour?.resetCaption == nil)
    #expect(presentation.authenticationAction == .openClaudeUsage(title: "View Claude usage"))
}

@Test func staleUsageKeepsTheLastKnownUsageWhileFreshQuotaRendersNormally() throws {
    let presentation = ProviderPopoverPresentation(snapshot: snapshot(
        provider: .cursor,
        usage: usage(totalTokens: 900, cacheWriteTokens: 10),
        quota: quota(usedPercent: 74),
        usageStatus: .stale(lastSuccessfulAt: .distantPast),
        quotaStatus: .fresh
    ))

    #expect(presentation.tokensToday == "900")
    #expect(presentation.headlineQuotaRemaining == nil)
    #expect(presentation.usageFreshness == .stale)
    #expect(presentation.quotaFreshness == .fresh)
}

@Test func unavailableStreamsRemainAbsentInsteadOfDisplayingZero() {
    let presentation = ProviderPopoverPresentation(snapshot: snapshot(
        provider: .claude,
        usage: nil,
        quota: nil,
        usageStatus: .unavailable,
        quotaStatus: .unavailable
    ))

    #expect(presentation.tokensToday == nil)
    #expect(presentation.estimatedCostToday == nil)
    #expect(presentation.cacheWriteTokens == nil)
    #expect(presentation.headlineQuotaRemaining == nil)
    #expect(presentation.quotaWindows.isEmpty)
}

@Test func overviewAggregatesOnlyRealDailySeriesByDate() {
    let overview = OverviewPopoverPresentation(
        snapshots: [
            snapshot(provider: .claude, usage: usage(totalTokens: 100), quota: nil, usageStatus: .fresh, quotaStatus: .unavailable),
            snapshot(provider: .codex, usage: usage(totalTokens: 50), quota: nil, usageStatus: .fresh, quotaStatus: .unavailable),
        ],
        dailyUsage: [
            .init(provider: .claude, date: "2026-08-10", totalTokens: 20),
            .init(provider: .codex, date: "2026-08-10", totalTokens: 30),
            .init(provider: .claude, date: "2026-08-11", totalTokens: 50),
        ]
    )

    #expect(overview.tokensToday == "150")
    #expect(overview.sevenDayTokens == [50, 50])
}

@Test func overviewLeavesTheChartUnavailableWhenNoDailySeriesExists() {
    let overview = OverviewPopoverPresentation(
        snapshots: [snapshot(provider: .claude, usage: usage(totalTokens: 100), quota: nil, usageStatus: .fresh, quotaStatus: .unavailable)],
        dailyUsage: []
    )

    #expect(overview.sevenDayTokens == nil)
}

@Test func overviewHeadlineQuotaUsesOnlyEnabledProviderModules() throws {
    let overview = OverviewPopoverPresentation(
        snapshots: [
            snapshot(provider: .claude, usage: nil, quota: quota(usedPercent: 20), usageStatus: .unavailable, quotaStatus: .fresh),
            snapshot(provider: .cursor, usage: nil, quota: quota(usedPercent: 90), usageStatus: .unavailable, quotaStatus: .fresh),
        ],
        dailyUsage: [],
        enabledProviders: [.claude]
    )

    #expect(overview.headlineQuotaRemaining == "80%")
}

@Test func ClaudePopoverUsesRecentStatusLineWithoutMaskingFableAge() throws {
    let received = Date(timeIntervalSince1970: 100_000)
    let directAt = received.addingTimeInterval(-3_600)
    let direct = QuotaSnapshot(windows: [
        try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 80, resetsAt: nil),
        try QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "Fable weekly", usedPercent: 90,
                        resetsAt: directAt.addingTimeInterval(600)),
    ])
    let record = StatusLineQuotaRecord(schemaVersion: 1, generation: UUID(),
        fiveHour: .init(usedPercent: 25, resetsAt: received.addingTimeInterval(3_600), receivedAt: received),
        sevenDay: nil)
    let mixed = ProviderSnapshot(provider: .claude, usage: nil, quota: direct,
        usageStatus: .unavailable, quotaStatus: .requiresAuthentication, updatedAt: received,
        claudeQuotaFailureReason: .quotaAccessUnavailable, quotaLastSuccessfulAt: directAt,
        claudeStatusLineQuota: record)

    let presentation = ProviderPopoverPresentation(snapshot: mixed, now: received.addingTimeInterval(60))

    #expect(presentation.headlineQuotaRemaining == "75%")
    #expect(presentation.quotaSourceText == "Reported by Claude Code")
    #expect(presentation.quotaLastCheckedText == DateFormatter.localizedString(from: received, dateStyle: .medium, timeStyle: .short))
    #expect(presentation.quotaFailureReasonText == nil)
    #expect(!presentation.quotaUnavailable)
    #expect(presentation.claudeFiveHour?.sourceLabel == "Reported by Claude Code")
    #expect(presentation.fableIsLastKnown)
    #expect(presentation.fableLastCheckedText == DateFormatter.localizedString(from: directAt, dateStyle: .medium, timeStyle: .short))
    #expect(presentation.claudeFable?.resetCaption == nil)
    #expect(presentation.authenticationAction == .openClaudeUsage(title: "View Claude usage"))
}

@Test func ClaudePopoverDoesNotPresentOldOrResetPassedStatusLineAsCurrent() {
    let received = Date(timeIntervalSince1970: 100_000)
    for (age, reset) in [(20 * 60.0, received.addingTimeInterval(3_600)),
                         (60.0, received.addingTimeInterval(30))] {
        let record = StatusLineQuotaRecord(schemaVersion: 1, generation: UUID(),
            fiveHour: .init(usedPercent: 25, resetsAt: reset, receivedAt: received), sevenDay: nil)
        let value = ProviderPopoverPresentation(snapshot: snapshot(provider: .claude, usage: nil, quota: nil,
            usageStatus: .unavailable, quotaStatus: .requiresAuthentication,
            claudeStatusLineQuota: record), now: received.addingTimeInterval(age))
        #expect(value.headlineQuotaRemaining == nil)
        #expect(value.lastKnownQuotaRemaining == "75%")
        #expect(value.quotaIsLastKnown)
        #expect(value.claudeFiveHour?.remaining == "75%")
        #expect(value.claudeFiveHour?.isLastKnown == true)
        #expect(value.claudeFiveHour?.resetCaption == nil)
    }
}

@Test func ClaudePopoverMixedMainWindowsKeepPerWindowProvenance() throws {
    let now = Date(timeIntervalSince1970: 100_000)
    let direct = QuotaSnapshot(windows: [
        try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 80,
                        resetsAt: now.addingTimeInterval(3_600)),
    ])
    let record = StatusLineQuotaRecord(schemaVersion: 1, generation: UUID(), fiveHour: nil,
        sevenDay: .init(usedPercent: 25, resetsAt: now.addingTimeInterval(3_600), receivedAt: now))
    let value = ProviderPopoverPresentation(snapshot: snapshot(provider: .claude, usage: nil, quota: direct,
        usageStatus: .unavailable, quotaStatus: .fresh, quotaLastSuccessfulAt: now.addingTimeInterval(-600),
        claudeStatusLineQuota: record), now: now)

    #expect(value.quotaSourceText == "Claude usage")
    #expect(value.claudeFiveHour?.sourceLabel == "Claude usage")
    #expect(value.claudeSevenDay?.sourceLabel == "Reported by Claude Code")
    #expect(value.claudeFiveHour?.observationLabel == "Last checked")
    #expect(value.claudeSevenDay?.observationLabel == "Received locally")
    #expect(value.claudeFiveHour?.observedAt == now.addingTimeInterval(-600))
    #expect(value.claudeSevenDay?.observedAt == now)
}

@Test func ClaudePopoverDirectRecoveryTakesPrecedenceOverStatusLine() throws {
    let now = Date(timeIntervalSince1970: 100_000)
    let record = StatusLineQuotaRecord(schemaVersion: 1, generation: UUID(),
        fiveHour: .init(usedPercent: 25, resetsAt: now.addingTimeInterval(3_600), receivedAt: now), sevenDay: nil)
    let direct = QuotaSnapshot(windows: [
        try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 40, resetsAt: now.addingTimeInterval(3_600)),
    ])
    let value = ProviderPopoverPresentation(snapshot: snapshot(provider: .claude, usage: nil, quota: direct,
        usageStatus: .unavailable, quotaStatus: .fresh, quotaLastSuccessfulAt: now,
        claudeStatusLineQuota: record), now: now)
    #expect(value.headlineQuotaRemaining == "60%")
    #expect(value.quotaSourceText == "Claude usage")
    #expect(value.quotaFailureReasonText == nil)
}

private func snapshot(
    provider: ProviderID,
    usage: UsageSnapshot?,
    quota: QuotaSnapshot?,
    usageStatus: DataStatus,
    quotaStatus: DataStatus,
    updatedAt: Date = .now,
    claudeQuotaFailureReason: ClaudeQuotaFailureReason? = nil,
    quotaLastSuccessfulAt: Date? = nil,
    claudeStatusLineQuota: StatusLineQuotaRecord? = nil
) -> ProviderSnapshot {
    ProviderSnapshot(
        provider: provider,
        usage: usage,
        quota: quota,
        usageStatus: usageStatus,
        quotaStatus: quotaStatus,
        updatedAt: updatedAt,
        claudeQuotaFailureReason: claudeQuotaFailureReason,
        quotaLastSuccessfulAt: quotaLastSuccessfulAt,
        claudeStatusLineQuota: claudeStatusLineQuota
    )
}

private func usage(totalTokens: UInt64, cacheWriteTokens: UInt64 = 0) -> UsageSnapshot {
    let today = UsagePeriod(
        inputTokens: totalTokens,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheWriteTokens: cacheWriteTokens,
        totalTokens: totalTokens,
        estimatedCostUSD: Decimal(string: "2.50")!
    )
    return UsageSnapshot(
        inputTokens: totalTokens,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheWriteTokens: cacheWriteTokens,
        totalTokens: totalTokens,
        estimatedCostUSD: Decimal(string: "2.50")!,
        today: today,
        last7Days: today,
        last30Days: today
    )
}

private func quota(usedPercent: Double) -> QuotaSnapshot {
    QuotaSnapshot(windows: [
        try! QuotaWindow(id: "window", title: "Plan", usedPercent: usedPercent, resetsAt: nil),
    ])
}
