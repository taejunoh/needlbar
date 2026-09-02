import AppKit
import Foundation
import NeedlbarCore

public struct MenuBarDashboardRenderResult: Equatable, Sendable {
    public enum Layout: Equatable, Sendable {
        case expanded
        case compact
    }

    public let layout: Layout
    public let title: String
    /// The modules actually represented in `title`, in configured order.
    public let moduleIDs: [MonitorModuleID]
    /// The visible modules configured by the user, before width fitting.
    public let configuredModuleIDs: [MonitorModuleID]
    /// The complete, uncropped title shown by the status item tooltip.
    public let tooltip: String
    /// True when the available width can only accommodate the menu-bar icon.
    public let usesIconFallback: Bool

    public init(
        layout: Layout,
        title: String,
        moduleIDs: [MonitorModuleID],
        configuredModuleIDs: [MonitorModuleID]? = nil,
        tooltip: String? = nil,
        usesIconFallback: Bool = false
    ) {
        self.layout = layout
        self.title = title
        self.moduleIDs = moduleIDs
        self.configuredModuleIDs = configuredModuleIDs ?? moduleIDs
        self.tooltip = tooltip ?? title
        self.usesIconFallback = usesIconFallback
    }
}

public enum MenuBarDashboardRenderer {
    public static let compactWidthThreshold: Double = 240

    public static func render(
        snapshot: CombinedUsageSnapshot,
        configuration: SystemMonitorConfiguration,
        availableWidth: Double
    ) -> MenuBarDashboardRenderResult {
        let configuredModuleIDs = orderedVisibleModules(configuration)
        let measuredBudget = availableWidth == .infinity
            ? compactWidthThreshold
            : min(compactWidthThreshold, availableWidth)
        let layout: MenuBarDashboardRenderResult.Layout =
            measuredBudget.isFinite && measuredBudget <= compactWidthThreshold ? .compact : .expanded
        let completeTitle = configuredModuleIDs
            .map { renderModule($0, snapshot: snapshot, configuration: configuration, layout: .expanded) }
            .joined(separator: "   ")
        let tooltip = completeTitle.isEmpty ? "Needlbar" : completeTitle

        let fitted = fit(
            configuredModuleIDs,
            snapshot: snapshot,
            configuration: configuration,
            layout: layout,
            availableWidth: availableWidth
        )
        return MenuBarDashboardRenderResult(
            // `fit` may choose compact spelling even when the caller supplied a
            // wide budget, so report the layout actually rendered.
            layout: fitted.layout,
            title: fitted.title,
            moduleIDs: fitted.moduleIDs,
            configuredModuleIDs: configuredModuleIDs,
            tooltip: tooltip,
            usesIconFallback: fitted.usesIconFallback
        )
    }

    private static func fit(
        _ configuredModuleIDs: [MonitorModuleID],
        snapshot: CombinedUsageSnapshot,
        configuration: SystemMonitorConfiguration,
        layout: MenuBarDashboardRenderResult.Layout,
        availableWidth: Double
    ) -> (title: String, layout: MenuBarDashboardRenderResult.Layout, moduleIDs: [MonitorModuleID], usesIconFallback: Bool) {
        let effectiveWidth = availableWidth == .infinity
            ? compactWidthThreshold
            : min(compactWidthThreshold, availableWidth)
        guard effectiveWidth.isFinite, effectiveWidth >= 22 else { return ("", layout, [], true) }

        let maximumModules = min(3, configuredModuleIDs.count)
        let alternateLayout: MenuBarDashboardRenderResult.Layout =
            layout == .expanded ? .compact : .expanded
        // Preserve as many configured modules as possible before choosing the more
        // compact spelling. This prevents a long expanded label from hiding a
        // module that would fit with compact labels.
        for count in stride(from: maximumModules, through: 1, by: -1) {
            for candidateLayout in [layout, alternateLayout] {
                let shown = Array(configuredModuleIDs.prefix(count))
                let omittedCount = configuredModuleIDs.count - count
                let candidate = title(
                    modules: shown,
                    omittedCount: omittedCount,
                    snapshot: snapshot,
                    configuration: configuration,
                    layout: candidateLayout
                )
                // An overflow marker without a rendered module is not useful to
                // VoiceOver or sighted users; use the explicit icon fallback instead.
                if measuredWidth(candidate) <= effectiveWidth {
                    return (candidate, candidateLayout, shown, false)
                }
            }
        }

        return ("", layout, [], true)
    }

    private static func title(
        modules: [MonitorModuleID],
        omittedCount: Int,
        snapshot: CombinedUsageSnapshot,
        configuration: SystemMonitorConfiguration,
        layout: MenuBarDashboardRenderResult.Layout
    ) -> String {
        var values = modules.map {
            renderModule($0, snapshot: snapshot, configuration: configuration, layout: layout)
        }
        if omittedCount > 0 {
            values.append("+\(omittedCount)")
        }
        return values.joined(separator: layout == .compact ? " · " : "   ")
    }

