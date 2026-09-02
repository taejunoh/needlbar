import Foundation
import Testing
@testable import NeedlbarCore

@Test func moduleConfigurationUsesApprovedDefaultsForAnEmptySuite() {
    let suiteName = "ModuleConfigurationTests.defaults.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let configuration = ModuleConfiguration(defaults: defaults)

    #expect(configuration.overview.isEnabled == true)
    #expect(configuration.claude.isEnabled == false)
    #expect(configuration.codex.isEnabled == false)
    #expect(configuration.cursor.isEnabled == false)
    #expect(configuration.overview.metric == .quotaRemaining)
    #expect(configuration.claude.metric == .quotaRemaining)
    #expect(configuration.codex.metric == .quotaRemaining)
    #expect(configuration.cursor.metric == .quotaRemaining)
}

@Test func moduleConfigurationPersistsOnlyModuleDisplayPreferences() {
    let suiteName = "ModuleConfigurationTests.persistence.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let configuration = ModuleConfiguration(defaults: defaults)
    configuration.claude = ModuleSettings(isEnabled: true, metric: .tokensToday)
    configuration.cursor = ModuleSettings(isEnabled: true, metric: .costToday)

    let reloaded = ModuleConfiguration(defaults: defaults)
    #expect(reloaded.claude == ModuleSettings(isEnabled: true, metric: .tokensToday))
    #expect(reloaded.cursor == ModuleSettings(isEnabled: true, metric: .costToday))
    #expect(reloaded.overview == ModuleSettings(isEnabled: true, metric: .quotaRemaining))
}

@Test func monitorConfigurationPersistsOrderVisibilityIPAndAIValues() {
    let defaults = freshMonitorConfigurationDefaults()
    let configuration = ModuleConfiguration(defaults: defaults)
    var value = configuration.systemMonitor
    value.order = [.ai, .cpu, .network, .memory, .disk, .battery]
    value.visibleModules = [.ai, .cpu, .network]
    value.publicIPEnabled = true
    value.ai[.codex] = AIProviderDisplayPreference(isVisible: false, metric: .cost)
    configuration.setSystemMonitor(value)

    let reloaded = ModuleConfiguration(defaults: defaults).systemMonitor
    #expect(reloaded == value)
}

@Test func emptyMonitorConfigurationUsesAllModulesAndProviderDefaults() {
    let defaults = freshMonitorConfigurationDefaults()
    let configuration = ModuleConfiguration(defaults: defaults)

    #expect(configuration.systemMonitor.order == MonitorModuleID.defaultOrder)
    #expect(configuration.systemMonitor.visibleModules == Set(MonitorModuleID.defaultOrder))
    #expect(configuration.systemMonitor.publicIPEnabled == false)
    #expect(configuration.systemMonitor.ai == Dictionary(
        uniqueKeysWithValues: ProviderID.allCases.map { ($0, AIProviderDisplayPreference()) }
    ))
}

@Test func invalidMonitorOrderFallsBackToCanonicalOrder() {
    let defaults = freshMonitorConfigurationDefaults()
    defaults.set(["cpu", "cpu", "unknown"], forKey: "needlbar.systemMonitor.order")
    let configuration = ModuleConfiguration(defaults: defaults)

    #expect(configuration.systemMonitor.order == MonitorModuleID.defaultOrder)
}

private func freshMonitorConfigurationDefaults() -> UserDefaults {
    let suiteName = "ModuleConfigurationTests.monitor.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
