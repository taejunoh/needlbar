import AppKit
import NeedlbarCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let snapshotStore: ProviderSnapshotStore
    private let refreshCoordinator: RefreshCoordinator
    private let moduleConfiguration: ModuleConfiguration
    private let menuBarController: MenuBarController
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
        lifecycleTask?.cancel()
        lifecycleTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshCoordinator.stop()
            self.menuBarController.stopObserving()
        }
    }
}
