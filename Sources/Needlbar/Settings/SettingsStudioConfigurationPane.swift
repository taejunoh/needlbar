import NeedlbarCore
import SwiftUI

struct SettingsStudioConfigurationPane: View {
    @ObservedObject var model: SystemMonitorSettingsModel
    let page: SettingsStudioPage
    let surface: MonitorDisplaySurface

    private func moduleToggle(_ id: MonitorModuleID) -> some View {
        SettingsStudioToggle(title: id.title, value: Binding(
            get: { model.isVisible(id, surface: surface) },
            set: { model.setVisible(id, $0, surface: surface) }))
    }
    private func providerToggle(_ id: ProviderID) -> some View {
        SettingsStudioToggle(title: id.displayName, value: Binding(
            get: { model.isVisible(id, surface: surface) },
            set: { model.setAIProvider(id, visible: $0, surface: surface) }))
    }
    private func moveButtons(_ index: Int, count: Int, name: String,
                             move: @escaping (IndexSet, Int) -> Void) -> some View {
        HStack {
            Button { move(IndexSet(integer: index), index - 1) } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0).accessibilityLabel("Move \(name) up")
            Button { move(IndexSet(integer: index), index + 2) } label: { Image(systemName: "chevron.down") }
                .disabled(index == count - 1).accessibilityLabel("Move \(name) down")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch page {
            case .layout:
                Text("Visibility is independent. Order is shared by both surfaces.")
                    .foregroundStyle(.secondary)
                List {
                    ForEach(Array(model.orderedModules.enumerated()), id: \.element) { index, id in
                        HStack {
                            Image(systemName: "line.3.horizontal").accessibilityHidden(true)
                            moduleToggle(id)
                            moveButtons(index, count: model.orderedModules.count, name: id.title, move: model.moveModules)
                        }
                    }.onMove(perform: model.moveModules)
                }.frame(height: 370)
                Button("Use compact defaults for this surface") { model.useCompactDefaults(surface: surface) }
                Text("AI provider order").font(.headline)
                List {
                    ForEach(Array(model.orderedProviders.enumerated()), id: \.element) { index, id in
                        HStack {
                            ProviderBrandIcon(provider: id, accessibility: .decorative)
                            providerToggle(id)
                            moveButtons(index, count: model.orderedProviders.count, name: id.displayName, move: model.moveAIProviders)
                        }
                    }.onMove(perform: model.moveAIProviders)
                }.frame(height: 195)
            case let .module(id):
                SettingsStudioSection(title: surface == .menuBar ? "Show in menu bar" : "Show in dashboard") {
                    moduleToggle(id)
                }
                if id == .network && surface == .dashboard {
                    SettingsStudioSection(title: "Network details") {
                        SettingsStudioToggle(title: "Show local IP addresses", value: Binding(
                            get: { model.value.localIPEnabled }, set: { model.setLocalIPEnabled($0) }))
                        Divider()
                        SettingsStudioToggle(title: "Show public IP address", value: Binding(
                            get: { model.value.publicIPEnabled }, set: { model.setPublicIPEnabled($0) }))
                    }
                    Text("Addresses appear in the dashboard only and are never exported. Public IP uses a fixed HTTPS endpoint and is cached for at least five minutes.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            case let .provider(id):
                SettingsStudioSection(title: surface == .menuBar ? "Show in menu bar" : "Show in dashboard") {
                    providerToggle(id)
                    Divider()
                    HStack {
                        Text("Display value (shared)")
                        Spacer(minLength: 12)
                        Picker("Display value (shared)", selection: Binding(
                            get: { model.value.ai[id]?.metric ?? .remaining },
                            set: { model.setAIProvider(id, metric: $0) })) {
                            ForEach(AIProviderDisplayMetric.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.labelsHidden()
                    }.font(.system(size: 17)).frame(minHeight: 54)
                }
            case .notifications, .data: EmptyView()
            }
        }
    }
}
