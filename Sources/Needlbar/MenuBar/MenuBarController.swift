import AppKit
import NeedlbarCore
import SwiftUI

@MainActor
public protocol StatusItemHandle: AnyObject {
    var title: String { get set }
    var action: (@MainActor () -> Void)? { get set }
    var availableWidth: Double { get }
    func presentationAnchor() -> StatusItemPresentationAnchor?
}

public extension StatusItemHandle {
    var availableWidth: Double { 400 }
}

@MainActor
public protocol GlobalMouseDownMonitoringToken: AnyObject {
    func cancel()
}

@MainActor
public protocol GlobalMouseDownMonitoring: AnyObject {
    func start(_ handler: @escaping @MainActor () -> Void) -> any GlobalMouseDownMonitoringToken
}

@MainActor
public final class AppKitGlobalMouseDownMonitor: GlobalMouseDownMonitoring {
    public init() {}

    public func start(_ handler: @escaping @MainActor () -> Void) -> any GlobalMouseDownMonitoringToken {
        let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { _ in
            Task { @MainActor in
                handler()
            }
        }
        return Token(monitor: monitor)
    }

    @MainActor
    private final class Token: GlobalMouseDownMonitoringToken {
        private var monitor: Any?

        init(monitor: Any?) {
            self.monitor = monitor
        }

        func cancel() {
            guard let monitor else { return }
            self.monitor = nil
            NSEvent.removeMonitor(monitor)
        }

    }
}

@MainActor
public protocol StatusItemFactory: AnyObject {
    func makeStatusItem() -> any StatusItemHandle
    func removeStatusItem(_ statusItem: any StatusItemHandle)
}

@MainActor
private final class LegacyMenuBarController: NSObject {
    private let configuration: ModuleConfiguration
    private let snapshotStore: ProviderSnapshotStore
    private let statusItemFactory: any StatusItemFactory
    private let onModuleActivated: @MainActor (MenuModuleID) -> Void
    private let onRetryRequested: @MainActor () -> Void
    private let onProviderLoginRequested: @MainActor (ProviderID) -> Void
    private let onSettingsRequested: @MainActor () -> Void
    private let onAnalyticsRequested: @MainActor () -> Void
    private let openCursorSpending: @MainActor () -> Void
    private let settingsWindowController: SettingsWindowController
    private let panelPresenter: any MenuPanelPresenting
    private let globalMouseDownMonitor: any GlobalMouseDownMonitoring
    private var globalMouseDownMonitoringToken: (any GlobalMouseDownMonitoringToken)?
    private var panelPresentationGeneration: UInt64 = 0
    private var snapshotRequestGeneration: UInt64 = 0
    private var activeMenuModule: MenuModuleID?
    private var statusItems: [MenuModuleID: any StatusItemHandle] = [:]
    private var deepLinkStatusItem: (any StatusItemHandle)?
    private var cachedSnapshots: [ProviderSnapshot] = []
    private var configurationObserver: NSObjectProtocol?
    private var snapshotObservationTask: Task<Void, Never>?
    private var observationGeneration: UInt64 = 0

    public init(
        configuration: ModuleConfiguration,
        snapshotStore: ProviderSnapshotStore,
        actions: SettingsActions,
        notificationPreferences: QuotaNotificationPreferences,
        notificationService: QuotaNotificationService,
        statusItemFactory: any StatusItemFactory = AppKitStatusItemFactory(),
        globalMouseDownMonitor: any GlobalMouseDownMonitoring = AppKitGlobalMouseDownMonitor(),
        panelPresenter: any MenuPanelPresenting = AppKitMenuPanelPresenter(),
        onModuleActivated: @escaping @MainActor (MenuModuleID) -> Void = { _ in },
        onRetryRequested: @escaping @MainActor () -> Void = {},
        onProviderLoginRequested: @escaping @MainActor (ProviderID) -> Void = { _ in },
        onSettingsRequested: @escaping @MainActor () -> Void = {},
        onAnalyticsRequested: @escaping @MainActor () -> Void = {},
        openCursorSpending: @escaping @MainActor () -> Void = { _ = CursorSpendingAction.open() }
    ) {
        self.configuration = configuration
        self.snapshotStore = snapshotStore
        self.statusItemFactory = statusItemFactory
        self.onModuleActivated = onModuleActivated
        self.onRetryRequested = onRetryRequested
        self.onProviderLoginRequested = onProviderLoginRequested
        self.onSettingsRequested = onSettingsRequested
        self.onAnalyticsRequested = onAnalyticsRequested
        self.openCursorSpending = openCursorSpending
        self.panelPresenter = panelPresenter
        self.globalMouseDownMonitor = globalMouseDownMonitor
        self.settingsWindowController = SettingsWindowController(
            configuration: configuration,
            actions: actions,
            notificationPreferences: notificationPreferences,
            notificationService: notificationService,
            openCursorSpending: openCursorSpending
        )
        super.init()
        panelPresenter.onDismiss = { [weak self] in
            self?.panelDidDismiss()
        }
    }

