import Foundation
import Testing
@testable import NeedlbarCore

@Suite("ClaudeUsageFreshness")
struct ClaudeUsageFreshnessTests {
    private let success = Date(timeIntervalSince1970: 1_800_000_000)

    private func report(status: DataStatus = .fresh) throws -> ProviderSnapshot {
        ProviderSnapshot(
            provider: .claude, usage: nil,
            quota: QuotaSnapshot(windows: [try QuotaWindow(
                id: "claude.weekly", title: "Weekly", usedPercent: 74, resetsAt: success.addingTimeInterval(86_400))]),
            usageStatus: .fresh, quotaStatus: status, updatedAt: success, quotaLastSuccessfulAt: success)
    }

    @Test(arguments: [1_199.0, 1_200.0, 1_201.0])
    func aReportStaysCurrentForTwentyMinutes(age: Double) throws {
        let selected = ClaudeQuotaPresentationSelector.select(
            snapshot: try report(), now: success.addingTimeInterval(age)).sevenDay
        #expect(selected?.isLastKnown == (age >= 1_200))
        #expect(selected?.observedAt == success)
    }

    @Test func theWindowOutlastsTheSlowestPeriodicRefresh() {
        let tick = TimeInterval(RefreshCoordinator.claudeUsageTickInterval.components.seconds)
        // The process deadline plus its termination grace, from `claude_usage_probe.rs`.
        let slowestRun: TimeInterval = 30 + 1
        #expect(ClaudeQuotaPresentationSelector.recentDirectInterval
            > ClaudeUsageProbeSchedule.periodicInterval + tick + slowestRun)
    }

    @Test(arguments: [900.0, 1_199.0, 1_200.0, 7_200.0])
    func aFailedRunIsLastKnownAtOnceAndKeepsItsCheckedTime(age: Double) throws {
        let failed = try report(status: .error(message: "fixture", lastSuccessfulAt: success))
        let selected = ClaudeQuotaPresentationSelector.select(
            snapshot: failed, now: success.addingTimeInterval(age)).sevenDay
        #expect(selected?.isLastKnown == true)
        #expect(selected?.observedAt == success)
        #expect(selected?.remainingPercent == 26)
    }

    @Test func theStatusLineWindowsDoNotChange() {
        #expect(ClaudeQuotaPresentationSelector.recentStatusLineInterval == 15 * 60)
        #expect(ClaudeQuotaPresentationSelector.maximumStatusLineAge == 24 * 60 * 60)
    }
}
