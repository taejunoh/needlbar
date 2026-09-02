import AppKit
import NeedlbarCore
import WidgetKit

@MainActor
protocol ProductionLifecycleServing: AnyObject {
    func startProductionMenu() async
    func startProductionSystem() async
    func startProductionNotifications() async
    func startProductionPublisher() async
    func startProductionRefresh() async
    func stopProductionRefresh() async
    func stopProductionPublisher() async
    func stopProductionNotifications() async
    func stopProductionSystem() async
    func stopProductionMenu() async
}

@MainActor
final class ProductionLifecycleController {
    private let services: any ProductionLifecycleServing
    private var running = false

    init(services: any ProductionLifecycleServing) {
        self.services = services
    }

    func start() async {
        guard !running else { return }
        running = true
        await services.startProductionMenu()
        guard running else { return }
        await services.startProductionSystem()
        guard running else { return }
        await services.startProductionNotifications()
        guard running else { return }
        await services.startProductionPublisher()
        guard running else { return }
        await services.startProductionRefresh()
    }

    func stop() async {
        guard running else { return }
        running = false
        await services.stopProductionRefresh()
        await services.stopProductionPublisher()
        await services.stopProductionNotifications()
        await services.stopProductionSystem()
        await services.stopProductionMenu()
    }

    func cancelStart() {
        running = false
    }
}

#if NEEDLBAR_ACCEPTANCE_DRIVER
@MainActor
protocol AcceptanceLifecycleServing: AnyObject {
    func startMenu() async
    func startNotifications() async
    func startPublisher() async
    func startDriver() async
    func stopDriver() async
    func stopPublisher() async
    func stopNotifications()
    func stopMenu()
}

@MainActor
final class AcceptanceLifecycleController {
    private let services: any AcceptanceLifecycleServing
    private var running = false

    init(services: any AcceptanceLifecycleServing) {
        self.services = services
    }

    func start() async {
        guard !running else { return }
        running = true
        await services.startMenu()
        guard running else { return }
        await services.startNotifications()
        guard running else { return }
        await services.startPublisher()
        guard running else { return }
        await services.startDriver()
    }

    func stop() async {
        guard running else { return }
        running = false
        await services.stopDriver()
        await services.stopPublisher()
        services.stopNotifications()
        services.stopMenu()
    }
}
#endif

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let snapshotStore: ProviderSnapshotStore
    private let combinedSnapshotStore: CombinedSnapshotStore
    private let moduleConfiguration: ModuleConfiguration
    private let notificationPreferences: QuotaNotificationPreferences
    private let notificationService: QuotaNotificationService
    private let widgetPublisher: WidgetProjectionPublisher?
    private let systemMetricsService: SystemMetricsService?
    private let menuBarController: MenuBarController
    private let terminationController = AccessoryTerminationController()
    private let launch: AppLaunchConfiguration
    private var refreshCoordinator: RefreshCoordinator?
    private var loginCoordinator: ProviderLoginCoordinator?
    private var snapshotExportController: SnapshotExportController?
    private var analyticsSnapshotStore: AnalyticsSnapshotStore?
    private var analyticsRepository: RustAnalyticsRepository?
    private var analyticsWindowController: AnalyticsWindowController?
    private var productionLifecycle: ProductionLifecycleController?
#if NEEDLBAR_ACCEPTANCE_DRIVER
    private var acceptanceDriver: AcceptanceFixtureDriver?
    private var acceptanceLifecycle: AcceptanceLifecycleController?
