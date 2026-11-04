import Foundation
import NeedlbarClaudeStatusLineSupport
import NeedlbarWidgetSupport
import Testing
@testable import NeedlbarCore

@Suite("ClaudeUsageReportReasons")
struct ClaudeUsageReportReasonTests {
    @Test(arguments: [
        ("notInstalled", ClaudeQuotaFailureReason.claudeCodeNotInstalled),
        ("requiresAuthentication", .claudeCodeSignInRequired),
        ("providerUnavailable", .claudeCodeCheckFailed),
        ("rateLimited", .temporarilyLimited),
        ("schemaChanged", .usageReportFormatChanged),
        ("internalError", .couldNotUpdateQuota),
        ("", .couldNotUpdateQuota),
    ])
    func eachBridgeCodeMapsToItsStateFromTheSpec(code: String, expected: ClaudeQuotaFailureReason) {
        #expect(ClaudeQuotaFailureReason(errorCode: code, associatedOrigin: nil) == expected)
    }

    @Test func theGuidanceIsInTheShortTextBecauseTheDashboardShowsNoDetailLine() {
        #expect(ClaudeQuotaFailureReason.claudeCodeNotInstalled.displayText == "Install Claude Code to see quota")
        #expect(ClaudeQuotaFailureReason.claudeCodeSignInRequired.displayText == "Sign in with claude in Terminal")
        #expect(ClaudeQuotaFailureReason.claudeCodeCheckFailed.displayText == "Could not check Claude Code")
        #expect(ClaudeQuotaFailureReason.usageReportFormatChanged.displayText == "Could not read Claude Code's usage report")
        #expect(ClaudeQuotaFailureReason.claudeCodeNotInstalled.detailText != nil)
        #expect(ClaudeQuotaFailureReason.claudeCodeSignInRequired.detailText != nil)
        #expect(ClaudeQuotaFailureReason.claudeCodeCheckFailed.detailText == nil)
        #expect(ClaudeQuotaFailureReason.usageReportFormatChanged.detailText == nil)
    }