    public convenience init(
        configuration: ModuleConfiguration,
        snapshotStore: ProviderSnapshotStore,
        loginCoordinator: ProviderLoginCoordinator,
        snapshotExportController: SnapshotExportController,
        notificationPreferences: QuotaNotificationPreferences,
        notificationService: QuotaNotificationService,
        statusItemFactory: any StatusItemFactory = AppKitStatusItemFactory(),
        globalMouseDownMonitor: any GlobalMouseDownMonitoring = AppKitGlobalMouseDownMonitor(),
        panelPresenter: any MenuPanelPresenting = AppKitMenuPanelPresenter(),
        onModuleActivated: @escaping @MainActor (MenuModuleID) -> Void = { _ in },
        onRetryRequested: @escaping @MainActor () -> Void = {},
        onProviderLoginRequested: @escaping @MainActor (ProviderID) -> Void = { _ in },
        onSettingsRequested: @escaping @MainActor () -> Void = {},
        onAnalyticsRequested: @escaping @MainActor () -> Void = {},
        openCursorSpending: @escaping @MainActor () -> Void = { _ = CursorSpendingAction.open() }
    ) {
        self.init(
            configuration: configuration,
            snapshotStore: snapshotStore,
            actions: SettingsActions(
                loginCoordinator: loginCoordinator,
                snapshotExportController: snapshotExportController
            ),
            notificationPreferences: notificationPreferences,
            notificationService: notificationService,
            statusItemFactory: statusItemFactory,
            globalMouseDownMonitor: globalMouseDownMonitor,
            panelPresenter: panelPresenter,
            onModuleActivated: onModuleActivated,
            onRetryRequested: onRetryRequested,
            onProviderLoginRequested: onProviderLoginRequested,
            onSettingsRequested: onSettingsRequested,
            onAnalyticsRequested: onAnalyticsRequested,
            openCursorSpending: openCursorSpending
        )
    }

    public var activeModuleIDs: [MenuModuleID] {
        MenuBarModule.all.compactMap { module in
            statusItems[module.id] == nil ? nil : module.id
        }
    }

    public func refresh() async {
        let snapshots = await snapshotStore.snapshots()
        reconcile(using: snapshots)
    }

