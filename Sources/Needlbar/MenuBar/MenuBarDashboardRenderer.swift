import Foundation
import NeedlbarCore

public struct MenuBarDashboardRenderResult: Equatable, Sendable {
    public enum Layout: Equatable, Sendable {
        case expanded
        case compact
    }

    public let layout: Layout
    public let title: String
    public let moduleIDs: [MonitorModuleID]

    public init(layout: Layout, title: String, moduleIDs: [MonitorModuleID]) {
        self.layout = layout
        self.title = title
        self.moduleIDs = moduleIDs
    }
}

public enum MenuBarDashboardRenderer {
    public static let compactWidthThreshold: Double = 240

    public static func render(
        snapshot: CombinedUsageSnapshot,
        configuration: SystemMonitorConfiguration,
        availableWidth: Double
    ) -> MenuBarDashboardRenderResult {
        let moduleIDs = configuration.order.filter { configuration.visibleModules.contains($0) }
        let layout: MenuBarDashboardRenderResult.Layout =
            availableWidth < compactWidthThreshold ? .compact : .expanded
        let title = moduleIDs.map { renderModule($0, snapshot: snapshot, configuration: configuration, layout: layout) }
            .joined(separator: layout == .compact ? " · " : "   ")
        return MenuBarDashboardRenderResult(layout: layout, title: title.isEmpty ? "Needlbar" : title, moduleIDs: moduleIDs)
    }

    private static func renderModule(
        _ id: MonitorModuleID,
        snapshot: CombinedUsageSnapshot,
        configuration: SystemMonitorConfiguration,
        layout: MenuBarDashboardRenderResult.Layout
    ) -> String {
        let label = MenuBarMonitorModule.module(for: id).label
        switch id {
        case .cpu:
            return "\(label) \(percentage(snapshot.system?.cpu.totalUsage))"
        case .memory:
            return "\(label) \(bytes(snapshot.system?.memory.usedBytes))"
        case .disk:
            return "\(label) \(bytes(snapshot.system?.disks.first?.usedBytes))"
        case .network:
            let upload = transfer(snapshot.system?.network.uploadBytesPerSecond)
            let download = transfer(snapshot.system?.network.downloadBytesPerSecond)
            return layout == .compact ? "\(label) ↑\(upload) ↓\(download)" : "\(label) ↑\(upload) ↓\(download)"
        case .battery:
            return "\(label) \(percentage(snapshot.system?.battery.level))"
        case .ai:
            return renderAI(snapshot: snapshot, configuration: configuration)
        }
    }

    private static func renderAI(
        snapshot: CombinedUsageSnapshot,
        configuration: SystemMonitorConfiguration
    ) -> String {
        let values = configuration.aiOrder.compactMap { provider -> String? in
            guard configuration.ai[provider]?.isVisible ?? true else { return nil }
            let preference = configuration.ai[provider] ?? AIProviderDisplayPreference()
            let providerSnapshot = snapshot.providers.first { $0.provider == provider }
            return "\(providerLabel(provider)) \(providerValue(preference.metric, snapshot: providerSnapshot))"
        }
        return "AI \(values.isEmpty ? "—" : values.joined(separator: ", "))"
    }

    private static func providerValue(_ metric: AIProviderDisplayMetric, snapshot: ProviderSnapshot?) -> String {
        guard let snapshot else { return "—" }
        switch metric {
        case .usage:
            return snapshot.usage.map { MetricFormatter.tokens($0.today.totalTokens) } ?? "—"
        case .remaining:
            return HeadlineQuotaSelector.mostConstrained([snapshot]).map {
                MetricFormatter.quotaRemaining($0.remainingPercent)
            } ?? "—"
        case .cost:
            return snapshot.usage.map { MetricFormatter.costUSD($0.today.estimatedCostUSD) } ?? "—"
        case .connectionStatus:
            switch snapshot.usageStatus {
            case .fresh: return "Connected"
            case .stale: return "Stale"
            case .requiresAuthentication: return "Sign in"
            case .unavailable: return "Unavailable"
            case .error: return "Error"
            }
        }
    }

    private static func providerLabel(_ provider: ProviderID) -> String {
        switch provider {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        }
    }

    private static func percentage(_ value: MetricPercentage?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.value.rounded()))%"
    }

    private static func bytes(_ value: UInt64?) -> String {
        guard let value else { return "—" }
        return format(value, units: ["B", "KB", "MB", "GB", "TB"])
    }

    private static func transfer(_ value: UInt64?) -> String {
        guard let value else { return "—" }
        return format(value, units: ["B/s", "KB/s", "MB/s", "GB/s"])
    }

    private static func format(_ value: UInt64, units: [String]) -> String {
        var amount = Double(value)
        var index = 0
        while amount >= 1_000 && index < units.count - 1 {
            amount /= 1_000
            index += 1
        }
        if index == 0 { return "\(value) \(units[index])" }
        return String(format: "%.1f %@", amount, units[index])
    }
}
