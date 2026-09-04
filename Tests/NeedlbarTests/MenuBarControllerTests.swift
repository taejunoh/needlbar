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
    #expect(factory.created[0].title.contains("CPU —"))
}

@MainActor
@Test func controllerPassesStructuredDashboardWithoutReplacingHandle() async throws {
    let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
    let factory = FakeStatusItemFactory()
    let controller = makeMenuBarController(
        configuration: configuration,
        snapshotStore: ProviderSnapshotStore(),
        loginCoordinator: testLoginCoordinator(),
        statusItemFactory: factory
    )

    await controller.refresh()
    let item = try #require(factory.created.last)
    let result = try #require(item.dashboardResults.last)

    #expect(!result.segments.isEmpty)
    #expect(item.tooltip == result.tooltip)
    #expect(item.accessibilityLabel == result.tooltip)
    #expect(item.action != nil)
    #expect(item.presentationAnchor() == FakeStatusItemHandle.literalAnchor)

    await controller.refresh()

    #expect(factory.created.count == 1)
    #expect(factory.created[0] === item)
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

    #expect(controller.activeModuleIDs == [.overview])
    #expect(factory.created.count == 1)
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
    #expect(factory.created.count == 1)
    #expect(factory.removed.isEmpty)
    #expect(factory.created[0] === overview)
}

@MainActor
@Test func anExistingModuleUpdatesItsTitleAndActionWithoutReplacement() async throws {
    let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
    configuration.overview = ModuleSettings(isEnabled: true, metric: .tokensToday)
    var monitor = configuration.systemMonitor
    monitor.ai[.claude] = AIProviderDisplayPreference(metric: .usage)
    configuration.setSystemMonitor(monitor)
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
    #expect(overview.title.contains("AI CL 1.42K"))
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

    var monitor = configuration.systemMonitor
    monitor.visibleModules = [.cpu]
    configuration.setSystemMonitor(monitor)

    let observedChange = await eventually {
        controller.activeModuleIDs == [.overview] && factory.created.count == 1
    }
    #expect(observedChange)
}

@MainActor
@Test func observingSnapshotChangesRendersTheUpdatedTitle() async throws {
    let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
    configuration.overview = ModuleSettings(isEnabled: true, metric: .tokensToday)
    var monitor = configuration.systemMonitor
    monitor.ai[.claude] = AIProviderDisplayPreference(metric: .usage)
    configuration.setSystemMonitor(monitor)
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

    #expect(await eventually { overview.title.contains("AI CL 1.42K") })
}

@MainActor
@Test func observingCombinedSystemSnapshotRendersCPUInTheSingleDashboardItem() async throws {
    let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
    let combinedStore = CombinedSnapshotStore()
    let factory = FakeStatusItemFactory()
    let controller = makeMenuBarController(
        configuration: configuration,
        snapshotStore: ProviderSnapshotStore(),
        combinedSnapshotStore: combinedStore,
        loginCoordinator: testLoginCoordinator(),
        statusItemFactory: factory
    )
    await controller.startObserving()
    defer { controller.stopObserving() }
    let item = try #require(factory.created.first)

    await combinedStore.applySystem(
        SystemMetricsSnapshot(
            capturedAt: Date(timeIntervalSince1970: 10_000),
            cpu: .init(totalUsage: MetricPercentage(24), perCoreUsage: []),
            memory: .init(usedBytes: nil, freeBytes: nil, swapUsedBytes: nil, pressure: nil),
            disks: [],
            network: .init(
                uploadBytesPerSecond: nil, downloadBytesPerSecond: nil,
                localIPAddresses: [], publicIPAddress: nil
            ),
            battery: .init(level: nil, isCharging: nil, health: nil),
            availability: [.cpu: .fresh(capturedAt: Date(timeIntervalSince1970: 10_000))]
        ),
        at: Date(timeIntervalSince1970: 10_000)
    )

    #expect(await eventually { item.title.contains("CPU 24%") })
}

@MainActor
@Test func liveCombinedUpdatesRefreshTheDashboardModelWithoutRepresentingThePanel() async throws {
    let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
    let combinedStore = CombinedSnapshotStore()
    let factory = FakeStatusItemFactory()
    let presenter = FakeMenuPanelPresenter()
    let controller = makeMenuBarController(
        configuration: configuration,
        snapshotStore: ProviderSnapshotStore(),
        combinedSnapshotStore: combinedStore,
        loginCoordinator: testLoginCoordinator(),
        statusItemFactory: factory,
        panelPresenter: presenter
    )
    await controller.startObserving()
    defer { controller.stopObserving() }
    let item = try #require(factory.created.first)
    item.performAction()
    #expect(await eventually { presenter.presentCount == 1 && presenter.isShown })

    let firstDate = Date(timeIntervalSince1970: 10_000)
    await combinedStore.applySystem(
        SystemMetricsSnapshot(
            capturedAt: firstDate,
            cpu: .init(totalUsage: MetricPercentage(24), perCoreUsage: []),
            memory: .init(usedBytes: nil, freeBytes: nil, swapUsedBytes: nil, pressure: nil),
            disks: [],
            network: .init(uploadBytesPerSecond: nil, downloadBytesPerSecond: nil, localIPAddresses: [], publicIPAddress: nil),
            battery: .init(level: nil, isCharging: nil, health: nil),
            availability: [.cpu: .fresh(capturedAt: firstDate)]
        ),
        at: firstDate
    )

    #expect(await eventually { item.title.contains("CPU 24%") })
    #expect(presenter.presentCount == 1)
    #expect(presenter.isShown)
    #expect(presenter.resizedSizes.isEmpty)
}