    public func startObserving() async {
        guard configurationObserver == nil, snapshotObservationTask == nil else { return }
        observationGeneration &+= 1
        let generation = observationGeneration
        let updates = await snapshotStore.updates()
        await refresh()
        configurationObserver = NotificationCenter.default.addObserver(
            forName: ModuleConfiguration.didChangeNotification,
            object: configuration,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.observationGeneration == generation else { return }
                self.reconcile(using: self.cachedSnapshots)
            }
        }
        snapshotObservationTask = Task { [weak self] in
            for await snapshots in updates {
                guard !Task.isCancelled else { return }
                guard let self, self.observationGeneration == generation else { return }
                self.reconcile(using: snapshots)
            }
        }
    }

    public func stopObserving() {
        observationGeneration &+= 1
        dismissPanelAndCleanUp()
        snapshotObservationTask?.cancel()
        snapshotObservationTask = nil
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
    }

    public func openOverview() {
        let statusItem: any StatusItemHandle
        if let existing = statusItems[.overview] {
            statusItem = existing
        } else if let existing = deepLinkStatusItem {
            statusItem = existing
        } else {
            let created = statusItemFactory.makeStatusItem()
            created.title = MenuBarModule.overview.title
            deepLinkStatusItem = created
            statusItem = created
        }
        snapshotRequestGeneration &+= 1
        showPanel(for: .overview, snapshots: cachedSnapshots, from: statusItem)
    }

    private func reconcile(using snapshots: [ProviderSnapshot]) {
        cachedSnapshots = snapshots
        let requiredIDs = Set(configuration.enabledModuleIDs)
        let existingIDs = Set(statusItems.keys)

        for moduleID in existingIDs.subtracting(requiredIDs) {
            guard let statusItem = statusItems.removeValue(forKey: moduleID) else { continue }
            statusItemFactory.removeStatusItem(statusItem)
        }

        for module in MenuBarModule.all where requiredIDs.contains(module.id) {
            let statusItem: any StatusItemHandle
            if let existing = statusItems[module.id] {
                statusItem = existing
            } else {
                let created = statusItemFactory.makeStatusItem()
                statusItems[module.id] = created
                statusItem = created
            }

            statusItem.title = MenuBarTitleRenderer.render(
                module: module,
                snapshot: module.provider.flatMap { provider in
                    snapshots.first(where: { $0.provider == provider })
                },
                allSnapshots: snapshots,
                configuration: configuration
            )
            statusItem.action = { [weak self, weak statusItem] in
                guard let self, let statusItem else { return }
                self.activate(module.id, from: statusItem)
            }
        }
    }

    private func activate(_ module: MenuModuleID, from statusItem: any StatusItemHandle) {
        onModuleActivated(module)
        snapshotRequestGeneration &+= 1
        let requestGeneration = snapshotRequestGeneration
        if panelPresenter.isShown, activeMenuModule == module {
            panelPresenter.dismiss()
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let snapshots = await self.snapshotStore.snapshots()
            guard !Task.isCancelled, self.snapshotRequestGeneration == requestGeneration else { return }
            self.showPanel(for: module, snapshots: snapshots, from: statusItem)
        }
    }

    private func showPanel(
        for module: MenuModuleID,
        snapshots: [ProviderSnapshot],
        from statusItem: any StatusItemHandle
    ) {
        if panelPresenter.isShown, activeMenuModule == module {
            panelPresenter.dismiss()
            return
        }

        let view: AnyView
        switch module {
        case .overview:
            view = AnyView(OverviewPopoverView(
                snapshots: snapshots,
                configuration: configuration,
                onShowSettings: { [weak self] in self?.performSettingsAction() },
                onShowAnalytics: { [weak self] in self?.performAnalyticsAction() }
            ))
        case .claude, .codex, .cursor:
            guard let provider = module.provider,
                  let snapshot = snapshots.first(where: { $0.provider == provider }) else { return }
            view = AnyView(ProviderPopoverView(
                snapshot: snapshot,
                onRetry: { [weak self] in self?.performRetryAction() },
                onAuthenticationAction: { [weak self] action in
                    self?.performPresentedAuthenticationAction(action, for: provider)
                }
            ))
        }
        guard let anchor = statusItem.presentationAnchor() else {
            dismissPanelAndCleanUp()
            return
        }

        cancelGlobalMouseDownMonitoring()
        let hostingController = NSHostingController(rootView: view)
        guard panelPresenter.present(hostingController, anchoredAt: anchor) else {
            dismissPanelAndCleanUp()
            return
        }

        activeMenuModule = module
        panelPresentationGeneration &+= 1
        let presentationGeneration = panelPresentationGeneration
        globalMouseDownMonitoringToken = globalMouseDownMonitor.start { [weak self] in
            guard let self,
                  self.panelPresentationGeneration == presentationGeneration,
                  self.panelPresenter.isShown else { return }
            self.panelPresenter.dismiss()
        }
    }

    private func cancelGlobalMouseDownMonitoring() {
        globalMouseDownMonitoringToken?.cancel()
        globalMouseDownMonitoringToken = nil
    }

    private func panelDidDismiss() {
        panelPresentationGeneration &+= 1
        snapshotRequestGeneration &+= 1
        cancelGlobalMouseDownMonitoring()
        activeMenuModule = nil
        guard let temporary = deepLinkStatusItem else { return }
        statusItemFactory.removeStatusItem(temporary)
        deepLinkStatusItem = nil
    }

    private func dismissPanelAndCleanUp() {
        if panelPresenter.isShown {
            panelPresenter.dismiss()
        } else {
            panelDidDismiss()
        }
    }

    func performRetryAction() {
        onRetryRequested()
    }

    func performSettingsAction() {
        panelPresenter.dismiss()
        showSettings()
    }

    func performAnalyticsAction() {
        panelPresenter.dismiss()
        onAnalyticsRequested()
    }

    func performAuthenticationAction(for provider: ProviderID) {
        let action: ProviderAuthenticationAction
        switch provider {
        case .claude:
            action = .browserLogin(title: "Sign in with Claude")
        case .codex:
            action = .browserLogin(title: "Sign in with ChatGPT")
        case .cursor:
            action = .openCursorSpending(title: "Open Cursor Spending")
        }
        performPresentedAuthenticationAction(action, for: provider)
    }

    func performPresentedAuthenticationAction(_ action: ProviderAuthenticationAction, for provider: ProviderID) {
        panelPresenter.dismiss()
        performAuthenticationAction(action, for: provider)
    }

    private func performAuthenticationAction(_ action: ProviderAuthenticationAction, for provider: ProviderID) {
        switch action {
        case .browserLogin:
            onProviderLoginRequested(provider)
        case .openCursorSpending:
            _ = openCursorSpending()
        }
    }

    private func showSettings() {
        onSettingsRequested()
        settingsWindowController.showSettings()
    }
}

