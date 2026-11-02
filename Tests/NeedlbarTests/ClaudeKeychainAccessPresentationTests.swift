import AppKit
import Foundation
import SwiftUI
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore
import NeedlbarClaudeStatusLineSupport

// The explicit "Allow Keychain access" action. The real SwiftUI surfaces are
// hosted, read through their accessibility tree and pressed through it, so the
// checks cover what is rendered and what a click does. Everything is synthetic:
// nothing here touches credentials or the Keychain.
@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct ClaudeKeychainAccessPresentationTests {
    nonisolated static let now = Date()
    nonisolated static let title = "Allow Keychain access"
    nonisolated static let reasonText = "Credential access unavailable"
    nonisolated static let allReasons: [ClaudeQuotaFailureReason] = [
        .quotaAccessUnavailable, .credentialAccessUnavailable, .connectionUnavailable,
        .temporarilyLimited, .couldNotUpdateQuota, .claudeCodeAccessExpired,
    ]

    // MARK: - Visibility

    @Test func onlyCredentialAccessUnavailableOffersTheAction() throws {
        for statusLine in [nil, Self.recentStatusLine()] {
            for reason in Self.allReasons {
                let expected: ProviderAuthenticationAction? = reason == .credentialAccessUnavailable
                    ? .allowClaudeKeychainAccess(title: Self.title) : nil
                let snapshot = try Self.claude(reason: reason, statusLine: statusLine)
                #expect(ProviderPopoverPresentation(snapshot: snapshot, now: Self.now).keychainAccessAction == expected, "\(reason)")
                #expect(Self.dashboardRow(snapshot).keychainAccessAction == expected, "\(reason)")
            }
            let healthy = try Self.claude(reason: nil, statusLine: statusLine)
            #expect(ProviderPopoverPresentation(snapshot: healthy, now: Self.now).keychainAccessAction == nil)
            #expect(Self.dashboardRow(healthy).keychainAccessAction == nil)
        }
    }

    @Test func viewClaudeUsageStaysAvailableBesideTheAction() throws {
        for statusLine in [nil, Self.recentStatusLine()] {
            let snapshot = try Self.claude(reason: .credentialAccessUnavailable, statusLine: statusLine)
            let usage = ProviderAuthenticationAction.openClaudeUsage(title: "View Claude usage")
            #expect(ProviderPopoverPresentation(snapshot: snapshot, now: Self.now).authenticationAction == usage)
            #expect(Self.dashboardRow(snapshot).action == usage)
        }
    }

    @Test func otherProvidersNeverOfferTheAction() throws {
        for provider in [ProviderID.codex, .cursor] {
            let snapshot = ProviderSnapshot(
                provider: provider, usage: nil, quota: nil, usageStatus: .fresh,
                quotaStatus: .error(message: "denied", lastSuccessfulAt: nil), updatedAt: Self.now,
                claudeQuotaFailureReason: .credentialAccessUnavailable)
            #expect(ProviderPopoverPresentation(snapshot: snapshot, now: Self.now).keychainAccessAction == nil)
        }
    }

    @Test func everySurfaceRendersOneButtonBesideUsageAndOnlyForThisReason() throws {
        for surface in Surface.allCases {
            for statusLine in [nil, Self.recentStatusLine()] {
                let offered = try surface.render(Self.claude(reason: .credentialAccessUnavailable, statusLine: statusLine))
                #expect(offered.buttons.filter { $0 == Self.title }.count == 1, "\(surface) \(offered.buttons)")
                #expect(offered.buttons.contains("View Claude usage"), "\(surface) \(offered.buttons)")

                for reason in Self.allReasons where reason != .credentialAccessUnavailable {
                    let rendered = try surface.render(Self.claude(reason: reason, statusLine: statusLine))
                    #expect(!rendered.buttons.contains(Self.title), "\(surface) \(reason) offered the action")
                    #expect(rendered.buttons.contains("View Claude usage"), "\(surface) \(reason)")
                }
            }
        }
    }

    /// The button must not appear without its reason. While status-line windows
    /// are recent the reason sits once on the direct-only Fable line, exactly
    /// where the expired reason sits, because Fable is what it keeps stale.
    @Test func withRecentStatusLineWindowsTheReasonSitsOnceOnTheFableLine() throws {
        let snapshot = try Self.claude(reason: .credentialAccessUnavailable, statusLine: Self.recentStatusLine())
        let popover = ProviderPopoverPresentation(snapshot: snapshot, now: Self.now)
        #expect(popover.hasRecentClaudeQuota)
        #expect(popover.quotaFailureReasonText == nil)
        #expect(popover.fableFailureReasonText == Self.reasonText)
        // The dashboard's standard row has no Fable line, as for the expired
        // reason, so there the button's title stands alone.
        for surface in [Surface.popover, .settings, .dashboardCompact] {
            let rendered = try surface.render(snapshot)
            #expect(rendered.count(containing: Self.reasonText) == 1, "\(surface) \(rendered.items)")
        }
    }

    @Test func withoutRecentValuesTheReasonKeepsItsExistingSlot() throws {
        let snapshot = try Self.claude(reason: .credentialAccessUnavailable, statusLine: nil)
        let popover = ProviderPopoverPresentation(snapshot: snapshot, now: Self.now)
        #expect(!popover.hasRecentClaudeQuota)
        #expect(popover.quotaFailureReasonText == Self.reasonText)
        #expect(popover.fableFailureReasonText == nil)
        for surface in Surface.allCases {
            #expect(try surface.render(snapshot).count(containing: Self.reasonText) == 1, "\(surface)")
        }
    }

    // MARK: - A click, and only a click

    @Test func renderingEverySurfaceTriggersNothingAndEachButtonFiresOnce() throws {
        let snapshot = try Self.claude(reason: .credentialAccessUnavailable, statusLine: nil)
        let clicks = ClickCounter()

        try Hosted(ProviderPopoverView(
            snapshot: snapshot,
            onAuthenticationAction: { action in
                if case .allowClaudeKeychainAccess = action { clicks.value += 1 }
                return true
            })) { hosted in
            #expect(clicks.value == 0, "rendering the popover must not request access")
            try hosted.press(Self.title)
            #expect(clicks.value == 1)
        }

        for metric in [AIProviderDisplayMetric.remaining, .usage] {
            clicks.value = 0
            try Hosted(SystemDashboardPopoverView(
                model: SystemDashboardModel(snapshot: Self.combined(snapshot), configuration: Self.dashboardConfiguration(metric: metric)),
                layout: SystemDashboardPopoverLayout(height: 900),
                onClaudeKeychainAccessAction: { _ in clicks.value += 1 })) { hosted in
                #expect(clicks.value == 0, "rendering the dashboard must not request access")
                try hosted.press(Self.title)
                #expect(clicks.value == 1)
            }
        }
    }

    @Test func theSettingsButtonRunsOneOperationAndIsDisabledWhileItRuns() async throws {
        let snapshot = try Self.claude(reason: .credentialAccessUnavailable, statusLine: nil)
        let operation = HeldOperation()
        let actions = SettingsActions(claudeKeychainAccessOperation: { await operation.run() })

        try Hosted(Self.settingsRow(snapshot, actions: actions)) { hosted in
            #expect(operation.startCount == 0, "rendering Settings must not request access")
            let enabled = try hosted.isEnabled(Self.title)
            #expect(enabled)
            try hosted.press(Self.title)
            #expect(actions.isRequestingClaudeKeychainAccess)
        }
        // The row is hosted without its SettingsView, so it reads the state once.
        try Hosted(Self.settingsRow(snapshot, actions: actions)) { hosted in
            let enabled = try hosted.isEnabled(Self.title)
            #expect(!enabled, "a second click must not be possible")
        }
        await operation.waitUntilStarted()
        #expect(operation.startCount == 1)

        // A click from another surface while it runs changes nothing.
        actions.requestClaudeKeychainAccess()
        await Task.yield()
        #expect(operation.startCount == 1)

        operation.finish()
        await operation.waitUntilFinished()
        while actions.isRequestingClaudeKeychainAccess, !Task.isCancelled { await Task.yield() }

        actions.requestClaudeKeychainAccess()
        await operation.waitUntilStarted(count: 2)
        #expect(operation.startCount == 2, "a finished request allows a later click")
        operation.finish()
        await operation.waitUntilFinished()
    }

    @Test func actionsWithoutAnOperationIgnoreTheRequest() {
        let actions = SettingsActions()
        actions.requestClaudeKeychainAccess()
        #expect(!actions.isRequestingClaudeKeychainAccess)
    }
}

