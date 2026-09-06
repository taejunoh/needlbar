import NeedlbarCore
import SwiftUI

public struct SystemMonitorSettingsView: View {
    @ObservedObject private var model: SystemMonitorSettingsModel

    public init(model: SystemMonitorSettingsModel) {
        _model = ObservedObject(wrappedValue: model)
    }

    public var body: some View {
        Section("Menu bar modules") {
            Text("Choose which modules use space in the menu bar and appear in the dashboard popover.")
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

            Button("Use compact defaults") { model.useCompactDefaults() }
                .help("Show CPU, RAM, and AI in the menu bar without changing provider preferences.")

            Toggle("Show local IP addresses", isOn: Binding(
                get: { model.value.localIPEnabled },
                set: { model.setLocalIPEnabled($0) }
            ))
            Text("Shows active local IPv4 addresses in the dashboard only. Addresses are never exported.")
                .font(.caption)
                .foregroundStyle(.secondary)

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
                    HStack(spacing: 6) {
                        ProviderBrandIcon(provider: provider, accessibility: .decorative)
                        Text(provider.displayName)
                    }
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
