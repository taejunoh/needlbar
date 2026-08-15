import CNeedlbar
import Darwin
import Foundation
import NeedlbarCore
import SwiftUI

public struct SettingsView: View {
    private let configuration: ModuleConfiguration
    private let cursorConnection = CursorSessionConnectionController()
    @State private var cursorSessionToken = ""
    @State private var connectionStatus: String?
    @State private var isCursorConnectionOperationInFlight = false

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
                    .disabled(isCursorConnectionOperationInFlight)
                HStack {
                    Button("Connect", action: connectCursor)
                        .disabled(isCursorConnectionOperationInFlight)
                    Button("Reconnect", action: connectCursor)
                        .disabled(isCursorConnectionOperationInFlight)
                    Button("Disconnect", action: disconnectCursor)
                        .disabled(isCursorConnectionOperationInFlight)
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
        let accepted = cursorConnection.connect(
            cursorSessionToken,
            clearInput: { cursorSessionToken = "" },
            operationStateChanged: { isCursorConnectionOperationInFlight = $0 },
            completion: { connected in
                connectionStatus = connected ? "Cursor connected." : "Cursor could not be connected."
            }
        )
        if accepted {
            connectionStatus = "Connecting Cursor…"
        }
    }

    private func disconnectCursor() {
        let accepted = cursorConnection.disconnect(
            operationStateChanged: { isCursorConnectionOperationInFlight = $0 },
            completion: { disconnected in
                connectionStatus = disconnected ? "Cursor disconnected." : "Cursor could not be disconnected."
            }
        )
        if accepted {
            connectionStatus = "Disconnecting Cursor…"
        }
    }
}

@MainActor
final class CursorSessionConnectionController {
    typealias Importer = @Sendable (String) async -> Bool
    typealias Clearer = @Sendable () async -> Bool

    private let importer: Importer
    private let clearer: Clearer
    private var nextOperationID: UInt64 = 0
    private var activeOperationID: UInt64?

    private(set) var isOperationInFlight = false

    init(
        importer: @escaping Importer = CursorSessionBridge.importSessionOffMainActor,
        clearer: @escaping Clearer = CursorSessionBridge.clearSessionOffMainActor
    ) {
        self.importer = importer
        self.clearer = clearer
    }

    func connect(
        _ token: String,
        clearInput: @escaping @MainActor () -> Void,
        operationStateChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        completion: @escaping @MainActor (Bool) -> Void
    ) -> Bool {
        clearInput()
        guard let operationID = beginOperation(operationStateChanged: operationStateChanged) else { return false }
        let importer = importer
        Task { [weak self] in
            let connected = await importer(token)
            self?.finishOperation(
                operationID,
                result: connected,
                operationStateChanged: operationStateChanged,
                completion: completion
            )
        }
        return true
    }

    func disconnect(
        operationStateChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        completion: @escaping @MainActor (Bool) -> Void
    ) -> Bool {
        guard let operationID = beginOperation(operationStateChanged: operationStateChanged) else { return false }
        let clearer = clearer
        Task { [weak self] in
            let disconnected = await clearer()
            self?.finishOperation(
                operationID,
                result: disconnected,
                operationStateChanged: operationStateChanged,
                completion: completion
            )
        }
        return true
    }

    private func beginOperation(
        operationStateChanged: @escaping @MainActor (Bool) -> Void
    ) -> UInt64? {
        guard activeOperationID == nil else { return nil }
        nextOperationID &+= 1
        activeOperationID = nextOperationID
        isOperationInFlight = true
        operationStateChanged(true)
        return nextOperationID
    }

    private func finishOperation(
        _ operationID: UInt64,
        result: Bool,
        operationStateChanged: @escaping @MainActor (Bool) -> Void,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard activeOperationID == operationID else { return }
        activeOperationID = nil
        isOperationInFlight = false
        operationStateChanged(false)
        completion(result)
    }
}

enum CursorSessionBridge {
    static func importSessionOffMainActor(_ token: String) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            importSessionSynchronously(token)
        }.value
    }

    static func clearSessionOffMainActor() async -> Bool {
        await Task.detached(priority: .userInitiated) {
            clearSessionSynchronously()
        }.value
    }

    private static func importSessionSynchronously(_ token: String) -> Bool {
        token.withCString { token in
            decodeConnected(needlbar_cursor_import_session_json(token), key: "connected")
        }
    }

    private static func clearSessionSynchronously() -> Bool {
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
