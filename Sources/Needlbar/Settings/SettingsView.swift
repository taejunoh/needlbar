import Combine
import Foundation
import NeedlbarCore
import SwiftUI

@MainActor
public struct SettingsView: View {
    private let configuration: ModuleConfiguration
    private let openCursorSpending: () -> Void
    @StateObject private var systemMonitorModel: SystemMonitorSettingsModel
    @ObservedObject private var actions: SettingsActions
    @ObservedObject private var notificationPreferences: QuotaNotificationPreferences
    private let notificationService: QuotaNotificationService
    @State private var selectedPage: SettingsStudioPage = .layout
    @State private var selectedTab: SettingsStudioTab = .menuBar
    @ObservedObject private var preview: SettingsPreviewModel

    public init(
        configuration: ModuleConfiguration,
        actions: SettingsActions,
        notificationPreferences: QuotaNotificationPreferences,
        notificationService: QuotaNotificationService,
        openCursorSpending: @escaping () -> Void = { _ = CursorSpendingAction.open() },
        preview: SettingsPreviewModel? = nil
    ) {
        self.configuration = configuration
        self.openCursorSpending = openCursorSpending
        _preview = ObservedObject(wrappedValue: preview ?? SettingsPreviewModel())
        _systemMonitorModel = StateObject(wrappedValue: SystemMonitorSettingsModel(configuration: configuration))
        _actions = ObservedObject(wrappedValue: actions)
        _notificationPreferences = ObservedObject(wrappedValue: notificationPreferences)
        self.notificationService = notificationService
    }

    public init(
        configuration: ModuleConfiguration,
        loginCoordinator: ProviderLoginCoordinator,
        snapshotExportController: SnapshotExportController,
        notificationPreferences: QuotaNotificationPreferences,
        notificationService: QuotaNotificationService,
        openCursorSpending: @escaping () -> Void = { _ = CursorSpendingAction.open() },
        preview: SettingsPreviewModel? = nil
    ) {
        self.init(
            configuration: configuration,
            actions: SettingsActions(
                loginCoordinator: loginCoordinator,
                snapshotExportController: snapshotExportController
            ),
            notificationPreferences: notificationPreferences,
            notificationService: notificationService,
            openCursorSpending: openCursorSpending,
            preview: preview
        )
    }

