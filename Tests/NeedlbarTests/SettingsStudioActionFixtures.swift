import Foundation
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

// Real coordinators, fake external boundaries. First invocation succeeds and
// subsequent invocations fail. No executable, browser, save panel or writer runs.
@MainActor
func settingsStudioReviewActions(delay: Duration) -> SettingsActions {
    let login = ProviderLoginCoordinator(
        resolver: SettingsStudioFixtureResolver(),
        runner: SettingsStudioFixtureRunner(delay: delay),
        refreshQuota: { _ in
            try? await Task.sleep(for: delay)
            return true
        },
        stateObserver: { provider, state in
            print("SETTINGS_ACTION_FIXTURE provider=\(provider.rawValue) state=\(state)")
        },
        beforeProcessStart: { _ in try? await Task.sleep(for: delay) })
    let exporter = SnapshotExportController(
        captureSource: SettingsStudioFixtureCapture(),
        savePanelPresenter: SettingsStudioFixtureDestination(),
        coreExportAction: SettingsStudioFixtureExport(delay: delay),
        captureClock: { .distantPast })
    return SettingsActions(loginCoordinator: login, snapshotExportController: exporter)
}

private struct SettingsStudioFixtureResolver: ProviderLoginCommandResolving {
    func command(for provider: ProviderID) throws -> ProviderLoginCommand {
        guard provider != .cursor else {
            throw ProviderLoginCommandResolutionError.unsupportedProvider
        }
        return ProviderLoginCommand(provider: provider,
            executableURL: URL(fileURLWithPath: "/fixture/never-executed"),
            arguments: [], environment: [:])
    }
}

private actor SettingsStudioFixtureRunner: ProviderLoginProcessRunning {
    let delay: Duration
    private var calls: [ProviderID: Int] = [:]
    init(delay: Duration) { self.delay = delay }
    func run(_ command: ProviderLoginCommand) async -> ProviderLoginProcessOutcome {
        calls[command.provider, default: 0] += 1
        let succeeds = calls[command.provider] == 1
        do { try await Task.sleep(for: delay) } catch { return .cancelled }
        return .exited(status: succeeds ? 0 : 1)
    }
    func stop() async -> ProviderLoginCleanupResult { .complete }
}

private struct SettingsStudioFixtureCapture: ExportCaptureProviding {
    func captureForExport(exportedAt: Date) async -> ExportCapture {
        ExportCapture(exportedAt: exportedAt, providers: [])
    }
}

@MainActor
private final class SettingsStudioFixtureDestination: SavePanelPresenter {
    func selectDestination(defaultFilename: String) -> URL? {
        // Merely passed to the inert action below; never created or accessed.
        URL(fileURLWithPath: "/fixture/never-written.json")
    }
}

private actor SettingsStudioFixtureExport: CoreExportAction {
    let delay: Duration
    private var calls = 0
    init(delay: Duration) { self.delay = delay }
    func export(_ capture: ExportCapture, to destination: URL) async throws -> AtomicWriteResult {
        calls += 1
        let succeeds = calls == 1
        try await Task.sleep(for: delay)
        guard succeeds else { throw SnapshotFileWriteError.writeFailed }
        return .committed
    }
}

@MainActor
@Test func settingsStudioActionFixturesExerciseRealStatePropagation() async throws {
    let actions = settingsStudioReviewActions(delay: .zero)
    #expect(actions.loginState(for: .claude) == .idle)
    #expect(actions.exportState == .idle)
    for provider in [ProviderID.claude, .codex] {
        actions.connect(provider)
        #expect(actions.loginState(for: provider) == .launching)
        try await waitForFixture { actions.loginState(for: provider) == .connected }
        actions.connect(provider)
        try await waitForFixture { actions.loginState(for: provider) == .failed(.providerRejected) }
    }
    actions.exportSnapshot()
    #expect(actions.isExporting)
    try await waitForFixture { actions.exportState == .exported }
    #expect(!actions.isExporting)
    actions.exportSnapshot()
    #expect(actions.isExporting)
    try await waitForFixture { actions.exportState == .failed }
    #expect(!actions.isExporting)
}

@MainActor
private func waitForFixture(_ condition: () -> Bool) async throws {
    // Other native layout tests can occupy MainActor for several seconds.
    // Bound observation attempts, not wall time spent waiting behind that work.
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    try #require(condition())
}