@MainActor
public final class MenuBarController: NSObject {
    private let configuration: ModuleConfiguration
    private let snapshotStore: ProviderSnapshotStore
    private let combinedSnapshotStore: CombinedSnapshotStore
    private let statusItemFactory: any StatusItemFactory
    private let globalMouseDownMonitor: any GlobalMouseDownMonitoring
    private let panelPresenter: any MenuPanelPresenting
    private let onModuleActivated: @MainActor (MenuModuleID) -> Void
    private let onRetryRequested: @MainActor () -> Void
    private let onProviderLoginRequested: @MainActor (ProviderID) -> Void
    private let onSettingsRequested: @MainActor () -> Void
    private let onAnalyticsRequested: @MainActor () -> Void
    private let openCursorSpending: @MainActor () -> Void
    private let settingsWindowController: SettingsWindowController
    private var statusItem: (any StatusItemHandle)?
    private var deepLinkStatusItem: (any StatusItemHandle)?
    private var cachedCombinedSnapshot: CombinedUsageSnapshot
    private var configurationObserver: NSObjectProtocol?
    private var providerObservationTask: Task<Void, Never>?
    private var combinedObservationTask: Task<Void, Never>?
    private var globalMouseDownMonitoringToken: (any GlobalMouseDownMonitoringToken)?
    private var panelPresentationGeneration: UInt64 = 0
    private var snapshotRequestGeneration: UInt64 = 0
    private var observationGeneration: UInt64 = 0
    private var activeMenuModule: MenuModuleID?

