import Combine
import Foundation

@MainActor
public final class QuotaNotificationPreferences: ObservableObject {
    public enum State: Equatable, Sendable {
        case off
        case enabled
        case unavailable
    }

    @Published public private(set) var state: State

    private let defaults: UserDefaults
    private let key = "needlbar.notifications.quota-alerts.enabled"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = defaults.bool(forKey: key) ? .enabled : .off
    }

    public var isEnabled: Bool {
        state == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
        state = enabled ? .enabled : .off
    }

    func setUnavailable() {
        defaults.set(false, forKey: key)
        state = .unavailable
    }
}
