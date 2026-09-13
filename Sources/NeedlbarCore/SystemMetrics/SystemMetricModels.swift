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

public enum MonitorDisplaySurface: String, CaseIterable, Sendable {
    case menuBar
    case dashboard
}

public struct AIProviderDisplayPreference: Codable, Equatable, Sendable {
    public var menuBarVisible: Bool
    public var dashboardVisible: Bool
    public var metric: AIProviderDisplayMetric
    public var apiBillingLinkVisible: Bool

    /// Compatibility for callers that explicitly configure both surfaces together.
    public var isVisible: Bool {
        get { menuBarVisible }
        set {
            menuBarVisible = newValue
            dashboardVisible = newValue
        }
    }

    public init(
        isVisible: Bool = true,
        metric: AIProviderDisplayMetric = .remaining,
        dashboardVisible: Bool? = nil,
        apiBillingLinkVisible: Bool = false
    ) {
        menuBarVisible = isVisible
        self.dashboardVisible = dashboardVisible ?? isVisible
        self.metric = metric
        self.apiBillingLinkVisible = apiBillingLinkVisible
    }

    private enum CodingKeys: String, CodingKey {
        case menuBarVisible, dashboardVisible, isVisible, metric, apiBillingLinkVisible
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let shared = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        menuBarVisible = try container.decodeIfPresent(Bool.self, forKey: .menuBarVisible) ?? shared
        dashboardVisible = try container.decodeIfPresent(Bool.self, forKey: .dashboardVisible) ?? shared
        metric = try container.decodeIfPresent(AIProviderDisplayMetric.self, forKey: .metric) ?? .remaining
        apiBillingLinkVisible = (try? container.decode(Bool.self, forKey: .apiBillingLinkVisible)) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(menuBarVisible, forKey: .menuBarVisible)
        try container.encode(dashboardVisible, forKey: .dashboardVisible)
        try container.encode(metric, forKey: .metric)
        try container.encode(apiBillingLinkVisible, forKey: .apiBillingLinkVisible)
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
    public var menuBarVisibleModules: Set<MonitorModuleID>
    public var dashboardVisibleModules: Set<MonitorModuleID>
    /// Compatibility for callers that explicitly configure both surfaces together.
    public var visibleModules: Set<MonitorModuleID> {
        get { menuBarVisibleModules }
        set {
            menuBarVisibleModules = newValue
            dashboardVisibleModules = newValue
        }
    }
    /// Allows the dashboard to disclose active local IPv4 addresses.
    /// Public IP display is controlled independently by `publicIPEnabled`.
    public var localIPEnabled: Bool
    public var publicIPEnabled: Bool
    public var aiOrder: [ProviderID]
    public var ai: [ProviderID: AIProviderDisplayPreference]

    public init(
        order: [MonitorModuleID] = MonitorModuleID.defaultOrder,
        visibleModules: Set<MonitorModuleID> = Set([.cpu, .memory, .ai]),
        publicIPEnabled: Bool = false,
        aiOrder: [ProviderID] = ProviderID.allCases,
        ai: [ProviderID: AIProviderDisplayPreference] = Dictionary(
            uniqueKeysWithValues: ProviderID.allCases.map { ($0, AIProviderDisplayPreference()) }
        ),
        localIPEnabled: Bool = false,
        dashboardVisibleModules: Set<MonitorModuleID>? = nil
    ) {
        self.order = order
        self.menuBarVisibleModules = visibleModules
        self.dashboardVisibleModules = dashboardVisibleModules ?? visibleModules
        self.localIPEnabled = localIPEnabled
        self.publicIPEnabled = publicIPEnabled
        self.aiOrder = aiOrder
        self.ai = ai
    }

    private enum CodingKeys: String, CodingKey {
        case order, visibleModules, menuBarVisibleModules, dashboardVisibleModules
        case localIPEnabled, publicIPEnabled, aiOrder, ai
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let shared = try container.decodeIfPresent(Set<MonitorModuleID>.self, forKey: .visibleModules)
            ?? Set([.cpu, .memory, .ai])
        self.init(
            order: try container.decodeIfPresent([MonitorModuleID].self, forKey: .order) ?? MonitorModuleID.defaultOrder,
            visibleModules: try container.decodeIfPresent(Set<MonitorModuleID>.self, forKey: .menuBarVisibleModules) ?? shared,
            publicIPEnabled: try container.decodeIfPresent(Bool.self, forKey: .publicIPEnabled) ?? false,
            aiOrder: try container.decodeIfPresent([ProviderID].self, forKey: .aiOrder) ?? ProviderID.allCases,
            ai: try container.decodeIfPresent([ProviderID: AIProviderDisplayPreference].self, forKey: .ai)
                ?? Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, AIProviderDisplayPreference()) }),
            localIPEnabled: try container.decodeIfPresent(Bool.self, forKey: .localIPEnabled) ?? false,
            dashboardVisibleModules: try container.decodeIfPresent(Set<MonitorModuleID>.self, forKey: .dashboardVisibleModules) ?? shared
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(order, forKey: .order)
        try container.encode(menuBarVisibleModules, forKey: .menuBarVisibleModules)
        try container.encode(dashboardVisibleModules, forKey: .dashboardVisibleModules)
        try container.encode(localIPEnabled, forKey: .localIPEnabled)
        try container.encode(publicIPEnabled, forKey: .publicIPEnabled)
        try container.encode(aiOrder, forKey: .aiOrder)
        try container.encode(ai, forKey: .ai)
    }
}
