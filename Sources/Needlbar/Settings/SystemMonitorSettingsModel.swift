import Combine
import NeedlbarCore
import SwiftUI

@MainActor
public final class SystemMonitorSettingsModel: ObservableObject {
    @Published public private(set) var value: SystemMonitorConfiguration

    private let configuration: ModuleConfiguration

    public init(configuration: ModuleConfiguration) {
        self.configuration = configuration
        value = configuration.systemMonitor
    }

    public var orderedModules: [MonitorModuleID] {
        value.order
    }

    public var orderedProviders: [ProviderID] {
        value.aiOrder
    }

    public func setVisible(
        _ module: MonitorModuleID,
        _ visible: Bool,
        surface: MonitorDisplaySurface = .menuBar
    ) {
        var next = value
        var modules = surface == .menuBar ? next.menuBarVisibleModules : next.dashboardVisibleModules
        if visible { modules.insert(module) } else { modules.remove(module) }
        if surface == .menuBar { next.menuBarVisibleModules = modules }
        else { next.dashboardVisibleModules = modules }
        commit(next)
    }

    public func isVisible(_ module: MonitorModuleID, surface: MonitorDisplaySurface) -> Bool {
        (surface == .menuBar ? value.menuBarVisibleModules : value.dashboardVisibleModules).contains(module)
    }

    public func isVisible(_ provider: ProviderID, surface: MonitorDisplaySurface) -> Bool {
        let preference = value.ai[provider] ?? AIProviderDisplayPreference()
        return surface == .menuBar ? preference.menuBarVisible : preference.dashboardVisible
    }

    public func move(_ module: MonitorModuleID, before target: MonitorModuleID) {
        guard module != target, value.order.contains(module), value.order.contains(target) else { return }
        var next = value
        next.order.removeAll { $0 == module }
        guard let index = next.order.firstIndex(of: target) else { return }
        next.order.insert(module, at: index)
        commit(next)
    }

    public func moveModules(from offsets: IndexSet, to destination: Int) {
        var next = value
        next.order.move(fromOffsets: offsets, toOffset: destination)
        guard Set(next.order) == Set(MonitorModuleID.allCases), next.order.count == MonitorModuleID.allCases.count else {
            return
        }
        commit(next)
    }

    public func setPublicIPEnabled(_ enabled: Bool) {
        var next = value
        next.publicIPEnabled = enabled
        commit(next)
    }

    public func setLocalIPEnabled(_ enabled: Bool) {
        var next = value
        next.localIPEnabled = enabled
        commit(next)
    }

    public func useCompactDefaults(surface: MonitorDisplaySurface = .menuBar) {
        var next = value
        if surface == .menuBar { next.menuBarVisibleModules = [.cpu, .memory, .ai] }
        else { next.dashboardVisibleModules = [.cpu, .memory, .ai] }
        commit(next)
    }

    public func setAIProvider(
        _ provider: ProviderID,
        visible: Bool? = nil,
        metric: AIProviderDisplayMetric? = nil,
        surface: MonitorDisplaySurface = .menuBar
    ) {
        var next = value
        var preference = next.ai[provider] ?? AIProviderDisplayPreference()
        if let visible {
            if surface == .menuBar { preference.menuBarVisible = visible }
            else { preference.dashboardVisible = visible }
        }
        if let metric {
            preference.metric = metric
        }
        next.ai[provider] = preference
        commit(next)
    }

    public func moveAIProvider(_ provider: ProviderID, before target: ProviderID) {
        guard provider != target, value.aiOrder.contains(provider), value.aiOrder.contains(target) else { return }
        var next = value
        next.aiOrder.removeAll { $0 == provider }
        guard let index = next.aiOrder.firstIndex(of: target) else { return }
        next.aiOrder.insert(provider, at: index)
        commit(next)
    }

    public func moveAIProviders(from offsets: IndexSet, to destination: Int) {
        var next = value
        next.aiOrder.move(fromOffsets: offsets, toOffset: destination)
        guard Set(next.aiOrder) == Set(ProviderID.allCases), next.aiOrder.count == ProviderID.allCases.count else {
            return
        }
        commit(next)
    }

    public func refresh() {
        value = configuration.systemMonitor
    }

    private func commit(_ next: SystemMonitorConfiguration) {
        value = next
        configuration.setSystemMonitor(next)
    }
}
