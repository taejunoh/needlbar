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
    @Test func clickedStatusItemAnchorIsPassedToThePanelPresenter() async throws {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        let factory = FakeStatusItemFactory()
        let presenter = FakeMenuPanelPresenter()
        let monitor = FakeGlobalMouseDownMonitor()
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: ProviderSnapshotStore(),
            loginCoordinator: testLoginCoordinator(),
            statusItemFactory: factory,
            globalMouseDownMonitor: monitor,
            panelPresenter: presenter
        )

        await controller.refresh()
        let overview = try #require(factory.created.first)
        overview.performAction()

        #expect(await eventually { presenter.presentedAnchors.count == 1 })
        let anchor = try #require(presenter.presentedAnchors.first)
        #expect(anchor.buttonFrameInScreen == FakeStatusItemHandle.literalAnchor.buttonFrameInScreen)
        #expect(anchor.visibleFrameInScreen == FakeStatusItemHandle.literalAnchor.visibleFrameInScreen)
    }

    @Test func globalMonitorStartsOnlyAfterThePanelIsPresented() {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        let eventLog = FakeEventLog()
        let presenter = FakeMenuPanelPresenter(eventLog: eventLog)
        let monitor = FakeGlobalMouseDownMonitor(eventLog: eventLog)
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: ProviderSnapshotStore(),
            loginCoordinator: testLoginCoordinator(),
            statusItemFactory: FakeStatusItemFactory(),
            globalMouseDownMonitor: monitor,
            panelPresenter: presenter
        )

        controller.openOverview()

        #expect(eventLog.events == ["present", "monitor"])
        #expect(monitor.startCount == 1)
    }

    @Test func missingAnchorRemovesTemporaryDeepLinkItemWithoutStartingAMonitor() {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        configuration.overview = ModuleSettings(isEnabled: false, metric: .quotaRemaining)
        let factory = FakeStatusItemFactory()
        factory.nextPresentationAnchor = nil
        let monitor = FakeGlobalMouseDownMonitor()
        let presenter = FakeMenuPanelPresenter()
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: ProviderSnapshotStore(),
            loginCoordinator: testLoginCoordinator(),
            statusItemFactory: factory,
            globalMouseDownMonitor: monitor,
            panelPresenter: presenter
        )

        controller.openOverview()

        #expect(presenter.presentedAnchors.isEmpty)
        #expect(monitor.startCount == 0)
        #expect(factory.removed.count == 1)
    }

    @Test func failedPresentationRemovesTemporaryDeepLinkItemWithoutStartingAMonitor() {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        configuration.overview = ModuleSettings(isEnabled: false, metric: .quotaRemaining)
        let factory = FakeStatusItemFactory()
        let monitor = FakeGlobalMouseDownMonitor()
        let presenter = FakeMenuPanelPresenter(presentResult: false)
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: ProviderSnapshotStore(),
            loginCoordinator: testLoginCoordinator(),
            statusItemFactory: factory,
            globalMouseDownMonitor: monitor,
            panelPresenter: presenter
        )

        controller.openOverview()

        #expect(presenter.presentedAnchors.count == 1)
        #expect(monitor.startCount == 0)
        #expect(factory.removed.count == 1)
    }

    @Test func panelDismissalCancelsMonitoringAndRemovesTemporaryItemOnlyOnce() {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        configuration.overview = ModuleSettings(isEnabled: false, metric: .quotaRemaining)
        let factory = FakeStatusItemFactory()
        let monitor = FakeGlobalMouseDownMonitor()
        let presenter = FakeMenuPanelPresenter()
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: ProviderSnapshotStore(),
            loginCoordinator: testLoginCoordinator(),
            statusItemFactory: factory,
            globalMouseDownMonitor: monitor,
            panelPresenter: presenter
        )

        controller.openOverview()
        presenter.dismiss()
        presenter.dismiss()

        #expect(monitor.cancelCount == 1)
        #expect(factory.removed.count == 1)
    }

    @Test func staleGlobalCallbackCannotDismissANewerPresentation() async {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        let monitor = FakeGlobalMouseDownMonitor()
        let presenter = FakeMenuPanelPresenter()
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: ProviderSnapshotStore(),
            loginCoordinator: testLoginCoordinator(),
            statusItemFactory: FakeStatusItemFactory(),
            globalMouseDownMonitor: monitor,
            panelPresenter: presenter
        )

        controller.openOverview()
        let staleCallback = monitor.scheduleMouseDown(at: 0)
        controller.openOverview()
        controller.openOverview()
        await staleCallback.value

        #expect(monitor.startCount == 2)
        #expect(presenter.dismissCount == 1)
        #expect(presenter.isShown)
    }

    @Test func clickingTheShownModuleTogglesThePanelClosedWithoutAnotherPresentation() {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        let presenter = FakeMenuPanelPresenter()
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: ProviderSnapshotStore(),
            loginCoordinator: testLoginCoordinator(),
            statusItemFactory: FakeStatusItemFactory(),
            panelPresenter: presenter
        )

        controller.openOverview()
        controller.openOverview()

        #expect(presenter.presentCount == 1)
        #expect(presenter.dismissCount == 1)
        #expect(!presenter.isShown)
    }

    @Test func clickingADifferentModuleReanchorsTheExistingPresenter() async throws {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        configuration.claude = ModuleSettings(isEnabled: true, metric: .quotaRemaining)
        let store = ProviderSnapshotStore()
        await store.applyUsage(menuBarUsage(totalTokens: 1), for: .claude)
        let factory = FakeStatusItemFactory()
        let presenter = FakeMenuPanelPresenter()
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: store,
            loginCoordinator: testLoginCoordinator(),
            statusItemFactory: factory,
            panelPresenter: presenter
        )

        await controller.refresh()
        controller.openOverview()
        let claude = try #require(factory.created.last)
        claude.anchorForPresentation = StatusItemPresentationAnchor(
            buttonFrameInScreen: NSRect(x: 200, y: 500, width: 24, height: 24),
            visibleFrameInScreen: NSRect(x: 0, y: 0, width: 1_024, height: 768)
        )
        claude.performAction()

        #expect(await eventually { presenter.presentCount == 2 })
        #expect(presenter.dismissCount == 0)
        let anchor = try #require(presenter.presentedAnchors.last)
        #expect(anchor.buttonFrameInScreen == claude.anchorForPresentation?.buttonFrameInScreen)
    }

    @Test func staleSnapshotFetchCannotReopenAPanelAfterItIsToggledClosed() async throws {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        let factory = FakeStatusItemFactory()
        let presenter = FakeMenuPanelPresenter()
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: ProviderSnapshotStore(),
            loginCoordinator: testLoginCoordinator(),
            statusItemFactory: factory,
            panelPresenter: presenter
        )

        await controller.refresh()
        let overview = try #require(factory.created.first)
        overview.performAction()
        controller.openOverview()
        controller.openOverview()
        for _ in 0..<10 { await Task.yield() }

        #expect(presenter.presentCount == 1)
        #expect(!presenter.isShown)
    }

    @Test func dismissingTheCurrentPanelInvalidatesAnInFlightDifferentModuleSnapshotFetch() async throws {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        configuration.claude = ModuleSettings(isEnabled: true, metric: .quotaRemaining)
        let store = ProviderSnapshotStore()
        await store.applyUsage(menuBarUsage(totalTokens: 1), for: .claude)
        let factory = FakeStatusItemFactory()
        let presenter = FakeMenuPanelPresenter()
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: store,
            loginCoordinator: testLoginCoordinator(),
            statusItemFactory: factory,
            panelPresenter: presenter
        )

        await controller.refresh()
        controller.openOverview()
        let claude = try #require(factory.created.last)
        claude.performAction()
        presenter.dismiss()
        for _ in 0..<10 { await Task.yield() }

        #expect(presenter.presentCount == 1)
        #expect(!presenter.isShown)
    }

    @Test func overviewDeepLinkPresentsCachedOverviewAndRemovesItsTemporaryItemOnDismissal() {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        configuration.overview = ModuleSettings(isEnabled: false, metric: .quotaRemaining)
        let factory = FakeStatusItemFactory()
        let presenter = FakeMenuPanelPresenter()
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: ProviderSnapshotStore(),
            loginCoordinator: testLoginCoordinator(),
            statusItemFactory: factory,
            panelPresenter: presenter
        )

        let opened = OverviewDeepLink.open(URL(string: "needlbar://overview")!) {
            controller.openOverview()
        }
        presenter.dismiss()

        #expect(opened)
        #expect(presenter.presentCount == 1)
        #expect(factory.removed.count == 1)
        #expect(factory.removed.first === factory.created.first)
    }

    @Test func invalidOverviewDeepLinksDoNotPresentOrCreateStatusItems() {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        configuration.overview = ModuleSettings(isEnabled: false, metric: .quotaRemaining)
        let factory = FakeStatusItemFactory()
        let presenter = FakeMenuPanelPresenter()
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: ProviderSnapshotStore(),
            loginCoordinator: testLoginCoordinator(),
            statusItemFactory: factory,
            panelPresenter: presenter
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
        #expect(presenter.presentCount == 0)
    }

    @Test func settingsDismissesThePanelBeforeInvokingTheCallback() {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        let eventLog = FakeEventLog()
        let presenter = FakeMenuPanelPresenter(eventLog: eventLog)
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: ProviderSnapshotStore(),
            loginCoordinator: testLoginCoordinator(),
            panelPresenter: presenter,
            onSettingsRequested: { eventLog.events.append("settings") }
        )

        controller.openOverview()
        controller.performSettingsAction()

        #expect(eventLog.events.suffix(2) == ["dismiss", "settings"])
    }

    @Test func providerAuthenticationActionsDismissBeforeTheirCallbacks() {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        let eventLog = FakeEventLog()
        let presenter = FakeMenuPanelPresenter(eventLog: eventLog)
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: ProviderSnapshotStore(),
            loginCoordinator: testLoginCoordinator(),
            panelPresenter: presenter,
            onProviderLoginRequested: { provider in eventLog.events.append("login-\(provider.rawValue)") },
            openCursorSpending: { eventLog.events.append("cursor") }
        )

        for provider in [ProviderID.claude, .codex, .cursor] {
            presenter.markShownForTesting()
            controller.performAuthenticationAction(for: provider)
        }

        #expect(eventLog.events == [
            "dismiss", "login-claude",
            "dismiss", "login-codex",
            "dismiss", "cursor",
        ])
    }

    @Test func retryLeavesThePanelShown() {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        var retries = 0
        let presenter = FakeMenuPanelPresenter()
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: ProviderSnapshotStore(),
            loginCoordinator: testLoginCoordinator(),
            panelPresenter: presenter,
            onRetryRequested: { retries += 1 }
        )

        controller.openOverview()
        controller.performRetryAction()

        #expect(retries == 1)
        #expect(presenter.isShown)
        #expect(presenter.dismissCount == 0)
    }

    @Test func stopObservingDismissesShownPanelAndCancelsMonitoringOnlyOnce() {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        let monitor = FakeGlobalMouseDownMonitor()
        let presenter = FakeMenuPanelPresenter()
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: ProviderSnapshotStore(),
            loginCoordinator: testLoginCoordinator(),
            globalMouseDownMonitor: monitor,
            panelPresenter: presenter
        )

        controller.openOverview()
        controller.stopObserving()
        controller.stopObserving()

        #expect(presenter.dismissCount == 1)
        #expect(monitor.cancelCount == 1)
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
    panelPresenter: any MenuPanelPresenting = FakeMenuPanelPresenter(),
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
        panelPresenter: panelPresenter,
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
    var nextPresentationAnchor: StatusItemPresentationAnchor? = FakeStatusItemHandle.literalAnchor

    func makeStatusItem() -> any StatusItemHandle {
        let handle = FakeStatusItemHandle(presentationAnchor: nextPresentationAnchor)
        created.append(handle)
        return handle
    }

    func removeStatusItem(_ statusItem: any StatusItemHandle) {
        removed.append(statusItem as! FakeStatusItemHandle)
    }
}