// MARK: - Surfaces

private enum Surface: CaseIterable, CustomStringConvertible {
    case popover, settings, dashboardCompact, dashboardStandard

    var description: String {
        switch self {
        case .popover: "provider popover"
        case .settings: "Settings Connection row"
        case .dashboardCompact: "dashboard compact row"
        case .dashboardStandard: "dashboard standard row"
        }
    }

    @MainActor
    func render(_ snapshot: ProviderSnapshot) throws -> RenderedButtons {
        let tests = ClaudeKeychainAccessPresentationTests.self
        switch self {
        case .popover:
            return try RenderedButtons(ProviderPopoverView(snapshot: snapshot))
        case .settings:
            return try RenderedButtons(tests.settingsRow(snapshot, actions: SettingsActions()))
        case .dashboardCompact, .dashboardStandard:
            let layout = SystemDashboardPopoverLayout(height: 900)
            layout.quotaDetailsExpanded = true
            let metric: AIProviderDisplayMetric = self == .dashboardCompact ? .remaining : .usage
            return try RenderedButtons(SystemDashboardPopoverView(
                model: SystemDashboardModel(snapshot: tests.combined(snapshot), configuration: tests.dashboardConfiguration(metric: metric)),
                layout: layout))
        }
    }
}

// MARK: - Accessibility host

