import Foundation
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

@Test @MainActor func legacyClaudeWindowWithMissingSuccessTimeStaysLastKnownAcrossSurfaces() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshot = ProviderSnapshot(
        provider: .claude,
        usage: nil,
        quota: QuotaSnapshot(windows: [try QuotaWindow(
            id: "claude.legacy", title: "Legacy window", usedPercent: 25, resetsAt: nil
        )]),
        usageStatus: .unavailable,
        quotaStatus: .fresh,
        updatedAt: now
    )
    let combined = CombinedUsageSnapshot(
        system: nil,
        providers: [snapshot],
        capturedAt: now,
        systemAvailability: [:]
    )

    let popover = ProviderPopoverPresentation(snapshot: snapshot, now: now)
    let dashboard = SystemDashboardPresentation(
        snapshot: combined,
        configuration: SystemMonitorConfiguration(),
        now: now
    )
    let settings = SettingsClaudeQuotaPresentation(snapshot: combined, now: now).value
    let detail = try #require(popover.claudeOtherWindows.first)
    let dashboardClaude = try #require(dashboard.ai.first { $0.provider == .claude })

    #expect(detail.id == "claude.legacy")
    #expect(detail.remaining == "75%")
    #expect(detail.isLastKnown)
    #expect(detail.observedAt == nil)
    #expect(detail.resetCaption == nil)
    #expect(popover.quotaIsLastKnown)
    #expect(popover.lastKnownQuotaRemaining == "75%")
    #expect(popover.quotaLastCheckedText == nil)
    #expect(!popover.requiresProviderSignIn)

    #expect(settings.claudeOtherWindows == popover.claudeOtherWindows)
    #expect(settings.quotaIsLastKnown)
    #expect(settings.lastKnownQuotaRemaining == "75%")
    #expect(settings.quotaLastCheckedText == nil)

    #expect(dashboardClaude.quotaIsLastKnown)
    #expect(dashboardClaude.quotaLastKnownRemaining == "75%")
    #expect(dashboardClaude.quotaLastCheckedText == nil)
}

@Test @MainActor func resetlessCurrentClaudeQuotaShowsUnavailableResetCopy() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshot = ProviderSnapshot(
        provider: .claude,
        usage: nil,
        quota: QuotaSnapshot(windows: [try QuotaWindow(
            id: "claude.session", title: "Session", usedPercent: 25, resetsAt: nil
        )]),
        usageStatus: .unavailable,
        quotaStatus: .fresh,
        updatedAt: now,
        quotaLastSuccessfulAt: now
    )
    let presentation = ProviderPopoverPresentation(snapshot: snapshot, now: now)

    #expect(presentation.claudeFiveHour?.remaining == "75%")
    #expect(presentation.claudeFiveHour?.isLastKnown == false)
    #expect(presentation.claudeFiveHour?.resetCaption == "Reset unavailable")
    #expect(presentation.quotaFreshness == .fresh)
    #expect(!presentation.requiresProviderSignIn)
}