    public init(
        configuration: ModuleConfiguration,
        snapshotStore: ProviderSnapshotStore,
        combinedSnapshotStore: CombinedSnapshotStore = CombinedSnapshotStore(),
        actions: SettingsActions,
        notificationPreferences: QuotaNotificationPreferences,
        notificationService: QuotaNotificationService,
        statusItemFactory: any StatusItemFactory = AppKitStatusItemFactory(),
        globalMouseDownMonitor: any GlobalMouseDownMonitoring = AppKitGlobalMouseDownMonitor(),
        panelPresenter: any MenuPanelPresenting = AppKitMenuPanelPresenter(),
        onModuleActivated: @escaping @MainActor (MenuModuleID) -> Void = { _ in },
        onRetryRequested: @escaping @MainActor () -> Void = {},
        onProviderLoginRequested: @escaping @MainActor (ProviderID) -> Void = { _ in },
        onSettingsRequested: @escaping @MainActor () -> Void = {},
        onAnalyticsRequested: @escaping @MainActor () -> Void = {},
        openCursorSpending: @escaping @MainActor () -> Void = { _ = CursorSpendingAction.open() }
    ) {
        self.configuration = configuration
        self.snapshotStore = snapshotStore
        self.combinedSnapshotStore = combinedSnapshotStore
        self.statusItemFactory = statusItemFactory
        self.globalMouseDownMonitor = globalMouseDownMonitor
        self.panelPresenter = panelPresenter
        self.onModuleActivated = onModuleActivated
        self.onRetryRequested = onRetryRequested
        self.onProviderLoginRequested = onProviderLoginRequested
        self.onSettingsRequested = onSettingsRequested
        self.onAnalyticsRequested = onAnalyticsRequested
        self.openCursorSpending = openCursorSpending
        self.settingsWindowController = SettingsWindowController(
            configuration: configuration,
            actions: actions,
            notificationPreferences: notificationPreferences,
            notificationService: notificationService,
            openCursorSpending: openCursorSpending
        )
        self.cachedCombinedSnapshot = CombinedUsageSnapshot(
            system: nil, providers: [], capturedAt: .distantPast, systemAvailability: [:]
        )
        super.init()
        panelPresenter.onDismiss = { [weak self] in
            self?.panelDidDismiss()
        }
    }

    public convenience init(
        configuration: ModuleConfiguration,
        snapshotStore: ProviderSnapshotStore,
        combinedSnapshotStore: CombinedSnapshotStore = CombinedSnapshotStore(),
        loginCoordinator: ProviderLoginCoordinator,
        snapshotExportController: SnapshotExportController,
        notificationPreferences: QuotaNotificationPreferences,
        notificationService: QuotaNotificationService,
        statusItemFactory: any StatusItemFactory = AppKitStatusItemFactory(),
        globalMouseDownMonitor: any GlobalMouseDownMonitoring = AppKitGlobalMouseDownMonitor(),
        panelPresenter: any MenuPanelPresenting = AppKitMenuPanelPresenter(),
        onModuleActivated: @escaping @MainActor (MenuModuleID) -> Void = { _ in },
        onRetryRequested: @escaping @MainActor () -> Void = {},
        onProviderLoginRequested: @escaping @MainActor (ProviderID) -> Void = { _ in },
        onSettingsRequested: @escaping @MainActor () -> Void = {},
        onAnalyticsRequested: @escaping @MainActor () -> Void = {},
        openCursorSpending: @escaping @MainActor () -> Void = { _ = CursorSpendingAction.open() }
    ) {
        self.init(
            configuration: configuration,
            snapshotStore: snapshotStore,
            combinedSnapshotStore: combinedSnapshotStore,
            actions: SettingsActions(
                loginCoordinator: loginCoordinator,
                snapshotExportController: snapshotExportController
            ),
            notificationPreferences: notificationPreferences,
            notificationService: notificationService,
            statusItemFactory: statusItemFactory,
            globalMouseDownMonitor: globalMouseDownMonitor,
            panelPresenter: panelPresenter,
            onModuleActivated: onModuleActivated,
            onRetryRequested: onRetryRequested,
            onProviderLoginRequested: onProviderLoginRequested,
            onSettingsRequested: onSettingsRequested,
            onAnalyticsRequested: onAnalyticsRequested,
            openCursorSpending: openCursorSpending
        )
    }

    public var activeModuleIDs: [MenuModuleID] {
        statusItem == nil ? [] : [.overview]
    }

    public func refresh() async {
        let snapshots = await snapshotStore.snapshots()
        await combinedSnapshotStore.applyProviders(snapshots)
        let combined = await combinedSnapshotStore.snapshot()
        reconcile(using: combined)
    }

