import Foundation
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore
import NeedlbarClaudeStatusLineSupport

@Suite("ClaudeUsageReportPresentation")
@MainActor
struct ClaudeUsageReportPresentationTests {
    private let now = Date()

    private func claude(
        windows: [QuotaWindow]?, reason: ClaudeQuotaFailureReason? = nil, age: TimeInterval = 60,
        statusLine: StatusLineQuotaRecord? = nil
    ) -> ProviderSnapshot {
        let at = now.addingTimeInterval(-age)
        return ProviderSnapshot(
            provider: .claude, usage: nil, quota: windows.map { QuotaSnapshot(windows: $0) }, usageStatus: .fresh,
            quotaStatus: reason == nil ? .fresh : .error(message: "fixture", lastSuccessfulAt: windows == nil ? nil : at),
            updatedAt: now, claudeQuotaFailureReason: reason,
            quotaLastSuccessfulAt: windows == nil ? nil : at, claudeStatusLineQuota: statusLine)
    }

    private func weekly() throws -> QuotaWindow {
        try QuotaWindow(id: "claude.weekly", title: "Weekly", usedPercent: 74, resetsAt: now.addingTimeInterval(86_400))
    }

    private func fable() throws -> QuotaWindow {
        try QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "Fable weekly", usedPercent: 0, resetsAt: nil)
    }

    private func dashboardRow(_ snapshot: ProviderSnapshot) -> SystemDashboardPresentation.AIProvider {
        let combined = CombinedUsageSnapshot(system: nil, providers: [
            snapshot,
            ProviderSnapshot(provider: .codex, usage: nil, quota: nil, usageStatus: .fresh, quotaStatus: .unavailable, updatedAt: now),
            ProviderSnapshot(provider: .cursor, usage: nil, quota: nil, usageStatus: .fresh, quotaStatus: .unavailable, updatedAt: now),
        ], capturedAt: now, systemAvailability: [:])
        let configuration = SystemMonitorConfiguration(aiOrder: [.claude, .codex, .cursor], dashboardVisibleModules: [.ai])
        return SystemDashboardPresentation(snapshot: combined, configuration: configuration, now: now)
            .ai.first { $0.provider == .claude }!
    }

    @Test func weeklyOnlyShowsNoSessionRowAndNoMadeUpZero() throws {
        let snapshot = claude(windows: [try weekly(), try fable()])
        let popover = ProviderPopoverPresentation(snapshot: snapshot, now: now)
        #expect(popover.claudeFiveHour == nil)
        #expect(popover.claudeSevenDay?.remaining == "26%")
        #expect(popover.claudeFable?.remaining == "100%")
        #expect(popover.headlineQuotaRemaining == "26%")
        #expect(!popover.quotaUnavailable)
        #expect(dashboardRow(snapshot).compactQuotaValue == "26%")
    }

    @Test func onlyFableIsNotQuotaUnavailableAndHasNoHeadline() throws {
        let popover = ProviderPopoverPresentation(snapshot: claude(windows: [try fable()]), now: now)
        #expect(!popover.quotaUnavailable)
        #expect(popover.claudeFable != nil)
        #expect(popover.headlineQuotaRemaining == nil)
        #expect(dashboardRow(claude(windows: [try fable()])).compactQuotaValue == "—")
    }

    @Test func noWindowsAtAllStaysQuotaUnavailableWithoutAValue() {
        let popover = ProviderPopoverPresentation(
            snapshot: claude(windows: nil, reason: .claudeCodeNotInstalled), now: now)
        #expect(popover.quotaUnavailable)
        #expect(popover.headlineQuotaRemaining == nil)
        #expect(popover.lastKnownQuotaRemaining == nil)
        #expect(popover.quotaLastCheckedText == nil)
    }

    @Test func failuresKeepLastKnownValuesWithTheirCheckedTime() throws {
        for reason in [ClaudeQuotaFailureReason.claudeCodeCheckFailed, .temporarilyLimited, .usageReportFormatChanged] {
            let popover = ProviderPopoverPresentation(
                snapshot: claude(windows: [try weekly()], reason: reason, age: 7_200), now: now)
            #expect(popover.quotaIsLastKnown)
            #expect(popover.lastKnownQuotaRemaining == "26%")
            #expect(popover.quotaLastCheckedText != nil)
            #expect(popover.quotaFailureReasonText == reason.displayText)
        }
    }

    @Test func notInstalledAndACheckFailureOfferTheUsageLinkAndNoLaunchButton() throws {
        for reason in [ClaudeQuotaFailureReason.claudeCodeNotInstalled, .claudeCodeCheckFailed] {
            let popover = ProviderPopoverPresentation(snapshot: claude(windows: nil, reason: reason), now: now)
            #expect(popover.quotaFailureReasonText == reason.displayText)
            #expect(popover.quotaFailureDetailText == reason.detailText)
            #expect(popover.authenticationAction == .openClaudeUsage(title: "View Claude usage"))
            #expect(!popover.requiresProviderSignIn)
            #expect(dashboardRow(claude(windows: nil, reason: reason)).quotaFailureReasonText == reason.displayText)
        }
    }

    @Test func withRecentStatusLineValuesTheGuidanceMovesToTheFableLine() throws {
        let record = StatusLineQuotaRecord(
            schemaVersion: StatusLineQuotaRecord.currentSchemaVersion, generation: UUID(),
            fiveHour: StatusLineWindowObservation(usedPercent: 25, resetsAt: nil, receivedAt: now.addingTimeInterval(-30)),
            sevenDay: StatusLineWindowObservation(usedPercent: 35, resetsAt: nil, receivedAt: now.addingTimeInterval(-30)))
        for reason in [ClaudeQuotaFailureReason.claudeCodeNotInstalled] {
            let popover = ProviderPopoverPresentation(
                snapshot: claude(windows: [try fable()], reason: reason, age: 3_600, statusLine: record), now: now)
            #expect(popover.hasRecentClaudeQuota)
            #expect(popover.quotaFailureReasonText == nil)
            #expect(popover.fableFailureReasonText == reason.displayText)
        }
    }

    @Test func noCopyOffersAnAutomaticSignIn() {
        for reason in [ClaudeQuotaFailureReason.claudeCodeNotInstalled,
                       .claudeCodeCheckFailed, .usageReportFormatChanged] {
            let text = "\(reason.displayText) \(reason.detailText ?? "")"
            for forbidden in ["Keychain", "credential", "Always Allow", "token"] {
                #expect(!text.localizedCaseInsensitiveContains(forbidden), "\(reason) \(forbidden)")
            }
        }
    }
}
