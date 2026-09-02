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

    public func setVisible(_ module: MonitorModuleID, _ visible: Bool) {
        var next = value
        if visible {
            next.visibleModules.insert(module)
        } else {
            next.visibleModules.remove(module)
        }
        commit(next)
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

    public func setAIProvider(
        _ provider: ProviderID,
        visible: Bool? = nil,
        metric: AIProviderDisplayMetric? = nil
    ) {
        var next = value
        var preference = next.ai[provider] ?? AIProviderDisplayPreference()
        if let visible {
            preference.isVisible = visible
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

public struct SystemMonitorSettingsView: View {
    @ObservedObject private var model: SystemMonitorSettingsModel

    public init(model: SystemMonitorSettingsModel) {
        _model = ObservedObject(wrappedValue: model)
    }

    public var body: some View {
        Section("Menu bar modules") {
            Text("Choose which modules use space in the menu bar. The dashboard popover always includes all six modules.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(model.orderedModules, id: \.self) { module in
                HStack {
                    Label(module.title, systemImage: module.systemImage)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.value.visibleModules.contains(module) },
                        set: { model.setVisible(module, $0) }
                    ))
                    .labelsHidden()
                }
            }
            .onMove(perform: model.moveModules)

            if !model.value.order.isEmpty {
                Text("Drag order is preserved in the compact and expanded layouts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Show public IP address", isOn: Binding(
                get: { model.value.publicIPEnabled },
                set: { model.setPublicIPEnabled($0) }
            ))
            Text("Public IP uses a fixed HTTPS endpoint and is cached for at least five minutes. It is never exported.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("AI provider display") {
            ForEach(model.orderedProviders, id: \.self) { provider in
                HStack {
                    Label(provider.displayName, systemImage: provider.systemImage)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.value.ai[provider]?.isVisible ?? true },
                        set: { model.setAIProvider(provider, visible: $0) }
                    ))
                    .labelsHidden()
                    Picker("", selection: Binding(
                        get: { model.value.ai[provider]?.metric ?? .usage },
                        set: { model.setAIProvider(provider, metric: $0) }
                    )) {
                        ForEach(AIProviderDisplayMetric.allCases, id: \.self) { metric in
                            Text(metric.title).tag(metric)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
            }
            .onMove(perform: model.moveAIProviders)
        }
    }
}

private extension MonitorModuleID {
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

private extension AIProviderDisplayMetric {
    var title: String {
        switch self {
        case .usage: "Usage"
        case .remaining: "Remaining"
        case .cost: "Cost"
        case .connectionStatus: "Connection"
        }
    }
}
