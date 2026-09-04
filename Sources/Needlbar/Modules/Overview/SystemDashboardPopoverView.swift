import AppKit
import NeedlbarCore
import SwiftUI

public struct SystemDashboardPopoverView: View {
    @ObservedObject private var model: SystemDashboardModel
    @ObservedObject private var layout: SystemDashboardPopoverLayout
    private let isMeasuring: Bool
    private let onShowSettings: () -> Void
    private let onShowAnalytics: () -> Void
    private let onProviderAction: (ProviderID) -> Void

    public init(
        model: SystemDashboardModel,
        height: CGFloat = SystemDashboardPanelSizing.fallbackHeight,
        onShowSettings: @escaping () -> Void = {},
        onShowAnalytics: @escaping () -> Void = {},
        onProviderAction: @escaping (ProviderID) -> Void = { _ in }
    ) {
        _model = ObservedObject(wrappedValue: model)
        _layout = ObservedObject(wrappedValue: SystemDashboardPopoverLayout(height: height))
        isMeasuring = false
        self.onShowSettings = onShowSettings
        self.onShowAnalytics = onShowAnalytics
        self.onProviderAction = onProviderAction
    }

    init(
        model: SystemDashboardModel,
        layout: SystemDashboardPopoverLayout,
        onShowSettings: @escaping () -> Void = {},
        onShowAnalytics: @escaping () -> Void = {},
        onProviderAction: @escaping (ProviderID) -> Void = { _ in }
    ) {
        _model = ObservedObject(wrappedValue: model)
        _layout = ObservedObject(wrappedValue: layout)
        isMeasuring = false
        self.onShowSettings = onShowSettings
        self.onShowAnalytics = onShowAnalytics
        self.onProviderAction = onProviderAction
    }

    init(measuring model: SystemDashboardModel) {
        _model = ObservedObject(wrappedValue: model)
        _layout = ObservedObject(wrappedValue: SystemDashboardPopoverLayout(height: SystemDashboardPanelSizing.fallbackHeight))
        isMeasuring = true
        onShowSettings = {}
        onShowAnalytics = {}
        onProviderAction = { _ in }
    }

    // Retain the previously public construction path for existing presenters.
    public init(
        snapshot: CombinedUsageSnapshot,
        configuration: ModuleConfiguration,
        onShowSettings: @escaping () -> Void = {},
        onShowAnalytics: @escaping () -> Void = {},
        onProviderAction: @escaping (ProviderID) -> Void = { _ in }
    ) {
        self.init(
            model: SystemDashboardModel(snapshot: snapshot, configuration: configuration.systemMonitor),
            height: SystemDashboardPanelSizing.fallbackHeight,
            onShowSettings: onShowSettings,
            onShowAnalytics: onShowAnalytics,
            onProviderAction: onProviderAction
        )
    }

    @ViewBuilder
    public var body: some View {
        if isMeasuring {
            dashboardChrome { dashboardSections }
                .frame(width: SystemDashboardPanelSizing.width)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            dashboardChrome {
                ScrollView { dashboardSections }
            }
            .frame(width: SystemDashboardPanelSizing.width, height: layout.height)
        }
    }