private final class ClickCounter {
    var value = 0
}

private final class HeldOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    private var finishes = 0
    private var held: [CheckedContinuation<Void, Never>] = []

    var startCount: Int { lock.withLock { starts } }

    func run() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                starts += 1
                held.append(continuation)
            }
        }
        lock.withLock { finishes += 1 }
    }

    func finish() {
        let continuation = lock.withLock { held.isEmpty ? nil : held.removeFirst() }
        continuation?.resume()
    }

    func waitUntilStarted(count: Int = 1) async {
        while startCount < count, !Task.isCancelled { await Task.yield() }
    }

    func waitUntilFinished() async {
        while !Task.isCancelled, lock.withLock({ finishes < starts }) { await Task.yield() }
    }
}

private struct RenderedItem: CustomStringConvertible {
    let role: String
    let label: String
    let value: String
    func contains(_ text: String) -> Bool { label.contains(text) || value.contains(text) }
    var description: String { "\(role)|\(label)|\(value)" }
}

/// Hosts a view and keeps it alive for the body, so its controls can be pressed.
@MainActor
private final class Hosted {
    private let host: NSView
    private let window: NSWindow

    @discardableResult
    init<Content: View>(_ content: Content, body: (Hosted) throws -> Void = { _ in }) throws {
        let application = NSApplication.shared
        let wasEnhanced = application.value(forKey: "accessibilityEnhancedUserInterface") as? Bool ?? false
        application.setValue(true, forKey: "accessibilityEnhancedUserInterface")
        defer { application.setValue(wasEnhanced, forKey: "accessibilityEnhancedUserInterface") }

        let hosting = NSHostingView(rootView: content.frame(width: 320, alignment: .topLeading))
        let frame = NSRect(x: 0, y: 0, width: 320, height: max(200, hosting.fittingSize.height))
        hosting.frame = frame
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        host = hosting
        self.window = window
        defer { window.close() }
        settle()
        try body(self)
    }

    func settle() {
        for _ in 0..<3 {
            window.display()
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }

    var items: [RenderedItem] { nodes.map(\.item) }

    private var nodes: [(item: RenderedItem, node: NSObject)] {
        var collected: [(item: RenderedItem, node: NSObject)] = []
        Self.walk(host, into: &collected, depth: 0)
        return collected
    }

    func press(_ title: String) throws {
        let button = try #require(nodes.first { $0.item.role == "AXButton" && $0.item.label == title })
        #expect(button.node.accessibilityPerformPress())
        settle()
    }

    func isEnabled(_ title: String) throws -> Bool {
        let button = try #require(nodes.first { $0.item.role == "AXButton" && $0.item.label == title })
        return button.node.isAccessibilityEnabled()
    }

    private static func walk(_ element: Any, into items: inout [(item: RenderedItem, node: NSObject)], depth: Int) {
        guard depth < 40, let node = element as? NSObject else { return }
        let role = (node.value(forKey: "accessibilityRole") as? String) ?? ""
        let label = (node.value(forKey: "accessibilityLabel") as? String) ?? ""
        let value = node.value(forKey: "accessibilityValue").map { "\($0)" } ?? ""
        if !(node is NSView) { items.append((.init(role: role, label: label, value: value), node)) }
        for child in (node.value(forKey: "accessibilityChildren") as? [Any]) ?? [] {
            walk(child, into: &items, depth: depth + 1)
        }
    }
}

@MainActor
private struct RenderedButtons {
    let items: [RenderedItem]

