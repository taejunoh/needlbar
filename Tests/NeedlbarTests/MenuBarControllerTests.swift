import AppKit
import Foundation
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

@MainActor
@Test func defaultConfigurationCreatesOnlyTheOverviewStatusItem() async {
    let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
    let factory = FakeStatusItemFactory()
    let controller = makeMenuBarController(
        configuration: configuration,
        snapshotStore: ProviderSnapshotStore(),
        loginCoordinator: testLoginCoordinator(),
        statusItemFactory: factory
    )

    await controller.refresh()

    #expect(controller.activeModuleIDs == [.overview])
    #expect(factory.created.count == 1)
    #expect(factory.created[0].title == "AI —")
}

@MainActor
@Test func enablingClaudeAddsItWithoutRecreatingOverview() async throws {
    let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
    let factory = FakeStatusItemFactory()
    let controller = makeMenuBarController(
        configuration: configuration,
        snapshotStore: ProviderSnapshotStore(),
        loginCoordinator: testLoginCoordinator(),
        statusItemFactory: factory
    )
    await controller.refresh()
    let overview = try #require(factory.created.first)

    configuration.claude = ModuleSettings(isEnabled: true, metric: .quotaRemaining)
    await controller.refresh()

    #expect(controller.activeModuleIDs == [.overview, .claude])
    #expect(factory.created.count == 2)
    #expect(factory.created[0] === overview)
    #expect(factory.removed.isEmpty)
}

@MainActor
@Test func disablingAModuleRemovesOnlyThatStatusItem() async throws {
    let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
    configuration.claude = ModuleSettings(isEnabled: true, metric: .quotaRemaining)
    let factory = FakeStatusItemFactory()
    let controller = makeMenuBarController(
        configuration: configuration,
        snapshotStore: ProviderSnapshotStore(),
        loginCoordinator: testLoginCoordinator(),
        statusItemFactory: factory
    )
    await controller.refresh()
    let overview = try #require(factory.created.first)
    let claude = try #require(factory.created.last)

    configuration.claude = ModuleSettings(isEnabled: false, metric: .quotaRemaining)
    await controller.refresh()

    #expect(controller.activeModuleIDs == [.overview])
    #expect(factory.created.count == 2)
    #expect(factory.removed.count == 1)
    #expect(factory.removed[0] === claude)
    #expect(factory.created[0] === overview)
}

@MainActor
@Test func anExistingModuleUpdatesItsTitleAndActionWithoutReplacement() async throws {
    let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
    configuration.overview = ModuleSettings(isEnabled: true, metric: .tokensToday)
    let store = ProviderSnapshotStore()
    let factory = FakeStatusItemFactory()
    var activatedModules: [MenuModuleID] = []
    let controller = makeMenuBarController(
        configuration: configuration,
        snapshotStore: store,
        loginCoordinator: testLoginCoordinator(),
        statusItemFactory: factory,
        onModuleActivated: { activatedModules.append($0) }
    )
    await controller.refresh()
    let overview = try #require(factory.created.first)
    let initialActionAssignments = overview.actionAssignmentCount

    await store.applyUsage(menuBarUsage(totalTokens: 1_420), for: .claude)
    await controller.refresh()
    overview.performAction()

    #expect(factory.created.count == 1)
    #expect(factory.removed.isEmpty)
    #expect(overview.title == "AI 1.42K")
    #expect(overview.actionAssignmentCount > initialActionAssignments)
    #expect(activatedModules == [.overview])
}

@MainActor
@Test func observingConfigurationChangesReconcilesEnabledModules() async {
    let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
    let factory = FakeStatusItemFactory()
    let controller = makeMenuBarController(
        configuration: configuration,
        snapshotStore: ProviderSnapshotStore(),
        loginCoordinator: testLoginCoordinator(),
        statusItemFactory: factory
    )
    await controller.startObserving()
    defer { controller.stopObserving() }

    configuration.codex = ModuleSettings(isEnabled: true, metric: .costToday)

    let observedChange = await eventually {
        controller.activeModuleIDs == [.overview, .codex] && factory.created.count == 2
    }
    #expect(observedChange)
}

