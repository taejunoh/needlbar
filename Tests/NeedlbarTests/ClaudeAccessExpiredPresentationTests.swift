import AppKit
import Foundation
import SwiftUI
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore
import NeedlbarClaudeStatusLineSupport

// Increment 1 of docs/superpowers/specs/2026-10-22-claude-credential-renewal-design.md,
// acceptance criteria 2 (shared read), 4, 5, 6 and 7 on the app side. The real
// SwiftUI surfaces are hosted and read through their accessibility tree, so the
// checks cover what is rendered, not only the presentation values.
@Suite(.serialized)
@MainActor
struct ClaudeAccessExpiredPresentationTests {
    // The hosted views age values against the wall clock, so fixtures are
    // relative to the time the suite runs.
    nonisolated static let now = Date()
    nonisolated static let directAt = now.addingTimeInterval(-3_600)
    nonisolated static let attemptAt = now.addingTimeInterval(-600)
    nonisolated static let shortText = "Waiting for Claude Code to renew access"
    nonisolated static let detailText = "Needlbar reads the access Claude Code saves on this Mac. It has expired. Needlbar updates automatically after Claude Code renews it."
    nonisolated static let oldText = "Quota access unavailable"
    nonisolated static var directChecked: String {
        DateFormatter.localizedString(from: directAt, dateStyle: .medium, timeStyle: .short)
    }

    // MARK: - No recent value: the existing reason slot

    @Test func withoutRecentValuesTheNewTextUsesTheExistingSlotOnEverySurface() throws {
        let snapshot = try Self.claude(reason: .claudeCodeAccessExpired, statusLine: nil)
        let popover = ProviderPopoverPresentation(snapshot: snapshot, now: Self.now)
        #expect(!popover.hasRecentClaudeQuota)
        #expect(popover.quotaFailureReasonText == Self.shortText)
        #expect(popover.quotaFailureDetailText == Self.detailText)
        #expect(popover.fableFailureReasonText == nil)

        let dashboard = try #require(Self.dashboard(snapshot).ai.first { $0.provider == .claude })
        #expect(dashboard.quotaFailureReasonText == Self.shortText)
        #expect(dashboard.fable?.statusText == nil)

        for surface in Surface.allCases {
            let rendered = try surface.render(snapshot)
            #expect(rendered.count(containing: Self.shortText) == 1, "\(surface) must show the reason once")
            #expect(rendered.count(containing: Self.detailText) == (surface.showsDetail ? 1 : 0), "\(surface) detail line")
            let index = try #require(rendered.items.firstIndex { $0.contains(Self.shortText) })
            let reason = rendered.items[index]
            #expect(reason.role == "AXStaticText")
            #expect(reason.spoken == Self.shortText, "\(surface) reason accessibility label")
            // The existing slot follows the "Last known" retained-value line,
            // not the Fable line.
            #expect(!rendered.items[index - 1].contains("Fable"), "\(surface) reason left the existing slot")
            if surface.showsDetail {
                #expect(rendered.items[index + 1].spoken == Self.detailText, "\(surface) detail follows the reason")
            }
        }
    }

    @Test func everythingElseRendersExactlyAsWithTheGenericReason() throws {
        for statusLine in [nil, Self.recentStatusLine()] {
            let new = try Self.claude(reason: .claudeCodeAccessExpired, statusLine: statusLine)
            let old = try Self.claude(reason: .quotaAccessUnavailable, statusLine: statusLine)
            for surface in Surface.allCases {
                // Remove the new lines (or the new status suffix on the compact
                // Fable line) and the old reason line; the rest must be equal.
                let newItems = try surface.render(new).items.compactMap { item -> AccessibilityItem? in
                    if item.spoken == Self.shortText || item.spoken == Self.detailText { return nil }
                    return item.removing(" · \(Self.shortText)")
                }
                let oldItems = try surface.render(old).items.filter { $0.spoken != Self.oldText }
                #expect(newItems == oldItems, "\(surface) changed beyond the reason lines")
            }
        }
    }

    // MARK: - Recent status-line windows: once, on the Fable line

