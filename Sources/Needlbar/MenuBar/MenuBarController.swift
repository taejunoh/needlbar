import AppKit
import NeedlbarCore

@MainActor
public protocol StatusItemHandle: AnyObject {
    var title: String { get set }
    var action: (@MainActor () -> Void)? { get set }
}

@MainActor
public protocol StatusItemFactory: AnyObject {
    func makeStatusItem() -> any StatusItemHandle
    func removeStatusItem(_ statusItem: any StatusItemHandle)
}

@MainActor
public final class MenuBarController {
    private let configuration: ModuleConfiguration
    private let snapshotStore: ProviderSnapshotStore
    private let statusItemFactory: any StatusItemFactory
    private let onModuleActivated: @MainActor (MenuModuleID) -> Void
    private var statusItems: [MenuModuleID: any StatusItemHandle] = [:]
    private var cachedSnapshots: [ProviderSnapshot] = []
    private var configurationObserver: NSObjectProtocol?
    private var snapshotObservationTask: Task<Void, Never>?
    private var observationGeneration: UInt64 = 0

    public init(
        configuration: ModuleConfiguration,
        snapshotStore: ProviderSnapshotStore,
        statusItemFactory: any StatusItemFactory = AppKitStatusItemFactory(),
        onModuleActivated: @escaping @MainActor (MenuModuleID) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.snapshotStore = snapshotStore
        self.statusItemFactory = statusItemFactory
        self.onModuleActivated = onModuleActivated
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
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
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
            statusItem.action = { [onModuleActivated] in
                onModuleActivated(module.id)
            }
        }
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

    @objc private func performAction() {
        action?()
    }
}