@MainActor
@Test func overviewUsesMeasured340PointContentBeforeFirstPresentation() async throws {
    let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
    let combinedStore = CombinedSnapshotStore(now: Date(timeIntervalSince1970: 10_000))
    let presenter = FakeMenuPanelPresenter()
    let controller = makeMenuBarController(
        configuration: configuration,
        snapshotStore: ProviderSnapshotStore(),
        combinedSnapshotStore: combinedStore,
        loginCoordinator: testLoginCoordinator(),
        statusItemFactory: FakeStatusItemFactory(),
        panelPresenter: presenter
    )
    await controller.refresh()
    let snapshot = await combinedStore.snapshot()
    let expectedModel = SystemDashboardModel(snapshot: snapshot, configuration: configuration.systemMonitor)
    let naturalHeight = try #require(SystemDashboardPopoverMeasurement.naturalHeight(for: expectedModel))
    let expectedHeight = SystemDashboardPanelSizing.height(
        naturalContentHeight: naturalHeight,
        visibleScreenHeight: FakeStatusItemHandle.literalAnchor.visibleFrameInScreen.height
    )

    controller.openOverview()

    #expect(presenter.presentCount == 1)
    #expect(presenter.presentedContentSizes.first == NSSize(width: 340, height: expectedHeight))
}

@MainActor
@Test func visibleModuleChangeResizesWithoutRepresentingAndKeepsAnchor() async throws {
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
    await controller.startObserving()
    defer { controller.stopObserving() }
    let item = try #require(factory.created.first)
    item.performAction()
    #expect(await eventually { presenter.presentCount == 1 && presenter.isShown })

    var monitor = configuration.systemMonitor
    monitor.visibleModules.insert(.disk)
    configuration.setSystemMonitor(monitor)

    #expect(await eventually { presenter.resizedSizes.count == 1 })
    #expect(presenter.presentCount == 1)
    #expect(presenter.resizedSizes.first?.width == 340)
    #expect(presenter.resizedAnchors == presenter.presentedAnchors)
    let installedController = try #require(presenter.presentedContentViewControllers.first)
    let resizedHeight = try #require(presenter.resizedSizes.first?.height)
    #expect(await eventually {
        installedController.view.layoutSubtreeIfNeeded()
        return installedController.view.fittingSize.height == resizedHeight
    })
    #expect(presenter.presentedContentViewControllers.count == 1)
}

@MainActor
@Test func visibleAIProviderChangeResizesWithoutRepresentingAndKeepsAnchor() async throws {
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
    await controller.startObserving()
    defer { controller.stopObserving() }
    let item = try #require(factory.created.first)
    item.performAction()
    #expect(await eventually { presenter.presentCount == 1 && presenter.isShown })

    var monitor = configuration.systemMonitor
    monitor.ai[.cursor]?.isVisible = false
    configuration.setSystemMonitor(monitor)

    #expect(await eventually { presenter.resizedSizes.count == 1 })
    #expect(presenter.presentCount == 1)
    #expect(presenter.resizedAnchors == presenter.presentedAnchors)
    let installedController = try #require(presenter.presentedContentViewControllers.first)
    let resizedHeight = try #require(presenter.resizedSizes.first?.height)
    #expect(await eventually {
        installedController.view.layoutSubtreeIfNeeded()
        return installedController.view.fittingSize.height == resizedHeight
    })
    #expect(presenter.presentedContentViewControllers.count == 1)
}

