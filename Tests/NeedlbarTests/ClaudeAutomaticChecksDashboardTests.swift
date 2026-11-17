import Foundation
import SwiftUI
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

// The dashboard Claude row while automatic checks are off: a neutral caption and
// a "Turn on" button beside "Check now". Everything is synthetic; the closures
// count calls and stop there.
@Suite("ClaudeAutomaticChecksDashboard", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct ClaudeAutomaticChecksDashboardTests {
    nonisolated static let now = ClaudeCheckNowActionTests.now

    // MARK: - Presentation

    @Test func thePromptIsOnTheClaudeRowOnlyAndOnlyWhileOff() throws {
        let snapshot = ClaudeCheckNowActionTests.combined(try ClaudeCheckNowActionTests.claude(reason: nil, statusLine: nil))
        let off = Self.presentation(snapshot, off: true)
        #expect(off.ai.filter { $0.automaticChecksPrompt != nil }.map(\.provider) == [.claude])
        #expect(Self.claudeRow(off)?.automaticChecksPrompt == .turnOn)
        #expect(ClaudeAutomaticChecksPrompt.turnOn.caption == "Automatic checks are off.")
        #expect(ClaudeAutomaticChecksPrompt.turnOn.actionTitle == "Turn on")

        let on = Self.presentation(snapshot, off: false)
        #expect(on.ai.allSatisfy { $0.automaticChecksPrompt == nil })
        let unstated = SystemDashboardPresentation(
            snapshot: snapshot, configuration: ClaudeCheckNowActionTests.dashboardConfiguration(), now: Self.now)
        #expect(unstated.ai.allSatisfy { $0.automaticChecksPrompt == nil }, "no prompt unless the caller says off")
    }

    @Test func offWithNoReadingAndNoRunTriedIsNeutral() throws {
        for metric in [AIProviderDisplayMetric.remaining, .usage] {
            let row = try #require(Self.claudeRow(Self.presentation(
                ClaudeCheckNowActionTests.combined(Self.neverChecked()), off: true, metric: metric)))
            #expect(row.automaticChecksPrompt?.caption == "Automatic checks are off.")
            #expect(row.statusText == nil, "no orange status")
            #expect(row.quotaFailureReasonText == nil, "no Could not update")
            #expect(row.quotaStatus == .unavailable, "no error state")
            #expect(row.compactQuotaValue == "—")
        }
    }

    @Test func aFailureFromAManualRunStillShowsAsToday() throws {
        let failed = ProviderSnapshot(
            provider: .claude, usage: nil, quota: nil, usageStatus: .fresh,
            quotaStatus: .error(message: "failed", lastSuccessfulAt: nil), updatedAt: Self.now,
            claudeQuotaFailureReason: .claudeCodeNotInstalled)
        let off = try #require(Self.claudeRow(Self.presentation(ClaudeCheckNowActionTests.combined(failed), off: true)))
        let on = try #require(Self.claudeRow(Self.presentation(ClaudeCheckNowActionTests.combined(failed), off: false)))
        #expect(off.quotaFailureReasonText == "Install Claude Code to see quota")
        #expect(off.quotaFailureReasonText == on.quotaFailureReasonText)
        #expect(off.statusText == on.statusText)
        #expect(off.automaticChecksPrompt == .turnOn, "the prompt stays beside the failure")
    }

    @Test func aRowWithAReadingIsUnchangedApartFromThePrompt() throws {
        let snapshot = ClaudeCheckNowActionTests.combined(try ClaudeCheckNowActionTests.claude(reason: nil, statusLine: nil))
        let off = try #require(Self.claudeRow(Self.presentation(snapshot, off: true)))
        let on = try #require(Self.claudeRow(Self.presentation(snapshot, off: false)))
        #expect(off.value == on.value)
        #expect(off.compactQuotaValue == on.compactQuotaValue)
        #expect(off.compactQuotaLabel == on.compactQuotaLabel)
        #expect(off.statusText == on.statusText)
        #expect(off.quotaIsLastKnown == on.quotaIsLastKnown)
        #expect(off.checkNowAction == .checkNow)
    }

    @Test func theModelKeepsTheStateAcrossUpdatesAndReprojection() throws {
        let snapshot = ClaudeCheckNowActionTests.combined(Self.neverChecked())
        let configuration = ClaudeCheckNowActionTests.dashboardConfiguration()
        let model = SystemDashboardModel(snapshot: snapshot, configuration: configuration, claudeAutomaticChecksOff: true)
        #expect(Self.claudeRow(model.presentation)?.automaticChecksPrompt == .turnOn)
        model.reproject(at: Self.now.addingTimeInterval(60))
        #expect(Self.claudeRow(model.presentation)?.automaticChecksPrompt == .turnOn)
        model.update(snapshot: snapshot, configuration: configuration, claudeAutomaticChecksOff: false)
        model.reproject(at: Self.now.addingTimeInterval(120))
        #expect(Self.claudeRow(model.presentation)?.automaticChecksPrompt == nil)
    }

    // MARK: - View

    @Test func bothLayoutsShowOneTurnOnButtonBesideCheckNowOnlyWhileOff() throws {
        for metric in [AIProviderDisplayMetric.remaining, .usage] {
            try Self.hostedDashboard(off: true, metric: metric) { hosted, _ in
                #expect(hosted.buttons.filter { $0 == "Turn on" }.count == 1, "\(metric) \(hosted.buttons)")
                #expect(hosted.buttons.filter { $0 == "Check now" }.count == 1, "\(metric) \(hosted.buttons)")
            }
            try Self.hostedDashboard(off: false, metric: metric) { hosted, _ in
                #expect(!hosted.buttons.contains("Turn on"), "\(metric) \(hosted.buttons)")
                #expect(hosted.buttons.filter { $0 == "Check now" }.count == 1)
            }
        }
    }

    @Test func turnOnReachesItsClosureOnceAndNothingElse() throws {
        for metric in [AIProviderDisplayMetric.remaining, .usage] {
            try Self.hostedDashboard(off: true, metric: metric) { hosted, counts in
                #expect(counts.turnOns == 0, "rendering must not turn anything on")
                try hosted.press("Turn on")
                #expect(counts.turnOns == 1, "\(metric)")
                #expect(counts.checks == 0, "Turn on is not Check now")
                #expect(counts.others == 0)
                try hosted.press("Check now")
                #expect(counts.checks == 1)
                #expect(counts.turnOns == 1, "Check now does not turn the schedule on")
            }
        }
    }
}

