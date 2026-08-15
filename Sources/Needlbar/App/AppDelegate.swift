import AppKit
import NeedlbarCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let snapshotStore: ProviderSnapshotStore
    private let refreshCoordinator: RefreshCoordinator
    private let moduleConfiguration: ModuleConfiguration
    private let menuBarController: MenuBarController
    private let terminationController = AccessoryTerminationController()
    private var lifecycleTask: Task<Void, Never>?

    public override init() {
        let snapshotStore = ProviderSnapshotStore()
        let moduleConfiguration = ModuleConfiguration()
        let usageFileWatcher = UsageFileWatcher()

        self.snapshotStore = snapshotStore
        self.moduleConfiguration = moduleConfiguration
        self.refreshCoordinator = RefreshCoordinator(
            usageRepository: RustUsageRepository(),
            quotaRepository: RustQuotaRepository(),
            store: snapshotStore,
            usageFileWatcher: usageFileWatcher
        )
        self.menuBarController = MenuBarController(
            configuration: moduleConfiguration,
            snapshotStore: snapshotStore
        )
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        lifecycleTask = Task { [weak self] in
            guard let self else { return }
            await self.menuBarController.startObserving()
            guard !Task.isCancelled else { return }
            await self.refreshCoordinator.start()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        terminationController.performSynchronousSafetyCleanup(
            cancelStartup: { [weak self] in self?.cancelLifecycleTask() },
            stopMenuBarObservation: { [weak self] in self?.menuBarController.stopObserving() }
        )
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminationController.requestTermination(
            cancelStartup: { [weak self] in self?.cancelLifecycleTask() },
            stopMenuBarObservation: { [weak self] in self?.menuBarController.stopObserving() },
            stopRefreshCoordinator: { [weak self] in
                await self?.refreshCoordinator.stop()
            },
            reply: {
                sender.reply(toApplicationShouldTerminate: true)
            }
        )
    }

    private func cancelLifecycleTask() {
        lifecycleTask?.cancel()
        lifecycleTask = nil
    }
}

@MainActor
final class AccessoryTerminationController {
    private var terminationTask: Task<Void, Never>?
    private var isTerminating = false
    private var didPerformSynchronousSafetyCleanup = false

    func requestTermination(
        cancelStartup: @escaping @MainActor () -> Void,
        stopMenuBarObservation: @escaping @MainActor () -> Void,
        stopRefreshCoordinator: @escaping @MainActor () async -> Void,
        reply: @escaping @MainActor () -> Void
    ) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateLater }
        isTerminating = true
        performSynchronousSafetyCleanup(
            cancelStartup: cancelStartup,
            stopMenuBarObservation: stopMenuBarObservation
        )
        terminationTask = Task { [weak self] in
            await stopRefreshCoordinator()
            guard let self, self.isTerminating else { return }
            reply()
            self.terminationTask = nil
        }
        return .terminateLater
    }

    func performSynchronousSafetyCleanup(
        cancelStartup: @escaping @MainActor () -> Void,
        stopMenuBarObservation: @escaping @MainActor () -> Void
    ) {
        guard !didPerformSynchronousSafetyCleanup else { return }
        didPerformSynchronousSafetyCleanup = true
        cancelStartup()
        stopMenuBarObservation()
    }
}