    @Test func recentStatusLineWindowsKeepTheMainPresentationAndMoveTheReasonToTheFableLine() throws {
        let new = try Self.claude(reason: .claudeCodeAccessExpired, statusLine: Self.recentStatusLine())
        let old = try Self.claude(reason: .quotaAccessUnavailable, statusLine: Self.recentStatusLine())
        let newPopover = ProviderPopoverPresentation(snapshot: new, now: Self.now)
        let oldPopover = ProviderPopoverPresentation(snapshot: old, now: Self.now)

        #expect(newPopover.hasRecentClaudeQuota)
        #expect(newPopover.mainWindowFields == oldPopover.mainWindowFields)
        #expect(newPopover.quotaFailureReasonText == nil)
        #expect(newPopover.fableFailureReasonText == Self.shortText)
        #expect(newPopover.quotaFailureDetailText == Self.detailText)
        #expect(oldPopover.fableFailureReasonText == nil)

        let newDashboard = try #require(Self.dashboard(new).ai.first { $0.provider == .claude })
        let oldDashboard = try #require(Self.dashboard(old).ai.first { $0.provider == .claude })
        #expect(newDashboard.mainFields == oldDashboard.mainFields)
        #expect(newDashboard.quotaFailureReasonText == nil)
        #expect(newDashboard.fable?.statusText == Self.shortText)
        #expect(newDashboard.fable?.compactStatusText == "Last known · \(Self.shortText)")
        #expect(oldDashboard.fable?.statusText == nil)

        // The line just before the reason is the last Fable line of each surface.
        let fableLine: [Surface: String] = [
            .popover: "Last checked \(Self.directChecked)",
            .settings: "Fable last checked \(Self.directChecked)",
            .dashboard: "Fable",
        ]
        for surface in Surface.allCases {
            let rendered = try surface.render(new)
            #expect(rendered.count(containing: "Reported by Claude Code") >= 1, "\(surface) is not in the recent state")
            #expect(rendered.count(containing: Self.shortText) == 1, "\(surface) must show the reason once")
            #expect(rendered.count(containing: Self.detailText) == (surface.showsDetail ? 1 : 0), "\(surface) detail line")
            let index = try #require(rendered.items.firstIndex { $0.contains(Self.shortText) })
            #expect(rendered.items[index - 1].spoken == fableLine[surface], "\(surface) reason must sit on the Fable line")
            // The compact dashboard status is drawn after a bullet; its label is
            // the full status without it.
            #expect(rendered.items[index].spoken
                == (surface == .dashboard ? "Last known · \(Self.shortText)" : Self.shortText),
                "\(surface) reason accessibility label")
            if surface.showsDetail {
                #expect(rendered.items[index + 1].spoken == Self.detailText, "\(surface) detail follows the reason")
            }
        }
    }

    @Test func unavailableFableStillCarriesTheReasonOnItsLine() throws {
        let snapshot = try Self.claude(reason: .claudeCodeAccessExpired, statusLine: Self.recentStatusLine(), directSuccess: false)
        #expect(ProviderPopoverPresentation(snapshot: snapshot, now: Self.now).fableFailureReasonText == Self.shortText)
        let dashboard = try #require(Self.dashboard(snapshot).ai.first { $0.provider == .claude })
        #expect(dashboard.fable?.remaining == "—")
        #expect(dashboard.fable?.statusText == Self.shortText)
        let fableLine: [Surface: String] = [
            .popover: "Fable weekly · Unavailable",
            .settings: "Fable weekly unavailable",
            .dashboard: "Fable",
        ]
        for surface in Surface.allCases {
            let rendered = try surface.render(snapshot)
            #expect(rendered.count(containing: Self.shortText) == 1, "\(surface)")
            let index = try #require(rendered.items.firstIndex { $0.contains(Self.shortText) })
            #expect(rendered.items[index - 1].spoken == fableLine[surface], "\(surface) reason must sit on the Fable line")
        }
    }

    @Test func lastCheckedShowsTheLastDirectSuccessNeverTheAttempt() throws {
        let snapshot = try Self.claude(reason: .claudeCodeAccessExpired, statusLine: Self.recentStatusLine())
        let attempt = DateFormatter.localizedString(from: Self.attemptAt, dateStyle: .medium, timeStyle: .short)
        #expect(Self.directChecked != attempt)
        #expect(ProviderPopoverPresentation(snapshot: snapshot, now: Self.now).fableLastCheckedText == Self.directChecked)
        #expect(try #require(Self.dashboard(snapshot).ai.first { $0.provider == .claude }).fable?.lastCheckedText == Self.directChecked)
        for surface in Surface.allCases {
            let rendered = try surface.render(snapshot)
            #expect(rendered.count(containing: Self.directChecked) >= 1, "\(surface) must show the last direct success")
            #expect(rendered.count(containing: attempt) == 0, "\(surface) must not show the attempt time")
        }
    }

    // MARK: - No new control, no sign-in, no side effects

    @Test func noSurfaceAddsAControlSignInOrCommandText() throws {
        for statusLine in [nil, Self.recentStatusLine()] {
            let new = try Self.claude(reason: .claudeCodeAccessExpired, statusLine: statusLine)
            let old = try Self.claude(reason: .quotaAccessUnavailable, statusLine: statusLine)
            for surface in Surface.allCases {
                let rendered = try surface.render(new)
                let previous = try surface.render(old)
                #expect(rendered.buttons == previous.buttons, "\(surface) controls changed")
                for forbidden in ["Sign in", "Log in", "Login", "Terminal", "Open Claude Code"] {
                    #expect(rendered.count(containing: forbidden) == 0, "\(surface) shows \(forbidden)")
                }
            }
        }
    }

    @Test func renderingTriggersNoLaunchURLOpenOrLoginCall() async throws {
        let spies = ActionSpies()
        let runner = LoginRunnerSpy()
        let login = ProviderLoginCoordinator(
            resolver: LoginResolverSpy(), runner: runner,
            refreshQuota: { _ in spies.record("refreshQuota"); return false },
            preflightClaudeLogin: { spies.record("preflight"); return .verificationFailed })
        for statusLine in [nil, Self.recentStatusLine()] {
            let snapshot = try Self.claude(reason: .claudeCodeAccessExpired, statusLine: statusLine)
            _ = try Rendered(ProviderPopoverView(
                snapshot: snapshot,
                onRetry: { spies.record("retry") },
                onAuthenticationAction: { _ in
                    spies.record("open")
                    MainActor.assumeIsolated { _ = login.connect(.claude) }
                    return true
                }))
            _ = try Rendered(SystemDashboardPopoverView(
                model: SystemDashboardModel(snapshot: Self.combined(snapshot), configuration: Self.dashboardConfiguration),
                layout: SystemDashboardPopoverLayout(height: 900),
                onShowSettings: { spies.record("settings") },
                onShowAnalytics: { spies.record("analytics") },
                onProviderAction: { provider in
                    spies.record("provider \(provider)")
                    MainActor.assumeIsolated { _ = login.connect(provider) }
                },
                onAPIBillingAction: { _ in spies.record("billing"); return true },
                onClaudeUsageAction: { spies.record("usage"); return true }))
            _ = try Rendered(Self.settingsRow(snapshot,
                openClaudeUsage: { spies.record("usage"); return true },
                openCursorSpending: { spies.record("cursor") }))
        }
        await Task.yield()
        #expect(spies.calls.isEmpty)
        #expect(runner.runCount == 0)
        #expect(login.state(for: .claude) == .idle)
    }

    @Test func codexCursorUsageBillingMenuBarAndAlertsAreUnchanged() throws {
        for statusLine in [nil, Self.recentStatusLine()] {
            let new = Self.combined(try Self.claude(reason: .claudeCodeAccessExpired, statusLine: statusLine))
            let old = Self.combined(try Self.claude(reason: .quotaAccessUnavailable, statusLine: statusLine))
            let newDashboard = Self.dashboard(new.providers[0])
            let oldDashboard = Self.dashboard(old.providers[0])
            #expect(newDashboard.ai.filter { $0.provider != .claude } == oldDashboard.ai.filter { $0.provider != .claude })
            let newClaude = try #require(newDashboard.ai.first { $0.provider == .claude })
            let oldClaude = try #require(oldDashboard.ai.first { $0.provider == .claude })
            #expect(newClaude.apiBillingAction == oldClaude.apiBillingAction)
            #expect(newClaude.usageStatus == oldClaude.usageStatus)
            let newPopover = ProviderPopoverPresentation(snapshot: new.providers[0], now: Self.now)
            let oldPopover = ProviderPopoverPresentation(snapshot: old.providers[0], now: Self.now)
            #expect(newPopover.tokensToday == oldPopover.tokensToday)
            #expect(newPopover.estimatedCostToday == oldPopover.estimatedCostToday)
            for provider in [ProviderID.codex, .cursor] {
                #expect(ProviderPopoverPresentation(snapshot: new.providers.first { $0.provider == provider }!, now: Self.now)
                    == ProviderPopoverPresentation(snapshot: old.providers.first { $0.provider == provider }!, now: Self.now))
            }
            var menuConfiguration = SystemMonitorConfiguration()
            menuConfiguration.menuBarVisibleModules = [.ai]
            #expect(MenuBarDashboardRenderer.render(snapshot: new, configuration: menuConfiguration, availableWidth: 400)
                == MenuBarDashboardRenderer.render(snapshot: old, configuration: menuConfiguration, availableWidth: 400))
            #expect(OverviewPopoverPresentation(snapshots: new.providers, dailyUsage: [], now: Self.now).headlineQuotaRemaining
                == OverviewPopoverPresentation(snapshots: old.providers, dailyUsage: [], now: Self.now).headlineQuotaRemaining)
        }
    }

    // MARK: - Shared read and logs

    @Test func reporterSharesTheCoordinatorReadAndLogsOnlyAllowlistedFields() async throws {
        let diagnosticsCalls = Counter()
        let quotaCalls = Counter()
        let json = """
        {"schemaVersion":"needlbar.v1","ok":true,"generatedAt":"2026-10-18T00:00:00Z","data":{"providers":[{"provider":"claude","usageStatus":"available","quotaStatus":"requiresAuthentication","usageSource":"local","quotaSource":"oauth","lastAttemptAt":"\(ISO8601DateFormatter().string(from: Self.now))","claudeQuotaFailureOrigin":"keychainCredentialExpired","rawSecretCanary":"CLAUDE-CANARY-SECRET","accountPath":"/private/canary"}]},"errors":[]}
        """
        let bridge = RustBridge(
            quotaCall: { quotaCalls.increment(); return nil },
            claudePreflightQuotaCall: { quotaCalls.increment(); return nil },
            claudeUserInitiatedQuotaCall: { quotaCalls.increment(); return nil },
            codexQuotaCall: { quotaCalls.increment(); return nil },
            diagnosticsCall: { diagnosticsCalls.increment(); return Self.cString(json) },
            free: { $0.map { UnsafeMutablePointer(mutating: $0).deallocate() } })
        let events = EventSink()
        let reporter = ClaudeQuotaFailureDiagnosticsReporter(readDiagnostics: bridge.diagnosticsEnvelope, sink: { events.append($0) })
        let store = ProviderSnapshotStore(now: { Self.now })
        let repository = OneShotQuotaRepository(.init(snapshots: [:], errors: [.claude: .init(
            provider: "claude", code: "authenticationExpired", message: "RAW_ERROR_TOKEN_PATH_CANARY", action: nil)]))
        let coordinator = RefreshCoordinator(
            usageRepository: NoUsageRepository(), quotaRepository: repository, store: store,
            clock: FixedClock(now: Self.now),
            claudeQuotaDiagnostics: reporter.completionDiagnostics)

        await coordinator.popoverOpened()
        let deadline = Date().addingTimeInterval(10)
        while events.values.isEmpty, Date() < deadline { try await Task.sleep(for: .milliseconds(1)) }

        #expect(diagnosticsCalls.value == 1)
        #expect(quotaCalls.value == 0)
        #expect(repository.callCount == 1)
        #expect(events.values.map(\.origin) == [.keychainCredentialExpired])
        let snapshot = await store.snapshot(for: .claude)
        #expect(snapshot.claudeQuotaFailureReason == .claudeCodeAccessExpired)

        let presentation = ProviderPopoverPresentation(snapshot: snapshot, now: Self.now)
        let surfaces = [String(describing: events.values), String(describing: presentation)]
            + (try Surface.allCases.map { try $0.render(snapshot).items.map(\.description).joined() })
        for text in surfaces {
            for marker in ["CLAUDE-CANARY-SECRET", "/private/canary", "RAW_ERROR_TOKEN_PATH_CANARY"] {
                #expect(!text.contains(marker), "\(marker) leaked")
            }
        }
    }
}

