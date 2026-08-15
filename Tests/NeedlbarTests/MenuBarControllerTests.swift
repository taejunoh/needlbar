import Foundation
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

@MainActor
@Test func defaultConfigurationCreatesOnlyTheOverviewStatusItem() async {
    let configuration = ModuleConfiguration(defaults: freshMenuBarDefaults())
    let factory = FakeStatusItemFactory()
    let controller = MenuBarController(
        configuration: configuration,
        snapshotStore: ProviderSnapshotStore(),
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
    let controller = MenuBarController(
        configuration: configuration,
        snapshotStore: ProviderSnapshotStore(),
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
    let controller = MenuBarController(
        configuration: configuration,
        snapshotStore: ProviderSnapshotStore(),
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
    let controller = MenuBarController(
        configuration: configuration,
        snapshotStore: store,
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
    let controller = MenuBarController(
        configuration: configuration,
        snapshotStore: ProviderSnapshotStore(),
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
    let controller = MenuBarController(
        configuration: configuration,
        snapshotStore: store,
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
    let controller = MenuBarController(
        configuration: configuration,
        snapshotStore: ProviderSnapshotStore(),
        statusItemFactory: factory
    )
    await controller.startObserving()

    configuration.claude = ModuleSettings(isEnabled: true, metric: .quotaRemaining)
    controller.stopObserving()
    for _ in 0..<10 { await Task.yield() }

    #expect(controller.activeModuleIDs == [.overview])
    #expect(factory.created.count == 1)
}

private func freshMenuBarDefaults() -> UserDefaults {
    let suiteName = "MenuBarControllerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
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
    var title = ""
    var action: (@MainActor () -> Void)? {
        didSet { actionAssignmentCount += 1 }
    }
    private(set) var actionAssignmentCount = 0

    func performAction() {
        action?()
    }
}