@MainActor
@Test func observingSnapshotChangesRendersTheUpdatedTitle() async throws {
    let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
    configuration.overview = ModuleSettings(isEnabled: true, metric: .tokensToday)
    let store = ProviderSnapshotStore()
    let factory = FakeStatusItemFactory()
    let controller = makeMenuBarController(
        configuration: configuration,
        snapshotStore: store,
        loginCoordinator: testLoginCoordinator(),
        statusItemFactory: factory
    )
    await controller.startObserving()
    defer { controller.stopObserving() }
    let overview = try #require(factory.created.first)

    await store.applyUsage(menuBarUsage(totalTokens: 1_420), for: .claude)

    #expect(await eventually { overview.title == "AI 1.42K" })
}

@MainActor
@Test func stoppingObservationIgnoresAnAlreadyQueuedConfigurationUpdate() async {
    let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
    let factory = FakeStatusItemFactory()
    let controller = makeMenuBarController(
        configuration: configuration,
        snapshotStore: ProviderSnapshotStore(),
        loginCoordinator: testLoginCoordinator(),
        statusItemFactory: factory
    )
    await controller.startObserving()

    configuration.claude = ModuleSettings(isEnabled: true, metric: .quotaRemaining)
    controller.stopObserving()
    for _ in 0..<10 { await Task.yield() }

    #expect(controller.activeModuleIDs == [.overview])
    #expect(factory.created.count == 1)
}

@MainActor
@Test func authenticationActionsRouteClaudeAndCodexToTheLoginCallbackExactlyOnce() {
    let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
    var requestedProviders: [ProviderID] = []
    let controller = makeMenuBarController(
        configuration: configuration,
        snapshotStore: ProviderSnapshotStore(),
        loginCoordinator: testLoginCoordinator(),
        onProviderLoginRequested: { requestedProviders.append($0) }
    )

    controller.performAuthenticationAction(for: .claude)
    controller.performAuthenticationAction(for: .codex)

    #expect(requestedProviders == [.claude, .codex])
}

@MainActor
@Test func cursorSpendingActionOpensFixedDashboardWithoutLoginOrSettings() {
    let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
    var requestedProviders: [ProviderID] = []
    var settingsRequests = 0
    var openedURLs: [URL] = []
    let controller = makeMenuBarController(
        configuration: configuration,
        snapshotStore: ProviderSnapshotStore(),
        loginCoordinator: testLoginCoordinator(),
        onProviderLoginRequested: { requestedProviders.append($0) },
        onSettingsRequested: { settingsRequests += 1 },
        openCursorSpending: {
            _ = CursorSpendingAction.open { url in
                openedURLs.append(url)
                return true
            }
        }
    )

    controller.performAuthenticationAction(for: .cursor)

    #expect(requestedProviders.isEmpty)
    #expect(settingsRequests == 0)
    #expect(openedURLs == [URL(string: "https://cursor.com/dashboard/spending")!])
}

@Suite("MenuBarControllerTests")
@MainActor
struct MenuBarControllerTests {
    @Test func flippedPopoverAnchorUsesMaximumYEdge() {
        #expect(preferredPopoverEdge(isFlipped: true) == .maxY)
    }

    @Test func nonFlippedPopoverAnchorUsesMinimumYEdge() {
        #expect(preferredPopoverEdge(isFlipped: false) == .minY)
    }

    @Test func showingPopoverInstallsGlobalMouseDownMonitor() async {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        let factory = FakeStatusItemFactory()
        let monitor = FakeGlobalMouseDownMonitor()
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: ProviderSnapshotStore(),
            loginCoordinator: testLoginCoordinator(),
            statusItemFactory: factory,
            globalMouseDownMonitor: monitor
        )

        await controller.refresh()
        controller.openOverview()

