import Combine
import Foundation
import NeedlbarCore

public enum DashboardFreshness: Equatable, Sendable {
    case fresh
    case stale
    case unavailable

    init(_ availability: MetricAvailability?) {
        switch availability {
        case .fresh:
            self = .fresh
        case .stale:
            self = .stale
        case .unavailable, .none:
            self = .unavailable
        }
    }

    public var label: String {
        switch self {
        case .fresh: "Fresh"
        case .stale: "Stale"
        case .unavailable: "Unavailable"
        }
    }
}

public struct SystemDashboardHistory: Equatable, Sendable {
    public struct DiskSample: Equatable, Sendable {
        public let capturedAt: Date
        public let readBytesPerSecond: Double?
        public let writeBytesPerSecond: Double?
    }

    public struct NetworkSample: Equatable, Sendable {
        public let capturedAt: Date
        public let uploadBytesPerSecond: Double?
        public let downloadBytesPerSecond: Double?
    }

    public private(set) var disk: [DiskSample] = []
    public private(set) var network: [NetworkSample] = []

    public init() {}

    mutating func append(_ system: SystemMetricsSnapshot?) {
        guard let system, !network.contains(where: { $0.capturedAt == system.capturedAt }) else { return }

        let diskIsFresh = Self.isFresh(.disk, in: system)
        let networkIsFresh = Self.isFresh(.network, in: system)
        let volume = system.disks.first

        disk.append(DiskSample(
            capturedAt: system.capturedAt,
            readBytesPerSecond: diskIsFresh ? volume?.readBytesPerSecond.map { Double($0) } : nil,
            writeBytesPerSecond: diskIsFresh ? volume?.writeBytesPerSecond.map { Double($0) } : nil
        ))
        network.append(NetworkSample(
            capturedAt: system.capturedAt,
            uploadBytesPerSecond: networkIsFresh ? system.network.uploadBytesPerSecond.map { Double($0) } : nil,
            downloadBytesPerSecond: networkIsFresh ? system.network.downloadBytesPerSecond.map { Double($0) } : nil
        ))
        if disk.count > 60 { disk.removeFirst(disk.count - 60) }
        if network.count > 60 { network.removeFirst(network.count - 60) }
    }

    private static func isFresh(_ module: MonitorModuleID, in system: SystemMetricsSnapshot) -> Bool {
        guard let availability = system.availability[module] else { return false }
        if case .fresh = availability { return true }
        return false
    }
}

public struct SystemDashboardPresentation: Equatable, Sendable {
    public struct CPU: Equatable, Sendable {
        public let usage: String
        public let usagePercent: Double?
        public let perCoreUsage: [String]
        public let perCorePercents: [Double]
        public let freshness: DashboardFreshness
    }

    public struct Memory: Equatable, Sendable {
        public let used: String
        public let available: String
        public let free: String
        public let swap: String
        public let pressure: String
        public let usedPercent: Double?
        public let freshness: DashboardFreshness
    }

    public struct Disk: Equatable, Sendable {
        public let name: String
        public let used: String
        public let free: String
        public let read: String
        public let write: String
        public let usedPercent: Double?
        public let freshness: DashboardFreshness
    }

    public struct Network: Equatable, Sendable {
        public let upload: String
        public let download: String
        public let localIPAddresses: [String]
        public let primaryLocalAddress: String?
        public let additionalLocalAddresses: [String]
        public let publicIPAddress: String?
        public let freshness: DashboardFreshness
    }

    public struct Battery: Equatable, Sendable {
        public let level: String
        public let status: String
        public let health: String
        public let levelPercent: Double?
        public let healthPercent: Double?
        public let freshness: DashboardFreshness
    }

    public struct AIProvider: Equatable, Sendable {
        public let provider: ProviderID
        public let value: String
        public let caption: String
        public let usageStatus: PresentationFreshness
        public let quotaStatus: PresentationFreshness
        public let action: ProviderAuthenticationAction?
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
        let cpuUsage = system?.cpu.totalUsage?.value
        cpu = CPU(
            usage: Self.percentage(system?.cpu.totalUsage),
            usagePercent: cpuUsage,
            perCoreUsage: system?.cpu.perCoreUsage.map(Self.percentage) ?? [],
            perCorePercents: system?.cpu.perCoreUsage.map(\.value) ?? [],
            freshness: DashboardFreshness(snapshot.systemAvailability[.cpu])
        )

        let memoryUsed = system?.memory.usedBytes
        let memoryAvailable = system?.memory.freeBytes
        memory = Memory(
            used: Self.binaryBytes(memoryUsed),
            available: Self.binaryBytes(memoryAvailable),
            free: Self.binaryBytes(memoryAvailable),
            swap: Self.binaryBytes(system?.memory.swapUsedBytes),
            pressure: system?.memory.pressure ?? "—",
            usedPercent: Self.ratioPercent(used: memoryUsed, available: memoryAvailable),
            freshness: DashboardFreshness(snapshot.systemAvailability[.memory])
        )

        let volume = system?.disks.first
        disk = Disk(
            name: volume?.name ?? "—",
            used: Self.decimalBytes(volume?.usedBytes),
            free: Self.decimalBytes(volume?.freeBytes),
            read: Self.transfer(volume?.readBytesPerSecond),
            write: Self.transfer(volume?.writeBytesPerSecond),
            usedPercent: Self.ratioPercent(used: volume?.usedBytes, available: volume?.freeBytes),
            freshness: DashboardFreshness(snapshot.systemAvailability[.disk])
        )

