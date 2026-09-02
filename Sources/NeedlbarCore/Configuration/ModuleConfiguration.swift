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
    public static let didChangeNotification = Notification.Name("needlbar.module-configuration.did-change")
    public static let systemMonitorDidChangeNotification = Notification.Name("needlbar.system-monitor-configuration.did-change")

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

    public var systemMonitor: SystemMonitorConfiguration {
        let order = validOrder(from: defaults.stringArray(forKey: "needlbar.systemMonitor.order"))
        let visibleModules = validVisibleModules(from: defaults.stringArray(forKey: "needlbar.systemMonitor.visible"))
        let publicIPEnabled = defaults.object(forKey: "needlbar.systemMonitor.publicIP") as? Bool ?? false
        let ai = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { provider in
            let visibleKey = "needlbar.systemMonitor.ai.\(provider.rawValue).visible"
            let metricKey = "needlbar.systemMonitor.ai.\(provider.rawValue).metric"
            let preference = AIProviderDisplayPreference(
                isVisible: defaults.object(forKey: visibleKey) as? Bool ?? migratedAIVisibility(for: provider),
                metric: defaults.string(forKey: metricKey)
                    .flatMap(AIProviderDisplayMetric.init(rawValue:)) ?? .usage
            )
            return (provider, preference)
        })
        return SystemMonitorConfiguration(
            order: order,
            visibleModules: visibleModules,
            publicIPEnabled: publicIPEnabled,
            ai: ai
        )
    }

    public func setSystemMonitor(_ configuration: SystemMonitorConfiguration) {
        let order = validOrder(configuration.order)
        let visibleModules = configuration.visibleModules.intersection(Set(MonitorModuleID.allCases))
        defaults.set(order.map(\.rawValue), forKey: "needlbar.systemMonitor.order")
        defaults.set(visibleModules.map(\.rawValue).sorted(), forKey: "needlbar.systemMonitor.visible")
        defaults.set(configuration.publicIPEnabled, forKey: "needlbar.systemMonitor.publicIP")
        for provider in ProviderID.allCases {
            let preference = configuration.ai[provider] ?? AIProviderDisplayPreference()
            defaults.set(preference.isVisible, forKey: "needlbar.systemMonitor.ai.\(provider.rawValue).visible")
            defaults.set(preference.metric.rawValue, forKey: "needlbar.systemMonitor.ai.\(provider.rawValue).metric")
        }
        NotificationCenter.default.post(name: Self.systemMonitorDidChangeNotification, object: self)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
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
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    public var enabledModuleIDs: [MenuModuleID] {
        MenuModuleID.allCases.filter { settings(for: $0).isEnabled }
    }

    private func defaultSettings(for module: MenuModuleID) -> ModuleSettings {
        ModuleSettings(isEnabled: module == .overview, metric: .quotaRemaining)
    }

    private func validOrder(from rawValues: [String]?) -> [MonitorModuleID] {
        guard let rawValues else { return MonitorModuleID.defaultOrder }
        let parsed = rawValues.compactMap(MonitorModuleID.init(rawValue:))
        return Set(parsed).count == MonitorModuleID.allCases.count && parsed.count == MonitorModuleID.allCases.count
            ? parsed
            : MonitorModuleID.defaultOrder
    }

    private func validOrder(_ order: [MonitorModuleID]) -> [MonitorModuleID] {
        Set(order).count == MonitorModuleID.allCases.count && order.count == MonitorModuleID.allCases.count
            ? order
            : MonitorModuleID.defaultOrder
    }

    private func validVisibleModules(from rawValues: [String]?) -> Set<MonitorModuleID> {
        guard let rawValues else { return Set(MonitorModuleID.defaultOrder) }
        return Set(rawValues.compactMap(MonitorModuleID.init(rawValue:)))
    }

    private func migratedAIVisibility(for provider: ProviderID) -> Bool {
        let legacyModule: MenuModuleID
        switch provider {
        case .claude: legacyModule = .claude
        case .codex: legacyModule = .codex
        case .cursor: legacyModule = .cursor
        }
        let key = key(for: legacyModule, property: "enabled")
        guard defaults.object(forKey: key) != nil else { return true }
        return settings(for: legacyModule).isEnabled
    }

    private func key(for module: MenuModuleID, property: String) -> String {
        "needlbar.menuBar.\(module.rawValue).\(property)"
    }
}
