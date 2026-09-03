import Foundation
import Testing
@testable import NeedlbarCore

@Test func mostConstrainedSelectsTheLowestRemainingEligibleWindow() throws {
    let snapshots = [
        makeQuotaSnapshot(provider: .claude, usedPercent: 68),
        makeQuotaSnapshot(provider: .codex, usedPercent: 81),
    ]

    let selected = HeadlineQuotaSelector.mostConstrained(snapshots)

    #expect(selected?.remainingPercent == 19)
}

@Test func mostConstrainedIgnoresRetainedCursorQuotaWindows() throws {
    let snapshots = [
        makeQuotaSnapshot(provider: .claude, usedPercent: 68),
        makeQuotaSnapshot(provider: .codex, usedPercent: 81),
        makeQuotaSnapshot(provider: .cursor, usedPercent: 99),
    ]

    let selected = HeadlineQuotaSelector.mostConstrained(snapshots)

    #expect(selected?.id == "codex.window")
    #expect(selected?.remainingPercent == 19)
}

@Test func mostConstrainedIgnoresProvidersWithoutQuotaWindows() throws {
    let snapshots = [
        makeQuotaSnapshot(provider: .claude, usedPercent: 68),
        ProviderSnapshot(
            provider: .codex,
            usage: nil,
            quota: nil,
            usageStatus: .unavailable,
            quotaStatus: .requiresAuthentication,
            updatedAt: .now
        ),
        ProviderSnapshot(
            provider: .cursor,
            usage: nil,
            quota: QuotaSnapshot(windows: []),
            usageStatus: .unavailable,
            quotaStatus: .unavailable,
            updatedAt: .now
        ),
    ]

    let selected = HeadlineQuotaSelector.mostConstrained(snapshots)

    #expect(selected?.remainingPercent == 32)
}

@Test func fableDoesNotChangeHeadlineButOtherUnknownWindowsRemainEligible() throws {
    func snapshot(
        provider: ProviderID,
        windows: [QuotaWindow]
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: provider,
            usage: nil,
            quota: QuotaSnapshot(windows: windows),
            usageStatus: .unavailable,
            quotaStatus: .fresh,
            updatedAt: .now
        )
    }

    let base = snapshot(
        provider: .claude,
        windows: [
            try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 68, resetsAt: nil)
        ]
    )
    let fable = snapshot(
        provider: .claude,
        windows: [
            try QuotaWindow(id: "claude.fable.weekly", title: "Fable weekly", usedPercent: 100, resetsAt: nil)
        ]
    )
    let unknown = snapshot(
        provider: .claude,
        windows: [
            try QuotaWindow(id: "claude.future", title: "Future", usedPercent: 99, resetsAt: nil)
        ]
    )

    #expect(HeadlineQuotaSelector.mostConstrained([base, fable]) == base.quota?.windows.first)
    #expect(HeadlineQuotaSelector.mostConstrained([base, fable, unknown]) == unknown.quota?.windows.first)
    #expect(HeadlineQuotaSelector.mostConstrained([fable]) == nil)
}

@Test func metricFormatterUsesCompactMetricFormatsAndDoesNotInventResets() {
    #expect(MetricFormatter.tokens(1_420_000) == "1.42M")
    #expect(MetricFormatter.tokens(842_000) == "842K")
    #expect(MetricFormatter.tokens(999) == "999")
    #expect(MetricFormatter.tokens(1_000) == "1K")
    #expect(MetricFormatter.tokens(1_426_000) == "1.43M")
    #expect(MetricFormatter.costUSD(Decimal(string: "7.81")!) == "$7.81")
    #expect(MetricFormatter.quotaRemaining(19.4) == "19%")
    #expect(MetricFormatter.reset(nil) == nil)
}

@Test func metricFormatterUsesTheSuppliedLocaleAndTimeZoneForResets() throws {
    let reset = try #require(BridgeDecoder.date("2026-08-14T10:00:00Z"))
    let utc = MetricFormatter.reset(
        reset,
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: TimeZone(secondsFromGMT: 0)!
    )
    let newYork = MetricFormatter.reset(
        reset,
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: TimeZone(identifier: "America/New_York")!
    )

    #expect(utc != nil)
    #expect(newYork != nil)
    #expect(utc != newYork)
}

private func makeQuotaSnapshot(provider: ProviderID, usedPercent: Double) -> ProviderSnapshot {
    ProviderSnapshot(
        provider: provider,
        usage: nil,
        quota: QuotaSnapshot(windows: [
            try! QuotaWindow(id: "\(provider.rawValue).window", title: "Window", usedPercent: usedPercent, resetsAt: nil),
        ]),
        usageStatus: .unavailable,
        quotaStatus: .fresh,
        updatedAt: .now
    )
}
