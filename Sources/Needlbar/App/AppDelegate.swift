import AppKit
import NeedlbarCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let snapshotStore: ProviderSnapshotStore
    private let refreshCoordinator: RefreshCoordinator
    private let loginCoordinator: ProviderLoginCoordinator
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
        let refreshCoordinator = RefreshCoordinator(
            usageRepository: RustUsageRepository(),
            quotaRepository: RustQuotaRepository(),
            store: snapshotStore,
            usageFileWatcher: usageFileWatcher
        )
        self.refreshCoordinator = refreshCoordinator
        let loginCoordinator = ProviderLoginCoordinator(
            refreshQuota: { provider in
                await refreshCoordinator.refreshQuota(afterUserAuthenticationFor: provider)
            }
        )
        self.loginCoordinator = loginCoordinator
        self.menuBarController = MenuBarController(
            configuration: moduleConfiguration,
            snapshotStore: snapshotStore,
            loginCoordinator: loginCoordinator,
            onModuleActivated: { _ in
                Task {
                    await refreshCoordinator.popoverOpened()
                }
            },
            onRetryRequested: {
                Task {
                    await refreshCoordinator.manualRefresh()
                }
            },
            onProviderLoginRequested: { provider in
                _ = loginCoordinator.connect(provider)
            }
        )
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ApplicationMenuInstaller.install(in: NSApp)
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
            stopLoginCoordinator: { [weak self] in
                guard let self else { return .complete }
                return await self.loginCoordinator.stop()
            },
            stopRefreshCoordinator: { [weak self] in
                await self?.refreshCoordinator.stop()
            },
            reply: { shouldTerminate in
                sender.reply(toApplicationShouldTerminate: shouldTerminate)
            },
            resumeLoginAdmission: { [weak self] in
                self?.loginCoordinator.resumeAfterDeniedTermination()
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
        stopLoginCoordinator: @escaping @MainActor () async -> ProviderLoginCleanupResult,
        stopRefreshCoordinator: @escaping @MainActor () async -> Void,
        reply: @escaping @MainActor (Bool) -> Void,
        resumeLoginAdmission: @escaping @MainActor () -> Void
    ) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateLater }
        isTerminating = true
        performSynchronousSafetyCleanup(
            cancelStartup: cancelStartup,
            stopMenuBarObservation: stopMenuBarObservation
        )
        terminationTask = Task { [weak self] in
            let loginCleanup = await stopLoginCoordinator()
            guard let self, self.isTerminating else { return }
            switch loginCleanup {
            case .complete:
                await stopRefreshCoordinator()
                guard self.isTerminating else { return }
                reply(true)
                self.terminationTask = nil
            case .pendingReap:
                reply(false)
                resumeLoginAdmission()
                self.isTerminating = false
                self.terminationTask = nil
            }
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