    public func startObserving() async {
        guard configurationObserver == nil, providerObservationTask == nil, combinedObservationTask == nil else { return }
        observationGeneration &+= 1
        let generation = observationGeneration
        let providerUpdates = await snapshotStore.updates()
        let combinedUpdates = await combinedSnapshotStore.updates()
        await refresh()
        configurationObserver = NotificationCenter.default.addObserver(
            forName: ModuleConfiguration.didChangeNotification,
            object: configuration,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.observationGeneration == generation else { return }
                self.reconcile(using: self.cachedCombinedSnapshot)
            }
        }
        providerObservationTask = Task { @MainActor [weak self] in
            for await snapshots in providerUpdates {
                guard !Task.isCancelled else { return }
                guard let self, self.observationGeneration == generation else { return }
                await self.combinedSnapshotStore.applyProviders(snapshots)
            }
        }
        combinedObservationTask = Task { @MainActor [weak self] in
            for await snapshot in combinedUpdates {
                guard !Task.isCancelled else { return }
                guard let self, self.observationGeneration == generation else { return }
                self.reconcile(using: snapshot)
            }
        }
    }

    public func stopObserving() {
        observationGeneration &+= 1
        dismissPanelAndCleanUp()
        providerObservationTask?.cancel()
        providerObservationTask = nil
        combinedObservationTask?.cancel()
        combinedObservationTask = nil
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
    }

    public func openOverview() {
        let item: any StatusItemHandle
        if let statusItem {
            item = statusItem
        } else if let deepLinkStatusItem {
            item = deepLinkStatusItem
        } else {
            let created = statusItemFactory.makeStatusItem()
            created.title = "Needlbar"
            deepLinkStatusItem = created
            item = created
        }
        snapshotRequestGeneration &+= 1
        showPanel(for: .overview, snapshot: cachedCombinedSnapshot, from: item)
    }

    private func reconcile(using snapshot: CombinedUsageSnapshot) {
        cachedCombinedSnapshot = snapshot
        let item: any StatusItemHandle
        if let statusItem {
            item = statusItem
        } else {
            let created = statusItemFactory.makeStatusItem()
            statusItem = created
            item = created
        }
        let rendered = MenuBarDashboardRenderer.render(
            snapshot: snapshot,
            configuration: configuration.systemMonitor,
            availableWidth: item.availableWidth
        )
        item.title = rendered.title
        item.action = { [weak self, weak item] in
            guard let self, let item else { return }
            self.activate(.overview, from: item)
        }
    }

    private func activate(_ module: MenuModuleID, from item: any StatusItemHandle) {
        onModuleActivated(module)
        snapshotRequestGeneration &+= 1
        let requestGeneration = snapshotRequestGeneration
        if panelPresenter.isShown, activeMenuModule == module {
            panelPresenter.dismiss()
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let snapshot = await self.combinedSnapshotStore.snapshot()
            guard !Task.isCancelled, self.snapshotRequestGeneration == requestGeneration else { return }
            self.showPanel(for: module, snapshot: snapshot, from: item)
        }
    }

    private func showPanel(
        for module: MenuModuleID,
        snapshot: CombinedUsageSnapshot,
        from item: any StatusItemHandle
    ) {
        if panelPresenter.isShown, activeMenuModule == module {
            panelPresenter.dismiss()
            return
        }
        guard module == .overview else { return }
        let view = AnyView(SystemDashboardPopoverView(
            snapshot: snapshot,
            configuration: configuration,
            onShowSettings: { [weak self] in self?.performSettingsAction() },
            onShowAnalytics: { [weak self] in self?.performAnalyticsAction() },
            onProviderAction: { [weak self] provider in
                self?.performAuthenticationAction(for: provider)
            }
        ))
        guard let anchor = item.presentationAnchor() else {
            dismissPanelAndCleanUp()
            return
        }
        cancelGlobalMouseDownMonitoring()
        let hostingController = NSHostingController(rootView: view)
        guard panelPresenter.present(hostingController, anchoredAt: anchor) else {
            dismissPanelAndCleanUp()
            return
        }
        activeMenuModule = module
        panelPresentationGeneration &+= 1
        let presentationGeneration = panelPresentationGeneration
        globalMouseDownMonitoringToken = globalMouseDownMonitor.start { [weak self] in
            guard let self,
                self.panelPresentationGeneration == presentationGeneration,
                self.panelPresenter.isShown
            else { return }
            self.panelPresenter.dismiss()
        }
    }

    private func cancelGlobalMouseDownMonitoring() {
        globalMouseDownMonitoringToken?.cancel()
        globalMouseDownMonitoringToken = nil
    }

    private func panelDidDismiss() {
        panelPresentationGeneration &+= 1
        snapshotRequestGeneration &+= 1
        cancelGlobalMouseDownMonitoring()
        activeMenuModule = nil
        if let temporary = deepLinkStatusItem {
            statusItemFactory.removeStatusItem(temporary)
            deepLinkStatusItem = nil
        }
    }

    private func dismissPanelAndCleanUp() {
        if panelPresenter.isShown {
            panelPresenter.dismiss()
        } else {
            panelDidDismiss()
        }
    }

    func performRetryAction() {
        onRetryRequested()
    }

    func performSettingsAction() {
        panelPresenter.dismiss()
        showSettings()
    }

    func performAnalyticsAction() {
        panelPresenter.dismiss()
        onAnalyticsRequested()
    }

    func performAuthenticationAction(for provider: ProviderID) {
        let action: ProviderAuthenticationAction
        switch provider {
        case .claude:
            action = .browserLogin(title: "Sign in with Claude")
        case .codex:
            action = .browserLogin(title: "Sign in with ChatGPT")
        case .cursor:
            action = .openCursorSpending(title: "Open Cursor Spending")
        }
        performPresentedAuthenticationAction(action, for: provider)
    }

    func performPresentedAuthenticationAction(_ action: ProviderAuthenticationAction, for provider: ProviderID) {
        panelPresenter.dismiss()
        switch action {
        case .browserLogin:
            onProviderLoginRequested(provider)
        case .openCursorSpending:
            _ = openCursorSpending()
        }
    }

    private func showSettings() {
        onSettingsRequested()
        settingsWindowController.showSettings()
    }
}

