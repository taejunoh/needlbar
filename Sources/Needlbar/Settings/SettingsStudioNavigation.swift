import NeedlbarCore
import SwiftUI

enum SettingsStudioTab: String, CaseIterable, Identifiable {
    case menuBar = "Menu bar", dashboard = "Dashboard", alerts = "Alerts"
    var id: Self { self }
    var surface: MonitorDisplaySurface? {
        switch self { case .menuBar: .menuBar; case .dashboard: .dashboard; case .alerts: nil }
    }
}
enum SettingsStudioPage: Hashable {
    case layout, module(MonitorModuleID), provider(ProviderID), notifications, data
    var title: String {
        switch self {
        case .layout: "Menu bar & dashboard"
        case let .module(id): id.title
        case let .provider(id): id.displayName
        case .notifications: "Notifications"
        case .data: "Data & Privacy"
        }
    }
    var tabs: [SettingsStudioTab] {
        switch self {
        case .layout: [.menuBar, .dashboard]
        case .module, .provider: SettingsStudioTab.allCases
        case .notifications, .data: []
        }
    }
}

extension MonitorModuleID {
    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "RAM"
        case .disk: "Disk"
        case .network: "Network"
        case .battery: "Battery"
        case .ai: "AI usage"
        }
    }

    var systemImage: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "network"
        case .battery: "battery.100"
        case .ai: "sparkles"
        }
    }
}

extension AIProviderDisplayMetric {
    var title: String {
        switch self {
        case .usage: "Usage"
        case .remaining: "Remaining"
        case .cost: "Cost"
        case .connectionStatus: "Connection"
        }
    }
}