        #expect(monitor.startCount == 1)
    }

    @Test func globalMouseDownCallbackClosesShownPopover() async {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        let monitor = FakeGlobalMouseDownMonitor()
        let popover = SpyPopover()
        popover.shownForTesting = true
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: ProviderSnapshotStore(),
            loginCoordinator: testLoginCoordinator(),
            statusItemFactory: FakeStatusItemFactory(),
            globalMouseDownMonitor: monitor,
            popover: popover
        )

        controller.openOverview()
        await monitor.sendMouseDown()

        #expect(popover.performCloseCount == 1)
    }

    @Test func globalMouseDownCallbackLeavesHiddenPopoverClosed() async {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        let monitor = FakeGlobalMouseDownMonitor()
        let popover = SpyPopover()
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: ProviderSnapshotStore(),
            loginCoordinator: testLoginCoordinator(),
            statusItemFactory: FakeStatusItemFactory(),
            globalMouseDownMonitor: monitor,
            popover: popover
        )

        controller.openOverview()
        popover.shownForTesting = false
        await monitor.sendMouseDown()

        #expect(popover.performCloseCount == 0)
    }

    @Test func popoverDidCloseCancelsGlobalMouseDownMonitorAndTemporaryItem() {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        configuration.overview = ModuleSettings(isEnabled: false, metric: .quotaRemaining)
        let factory = FakeStatusItemFactory()
        let monitor = FakeGlobalMouseDownMonitor()
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: ProviderSnapshotStore(),
            loginCoordinator: testLoginCoordinator(),
            statusItemFactory: factory,
            globalMouseDownMonitor: monitor
        )

        controller.openOverview()
        controller.popoverDidClose(Notification(name: .init("testPopoverClosed")))
        controller.popoverDidClose(Notification(name: .init("testPopoverClosedAgain")))

        #expect(monitor.cancelCount == 1)
        #expect(factory.removed.count == 1)
    }

    @Test func stopObservingCancelsGlobalMouseDownMonitor() {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        let monitor = FakeGlobalMouseDownMonitor()
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: ProviderSnapshotStore(),
            loginCoordinator: testLoginCoordinator(),
            statusItemFactory: FakeStatusItemFactory(),
            globalMouseDownMonitor: monitor
        )

        controller.openOverview()
        controller.stopObserving()

        #expect(monitor.cancelCount == 1)
    }

    @Test func showingAgainReplacesPreviousGlobalMouseDownMonitor() {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        let monitor = FakeGlobalMouseDownMonitor()
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: ProviderSnapshotStore(),
            loginCoordinator: testLoginCoordinator(),
            statusItemFactory: FakeStatusItemFactory(),
            globalMouseDownMonitor: monitor
        )

        controller.openOverview()
        controller.openOverview()

        #expect(monitor.startCount == 2)
        #expect(monitor.cancelCount == 1)
    }

    @Test func staleMouseDownCallbackFromPreviousPresentationDoesNotCloseCurrentPopover() async {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        let monitor = FakeGlobalMouseDownMonitor()
        let popover = SpyPopover()
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: ProviderSnapshotStore(),
            loginCoordinator: testLoginCoordinator(),
            statusItemFactory: FakeStatusItemFactory(),
            globalMouseDownMonitor: monitor,
            popover: popover
        )

        controller.openOverview()
        let staleCallback = monitor.scheduleMouseDown(at: 0)
        controller.openOverview()
        #expect(monitor.startCount == 2)
        #expect(popover.isShown)
        await staleCallback.value
        #expect(monitor.callbackInvocationCount == 1)

        #expect(popover.performCloseCount == 0)
    }

    @Test func hiddenPopoverDoesNotInstallGlobalMouseDownMonitor() {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        let monitor = FakeGlobalMouseDownMonitor()
        let popover = SpyPopover(markShownOnShow: false)
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: ProviderSnapshotStore(),
            loginCoordinator: testLoginCoordinator(),
            statusItemFactory: FakeStatusItemFactory(),
            globalMouseDownMonitor: monitor,
            popover: popover
        )

        controller.openOverview()

        #expect(monitor.startCount == 0)
    }

    @Test func overviewDeepLinkShowsCachedOverviewWhenTheModuleIsDisabled() {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        configuration.overview = ModuleSettings(isEnabled: false, metric: .quotaRemaining)
        let factory = FakeStatusItemFactory()
        var activatedModules: [MenuModuleID] = []
        var retries = 0
        var loginRequests = 0
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: ProviderSnapshotStore(),
            loginCoordinator: testLoginCoordinator(),
            statusItemFactory: factory,
            onModuleActivated: { activatedModules.append($0) },
            onRetryRequested: { retries += 1 },
            onProviderLoginRequested: { _ in loginRequests += 1 }
        )

        let opened = OverviewDeepLink.open(URL(string: "needlbar://overview")!) {
            controller.openOverview()
        }

        #expect(opened)
        #expect(factory.created.count == 1)
        #expect(factory.created[0].showCount == 1)
        #expect(activatedModules.isEmpty)
        #expect(retries == 0)
        #expect(loginRequests == 0)

        controller.popoverDidClose(Notification(name: .init("testPopoverClosed")))

        #expect(factory.removed.count == 1)
        #expect(factory.removed[0] === factory.created[0])
    }

    @Test func invalidOverviewDeepLinksDoNotShowOrRefreshOrLogin() {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        configuration.overview = ModuleSettings(isEnabled: false, metric: .quotaRemaining)
        let factory = FakeStatusItemFactory()
        var activatedModules: [MenuModuleID] = []
        var retries = 0
        var loginRequests = 0
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: ProviderSnapshotStore(),
            loginCoordinator: testLoginCoordinator(),
            statusItemFactory: factory,
            onModuleActivated: { activatedModules.append($0) },
            onRetryRequested: { retries += 1 },
            onProviderLoginRequested: { _ in loginRequests += 1 }
        )

        for value in [
            "needlbar://overview?refresh=1",
            "needlbar://overview/",
            "needlbar://user@overview",
            "needlbar://overview:1",
        ] {
            let opened = OverviewDeepLink.open(URL(string: value)!) {
                controller.openOverview()
            }
            #expect(!opened)
        }

        #expect(factory.created.isEmpty)
        #expect(activatedModules.isEmpty)
        #expect(retries == 0)
        #expect(loginRequests == 0)
    }
}

