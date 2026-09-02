import Foundation
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

@MainActor
@Test func changingSettingsPersistsVisibilityOrderAndProviderMetric() {
    let defaults = UserDefaults(suiteName: "needlbar.settings-tests.\(UUID().uuidString)")!
    let configuration = ModuleConfiguration(defaults: defaults)
    let model = SystemMonitorSettingsModel(configuration: configuration)

    model.setVisible(.network, false)
    model.move(.ai, before: .cpu)
    model.setPublicIPEnabled(true)
    model.setLocalIPEnabled(true)
    model.setAIProvider(.claude, metric: .cost)

    let saved = configuration.systemMonitor
    #expect(saved.visibleModules.contains(.network) == false)
    #expect(saved.order.first == .ai)
    #expect(saved.publicIPEnabled == true)
    #expect(saved.localIPEnabled == true)
    #expect(saved.ai[.claude]?.metric == .cost)
}

@MainActor
@Test func compactDefaultsSelectOnlySystemHeadlineModulesWithoutChangingProviderPreferences() {
    let defaults = UserDefaults(suiteName: "needlbar.settings-tests.\(UUID().uuidString)")!
    let configuration = ModuleConfiguration(defaults: defaults)
    configuration.setSystemMonitor(SystemMonitorConfiguration(
        visibleModules: Set(MonitorModuleID.allCases),
        ai: [.claude: AIProviderDisplayPreference(isVisible: false, metric: .cost)]
    ))
    let model = SystemMonitorSettingsModel(configuration: configuration)

    model.useCompactDefaults()

    let saved = configuration.systemMonitor
    #expect(saved.visibleModules == Set([.cpu, .memory, .ai]))
    #expect(saved.ai[.claude] == AIProviderDisplayPreference(isVisible: false, metric: .cost))
}

@MainActor
@Test func movingModulesCannotCreateDuplicatesOrDropAnUnrelatedModule() {
    let defaults = UserDefaults(suiteName: "needlbar.settings-tests.\(UUID().uuidString)")!
    let configuration = ModuleConfiguration(defaults: defaults)
    let model = SystemMonitorSettingsModel(configuration: configuration)

    model.move(.network, before: .cpu)
    model.move(.network, before: .network)

    let order = configuration.systemMonitor.order
    #expect(order.count == MonitorModuleID.allCases.count)
    #expect(Set(order).count == MonitorModuleID.allCases.count)
    #expect(Set(order) == Set(MonitorModuleID.allCases))
}

@MainActor
@Test func providerVisibilityAndMetricChangesAreIsolatedPerProvider() {
    let defaults = UserDefaults(suiteName: "needlbar.settings-tests.\(UUID().uuidString)")!
    let configuration = ModuleConfiguration(defaults: defaults)
    var initial = configuration.systemMonitor
    initial.ai[.claude] = AIProviderDisplayPreference(metric: .usage)
    configuration.setSystemMonitor(initial)
    let model = SystemMonitorSettingsModel(configuration: configuration)

    model.setAIProvider(.claude, visible: false)
    model.setAIProvider(.codex, metric: .remaining)

    let saved = configuration.systemMonitor
    #expect(saved.ai[.claude]?.isVisible == false)
    #expect(saved.ai[.claude]?.metric == .usage)
    #expect(saved.ai[.codex]?.isVisible == true)
    #expect(saved.ai[.codex]?.metric == .remaining)
}

@MainActor
@Test func providerReorderPersistsWithoutChangingProviderPreferences() {
    let defaults = UserDefaults(suiteName: "needlbar.settings-tests.\(UUID().uuidString)")!
    let configuration = ModuleConfiguration(defaults: defaults)
    let model = SystemMonitorSettingsModel(configuration: configuration)

    model.moveAIProvider(.cursor, before: .claude)

    let saved = configuration.systemMonitor
    #expect(saved.aiOrder == [.cursor, .claude, .codex])
    #expect(saved.ai[.claude] == AIProviderDisplayPreference(metric: .remaining))
    #expect(saved.ai[.cursor] == AIProviderDisplayPreference(metric: .remaining))
}
