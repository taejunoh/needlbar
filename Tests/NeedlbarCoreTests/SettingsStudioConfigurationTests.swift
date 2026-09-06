import Foundation
import Testing
@testable import NeedlbarCore

@Suite("SettingsStudioConfiguration")
struct SettingsStudioConfigurationTests {
    @Test func legacyReadIsLazyAndWritesPreserveLegacy() {
        let name = "SettingsStudio.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["cpu", "ai"], forKey: "needlbar.systemMonitor.visible")
        defaults.set(false, forKey: "needlbar.systemMonitor.ai.claude.visible")
        let before = defaults.persistentDomain(forName: name)! as NSDictionary
        let store = ModuleConfiguration(defaults: defaults)
        var value = store.systemMonitor
        #expect(value.menuBarVisibleModules == [.cpu, .ai])
        #expect(value.dashboardVisibleModules == [.cpu, .ai])
        #expect(value.ai[.claude]?.dashboardVisible == false)
        #expect(before.isEqual(to: defaults.persistentDomain(forName: name)!))
        value.menuBarVisibleModules = []
        value.ai[.claude]?.menuBarVisible = true
        store.setSystemMonitor(value)
        let loaded = store.systemMonitor
        #expect(loaded.menuBarVisibleModules.isEmpty)
        #expect(loaded.dashboardVisibleModules == [.cpu, .ai])
        #expect(loaded.ai[.claude]?.menuBarVisible == true)
        #expect(loaded.ai[.claude]?.dashboardVisible == false)
        #expect(defaults.stringArray(forKey: "needlbar.systemMonitor.visible") == ["cpu", "ai"])
        #expect(defaults.object(forKey: "needlbar.systemMonitor.ai.claude.visible") as? Bool == false)
    }

    @Test func malformedAndEmptyAreDifferent() {
        let name = "SettingsStudio.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["disk"], forKey: "needlbar.systemMonitor.visible")
        defaults.set([String](), forKey: "needlbar.systemMonitor.menuBar.visible")
        defaults.set("not-an-array", forKey: "needlbar.systemMonitor.dashboard.visible")
        defaults.set(false, forKey: "needlbar.systemMonitor.ai.codex.visible")
        defaults.set("true", forKey: "needlbar.systemMonitor.ai.codex.menuBar.visible")
        let value = ModuleConfiguration(defaults: defaults).systemMonitor
        #expect(value.menuBarVisibleModules.isEmpty)
        #expect(value.dashboardVisibleModules == [.disk])
        #expect(value.ai[.codex]?.menuBarVisible == false)
    }

    @Test func valuesRoundTrip() throws {
        var value = SystemMonitorConfiguration()
        value.menuBarVisibleModules = []
        value.dashboardVisibleModules = [.network]
        value.ai[.claude]?.dashboardVisible = false
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(SystemMonitorConfiguration.self, from: data) == value)
    }

    @Test func malformedProviderFlagsUseLegacyBoolean() {
        let name = "SettingsStudio.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "needlbar.systemMonitor.ai.codex.visible")
        let key = "needlbar.systemMonitor.ai.codex.menuBar.visible"
        let store = ModuleConfiguration(defaults: defaults)
        for raw: Any in [0, 1, "false", "true"] {
            defaults.set(raw, forKey: key)
            #expect(store.systemMonitor.ai[.codex]?.menuBarVisible == false)
        }
        defaults.removeObject(forKey: key)
        #expect(store.systemMonitor.ai[.codex]?.menuBarVisible == false)
        defaults.set(true, forKey: key)
        #expect(store.systemMonitor.ai[.codex]?.menuBarVisible == true)
        #expect(store.systemMonitor.ai[.codex]?.dashboardVisible == false)
    }

    @Test func freshDefaultsApplyToBothSurfacesWithoutWrites() {
        let name = "SettingsStudio.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let value = ModuleConfiguration(defaults: defaults).systemMonitor
        #expect(value.menuBarVisibleModules == [.cpu, .memory, .ai])
        #expect(value.dashboardVisibleModules == [.cpu, .memory, .ai])
        #expect(!value.localIPEnabled && !value.publicIPEnabled)
        #expect(value.ai.values.allSatisfy { $0.menuBarVisible && $0.dashboardVisible && $0.metric == .remaining })
        #expect(defaults.persistentDomain(forName: name)?.isEmpty != false)
    }

    @Test func legacyJSONDecodesBothSurfaces() throws {
        let provider = try JSONDecoder().decode(AIProviderDisplayPreference.self,
            from: Data(#"{"isVisible":false,"metric":"remaining"}"#.utf8))
        #expect(!provider.menuBarVisible && !provider.dashboardVisible)
        let configuration = try JSONDecoder().decode(SystemMonitorConfiguration.self,
            from: Data(#"{"visibleModules":["network"]}"#.utf8))
        #expect(configuration.menuBarVisibleModules == [.network])
        #expect(configuration.dashboardVisibleModules == [.network])
    }
}
