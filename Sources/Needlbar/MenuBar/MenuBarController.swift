import AppKit
import NeedlbarCore
import SwiftUI

@MainActor
public protocol StatusItemHandle: AnyObject {
    var title: String { get set }
    var action: (@MainActor () -> Void)? { get set }
    func show(_ popover: NSPopover)
    func presentationAnchor() -> StatusItemPresentationAnchor?
}

public extension StatusItemHandle {
    func show(_ popover: NSPopover) {}
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
public final class MenuBarController: NSObject, NSPopoverDelegate {
    private let configuration: ModuleConfiguration
    private let snapshotStore: ProviderSnapshotStore
    private let statusItemFactory: any StatusItemFactory
    private let onModuleActivated: @MainActor (MenuModuleID) -> Void
    private let onRetryRequested: @MainActor () -> Void
    private let onProviderLoginRequested: @MainActor (ProviderID) -> Void
    private let onSettingsRequested: @MainActor () -> Void
    private let openCursorSpending: @MainActor () -> Void
    private let settingsWindowController: SettingsWindowController
    private let popover: NSPopover
    private let globalMouseDownMonitor: any GlobalMouseDownMonitoring
    private var globalMouseDownMonitoringToken: (any GlobalMouseDownMonitoringToken)?
    private var popoverPresentationGeneration: UInt64 = 0
    private var statusItems: [MenuModuleID: any StatusItemHandle] = [:]
    private var deepLinkStatusItem: (any StatusItemHandle)?
    private var cachedSnapshots: [ProviderSnapshot] = []
    private var configurationObserver: NSObjectProtocol?
    private var snapshotObservationTask: Task<Void, Never>?
    private var observationGeneration: UInt64 = 0

    public init(
        configuration: ModuleConfiguration,
        snapshotStore: ProviderSnapshotStore,
        loginCoordinator: ProviderLoginCoordinator,
        snapshotExportController: SnapshotExportController,
        notificationPreferences: QuotaNotificationPreferences,
        notificationService: QuotaNotificationService,
        statusItemFactory: any StatusItemFactory = AppKitStatusItemFactory(),
        globalMouseDownMonitor: any GlobalMouseDownMonitoring = AppKitGlobalMouseDownMonitor(),
        popover: NSPopover = NSPopover(),
        onModuleActivated: @escaping @MainActor (MenuModuleID) -> Void = { _ in },
        onRetryRequested: @escaping @MainActor () -> Void = {},
        onProviderLoginRequested: @escaping @MainActor (ProviderID) -> Void = { _ in },
        onSettingsRequested: @escaping @MainActor () -> Void = {},
        openCursorSpending: @escaping @MainActor () -> Void = { _ = CursorSpendingAction.open() }
    ) {
        self.configuration = configuration
        self.snapshotStore = snapshotStore
        self.statusItemFactory = statusItemFactory
        self.onModuleActivated = onModuleActivated
        self.onRetryRequested = onRetryRequested
        self.onProviderLoginRequested = onProviderLoginRequested
        self.onSettingsRequested = onSettingsRequested
        self.openCursorSpending = openCursorSpending
        self.popover = popover
        self.globalMouseDownMonitor = globalMouseDownMonitor
        self.settingsWindowController = SettingsWindowController(
            configuration: configuration,
            loginCoordinator: loginCoordinator,
            snapshotExportController: snapshotExportController,
            notificationPreferences: notificationPreferences,
            notificationService: notificationService,
            openCursorSpending: openCursorSpending
        )
        super.init()
        popover.delegate = self
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
        snapshotObservationTask?.cancel()
        snapshotObservationTask = nil
        cancelGlobalMouseDownMonitoring()
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
        showPopover(for: .overview, snapshots: cachedSnapshots, from: statusItem)
    }

    public func popoverDidClose(_ notification: Notification) {
        cancelGlobalMouseDownMonitoring()
        guard let temporary = deepLinkStatusItem else { return }
        statusItemFactory.removeStatusItem(temporary)
        deepLinkStatusItem = nil
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
        Task { [weak self] in
            guard let self else { return }
            let snapshots = await self.snapshotStore.snapshots()
            guard !Task.isCancelled else { return }
            self.showPopover(for: module, snapshots: snapshots, from: statusItem)
        }
    }

    private func showPopover(
        for module: MenuModuleID,
        snapshots: [ProviderSnapshot],
        from statusItem: any StatusItemHandle
    ) {
        let view: AnyView
        switch module {
        case .overview:
            view = AnyView(OverviewPopoverView(snapshots: snapshots, configuration: configuration) { [weak self] in
                self?.popover.performClose(nil)
                self?.showSettings()
            })
        case .claude, .codex, .cursor:
            guard let provider = module.provider,
                  let snapshot = snapshots.first(where: { $0.provider == provider }) else { return }
            view = AnyView(ProviderPopoverView(
                snapshot: snapshot,
                onRetry: { [weak self] in self?.onRetryRequested() },
                onAuthenticationAction: { [weak self] action in
                    self?.popover.performClose(nil)
                    self?.performAuthenticationAction(action, for: provider)
                }
            ))
        }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: view)
        popoverPresentationGeneration &+= 1
        let presentationGeneration = popoverPresentationGeneration
        globalMouseDownMonitoringToken?.cancel()
        globalMouseDownMonitoringToken = nil
        statusItem.show(popover)
        guard popover.isShown else { return }
        globalMouseDownMonitoringToken = globalMouseDownMonitor.start { [weak self] in
            guard let self,
                  self.popoverPresentationGeneration == presentationGeneration,
                  self.popover.isShown else { return }
            self.popover.performClose(nil)
        }
    }

    private func cancelGlobalMouseDownMonitoring() {
        popoverPresentationGeneration &+= 1
        globalMouseDownMonitoringToken?.cancel()
        globalMouseDownMonitoringToken = nil
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

    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        super.init()
    }

    func show(_ popover: NSPopover) {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: preferredPopoverEdge(isFlipped: button.isFlipped))
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

func preferredPopoverEdge(isFlipped: Bool) -> NSRectEdge {
    isFlipped ? .maxY : .minY
}
