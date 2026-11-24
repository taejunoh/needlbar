import Foundation
import NeedlbarCore
import SwiftUI
import Testing
@testable import NeedlbarApp

// The Settings toggle for automatic Claude checks. Everything is synthetic:
// isolated defaults, no refresh coordinator, and nothing here runs `claude`.
@Suite("ClaudeAutomaticChecksSettings", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct ClaudeAutomaticChecksSettingsTests {
    @Test func theCopyIsTheApprovedText() {
        #expect(ClaudeAutomaticChecksCopy.offCaption == "Automatic checks are off.")
        #expect(ClaudeAutomaticChecksCopy.turnOn == "Turn on")
        #expect(ClaudeAutomaticChecksCopy.settingsToggle == "Check Claude quota automatically")
        #expect(ClaudeAutomaticChecksCopy.settingsCaption(enabled: false, claudeShown: true)
            == "Runs /usage in your Claude Code about every 15 minutes. Off: only when you click Check now.")
        #expect(ClaudeAutomaticChecksCopy.settingsCaption(enabled: true, claudeShown: true)
            == ClaudeAutomaticChecksCopy.settingsCaption(enabled: false, claudeShown: true))
        #expect(ClaudeAutomaticChecksCopy.settingsCaption(enabled: false, claudeShown: false)
            == ClaudeAutomaticChecksCopy.settingsCaption(enabled: false, claudeShown: true),
            "off and hidden still explains the setting")
        #expect(ClaudeAutomaticChecksCopy.settingsCaption(enabled: true, claudeShown: false)
            == "Paused while Claude is hidden.")
    }

    @Test func actionsWithoutAPreferenceCarryNoSettingAndIgnoreARequest() {
        let actions = SettingsActions()
        #expect(actions.claudeAutomaticChecksEnabled == nil)
        actions.setClaudeAutomaticChecksEnabled(true)
        #expect(actions.claudeAutomaticChecksEnabled == nil)
    }

    @Test func actionsShowAndSetThePreferenceAndRunNoCheck() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        var checks = 0
        let actions = SettingsActions(claudeCheckNow: { checks += 1 }, claudeAutomaticChecks: fixture.preferences)
        #expect(actions.claudeAutomaticChecksEnabled == false)
        actions.setClaudeAutomaticChecksEnabled(true)
        #expect(actions.claudeAutomaticChecksEnabled == true)
        #expect(fixture.preferences.isEnabled)
        actions.setClaudeAutomaticChecksEnabled(false)
        #expect(actions.claudeAutomaticChecksEnabled == false)
        #expect(!fixture.preferences.isEnabled)
        #expect(checks == 0, "the toggle is not Check now")
    }

    @Test func actionsFollowAChangeMadeElsewhere() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let actions = SettingsActions(claudeAutomaticChecks: fixture.preferences)
        fixture.preferences.setEnabled(true)
        while !Task.isCancelled, actions.claudeAutomaticChecksEnabled != true {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(actions.claudeAutomaticChecksEnabled == true)
    }

    @Test func theCaptionSaysPausedOnlyWhileOnAndClaudeIsHidden() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let view = fixture.settingsView(actions: SettingsActions(claudeAutomaticChecks: fixture.preferences))
        #expect(view.claudeAutomaticChecksCaption(enabled: false) == ClaudeAutomaticChecksCopy.settingsCaption)
        #expect(view.claudeAutomaticChecksCaption(enabled: true) == ClaudeAutomaticChecksCopy.settingsCaption)
        fixture.defaults.set(false, forKey: "needlbar.systemMonitor.ai.claude.menuBar.visible")
        fixture.defaults.set(false, forKey: "needlbar.systemMonitor.ai.claude.dashboard.visible")
        #expect(view.claudeAutomaticChecksCaption(enabled: true) == "Paused while Claude is hidden.")
        #expect(view.claudeAutomaticChecksCaption(enabled: false) == ClaudeAutomaticChecksCopy.settingsCaption)
    }

    @Test func theRowsRenderOnlyWhenTheActionsCarryAPreference() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let with = fixture.settingsView(actions: SettingsActions(claudeAutomaticChecks: fixture.preferences))
        try AccessibilityHostedView(VStack { with.claudeAutomaticChecksRows }, width: 640) { hosted in
            #expect(hosted.items.filter { $0.role == "AXCheckBox" }.map(\.label) == ["Check Claude quota automatically"],
                    "\(hosted.items)")
        }
        let without = fixture.settingsView(actions: SettingsActions())
        try AccessibilityHostedView(VStack { without.claudeAutomaticChecksRows }, width: 640) { hosted in
            #expect(!hosted.items.contains { $0.label == "Check Claude quota automatically" }, "\(hosted.items)")
        }
    }
}

@MainActor
private final class Fixture {
    let defaults: UserDefaults
    let preferences: ClaudeAutomaticChecksPreferences
    private let name: String

    init() throws {
        name = "ClaudeAutomaticChecksSettings.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: name))
        preferences = ClaudeAutomaticChecksPreferences(defaults: defaults)
    }

    func settingsView(actions: SettingsActions) -> SettingsView {
        let notificationPreferences = QuotaNotificationPreferences(defaults: defaults)
        return SettingsView(
            configuration: ModuleConfiguration(defaults: defaults),
            actions: actions,
            notificationPreferences: notificationPreferences,
            notificationService: QuotaNotificationService(
                store: ProviderSnapshotStore(), preferences: notificationPreferences),
            openCursorSpending: {},
            openClaudeUsage: { true }
        )
    }

    func tearDown() { defaults.removePersistentDomain(forName: name) }
}
