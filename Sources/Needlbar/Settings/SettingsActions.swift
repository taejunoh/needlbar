import Combine
import Foundation
import NeedlbarCore

@MainActor
public final class SettingsActions: ObservableObject {
    @Published public private(set) var loginStates: [ProviderID: ProviderLoginState]
    @Published public private(set) var exportState: SnapshotExportState
    @Published public private(set) var isRequestingClaudeKeychainAccess = false

    private let loginCoordinator: ProviderLoginCoordinator?
    private let snapshotExportController: SnapshotExportController?
    private let claudeKeychainAccessOperation: (@Sendable () async -> Void)?
    private var cancellables: Set<AnyCancellable> = []

    public init(
        loginCoordinator: ProviderLoginCoordinator,
        snapshotExportController: SnapshotExportController,
        claudeKeychainAccessOperation: (@Sendable () async -> Void)? = nil
    ) {
        loginStates = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, loginCoordinator.state(for: $0)) })
        exportState = snapshotExportController.state
        self.loginCoordinator = loginCoordinator
        self.snapshotExportController = snapshotExportController
        self.claudeKeychainAccessOperation = claudeKeychainAccessOperation

        loginCoordinator.objectWillChange
            .sink { [weak self, weak loginCoordinator] _ in
                Task { @MainActor in
                    self?.replaceLoginStates(from: loginCoordinator)
                }
            }
            .store(in: &cancellables)

        snapshotExportController.objectWillChange
            .sink { [weak self, weak snapshotExportController] _ in
                Task { @MainActor in
                    self?.replaceExportState(from: snapshotExportController)
                }
            }
            .store(in: &cancellables)
    }

    public init(claudeKeychainAccessOperation: (@Sendable () async -> Void)? = nil) {
        loginStates = [:]
        exportState = .idle
        loginCoordinator = nil
        snapshotExportController = nil
        self.claudeKeychainAccessOperation = claudeKeychainAccessOperation
    }

    public func loginState(for provider: ProviderID) -> ProviderLoginState {
        loginStates[provider] ?? .idle
    }

    public var isExporting: Bool {
        snapshotExportController?.isExporting ?? (exportState == .exporting)
    }

    public func connect(_ provider: ProviderID) {
        guard let loginCoordinator else { return }
        _ = loginCoordinator.connect(provider)
        replaceLoginStates(from: loginCoordinator)
    }

    /// One explicit click on "Allow Keychain access". Clicks on any surface
    /// while one is running do nothing, and the operation's own result reaches
    /// every surface through the Claude quota failure reason.
    public func requestClaudeKeychainAccess() {
        guard let claudeKeychainAccessOperation, !isRequestingClaudeKeychainAccess else { return }
        isRequestingClaudeKeychainAccess = true
        Task {
            await claudeKeychainAccessOperation()
            isRequestingClaudeKeychainAccess = false
        }
    }

    public func exportSnapshot() {
        guard let snapshotExportController else { return }
        snapshotExportController.exportSnapshot()
        replaceExportState(from: snapshotExportController)
    }

    private func replaceLoginStates(from coordinator: ProviderLoginCoordinator?) {
        guard let coordinator else { return }
        loginStates = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, coordinator.state(for: $0)) })
    }

    private func replaceExportState(from controller: SnapshotExportController?) {
        if let controller { exportState = controller.state }
    }
}
