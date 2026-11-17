import Foundation
import Testing
@testable import NeedlbarCore

@Suite("ClaudeIsShown")
struct ClaudeVisibilityTests {
    @Test func claudeIsShownWhenEitherSurfaceShowsItsAISectionAndClaudeInIt() {
        for aiOnMenuBar in [false, true] {
            for claudeOnMenuBar in [false, true] {
                for aiOnDashboard in [false, true] {
                    for claudeOnDashboard in [false, true] {
                        var configuration = SystemMonitorConfiguration(
                            visibleModules: aiOnMenuBar ? [.cpu, .ai] : [.cpu],
                            dashboardVisibleModules: aiOnDashboard ? [.memory, .ai] : [.memory])
                        configuration.ai[.claude] = AIProviderDisplayPreference(
                            isVisible: claudeOnMenuBar, dashboardVisible: claudeOnDashboard)
                        let expected = (aiOnMenuBar && claudeOnMenuBar) || (aiOnDashboard && claudeOnDashboard)
                        #expect(
                            claudeIsShown(configuration) == expected,
                            "menu bar \(aiOnMenuBar)/\(claudeOnMenuBar), dashboard \(aiOnDashboard)/\(claudeOnDashboard)")
                    }
                }
            }
        }
    }

    @Test func otherProvidersDoNotCount() {
        var configuration = SystemMonitorConfiguration(visibleModules: [.ai])
        configuration.ai[.claude] = AIProviderDisplayPreference(isVisible: false)
        configuration.ai[.codex] = AIProviderDisplayPreference(isVisible: true)
        configuration.ai[.cursor] = AIProviderDisplayPreference(isVisible: true)
        #expect(!claudeIsShown(configuration))
    }

    @Test func aMissingClaudePreferenceCountsAsVisibleLikeTheRenderers() {
        var configuration = SystemMonitorConfiguration(visibleModules: [.ai])
        configuration.ai[.claude] = nil
        #expect(claudeIsShown(configuration))
    }

    @Test func theDefaultConfigurationShowsClaude() {
        #expect(claudeIsShown(SystemMonitorConfiguration()))
    }

    @Test func theLegacyMenuBarSwitchCannotOverrideTheNewerKeys() throws {
        let name = "ClaudeIsShown.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "needlbar.systemMonitor.ai.claude.menuBar.visible")
        defaults.set(false, forKey: "needlbar.systemMonitor.ai.claude.dashboard.visible")
        defaults.set(true, forKey: "needlbar.menuBar.claude.enabled")
        let configuration = ModuleConfiguration(defaults: defaults)
        #expect(configuration.claude.isEnabled)
        #expect(!claudeIsShown(configuration.systemMonitor))
    }
}
