import CoreFoundation
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
        let localIPEnabled = defaults.object(forKey: "needlbar.systemMonitor.localIP") as? Bool ?? false
        let publicIPEnabled = defaults.object(forKey: "needlbar.systemMonitor.publicIP") as? Bool ?? false
        let aiOrder = validAIOrder(from: defaults.stringArray(forKey: "needlbar.systemMonitor.ai.order"))
        let ai = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { provider in
            let metricKey = "needlbar.systemMonitor.ai.\(provider.rawValue).metric"
            let apiBillingLinkVisible = switch provider {
            case .claude, .codex:
                strictBool("needlbar.systemMonitor.ai.\(provider.rawValue).apiBillingLink.visible") ?? false
            case .cursor:
                false
            }
            let preference = AIProviderDisplayPreference(
                isVisible: providerVisible(provider, surface: .menuBar),
                metric: defaults.string(forKey: metricKey)
                    .flatMap(AIProviderDisplayMetric.init(rawValue:)) ?? .remaining,
                dashboardVisible: providerVisible(provider, surface: .dashboard),
                apiBillingLinkVisible: apiBillingLinkVisible
            )
            return (provider, preference)
        })
        return SystemMonitorConfiguration(
            order: order,
            visibleModules: visibleModules(for: .menuBar),
            publicIPEnabled: publicIPEnabled,
            aiOrder: aiOrder,
            ai: ai,
            localIPEnabled: localIPEnabled,
            dashboardVisibleModules: visibleModules(for: .dashboard)
        )
    }

    public func setSystemMonitor(_ configuration: SystemMonitorConfiguration) {
        let order = validOrder(configuration.order)
        defaults.set(order.map(\.rawValue), forKey: "needlbar.systemMonitor.order")
        defaults.set(configuration.menuBarVisibleModules.map(\.rawValue).sorted(),
                     forKey: "needlbar.systemMonitor.menuBar.visible")
        defaults.set(configuration.dashboardVisibleModules.map(\.rawValue).sorted(),
                     forKey: "needlbar.systemMonitor.dashboard.visible")
        defaults.set(configuration.localIPEnabled, forKey: "needlbar.systemMonitor.localIP")
        defaults.set(configuration.publicIPEnabled, forKey: "needlbar.systemMonitor.publicIP")
        defaults.set(validAIOrder(configuration.aiOrder).map(\.rawValue), forKey: "needlbar.systemMonitor.ai.order")
        for provider in ProviderID.allCases {
            let preference = configuration.ai[provider] ?? AIProviderDisplayPreference()
            defaults.set(preference.menuBarVisible,
                         forKey: "needlbar.systemMonitor.ai.\(provider.rawValue).menuBar.visible")
            defaults.set(preference.dashboardVisible,
                         forKey: "needlbar.systemMonitor.ai.\(provider.rawValue).dashboard.visible")
            defaults.set(preference.metric.rawValue, forKey: "needlbar.systemMonitor.ai.\(provider.rawValue).metric")
            if provider == .claude || provider == .codex {
                let apiBillingLinkKey = "needlbar.systemMonitor.ai.\(provider.rawValue).apiBillingLink.visible"
                defaults.removeObject(forKey: apiBillingLinkKey)
                defaults.set(preference.apiBillingLinkVisible, forKey: apiBillingLinkKey)
            }
        }
        NotificationCenter.default.post(name: Self.systemMonitorDidChangeNotification, object: self)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    public func setAPIBillingLinkVisible(_ visible: Bool, for provider: ProviderID) {
        guard provider == .claude || provider == .codex else { return }
        let key = "needlbar.systemMonitor.ai.\(provider.rawValue).apiBillingLink.visible"
        defaults.removeObject(forKey: key)
        defaults.set(visible, forKey: key)
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
        guard let rawValues, rawValues.count == MonitorModuleID.allCases.count else {
            return MonitorModuleID.defaultOrder
        }
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
        guard let rawValues else { return Set([.cpu, .memory, .ai]) }
        return Set(rawValues.compactMap(MonitorModuleID.init(rawValue:)))
    }

    private func validAIOrder(from rawValues: [String]?) -> [ProviderID] {
        guard let rawValues, rawValues.count == ProviderID.allCases.count else {
            return ProviderID.allCases
        }
        let parsed = rawValues.compactMap(ProviderID.init(rawValue:))
        return Set(parsed).count == ProviderID.allCases.count && parsed.count == ProviderID.allCases.count
            ? parsed
            : ProviderID.allCases
    }

    private func validAIOrder(_ order: [ProviderID]) -> [ProviderID] {
        Set(order).count == ProviderID.allCases.count && order.count == ProviderID.allCases.count
            ? order
            : ProviderID.allCases
    }

    private func strictBool(_ key: String) -> Bool? {
        guard let number = defaults.object(forKey: key) as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private func visibleModules(for surface: MonitorDisplaySurface) -> Set<MonitorModuleID> {
        let raw = defaults.stringArray(forKey: "needlbar.systemMonitor.\(surface.rawValue).visible")
            ?? defaults.stringArray(forKey: "needlbar.systemMonitor.visible")
        return validVisibleModules(from: raw)
    }

    private func providerVisible(_ provider: ProviderID, surface: MonitorDisplaySurface) -> Bool {
        let base = "needlbar.systemMonitor.ai.\(provider.rawValue)"
        return strictBool("\(base).\(surface.rawValue).visible")
            ?? strictBool("\(base).visible")
            ?? strictBool("needlbar.menuBar.\(provider.rawValue).enabled")
            ?? true
    }

    private func key(for module: MenuModuleID, property: String) -> String {
        "needlbar.menuBar.\(module.rawValue).\(property)"
    }
}
