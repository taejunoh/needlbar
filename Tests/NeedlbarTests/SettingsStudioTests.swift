import AppKit
import Foundation
import SwiftUI
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore
import NeedlbarClaudeStatusLineSupport
import NeedlbarSettingsStudioReviewSupport

@Suite("SettingsStudio", .serialized)
@MainActor
struct SettingsStudioTests {
    @Test func claudeSettingsUsageActionKeepsFeedbackLocalAndClearsAfterSuccess() {
        var openedURL: URL?
        var openerCalls = 0
        var state = SettingsClaudeUsageRowState()
        let settingsActions = SettingsActions()

        state.openUsage {
            openerCalls += 1
            return ClaudeUsageAction.open { url in
                openedURL = url
                return openerCalls == 2
            }
        }
        #expect(state.showsFailure)
        #expect(openedURL?.absoluteString == "https://claude.ai/settings/usage")
        #expect(settingsActions.loginState(for: .claude) == .idle)

        state.openUsage {
            openerCalls += 1
            return ClaudeUsageAction.open { url in
                openedURL = url
                return openerCalls == 2
            }
        }
        #expect(!state.showsFailure)
        #expect(openerCalls == 2)
        #expect(settingsActions.loginState(for: .claude) == .idle)
    }

    @Test func claudeUsageActionHasOnlyTheApprovedDestination() {
        var openedURL: URL?

        let opened = ClaudeUsageAction.open { url in
            openedURL = url
            return false
        }

        #expect(!opened)
        #expect(openedURL?.absoluteString == "https://claude.ai/settings/usage")
    }

    @Test func settingsControllerSharesClaudeFallbackStateAndClearsItAfterSuccess() throws {
        let name = "SettingsStudio.claude-runtime.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = QuotaNotificationPreferences(defaults: defaults)
        let controller = SettingsWindowController(
            configuration: ModuleConfiguration(defaults: defaults),
            actions: SettingsActions(),
            notificationPreferences: preferences,
            notificationService: QuotaNotificationService(store: ProviderSnapshotStore(), preferences: preferences),
            openCursorSpending: {}
        )
        let lastSuccess = Date(timeIntervalSince1970: 10_000)
        let failedAttempt = Date(timeIntervalSince1970: 20_000)
        let quota = QuotaSnapshot(windows: [
            try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 68, resetsAt: nil),
        ])

        controller.update(snapshot: Self.claudeQuotaSnapshot(
            quota: quota,
            quotaStatus: .error(message: "untrusted", lastSuccessfulAt: lastSuccess),
            reason: .couldNotUpdateQuota,
            quotaLastSuccessfulAt: lastSuccess,
            updatedAt: failedAttempt
        ), configuration: .init())

        #expect(controller.claudeQuotaState.quotaIsLastKnown)
        #expect(controller.claudeQuotaState.headlineQuotaRemaining == nil)
        #expect(controller.claudeQuotaState.lastKnownQuotaRemaining == "32%")
        #expect(controller.claudeQuotaState.quotaFailureReasonText == "Could not update quota")
        #expect(controller.claudeQuotaState.quotaLastCheckedText != nil)
        #expect(controller.claudeQuotaState.quotaLastCheckedText != MetricFormatter.reset(failedAttempt))

        controller.update(snapshot: Self.claudeQuotaSnapshot(
            quota: quota,
            quotaStatus: .fresh,
            reason: nil,
            quotaLastSuccessfulAt: lastSuccess,
            updatedAt: failedAttempt.addingTimeInterval(1)
        ), configuration: .init())