@MainActor
@Test func failedResizeKeepsTheInstalledDashboardLayoutUnchanged() async throws {
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
    await controller.startObserving()
    defer { controller.stopObserving() }
    let item = try #require(factory.created.first)
    item.performAction()
    #expect(await eventually { presenter.presentCount == 1 && presenter.isShown })
    let installedController = try #require(presenter.presentedContentViewControllers.first)
    installedController.view.layoutSubtreeIfNeeded()
    let initialHeight = installedController.view.fittingSize.height

    presenter.resizeResult = false
    var monitor = configuration.systemMonitor
    monitor.visibleModules.insert(.disk)
    configuration.setSystemMonitor(monitor)

    #expect(await eventually { !presenter.resizedSizes.isEmpty })
    #expect(presenter.presentCount == 1)
    #expect(presenter.presentedContentViewControllers.count == 1)
    #expect(presenter.presentedContentViewControllers.first === installedController)
    installedController.view.layoutSubtreeIfNeeded()
    #expect(installedController.view.fittingSize.height == initialHeight)
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

    @Test func singleDashboardItemUsesItsCurrentAnchorForTheDashboard() async throws {
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
        controller.openOverview()
        let item = try #require(factory.created.first)
        item.anchorForPresentation = StatusItemPresentationAnchor(
            buttonFrameInScreen: NSRect(x: 200, y: 500, width: 24, height: 24),
            visibleFrameInScreen: NSRect(x: 0, y: 0, width: 1_024, height: 768)
        )
        presenter.dismiss()
        item.performAction()

        #expect(await eventually { presenter.presentCount == 2 })
        #expect(presenter.dismissCount == 1)
        let anchor = try #require(presenter.presentedAnchors.last)
        #expect(anchor.buttonFrameInScreen == item.anchorForPresentation?.buttonFrameInScreen)
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
        let item = try #require(factory.created.first)
        item.performAction()
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

    @Test func analyticsDismissesThePanelBeforeInvokingItsCallbackExactlyOnce() {
        let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
        let eventLog = FakeEventLog()
        let presenter = FakeMenuPanelPresenter(eventLog: eventLog)
        var analyticsRequests = 0
        var retries = 0
        var loginRequests = 0
        var cursorRequests = 0
        let controller = makeMenuBarController(
            configuration: configuration,
            snapshotStore: ProviderSnapshotStore(),
            loginCoordinator: testLoginCoordinator(),
            panelPresenter: presenter,
            onRetryRequested: { retries += 1 },
            onProviderLoginRequested: { _ in loginRequests += 1 },
            onAnalyticsRequested: {
                analyticsRequests += 1
                eventLog.events.append("analytics")
            },
            openCursorSpending: { cursorRequests += 1 }
        )

        controller.openOverview()
        controller.performAnalyticsAction()

        #expect(eventLog.events == ["present", "dismiss", "analytics"])
        #expect(analyticsRequests == 1)
        #expect(retries == 0)
        #expect(loginRequests == 0)
        #expect(cursorRequests == 0)
    }

    @Test func presentedProviderAuthenticationActionsDismissBeforeTheirCallbacks() {
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

        for (provider, action) in [
            (ProviderID.claude, ProviderAuthenticationAction.browserLogin(title: "Sign in with Claude")),
            (.codex, .browserLogin(title: "Sign in with ChatGPT")),
            (.cursor, .openCursorSpending(title: "Open Cursor Spending")),
        ] {
            presenter.markShownForTesting()
            controller.performPresentedAuthenticationAction(action, for: provider)
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
    combinedSnapshotStore: CombinedSnapshotStore? = nil,
    loginCoordinator: ProviderLoginCoordinator,
    statusItemFactory: any StatusItemFactory = AppKitStatusItemFactory(),
    globalMouseDownMonitor: any GlobalMouseDownMonitoring = FakeGlobalMouseDownMonitor(),
    panelPresenter: any MenuPanelPresenting = FakeMenuPanelPresenter(),
    onModuleActivated: @escaping @MainActor (MenuModuleID) -> Void = { _ in },
    onRetryRequested: @escaping @MainActor () -> Void = {},
    onProviderLoginRequested: @escaping @MainActor (ProviderID) -> Void = { _ in },
    onSettingsRequested: @escaping @MainActor () -> Void = {},
    onAnalyticsRequested: @escaping @MainActor () -> Void = {},
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
        combinedSnapshotStore: combinedSnapshotStore ?? CombinedSnapshotStore(),
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
        onAnalyticsRequested: onAnalyticsRequested,
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
    var tooltip = ""
    var accessibilityLabel = ""
    var usesIconFallback = false
    private(set) var dashboardResults: [MenuBarDashboardRenderResult] = []
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

    func presentDashboard(_ result: MenuBarDashboardRenderResult) {
        title = result.title
        tooltip = result.tooltip
        accessibilityLabel = result.usesIconFallback ? "Needlbar" : result.tooltip
        usesIconFallback = result.usesIconFallback
        dashboardResults.append(result)
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
    private(set) var presentedContentSizes: [NSSize] = []
    private(set) var presentedContentViewControllers: [NSViewController] = []
    private(set) var resizedSizes: [NSSize] = []
    private(set) var resizedAnchors: [StatusItemPresentationAnchor] = []
    private(set) var isShown = false
    var resizeResult = true
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
        contentViewController.view.layoutSubtreeIfNeeded()
        presentedContentSizes.append(contentViewController.view.fittingSize)
        presentedContentViewControllers.append(contentViewController)
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

    func resize(to contentSize: NSSize, anchoredAt anchor: StatusItemPresentationAnchor) -> Bool {
        guard isShown else { return false }
        resizedSizes.append(contentSize)
        resizedAnchors.append(anchor)
        return resizeResult
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
