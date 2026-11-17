import Foundation

/// The in-app copy for automatic Claude checks (spec 2026-11-16 §6). It does not
/// say whether a run uses quota or sends a model request; neither is verified.
enum ClaudeAutomaticChecksCopy {
    static let offCaption = "Automatic checks are off."
    static let turnOn = "Turn on"
    static let settingsToggle = "Check Claude quota automatically"
    static let settingsCaption =
        "Runs /usage in your Claude Code about every 15 minutes. Off: only when you click Check now."
    static let settingsPausedCaption = "Paused while Claude is hidden."

    /// The one caption line under the Settings toggle.
    static func settingsCaption(enabled: Bool, claudeShown: Bool) -> String {
        enabled && !claudeShown ? settingsPausedCaption : settingsCaption
    }
}
