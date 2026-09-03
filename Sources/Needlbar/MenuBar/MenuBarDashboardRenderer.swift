import AppKit
import Foundation
import NeedlbarCore

public struct MenuBarDashboardValuePart: Equatable, Sendable {
    public let text: String
    public let widthSamples: [String]

    public init(_ text: String, samples: [String]) {
        self.text = text
        self.widthSamples = samples
    }
}

public struct MenuBarDashboardSegment: Equatable, Sendable {
    public let moduleID: MonitorModuleID
    public let label: String
    public let compactLabel: String
    public let primary: MenuBarDashboardValuePart
    public let secondary: MenuBarDashboardValuePart?
    public let providerOverflowCount: Int

    public init(
        _ moduleID: MonitorModuleID,
        label: String,
        primary: MenuBarDashboardValuePart,
        secondary: MenuBarDashboardValuePart? = nil,
        providerOverflowCount: Int = 0,
        compactLabel: String? = nil
    ) {
        self.moduleID = moduleID
        self.label = label
        self.primary = primary
        self.secondary = secondary
        self.providerOverflowCount = providerOverflowCount
        self.compactLabel = compactLabel ?? label
    }
}

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
    public let segments: [MenuBarDashboardSegment]
    public let textCandidates: [String]

    public init(
        layout: Layout,
        title: String,
        moduleIDs: [MonitorModuleID],
        configuredModuleIDs: [MonitorModuleID]? = nil,
        tooltip: String? = nil,
        usesIconFallback: Bool = false,
        segments: [MenuBarDashboardSegment] = [],
        textCandidates: [String] = []
    ) {
        self.layout = layout
        self.title = title
        self.moduleIDs = moduleIDs
        self.configuredModuleIDs = configuredModuleIDs ?? moduleIDs
        self.tooltip = tooltip ?? title
        self.usesIconFallback = usesIconFallback
        self.segments = segments
        self.textCandidates = textCandidates
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
            usesIconFallback: fitted.usesIconFallback,
            segments: configuredModuleIDs.map {
                segment($0, snapshot: snapshot, configuration: configuration)
            },
            textCandidates: textCandidates(
                configuredModuleIDs, snapshot: snapshot, configuration: configuration
            )
        )
    }

    private static let percentSamples = ["100%", "—"]

    private static func segment(
        _ id: MonitorModuleID,
        snapshot: CombinedUsageSnapshot,
        configuration: SystemMonitorConfiguration
    ) -> MenuBarDashboardSegment {
        switch id {
        case .cpu:
            return .init(
                id,
                label: "CPU",
                primary: .init(percentage(snapshot.system?.cpu.totalUsage), samples: percentSamples)
            )
        case .memory:
            let memory = snapshot.system?.memory
            return .init(
                id,
                label: "RAM",
                primary: .init(
                    percentage(used: memory?.usedBytes, free: memory?.freeBytes),
                    samples: percentSamples
                )
            )
        case .disk:
            let disk = snapshot.system?.disks.first
            return .init(
                id,
                label: "Disk",
                primary: .init(
                    percentage(used: disk?.usedBytes, free: disk?.freeBytes),
                    samples: percentSamples
                ),
                compactLabel: "DSK"
            )
        case .network:
            let rates = ["999B", "999.9K", "999.9M", "999.9G", "—"]
            return .init(
                id,
                label: "NET",
                primary: .init(
                    "↑" + compactTransfer(snapshot.system?.network.uploadBytesPerSecond),
                    samples: rates.map { "↑" + $0 }
                ),
                secondary: .init(
                    "↓" + compactTransfer(snapshot.system?.network.downloadBytesPerSecond),
                    samples: rates.map { "↓" + $0 }
                )
            )
        case .battery:
            return .init(
                id,
                label: "BAT",
                primary: .init(percentage(snapshot.system?.battery.level), samples: percentSamples)
            )
        case .ai:
            let providers = configuration.aiOrder.filter {
                configuration.ai[$0]?.isVisible ?? true
            }
            guard let provider = providers.first else {
                return .init(id, label: "AI", primary: .init("—", samples: percentSamples))
            }

            let preference = configuration.ai[provider] ?? AIProviderDisplayPreference()
            let samples: [String]
            switch preference.metric {
            case .remaining:
                samples = percentSamples
            case .usage:
                samples = ["999", "999.99K", "999.99M", "999.99B", "—"]
            case .cost:
                samples = ["$999,999.99", "—"]
            case .connectionStatus:
                samples = ["Connected", "Unavailable", "Sign in", "Stale", "Error", "—"]
            }
            return .init(
                id,
                label: providerLabel(provider),
                primary: .init(
                    providerValue(
                        preference.metric,
                        snapshot: snapshot.providers.first { $0.provider == provider }
                    ),
                    samples: samples
                ),
                providerOverflowCount: max(0, providers.count - 1),
                compactLabel: compactProviderLabel(provider)
            )
        }
    }

    private static func textCandidates(
        _ ids: [MonitorModuleID],
        snapshot: CombinedUsageSnapshot,
        configuration: SystemMonitorConfiguration
    ) -> [String] {
        guard !ids.isEmpty else { return [] }
        return stride(from: min(3, ids.count), through: 1, by: -1).flatMap { count in
            [MenuBarDashboardRenderResult.Layout.compact, .expanded].map { layout in
                title(
                    modules: Array(ids.prefix(count)),
                    omittedCount: ids.count - count,
                    snapshot: snapshot,
                    configuration: configuration,
                    layout: layout
                )
            }
        }
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