    private static func orderedVisibleModules(_ configuration: SystemMonitorConfiguration) -> [MonitorModuleID] {
        var seen = Set<MonitorModuleID>()
        return configuration.order.filter {
            configuration.visibleModules.contains($0) && seen.insert($0).inserted
        }
    }

    private static func measuredWidth(_ string: String) -> Double {
        let font = NSFont.menuFont(ofSize: 0)
        return Double((string as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func renderModule(
        _ id: MonitorModuleID,
        snapshot: CombinedUsageSnapshot,
        configuration: SystemMonitorConfiguration,
        layout: MenuBarDashboardRenderResult.Layout
    ) -> String {
        switch id {
        case .cpu:
            return "CPU \(percentage(snapshot.system?.cpu.totalUsage))"
        case .memory:
            let memory = snapshot.system?.memory
            return "RAM \(percentage(used: memory?.usedBytes, free: memory?.freeBytes))"
        case .disk:
            let volume = snapshot.system?.disks.first
            return "DSK \(percentage(used: volume?.usedBytes, free: volume?.freeBytes))"
        case .network:
            let upload = layout == .compact
                ? compactTransfer(snapshot.system?.network.uploadBytesPerSecond)
                : transfer(snapshot.system?.network.uploadBytesPerSecond)
            let download = layout == .compact
                ? compactTransfer(snapshot.system?.network.downloadBytesPerSecond)
                : transfer(snapshot.system?.network.downloadBytesPerSecond)
            return "NET ↑\(upload) ↓\(download)"
        case .battery:
            return "BAT \(percentage(snapshot.system?.battery.level))"
        case .ai:
            return renderAI(snapshot: snapshot, configuration: configuration, compact: layout == .compact)
        }
    }

    private static func renderAI(
        snapshot: CombinedUsageSnapshot,
        configuration: SystemMonitorConfiguration,
        compact: Bool
    ) -> String {
        let providers = configuration.aiOrder.filter { configuration.ai[$0]?.isVisible ?? true }
        let values = providers.prefix(compact ? 1 : providers.count).compactMap { provider -> String? in
            let preference = configuration.ai[provider] ?? AIProviderDisplayPreference()
            let providerSnapshot = snapshot.providers.first { $0.provider == provider }
            let value = providerValue(preference.metric, snapshot: providerSnapshot)
            let label = compact ? compactProviderLabel(provider) : providerLabel(provider)
            return "\(label) \(value)"
        }
        guard !values.isEmpty else { return "AI —" }
        let remaining = compact ? providers.count - values.count : 0
        return "AI \(values.joined(separator: " · "))\(remaining > 0 ? " +\(remaining)" : "")"
    }

    private static func providerValue(_ metric: AIProviderDisplayMetric, snapshot: ProviderSnapshot?) -> String {
        guard let snapshot else { return "—" }
        switch metric {
        case .usage:
            return snapshot.usage.map { tokens($0.today.totalTokens) } ?? "—"
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

    private static func compactProviderLabel(_ provider: ProviderID) -> String {
        switch provider {
        case .claude: return "CL"
        case .codex: return "CX"
        case .cursor: return "CU"
        }
    }

    private static func percentage(_ value: MetricPercentage?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.value.rounded()))%"
    }

    private static func percentage(used: UInt64?, free: UInt64?) -> String {
        guard let used, let free else { return "—" }
        let total = used.addingReportingOverflow(free)
        guard !total.overflow, total.partialValue > 0 else { return "—" }
        return "\(Int((Double(used) / Double(total.partialValue) * 100).rounded()))%"
    }

    private static func tokens(_ value: UInt64) -> String {
        switch value {
        case 1_000_000_000...:
            return compact(Double(value) / 1_000_000_000, suffix: "B")
        case 1_000_000...:
            return compact(Double(value) / 1_000_000, suffix: "M")
        case 1_000...:
            return compact(Double(value) / 1_000, suffix: "K")
        default:
            return String(value)
        }
    }

    private static func compact(_ value: Double, suffix: String) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression) + suffix
    }

    private static func transfer(_ value: UInt64?) -> String {
        guard let value else { return "—" }
        return format(value, units: ["B/s", "KB/s", "MB/s", "GB/s"])
    }

    private static func compactTransfer(_ value: UInt64?) -> String {
        guard let value else { return "—" }
        var amount = Double(value)
        var index = 0
        let units = ["B", "K", "M", "G"]
        while amount >= 1_000 && index < units.count - 1 {
            amount /= 1_000
            index += 1
        }
        if index == 0 { return "\(value)B" }
        return String(format: "%.1f%@", locale: Locale(identifier: "en_US_POSIX"), amount, units[index])
            .replacingOccurrences(of: #"\.0([KMGB])$"#, with: "$1", options: .regularExpression)
    }

    private static func format(_ value: UInt64, units: [String]) -> String {
        var amount = Double(value)
        var index = 0
        while amount >= 1_000 && index < units.count - 1 {
            amount /= 1_000
            index += 1
        }
        if index == 0 { return "\(value) \(units[index])" }
        return String(
            format: "%.1f %@",
            locale: Locale(identifier: "en_US_POSIX"),
            amount,
            units[index]
        )
    }
}
