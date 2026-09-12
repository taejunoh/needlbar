import Foundation
import NeedlbarApp
import NeedlbarCore

public enum SettingsStudioReviewLaunch {
    public static let argument = "--settings-studio-review"

    public static func isOptedIn(arguments: [String]) -> Bool {
        Array(arguments.dropFirst()) == [argument]
    }
}

/// Real SettingsActions with all process, credential, file and browser boundaries inert.
@MainActor
public func settingsStudioReviewActions(delay: Duration) -> SettingsActions {
    let login = ProviderLoginCoordinator(
        resolver: SettingsStudioFixtureResolver(),
        runner: SettingsStudioFixtureRunner(delay: delay),
        refreshQuota: { _ in
            try? await Task.sleep(for: delay)
            return true
        },
        preflightClaudeLogin: { .requiresAuthentication },
        stateObserver: { provider, state in
            print("SETTINGS_ACTION_FIXTURE provider=\(provider.rawValue) state=\(state)")
        },
        beforeProcessStart: { _ in try? await Task.sleep(for: delay) }
    )
    let exporter = SnapshotExportController(
        captureSource: SettingsStudioFixtureCapture(),
        savePanelPresenter: SettingsStudioFixtureDestination(),
        coreExportAction: SettingsStudioFixtureExport(delay: delay),
        captureClock: { .distantPast }
    )
    return SettingsActions(loginCoordinator: login, snapshotExportController: exporter)
}

public struct SettingsStudioInertNotificationClient: QuotaNotificationClient {
    public init() {}

    public func currentAuthorization() async -> QuotaNotificationAuthorization { .denied }
    public func requestAuthorization() async -> QuotaNotificationAuthorization { .denied }
    public func submit(body: String) async -> QuotaNotificationSubmission { .failed }
}

private struct SettingsStudioFixtureResolver: ProviderLoginCommandResolving {
    func command(for provider: ProviderID) throws -> ProviderLoginCommand {
        guard provider != .cursor else {
            throw ProviderLoginCommandResolutionError.unsupportedProvider
        }
        return ProviderLoginCommand(
            provider: provider,
            executableURL: URL(fileURLWithPath: "/fixture/never-executed"),
            arguments: [],
            environment: [:]
        )
    }
}

private actor SettingsStudioFixtureRunner: ProviderLoginProcessRunning {
    let delay: Duration
    private var calls: [ProviderID: Int] = [:]

    init(delay: Duration) { self.delay = delay }

    func run(_ command: ProviderLoginCommand) async -> ProviderLoginProcessOutcome {
        calls[command.provider, default: 0] += 1
        let succeeds = calls[command.provider] == 1
        do {
            try await Task.sleep(for: delay)
        } catch {
            return .cancelled
        }
        return .exited(status: succeeds ? 0 : 1)
    }

    func stop() async -> ProviderLoginCleanupResult { .complete }
}

private struct SettingsStudioFixtureCapture: ExportCaptureProviding {
    func captureForExport(exportedAt: Date) async -> ExportCapture {
        await ProviderSnapshotStore().captureForExport(exportedAt: exportedAt)
    }
}

@MainActor
private final class SettingsStudioFixtureDestination: SavePanelPresenter {
    func selectDestination(defaultFilename: String) -> URL? {
        // Only passed to the inert export action; no path is created or accessed.
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
