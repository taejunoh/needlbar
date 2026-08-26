import NeedlbarCore
import SwiftUI

public struct SettingsView: View {
    private let configuration: ModuleConfiguration
    @ObservedObject private var loginCoordinator: ProviderLoginCoordinator

    public init(configuration: ModuleConfiguration, loginCoordinator: ProviderLoginCoordinator) {
        self.configuration = configuration
        _loginCoordinator = ObservedObject(wrappedValue: loginCoordinator)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cursor")
                    Text("Usage is read from an existing local cache. Quota is available in Cursor Spending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420)
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
                _ = loginCoordinator.connect(provider)
            }
            .disabled(isLoginInFlight(for: provider))
        }
    }

    private func isLoginInFlight(for provider: ProviderID) -> Bool {
        switch loginCoordinator.state(for: provider) {
        case .launching, .awaitingBrowser, .refreshingQuota:
            true
        case .idle, .connected, .failed:
            false
        }
    }

    private func loginStatusCopy(for provider: ProviderID) -> String {
        switch loginCoordinator.state(for: provider) {
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