    public var body: some View {
        HStack(spacing: 0) {
            SettingsStudioSidebar(selection: $selectedPage)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pageEyebrow).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(selectedPage.title).font(.system(size: 24, weight: .bold))
                        Text(pageDescription).font(.callout).foregroundStyle(.secondary)
                    }
                    if !selectedPage.tabs.isEmpty {
                        Picker("Settings surface", selection: $selectedTab) {
                            ForEach(selectedPage.tabs) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                    }
                    if selectedPage == .layout { SettingsPreviewView(model: preview) }
                    detailPane
                    Spacer(minLength: 0)
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: selectedPage) { _, page in
            if !page.tabs.contains(selectedTab) { selectedTab = page.tabs.first ?? .menuBar }
        }
        .onReceive(NotificationCenter.default.publisher(for: ModuleConfiguration.systemMonitorDidChangeNotification)
            .receive(on: RunLoop.main)) { note in
            guard let changed = note.object as? ModuleConfiguration, changed === configuration else { return }
            systemMonitorModel.refresh()
        }
    }

    @ViewBuilder private var detailPane: some View {
        switch selectedPage {
        case .notifications:
            SettingsStudioSection(title: "Quota reminders") {
                SettingsStudioToggle(title: "Quota threshold alerts", value: Binding(
                    get: { notificationPreferences.isEnabled }, set: { setQuotaAlertsEnabled($0) }))
            }
            Text(notificationStatusCopy).foregroundStyle(.secondary)
        case .data:
            SettingsStudioSection(title: "Snapshot export") {
                Button("Export snapshot…", action: exportSnapshot)
                    .disabled(isExportButtonDisabled).frame(minHeight: 54)
                if actions.exportState == .exported { Text("Exported") }
                if actions.exportState == .failed { Text("Could not export snapshot.") }
            }
            Text("IP addresses and credentials are not included in snapshot exports.").foregroundStyle(.secondary)
        case .layout, .module, .provider:
            if let surface = selectedTab.surface {
                SettingsStudioConfigurationPane(model: systemMonitorModel, page: selectedPage, surface: surface)
                if case let .provider(provider) = selectedPage { connectionPane(provider) }
            } else if case .module = selectedPage {
                Text("System threshold alerts are not available yet.").foregroundStyle(.secondary)
            } else if case .provider = selectedPage {
                Text("Quota reminders use the global Notifications setting.").foregroundStyle(.secondary)
                Button("Open Notifications") { selectedPage = .notifications }
            }
        }
    }

    @ViewBuilder private func connectionPane(_ provider: ProviderID) -> some View {
        SettingsStudioSection(title: "Connection") {
            switch provider {
            case .claude: providerLoginRow(provider: .claude, title: "Claude", actionTitle: "Sign in with Claude")
            case .codex: providerLoginRow(provider: .codex, title: "Codex", actionTitle: "Sign in with ChatGPT")
            case .cursor:
                HStack(alignment: .top, spacing: 8) {
                    ProviderBrandIcon(provider: .cursor, accessibility: .decorative)
                    Text("Usage comes from an existing local cache. Quota is available in Cursor Spending.")
                    Spacer()
                    Button("Open Cursor Spending", action: openCursorSpending)
                }.padding(.vertical, 12)
            }
        }
    }

    private var pageEyebrow: String {
        switch selectedPage {
        case .layout: "LAYOUT"
        case .module: "SYSTEM"
        case .provider: "AI PROVIDERS"
        case .notifications, .data: "PREFERENCES"
        }
    }

    private var pageDescription: String {
        switch selectedPage {
        case .layout: "Choose what appears on each surface and arrange the shared display order."
        case .module: "Control visibility without interrupting background collection."
        case .provider: "Choose where this provider appears and manage its existing connection."
        case .notifications: "Manage reminders for fresh provider quota readings."
        case .data: "Export a local snapshot without credentials or IP addresses."
        }
    }

    func exportSnapshot() {
        actions.exportSnapshot()
    }

    var isExportButtonDisabled: Bool {
        actions.isExporting
    }

    func setQuotaAlertsEnabled(_ enabled: Bool) {
        Task { await notificationService.setEnabledFromSettings(enabled) }
    }

    var notificationStatusCopy: String {
        switch notificationPreferences.state {
        case .off: "Off. Enable to request permission."
        case .enabled: "Alerts are enabled for fresh Claude and Codex quota readings."
        case .unavailable: "Notifications unavailable in macOS settings."
        }
    }

    @ViewBuilder
    private func providerLoginRow(provider: ProviderID, title: String, actionTitle: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ProviderBrandIcon(provider: provider, accessibility: .decorative)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(loginStatusCopy(for: provider))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(actionTitle) {
                actions.connect(provider)
            }
            .disabled(isLoginInFlight(for: provider))
        }
    }

    private func isLoginInFlight(for provider: ProviderID) -> Bool {
        switch actions.loginState(for: provider) {
        case .launching, .awaitingBrowser, .refreshingQuota:
            true
        case .idle, .connected, .failed:
            false
        }
    }

    private func loginStatusCopy(for provider: ProviderID) -> String {
        switch actions.loginState(for: provider) {
        case .idle:
            "Sign in opens the provider's browser flow."
        case .launching:
            "Starting sign-in…"
        case .awaitingBrowser:
            "Continue sign-in in your browser."
        case .refreshingQuota:
            provider == .claude
                ? "macOS may request access to Claude Code credentials."
                : "Verifying quota…"
        case .connected:
            "Connected."
        case let .failed(failure):
            switch failure {
            case .cliNotInstalled: "CLI not found."
            case .launchFailed: "Login could not start."
            case .cancelled: "Login cancelled."
            case .timedOut: "Login timed out."
            case .providerRejected, .unsupportedProvider: "Login incomplete."
            case .verificationFailed: "Sign-in completed but quota could not be verified."
            }
        }
    }

}

private extension MenuModuleID {
    var title: String {
        switch self {
        case .overview: "Overview"
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }
}

private extension MenuBarMetric {
    var title: String {
        switch self {
        case .quotaRemaining: "Quota remaining"
        case .tokensToday: "Tokens today"
        case .costToday: "Cost today"
        }
    }
}
