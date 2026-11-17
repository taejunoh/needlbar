import Combine
import Foundation

/// Whether Needlbar may start `claude` to run `/usage` without a click. Off by
/// default, for new installs and for people updating: a missing value means off.
@MainActor
public final class ClaudeAutomaticChecksPreferences: ObservableObject {
    static let key = "needlbar.claude.automaticUsageChecks.enabled"

    @Published public private(set) var isEnabled: Bool

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.key)
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.key)
        isEnabled = enabled
    }
}