#endif
    private var lifecycleTask: Task<Void, Never>?
    private var providerSnapshotForwardingTask: Task<Void, Never>?
    private var systemMetricsForwardingTask: Task<Void, Never>?
    private var systemMonitorConfigurationObserver: NSObjectProtocol?

    public init(launch: AppLaunchConfiguration = .production) {
        let snapshotStore = ProviderSnapshotStore()
        let combinedSnapshotStore = CombinedSnapshotStore()
        let moduleConfiguration = ModuleConfiguration()
        let notificationPreferences = QuotaNotificationPreferences()
        self.snapshotStore = snapshotStore
        self.combinedSnapshotStore = combinedSnapshotStore
        self.moduleConfiguration = moduleConfiguration
        self.notificationPreferences = notificationPreferences
        self.notificationService = QuotaNotificationService(
            store: snapshotStore,
            preferences: notificationPreferences
        )
        self.widgetPublisher = makeWidgetPublisher()
        self.launch = launch

        switch launch {
        case .production:
            let systemMetricsService = SystemMetricsService(collector: MacSystemMetricsCollector())
            let usageFileWatcher = UsageFileWatcher()
            let refreshCoordinator = RefreshCoordinator(
                usageRepository: RustUsageRepository(),
                quotaRepository: RustQuotaRepository(),
                store: snapshotStore,
                usageFileWatcher: usageFileWatcher
            )
            let loginCoordinator = ProviderLoginCoordinator(
                refreshQuota: { provider in
                    await refreshCoordinator.refreshQuota(afterUserAuthenticationFor: provider)
                }
            )
            let snapshotExportController = SnapshotExportController(
                captureSource: snapshotStore,
                savePanelPresenter: NSSavePanelPresenter(),
                coreExportAction: DefaultCoreExportAction(),
                captureClock: Date.init
            )
            let analyticsSnapshotStore = AnalyticsSnapshotStore()
            let analyticsRepository = RustAnalyticsRepository()
            let analyticsWindowController = AnalyticsWindowController(
                store: analyticsSnapshotStore,
                repository: analyticsRepository
            )
            let actions = SettingsActions(
                loginCoordinator: loginCoordinator,
                snapshotExportController: snapshotExportController
            )
            self.refreshCoordinator = refreshCoordinator
            self.loginCoordinator = loginCoordinator
            self.snapshotExportController = snapshotExportController
            self.analyticsSnapshotStore = analyticsSnapshotStore
            self.analyticsRepository = analyticsRepository
            self.analyticsWindowController = analyticsWindowController
            self.systemMetricsService = systemMetricsService
            self.menuBarController = MenuBarController(
                configuration: moduleConfiguration,
                snapshotStore: snapshotStore,
                combinedSnapshotStore: combinedSnapshotStore,
                observeProviderSnapshots: false,
                actions: actions,
                notificationPreferences: self.notificationPreferences,
                notificationService: self.notificationService,
                onModuleActivated: { _ in
                    Task { await refreshCoordinator.popoverOpened() }
                },
                onRetryRequested: {
                    Task { await refreshCoordinator.manualRefresh() }
                },
                onProviderLoginRequested: { provider in
                    _ = loginCoordinator.connect(provider)
                },
                onAnalyticsRequested: { [weak analyticsWindowController] in
                    analyticsWindowController?.showAnalytics()
                }
            )
#if NEEDLBAR_ACCEPTANCE_DRIVER
            self.acceptanceDriver = nil
#endif
#if NEEDLBAR_ACCEPTANCE_DRIVER
        case .acceptance(let fixture):
            let actions = SettingsActions()
            self.systemMetricsService = nil
            self.refreshCoordinator = nil
            self.loginCoordinator = nil
            self.snapshotExportController = nil
            self.analyticsSnapshotStore = nil
            self.analyticsRepository = nil
            self.analyticsWindowController = nil
            self.acceptanceDriver = AcceptanceFixtureDriver(fixture: fixture, store: snapshotStore)
            self.menuBarController = MenuBarController(
                configuration: moduleConfiguration,
                snapshotStore: snapshotStore,
                combinedSnapshotStore: combinedSnapshotStore,
                actions: actions,
                notificationPreferences: self.notificationPreferences,
                notificationService: self.notificationService
            )
#endif
        }
        super.init()
        if case .production = launch {
            productionLifecycle = ProductionLifecycleController(services: self)
        }
#if NEEDLBAR_ACCEPTANCE_DRIVER
        if case .acceptance = launch {
            acceptanceLifecycle = AcceptanceLifecycleController(services: self)
        }
#endif
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ApplicationMenuInstaller.install(in: NSApp)
        lifecycleTask = Task { [weak self] in
            guard let self else { return }
            switch self.launch {
            case .production:
                await self.productionLifecycle?.start()
#if NEEDLBAR_ACCEPTANCE_DRIVER
            case .acceptance:
                await self.acceptanceLifecycle?.start()
#endif
            }
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
#if NEEDLBAR_ACCEPTANCE_DRIVER
        if case .acceptance = launch {
            cancelLifecycleTask()
            return
        }
#endif
        terminationController.performSynchronousSafetyCleanup(
            cancelStartup: { [weak self] in self?.cancelLifecycleTask() },
            stopNotifications: { [weak self] in self?.notificationService.stop() },
            stopMenuBarObservation: { [weak self] in self?.menuBarController.stopObserving() },
            stopSystemMetrics: { [weak self] in self?.stopSystemMetricsSynchronously() }
        )
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
#if NEEDLBAR_ACCEPTANCE_DRIVER
        if case .acceptance = launch {
            cancelLifecycleTask()
            lifecycleTask = Task { [weak self] in
                await self?.acceptanceLifecycle?.stop()
                sender.reply(toApplicationShouldTerminate: true)
                self?.lifecycleTask = nil
            }
            return .terminateLater
        }
#endif
        return terminationController.requestTermination(
            cancelStartup: { [weak self] in self?.cancelLifecycleTask() },
            stopNotifications: { [weak self] in self?.notificationService.stop() },
            stopMenuBarObservation: { [weak self] in self?.menuBarController.stopObserving() },
            stopLoginCoordinator: { [weak self] in
                guard let coordinator = self?.loginCoordinator else { return .complete }
                return await coordinator.stop()
            },
            stopRefreshCoordinator: { [weak self] in
                guard let self else { return }
                await self.widgetPublisher?.stop()
                await self.refreshCoordinator?.stop()
            },
            reply: { shouldTerminate in
                sender.reply(toApplicationShouldTerminate: shouldTerminate)
            },
            resumeLoginAdmission: { [weak self] in
                self?.loginCoordinator?.resumeAfterDeniedTermination()
            },
            resumeNotifications: { [weak self] in
                Task { await self?.notificationService.start() }
            },
            stopSystemMetrics: { [weak self] in self?.stopSystemMetricsSynchronously() }
        )
    }

    private func cancelLifecycleTask() {
        lifecycleTask?.cancel()
        lifecycleTask = nil
        productionLifecycle?.cancelStart()
    }

    private func stopSystemMetricsSynchronously() {
        removeSystemMonitorConfigurationObserver()
        providerSnapshotForwardingTask?.cancel()
        providerSnapshotForwardingTask = nil
        systemMetricsForwardingTask?.cancel()
        systemMetricsForwardingTask = nil
        guard let systemMetricsService else { return }
        Task { await systemMetricsService.stop() }
    }
}