        #expect(!controller.claudeQuotaState.quotaIsLastKnown)
        #expect(!controller.claudeQuotaState.quotaUnavailable)
        #expect(controller.claudeQuotaState.quotaFailureReasonText == nil)
        #expect(controller.claudeQuotaState.quotaLastCheckedText
            == DateFormatter.localizedString(from: lastSuccess, dateStyle: .medium, timeStyle: .short))
    }

    @Test func settingsControllerUpdatesCPUInformationWithoutFollowingVisibilityPreferences() throws {
        let name = "SettingsStudio.cpu-information.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let configuration = ModuleConfiguration(defaults: defaults)
        var monitor = configuration.systemMonitor
        monitor.menuBarVisibleModules.remove(.cpu)
        monitor.dashboardVisibleModules.remove(.cpu)
        configuration.setSystemMonitor(monitor)
        let preferences = QuotaNotificationPreferences(defaults: defaults)
        let controller = SettingsWindowController(
            configuration: configuration,
            actions: SettingsActions(),
            notificationPreferences: preferences,
            notificationService: QuotaNotificationService(store: ProviderSnapshotStore(), preferences: preferences),
            openCursorSpending: {}
        )

        controller.update(snapshot: SettingsStudioReviewFixtures.cpuSnapshot(), configuration: configuration.systemMonitor)

        #expect(!configuration.systemMonitor.menuBarVisibleModules.contains(.cpu))
        #expect(!configuration.systemMonitor.dashboardVisibleModules.contains(.cpu))
        #expect(controller.cpuInformationState.hardware?.name == "Apple M5 Pro")
        #expect(controller.cpuInformationState.totalUsagePercent == 25)
        #expect(controller.cpuInformationState.idlePercent == 75)
    }

    @Test func settingsControllerUpdatesRAMInformationWithBothVisibilityPreferencesOff() throws {
        let name = "SettingsStudio.ram-information.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let configuration = ModuleConfiguration(defaults: defaults)
        var monitor = configuration.systemMonitor
        monitor.menuBarVisibleModules.remove(.memory)
        monitor.dashboardVisibleModules.remove(.memory)
        configuration.setSystemMonitor(monitor)
        let preferences = QuotaNotificationPreferences(defaults: defaults)
        let controller = SettingsWindowController(
            configuration: configuration, actions: SettingsActions(),
            notificationPreferences: preferences,
            notificationService: QuotaNotificationService(store: ProviderSnapshotStore(), preferences: preferences),
            openCursorSpending: {}
        )
        controller.update(snapshot: SettingsStudioReviewFixtures.cpuSnapshot(), configuration: monitor)
        #expect(controller.ramInformationState.totalBytes == 51_539_607_552)
        #expect(controller.ramInformationState.usedPercent == 75)
        #expect(controller.ramInformationState.pressure == "normal")
        controller.update(snapshot: SettingsRAMInformationTests.snapshot(availability: .unavailable(code: "memoryUnavailable")), configuration: monitor)
        #expect(controller.ramInformationState.usedBytes == nil)
        #expect(controller.ramInformationState.successfulAt == nil)
        #expect(controller.ramInformationState.totalBytes == 51_539_607_552)
    }

    @Test func settingsControllerUpdatesDiskInformationWithBothVisibilityPreferencesOff() throws {
        let name = "SettingsStudio.disk-information.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let configuration = ModuleConfiguration(defaults: defaults)
        var monitor = configuration.systemMonitor
        monitor.menuBarVisibleModules.remove(.disk)
        monitor.dashboardVisibleModules.remove(.disk)
        configuration.setSystemMonitor(monitor)
        let preferences = QuotaNotificationPreferences(defaults: defaults)
        let controller = SettingsWindowController(configuration: configuration, actions: SettingsActions(),
            notificationPreferences: preferences,
            notificationService: QuotaNotificationService(store: ProviderSnapshotStore(), preferences: preferences), openCursorSpending: {})
        controller.update(snapshot: SettingsStudioReviewFixtures.cpuSnapshot(), configuration: monitor)
        #expect(!configuration.systemMonitor.menuBarVisibleModules.contains(.disk))
        #expect(!configuration.systemMonitor.dashboardVisibleModules.contains(.disk))
        #expect(controller.diskInformationState.name == "Macintosh HD")
        #expect(controller.diskInformationState.totalBytes == 1_099_511_627_776)
        #expect(controller.diskInformationState.usedPercent == 75)
        controller.update(snapshot: SettingsDiskInformationTests.snapshot(availability: .unavailable(code: "diskUnavailable")), configuration: monitor)
        #expect(controller.diskInformationState.usedBytes == nil)
        #expect(controller.diskInformationState.readBytesPerSecond == nil)
        #expect(controller.diskInformationState.successfulAt == nil)
        #expect(controller.diskInformationState.totalBytes == 1_099_511_627_776)
        controller.update(snapshot: SettingsDiskInformationTests.snapshot(hasDisk: false), configuration: monitor)
        #expect(controller.diskInformationState.name == nil)
        #expect(controller.diskInformationState.totalBytes == nil)
    }

    @Test func claudeStatusLineDisconnectInvokesImmediateClearCallback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Needlbar-settings-disconnect-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("claude")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: config.path)
        let settings = config.appendingPathComponent("settings.json")
        try Data(#"{"statusLine":{"type":"command","command":"printf original"}}"#.utf8).write(to: settings)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settings.path)
        let helper = root.appendingPathComponent("NeedlbarClaudeStatusLine")
        try Data("synthetic-helper".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let privateStore = try StatusLinePrivateStore(rootURL: root.appendingPathComponent("private"))
        let manager = ClaudeStatusLineConnectionManager(configRootURL: config, store: privateStore,
                                                        helperURL: helper, environment: [:])
        let name = "SettingsStudio.disconnect.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = QuotaNotificationPreferences(defaults: defaults)
        var clearCalls = 0
        let view = SettingsView(configuration: ModuleConfiguration(defaults: defaults), actions: SettingsActions(),
            notificationPreferences: preferences,
            notificationService: QuotaNotificationService(store: ProviderSnapshotStore(), preferences: preferences),
            claudeStatusLineManager: manager,
            onClaudeStatusLineDisconnected: { clearCalls += 1 })

        view.setClaudeStatusLineEnabled(true)
        #expect(manager.recover() == .waitingForData)
        #expect(clearCalls == 0)
        view.setClaudeStatusLineEnabled(false)
        #expect(clearCalls == 1)
        #expect(manager.recover() == .disconnected)
    }

    @Test func failedRestorationStillClearsFencedStatusLineWithoutOverwritingUserChange() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Needlbar-settings-partial-disconnect-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("claude")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: config.path)
        let settings = config.appendingPathComponent("settings.json")
        try Data(#"{"statusLine":{"type":"command","command":"printf original"}}"#.utf8).write(to: settings)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settings.path)
        let helper = root.appendingPathComponent("NeedlbarClaudeStatusLine")
        try Data("synthetic-helper".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let privateStore = try StatusLinePrivateStore(rootURL: root.appendingPathComponent("private"))
        let userChange = Data(#"{"statusLine":{"type":"command","command":"printf user-change"}}"#.utf8)
        var replaces = 0
        let manager = ClaudeStatusLineConnectionManager(
            configRootURL: config, store: privateStore, helperURL: helper, environment: [:],
            beforeAtomicReplace: {
                replaces += 1
                if replaces == 2 { try? userChange.write(to: settings) }
            }
        )
        let name = "SettingsStudio.partial-disconnect.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = QuotaNotificationPreferences(defaults: defaults)
        var clearCalls = 0
        let view = SettingsView(configuration: ModuleConfiguration(defaults: defaults), actions: SettingsActions(),
            notificationPreferences: preferences,
            notificationService: QuotaNotificationService(store: ProviderSnapshotStore(), preferences: preferences),
            claudeStatusLineManager: manager,
            onClaudeStatusLineDisconnected: { clearCalls += 1 })

        view.setClaudeStatusLineEnabled(true)
        #expect(manager.recover() == .waitingForData)
        view.setClaudeStatusLineEnabled(false)
        #expect(try privateStore.activeGeneration() == nil)
        #expect(try Data(contentsOf: settings) == userChange)
        #expect(clearCalls == 1)
    }

    @Test func apiBillingSettingsToggleDoesNotMakeProviderVisible() throws {
        let name = "SettingsStudio.api.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ModuleConfiguration(defaults: defaults)
        var value = store.systemMonitor
        value.ai[.claude] = AIProviderDisplayPreference(isVisible: false, metric: .usage, dashboardVisible: false)
        store.setSystemMonitor(value)
        let model = SystemMonitorSettingsModel(configuration: store)
        model.setAPIBillingLinkVisible(true, for: .claude)
        #expect(store.systemMonitor.ai[.claude]?.apiBillingLinkVisible == true)
        #expect(!model.isVisible(.claude, surface: .menuBar))
        #expect(!model.isVisible(.claude, surface: .dashboard))
        #expect(store.systemMonitor.ai[.claude]?.metric == .usage)
        model.setAPIBillingLinkVisible(false, for: .claude)
        #expect(store.systemMonitor.ai[.claude]?.apiBillingLinkVisible == false)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Needlbar/Settings/SettingsView.swift"), encoding: .utf8)
        #expect(source.contains("SettingsStudioSection(title: \"API Billing\")"))
        #expect(source.contains("Show API billing link"))
        #expect(!source.contains("ProviderAPIBillingActionRouter.open"))
    }

    @Test func compactMenuResetPreservesDashboardAndProviderChoices() throws {
        let name = "SettingsStudio.menu-reset.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ModuleConfiguration(defaults: defaults)
        var initial = SystemMonitorConfiguration(visibleModules: [.disk], dashboardVisibleModules: [.network])
        initial.ai[.claude]?.dashboardVisible = false
        initial.ai[.codex]?.metric = .usage
        store.setSystemMonitor(initial)
        SystemMonitorSettingsModel(configuration: store).useCompactDefaults(surface: .menuBar)
        let saved = store.systemMonitor
        #expect(saved.menuBarVisibleModules == [.cpu, .memory, .ai])
        #expect(saved.dashboardVisibleModules == [.network])
        #expect(saved.ai == initial.ai)
    }

    @Test func settingsSectionUsesAllocatedDetailWidth() throws {
        let measurement = SettingsStudioWidthMeasurement()
        let content = SettingsStudioMeasuringLayout(measurement: measurement) {
            SettingsStudioSection(title: "Show in dashboard") {
                SettingsStudioToggle(title: "CPU", value: .constant(true))
            }
        }.frame(width: 500, height: 160, alignment: .topLeading)
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 160)
        host.layoutSubtreeIfNeeded()
        _ = host.fittingSize
        let width = try #require(measurement.width)
        #expect(width >= 499)
    }

    @Test func hostingLayoutDoesNotOverwriteWindowMinimum() async throws {
        let name = "SettingsStudio.window-minimum.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = QuotaNotificationPreferences(defaults: defaults)
        let controller = SettingsWindowController(configuration: ModuleConfiguration(defaults: defaults),
            actions: SettingsActions(), notificationPreferences: preferences,
            notificationService: QuotaNotificationService(store: ProviderSnapshotStore(), preferences: preferences),
            openCursorSpending: {})
        let window = try #require(controller.window)
        window.contentMinSize = NSSize(width: 760, height: 560)
        window.setContentSize(NSSize(width: 760, height: 560))
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        #expect(window.contentMinSize == NSSize(width: 760, height: 560))
    }

    @Test func settingsWindowFitsSmallAndOffsetScreens() {
        let screen = NSRect(x: -1440, y: 50, width: 800, height: 600)
        let desired = NSRect(x: 1000, y: -1000, width: 960, height: 720)
        let frame = SettingsWindowController.fittedFrame(desired, in: screen)
        #expect(screen.contains(frame))
        #expect(frame == screen)
        let inside = NSRect(x: -1400, y: 100, width: 500, height: 400)
        #expect(SettingsWindowController.fittedFrame(inside, in: screen) == inside)
    }

    @Test func previewUsesProductionRendererAndHasNoFixtureValues() {
        let model = SettingsPreviewModel()
        var configuration = SystemMonitorConfiguration()
        configuration.menuBarVisibleModules = [.cpu]
        model.update(snapshot: Self.emptySnapshot, configuration: configuration)
        #expect(model.result == MenuBarDashboardRenderer.render(snapshot: Self.emptySnapshot,
            configuration: configuration, availableWidth: 240))
        #expect(model.result.tooltip == "CPU —")
        #expect(model.result.configuredModuleIDs == [.cpu])
    }

    @Test func tabsCannotRouteAlertsIntoVisibility() {
        #expect(SettingsStudioTab.alerts.surface == nil)
        #expect(SettingsStudioTab.menuBar.surface == .menuBar)
        #expect(SettingsStudioTab.dashboard.surface == .dashboard)
        #expect(SettingsStudioPage.layout.tabs == [.menuBar, .dashboard])
        #expect(SettingsStudioPage.notifications.tabs.isEmpty)
        #expect(SettingsStudioPage.data.tabs.isEmpty)
        #expect(SettingsStudioPage.module(.cpu).tabs == [.menuBar, .dashboard, .alerts])
        #expect(SettingsStudioPage.provider(.claude).tabs == [.menuBar, .dashboard, .alerts])
    }

    static var emptySnapshot: CombinedUsageSnapshot {
        .init(system: nil, providers: [], capturedAt: .distantPast, systemAvailability: [:])
    }

    static func claudeQuotaSnapshot(
        quota: QuotaSnapshot?,
        quotaStatus: DataStatus,
        reason: ClaudeQuotaFailureReason?,
        quotaLastSuccessfulAt: Date?,
        updatedAt: Date
    ) -> CombinedUsageSnapshot {
        .init(
            system: nil,
            providers: [ProviderSnapshot(
                provider: .claude,
                usage: nil,
                quota: quota,
                usageStatus: .unavailable,
                quotaStatus: quotaStatus,
                updatedAt: updatedAt,
                claudeQuotaFailureReason: reason,
                quotaLastSuccessfulAt: quotaLastSuccessfulAt
            )],
            capturedAt: updatedAt,
            systemAvailability: [:]
        )
    }

    @Test func editorDoesNotCrossSurfaces() {
        let name = "SettingsStudio.editor.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ModuleConfiguration(defaults: defaults)
        var initial = SystemMonitorConfiguration(visibleModules: Set(MonitorModuleID.allCases))
        initial.publicIPEnabled = true
        initial.localIPEnabled = true
        initial.order = [.ai, .network, .battery, .disk, .memory, .cpu]
        initial.aiOrder = [.cursor, .codex, .claude]
        store.setSystemMonitor(initial)
        let model = SystemMonitorSettingsModel(configuration: store)
        model.setVisible(.cpu, false, surface: .menuBar)
        model.setAIProvider(.claude, visible: false, surface: .dashboard)
        model.setAIProvider(.claude, metric: .cost)
        model.useCompactDefaults(surface: .dashboard)
        let value = store.systemMonitor
        #expect(value.menuBarVisibleModules == [.memory, .disk, .network, .battery, .ai])
        #expect(value.dashboardVisibleModules == [.cpu, .memory, .ai])
        #expect(value.ai[.claude]?.menuBarVisible == true)
        #expect(value.ai[.claude]?.dashboardVisible == false)
        #expect(value.ai[.claude]?.metric == .cost)
        #expect(value.publicIPEnabled && value.localIPEnabled)
        #expect(value.order == [.ai, .network, .battery, .disk, .memory, .cpu])
        #expect(value.aiOrder == [.cursor, .codex, .claude])
        #expect(model.isVisible(.cpu, surface: .dashboard))
        #expect(!model.isVisible(.cpu, surface: .menuBar))
        #expect(model.isVisible(.claude, surface: .menuBar))
        #expect(!model.isVisible(.claude, surface: .dashboard))
    }

    @Test func consumersUseDifferentSurfaces() {
        var configuration = SystemMonitorConfiguration()
        configuration.menuBarVisibleModules = [.cpu, .ai]
        configuration.dashboardVisibleModules = [.memory, .ai]
        configuration.ai[.claude]?.menuBarVisible = false
        configuration.ai[.claude]?.dashboardVisible = true
        configuration.ai[.codex]?.dashboardVisible = false
        configuration.ai[.cursor]?.dashboardVisible = false
        let menu = MenuBarDashboardRenderer.render(snapshot: Self.emptySnapshot,
            configuration: configuration, availableWidth: 240)
        let dashboard = SystemDashboardPresentation(snapshot: Self.emptySnapshot, configuration: configuration)
        #expect(menu.configuredModuleIDs == [.cpu, .ai])
        #expect(!menu.tooltip.contains("Claude"))
        #expect(dashboard.moduleIDs == [.memory, .ai])
        #expect(dashboard.ai.map(\.provider) == [.claude])
        configuration.menuBarVisibleModules = []
        #expect(MenuBarDashboardRenderer.render(snapshot: Self.emptySnapshot,
            configuration: configuration, availableWidth: 240).usesIconFallback)
        #expect(SystemDashboardPresentation(snapshot: Self.emptySnapshot,
            configuration: configuration).moduleIDs == [.memory, .ai])
    }
}

private struct SettingsStudioMeasuringLayout: Layout {
    let measurement: SettingsStudioWidthMeasurement
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let view = subviews.first else { return .zero }
        let size = view.sizeThatFits(proposal)
        if proposal.width == 500 { measurement.record(size.width) }
        return size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: proposal)
    }
}

private final class SettingsStudioWidthMeasurement: @unchecked Sendable {
    private let lock = NSLock()
    private var measuredWidth: CGFloat?
    var width: CGFloat? { lock.withLock { measuredWidth } }
    func record(_ width: CGFloat) { lock.withLock { measuredWidth = width } }
}
