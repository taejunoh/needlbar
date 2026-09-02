import Foundation

public struct MetricPercentage: Equatable, Sendable {
    public let value: Double

    public init?(_ value: Double?) {
        guard let value, value.isFinite, (0...100).contains(value) else { return nil }
        self.value = value
    }
}

public enum MetricAvailability: Equatable, Sendable {
    case fresh(capturedAt: Date)
    case stale(lastSuccessfulAt: Date)
    case unavailable(code: String)
}

public enum MonitorModuleID: String, CaseIterable, Codable, Sendable {
    case cpu
    case memory
    case disk
    case network
    case battery
    case ai

    public static let defaultOrder: [MonitorModuleID] = [.cpu, .memory, .disk, .network, .battery, .ai]
}

public enum AIProviderDisplayMetric: String, CaseIterable, Codable, Sendable {
    case usage
    case remaining
    case cost
    case connectionStatus
}

public struct AIProviderDisplayPreference: Codable, Equatable, Sendable {
    public var isVisible: Bool
    public var metric: AIProviderDisplayMetric

    public init(isVisible: Bool = true, metric: AIProviderDisplayMetric = .usage) {
        self.isVisible = isVisible
        self.metric = metric
    }
}

public struct SystemMetricsSnapshot: Equatable, Sendable {
    public struct CPU: Equatable, Sendable {
        public let totalUsage: MetricPercentage?
        public let perCoreUsage: [MetricPercentage]

        public init(totalUsage: MetricPercentage?, perCoreUsage: [MetricPercentage]) {
            self.totalUsage = totalUsage
            self.perCoreUsage = perCoreUsage
        }
    }

    public struct Memory: Equatable, Sendable {
        public let usedBytes: UInt64?
        public let freeBytes: UInt64?
        public let swapUsedBytes: UInt64?
        public let pressure: String?

        public init(usedBytes: UInt64?, freeBytes: UInt64?, swapUsedBytes: UInt64?, pressure: String?) {
            self.usedBytes = usedBytes
            self.freeBytes = freeBytes
            self.swapUsedBytes = swapUsedBytes
            self.pressure = pressure
        }
    }

    public struct DiskVolume: Equatable, Sendable {
        public let name: String
        public let usedBytes: UInt64?
        public let freeBytes: UInt64?
        public let readBytesPerSecond: UInt64?
        public let writeBytesPerSecond: UInt64?

        public init(
            name: String,
            usedBytes: UInt64?,
            freeBytes: UInt64?,
            readBytesPerSecond: UInt64?,
            writeBytesPerSecond: UInt64?
        ) {
            self.name = name
            self.usedBytes = usedBytes
            self.freeBytes = freeBytes
            self.readBytesPerSecond = readBytesPerSecond
            self.writeBytesPerSecond = writeBytesPerSecond
        }
    }

    public struct Network: Equatable, Sendable {
        public let uploadBytesPerSecond: UInt64?
        public let downloadBytesPerSecond: UInt64?
        public let localIPAddresses: [String]
        public let publicIPAddress: String?

        public init(
            uploadBytesPerSecond: UInt64?,
            downloadBytesPerSecond: UInt64?,
            localIPAddresses: [String],
            publicIPAddress: String?
        ) {
            self.uploadBytesPerSecond = uploadBytesPerSecond
            self.downloadBytesPerSecond = downloadBytesPerSecond
            self.localIPAddresses = localIPAddresses
            self.publicIPAddress = publicIPAddress
        }
    }

    public struct Battery: Equatable, Sendable {
        public let level: MetricPercentage?
        public let isCharging: Bool?
        public let health: MetricPercentage?

        public init(level: MetricPercentage?, isCharging: Bool?, health: MetricPercentage?) {
            self.level = level
            self.isCharging = isCharging
            self.health = health
        }
    }

    public let capturedAt: Date
    public let cpu: CPU
    public let memory: Memory
    public let disks: [DiskVolume]
    public let network: Network
    public let battery: Battery
    public let availability: [MonitorModuleID: MetricAvailability]

    public init(
        capturedAt: Date,
        cpu: CPU,
        memory: Memory,
        disks: [DiskVolume],
        network: Network,
        battery: Battery,
        availability: [MonitorModuleID: MetricAvailability]
    ) {
        self.capturedAt = capturedAt
        self.cpu = cpu
        self.memory = memory
        self.disks = disks
        self.network = network
        self.battery = battery
        self.availability = availability
    }
}

public struct SystemMonitorConfiguration: Codable, Equatable, Sendable {
    public var order: [MonitorModuleID]
    public var visibleModules: Set<MonitorModuleID>
    public var publicIPEnabled: Bool
    public var aiOrder: [ProviderID]
    public var ai: [ProviderID: AIProviderDisplayPreference]

    public init(
        order: [MonitorModuleID] = MonitorModuleID.defaultOrder,
        visibleModules: Set<MonitorModuleID> = Set(MonitorModuleID.defaultOrder),
        publicIPEnabled: Bool = false,
        aiOrder: [ProviderID] = ProviderID.allCases,
        ai: [ProviderID: AIProviderDisplayPreference] = Dictionary(
            uniqueKeysWithValues: ProviderID.allCases.map { ($0, AIProviderDisplayPreference()) }
        )
    ) {
        self.order = order
        self.visibleModules = visibleModules
        self.publicIPEnabled = publicIPEnabled
        self.aiOrder = aiOrder
        self.ai = ai
    }
}
