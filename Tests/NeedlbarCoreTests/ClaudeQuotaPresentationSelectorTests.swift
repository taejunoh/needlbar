import Foundation
import NeedlbarClaudeStatusLineSupport
import Testing
@testable import NeedlbarCore

@Suite("ClaudeQuotaPresentationSelectorTests")
struct ClaudeQuotaPresentationSelectorTests {
    private let observedAt = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(arguments: [899.0, 900.0, 901.0])
    func directObservationExpiresAtStrictFifteenMinuteBoundary(age: Double) throws {
        let success = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = ProviderSnapshot(
            provider: .claude, usage: nil,
            quota: .init(windows: [try QuotaWindow(
                id: "claude.session", title: "Session", usedPercent: 25,
                resetsAt: success.addingTimeInterval(3_600))]),
            usageStatus: .unavailable, quotaStatus: .fresh,
            updatedAt: success.addingTimeInterval(age), quotaLastSuccessfulAt: success)
        let selected = ClaudeQuotaPresentationSelector.select(
            snapshot: snapshot, now: success.addingTimeInterval(age))
        #expect(selected.fiveHour?.remainingPercent == 75)
        #expect(selected.fiveHour?.isLastKnown == (age >= 900))
    }

    @Test func missingSuccessNeverUsesUpdatedAtAsObservationTime() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = ProviderSnapshot(
            provider: .claude, usage: nil,
            quota: .init(windows: [try QuotaWindow(
                id: "claude.session", title: "Session", usedPercent: 25, resetsAt: nil)]),
            usageStatus: .unavailable, quotaStatus: .fresh, updatedAt: now)
        let selected = ClaudeQuotaPresentationSelector.select(snapshot: snapshot, now: now)
        #expect(selected.fiveHour?.isLastKnown == true)
        #expect(selected.fiveHour?.observedAt == nil)
    }

    @Test(arguments: [nil, Date(timeIntervalSince1970: 1_800_000_000), Date(timeIntervalSince1970: 1_800_000_001), Date(timeIntervalSince1970: 1_799_999_999), Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: .infinity)])
    func directObservationOnlyUsesFiniteNonFutureSuccessTime(successAt: Date?) throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = try directSnapshot(successAt: successAt, resetAt: now.addingTimeInterval(60), updatedAt: now)
        let selected = ClaudeQuotaPresentationSelector.select(snapshot: snapshot, now: now).fiveHour
        let usable = successAt.map { $0.timeIntervalSince1970.isFinite && $0 <= now } ?? false
        #expect(selected?.isLastKnown == !usable)
        #expect(selected?.observedAt == (usable ? successAt : nil))
    }

    @Test(arguments: [nil, Date(timeIntervalSince1970: 1_799_999_999), Date(timeIntervalSince1970: 1_800_000_000), Date(timeIntervalSince1970: 1_800_000_001)])
    func directResetMustBeLaterThanNowWhenPresent(resetAt: Date?) throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let selected = ClaudeQuotaPresentationSelector.select(
            snapshot: try directSnapshot(successAt: now, resetAt: resetAt, updatedAt: now), now: now
        ).fiveHour
        #expect(selected?.isLastKnown == (resetAt.map { $0 <= now } ?? false))
        #expect(selected?.resetsAt == resetAt)
    }

    @Test(arguments: [DataStatus.fresh, .stale(lastSuccessfulAt: Date(timeIntervalSince1970: 1_800_000_000)), .unavailable, .requiresAuthentication, .error(message: "fixture", lastSuccessfulAt: nil)])
    func onlyFreshDirectQuotaStatusCanBeCurrent(status: DataStatus) throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let selected = ClaudeQuotaPresentationSelector.select(
            snapshot: try directSnapshot(successAt: now, resetAt: now.addingTimeInterval(30), updatedAt: now, status: status), now: now
        ).fiveHour
        #expect(selected?.isLastKnown == (status != .fresh))
    }

    @Test func failedDirectStreamRetainsValueAndTimestampButPrefersRecentBridge() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let successAt = now.addingTimeInterval(-1_000)
        let record = StatusLineQuotaRecord(
            schemaVersion: StatusLineQuotaRecord.currentSchemaVersion,
            generation: UUID(),
            fiveHour: StatusLineWindowObservation(usedPercent: 40, resetsAt: now.addingTimeInterval(60), receivedAt: now),
            sevenDay: nil
        )
        let snapshot = ProviderSnapshot(
            provider: .claude, usage: nil,
            quota: QuotaSnapshot(windows: [try QuotaWindow(
                id: "claude.session", title: "Session", usedPercent: 25, resetsAt: now.addingTimeInterval(60))]),
            usageStatus: .error(message: "fixture", lastSuccessfulAt: successAt),
            quotaStatus: .error(message: "fixture", lastSuccessfulAt: successAt),
            updatedAt: now, quotaLastSuccessfulAt: successAt, claudeStatusLineQuota: record
        )
        let selected = ClaudeQuotaPresentationSelector.select(snapshot: snapshot, now: now).fiveHour
        #expect(selected?.remainingPercent == 60)
        #expect(selected?.source == .claudeCodeStatusLine)
        #expect(selected?.observedAt == now)
        #expect(selected?.isLastKnown == false)
    }

    @Test func datedLastKnownValuesRankAheadOfUndatedAndDirectWinsTies() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let direct = try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 25, resetsAt: now)
        let newerBridge = record(fiveHour: StatusLineWindowObservation(
            usedPercent: 40, resetsAt: now, receivedAt: now.addingTimeInterval(-20)), sevenDay: nil)
        let snapshot = ProviderSnapshot(
            provider: .claude, usage: nil, quota: QuotaSnapshot(windows: [direct]),
            usageStatus: .unavailable, quotaStatus: .fresh, updatedAt: now,
            quotaLastSuccessfulAt: nil, claudeStatusLineQuota: newerBridge
        )
        let newer = ClaudeQuotaPresentationSelector.select(snapshot: snapshot, now: now).fiveHour
        #expect(newer?.source == .claudeCodeStatusLine)
        #expect(newer?.isLastKnown == true)

        let tied = ProviderSnapshot(
            provider: .claude, usage: nil, quota: QuotaSnapshot(windows: [direct]),
            usageStatus: .unavailable, quotaStatus: .fresh, updatedAt: now,
            quotaLastSuccessfulAt: now,
            claudeStatusLineQuota: record(fiveHour: StatusLineWindowObservation(
                usedPercent: 40, resetsAt: now, receivedAt: now), sevenDay: nil)
        )
        #expect(ClaudeQuotaPresentationSelector.select(snapshot: tied, now: now).fiveHour?.source == .direct)
    }

    @Test(arguments: [899.0, 900.0, 901.0])
    func bridgeKeepsItsInclusiveFifteenMinuteRecencyBoundary(age: Double) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = ProviderSnapshot(
            provider: .claude, usage: nil, quota: nil,
            usageStatus: .unavailable, quotaStatus: .unavailable, updatedAt: now,
            claudeStatusLineQuota: record(fiveHour: StatusLineWindowObservation(
                usedPercent: 25, resetsAt: now.addingTimeInterval(30),
                receivedAt: now.addingTimeInterval(-age)), sevenDay: nil)
        )
        let selected = ClaudeQuotaPresentationSelector.select(snapshot: snapshot, now: now).fiveHour
        #expect(selected?.isLastKnown == (age > 900))
    }

    @Test(arguments: [Date(timeIntervalSince1970: 1_799_999_999), Date(timeIntervalSince1970: 1_800_000_000), Date(timeIntervalSince1970: 1_800_000_001)])
    func bridgeResetAtOrBeforeNowIsLastKnown(resetAt: Date) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = ProviderSnapshot(
            provider: .claude, usage: nil, quota: nil,
            usageStatus: .unavailable, quotaStatus: .unavailable, updatedAt: now,
            claudeStatusLineQuota: record(fiveHour: StatusLineWindowObservation(
                usedPercent: 25, resetsAt: resetAt, receivedAt: now), sevenDay: nil)
        )
        let selected = ClaudeQuotaPresentationSelector.select(snapshot: snapshot, now: now).fiveHour
        #expect(selected?.isLastKnown == (resetAt <= now))
    }

    @Test(arguments: [-1.0, 101.0, .nan, .infinity])
    func invalidBridgePercentageIsRejected(usedPercent: Double) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = ProviderSnapshot(
            provider: .claude, usage: nil, quota: nil,
            usageStatus: .unavailable, quotaStatus: .unavailable, updatedAt: now,
            claudeStatusLineQuota: record(fiveHour: StatusLineWindowObservation(
                usedPercent: usedPercent, resetsAt: now.addingTimeInterval(30), receivedAt: now), sevenDay: nil)
        )
        #expect(ClaudeQuotaPresentationSelector.select(snapshot: snapshot, now: now).fiveHour == nil)
    }

    @Test(arguments: [Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: .infinity)])
    func nonfiniteBridgeReceiptTimeRetainsValueWithoutUsableTime(receivedAt: Date) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = ProviderSnapshot(
            provider: .claude, usage: nil, quota: nil,
            usageStatus: .unavailable, quotaStatus: .unavailable, updatedAt: now,
            claudeStatusLineQuota: record(fiveHour: StatusLineWindowObservation(
                usedPercent: 25, resetsAt: now.addingTimeInterval(30), receivedAt: receivedAt), sevenDay: nil)
        )
        let selected = ClaudeQuotaPresentationSelector.select(snapshot: snapshot, now: now).fiveHour
        #expect(selected?.remainingPercent == 75)
        #expect(selected?.observedAt == nil)
        #expect(selected?.isLastKnown == true)
    }

    @Test func unusableBridgeTimeRemainsLastKnownWithoutDisplayedTimeAndDirectWinsWhenNeitherHasTime() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let direct = try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 25, resetsAt: now)
        let snapshot = ProviderSnapshot(
            provider: .claude, usage: nil, quota: QuotaSnapshot(windows: [direct]),
            usageStatus: .unavailable, quotaStatus: .fresh, updatedAt: now,
            quotaLastSuccessfulAt: nil,
            claudeStatusLineQuota: record(fiveHour: StatusLineWindowObservation(
                usedPercent: 40, resetsAt: now, receivedAt: now.addingTimeInterval(1)), sevenDay: nil)
        )
        let selected = ClaudeQuotaPresentationSelector.select(snapshot: snapshot, now: now).fiveHour
        #expect(selected?.source == .direct)
        #expect(selected?.observedAt == nil)
        #expect(selected?.isLastKnown == true)

        let bridgeOnly = ProviderSnapshot(
            provider: .claude, usage: nil, quota: nil,
            usageStatus: .unavailable, quotaStatus: .unavailable, updatedAt: now,
            claudeStatusLineQuota: record(fiveHour: StatusLineWindowObservation(
                usedPercent: 40, resetsAt: now, receivedAt: now.addingTimeInterval(1)), sevenDay: nil)
        )
        let retainedBridge = ClaudeQuotaPresentationSelector.select(snapshot: bridgeOnly, now: now).fiveHour
        #expect(retainedBridge?.source == .claudeCodeStatusLine)
        #expect(retainedBridge?.observedAt == nil)
        #expect(retainedBridge?.isLastKnown == true)

        let noValue = ProviderSnapshot(
            provider: .claude, usage: nil, quota: nil,
            usageStatus: .unavailable, quotaStatus: .unavailable, updatedAt: now
        )
        #expect(ClaudeQuotaPresentationSelector.select(snapshot: noValue, now: now).fiveHour == nil)
    }

    @Test func fableResetCanExpireWhileMainDirectWindowRemainsCurrent() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let success = now.addingTimeInterval(-30)
        let snapshot = ProviderSnapshot(
            provider: .claude, usage: nil,
            quota: QuotaSnapshot(windows: [
                try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 25, resetsAt: now.addingTimeInterval(60)),
                try QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "Fable", usedPercent: 25, resetsAt: now),
            ]),
            usageStatus: .unavailable, quotaStatus: .fresh, updatedAt: now, quotaLastSuccessfulAt: success
        )
        let selected = ClaudeQuotaPresentationSelector.select(snapshot: snapshot, now: now)
        #expect(selected.fiveHour?.isLastKnown == false)
        #expect(selected.fable?.isLastKnown == true)
    }

    private func directSnapshot(successAt: Date?, resetAt: Date?, updatedAt: Date, status: DataStatus = .fresh) throws -> ProviderSnapshot {
        ProviderSnapshot(
            provider: .claude, usage: nil,
            quota: QuotaSnapshot(windows: [try QuotaWindow(
                id: "claude.session", title: "Session", usedPercent: 25, resetsAt: resetAt)]),
            usageStatus: .unavailable, quotaStatus: status, updatedAt: updatedAt,
            quotaLastSuccessfulAt: successAt
        )
    }

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