    init<Content: View>(_ content: Content) throws {
        var captured: [RenderedItem] = []
        try Hosted(content) { captured = $0.items }
        items = captured
        #expect(!items.isEmpty, "accessibility tree was empty")
    }

    var buttons: [String] { items.filter { $0.role == "AXButton" }.map(\.label) }
    func count(containing text: String) -> Int { items.filter { $0.contains(text) }.count }
}

private extension NSObject {
    func accessibilityPerformPress() -> Bool {
        (self as? NSAccessibilityButton)?.accessibilityPerformPress()
            ?? (perform(NSSelectorFromString("accessibilityPerformPress")) != nil)
    }

    func isAccessibilityEnabled() -> Bool {
        (value(forKey: "accessibilityEnabled") as? Bool) ?? true
    }
}

// MARK: - Fixtures

private extension ClaudeKeychainAccessPresentationTests {
    static func dashboardConfiguration(metric: AIProviderDisplayMetric = .remaining) -> SystemMonitorConfiguration {
        var configuration = SystemMonitorConfiguration(aiOrder: [.claude, .codex, .cursor], dashboardVisibleModules: [.ai])
        configuration.ai[.claude]?.metric = metric
        return configuration
    }

    static func recentStatusLine() -> StatusLineQuotaRecord {
        StatusLineQuotaRecord(schemaVersion: 1, generation: UUID(uuidString: "00000000-0000-0000-0000-000000001102")!,
            fiveHour: .init(usedPercent: 25, resetsAt: now.addingTimeInterval(3_600), receivedAt: now.addingTimeInterval(-30)),
            sevenDay: .init(usedPercent: 35, resetsAt: now.addingTimeInterval(86_400), receivedAt: now.addingTimeInterval(-30)))
    }

    static func claude(reason: ClaudeQuotaFailureReason?, statusLine: StatusLineQuotaRecord?) throws -> ProviderSnapshot {
        let directAt = now.addingTimeInterval(-3_600)
        return ProviderSnapshot(
            provider: .claude,
            usage: nil,
            quota: QuotaSnapshot(windows: try [
                QuotaWindow(id: "claude.session", title: "Session", usedPercent: 68, resetsAt: directAt.addingTimeInterval(7_200)),
                QuotaWindow(id: "claude.weekly", title: "Weekly", usedPercent: 53, resetsAt: directAt.addingTimeInterval(86_400)),
                QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "Fable weekly", usedPercent: 42, resetsAt: directAt.addingTimeInterval(86_400)),
            ]),
            usageStatus: .fresh,
            quotaStatus: reason == nil ? .fresh : .error(message: "denied", lastSuccessfulAt: directAt),
            updatedAt: now.addingTimeInterval(-600),
            claudeQuotaFailureReason: reason,
            quotaLastSuccessfulAt: directAt,
            claudeStatusLineQuota: statusLine
        )
    }

    static func combined(_ claude: ProviderSnapshot) -> CombinedUsageSnapshot {
        CombinedUsageSnapshot(system: nil, providers: [
            claude,
            ProviderSnapshot(provider: .codex, usage: nil, quota: nil, usageStatus: .fresh, quotaStatus: .unavailable, updatedAt: now),
            ProviderSnapshot(provider: .cursor, usage: nil, quota: nil, usageStatus: .fresh, quotaStatus: .unavailable, updatedAt: now),
        ], capturedAt: now, systemAvailability: [:])
    }

    static func dashboardRow(_ claude: ProviderSnapshot) -> SystemDashboardPresentation.AIProvider {
        SystemDashboardPresentation(snapshot: combined(claude), configuration: dashboardConfiguration(), now: now)
            .ai.first { $0.provider == .claude }!
    }

    static func settingsRow(_ snapshot: ProviderSnapshot, actions: SettingsActions) -> some View {
        let name = "ClaudeKeychainAccess.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = QuotaNotificationPreferences(defaults: defaults)
        return SettingsView(
            configuration: ModuleConfiguration(defaults: defaults),
            actions: actions,
            notificationPreferences: preferences,
            notificationService: QuotaNotificationService(store: ProviderSnapshotStore(), preferences: preferences),
            openCursorSpending: {},
            openClaudeUsage: { false },
            claudeQuotaPresentation: SettingsClaudeQuotaPresentation(snapshot: combined(snapshot), now: now)
        ).claudeUsageRowContent
    }
}
