import Foundation
import NeedlbarClaudeStatusLineSupport
import NeedlbarWidgetSupport
import Testing
@testable import NeedlbarCore

// Amendment of 2026-10-22 to
// docs/superpowers/specs/2026-10-07-claude-refresh-reliability-design.md and
// docs/superpowers/specs/2026-09-25-claude-statusline-quota-bridge-design.md:
// a Claude Code status-line window received more than 24 hours before the
// injected current time is treated exactly like a missing status-line window.
// Direct observations, and status-line receipt times that are not usable
// (future or non-finite), keep their existing handling.
@Suite("ClaudeStatusLineMaximumAgeTests")
struct ClaudeStatusLineMaximumAgeTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let day: TimeInterval = 86_400

    // MARK: - Boundary

    @Test(arguments: [86_399.0, 86_400.0, 86_401.0])
    func statusLineWindowsArePresentedUpToAndIncludingTwentyFourHours(age: Double) {
        let selected = ClaudeQuotaPresentationSelector.select(
            snapshot: Self.claude(statusLine: Self.record(fiveHourAge: age, sevenDayAge: age)), now: Self.now)
        if age > Self.day {
            #expect(selected.fiveHour == nil)
            #expect(selected.sevenDay == nil)
        } else {
            #expect(selected.fiveHour == DisplayedClaudeWindow(
                remainingPercent: 87, source: .claudeCodeStatusLine,
                observedAt: Self.now.addingTimeInterval(-age), resetsAt: nil, isLastKnown: true))
            #expect(selected.sevenDay == DisplayedClaudeWindow(
                remainingPercent: 96, source: .claudeCodeStatusLine,
                observedAt: Self.now.addingTimeInterval(-age), resetsAt: Self.sevenDayReset, isLastKnown: true))
        }
        #expect(selected.fable == nil)
    }

    @Test func windowsAgeIndependentlyByTheirOwnReceiptTime() {
        let selected = ClaudeQuotaPresentationSelector.select(
            snapshot: Self.claude(statusLine: Self.record(fiveHourAge: Self.day + 1, sevenDayAge: Self.day - 1)),
            now: Self.now)
        #expect(selected.fiveHour == nil)
        #expect(selected.sevenDay?.source == .claudeCodeStatusLine)
        #expect(selected.sevenDay?.observedAt == Self.now.addingTimeInterval(-(Self.day - 1)))
        #expect(selected.sevenDay?.isLastKnown == true)
    }

    // MARK: - Exactly like a missing status-line window

    enum Direct: CaseIterable, Sendable {
        case none, current, olderLastKnown, undatedLastKnown
    }

    @Test(arguments: Direct.allCases, [86_401.0, 15 * 86_400.0])
    func olderStatusLineSelectsExactlyAsWithoutAStatusLineRecord(direct: Direct, age: Double) throws {
        let stale = try Self.claude(direct: direct, statusLine: Self.record(fiveHourAge: age, sevenDayAge: age))
        let missing = try Self.claude(direct: direct, statusLine: nil)
        #expect(ClaudeQuotaPresentationSelector.select(snapshot: stale, now: Self.now)
            == ClaudeQuotaPresentationSelector.select(snapshot: missing, now: Self.now))
    }

    @Test func olderDirectLastKnownIsShownOnceTheNewerStatusLineIsOlderThanTwentyFourHours() throws {
        // Direct 30 hours old, status line 25 hours old: the status line was the
        // most recent last-known value; past the limit it no longer competes.
        let snapshot = try Self.claude(direct: .olderLastKnown,
                                       statusLine: Self.record(fiveHourAge: 25 * 3_600, sevenDayAge: 25 * 3_600))
        let selected = ClaudeQuotaPresentationSelector.select(snapshot: snapshot, now: Self.now)
        #expect(selected.fiveHour?.source == .direct)
        #expect(selected.fiveHour?.observedAt == Self.now.addingTimeInterval(-30 * 3_600))
        #expect(selected.fiveHour?.isLastKnown == true)
    }

    // MARK: - Unchanged behaviour

    @Test(arguments: [30.0, 900.0, 901.0])
    func freshAndRecentlyLastKnownStatusLineValuesAreUnchanged(age: Double) {
        let selected = ClaudeQuotaPresentationSelector.select(
            snapshot: Self.claude(statusLine: Self.record(fiveHourAge: age, sevenDayAge: age)), now: Self.now)
        #expect(selected.fiveHour?.remainingPercent == 87)
        #expect(selected.fiveHour?.observedAt == Self.now.addingTimeInterval(-age))
        #expect(selected.fiveHour?.isLastKnown == (age > 15 * 60))
    }

    @Test(arguments: [86_401.0, 30 * 86_400.0])
    func directValuesKeepNoMaximumAge(age: Double) throws {
        let snapshot = ProviderSnapshot(
            provider: .claude, usage: nil,
            quota: QuotaSnapshot(windows: [
                try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 13, resetsAt: nil),
                try QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "Fable weekly", usedPercent: 20, resetsAt: nil),
            ]),
            usageStatus: .unavailable, quotaStatus: .requiresAuthentication, updatedAt: Self.now,
            claudeQuotaFailureReason: .claudeCodeAccessExpired,
            quotaLastSuccessfulAt: Self.now.addingTimeInterval(-age))
        let selected = ClaudeQuotaPresentationSelector.select(snapshot: snapshot, now: Self.now)
        #expect(selected.fiveHour?.source == .direct)
        #expect(selected.fiveHour?.remainingPercent == 87)
        #expect(selected.fiveHour?.observedAt == Self.now.addingTimeInterval(-age))
        #expect(selected.fiveHour?.isLastKnown == true)
        #expect(selected.fable?.observedAt == Self.now.addingTimeInterval(-age))
        #expect(selected.fable?.isLastKnown == true)
    }

    /// Future-dated receipt times have no usable age. As before, such a window
    /// stays an undated last-known value that ranks behind dated values; the
    /// maximum age neither hides nor freshens it. (The private store already
    /// rejects non-finite receipt times on read; the selector keeps treating
    /// them the same way as future ones.)
    @Test(arguments: [1.0, 3_600, 30 * 86_400.0, .infinity, .nan])
    func unusableReceiptTimesKeepTheirExistingUndatedLastKnownHandling(offset: Double) throws {
        let receivedAt = offset.isNaN ? Date(timeIntervalSince1970: .nan) : Self.now.addingTimeInterval(offset)
        let record = StatusLineQuotaRecord(
            schemaVersion: StatusLineQuotaRecord.currentSchemaVersion, generation: Self.generation,
            fiveHour: .init(usedPercent: 13, resetsAt: nil, receivedAt: receivedAt), sevenDay: nil)
        let bridgeOnly = ClaudeQuotaPresentationSelector.select(snapshot: Self.claude(statusLine: record), now: Self.now)
        #expect(bridgeOnly.fiveHour == DisplayedClaudeWindow(
            remainingPercent: 87, source: .claudeCodeStatusLine, observedAt: nil, resetsAt: nil, isLastKnown: true))

        let withDatedDirect = ClaudeQuotaPresentationSelector.select(
            snapshot: try Self.claude(direct: .olderLastKnown, statusLine: record), now: Self.now)
        #expect(withDatedDirect.fiveHour?.source == .direct)
    }

    // MARK: - Menu bar value source

    @Test(arguments: [86_399.0, 86_400.0, 86_401.0])
    func headlineQuotaUsedByTheMenuBarAndOverviewFollowsTheSameBoundary(age: Double) throws {
        let claude = Self.claude(statusLine: Self.record(fiveHourAge: age, sevenDayAge: age))
        let codex = ProviderSnapshot(
            provider: .codex, usage: nil,
            quota: QuotaSnapshot(windows: [try QuotaWindow(id: "codex.primary", title: "Primary", usedPercent: 45, resetsAt: nil)]),
            usageStatus: .unavailable, quotaStatus: .fresh, updatedAt: Self.now, quotaLastSuccessfulAt: Self.now)
        let claudeOnly = HeadlineQuotaSelector.mostConstrained([claude], now: Self.now)
        let overview = HeadlineQuotaSelector.mostConstrained([claude, codex], now: Self.now)
        if age > Self.day {
            #expect(claudeOnly == nil)
            #expect(overview?.id == "codex.primary")
        } else {
            #expect(claudeOnly?.id == "claude.session")
            #expect(claudeOnly?.remainingPercent == 87)
            #expect(overview?.id == "codex.primary")
            #expect(overview?.remainingPercent == 55)
        }
    }

    // MARK: - Widget, export and alerts never take status-line values

    @Test(arguments: [nil, 30.0, 86_399.0, 86_401.0, 15 * 86_400.0] as [Double?])
    func widgetExportAndAlertCapturesAreIndependentOfStatusLineAge(age: Double?) async throws {
        func outputs(statusLine: StatusLineQuotaRecord?) async throws -> (widget: Data, export: Data, alerts: [QuotaAlertSample]) {
            let store = ProviderSnapshotStore(now: { Self.now })
            await store.markQuotaFailure(for: .claude, status: .requiresAuthentication,
                                         claudeFailureReason: .claudeCodeAccessExpired, at: Self.now.addingTimeInterval(-60))
            await store.applyQuota(QuotaSnapshot(windows: [
                try QuotaWindow(id: "codex.primary", title: "Primary", usedPercent: 45, resetsAt: Self.now.addingTimeInterval(3_600)),
            ]), for: .codex, at: Self.now.addingTimeInterval(-60))
            if let statusLine { await store.applyClaudeStatusLineQuota(statusLine) }
            return (
                try WidgetProjection.encode(
                    try WidgetProjectionMapper(now: Self.now).map(await store.captureForWidget(exportedAt: Self.now))),
                try SnapshotExporter().encode(await store.captureForExport(exportedAt: Self.now)),
                await store.quotaAlertCapture())
        }
        let withRecord = try await outputs(statusLine: age.map { Self.record(fiveHourAge: $0, sevenDayAge: $0) })
        let withoutRecord = try await outputs(statusLine: nil)
        #expect(withRecord.widget == withoutRecord.widget)
        #expect(withRecord.export == withoutRecord.export)
        #expect(withRecord.alerts == withoutRecord.alerts)
        #expect(withRecord.alerts.first { $0.provider == .claude }?.quota == nil)
    }

    // MARK: - Fixtures

    static let generation = UUID(uuidString: "00000000-0000-0000-0000-000000001022")!
    static let sevenDayReset = now.addingTimeInterval(3 * day)

    static func record(fiveHourAge: TimeInterval, sevenDayAge: TimeInterval) -> StatusLineQuotaRecord {
        StatusLineQuotaRecord(
            schemaVersion: StatusLineQuotaRecord.currentSchemaVersion, generation: generation,
            fiveHour: .init(usedPercent: 13, resetsAt: nil, receivedAt: now.addingTimeInterval(-fiveHourAge)),
            sevenDay: .init(usedPercent: 4, resetsAt: sevenDayReset, receivedAt: now.addingTimeInterval(-sevenDayAge)))
    }

    static func claude(statusLine: StatusLineQuotaRecord?) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: .claude, usage: nil, quota: nil,
            usageStatus: .unavailable, quotaStatus: .requiresAuthentication, updatedAt: now,
            claudeQuotaFailureReason: .claudeCodeAccessExpired, claudeStatusLineQuota: statusLine)
    }

    static func claude(direct: Direct, statusLine: StatusLineQuotaRecord?) throws -> ProviderSnapshot {
        let windows = try [
            QuotaWindow(id: "claude.session", title: "Session", usedPercent: 50, resetsAt: nil),
            QuotaWindow(id: "claude.weekly", title: "Weekly", usedPercent: 60, resetsAt: nil),
        ]
        switch direct {
        case .none:
            return claude(statusLine: statusLine)
        case .current:
            return ProviderSnapshot(
                provider: .claude, usage: nil, quota: QuotaSnapshot(windows: windows),
                usageStatus: .unavailable, quotaStatus: .fresh, updatedAt: now,
                quotaLastSuccessfulAt: now.addingTimeInterval(-60), claudeStatusLineQuota: statusLine)
        case .olderLastKnown, .undatedLastKnown:
            return ProviderSnapshot(
                provider: .claude, usage: nil, quota: QuotaSnapshot(windows: windows),
                usageStatus: .unavailable, quotaStatus: .requiresAuthentication, updatedAt: now,
                claudeQuotaFailureReason: .claudeCodeAccessExpired,
                quotaLastSuccessfulAt: direct == .olderLastKnown ? now.addingTimeInterval(-30 * 3_600) : nil,
                claudeStatusLineQuota: statusLine)
        }
    }
}