@MainActor
private final class FakeStatusItemHandle: StatusItemHandle {
    static let literalAnchor = StatusItemPresentationAnchor(
        buttonFrameInScreen: NSRect(x: 0, y: 0, width: 24, height: 24),
        visibleFrameInScreen: NSRect(x: 0, y: 0, width: 1_024, height: 768)
    )
    var anchorForPresentation: StatusItemPresentationAnchor?
    var title = ""
    var action: (@MainActor () -> Void)? {
        didSet { actionAssignmentCount += 1 }
    }
    private(set) var actionAssignmentCount = 0

    init(presentationAnchor: StatusItemPresentationAnchor?) {
        anchorForPresentation = presentationAnchor
    }

    func performAction() {
        action?()
    }

    func presentationAnchor() -> StatusItemPresentationAnchor? {
        anchorForPresentation
    }
}

@MainActor
private final class FakeEventLog {
    var events: [String] = []
}

@MainActor
private final class FakeMenuPanelPresenter: MenuPanelPresenting {
    private let presentResult: Bool
    private let eventLog: FakeEventLog?
    private(set) var presentCount = 0
    private(set) var dismissCount = 0
    private(set) var presentedAnchors: [StatusItemPresentationAnchor] = []
    private(set) var isShown = false
    var onDismiss: (@MainActor () -> Void)?

