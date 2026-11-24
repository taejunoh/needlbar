import Foundation
import NeedlbarClaudeStatusLineSupport
import NeedlbarWidgetSupport
import Testing
@testable import NeedlbarCore

// The widget's stale reason, from the store's captured Claude failure reason to the
// projection row (spec 2026-11-20 §6). Everything is synthetic.
@Suite("WidgetPlanUsageUnavailableMapper")
struct WidgetPlanUsageUnavailableMapperTests {
    private let checkedAt = Date(timeIntervalSince1970: 1_800_000_000)
    private var now: Date { checkedAt.addingTimeInterval(3_600) }

    private func weekly() throws -> QuotaSnapshot {
        QuotaSnapshot(windows: [
            try QuotaWindow(id: "claude.weekly", title: "Weekly", usedPercent: 74, resetsAt: nil),
        ])
    }

    private func projection(_ store: ProviderSnapshotStore) async throws -> WidgetProjection {
        try WidgetProjectionMapper(now: now).map(await store.captureForWidget(exportedAt: now))
    }

    private func markPlanUsageUnavailable(_ store: ProviderSnapshotStore) async {
        await store.markQuotaFailure(
            for: .claude, status: .requiresAuthentication, claudeFailureReason: .planUsageUnavailable, at: now)
    }

    @Test func theCaptureCarriesOnlyTheClaudeReason() async throws {
        let store = ProviderSnapshotStore(now: { self.now })
        await store.applyQuota(try weekly(), for: .claude, at: checkedAt)
        await markPlanUsageUnavailable(store)
        await store.markQuotaFailure(for: .codex, status: .requiresAuthentication, at: now)
        let capture = await store.captureForWidget(exportedAt: now)
        #expect(capture.providers.map(\.claudeQuotaFailureReason) == [.planUsageUnavailable, nil, nil])
    }

    @Test func aPlanUsageFailureAfterASuccessMarksTheStaleClaudeRow() async throws {
        let store = ProviderSnapshotStore(now: { self.now })
        await store.applyQuota(try weekly(), for: .claude, at: checkedAt)
        await markPlanUsageUnavailable(store)
        let rows = try await projection(store).quotaRows
        #expect(rows[0].stream == .stale)
        #expect(rows[0].lastSuccessfulAt == checkedAt)
        #expect(rows[0].headline?.id == .claudeWeekly)
        #expect(rows[0].staleReason == .planUsageUnavailable)
        #expect(rows[1].staleReason == nil)
    }

    @Test func aSuccessClearsTheReasonAndADifferentFailureReplacesIt() async throws {
        let store = ProviderSnapshotStore(now: { self.now })
        await store.applyQuota(try weekly(), for: .claude, at: checkedAt)
        await markPlanUsageUnavailable(store)
        #expect(try await projection(store).quotaRows[0].staleReason == .planUsageUnavailable)

        await store.applyQuota(try weekly(), for: .claude, at: now)
        let cleared = try await projection(store).quotaRows[0]
        #expect(cleared.stream == .fresh)
        #expect(cleared.staleReason == nil)

        await markPlanUsageUnavailable(store)
        await store.markQuotaFailure(
            for: .claude, status: .error(message: "fixture", lastSuccessfulAt: nil),
            claudeFailureReason: .usageReportFormatChanged, at: now)
        let replaced = try await projection(store).quotaRows[0]
        #expect(replaced.stream == .stale)
        #expect(replaced.staleReason == nil)
    }

    @Test func otherReasonsNeverSetIt() async throws {
        for reason in [ClaudeQuotaFailureReason.quotaAccessUnavailable, .connectionUnavailable, .temporarilyLimited,
                       .couldNotUpdateQuota, .claudeCodeNotInstalled, .claudeCodeCheckFailed, .usageReportFormatChanged] {
            let store = ProviderSnapshotStore(now: { self.now })
            await store.applyQuota(try weekly(), for: .claude, at: checkedAt)
            await store.markQuotaFailure(
                for: .claude, status: .error(message: "fixture", lastSuccessfulAt: nil), claudeFailureReason: reason, at: now)
            #expect(try await projection(store).quotaRows[0].staleReason == nil, "\(reason)")
        }
    }

    @Test func theReasonIsLeftOutWithoutThrowingWhenTheRowCannotCarryIt() async throws {
        // No earlier success: no last successful time and no headline.
        let neverChecked = ProviderSnapshotStore(now: { self.now })
        await markPlanUsageUnavailable(neverChecked)
        let undated = try await projection(neverChecked).quotaRows[0]
        #expect(undated.lastSuccessfulAt == nil)
        #expect(undated.staleReason == nil)

        // A reading with Fable only has no headline.
        let fableOnly = ProviderSnapshotStore(now: { self.now })
        await fableOnly.applyQuota(QuotaSnapshot(windows: [
            try QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "Fable weekly", usedPercent: 3, resetsAt: nil),
        ]), for: .claude, at: checkedAt)
        await markPlanUsageUnavailable(fableOnly)
        let withoutHeadline = try await projection(fableOnly).quotaRows[0]
        #expect(withoutHeadline.headline == nil)
        #expect(withoutHeadline.staleReason == nil)
    }

    @Test func aFresherStatusLineReadingDoesNotClearIt() async throws {
        let store = ProviderSnapshotStore(now: { self.now })
        await store.applyQuota(try weekly(), for: .claude, at: checkedAt)
        await markPlanUsageUnavailable(store)
        await store.applyClaudeStatusLineQuota(StatusLineQuotaRecord(
            schemaVersion: StatusLineQuotaRecord.currentSchemaVersion, generation: UUID(),
            fiveHour: StatusLineWindowObservation(usedPercent: 10, resetsAt: nil, receivedAt: now),
            sevenDay: StatusLineWindowObservation(usedPercent: 20, resetsAt: nil, receivedAt: now)))
        let row = try await projection(store).quotaRows[0]
        #expect(row.headline?.remainingPercent == 26, "the widget shows only the stalled /usage value")
        #expect(row.staleReason == .planUsageUnavailable)
    }
}