// MARK: - Surfaces and accessibility capture

private enum Surface: CaseIterable, Hashable, CustomStringConvertible {
    case popover, settings, dashboard

    var description: String {
        switch self {
        case .popover: "provider popover"
        case .settings: "Settings Claude row"
        case .dashboard: "dashboard"
        }
    }

    var showsDetail: Bool { self != .dashboard }

    @MainActor
    func render(_ snapshot: ProviderSnapshot) throws -> Rendered {
        switch self {
        case .popover:
            return try Rendered(ProviderPopoverView(snapshot: snapshot))
        case .settings:
            return try Rendered(ClaudeAccessExpiredPresentationTests.settingsRow(snapshot))
        case .dashboard:
            let layout = SystemDashboardPopoverLayout(height: 900)
            layout.quotaDetailsExpanded = true
            return try Rendered(SystemDashboardPopoverView(
                model: SystemDashboardModel(
                    snapshot: ClaudeAccessExpiredPresentationTests.combined(snapshot),
                    configuration: ClaudeAccessExpiredPresentationTests.dashboardConfiguration),
                layout: layout))
        }
    }
}

private struct AccessibilityItem: Equatable, CustomStringConvertible {
    let role: String
    let label: String
    let value: String

    func contains(_ text: String) -> Bool { label.contains(text) || value.contains(text) }
    /// What VoiceOver announces. SwiftUI on macOS exposes a static text's
    /// accessibility label as its AXValue, so the label wins over the visible text.
    var spoken: String { label.isEmpty ? value : label }
    func removing(_ text: String) -> AccessibilityItem {
        .init(role: role, label: label.replacingOccurrences(of: text, with: ""),
              value: value.replacingOccurrences(of: text, with: ""))
    }
    var description: String { "\(role)|\(label)|\(value)" }
}