private func freshMenuBarDefaults() -> UserDefaults {
    let suiteName = "MenuBarControllerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@MainActor
private func testLoginCoordinator() -> ProviderLoginCoordinator {
    ProviderLoginCoordinator(refreshQuota: { _ in false })
}

@MainActor
private func makeMenuBarController(
    configuration: ModuleConfiguration,
    snapshotStore: ProviderSnapshotStore,
    loginCoordinator: ProviderLoginCoordinator,
    statusItemFactory: any StatusItemFactory = AppKitStatusItemFactory(),
    globalMouseDownMonitor: any GlobalMouseDownMonitoring = FakeGlobalMouseDownMonitor(),
    popover: NSPopover = SpyPopover(),
    onModuleActivated: @escaping @MainActor (MenuModuleID) -> Void = { _ in },
    onRetryRequested: @escaping @MainActor () -> Void = {},
    onProviderLoginRequested: @escaping @MainActor (ProviderID) -> Void = { _ in },
    onSettingsRequested: @escaping @MainActor () -> Void = {},
    openCursorSpending: @escaping @MainActor () -> Void = {}
) -> MenuBarController {
    let notificationPreferences = QuotaNotificationPreferences(defaults: freshMenuBarDefaults())
    let notificationService = QuotaNotificationService(
        store: snapshotStore,
        preferences: notificationPreferences
    )
    return MenuBarController(
        configuration: configuration,
        snapshotStore: snapshotStore,
        loginCoordinator: loginCoordinator,
        snapshotExportController: SnapshotExportController(
            captureSource: ProviderSnapshotStore(),
            savePanelPresenter: CancellingSavePanelPresenter(),
            coreExportAction: FailingCoreExportAction(),
            captureClock: Date.init
        ),
        notificationPreferences: notificationPreferences,
        notificationService: notificationService,
        statusItemFactory: statusItemFactory,
        globalMouseDownMonitor: globalMouseDownMonitor,
        popover: popover,
        onModuleActivated: onModuleActivated,
        onRetryRequested: onRetryRequested,
        onProviderLoginRequested: onProviderLoginRequested,
        onSettingsRequested: onSettingsRequested,
        openCursorSpending: openCursorSpending
    )
}

@MainActor
private final class CancellingSavePanelPresenter: SavePanelPresenter {
    func selectDestination(defaultFilename _: String) -> URL? {
        nil
    }
}

private struct FailingCoreExportAction: CoreExportAction {
    func export(_ capture: ExportCapture, to destination: URL) async throws -> AtomicWriteResult {
        throw SnapshotFileWriteError.writeFailed
    }
}

private func menuBarUsage(totalTokens: UInt64) -> UsageSnapshot {
    let today = UsagePeriod(
        inputTokens: totalTokens,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheWriteTokens: 0,
        totalTokens: totalTokens,
        estimatedCostUSD: 0
    )
    return UsageSnapshot(
        inputTokens: totalTokens,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheWriteTokens: 0,
        totalTokens: totalTokens,
        estimatedCostUSD: 0,
        today: today,
        last7Days: today,
        last30Days: today
    )
}

@MainActor
private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<100 {
        if condition() { return true }
        await Task.yield()
    }
    return false
}

