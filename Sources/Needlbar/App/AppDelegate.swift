import AppKit
import NeedlbarCore
import WidgetKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let snapshotStore: ProviderSnapshotStore
    private let refreshCoordinator: RefreshCoordinator
    private let loginCoordinator: ProviderLoginCoordinator
    private let moduleConfiguration: ModuleConfiguration
    private let snapshotExportController: SnapshotExportController
    private let notificationPreferences: QuotaNotificationPreferences
    private let notificationService: QuotaNotificationService
    private let widgetPublisher: WidgetProjectionPublisher?
    private let analyticsSnapshotStore: AnalyticsSnapshotStore
    private let analyticsRepository: RustAnalyticsRepository
    private let analyticsWindowController: AnalyticsWindowController
    private let menuBarController: MenuBarController
    private let terminationController = AccessoryTerminationController()
    private var lifecycleTask: Task<Void, Never>?

    public override init() {
        let snapshotStore = ProviderSnapshotStore()
        let moduleConfiguration = ModuleConfiguration()
        let usageFileWatcher = UsageFileWatcher()

        self.snapshotStore = snapshotStore
        let notificationPreferences = QuotaNotificationPreferences()
        self.notificationPreferences = notificationPreferences
        let notificationService = QuotaNotificationService(
            store: snapshotStore,
            preferences: notificationPreferences
        )
        self.notificationService = notificationService
        self.moduleConfiguration = moduleConfiguration
        self.widgetPublisher = makeWidgetPublisher()
        let analyticsSnapshotStore = AnalyticsSnapshotStore()
        let analyticsRepository = RustAnalyticsRepository()
        let analyticsWindowController = AnalyticsWindowController(
            store: analyticsSnapshotStore,
            repository: analyticsRepository
        )
        self.analyticsSnapshotStore = analyticsSnapshotStore
        self.analyticsRepository = analyticsRepository
        self.analyticsWindowController = analyticsWindowController
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
        let snapshotExportController = SnapshotExportController(
            captureSource: snapshotStore,
            savePanelPresenter: NSSavePanelPresenter(),
            coreExportAction: DefaultCoreExportAction(),
            captureClock: Date.init
        )
        self.snapshotExportController = snapshotExportController
        let openCursorSpending: @MainActor () -> Void = {
            _ = CursorSpendingAction.open()
        }
        self.menuBarController = MenuBarController(
            configuration: moduleConfiguration,
            snapshotStore: snapshotStore,
            loginCoordinator: loginCoordinator,
            snapshotExportController: snapshotExportController,
            notificationPreferences: notificationPreferences,
            notificationService: notificationService,
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
            },
            onAnalyticsRequested: { [weak analyticsWindowController] in
                analyticsWindowController?.showAnalytics()
            },
            openCursorSpending: openCursorSpending
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
            await self.notificationService.start()
            guard !Task.isCancelled else { return }
            await self.widgetPublisher?.start(observing: self.snapshotStore)
            guard !Task.isCancelled else { return }
            await self.refreshCoordinator.start()
        }
    }

    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            _ = OverviewDeepLink.open(url) { [weak self] in
                self?.menuBarController.openOverview()
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        terminationController.performSynchronousSafetyCleanup(
            cancelStartup: { [weak self] in self?.cancelLifecycleTask() },
            stopNotifications: { [weak self] in self?.notificationService.stop() },
            stopMenuBarObservation: { [weak self] in self?.menuBarController.stopObserving() }
        )
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminationController.requestTermination(
            cancelStartup: { [weak self] in self?.cancelLifecycleTask() },
            stopNotifications: { [weak self] in self?.notificationService.stop() },
            stopMenuBarObservation: { [weak self] in self?.menuBarController.stopObserving() },
            stopLoginCoordinator: { [weak self] in
                guard let self else { return .complete }
                return await self.loginCoordinator.stop()
            },
            stopRefreshCoordinator: { [weak self] in
                guard let self else { return }
                await self.widgetPublisher?.stop()
                await self.refreshCoordinator.stop()
            },
            reply: { shouldTerminate in
                sender.reply(toApplicationShouldTerminate: shouldTerminate)
            },
            resumeLoginAdmission: { [weak self] in
                self?.loginCoordinator.resumeAfterDeniedTermination()
            },
            resumeNotifications: { [weak self] in
                Task { await self?.notificationService.start() }
            }
        )
    }

    private func cancelLifecycleTask() {
        lifecycleTask?.cancel()
        lifecycleTask = nil
    }
}

@MainActor
enum OverviewDeepLink {
    static func open(_ url: URL, showOverview: () -> Void) -> Bool {
        guard url.scheme == "needlbar",
              url.host == "overview",
              url.port == nil,
              url.user == nil,
              url.password == nil,
              url.path.isEmpty,
              url.query == nil,
              url.fragment == nil else {
            return false
        }
        showOverview()
        return true
    }
}

struct WidgetKitTimelineReloader: WidgetTimelineReloading {
    func reloadOverview() async {
        WidgetCenter.shared.reloadTimelines(ofKind: "NeedlbarOverview")
    }
}

private func makeWidgetPublisher() -> WidgetProjectionPublisher? {
    guard let id = Bundle.main.object(forInfoDictionaryKey: "NeedlbarAppGroupIdentifier") as? String,
          let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else { return nil }
    return WidgetProjectionPublisher(
        reloader: WidgetKitTimelineReloader(),
        destination: directory.appendingPathComponent("NeedlbarWidgetProjection.json")
    )
}

@MainActor
final class AccessoryTerminationController {
    private var terminationTask: Task<Void, Never>?
    private var isTerminating = false
    private var didPerformSynchronousSafetyCleanup = false

    func requestTermination(
        cancelStartup: @escaping @MainActor () -> Void,
        stopNotifications: @escaping @MainActor () -> Void,
        stopMenuBarObservation: @escaping @MainActor () -> Void,
        stopLoginCoordinator: @escaping @MainActor () async -> ProviderLoginCleanupResult,
        stopRefreshCoordinator: @escaping @MainActor () async -> Void,
        reply: @escaping @MainActor (Bool) -> Void,
        resumeLoginAdmission: @escaping @MainActor () -> Void,
        resumeNotifications: @escaping @MainActor () -> Void
    ) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateLater }
        isTerminating = true
        performSynchronousSafetyCleanup(
            cancelStartup: cancelStartup,
            stopNotifications: stopNotifications,
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
                resumeNotifications()
                self.isTerminating = false
                self.didPerformSynchronousSafetyCleanup = false
                self.terminationTask = nil
            }
        }
        return .terminateLater
    }

    func performSynchronousSafetyCleanup(
        cancelStartup: @escaping @MainActor () -> Void,
        stopNotifications: @escaping @MainActor () -> Void,
        stopMenuBarObservation: @escaping @MainActor () -> Void
    ) {
        guard !didPerformSynchronousSafetyCleanup else { return }
        didPerformSynchronousSafetyCleanup = true
        cancelStartup()
        stopNotifications()
        stopMenuBarObservation()
    }
}
