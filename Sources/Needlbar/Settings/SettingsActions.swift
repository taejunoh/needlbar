import Combine
import Foundation
import NeedlbarCore

@MainActor
public final class SettingsActions: ObservableObject {
    @Published public private(set) var loginStates: [ProviderID: ProviderLoginState]
    @Published public private(set) var exportState: SnapshotExportState

    private let loginCoordinator: ProviderLoginCoordinator?
    private let snapshotExportController: SnapshotExportController?
    private let claudeCheckNow: (@MainActor () -> Void)?
    private var cancellables: Set<AnyCancellable> = []

    public init(
        loginCoordinator: ProviderLoginCoordinator,
        snapshotExportController: SnapshotExportController,
        claudeCheckNow: (@MainActor () -> Void)? = nil
    ) {
        loginStates = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, loginCoordinator.state(for: $0)) })
        exportState = snapshotExportController.state
        self.loginCoordinator = loginCoordinator
        self.snapshotExportController = snapshotExportController
        self.claudeCheckNow = claudeCheckNow

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

    public init(claudeCheckNow: (@MainActor () -> Void)? = nil) {
        loginStates = [:]
        exportState = .idle
        loginCoordinator = nil
        snapshotExportController = nil
        self.claudeCheckNow = claudeCheckNow
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

    /// One click on "Check now". It goes straight to the existing manual refresh,
    /// which joins a run already in flight, so repeated clicks need no state here.
    public func checkClaudeNow() {
        claudeCheckNow?()
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
