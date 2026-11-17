import Foundation
import Testing
@testable import NeedlbarApp

@Suite("ClaudeAutomaticChecksPreferences")
@MainActor
struct ClaudeAutomaticChecksPreferencesTests {
    private static func makeDefaults() throws -> (UserDefaults, String) {
        let name = "ClaudeAutomaticChecks.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    @Test func aMissingValueMeansOff() throws {
        let (defaults, name) = try Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(defaults.object(forKey: "needlbar.claude.automaticUsageChecks.enabled") == nil)
        #expect(!ClaudeAutomaticChecksPreferences(defaults: defaults).isEnabled)
    }

    @Test func theChoicePersistsUnderTheSpecifiedKey() throws {
        let (defaults, name) = try Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = ClaudeAutomaticChecksPreferences(defaults: defaults)
        preferences.setEnabled(true)
        #expect(preferences.isEnabled)
        #expect(defaults.object(forKey: "needlbar.claude.automaticUsageChecks.enabled") as? Bool == true)
        #expect(ClaudeAutomaticChecksPreferences(defaults: defaults).isEnabled)
        preferences.setEnabled(false)
        #expect(!preferences.isEnabled)
        #expect(!ClaudeAutomaticChecksPreferences(defaults: defaults).isEnabled)
    }

    @Test func aChangeIsPublished() throws {
        let (defaults, name) = try Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = ClaudeAutomaticChecksPreferences(defaults: defaults)
        var seen: [Bool] = []
        let observation = preferences.$isEnabled.sink { seen.append($0) }
        preferences.setEnabled(true)
        preferences.setEnabled(false)
        observation.cancel()
        #expect(seen == [false, true, false])
    }
}