@MainActor
extension AppDelegate: ProductionLifecycleServing {
    func startProductionMenu() async {
        await menuBarController.startObserving()
    }

    func startProductionSystem() async {
        guard providerSnapshotForwardingTask == nil, systemMetricsForwardingTask == nil else { return }
        let providerUpdates = await snapshotStore.updates()
        providerSnapshotForwardingTask = Task { [combinedSnapshotStore] in
            for await snapshots in providerUpdates {
                guard !Task.isCancelled else { return }
                await combinedSnapshotStore.applyProviders(snapshots)
            }
        }
        guard let systemMetricsService else { return }
        let systemUpdates = await systemMetricsService.updates()
        systemMetricsForwardingTask = Task { [combinedSnapshotStore] in
            for await snapshot in systemUpdates {
                guard !Task.isCancelled else { return }
                await combinedSnapshotStore.applySystem(snapshot)
            }
        }
        systemMonitorConfigurationObserver = NotificationCenter.default.addObserver(
            forName: ModuleConfiguration.systemMonitorDidChangeNotification,
            object: moduleConfiguration,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let systemMetricsService = self.systemMetricsService else { return }
                await systemMetricsService.setPublicIPEnabled(self.moduleConfiguration.systemMonitor.publicIPEnabled)
            }
        }
        await systemMetricsService.start(publicIPEnabled: moduleConfiguration.systemMonitor.publicIPEnabled)
    }

    func startProductionNotifications() async {
        await notificationService.start()
    }

    func startProductionPublisher() async {
        await widgetPublisher?.start(observing: snapshotStore)
    }

    func startProductionRefresh() async {
        await refreshCoordinator?.start()
    }

    func stopProductionRefresh() async {
        await refreshCoordinator?.stop()
    }

    func stopProductionPublisher() async {
        await widgetPublisher?.stop()
    }

    func stopProductionNotifications() async {
        notificationService.stop()
    }

    func stopProductionSystem() async {
        removeSystemMonitorConfigurationObserver()
        providerSnapshotForwardingTask?.cancel()
        providerSnapshotForwardingTask = nil
        systemMetricsForwardingTask?.cancel()
        systemMetricsForwardingTask = nil
        await systemMetricsService?.stop()
    }

    func stopProductionMenu() async {
        menuBarController.stopObserving()
    }

    private func removeSystemMonitorConfigurationObserver() {
        guard let observer = systemMonitorConfigurationObserver else { return }
        NotificationCenter.default.removeObserver(observer)
        systemMonitorConfigurationObserver = nil
    }
}

#if NEEDLBAR_ACCEPTANCE_DRIVER
@MainActor
extension AppDelegate: AcceptanceLifecycleServing {
    func startMenu() async {
        await menuBarController.startObserving()
    }

    func startNotifications() async {
        await notificationService.start()
    }

    func startPublisher() async {
        await widgetPublisher?.start(observing: snapshotStore)
    }

    func startDriver() async {
        await acceptanceDriver?.start()
    }

    func stopDriver() async {
        await acceptanceDriver?.stop()
    }

    func stopPublisher() async {
        await widgetPublisher?.stop()
    }

    func stopNotifications() {
        notificationService.stop()
    }

    func stopMenu() {
        menuBarController.stopObserving()
    }
}
#endif

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
        resumeNotifications: @escaping @MainActor () -> Void,
        stopSystemMetrics: @escaping @MainActor () -> Void = {}
    ) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateLater }
        isTerminating = true
        performSynchronousSafetyCleanup(
            cancelStartup: cancelStartup,
            stopNotifications: stopNotifications,
            stopMenuBarObservation: stopMenuBarObservation,
            stopSystemMetrics: stopSystemMetrics
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
        stopMenuBarObservation: @escaping @MainActor () -> Void,
        stopSystemMetrics: @escaping @MainActor () -> Void = {}
    ) {
        guard !didPerformSynchronousSafetyCleanup else { return }
        didPerformSynchronousSafetyCleanup = true
        cancelStartup()
        stopNotifications()
        stopSystemMetrics()
        stopMenuBarObservation()
    }
}
