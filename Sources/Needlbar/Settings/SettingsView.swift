import NeedlbarCore
import SwiftUI

public struct SettingsView: View {
    private let configuration: ModuleConfiguration
    private let openCursorSpending: () -> Void
    @ObservedObject private var actions: SettingsActions
    @ObservedObject private var notificationPreferences: QuotaNotificationPreferences
    private let notificationService: QuotaNotificationService

    public init(
        configuration: ModuleConfiguration,
        actions: SettingsActions,
        notificationPreferences: QuotaNotificationPreferences,
        notificationService: QuotaNotificationService,
        openCursorSpending: @escaping () -> Void = { _ = CursorSpendingAction.open() }
    ) {
        self.configuration = configuration
        self.openCursorSpending = openCursorSpending
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
        openCursorSpending: @escaping () -> Void = { _ = CursorSpendingAction.open() }
    ) {
        self.init(
            configuration: configuration,
            actions: SettingsActions(
                loginCoordinator: loginCoordinator,
                snapshotExportController: snapshotExportController
            ),
            notificationPreferences: notificationPreferences,
            notificationService: notificationService,
            openCursorSpending: openCursorSpending
        )
    }

    public var body: some View {
        Form {
            Section("Menu Bar Modules") {
                ForEach(MenuModuleID.allCases, id: \.rawValue) { module in
                    Toggle(module.title, isOn: enabledBinding(for: module))
                }
            }

            Section("Metric per enabled module") {
                ForEach(MenuModuleID.allCases, id: \.rawValue) { module in
                    Picker(module.title, selection: metricBinding(for: module)) {
                        ForEach(MenuBarMetric.allCases, id: \.rawValue) { metric in
                            Text(metric.title).tag(metric)
                        }
                    }
                }
            }

            Section("Connections") {
                providerLoginRow(provider: .claude, title: "Claude", actionTitle: "Sign in with Claude")
                providerLoginRow(provider: .codex, title: "Codex", actionTitle: "Sign in with ChatGPT")
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cursor")
                        Text("Usage is read from an existing local cache. Quota is available in Cursor Spending.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Cursor Spending", action: openCursorSpending)
                }
            }

            Section("Data Export") {
                Button("Export snapshot…", action: exportSnapshot)
                    .disabled(isExportButtonDisabled)
                if actions.exportState == .exported {
                    Text("Exported")
                }
                if actions.exportState == .failed {
                    Text("Could not export snapshot.")
                }
            }

            Section("Notifications") {
                Toggle("Quota threshold alerts", isOn: Binding(
                    get: { notificationPreferences.isEnabled },
                    set: { setQuotaAlertsEnabled($0) }
                ))
                Text(notificationStatusCopy)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420)
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
        HStack {
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

    private func enabledBinding(for module: MenuModuleID) -> Binding<Bool> {
        Binding(
            get: { configuration.settings(for: module).isEnabled },
            set: { isEnabled in
                var settings = configuration.settings(for: module)
                settings.isEnabled = isEnabled
                configuration.set(settings, for: module)
            }
        )
    }

    private func metricBinding(for module: MenuModuleID) -> Binding<MenuBarMetric> {
        Binding(
            get: { configuration.settings(for: module).metric },
            set: { metric in
                var settings = configuration.settings(for: module)
                settings.metric = metric
                configuration.set(settings, for: module)
            }
        )
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
