import NeedlbarCore

public struct MenuBarMonitorModule: Equatable, Sendable {
    public let id: MonitorModuleID
    public let label: String
    public let compactSymbolName: String

    public init(id: MonitorModuleID, label: String, compactSymbolName: String) {
        self.id = id
        self.label = label
        self.compactSymbolName = compactSymbolName
    }

    public static let cpu = MenuBarMonitorModule(id: .cpu, label: "CPU", compactSymbolName: "cpu")
    public static let memory = MenuBarMonitorModule(id: .memory, label: "RAM", compactSymbolName: "memorychip")
    public static let disk = MenuBarMonitorModule(id: .disk, label: "Disk", compactSymbolName: "internaldrive")
    public static let network = MenuBarMonitorModule(id: .network, label: "NET", compactSymbolName: "network")
    public static let battery = MenuBarMonitorModule(id: .battery, label: "BAT", compactSymbolName: "battery.100")
    public static let ai = MenuBarMonitorModule(id: .ai, label: "AI", compactSymbolName: "sparkles")

    public static let all: [MenuBarMonitorModule] = [cpu, memory, disk, network, battery, ai]

    public static func module(for id: MonitorModuleID) -> MenuBarMonitorModule {
        all.first { $0.id == id } ?? cpu
    }
}
