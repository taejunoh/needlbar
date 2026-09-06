import Foundation
import Testing
@testable import NeedlbarCore

@Suite("SettingsStudioConfiguration")
struct SettingsStudioConfigurationTests {
    @Test func malformedLegacyAndNewSetsUseFreshDefaults() {
        let name = "SettingsStudio.invalid-legacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("cpu", forKey: "needlbar.systemMonitor.visible")
        defaults.set(["invalid": true], forKey: "needlbar.systemMonitor.dashboard.visible")
        let value = ModuleConfiguration(defaults: defaults).systemMonitor
        #expect(value.menuBarVisibleModules == [.cpu, .memory, .ai])
        #expect(value.dashboardVisibleModules == [.cpu, .memory, .ai])
    }

    @Test(arguments: ["missing", "malformed", "empty", "unknown", "valid"], ["menuBar", "dashboard"])
    func moduleVisibilityMigrationMatrix(_ input: String, _ surface: String) {
        let name = "SettingsStudio.modules.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["disk"], forKey: "needlbar.systemMonitor.visible")
        let key = "needlbar.systemMonitor.\(surface).visible"
        let expected: Set<MonitorModuleID>
        switch input {
        case "malformed": defaults.set("cpu", forKey: key); expected = [.disk]
        case "empty": defaults.set([String](), forKey: key); expected = []
        case "unknown": defaults.set(["unknown", "cpu"], forKey: key); expected = [.cpu]
        case "valid": defaults.set(["network", "ai"], forKey: key); expected = [.network, .ai]
        default: expected = [.disk]
        }
        let value = ModuleConfiguration(defaults: defaults).systemMonitor
        #expect(value.menuBarVisibleModules == (surface == "menuBar" ? expected : [.disk]))
        #expect(value.dashboardVisibleModules == (surface == "dashboard" ? expected : [.disk]))
    }

    @Test(arguments: ["missing", "empty", "true", "false", "string", "number"], ProviderID.allCases)
    func providerVisibilityMigrationMatrix(_ input: String, _ provider: ProviderID) {
        let name = "SettingsStudio.providers.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let base = "needlbar.systemMonitor.ai.\(provider.rawValue)"
        defaults.set(false, forKey: "\(base).visible")
        defaults.set(true, forKey: "\(base).menuBar.visible")
        let key = "\(base).dashboard.visible"
        switch input {
        case "empty": defaults.set([String](), forKey: key)
        case "true": defaults.set(true, forKey: key)
        case "false": defaults.set(false, forKey: key)
        case "string": defaults.set("true", forKey: key)
        case "number": defaults.set(1, forKey: key)
        default: break
        }
        let value = ModuleConfiguration(defaults: defaults).systemMonitor
        #expect(value.ai[provider]?.menuBarVisible == true)
        #expect(value.ai[provider]?.dashboardVisible == (input == "true"))
    }

    @Test(arguments: ["true", "false", "1", "0"])
    func malformedProviderStringsUseLegacyEnabledFlag(_ raw: String) {
        let name = "SettingsStudio.old-enabled.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "needlbar.menuBar.cursor.enabled")
        defaults.set(raw, forKey: "needlbar.systemMonitor.ai.cursor.visible")
        defaults.set(raw, forKey: "needlbar.systemMonitor.ai.cursor.dashboard.visible")
        let value = ModuleConfiguration(defaults: defaults).systemMonitor
        #expect(value.ai[.cursor]?.menuBarVisible == false)
        #expect(value.ai[.cursor]?.dashboardVisible == false)
    }

    @Test(arguments: ["usage", "cost", "invalid"])
    func savedMetricsSurviveVisibilityEdits(_ raw: String) {
        let name = "SettingsStudio.metrics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(raw, forKey: "needlbar.systemMonitor.ai.claude.metric")
        let store = ModuleConfiguration(defaults: defaults)
        var value = store.systemMonitor
        value.ai[.claude]?.dashboardVisible = false
        store.setSystemMonitor(value)
        let expected: AIProviderDisplayMetric = raw == "usage" ? .usage : (raw == "cost" ? .cost : .remaining)
        #expect(store.systemMonitor.ai[.claude]?.metric == expected)
        #expect(store.systemMonitor.ai[.claude]?.menuBarVisible == true)
    }

    @Test(arguments: ["empty", "incomplete", "duplicate", "unknown", "valid"])
    func onlyCompleteKnownPermutationsPreserveSavedOrder(_ input: String) {
        let name = "SettingsStudio.orders.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var modules = ["ai", "battery", "network", "disk", "memory", "cpu"]
        var providers = ["cursor", "codex", "claude"]
        switch input {
        case "empty": modules = []; providers = []
        case "incomplete": modules.removeLast(); providers.removeLast()
        case "duplicate": modules[0] = "cpu"; providers[0] = "claude"
        case "unknown": modules.append("unknown"); providers.append("unknown")
        default: break
        }
        defaults.set(modules, forKey: "needlbar.systemMonitor.order")
        defaults.set(providers, forKey: "needlbar.systemMonitor.ai.order")
        let value = ModuleConfiguration(defaults: defaults).systemMonitor
        #expect(value.order == (input == "valid"
            ? [.ai, .battery, .network, .disk, .memory, .cpu]
            : [.cpu, .memory, .disk, .network, .battery, .ai]))
        #expect(value.aiOrder == (input == "valid" ? [.cursor, .codex, .claude] : [.claude, .codex, .cursor]))
    }

    @Test func gettersNeverPostConfigurationNotifications() {
        let name = "SettingsStudio.notifications.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ModuleConfiguration(defaults: defaults)
        let count = SettingsStudioNotificationCount()
        let center = NotificationCenter.default
        let tokens = [ModuleConfiguration.didChangeNotification, ModuleConfiguration.systemMonitorDidChangeNotification].map {
            center.addObserver(forName: $0, object: store, queue: nil) { _ in count.increment() }
        }
        defer { tokens.forEach(center.removeObserver) }
        for _ in 0..<3 { _ = store.systemMonitor }
        #expect(count.value == 0)
        #expect(defaults.persistentDomain(forName: name)?.isEmpty != false)
        store.setSystemMonitor(store.systemMonitor)
        #expect(count.value == 2)
    }

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

private final class SettingsStudioNotificationCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