        let addresses = configuration.localIPEnabled ? (system?.network.localIPAddresses ?? []) : []
        let primary = addresses.first(where: Self.isIPv4) ?? addresses.first
        network = Network(
            upload: Self.transfer(system?.network.uploadBytesPerSecond),
            download: Self.transfer(system?.network.downloadBytesPerSecond),
            localIPAddresses: addresses,
            primaryLocalAddress: primary,
            additionalLocalAddresses: addresses.filter { $0 != primary },
            publicIPAddress: configuration.publicIPEnabled ? system?.network.publicIPAddress : nil,
            freshness: DashboardFreshness(snapshot.systemAvailability[.network])
        )

        let batteryLevel = system?.battery.level?.value
        battery = Battery(
            level: Self.percentage(system?.battery.level),
            status: Self.batteryStatus(system?.battery.isCharging),
            health: Self.percentage(system?.battery.health),
            levelPercent: batteryLevel,
            healthPercent: system?.battery.health?.value,
            freshness: DashboardFreshness(snapshot.systemAvailability[.battery])
        )

        ai = configuration.aiOrder.compactMap { provider in
            let preference = configuration.ai[provider] ?? AIProviderDisplayPreference()
            guard preference.isVisible else { return nil }
            let providerSnapshot = snapshot.providers.first { $0.provider == provider }
            let popover = ProviderPopoverPresentation(snapshot: providerSnapshot ?? .unavailable(for: provider))
            return AIProvider(
                provider: provider,
                value: Self.providerValue(preference.metric, snapshot: providerSnapshot),
                caption: Self.providerCaption(preference.metric),
                usageStatus: PresentationFreshness(providerSnapshot?.usageStatus ?? .unavailable),
                quotaStatus: PresentationFreshness(providerSnapshot?.quotaStatus ?? .unavailable),
                action: popover.authenticationAction
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
            return snapshot.usage.map { Self.dashboardTokens($0.today.totalTokens) } ?? "—"
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

    private static func providerCaption(_ metric: AIProviderDisplayMetric) -> String {
        switch metric {
        case .usage: "Tokens today"
        case .remaining: "Most constrained quota remaining"
        case .cost: "Estimated cost today"
        case .connectionStatus: "Connection"
        }
    }

    private static func dashboardTokens(_ value: UInt64) -> String {
        let divisor: Double
        let suffix: String
        switch value {
        case 1_000_000_000...:
            divisor = 1_000_000_000
            suffix = "B"
        case 1_000_000...:
            divisor = 1_000_000
            suffix = "M"
        case 1_000...:
            divisor = 1_000
            suffix = "K"
        default:
            return String(value)
        }
        return String(format: "%.2f", Double(value) / divisor)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression) + suffix
    }

    private static func percentage(_ value: MetricPercentage?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.value.rounded()))%"
    }

    private static func binaryBytes(_ value: UInt64?) -> String {
        format(value, divisor: 1_024, units: ["B", "KiB", "MiB", "GiB", "TiB"])
    }

    private static func decimalBytes(_ value: UInt64?) -> String {
        format(value, divisor: 1_000, units: ["B", "KB", "MB", "GB", "TB"])
    }

    private static func transfer(_ value: UInt64?) -> String {
        format(value, divisor: 1_000, units: ["B/s", "KB/s", "MB/s", "GB/s"])
    }

    private static func format(_ value: UInt64?, divisor: Double, units: [String]) -> String {
        guard let value else { return "—" }
        var amount = Double(value)
        var index = 0
        while amount >= divisor && index < units.count - 1 {
            amount /= divisor
            index += 1
        }
        return index == 0 ? "\(value) \(units[index])" : String(format: "%.1f %@", amount, units[index])
    }

    private static func ratioPercent(used: UInt64?, available: UInt64?) -> Double? {
        guard let used, let available else { return nil }
        let total = used.addingReportingOverflow(available)
        guard !total.overflow, total.partialValue > 0 else { return nil }
        return min(100, (Double(used) / Double(total.partialValue)) * 100)
    }

    private static func batteryStatus(_ charging: Bool?) -> String {
        guard let charging else { return "—" }
        return charging ? "Charging" : "On battery"
    }

    private static func isIPv4(_ address: String) -> Bool {
        address.split(separator: ".").count == 4
    }
}

@MainActor
public final class SystemDashboardModel: ObservableObject {
    @Published public private(set) var presentation: SystemDashboardPresentation
    @Published public private(set) var history: SystemDashboardHistory

    public init(snapshot: CombinedUsageSnapshot, configuration: SystemMonitorConfiguration) {
        presentation = SystemDashboardPresentation(snapshot: snapshot, configuration: configuration)
        var initialHistory = SystemDashboardHistory()
        initialHistory.append(snapshot.system)
        history = initialHistory
    }

    public func update(snapshot: CombinedUsageSnapshot, configuration: SystemMonitorConfiguration) {
        presentation = SystemDashboardPresentation(snapshot: snapshot, configuration: configuration)
        history.append(snapshot.system)
    }
}

private extension ProviderSnapshot {
    static func unavailable(for provider: ProviderID) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: provider,
            usage: nil,
            quota: nil,
            usageStatus: .unavailable,
            quotaStatus: .unavailable,
            updatedAt: .now
        )
    }
}