/// Hosts a view in a window and collects its accessibility tree in order.
@MainActor
private struct Rendered {
    let items: [AccessibilityItem]

    init<Content: View>(_ content: Content, width: CGFloat = 320) throws {
        // SwiftUI builds a hosting view's accessibility tree only for an
        // assistive client; the enhanced-interface flag stands in for one.
        let application = NSApplication.shared
        guard application.responds(to: NSSelectorFromString("isAccessibilityEnhancedUserInterface")),
              application.responds(to: NSSelectorFromString("setAccessibilityEnhancedUserInterface:")) else {
            Issue.record("NSApplication cannot expose the SwiftUI accessibility tree on this macOS")
            items = []
            return
        }
        let wasEnhanced = application.value(forKey: "accessibilityEnhancedUserInterface") as? Bool ?? false
        application.setValue(true, forKey: "accessibilityEnhancedUserInterface")
        defer { application.setValue(wasEnhanced, forKey: "accessibilityEnhancedUserInterface") }

        let host = NSHostingView(rootView: content.frame(width: width, alignment: .topLeading))
        let height = max(200, host.fittingSize.height)
        let frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.frame = frame
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        for _ in 0..<3 {
            window.display()
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        var collected: [AccessibilityItem] = []
        Self.walk(host, into: &collected, depth: 0)
        items = collected
        #expect(!items.isEmpty, "accessibility tree was empty")
    }

    var buttons: [String] { items.filter { $0.role == "AXButton" }.map(\.label) }

    func count(containing text: String) -> Int { items.filter { $0.contains(text) }.count }

    private static func walk(_ element: Any, into items: inout [AccessibilityItem], depth: Int) {
        guard depth < 40, let node = element as? NSObject else { return }
        let role = (node.value(forKey: "accessibilityRole") as? String) ?? ""
        let label = (node.value(forKey: "accessibilityLabel") as? String) ?? ""
        let value = node.value(forKey: "accessibilityValue").map { "\($0)" } ?? ""
        if !(node is NSView) { items.append(.init(role: role, label: label, value: value)) }
        for child in (node.value(forKey: "accessibilityChildren") as? [Any]) ?? [] {
            walk(child, into: &items, depth: depth + 1)
        }
    }
}

// MARK: - Fixtures

private extension ClaudeAccessExpiredPresentationTests {
    static var dashboardConfiguration: SystemMonitorConfiguration {
        var configuration = SystemMonitorConfiguration(aiOrder: [.claude, .codex, .cursor], dashboardVisibleModules: [.ai])
        configuration.ai[.claude]?.apiBillingLinkVisible = true
        return configuration
    }

