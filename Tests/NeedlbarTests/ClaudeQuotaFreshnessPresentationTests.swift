import Foundation
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore
import NeedlbarClaudeStatusLineSupport

private final class TwoFrameQuotaClock: ClockLike, @unchecked Sendable {
    private let lock = NSLock()
    private let initial: Date
    private let betweenFrames: (@Sendable () async -> Void)?
    private var frame = 0
    init(initial: Date, betweenFrames: (@Sendable () async -> Void)? = nil) {
        self.initial = initial
        self.betweenFrames = betweenFrames
    }
    var now: Date { lock.withLock { initial.addingTimeInterval(Double(frame)) } }
    func sleep(for duration: Duration) async throws {
        let next = lock.withLock { frame += 1; return frame }
        if next > 1 { throw CancellationError() }
        await betweenFrames?()
    }
}

@Suite struct ClaudeQuotaFreshnessPresentationTests {
    @Test @MainActor func openSurfacesAgeWithoutAnotherRepositoryCall() async throws {
        let success = Date(timeIntervalSince1970: 1_800_000_000)
        let window = try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 25, resetsAt: nil)
        let snapshot = ProviderSnapshot(provider: .claude, usage: nil,
            quota: .init(windows: [window]), usageStatus: .unavailable,
            quotaStatus: .fresh, updatedAt: success, quotaLastSuccessfulAt: success)
        let combined = CombinedUsageSnapshot(system: nil, providers: [snapshot],
                                             capturedAt: success, systemAvailability: [:])
        let settings = SettingsClaudeQuotaPresentation(snapshot: combined, now: success)
        var frames: [[Bool]] = []
        await QuotaPresentationTicker.run(
            clock: TwoFrameQuotaClock(initial: success.addingTimeInterval(899))) { now in
            settings.update(snapshot: combined, now: now)
            let popover = ProviderPopoverPresentation(snapshot: snapshot, now: now)
            let dashboard = SystemDashboardPresentation(snapshot: combined, configuration: .init(), now: now)
            frames.append([settings.value.quotaIsLastKnown, popover.quotaIsLastKnown,
                           dashboard.ai.first { $0.provider == .claude }?.quotaIsLastKnown ?? false])
        }
        #expect(frames == [[false, false, false], [true, true, true]])
    }

    @Test @MainActor func legacyClaudeWindowWithMissingSuccessTimeStaysLastKnownAcrossSurfaces() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = ProviderSnapshot(
            provider: .claude,
            usage: nil,
            quota: QuotaSnapshot(windows: [try QuotaWindow(
                id: "claude.legacy", title: "Legacy window", usedPercent: 25, resetsAt: nil
            )]),
            usageStatus: .unavailable,
            quotaStatus: .fresh,
            updatedAt: now
        )
        let combined = CombinedUsageSnapshot(
            system: nil,
            providers: [snapshot],
            capturedAt: now,
            systemAvailability: [:]
        )

        let popover = ProviderPopoverPresentation(snapshot: snapshot, now: now)
        let dashboard = SystemDashboardPresentation(
            snapshot: combined,
            configuration: SystemMonitorConfiguration(),
            now: now
        )
        let settings = SettingsClaudeQuotaPresentation(snapshot: combined, now: now).value
        let detail = try #require(popover.claudeOtherWindows.first)
        let dashboardClaude = try #require(dashboard.ai.first { $0.provider == .claude })

        #expect(detail.id == "claude.legacy")
        #expect(detail.remaining == "75%")
        #expect(detail.isLastKnown)
        #expect(detail.observedAt == nil)
        #expect(detail.resetCaption == nil)
        #expect(popover.quotaIsLastKnown)
        #expect(popover.lastKnownQuotaRemaining == "75%")
        #expect(popover.quotaLastCheckedText == nil)
        #expect(!popover.requiresProviderSignIn)

        #expect(settings.claudeOtherWindows == popover.claudeOtherWindows)
        #expect(settings.quotaIsLastKnown)
        #expect(settings.lastKnownQuotaRemaining == "75%")
        #expect(settings.quotaLastCheckedText == nil)

        #expect(dashboardClaude.quotaIsLastKnown)
        #expect(dashboardClaude.quotaLastKnownRemaining == "75%")
        #expect(dashboardClaude.quotaLastCheckedText == nil)
    }

    @Test @MainActor func resetlessCurrentClaudeQuotaShowsUnavailableResetCopy() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = ProviderSnapshot(
            provider: .claude,
            usage: nil,
            quota: QuotaSnapshot(windows: [try QuotaWindow(
                id: "claude.session", title: "Session", usedPercent: 25, resetsAt: nil
            )]),
            usageStatus: .unavailable,
            quotaStatus: .fresh,
            updatedAt: now,
            quotaLastSuccessfulAt: now
        )
        let presentation = ProviderPopoverPresentation(snapshot: snapshot, now: now)

        #expect(presentation.claudeFiveHour?.remaining == "75%")
        #expect(presentation.claudeFiveHour?.isLastKnown == false)
        #expect(presentation.claudeFiveHour?.resetCaption == "Reset unavailable")
        #expect(presentation.quotaFreshness == .fresh)
        #expect(!presentation.requiresProviderSignIn)
    }

    @Test @MainActor func cachedReprojectionCrossesAgeAndResetBoundariesWithoutAddingHistory() async throws {
        let success = Date(timeIntervalSince1970: 1_800_000_000)
        let generation = UUID()
        let bridge = StatusLineQuotaRecord(schemaVersion: 1, generation: generation,
            fiveHour: .init(usedPercent: 50, resetsAt: nil, receivedAt: success), sevenDay: nil)
        let cases: [(String, [QuotaWindow], Date?, StatusLineQuotaRecord?, TimeInterval, [[Bool]])] = [
            ("direct age", [try window()], success, nil, 899, [[false, false], [true, false]]),
            ("direct reset", [try window(reset: success.addingTimeInterval(100))], success, nil, 99,
             [[false, false], [true, false]]),
            // Bridge receipt semantics retain the existing inclusive 15-minute boundary.
            ("bridge age", [], nil, bridge, 900, [[false, false], [true, false]]),
            ("Fable reset", [try window(), try window(id: QuotaWindow.claudeFableWeeklyID,
                reset: success.addingTimeInterval(100))], success, nil, 99, [[false, false], [false, true]]),
            ("Fable-only reset", [try window(id: QuotaWindow.claudeFableWeeklyID,
                reset: success.addingTimeInterval(100))], success, nil, 99, [[false, false], [false, true]]),
            ("missing observation", [try window()], nil, nil, 0, [[true, false], [true, false]]),
            ("future observation", [try window()], success.addingTimeInterval(100), nil, 0,
             [[true, false], [true, false]])
        ]
        for (name, windows, observed, record, start, expected) in cases {
            let provider = ProviderSnapshot(provider: .claude, usage: nil,
                quota: windows.isEmpty ? nil : .init(windows: windows), usageStatus: .unavailable,
                quotaStatus: windows.isEmpty ? .unavailable : .fresh, updatedAt: success,
                quotaLastSuccessfulAt: observed, claudeStatusLineQuota: record)
            let combined = combined(provider, at: success, includeSystem: true)
            let settings = SettingsClaudeQuotaPresentation(snapshot: combined, now: success)
            let dashboard = SystemDashboardModel(snapshot: combined, configuration: .init())
            let history = dashboard.history
            let expectedRemaining: String? = windows.contains { $0.id == "claude.session" } ? "75%" : record == nil ? nil : "50%"
            #expect(history.network.count == 1)
            var frames: [[Bool]] = []
            await QuotaPresentationTicker.run(clock: TwoFrameQuotaClock(initial: success.addingTimeInterval(start))) { now in
                settings.reproject(at: now)
                dashboard.reproject(at: now)
                let popover = ProviderPopoverPresentation(snapshot: provider, now: now)
                let overview = OverviewPopoverPresentation(snapshots: [provider], dailyUsage: [], now: now)
                let dashboardClaude = dashboard.presentation.ai.first { $0.provider == .claude }
                let state = [popover.quotaIsLastKnown, popover.fableIsLastKnown]
                frames.append(state)
                #expect([settings.value.quotaIsLastKnown, settings.value.fableIsLastKnown] == state, "\(name)")
                #expect([dashboardClaude?.quotaIsLastKnown ?? false,
                         dashboardClaude?.fable?.isLastKnown ?? false] == state, "\(name)")
                #expect(overview.providerRows.first { $0.provider == .claude }?.quotaIsLastKnown == state[0], "\(name)")
                #expect(overview.headlineQuotaRemaining == expectedRemaining, "\(name)")
                #expect(dashboard.history == history)
                #expect(settings.value.claudeFiveHour?.remaining == popover.claudeFiveHour?.remaining)
                if observed == nil && record == nil || (observed ?? success) > now {
                    #expect(settings.value.quotaLastCheckedText == nil)
                    #expect(dashboardClaude?.quotaLastCheckedText == nil)
                }
            }
            #expect(frames == expected, "\(name)")
        }
    }

    @Test @MainActor func reprojectionUsesLatestUpdatedSnapshotAndConfiguration() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let initial = combined(ProviderSnapshot(provider: .claude, usage: nil, quota: nil,
            usageStatus: .unavailable, quotaStatus: .unavailable, updatedAt: now), at: now)
        let provider = ProviderSnapshot(provider: .claude, usage: nil, quota: .init(windows: [try window()]),
            usageStatus: .unavailable, quotaStatus: .fresh, updatedAt: now, quotaLastSuccessfulAt: now)
        let latest = combined(provider, at: now)
        let settings = SettingsClaudeQuotaPresentation(snapshot: initial, now: now)
        let dashboard = SystemDashboardModel(snapshot: initial, configuration: .init())
        var configuration = SystemMonitorConfiguration()
        configuration.dashboardVisibleModules = [.ai]
        configuration.ai[.codex]?.dashboardVisible = false
        settings.update(snapshot: latest, now: now)
        dashboard.update(snapshot: latest, configuration: configuration)
        settings.reproject(at: now.addingTimeInterval(900))
        dashboard.reproject(at: now.addingTimeInterval(900))
        #expect(settings.value.quotaIsLastKnown)
        #expect(settings.value.lastKnownQuotaRemaining == "75%")
        #expect(dashboard.presentation.ai.first { $0.provider == .claude }?.quotaLastKnownRemaining == "75%")
        #expect(dashboard.presentation.moduleIDs == [.ai])
        #expect(!dashboard.presentation.ai.contains { $0.provider == .codex })
    }

    @Test @MainActor func tickerCancellationStopsUpdates() async {
        let clock = CancellationQuotaClock()
        var updates = 0
        let task = Task { await QuotaPresentationTicker.run(clock: clock) { _ in updates += 1 } }
        for _ in 0..<10_000 {
            if clock.isSleeping { break }
            await Task.yield()
        }
        #expect(clock.isSleeping)
        task.cancel()
        await task.value
        let countAtCancellation = updates
        for _ in 0..<10 { await Task.yield() }
        #expect(countAtCancellation == 1)
        #expect(updates == countAtCancellation)
    }

    @Test @MainActor func ageBoundarySwitchesEverySurfaceFromDirectToCurrentBridge() async throws {
        let success = Date(timeIntervalSince1970: 1_800_000_000)
        let bridge = StatusLineQuotaRecord(schemaVersion: 1, generation: UUID(),
            fiveHour: .init(usedPercent: 50, resetsAt: nil, receivedAt: success.addingTimeInterval(1)), sevenDay: nil)
        let provider = ProviderSnapshot(provider: .claude, usage: nil, quota: .init(windows: [try window()]),
            usageStatus: .unavailable, quotaStatus: .fresh, updatedAt: success,
            quotaLastSuccessfulAt: success, claudeStatusLineQuota: bridge)
        let snapshot = combined(provider, at: success)
        let settings = SettingsClaudeQuotaPresentation(snapshot: snapshot, now: success)
        let dashboard = SystemDashboardModel(snapshot: snapshot, configuration: .init())
        var values: [String?] = []
        var sources: [String?] = []
        await QuotaPresentationTicker.run(clock: TwoFrameQuotaClock(initial: success.addingTimeInterval(899))) { now in
            settings.reproject(at: now)
            dashboard.reproject(at: now)
            let popover = ProviderPopoverPresentation(snapshot: provider, now: now)
            let overview = OverviewPopoverPresentation(snapshots: [provider], dailyUsage: [], now: now)
            values.append(settings.value.headlineQuotaRemaining)
            sources.append(settings.value.quotaSourceText)
            #expect(popover.headlineQuotaRemaining == settings.value.headlineQuotaRemaining)
            #expect(overview.headlineQuotaRemaining == settings.value.headlineQuotaRemaining)
            #expect(dashboard.presentation.ai.first { $0.provider == .claude }?.value == settings.value.headlineQuotaRemaining)
            #expect(popover.quotaSourceText == settings.value.quotaSourceText)
            #expect(dashboard.presentation.ai.first { $0.provider == .claude }?.quotaSourceText == settings.value.quotaSourceText)
        }
        #expect(values == ["75%", "50%"])
        #expect(sources == ["Claude usage", "Reported by Claude Code"])
    }

    @Test @MainActor func coordinatorCallsStayFrozenWhileCachedSurfacesAge() async throws {
        let success = Date(timeIntervalSince1970: 1_800_000_000)
        let repository = CachedQuotaRepositorySpy(quota: .init(windows: [try window()]))
        let store = ProviderSnapshotStore(now: { success })
        let coordinator = RefreshCoordinator(usageRepository: CachedEmptyUsageRepository(),
            quotaRepository: repository, store: store, clock: FrozenQuotaClock(now: success))
        await coordinator.start()
        for _ in 0..<10_000 {
            if await store.snapshot(for: .claude).quotaLastSuccessfulAt == success { break }
            await Task.yield()
        }
        let provider = await store.snapshot(for: .claude)
        #expect(provider.quotaLastSuccessfulAt == success)
        let snapshot = combined(provider, at: success)
        let settings = SettingsClaudeQuotaPresentation(snapshot: snapshot, now: success)
        let dashboard = SystemDashboardModel(snapshot: snapshot, configuration: .init())
        let calls = repository.callCount
        #expect(calls == 1)
        var frames: [Bool] = []
        await QuotaPresentationTicker.run(clock: TwoFrameQuotaClock(initial: success.addingTimeInterval(899))) { now in
            settings.reproject(at: now)
            dashboard.reproject(at: now)
            frames.append(settings.value.quotaIsLastKnown)
            #expect(dashboard.presentation.ai.first { $0.provider == .claude }?.quotaIsLastKnown == frames.last)
            #expect(repository.callCount == calls)
        }
        #expect(frames == [false, true])
        #expect(repository.callCount == calls)
        await coordinator.stop()
    }

    @Test @MainActor func nextCachedSnapshotClearsDisconnectedBridgeBetweenTicks() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let generation = UUID()
        let oldRecord = StatusLineQuotaRecord(schemaVersion: 1, generation: generation,
            fiveHour: .init(usedPercent: 25, resetsAt: nil, receivedAt: now), sevenDay: nil)
        let store = ProviderSnapshotStore(now: { now })
        await store.applyClaudeStatusLineQuota(oldRecord, expectedGeneration: generation, activeGeneration: { generation })
        let initial = combined(await store.snapshot(for: .claude), at: now)
        let settings = SettingsClaudeQuotaPresentation(snapshot: initial, now: now)
        let dashboard = SystemDashboardModel(snapshot: initial, configuration: .init())
        let clock = TwoFrameQuotaClock(initial: now) {
            await store.reconcileClaudeStatusLineQuota(activeGeneration: { nil })
            // Reuse the generation-fenced application path: a delayed old read cannot restore disconnected values.
            await store.applyClaudeStatusLineQuota(oldRecord, expectedGeneration: generation, activeGeneration: { nil })
            let providers = await store.snapshots()
            let cleared = CombinedUsageSnapshot(system: nil, providers: providers, capturedAt: now, systemAvailability: [:])
            await MainActor.run {
                settings.update(snapshot: cleared, now: now)
                dashboard.update(snapshot: cleared, configuration: .init())
            }
        }
        var values: [String?] = []
        await QuotaPresentationTicker.run(clock: clock) { tick in
            settings.reproject(at: tick)
            dashboard.reproject(at: tick)
            values.append(settings.value.claudeFiveHour?.remaining)
            #expect(dashboard.presentation.ai.first { $0.provider == .claude }?.quotaUnavailable == settings.value.quotaUnavailable)
        }
        #expect(values == ["75%", nil])
        #expect(settings.value.quotaUnavailable)
        #expect(await store.snapshot(for: .claude).claudeStatusLineQuota == nil)
    }

    private func window(id: String = "claude.session", reset: Date? = nil) throws -> QuotaWindow {
        try QuotaWindow(id: id, title: id, usedPercent: 25, resetsAt: reset)
    }

    private func combined(_ provider: ProviderSnapshot, at date: Date, includeSystem: Bool = false) -> CombinedUsageSnapshot {
        let system: SystemMetricsSnapshot? = includeSystem ? .init(capturedAt: date,
            cpu: .init(totalUsage: nil, perCoreUsage: []),
            memory: .init(usedBytes: nil, freeBytes: nil, swapUsedBytes: nil, pressure: nil),
            disks: [.init(name: "Fixture", usedBytes: 10, freeBytes: 90, readBytesPerSecond: 5, writeBytesPerSecond: 7)],
            network: .init(uploadBytesPerSecond: 11, downloadBytesPerSecond: 13, localIPAddresses: [], publicIPAddress: nil),
            battery: .init(level: nil, isCharging: nil, health: nil),
            availability: [.disk: .fresh(capturedAt: date), .network: .fresh(capturedAt: date)]) : nil
        return .init(system: system, providers: [provider], capturedAt: date, systemAvailability: system?.availability ?? [:])
    }
}

private final class CancellationQuotaClock: ClockLike, @unchecked Sendable {
    private let lock = NSLock()
    private var sleeping = false
    var isSleeping: Bool { lock.withLock { sleeping } }
    var now: Date { Date(timeIntervalSince1970: 1_800_000_000) }
    func sleep(for duration: Duration) async throws {
        lock.withLock { sleeping = true }
        try await Task.sleep(for: .seconds(3_600))
    }
}

private struct FrozenQuotaClock: ClockLike {
    let now: Date
    func sleep(for duration: Duration) async throws { try await Task.sleep(for: .seconds(3_600)) }
}

private struct CachedEmptyUsageRepository: UsageRepository {
    func refresh() throws -> UsageRefreshResult { .init(snapshots: [:], errors: [:]) }
}

private final class CachedQuotaRepositorySpy: QuotaRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private let quota: QuotaSnapshot
    init(quota: QuotaSnapshot) { self.quota = quota }
    var callCount: Int { lock.withLock { calls } }
    func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult {
        lock.withLock { calls += 1 }
        return .init(snapshots: [.claude: quota], errors: [:])
    }
}