@MainActor
private final class Counts {
    var turnOns = 0
    var checks = 0
    var others = 0
}

extension ClaudeAutomaticChecksDashboardTests {
    /// Claude as the store reports it before any run: no quota, no failure reason.
    static func neverChecked() -> ProviderSnapshot {
        ProviderSnapshot(
            provider: .claude, usage: nil, quota: nil, usageStatus: .fresh,
            quotaStatus: .unavailable, updatedAt: now)
    }

    static func presentation(
        _ snapshot: CombinedUsageSnapshot, off: Bool, metric: AIProviderDisplayMetric = .remaining
    ) -> SystemDashboardPresentation {
        SystemDashboardPresentation(
            snapshot: snapshot, configuration: ClaudeCheckNowActionTests.dashboardConfiguration(metric: metric),
            claudeAutomaticChecksOff: off, now: now)
    }

    static func claudeRow(_ presentation: SystemDashboardPresentation) -> SystemDashboardPresentation.AIProvider? {
        presentation.ai.first { $0.provider == .claude }
    }

    fileprivate static func hostedDashboard(
        off: Bool,
        metric: AIProviderDisplayMetric,
        body: (AccessibilityHostedView, Counts) throws -> Void
    ) throws {
        let counts = Counts()
        let layout = SystemDashboardPopoverLayout(height: 900)
        let model = SystemDashboardModel(
            snapshot: ClaudeCheckNowActionTests.combined(neverChecked()),
            configuration: ClaudeCheckNowActionTests.dashboardConfiguration(metric: metric),
            claudeAutomaticChecksOff: off)
        let view = SystemDashboardPopoverView(
            model: model,
            layout: layout,
            onShowSettings: { counts.others += 1 },
            onShowAnalytics: { counts.others += 1 },
            onProviderAction: { _ in counts.others += 1 },
            onAPIBillingAction: { _ in counts.others += 1; return false },
            onClaudeUsageAction: { counts.others += 1; return true },
            onClaudeCheckNow: { counts.checks += 1 },
            onClaudeAutomaticChecksTurnOn: { counts.turnOns += 1 })
        try AccessibilityHostedView(view, body: { try body($0, counts) })
    }
}