    static func recentStatusLine() -> StatusLineQuotaRecord {
        StatusLineQuotaRecord(schemaVersion: 1, generation: UUID(uuidString: "00000000-0000-0000-0000-000000000026")!,
            fiveHour: .init(usedPercent: 25, resetsAt: now.addingTimeInterval(3_600), receivedAt: now.addingTimeInterval(-30)),
            sevenDay: .init(usedPercent: 35, resetsAt: now.addingTimeInterval(86_400), receivedAt: now.addingTimeInterval(-30)))
    }

    static func claude(
        reason: ClaudeQuotaFailureReason,
        statusLine: StatusLineQuotaRecord?,
        directSuccess: Bool = true
    ) throws -> ProviderSnapshot {
        let windows = try [
            QuotaWindow(id: "claude.session", title: "Session", usedPercent: 68, resetsAt: directAt.addingTimeInterval(7_200)),
            QuotaWindow(id: "claude.weekly", title: "Weekly", usedPercent: 53, resetsAt: directAt.addingTimeInterval(86_400)),
            QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "Fable weekly", usedPercent: 42,
                        resetsAt: directAt.addingTimeInterval(86_400)),
        ]
        return ProviderSnapshot(
            provider: .claude,
            usage: usage(),
            quota: directSuccess ? QuotaSnapshot(windows: windows) : nil,
            usageStatus: .fresh,
            quotaStatus: .requiresAuthentication,
            updatedAt: attemptAt,
            claudeQuotaFailureReason: reason,
            quotaLastSuccessfulAt: directSuccess ? directAt : nil,
            claudeStatusLineQuota: statusLine
        )
    }

