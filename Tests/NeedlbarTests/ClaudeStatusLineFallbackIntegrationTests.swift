import Foundation
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore
import NeedlbarClaudeStatusLineSupport

@Suite("Claude status-line fallback integration", .serialized)
struct ClaudeStatusLineFallbackIntegrationTests {
    @Test func newlyPublishedQuotaReplacesFailedDirectMainWindowsButKeepsFableAndFailure() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let lastDirectAt = now.addingTimeInterval(-3_600)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Needlbar-fallback-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let privateStore = try StatusLinePrivateStore(rootURL: root.appendingPathComponent("private"))
        let generation = UUID()
        try privateStore.prepare(metadata: .init(generation: generation, originalStatusLineJSON: nil,
                                                  originalCommand: nil, ownedStatusLineJSON: Data("{}".utf8)))
        try privateStore.activate(generation: generation)
        #expect(try privateStore.read(expectedGeneration: generation) == nil)

        let store = ProviderSnapshotStore(now: { now })
        let lastDirect = QuotaSnapshot(windows: [
            try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 32,
                            resetsAt: now.addingTimeInterval(1_800)),
            try QuotaWindow(id: "claude.weekly", title: "Weekly", usedPercent: 32,
                            resetsAt: now.addingTimeInterval(86_400)),
            try QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "Fable weekly", usedPercent: 2,
                            resetsAt: now.addingTimeInterval(86_400)),
        ])
        await store.applyQuota(lastDirect, for: .claude, at: lastDirectAt)
        let coordinator = RefreshCoordinator(
            usageRepository: EmptyUsageRepository(),
            quotaRepository: ExpiredClaudeQuotaRepository(),
            store: store,
            clock: FixedFallbackClock(now: now),
            statusLineRepository: ClaudeStatusLineCacheRepository(store: privateStore)
        )
        await coordinator.start()
        try await waitUntil {
            await store.snapshot(for: .claude).claudeQuotaFailureReason == .quotaAccessUnavailable
        }

        let before = await store.snapshot(for: .claude)
        #expect(before.claudeStatusLineQuota == nil)
        #expect(before.quotaLastSuccessfulAt == lastDirectAt)

        let input = Data(#"{"rate_limits":{"five_hour":{"used_percentage":6,"resets_at":1800003600},"seven_day":{"used_percentage":34,"resets_at":1800604800}}}"#.utf8)
        let record = try #require(StatusLineQuotaParser.parse(input, generation: generation, receivedAt: now))
        #expect(try privateStore.publish(record))
        await coordinator.popoverOpened()
        try await waitUntil {
            let snapshot = await store.snapshot(for: .claude)
            return snapshot.claudeStatusLineQuota?.fiveHour?.usedPercent == 6
                && snapshot.claudeStatusLineQuota?.sevenDay?.usedPercent == 34
        }

        let snapshot = await store.snapshot(for: .claude)
        let settingsAndProviderPopover = ProviderPopoverPresentation(snapshot: snapshot, now: now.addingTimeInterval(60))
        let combined = CombinedUsageSnapshot(system: nil, providers: await store.snapshots(),
                                             capturedAt: now, systemAvailability: [:])
        let dashboard = SystemDashboardPresentation(snapshot: combined, configuration: .init(),
                                                    now: now.addingTimeInterval(60))
        let claudeRow = try #require(dashboard.ai.first { $0.provider == .claude })

        #expect(settingsAndProviderPopover.claudeFiveHour?.remaining == "94%")
        #expect(settingsAndProviderPopover.claudeSevenDay?.remaining == "66%")
        #expect(settingsAndProviderPopover.headlineQuotaRemaining == "66%")
        #expect(settingsAndProviderPopover.quotaSourceText == "Reported by Claude Code")
        #expect(settingsAndProviderPopover.quotaFailureReasonText == nil)
        #expect(claudeRow.value == "66%")
        #expect(claudeRow.quotaSourceText == "Reported by Claude Code")
        #expect(claudeRow.fable?.remaining == "98%")
        #expect(claudeRow.fable?.isLastKnown == true)
        #expect(claudeRow.fable?.lastCheckedText == DateFormatter.localizedString(
            from: lastDirectAt, dateStyle: .medium, timeStyle: .short))
        if case .error(_, let lastSuccessfulAt) = snapshot.quotaStatus {
            #expect(lastSuccessfulAt == lastDirectAt)
        } else {
            Issue.record("The direct quota failure should retain the earlier reading")
        }
        #expect(snapshot.claudeQuotaFailureReason == .quotaAccessUnavailable)
        #expect(snapshot.quotaLastSuccessfulAt == lastDirectAt)
        #expect(snapshot.quota == lastDirect)
        await coordinator.stop()
    }

    private func waitUntil(_ condition: @escaping () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for the coordinator to apply the expected state")
    }
}

private struct EmptyUsageRepository: UsageRepository {
    func refresh() throws -> UsageRefreshResult { .init(snapshots: [:], errors: [:]) }
}

private struct ExpiredClaudeQuotaRepository: QuotaRepository {
    func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult {
        .init(snapshots: [:], errors: [
            .claude: .init(provider: "claude", code: "authenticationExpired", message: "fixture", action: nil)
        ])
    }
}

private struct FixedFallbackClock: ClockLike {
    let now: Date

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