    private func dashboardChrome<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        DashboardSurface {
            VStack(spacing: 0) {
                header
                Divider()
                content()
                Divider()
                footer
            }
        }
    }

    private var dashboardSections: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.presentation.moduleIDs, id: \.self) { module in
                dashboardSection(module)
                if module != model.presentation.moduleIDs.last {
                    Divider().padding(.leading, 18)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func dashboardSection(_ module: MonitorModuleID) -> some View {
        switch module {
        case .cpu:
            DashboardSection(title: "CPU", icon: "cpu", freshness: model.presentation.cpu.freshness) {
                HStack(alignment: .center, spacing: 16) {
                    MetricGauge(value: model.presentation.cpu.usagePercent, label: model.presentation.cpu.usage, accessibilityMetric: "CPU usage", tint: .blue)
                    DashboardMetricGrid {
                        DashboardMetricRow(label: "Usage", value: .init(model.presentation.cpu.usage))
                        DashboardMetricRow(label: "Idle", value: .init(model.presentation.cpu.usagePercent.map { Self.percent(100 - $0) } ?? "—"))
                    }
                }
                if !model.presentation.cpu.perCorePercents.isEmpty {
                    PerCoreActivityBars(values: model.presentation.cpu.perCorePercents)
                }
            }
        case .memory:
            DashboardSection(title: "RAM", icon: "memorychip", freshness: model.presentation.memory.freshness) {
                HStack(alignment: .center, spacing: 16) {
                    MetricGauge(value: model.presentation.memory.usedPercent, label: model.presentation.memory.usedPercent.map(Self.percent) ?? "—", accessibilityMetric: "RAM used", tint: .purple)
                    DashboardMetricGrid {
                        DashboardMetricRow(label: "Used", value: .init(model.presentation.memory.used))
                        DashboardMetricRow(label: "Available", value: .init(model.presentation.memory.available))
                        DashboardMetricRow(label: "Swap", value: .init(model.presentation.memory.swap))
                        DashboardMetricRow(label: "Pressure", value: .init(model.presentation.memory.pressure))
                    }
                }
            }
        case .disk:
            DashboardSection(title: "Disk", icon: "internaldrive", freshness: model.presentation.disk.freshness) {
                HStack(alignment: .center, spacing: 16) {
                    MetricGauge(value: model.presentation.disk.usedPercent, label: model.presentation.disk.usedPercent.map(Self.percent) ?? "—", accessibilityMetric: "Disk used", tint: .cyan)
                    DashboardMetricGrid {
                        DashboardMetricRow(label: "Name", value: .init(model.presentation.disk.name, truncation: .tail))
                        DashboardMetricRow(label: "Used", value: .init(model.presentation.disk.used))
                        DashboardMetricRow(label: "Available", value: .init(model.presentation.disk.free))
                    }
                }
                DashboardTrendMetrics(
                    firstTitle: "Read", firstValue: .init(model.presentation.disk.read), firstColor: .blue,
                    secondTitle: "Write", secondValue: .init(model.presentation.disk.write), secondColor: .orange,
                    samples: model.history.disk.map { ($0.readBytesPerSecond, $0.writeBytesPerSecond) },
                    accessibilityLabel: "System disk I/O, read \(model.presentation.disk.read), write \(model.presentation.disk.write)"
                )
            }
        case .network:
            DashboardSection(title: "Network", icon: "network", freshness: model.presentation.network.freshness) {
                DashboardMetricGrid {
                    DashboardMetricRow(label: "Download", value: .init(model.presentation.network.download))
                    DashboardMetricRow(label: "Upload", value: .init(model.presentation.network.upload))
                }
                DashboardTrendMetrics(
                    firstTitle: "Download", firstValue: .init(model.presentation.network.download), firstColor: .blue,
                    secondTitle: "Upload", secondValue: .init(model.presentation.network.upload), secondColor: .orange,
                    samples: model.history.network.map { ($0.downloadBytesPerSecond, $0.uploadBytesPerSecond) },
                    accessibilityLabel: "Recent network transfer, download \(model.presentation.network.download), upload \(model.presentation.network.upload)"
                )
                networkAddresses
            }
        case .battery:
            DashboardSection(title: "Battery", icon: "battery.75", freshness: model.presentation.battery.freshness) {
                HStack(alignment: .center, spacing: 16) {
                    MetricGauge(value: model.presentation.battery.levelPercent, label: model.presentation.battery.level, accessibilityMetric: "Battery level", tint: .green)
                    DashboardMetricGrid {
                        DashboardMetricRow(label: "Level", value: .init(model.presentation.battery.level))
                        DashboardMetricRow(label: "Status", value: .init(model.presentation.battery.status))
                        DashboardMetricRow(label: "Health", value: .init(model.presentation.battery.health))
                    }
                }
            }
        case .ai:
            aiSection
        }
    }

    @ViewBuilder
    private var networkAddresses: some View {
        if let address = model.presentation.network.primaryLocalAddress {
            DashboardMetricRow(label: "Local IP", value: .init(address, truncation: .middle))
                .padding(.top, 5)
        }
        if !model.presentation.network.additionalLocalAddresses.isEmpty {
            DisclosureGroup("Additional addresses") {
                ForEach(model.presentation.network.additionalLocalAddresses, id: \.self) { address in
                    DashboardMetricText(value: .init(address, truncation: .middle))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(address)
                        .accessibilityLabel("Additional local IP, \(address)")
                }
            }
            .font(.caption)
            .padding(.top, 4)
        }
        if let publicIP = model.presentation.network.publicIPAddress {
            DashboardMetricRow(label: "Public IP", value: .init(publicIP, truncation: .middle))
                .padding(.top, 3)
        }
    }

    @ViewBuilder
    private var aiSection: some View {
        DashboardSection(title: "AI usage", icon: "sparkles", freshness: nil) {
            if model.presentation.ai.isEmpty {
                Text("No providers selected for the dashboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.presentation.ai, id: \.provider) { provider in
                providerRow(provider)
            }
        }
    }

    @ViewBuilder
    private func providerRow(_ provider: SystemDashboardPresentation.AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: provider.provider.systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(provider.provider.displayName)
                    .fontWeight(.medium)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                DashboardMetricText(value: .init(provider.value))
                if let action = provider.action {
                    let visibleTitle = Self.visibleActionTitle(for: action)
                    let identityTitle = Self.accessibilityActionTitle(for: action)
                    Button(visibleTitle) { onProviderAction(provider.provider) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .help(identityTitle)
                        .accessibilityLabel(identityTitle)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(provider.caption)
                    .foregroundStyle(.secondary)
                if let status = DashboardReadabilityPolicy.providerStatus(usage: provider.usageStatus, quota: provider.quotaStatus) {
                    Text("· \(status)")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption2)
            if let fable = provider.fable {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Fable weekly")
                    Spacer(minLength: 8)
                    DashboardMetricText(value: .init("\(fable.remaining) remaining"))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let status = fableStatus(fable.freshness) {
                    Text("\(fable.resetCaption) · \(status)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else {
                    Text(fable.resetCaption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func fableStatus(_ freshness: PresentationFreshness) -> String? {
        switch freshness {
        case .fresh, .unavailable: return nil
        case .stale: return "Stale"
        case .requiresAuthentication: return "Authentication required"
        case .error: return "Error"
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Needlbar").font(.headline.weight(.semibold))
                Text("System dashboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Live")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Dashboard updates as metrics are collected")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Button("Settings", action: onShowSettings)
            Spacer()
            Button("Analytics…", action: onShowAnalytics)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .font(.caption)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    nonisolated internal static func visibleActionTitle(for action: ProviderAuthenticationAction) -> String {
        switch action {
        case .browserLogin:
            return "Sign in"
        case let .openCursorSpending(title):
            return title
        }
    }

    nonisolated internal static func accessibilityActionTitle(for action: ProviderAuthenticationAction) -> String {
        switch action {
        case let .browserLogin(title), let .openCursorSpending(title): title
        }
    }

    private static func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }
}