    init(presentResult: Bool = true, eventLog: FakeEventLog? = nil) {
        self.presentResult = presentResult
        self.eventLog = eventLog
    }

    func present(
        _ contentViewController: NSViewController,
        anchoredAt anchor: StatusItemPresentationAnchor
    ) -> Bool {
        presentCount += 1
        presentedAnchors.append(anchor)
        eventLog?.events.append("present")
        guard presentResult else { return false }
        isShown = true
        return true
    }

    func dismiss() {
        guard isShown else { return }
        dismissCount += 1
        isShown = false
        eventLog?.events.append("dismiss")
        onDismiss?()
    }

    func markShownForTesting() {
        isShown = true
    }
}

@MainActor
private final class FakeGlobalMouseDownMonitor: GlobalMouseDownMonitoring {
    private let eventLog: FakeEventLog?
    private(set) var startCount = 0
    private(set) var cancelCount = 0
    private(set) var callbackInvocationCount = 0
    private var callbacks: [(@MainActor () -> Void)?] = []

    init(eventLog: FakeEventLog? = nil) {
        self.eventLog = eventLog
    }

    func start(_ callback: @escaping @MainActor () -> Void) -> any GlobalMouseDownMonitoringToken {
        startCount += 1
        eventLog?.events.append("monitor")
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
