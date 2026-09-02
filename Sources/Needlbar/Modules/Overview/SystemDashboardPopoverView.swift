import SwiftUI
import NeedlbarCore

public struct SystemDashboardPresentation: Equatable, Sendable {
    public struct CPU: Equatable, Sendable {
        public let usage: String
        public let perCoreUsage: [String]
    }

    public struct Memory: Equatable, Sendable {
        public let used: String
        public let free: String
        public let swap: String
        public let pressure: String
    }

    public struct Disk: Equatable, Sendable {
        public let name: String
        public let used: String
        public let free: String
        public let read: String
        public let write: String
    }

    public struct Network: Equatable, Sendable {
        public let upload: String
        public let download: String
        public let localIPAddresses: [String]
        public let publicIPAddress: String?
    }

    public struct Battery: Equatable, Sendable {
        public let level: String
        public let status: String
        public let health: String
    }

    public struct AIProvider: Equatable, Sendable {
        public let provider: ProviderID
        public let value: String
        public let usageStatus: PresentationFreshness
        public let quotaStatus: PresentationFreshness
    }

    public let moduleIDs: [MonitorModuleID]
    public let cpu: CPU
    public let memory: Memory
    public let disk: Disk
    public let network: Network
    public let battery: Battery
    public let ai: [AIProvider]

    public init(snapshot: CombinedUsageSnapshot, configuration: SystemMonitorConfiguration) {
        let system = snapshot.system
        cpu = CPU(
            usage: Self.percentage(system?.cpu.totalUsage),
            perCoreUsage: system?.cpu.perCoreUsage.map(Self.percentage) ?? []
        )
        memory = Memory(
            used: Self.bytes(system?.memory.usedBytes),
            free: Self.bytes(system?.memory.freeBytes),
            swap: Self.bytes(system?.memory.swapUsedBytes),
            pressure: system?.memory.pressure ?? "—"
        )
        let volume = system?.disks.first
        disk = Disk(
            name: volume?.name ?? "—",
            used: Self.bytes(volume?.usedBytes),
            free: Self.bytes(volume?.freeBytes),
            read: Self.transfer(volume?.readBytesPerSecond),
            write: Self.transfer(volume?.writeBytesPerSecond)
        )
        network = Network(
            upload: Self.transfer(system?.network.uploadBytesPerSecond),
            download: Self.transfer(system?.network.downloadBytesPerSecond),
            localIPAddresses: system?.network.localIPAddresses ?? [],
            publicIPAddress: configuration.publicIPEnabled ? system?.network.publicIPAddress : nil
        )
        battery = Battery(
            level: Self.percentage(system?.battery.level),
            status: Self.batteryStatus(system?.battery.isCharging),
            health: Self.percentage(system?.battery.health)
        )
        ai = configuration.aiOrder.map { provider in
            let snapshot = snapshot.providers.first { $0.provider == provider }
            let preference = configuration.ai[provider] ?? AIProviderDisplayPreference()
            return AIProvider(
                provider: provider,
                value: Self.providerValue(preference.metric, snapshot: snapshot),
                usageStatus: PresentationFreshness(snapshot?.usageStatus ?? .unavailable),
                quotaStatus: PresentationFreshness(snapshot?.quotaStatus ?? .unavailable)
            )
        }
        let configuredOrder = configuration.order
        moduleIDs = configuredOrder.count == MonitorModuleID.allCases.count
            && Set(configuredOrder) == Set(MonitorModuleID.allCases)
            ? configuredOrder
            : MonitorModuleID.defaultOrder
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
        return index == 0 ? "\(value) \(units[index])" : String(format: "%.1f %@", amount, units[index])
    }

    private static func batteryStatus(_ charging: Bool?) -> String {
        guard let charging else { return "—" }
        return charging ? "Charging" : "On battery"
    }
}

public struct SystemDashboardPopoverView: View {
    private let presentation: SystemDashboardPresentation
    private let onShowSettings: () -> Void
    private let onShowAnalytics: () -> Void
    private let onProviderAction: (ProviderID) -> Void

    public init(
        snapshot: CombinedUsageSnapshot,
        configuration: ModuleConfiguration,
        onShowSettings: @escaping () -> Void = {},
        onShowAnalytics: @escaping () -> Void = {},
        onProviderAction: @escaping (ProviderID) -> Void = { _ in }
    ) {
        presentation = SystemDashboardPresentation(snapshot: snapshot, configuration: configuration.systemMonitor)
        self.onShowSettings = onShowSettings
        self.onShowAnalytics = onShowAnalytics
        self.onProviderAction = onProviderAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Needlbar").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(presentation.moduleIDs, id: \.self) { module in
                        section(module)
                    }
                }
            }
            Divider()
            HStack {
                Button("Settings", action: onShowSettings)
                Spacer()
                Button("Analytics…", action: onShowAnalytics)
            }
        }
        .padding()
        .frame(width: 360)
    }

    @ViewBuilder
    private func section(_ module: MonitorModuleID) -> some View {
        switch module {
        case .cpu:
            GroupBox("CPU") {
                metricRow("Usage", presentation.cpu.usage)
                if !presentation.cpu.perCoreUsage.isEmpty {
                    metricRow("Per core", presentation.cpu.perCoreUsage.joined(separator: ", "))
                }
            }
        case .memory:
            GroupBox("RAM") {
                metricRow("Used", presentation.memory.used)
                metricRow("Free", presentation.memory.free)
                metricRow("Swap", presentation.memory.swap)
                metricRow("Pressure", presentation.memory.pressure)
            }
        case .disk:
            GroupBox("Disk") {
                metricRow(presentation.disk.name, "Used \(presentation.disk.used) · Free \(presentation.disk.free)")
                metricRow("Read", presentation.disk.read)
                metricRow("Write", presentation.disk.write)
            }
        case .network:
            GroupBox("Network") {
                metricRow("Upload", presentation.network.upload)
                metricRow("Download", presentation.network.download)
                metricRow("Local IP", presentation.network.localIPAddresses.joined(separator: ", ").isEmpty ? "—" : presentation.network.localIPAddresses.joined(separator: ", "))
                if let publicIP = presentation.network.publicIPAddress {
                    metricRow("Public IP", publicIP)
                }
            }
        case .battery:
            GroupBox("Battery") {
                metricRow("Level", presentation.battery.level)
                metricRow("Status", presentation.battery.status)
                metricRow("Health", presentation.battery.health)
            }
        case .ai:
            GroupBox("AI Usage") {
                ForEach(presentation.ai, id: \.provider) { provider in
                    HStack {
                        Text(provider.provider.displayName)
                        Spacer()
                        Text(provider.value)
                        if provider.usageStatus != .fresh || provider.quotaStatus != .fresh {
                            Button("Connect") { onProviderAction(provider.provider) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
    }
}
