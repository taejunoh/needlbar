import Foundation
import Testing
import NeedlbarClaudeStatusLineSupport
@testable import NeedlbarApp
@testable import NeedlbarCore

// Amendment of 2026-10-22 to the 2026-10-07 refresh-reliability and the
// 2026-09-25 status-line bridge designs, on every app surface: a status-line
// window received more than 24 hours ago is presented exactly like a missing
// one. The observed case is a direct source failing with an expired Claude
// Code access and no direct value since launch, so the only remaining value is
// the persisted status-line cache.
@Suite @MainActor
struct ClaudeStatusLineMaximumAgePresentationTests {
    nonisolated static let now = Date(timeIntervalSince1970: 1_800_000_000)
    nonisolated static let shortText = "Claude Code access on this Mac expired"
    nonisolated static let detailText = "Needlbar reads the access the Claude Code command-line tool saves on this Mac. The Claude desktop app does not renew it, so it updates after Claude Code runs in Terminal."

    // MARK: - Popover, Settings and dashboard (injected clock)

    @Test(arguments: [86_399.0, 86_400.0, 86_401.0])
    func popoverSettingsAndDashboardStopPresentingStatusLineValuesOlderThanTwentyFourHours(age: Double) throws {
        let snapshot = Self.claude(statusLine: Self.record(age: age))
        let popover = ProviderPopoverPresentation(snapshot: snapshot, now: Self.now)
        let settings = SettingsClaudeQuotaPresentation(snapshot: Self.combined(snapshot), now: Self.now).value
        let dashboard = try #require(Self.dashboard(snapshot, now: Self.now).ai.first { $0.provider == .claude })

        // Settings renders the same projection as the popover.
        #expect(settings == popover)
        // Not recent either way, so the reason uses the normal slot.
        #expect(!popover.hasRecentClaudeQuota)
        #expect(popover.headlineQuotaRemaining == nil)
        #expect(popover.quotaFailureReasonText == Self.shortText)
        #expect(popover.quotaFailureDetailText == Self.detailText)
        #expect(popover.fableFailureReasonText == nil)
        #expect(dashboard.quotaFailureReasonText == Self.shortText)
        #expect(dashboard.fable?.statusText == nil)

        if age > 86_400 {
            let missing = Self.claude(statusLine: nil)
            #expect(popover == ProviderPopoverPresentation(snapshot: missing, now: Self.now))
            #expect(dashboard == Self.dashboard(missing, now: Self.now).ai.first { $0.provider == .claude })
            #expect(popover.quotaSourceText == nil)
            #expect(popover.quotaLastCheckedText == nil)
            #expect(popover.lastKnownQuotaRemaining == nil)
            #expect(!popover.quotaIsLastKnown)
            #expect(popover.quotaUnavailable)
            #expect(popover.claudeFiveHour == nil)
            #expect(popover.claudeSevenDay == nil)
            #expect(dashboard.value == "—")
            #expect(dashboard.compactQuotaValue == "—")
            #expect(dashboard.compactQuotaLabel == "Quota remaining")
            #expect(dashboard.quotaSourceText == nil)
            #expect(dashboard.quotaLastCheckedText == nil)
            #expect(dashboard.quotaLastKnownRemaining == nil)
            #expect(!dashboard.quotaIsLastKnown)
            #expect(dashboard.quotaUnavailable)
        } else {
            let received = DateFormatter.localizedString(
                from: Self.now.addingTimeInterval(-age), dateStyle: .medium, timeStyle: .short)
            #expect(popover.quotaSourceText == "Reported by Claude Code")
            #expect(popover.quotaObservationLabel == "Received locally")
            #expect(popover.quotaLastCheckedText == received)
            #expect(popover.lastKnownQuotaRemaining == "87%")
            #expect(popover.quotaIsLastKnown)
            #expect(!popover.quotaUnavailable)
            #expect(popover.claudeFiveHour?.remaining == "87%")
            #expect(popover.claudeFiveHour?.sourceLabel == "Reported by Claude Code")
            #expect(popover.claudeSevenDay?.remaining == "96%")
            #expect(dashboard.value == "—")
            #expect(dashboard.compactQuotaValue == "87%")
            #expect(dashboard.compactQuotaLabel == "Last known")
            #expect(dashboard.quotaSourceText == "Reported by Claude Code")
            #expect(dashboard.quotaLastCheckedText == received)
            #expect(dashboard.quotaLastKnownRemaining == "87%")
        }
    }