    static func combined(_ claude: ProviderSnapshot) -> CombinedUsageSnapshot {
        let codex = ProviderSnapshot(
            provider: .codex, usage: usage(), quota: QuotaSnapshot(windows: [
                try! QuotaWindow(id: "codex.primary", title: "Primary", usedPercent: 45, resetsAt: nil),
            ]), usageStatus: .fresh, quotaStatus: .fresh, updatedAt: now, quotaLastSuccessfulAt: now)
        let cursor = ProviderSnapshot(
            provider: .cursor, usage: usage(), quota: nil, usageStatus: .fresh, quotaStatus: .unavailable, updatedAt: now)
        return CombinedUsageSnapshot(system: nil, providers: [claude, codex, cursor], capturedAt: now, systemAvailability: [:])
    }

    static func dashboard(_ claude: ProviderSnapshot) -> SystemDashboardPresentation {
        SystemDashboardPresentation(snapshot: combined(claude), configuration: dashboardConfiguration, now: now)
    }

    static func usage() -> UsageSnapshot {
        let period = UsagePeriod(inputTokens: 1_000, outputTokens: 400, cacheReadTokens: 0, cacheWriteTokens: 0,
                                 totalTokens: 1_400, estimatedCostUSD: Decimal(string: "1.25")!)
        return UsageSnapshot(inputTokens: 1_000, outputTokens: 400, cacheReadTokens: 0, cacheWriteTokens: 0,
                             totalTokens: 1_400, estimatedCostUSD: Decimal(string: "1.25")!, today: period,
                             last7Days: period, last30Days: period)
    }

    static func settingsRow(
        _ snapshot: ProviderSnapshot,
        openClaudeUsage: @escaping () -> Bool = { false },
        openCursorSpending: @escaping () -> Void = {}
    ) -> some View {
        let name = "ClaudeAccessExpired.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = QuotaNotificationPreferences(defaults: defaults)
        return SettingsView(
            configuration: ModuleConfiguration(defaults: defaults),
            actions: SettingsActions(),
            notificationPreferences: preferences,
            notificationService: QuotaNotificationService(store: ProviderSnapshotStore(), preferences: preferences),
            openCursorSpending: openCursorSpending,
            openClaudeUsage: openClaudeUsage,
            claudeQuotaPresentation: SettingsClaudeQuotaPresentation(snapshot: combined(snapshot), now: now)
        ).claudeUsageRowContent
    }

