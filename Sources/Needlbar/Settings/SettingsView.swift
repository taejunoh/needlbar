import CNeedlbar
import Darwin
import Foundation
import NeedlbarCore
import SwiftUI

public struct SettingsView: View {
    private let configuration: ModuleConfiguration
    @State private var cursorSessionToken = ""
    @State private var connectionStatus: String?

    public init(configuration: ModuleConfiguration) {
        self.configuration = configuration
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
                Text("Claude and Codex use their provider-native app or CLI sign-in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("Cursor session token", text: $cursorSessionToken)
                    .onSubmit(connectCursor)
                HStack {
                    Button("Connect", action: connectCursor)
                    Button("Reconnect", action: connectCursor)
                    Button("Disconnect", action: disconnectCursor)
                }
                if let connectionStatus {
                    Text(connectionStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420)
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

    private func connectCursor() {
        let token = cursorSessionToken
        let connected = CursorSessionBridge.importSession(token)
        cursorSessionToken = ""
        connectionStatus = connected ? "Cursor connected." : "Cursor could not be connected."
    }

    private func disconnectCursor() {
        connectionStatus = CursorSessionBridge.clearSession()
            ? "Cursor disconnected."
            : "Cursor could not be disconnected."
    }
}

enum CursorSessionBridge {
    static func importSession(_ token: String) -> Bool {
        token.withCString { token in
            decodeConnected(needlbar_cursor_import_session_json(token), key: "connected")
        }
    }

    static func clearSession() -> Bool {
        decodeConnected(needlbar_cursor_clear_session_json(), key: "disconnected")
    }

    private static func decodeConnected(_ pointer: UnsafePointer<CChar>?, key: String) -> Bool {
        guard let pointer else { return false }
        defer { needlbar_free_string(pointer) }
        let data = Data(bytes: pointer, count: Int(strlen(pointer)))
        let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (response?["data"] as? [String: Any])?[key] as? Bool == true
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
