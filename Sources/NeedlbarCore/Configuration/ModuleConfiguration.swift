import Foundation

public enum MenuModuleID: String, CaseIterable, Sendable {
    case overview
    case claude
    case codex
    case cursor

    public var provider: ProviderID? {
        switch self {
        case .overview:
            nil
        case .claude:
            .claude
        case .codex:
            .codex
        case .cursor:
            .cursor
        }
    }
}

public enum MenuBarMetric: String, CaseIterable, Sendable {
    case quotaRemaining
    case tokensToday
    case costToday
}

public struct ModuleSettings: Equatable, Sendable {
    public var isEnabled: Bool
    public var metric: MenuBarMetric

    public init(isEnabled: Bool, metric: MenuBarMetric) {
        self.isEnabled = isEnabled
        self.metric = metric
    }
}

public final class ModuleConfiguration {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var overview: ModuleSettings {
        get { settings(for: .overview) }
        set { set(newValue, for: .overview) }
    }

    public var claude: ModuleSettings {
        get { settings(for: .claude) }
        set { set(newValue, for: .claude) }
    }

    public var codex: ModuleSettings {
        get { settings(for: .codex) }
        set { set(newValue, for: .codex) }
    }

    public var cursor: ModuleSettings {
        get { settings(for: .cursor) }
        set { set(newValue, for: .cursor) }
    }

    public func settings(for module: MenuModuleID) -> ModuleSettings {
        let enabledKey = key(for: module, property: "enabled")
        let metricKey = key(for: module, property: "metric")
        let isEnabled = defaults.object(forKey: enabledKey) as? Bool ?? defaultSettings(for: module).isEnabled
        let metric = (defaults.string(forKey: metricKey)).flatMap(MenuBarMetric.init(rawValue:)) ?? .quotaRemaining
        return ModuleSettings(isEnabled: isEnabled, metric: metric)
    }

    public func set(_ settings: ModuleSettings, for module: MenuModuleID) {
        defaults.set(settings.isEnabled, forKey: key(for: module, property: "enabled"))
        defaults.set(settings.metric.rawValue, forKey: key(for: module, property: "metric"))
    }

    public var enabledModuleIDs: [MenuModuleID] {
        MenuModuleID.allCases.filter { settings(for: $0).isEnabled }
    }

    private func defaultSettings(for module: MenuModuleID) -> ModuleSettings {
        ModuleSettings(isEnabled: module == .overview, metric: .quotaRemaining)
    }

    private func key(for module: MenuModuleID, property: String) -> String {
        "needlbar.menuBar.\(module.rawValue).\(property)"
    }
}