    nonisolated static func cString(_ text: String) -> UnsafePointer<CChar>? {
        let bytes = Array(text.utf8).map(CChar.init) + [0]
        let pointer = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count)
        pointer.initialize(from: bytes, count: bytes.count)
        return UnsafePointer(pointer)
    }
}

private struct MainWindowFields: Equatable {
    let values: [String?]
    let flags: [Bool]
    let windows: [ClaudePopoverQuotaDetail?]
    let other: [ClaudePopoverQuotaDetail]
    let action: ProviderAuthenticationAction?
}

private extension ProviderPopoverPresentation {
    var mainWindowFields: MainWindowFields {
        MainWindowFields(
            values: [headlineQuotaRemaining, lastKnownQuotaRemaining, quotaFailureReasonText, quotaLastCheckedText,
                     quotaSourceText, quotaObservationLabel, fableLastCheckedText, freshnessSummary,
                     quotaFreshness.label, usageFreshness.label],
            flags: [quotaIsLastKnown, quotaUnavailable, fableIsLastKnown, hasRecentClaudeQuota, requiresProviderSignIn],
            windows: [claudeFiveHour, claudeSevenDay, claudeFable],
            other: claudeOtherWindows,
            action: authenticationAction)
    }
}

private struct DashboardMainFields: Equatable {
    let strings: [String?]
    let flags: [Bool]
    let action: ProviderAuthenticationAction?
    let fableRemaining: String?
    let fableReset: String?
    let fableChecked: String?
}

private extension SystemDashboardPresentation.AIProvider {
    var mainFields: DashboardMainFields {
        DashboardMainFields(
            strings: [value, caption, statusText, quotaLastKnownRemaining, quotaFailureReasonText, quotaLastCheckedText,
                      quotaSourceText, quotaObservationLabel, compactQuotaValue, compactQuotaLabel],
            flags: [quotaIsLastKnown, quotaUnavailable, showsCompactClaudeQuota],
            action: action,
            fableRemaining: fable?.remaining,
            fableReset: fable?.resetCaption,
            fableChecked: fable?.lastCheckedText)
    }
}

// MARK: - Test doubles

private final class ActionSpies: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    var calls: [String] { lock.withLock { recorded } }
    func record(_ call: String) { lock.withLock { recorded.append(call) } }
}

private final class LoginRunnerSpy: ProviderLoginProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var runs = 0
    var runCount: Int { lock.withLock { runs } }
    func run(_ command: ProviderLoginCommand) async -> ProviderLoginProcessOutcome {
        lock.withLock { runs += 1 }
        return .launchFailed
    }
    func stop() async -> ProviderLoginCleanupResult { .complete }
    func waitForReaping(for provider: ProviderID) async {}
}

private struct LoginResolverSpy: ProviderLoginCommandResolving {
    func command(for provider: ProviderID) throws -> ProviderLoginCommand {
        ProviderLoginCommand(provider: provider, executableURL: URL(fileURLWithPath: "/nonexistent/fixture"),
                             arguments: [], environment: [:])
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private final class EventSink: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [ClaudeQuotaFailureDiagnosticEvent] = []
    var values: [ClaudeQuotaFailureDiagnosticEvent] { lock.withLock { events } }
    func append(_ event: ClaudeQuotaFailureDiagnosticEvent) { lock.withLock { events.append(event) } }
}

private final class OneShotQuotaRepository: QuotaRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let result: QuotaRefreshResult
    private var calls = 0
    init(_ result: QuotaRefreshResult) { self.result = result }
    var callCount: Int { lock.withLock { calls } }
    func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult {
        lock.withLock { calls += 1 }
        return result
    }
}

private struct NoUsageRepository: UsageRepository {
    func refresh() throws -> UsageRefreshResult { .init(snapshots: [:], errors: [:]) }
}

private struct FixedClock: ClockLike {
    let now: Date
    func sleep(for duration: Duration) async throws { try await Task.sleep(for: .seconds(3_600)) }
}