@MainActor
public final class AppKitStatusItemFactory: StatusItemFactory {
    private let statusBar: NSStatusBar

    public init(statusBar: NSStatusBar = .system) {
        self.statusBar = statusBar
    }

    public func makeStatusItem() -> any StatusItemHandle {
        AppKitStatusItemHandle(statusItem: statusBar.statusItem(withLength: NSStatusItem.variableLength))
    }

    public func removeStatusItem(_ statusItem: any StatusItemHandle) {
        guard let appKitStatusItem = statusItem as? AppKitStatusItemHandle else { return }
        statusBar.removeStatusItem(appKitStatusItem.statusItem)
    }
}

@MainActor
private final class AppKitStatusItemHandle: NSObject, StatusItemHandle {
    let statusItem: NSStatusItem
    var action: (@MainActor () -> Void)? {
        didSet {
            statusItem.button?.target = self
            statusItem.button?.action = #selector(performAction)
        }
    }

    var title: String {
        get { statusItem.button?.title ?? "" }
        set { statusItem.button?.title = newValue }
    }

    var availableWidth: Double {
        guard let screen = statusItem.button?.window?.screen else { return 400 }
        return min(400, max(120, screen.visibleFrame.width * 0.25))
    }

    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        super.init()
    }

    func presentationAnchor() -> StatusItemPresentationAnchor? {
        guard let button = statusItem.button,
              let window = button.window,
              let screen = window.screen else {
            return nil
        }
        let buttonFrameInScreen = window.convertToScreen(button.convert(button.bounds, to: nil))
        return StatusItemPresentationAnchor(
            buttonFrameInScreen: buttonFrameInScreen,
            visibleFrameInScreen: screen.visibleFrame
        )
    }

    @objc private func performAction() {
        action?()
    }
}
