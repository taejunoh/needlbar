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