    @Test func theNewCopyComesFromLocalizableKeys() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("needlbar-usage-report-\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let table = """
        "claudeQuota.reason.claudeCodeNotInstalled" = "A";
        "claudeQuota.reason.claudeCodeNotInstalled.detail" = "B";
        "claudeQuota.reason.claudeCodeSignInRequired" = "C";
        "claudeQuota.reason.claudeCodeSignInRequired.detail" = "D";
        "claudeQuota.reason.claudeCodeCheckFailed" = "E";
        "claudeQuota.reason.usageReportFormatChanged" = "F";
        """
        try Data(table.utf8).write(to: directory.appendingPathComponent("Localizable.strings"))
        let bundle = try #require(Bundle(url: directory))
        #expect(ClaudeQuotaFailureReason.claudeCodeNotInstalled.localizedDisplayText(bundle: bundle) == "A")
        #expect(ClaudeQuotaFailureReason.claudeCodeNotInstalled.localizedDetailText(bundle: bundle) == "B")
        #expect(ClaudeQuotaFailureReason.claudeCodeSignInRequired.localizedDisplayText(bundle: bundle) == "C")
        #expect(ClaudeQuotaFailureReason.claudeCodeSignInRequired.localizedDetailText(bundle: bundle) == "D")
        #expect(ClaudeQuotaFailureReason.claudeCodeCheckFailed.localizedDisplayText(bundle: bundle) == "E")
        #expect(ClaudeQuotaFailureReason.usageReportFormatChanged.localizedDisplayText(bundle: bundle) == "F")
    }

    // MARK: - Source order

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(reportAge: TimeInterval, statusLineAge: TimeInterval, failed: Bool = false) throws -> ProviderSnapshot {
        let reportAt = now.addingTimeInterval(-reportAge)
        return ProviderSnapshot(
            provider: .claude, usage: nil,
            quota: QuotaSnapshot(windows: [try QuotaWindow(id: "claude.weekly", title: "Weekly", usedPercent: 10, resetsAt: nil)]),
            usageStatus: .fresh,
            quotaStatus: failed ? .error(message: "fixture", lastSuccessfulAt: reportAt) : .fresh,
            updatedAt: now, quotaLastSuccessfulAt: reportAt,
            claudeStatusLineQuota: StatusLineQuotaRecord(
                schemaVersion: StatusLineQuotaRecord.currentSchemaVersion, generation: UUID(), fiveHour: nil,
                sevenDay: StatusLineWindowObservation(usedPercent: 40, resetsAt: nil, receivedAt: now.addingTimeInterval(-statusLineAge)))
        )
    }

    @Test func aNewerStatusLineReadingWinsOverARecentReport() throws {
        let selected = ClaudeQuotaPresentationSelector.select(
            snapshot: try snapshot(reportAge: 300, statusLineAge: 30), now: now).sevenDay
        #expect(selected?.source == .claudeCodeStatusLine)
        #expect(selected?.remainingPercent == 60)
    }

    @Test func aNewerReportWinsOverARecentStatusLineEvenAfterALaterFailure() throws {
        let selected = ClaudeQuotaPresentationSelector.select(
            snapshot: try snapshot(reportAge: 30, statusLineAge: 300, failed: true), now: now).sevenDay
        #expect(selected?.source == .direct)
        #expect(selected?.isLastKnown == true)
    }

    @Test func aTieGoesToTheReport() throws {
        let selected = ClaudeQuotaPresentationSelector.select(
            snapshot: try snapshot(reportAge: 60, statusLineAge: 60), now: now).sevenDay
        #expect(selected?.source == .direct)
    }

    // MARK: - Consumers with a window missing

    private func weeklyAndFable() throws -> QuotaSnapshot {
        QuotaSnapshot(windows: [
            try QuotaWindow(id: "claude.weekly", title: "Weekly", usedPercent: 74, resetsAt: now.addingTimeInterval(86_400)),
            try QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "Fable weekly", usedPercent: 0, resetsAt: nil),
        ])
    }

    @Test func theHeadlineUsesTheWeeklyWindowWhenThereIsNoSession() async throws {
        let store = ProviderSnapshotStore(now: { self.now })
        await store.applyQuota(try weeklyAndFable(), for: .claude, at: now)
        let headline = HeadlineQuotaSelector.mostConstrained([await store.snapshot(for: .claude)], now: now)
        #expect(headline?.id == "claude.weekly")
        #expect(headline?.remainingPercent == 26)
    }

    @Test func fableAloneNeverBecomesTheHeadline() async throws {
        let store = ProviderSnapshotStore(now: { self.now })
        await store.applyQuota(QuotaSnapshot(windows: [
            try QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "Fable weekly", usedPercent: 3, resetsAt: nil),
        ]), for: .claude, at: now)
        #expect(HeadlineQuotaSelector.mostConstrained([await store.snapshot(for: .claude)], now: now) == nil)
    }

    @Test func theWidgetAcceptsWeeklyOnlyAndFableOnly() async throws {
        let store = ProviderSnapshotStore(now: { self.now })
        await store.applyQuota(try weeklyAndFable(), for: .claude, at: now)
        var projection = try WidgetProjectionMapper(now: now).map(await store.captureForWidget(exportedAt: now))
        #expect(projection.quotaRows[0].headline?.id == .claudeWeekly)

        await store.applyQuota(QuotaSnapshot(windows: [
            try QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "Fable weekly", usedPercent: 3, resetsAt: nil),
        ]), for: .claude, at: now)
        projection = try WidgetProjectionMapper(now: now).map(await store.captureForWidget(exportedAt: now))
        #expect(projection.quotaRows[0].headline == nil)
    }

    @Test func theExportAcceptsWeeklyOnlyAndDropsFable() async throws {
        let store = ProviderSnapshotStore(now: { self.now })
        await store.applyQuota(try weeklyAndFable(), for: .claude, at: now)
        let data = try SnapshotExporter().encode(await store.captureForExport(exportedAt: now))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("claude.weekly"))
        #expect(!text.contains("claude.session"))
        #expect(!text.contains("claude.fable.weekly"))
    }

    @Test func alertKeysAreUnchangedAndAMissingWindowIsSimplyAbsent() throws {
        #expect(QuotaAlertKey.isAllowed(provider: .claude, windowID: "claude.session"))
        #expect(QuotaAlertKey.isAllowed(provider: .claude, windowID: "claude.weekly"))
        #expect(!QuotaAlertKey.isAllowed(provider: .claude, windowID: QuotaWindow.claudeFableWeeklyID))
    }
}
