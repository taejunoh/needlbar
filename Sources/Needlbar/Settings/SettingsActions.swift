import Combine
import Foundation
import NeedlbarCore

@MainActor
public final class SettingsActions: ObservableObject {
    @Published public private(set) var loginStates: [ProviderID: ProviderLoginState]
    @Published public private(set) var exportState: SnapshotExportState

    private let loginCoordinator: ProviderLoginCoordinator?
    private let snapshotExportController: SnapshotExportController?
    private var cancellables: Set<AnyCancellable> = []

    public init(loginCoordinator: ProviderLoginCoordinator, snapshotExportController: SnapshotExportController) {
        loginStates = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, loginCoordinator.state(for: $0)) })
        exportState = snapshotExportController.state
        self.loginCoordinator = loginCoordinator
        self.snapshotExportController = snapshotExportController

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

    public init() {
        loginStates = [:]
        exportState = .idle
        loginCoordinator = nil
        snapshotExportController = nil
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
