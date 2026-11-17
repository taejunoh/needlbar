import Combine
import Foundation
import NeedlbarCore

@MainActor
public final class SettingsActions: ObservableObject {
    @Published public private(set) var loginStates: [ProviderID: ProviderLoginState]
    @Published public private(set) var exportState: SnapshotExportState
    /// The automatic Claude checks setting, or nil when these actions carry no
    /// preference (the acceptance build and tests), which hides its controls.
    @Published public private(set) var claudeAutomaticChecksEnabled: Bool?

    private let loginCoordinator: ProviderLoginCoordinator?
    private let snapshotExportController: SnapshotExportController?
    private let claudeCheckNow: (@MainActor () -> Void)?
    private let claudeAutomaticChecks: ClaudeAutomaticChecksPreferences?
    private var cancellables: Set<AnyCancellable> = []

    public init(
        loginCoordinator: ProviderLoginCoordinator,
        snapshotExportController: SnapshotExportController,
        claudeCheckNow: (@MainActor () -> Void)? = nil,
        claudeAutomaticChecks: ClaudeAutomaticChecksPreferences? = nil
    ) {
        loginStates = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, loginCoordinator.state(for: $0)) })
        exportState = snapshotExportController.state
        self.loginCoordinator = loginCoordinator
        self.snapshotExportController = snapshotExportController
        self.claudeCheckNow = claudeCheckNow
        self.claudeAutomaticChecks = claudeAutomaticChecks
        claudeAutomaticChecksEnabled = claudeAutomaticChecks?.isEnabled
        observeClaudeAutomaticChecks()

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

    public init(
        claudeCheckNow: (@MainActor () -> Void)? = nil,
        claudeAutomaticChecks: ClaudeAutomaticChecksPreferences? = nil
    ) {
        loginStates = [:]
        exportState = .idle
        loginCoordinator = nil
        snapshotExportController = nil
        self.claudeCheckNow = claudeCheckNow
        self.claudeAutomaticChecks = claudeAutomaticChecks
        claudeAutomaticChecksEnabled = claudeAutomaticChecks?.isEnabled
        observeClaudeAutomaticChecks()
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

    /// Sets the automatic Claude checks preference. It starts no run itself: the
    /// app observes the preference and tells the refresh coordinator.
    public func setClaudeAutomaticChecksEnabled(_ enabled: Bool) {
        guard let claudeAutomaticChecks else { return }
        claudeAutomaticChecks.setEnabled(enabled)
        claudeAutomaticChecksEnabled = enabled
    }

    /// Follows a change made elsewhere: the dashboard row or the first-run window.
    private func observeClaudeAutomaticChecks() {
        guard let claudeAutomaticChecks else { return }
        claudeAutomaticChecks.$isEnabled.dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.claudeAutomaticChecksEnabled = self.claudeAutomaticChecks?.isEnabled
                }
            }
            .store(in: &cancellables)
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
