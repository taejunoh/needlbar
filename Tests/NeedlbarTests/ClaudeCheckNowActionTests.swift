import AppKit
import Foundation
import SwiftUI
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore
import NeedlbarClaudeStatusLineSupport

// The manual "Check now" control for Claude quota, on the dashboard and in
// Settings. The real SwiftUI surfaces are hosted and pressed through their
// accessibility tree. Everything is synthetic: nothing here runs `claude`,
// touches credentials, or starts an app. The closures count calls and stop there.
@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct ClaudeCheckNowActionTests {
    nonisolated static let now = Date()
    nonisolated static let title = "Check now"
    nonisolated static let allReasons: [ClaudeQuotaFailureReason] = [
        .quotaAccessUnavailable, .connectionUnavailable, .temporarilyLimited, .couldNotUpdateQuota,
        .claudeCodeNotInstalled, .claudeCodeCheckFailed, .usageReportFormatChanged,
    ]

    // MARK: - The action and its copy

    @Test func theActionUsesTheExactTitleAndALocalizedKey() {
        #expect(ClaudeCheckNowAction.checkNow.title == Self.title)
        #expect(String(localized: "claudeQuota.action.checkNow", defaultValue: "Check now") == Self.title)
    }

    // MARK: - Dashboard model

    @Test func theModelExposesTheActionInSuccessAndEveryFailureState() throws {
        for statusLine in [nil, Self.recentStatusLine()] {
            let healthy = try Self.claude(reason: nil, statusLine: statusLine)
            #expect(Self.dashboardRow(healthy)?.checkNowAction == .checkNow, "healthy")

            for reason in Self.allReasons {
                let failed = try Self.claude(reason: reason, statusLine: statusLine)
                #expect(Self.dashboardRow(failed)?.checkNowAction == .checkNow, "\(reason)")
            }
        }
        for status in [DataStatus.requiresAuthentication, .unavailable, .stale(lastSuccessfulAt: Self.now),
                       .error(message: "failed", lastSuccessfulAt: nil)] {
            let snapshot = ProviderSnapshot(
                provider: .claude, usage: nil, quota: nil, usageStatus: .fresh,
                quotaStatus: status, updatedAt: Self.now)
            #expect(Self.dashboardRow(snapshot)?.checkNowAction == .checkNow, "\(status)")
        }
    }

    @Test func theActionIsOnlyOnTheClaudeRow() throws {
        let presentation = SystemDashboardPresentation(
            snapshot: Self.combined(try Self.claude(reason: nil, statusLine: nil)),
            configuration: Self.dashboardConfiguration(), now: Self.now)
        #expect(presentation.ai.filter { $0.checkNowAction != nil }.map(\.provider) == [.claude])
    }

    @Test func theModelHidesTheActionWhenClaudeIsDisabled() throws {
        var configuration = Self.dashboardConfiguration()
        configuration.ai[.claude]?.dashboardVisible = false
        for reason in [nil] + Self.allReasons.map(Optional.some) {
            let presentation = SystemDashboardPresentation(
                snapshot: Self.combined(try Self.claude(reason: reason, statusLine: nil)),
                configuration: configuration, now: Self.now)
            #expect(!presentation.ai.contains { $0.provider == .claude })
            #expect(presentation.ai.allSatisfy { $0.checkNowAction == nil }, "\(String(describing: reason))")
        }
    }

    // MARK: - Dashboard view

    @Test func theDashboardRendersOneButtonInEveryStateAndNoneWhenClaudeIsDisabled() throws {
        for metric in [AIProviderDisplayMetric.remaining, .usage] {
            for reason in [nil] + Self.allReasons.map(Optional.some) {
                let snapshot = try Self.claude(reason: reason, statusLine: nil)
                try Self.hostedDashboard(snapshot, metric: metric) { hosted, _ in
                    #expect(hosted.buttons.filter { $0 == Self.title }.count == 1,
                            "\(metric) \(String(describing: reason)) \(hosted.buttons)")
                    #expect(hosted.buttons.contains("Usage") || hosted.buttons.contains("View Claude usage"))
                }
            }

            var disabled = Self.dashboardConfiguration(metric: metric)
            disabled.ai[.claude]?.dashboardVisible = false
            try Self.hostedDashboard(try Self.claude(reason: nil, statusLine: nil), configuration: disabled) { hosted, _ in
                #expect(!hosted.buttons.contains(Self.title), "\(hosted.buttons)")
            }
        }
    }

    @Test func aDashboardClickReachesTheRefreshClosureOnceAndNothingElse() throws {
        for metric in [AIProviderDisplayMetric.remaining, .usage] {
            let snapshot = try Self.claude(reason: .couldNotUpdateQuota, statusLine: nil)
            try Self.hostedDashboard(snapshot, metric: metric) { hosted, counts in
                #expect(counts.checks == 0, "rendering must not refresh")
                try hosted.press(Self.title)
                #expect(counts.checks == 1, "\(metric)")
                #expect(counts.others == 0, "the click must not open Settings, Analytics, login or the usage page")
            }
        }
    }

    // MARK: - Settings

    @Test func settingsShowsTheButtonBesideViewClaudeUsageInEveryState() throws {
        for reason in [nil] + Self.allReasons.map(Optional.some) {
            let snapshot = try Self.claude(reason: reason, statusLine: nil)
            try Self.hostedSettingsRow(snapshot) { hosted, _ in
                #expect(hosted.buttons.filter { $0 == Self.title }.count == 1, "\(String(describing: reason)) \(hosted.buttons)")
                #expect(hosted.buttons.contains("View Claude usage"))
            }
        }
    }

    @Test func settingsHidesTheButtonOnlyWhenClaudeIsOffOnBothSurfaces() throws {
        let snapshot = try Self.claude(reason: nil, statusLine: nil)
        let base = "needlbar.systemMonitor.ai.claude"

        try Self.hostedSettingsRow(snapshot, defaults: { $0.set(false, forKey: "\(base).visible") }) { hosted, _ in
            #expect(!hosted.buttons.contains(Self.title), "\(hosted.buttons)")
            #expect(hosted.buttons.contains("View Claude usage"))
        }
        try Self.hostedSettingsRow(snapshot, defaults: {
            $0.set(false, forKey: "\(base).menuBar.visible")
            $0.set(false, forKey: "\(base).dashboard.visible")
        }) { hosted, _ in
            #expect(!hosted.buttons.contains(Self.title))
        }
        for surface in ["menuBar", "dashboard"] {
            try Self.hostedSettingsRow(snapshot, defaults: { $0.set(false, forKey: "\(base).\(surface).visible") }) { hosted, _ in
                #expect(hosted.buttons.contains(Self.title), "visible on the other surface than \(surface)")
            }
        }
    }

    @Test func aSettingsClickReachesTheRefreshClosureOnceAndNothingElse() throws {
        let snapshot = try Self.claude(reason: .claudeCodeCheckFailed, statusLine: nil)
        try Self.hostedSettingsRow(snapshot) { hosted, counts in
            #expect(counts.checks == 0, "rendering must not refresh")
            try hosted.press(Self.title)
            #expect(counts.checks == 1)
            #expect(counts.others == 0, "the click must not open the usage page")
        }
    }

    @Test func settingsActionsWithoutAnOperationIgnoreTheRequest() {
        SettingsActions().checkClaudeNow()
    }

    @Test func settingsActionsRunTheOperationOncePerRequest() {
        var runs = 0
        let actions = SettingsActions(claudeCheckNow: { runs += 1 })
        actions.checkClaudeNow()
        #expect(runs == 1)
        actions.checkClaudeNow()
        #expect(runs == 2, "no state: each request goes to the refresh, which joins a run in flight")
    }
}