@MainActor
private final class FakeStatusItemFactory: StatusItemFactory {
    var created: [FakeStatusItemHandle] = []
    var removed: [FakeStatusItemHandle] = []

    func makeStatusItem() -> any StatusItemHandle {
        let handle = FakeStatusItemHandle()
        created.append(handle)
        return handle
    }

    func removeStatusItem(_ statusItem: any StatusItemHandle) {
        removed.append(statusItem as! FakeStatusItemHandle)
    }
}

@MainActor
private final class FakeStatusItemHandle: StatusItemHandle {
    let fixedPresentationAnchor = StatusItemPresentationAnchor(
        buttonFrameInScreen: NSRect(x: 0, y: 0, width: 24, height: 24),
        visibleFrameInScreen: NSRect(x: 0, y: 0, width: 1_024, height: 768)
    )
    var title = ""
    var action: (@MainActor () -> Void)? {
        didSet { actionAssignmentCount += 1 }
    }
    private(set) var actionAssignmentCount = 0
    private(set) var showCount = 0

    func performAction() {
        action?()
    }

    func show(_ popover: NSPopover) {
        showCount += 1
        (popover as? SpyPopover)?.markShownIfConfigured()
    }

    func presentationAnchor() -> StatusItemPresentationAnchor? {
        fixedPresentationAnchor
    }
}

@MainActor
private final class FakeGlobalMouseDownMonitor: GlobalMouseDownMonitoring {
    private(set) var startCount = 0
    private(set) var cancelCount = 0
    private(set) var callbackInvocationCount = 0
    private var callbacks: [(@MainActor () -> Void)?] = []

    func start(_ callback: @escaping @MainActor () -> Void) -> any GlobalMouseDownMonitoringToken {
        startCount += 1
        callbacks.append { [weak self] in
            self?.callbackInvocationCount += 1
            callback()
        }
        return Token { [weak self] in
            self?.cancelCount += 1
        }
    }

    func sendMouseDown(at index: Int = 0) async {
        await scheduleMouseDown(at: index).value
    }

    func scheduleMouseDown(at index: Int) -> Task<Void, Never> {
        Task { @MainActor [callbacks] in
            callbacks[index]?()
        }
    }

    private final class Token: GlobalMouseDownMonitoringToken {
        private let onCancel: () -> Void
        private var isCancelled = false

        init(onCancel: @escaping () -> Void) {
            self.onCancel = onCancel
        }

        func cancel() {
            guard !isCancelled else { return }
            isCancelled = true
            onCancel()
        }
    }
}

@MainActor
private final class SpyPopover: NSPopover {
    private let markShownOnShow: Bool
    var shownForTesting = false
    private(set) var performCloseCount = 0

    init(markShownOnShow: Bool = true) {
        self.markShownOnShow = markShownOnShow
        super.init()
    }

    required init?(coder: NSCoder) {
        self.markShownOnShow = true
        super.init(coder: coder)
    }

    func markShownIfConfigured() {
        if markShownOnShow {
            shownForTesting = true
        }
    }

    override var isShown: Bool { shownForTesting }

    override func performClose(_ sender: Any?) {
        performCloseCount += 1
        shownForTesting = false
        super.performClose(sender)
    }
}
