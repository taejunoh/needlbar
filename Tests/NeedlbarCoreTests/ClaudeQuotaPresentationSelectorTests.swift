import Foundation
import NeedlbarClaudeStatusLineSupport
import Testing
@testable import NeedlbarCore

@Suite("ClaudeQuotaPresentationSelectorTests")
struct ClaudeQuotaPresentationSelectorTests {
    private let observedAt = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func recentStatusLineFiveHourSurvivesDirectFailureWithoutFresheningFable() async throws {
        let oldDate = observedAt.addingTimeInterval(-3_600)
        let store = ProviderSnapshotStore(now: { observedAt })
        let fable = try QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "Fable weekly", usedPercent: 62, resetsAt: observedAt.addingTimeInterval(3_600))
        await store.applyQuota(QuotaSnapshot(windows: [fable]), for: .claude, at: oldDate)
        await store.markQuotaFailure(for: .claude, status: .requiresAuthentication, claudeFailureReason: .quotaAccessUnavailable, at: observedAt)
        await store.applyClaudeStatusLineQuota(record(fiveHour: window(used: 25), sevenDay: nil))

        let snapshot = await store.snapshot(for: .claude)
        let selection = ClaudeQuotaPresentationSelector.select(snapshot: snapshot, now: observedAt)
        #expect(selection.fiveHour?.remainingPercent == 75)
        #expect(selection.fiveHour?.source == .claudeCodeStatusLine)
        #expect(selection.fiveHour?.observedAt == observedAt)
        #expect(selection.fiveHour?.isLastKnown == false)
        #expect(selection.sevenDay == nil)
        #expect(selection.fable?.remainingPercent == 38)
        #expect(selection.fable?.source == .direct)
        #expect(selection.fable?.observedAt == oldDate)
        #expect(selection.fable?.isLastKnown == true)
        #expect(snapshot.claudeQuotaFailureReason == .quotaAccessUnavailable)
        #expect(snapshot.quotaLastSuccessfulAt == oldDate)
    }

    @Test func repeatedObservationDoesNotExtendFifteenMinuteRecency() async {
        let store = ProviderSnapshotStore(now: { observedAt })
        let sample = record(fiveHour: window(used: 25), sevenDay: nil)
        await store.applyClaudeStatusLineQuota(sample)
        await store.applyClaudeStatusLineQuota(sample)
        let snapshot = await store.snapshot(for: .claude)
        let selection = ClaudeQuotaPresentationSelector.select(snapshot: snapshot, now: observedAt.addingTimeInterval(1_201))
        #expect(selection.fiveHour?.remainingPercent == 75)
        #expect(selection.fiveHour?.isLastKnown == true)
        #expect(selection.fiveHour?.observedAt == observedAt)
    }

    @Test func passedStatusLineResetIsLastKnownEvenInsideRecencyLimit() async {
        let store = ProviderSnapshotStore(now: { observedAt })
        await store.applyClaudeStatusLineQuota(record(fiveHour: window(used: 100, reset: observedAt.addingTimeInterval(30)), sevenDay: nil))
        let selected = ClaudeQuotaPresentationSelector.select(snapshot: await store.snapshot(for: .claude), now: observedAt.addingTimeInterval(31))
        #expect(selected.fiveHour?.remainingPercent == 0)
        #expect(selected.fiveHour?.isLastKnown == true)
    }

    @Test func freshDirectQuotaTakesPrecedenceOverStatusLine() async throws {
        let store = ProviderSnapshotStore(now: { observedAt })
        await store.applyClaudeStatusLineQuota(record(fiveHour: window(used: 25), sevenDay: window(used: 50)))
        let direct = QuotaSnapshot(windows: [
            try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 10, resetsAt: observedAt.addingTimeInterval(3_600)),
            try QuotaWindow(id: "claude.weekly", title: "Weekly", usedPercent: 20, resetsAt: observedAt.addingTimeInterval(86_400)),
        ])
        await store.applyQuota(direct, for: .claude, at: observedAt.addingTimeInterval(60))
        let selected = ClaudeQuotaPresentationSelector.select(snapshot: await store.snapshot(for: .claude), now: observedAt.addingTimeInterval(60))
        #expect(selected.fiveHour?.remainingPercent == 90)
        #expect(selected.sevenDay?.remainingPercent == 80)
        #expect(selected.fiveHour?.source == .direct)
        #expect(selected.sevenDay?.source == .direct)
        #expect(selected.fiveHour?.isLastKnown == false)
    }

    @Test func statusLineStateCannotPopulateNonClaudeProvider() async {
        let store = ProviderSnapshotStore(now: { observedAt })
        await store.applyClaudeStatusLineQuota(record(fiveHour: window(used: 25), sevenDay: nil))
        let codex = await store.snapshot(for: .codex)
        #expect(codex.claudeStatusLineQuota == nil)
        #expect(codex.quota == nil)
    }

    private func window(used: Double, reset: Date? = nil) -> StatusLineWindowObservation {
        StatusLineWindowObservation(usedPercent: used, resetsAt: reset, receivedAt: observedAt)
    }

    private func record(fiveHour: StatusLineWindowObservation?, sevenDay: StatusLineWindowObservation?) -> StatusLineQuotaRecord {
        StatusLineQuotaRecord(schemaVersion: StatusLineQuotaRecord.currentSchemaVersion, generation: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!, fiveHour: fiveHour, sevenDay: sevenDay)
    }
}