// MARK: - Counting

@MainActor
private final class Counts {
    var checks = 0
    var others = 0
}

// MARK: - Fixtures

extension ClaudeCheckNowActionTests {
    static func dashboardConfiguration(metric: AIProviderDisplayMetric = .remaining) -> SystemMonitorConfiguration {
        var configuration = SystemMonitorConfiguration(aiOrder: [.claude, .codex, .cursor], dashboardVisibleModules: [.ai])
        configuration.ai[.claude]?.metric = metric
        return configuration
    }

    static func recentStatusLine() -> StatusLineQuotaRecord {
        StatusLineQuotaRecord(schemaVersion: 1, generation: UUID(uuidString: "00000000-0000-0000-0000-000000001103")!,
            fiveHour: .init(usedPercent: 25, resetsAt: now.addingTimeInterval(3_600), receivedAt: now.addingTimeInterval(-30)),
            sevenDay: .init(usedPercent: 35, resetsAt: now.addingTimeInterval(86_400), receivedAt: now.addingTimeInterval(-30)))
    }

    static func claude(reason: ClaudeQuotaFailureReason?, statusLine: StatusLineQuotaRecord?) throws -> ProviderSnapshot {
        let directAt = now.addingTimeInterval(-3_600)
        return ProviderSnapshot(
            provider: .claude,
            usage: nil,
            quota: QuotaSnapshot(windows: try [
                QuotaWindow(id: "claude.session", title: "Session", usedPercent: 68, resetsAt: directAt.addingTimeInterval(7_200)),
                QuotaWindow(id: "claude.weekly", title: "Weekly", usedPercent: 53, resetsAt: directAt.addingTimeInterval(86_400)),
                QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "Fable weekly", usedPercent: 42, resetsAt: directAt.addingTimeInterval(86_400)),
            ]),
            usageStatus: .fresh,
            quotaStatus: reason == nil ? .fresh : .error(message: "failed", lastSuccessfulAt: directAt),
            updatedAt: now.addingTimeInterval(-600),
            claudeQuotaFailureReason: reason,
            quotaLastSuccessfulAt: directAt,
            claudeStatusLineQuota: statusLine
        )
    }

    static func combined(_ claude: ProviderSnapshot) -> CombinedUsageSnapshot {
        CombinedUsageSnapshot(system: nil, providers: [
            claude,
            ProviderSnapshot(provider: .codex, usage: nil, quota: nil, usageStatus: .fresh, quotaStatus: .unavailable, updatedAt: now),
            ProviderSnapshot(provider: .cursor, usage: nil, quota: nil, usageStatus: .fresh, quotaStatus: .unavailable, updatedAt: now),
        ], capturedAt: now, systemAvailability: [:])
    }

    static func dashboardRow(_ claude: ProviderSnapshot) -> SystemDashboardPresentation.AIProvider? {
        SystemDashboardPresentation(snapshot: combined(claude), configuration: dashboardConfiguration(), now: now)
            .ai.first { $0.provider == .claude }
    }

    fileprivate static func hostedDashboard(
        _ snapshot: ProviderSnapshot,
        metric: AIProviderDisplayMetric = .remaining,
        configuration: SystemMonitorConfiguration? = nil,
        body: (AccessibilityHostedView, Counts) throws -> Void
    ) throws {
        let counts = Counts()
        let layout = SystemDashboardPopoverLayout(height: 900)
        layout.quotaDetailsExpanded = true
        let model = SystemDashboardModel(
            snapshot: combined(snapshot), configuration: configuration ?? dashboardConfiguration(metric: metric))
        let view = SystemDashboardPopoverView(
            model: model,
            layout: layout,
            onShowSettings: { counts.others += 1 },
            onShowAnalytics: { counts.others += 1 },
            onProviderAction: { _ in counts.others += 1 },
            onAPIBillingAction: { _ in counts.others += 1; return false },
            onClaudeUsageAction: { counts.others += 1; return true },
            onClaudeCheckNow: { counts.checks += 1 })
        try AccessibilityHostedView(view, body: { try body($0, counts) })
    }

    fileprivate static func hostedSettingsRow(
        _ snapshot: ProviderSnapshot,
        defaults configure: (UserDefaults) -> Void = { _ in },
        body: (AccessibilityHostedView, Counts) throws -> Void
    ) throws {
        let counts = Counts()
        let name = "ClaudeCheckNow.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        configure(defaults)
        let preferences = QuotaNotificationPreferences(defaults: defaults)
        let row = SettingsView(
            configuration: ModuleConfiguration(defaults: defaults),
            actions: SettingsActions(claudeCheckNow: { counts.checks += 1 }),
            notificationPreferences: preferences,
            notificationService: QuotaNotificationService(store: ProviderSnapshotStore(), preferences: preferences),
            openCursorSpending: {},
            openClaudeUsage: { counts.others += 1; return true },
            claudeQuotaPresentation: SettingsClaudeQuotaPresentation(snapshot: combined(snapshot), now: now)
        ).claudeUsageRowContent
        try AccessibilityHostedView(row, body: { try body($0, counts) })
    }
}