    @Test func openSettingsAndDashboardHideTheValueAsTheyCrossTwentyFourHoursWithoutAStoreUpdate() {
        let receivedAt = Self.now.addingTimeInterval(-86_400)
        let snapshot = Self.combined(Self.claude(statusLine: Self.record(age: 86_400)))
        let settings = SettingsClaudeQuotaPresentation(snapshot: snapshot, now: Self.now)
        let dashboard = SystemDashboardModel(snapshot: snapshot, configuration: Self.dashboardConfiguration)
        var frames: [[String?]] = []
        for offset in [0.0, 1.0] {
            let tick = Self.now.addingTimeInterval(offset)
            settings.reproject(at: tick)
            dashboard.reproject(at: tick)
            let claude = dashboard.presentation.ai.first { $0.provider == .claude }
            frames.append([settings.value.lastKnownQuotaRemaining, settings.value.quotaSourceText,
                           claude?.compactQuotaValue, claude?.quotaSourceText])
        }
        #expect(receivedAt.addingTimeInterval(86_400) == Self.now)
        #expect(frames == [["87%", "Reported by Claude Code", "87%", "Reported by Claude Code"],
                           [nil, nil, "—", nil]])
    }

    @Test(arguments: [86_399.0, 86_400.0, 86_401.0])
    func overviewHeadlineFollowsTheSameBoundary(age: Double) {
        let overview = OverviewPopoverPresentation(
            snapshots: [Self.claude(statusLine: Self.record(age: age))], dailyUsage: [], now: Self.now)
        #expect(overview.headlineQuotaRemaining == (age > 86_400 ? nil : "87%"))
        #expect(overview.providerRows.first { $0.provider == .claude }?.quotaSourceText
            == (age > 86_400 ? nil : "Reported by Claude Code"))
    }

    @Test(arguments: [30.0, 15 * 60.0])
    func freshStatusLineValuesAreUnchanged(age: Double) throws {
        let snapshot = Self.claude(statusLine: Self.record(age: age))
        let popover = ProviderPopoverPresentation(snapshot: snapshot, now: Self.now)
        let dashboard = try #require(Self.dashboard(snapshot, now: Self.now).ai.first { $0.provider == .claude })
        #expect(popover.hasRecentClaudeQuota)
        #expect(popover.headlineQuotaRemaining == "87%")
        #expect(popover.quotaSourceText == "Reported by Claude Code")
        #expect(popover.quotaFailureReasonText == nil)
        #expect(popover.fableFailureReasonText == Self.shortText)
        #expect(dashboard.value == "87%")
        #expect(dashboard.compactQuotaValue == "87%")
    }

    @Test(arguments: [86_401.0, 30 * 86_400.0])
    func directLastKnownValuesKeepNoMaximumAge(age: Double) throws {
        let directAt = Self.now.addingTimeInterval(-age)
        let snapshot = ProviderSnapshot(
            provider: .claude, usage: nil,
            quota: QuotaSnapshot(windows: [try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 40, resetsAt: nil)]),
            usageStatus: .unavailable, quotaStatus: .requiresAuthentication, updatedAt: Self.now,
            claudeQuotaFailureReason: .claudeCodeAccessExpired, quotaLastSuccessfulAt: directAt,
            claudeStatusLineQuota: Self.record(age: 86_401))
        let popover = ProviderPopoverPresentation(snapshot: snapshot, now: Self.now)
        #expect(popover.quotaSourceText == "Claude usage")
        #expect(popover.quotaObservationLabel == "Last checked")
        #expect(popover.quotaLastCheckedText == DateFormatter.localizedString(from: directAt, dateStyle: .medium, timeStyle: .short))
        #expect(popover.lastKnownQuotaRemaining == "60%")
        #expect(popover.quotaIsLastKnown)
        #expect(popover.quotaFailureReasonText == Self.shortText)
        #expect(HeadlineQuotaSelector.mostConstrained([snapshot], now: Self.now)?.remainingPercent == 60)
    }

    // MARK: - Menu bar (renderers read the wall clock; one-hour margins)

    @Test(arguments: [false, true])
    func menuBarTitlesStopShowingStatusLineValuesOlderThanTwentyFourHours(older: Bool) throws {
        let wallNow = Date()
        let age = 86_400 + (older ? 3_600.0 : -3_600.0)
        let record = Self.record(age: age, relativeTo: wallNow)
        let claude = Self.claude(statusLine: record, at: wallNow)
        let codex = ProviderSnapshot(
            provider: .codex, usage: nil,
            quota: QuotaSnapshot(windows: [try QuotaWindow(id: "codex.primary", title: "Primary", usedPercent: 45, resetsAt: nil)]),
            usageStatus: .unavailable, quotaStatus: .fresh, updatedAt: wallNow, quotaLastSuccessfulAt: wallNow)

        let suite = "ClaudeStatusLineMaximumAge.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = ModuleConfiguration(defaults: defaults)
        configuration.claude = ModuleSettings(isEnabled: true, metric: .quotaRemaining)
        configuration.codex = ModuleSettings(isEnabled: true, metric: .quotaRemaining)
        let providerTitle = MenuBarTitleRenderer.render(
            module: .claude, snapshot: claude, allSnapshots: [claude, codex], configuration: configuration)
        let overviewTitle = MenuBarTitleRenderer.render(
            module: .overview, snapshot: nil, allSnapshots: [claude, codex], configuration: configuration)
        #expect(providerTitle == (older ? "Claude —" : "Claude 87%"))
        #expect(overviewTitle == "AI 55%")

        let lowClaude = Self.claude(statusLine: Self.record(age: age, relativeTo: wallNow, fiveHourUsed: 70), at: wallNow)
        #expect(MenuBarTitleRenderer.render(
            module: .overview, snapshot: nil, allSnapshots: [lowClaude, codex], configuration: configuration)
            == (older ? "AI 55%" : "AI 30%"))

        var menuConfiguration = SystemMonitorConfiguration()
        menuConfiguration.menuBarVisibleModules = [.ai]
        let combined = CombinedUsageSnapshot(system: nil, providers: [claude, codex], capturedAt: wallNow, systemAvailability: [:])
        let withoutStatusLine = CombinedUsageSnapshot(
            system: nil, providers: [Self.claude(statusLine: nil, at: wallNow), codex], capturedAt: wallNow, systemAvailability: [:])
        let rendered = MenuBarDashboardRenderer.render(snapshot: combined, configuration: menuConfiguration, availableWidth: 400)
        #expect(rendered.tooltip.contains(older ? "Claude —" : "Claude 87%"))
        if older {
            #expect(rendered == MenuBarDashboardRenderer.render(
                snapshot: withoutStatusLine, configuration: menuConfiguration, availableWidth: 400))
        }
    }

    // MARK: - Fixtures

    static var dashboardConfiguration: SystemMonitorConfiguration {
        SystemMonitorConfiguration(aiOrder: [.claude, .codex, .cursor], dashboardVisibleModules: [.ai])
    }

    static func record(age: TimeInterval, relativeTo reference: Date = now, fiveHourUsed: Double = 13) -> StatusLineQuotaRecord {
        let receivedAt = reference.addingTimeInterval(-age)
        return StatusLineQuotaRecord(
            schemaVersion: StatusLineQuotaRecord.currentSchemaVersion,
            generation: UUID(uuidString: "00000000-0000-0000-0000-000000001022")!,
            fiveHour: .init(usedPercent: fiveHourUsed, resetsAt: nil, receivedAt: receivedAt),
            sevenDay: .init(usedPercent: 4, resetsAt: reference.addingTimeInterval(3 * 86_400), receivedAt: receivedAt))
    }

    /// No direct value since launch, a direct failure with an expired Claude
    /// Code access, and an optional persisted status-line record.
    static func claude(statusLine: StatusLineQuotaRecord?, at reference: Date = now) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: .claude, usage: nil, quota: nil,
            usageStatus: .unavailable, quotaStatus: .requiresAuthentication, updatedAt: reference,
            claudeQuotaFailureReason: .claudeCodeAccessExpired, claudeStatusLineQuota: statusLine)
    }

    static func combined(_ claude: ProviderSnapshot) -> CombinedUsageSnapshot {
        CombinedUsageSnapshot(system: nil, providers: [claude], capturedAt: now, systemAvailability: [:])
    }

    static func dashboard(_ claude: ProviderSnapshot, now: Date) -> SystemDashboardPresentation {
        SystemDashboardPresentation(snapshot: combined(claude), configuration: dashboardConfiguration, now: now)
    }
}
