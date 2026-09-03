import AppKit
import NeedlbarCore
import SwiftUI

public struct SystemDashboardPopoverView: View {
    @ObservedObject private var model: SystemDashboardModel
    private let maximumHeight: CGFloat
    private let onShowSettings: () -> Void
    private let onShowAnalytics: () -> Void
    private let onProviderAction: (ProviderID) -> Void

    public init(
        model: SystemDashboardModel,
        maximumHeight: CGFloat = 680,
        onShowSettings: @escaping () -> Void = {},
        onShowAnalytics: @escaping () -> Void = {},
        onProviderAction: @escaping (ProviderID) -> Void = { _ in }
    ) {
        _model = ObservedObject(wrappedValue: model)
        self.maximumHeight = maximumHeight
        self.onShowSettings = onShowSettings
        self.onShowAnalytics = onShowAnalytics
        self.onProviderAction = onProviderAction
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
            onShowSettings: onShowSettings,
            onShowAnalytics: onShowAnalytics,
            onProviderAction: onProviderAction
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.presentation.moduleIDs, id: \.self) { module in
                        dashboardSection(module)
                        if module != model.presentation.moduleIDs.last {
                            Divider().padding(.leading, 18)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Divider()
            footer
        }
        .frame(width: 360, height: min(680, max(180, maximumHeight)))
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Needlbar").font(.headline)
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
        .padding(.vertical, 6)
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
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func dashboardSection(_ module: MonitorModuleID) -> some View {
        switch module {
        case .cpu:
            DashboardSection(title: "CPU", icon: "cpu", freshness: model.presentation.cpu.freshness) {
                HStack(alignment: .center, spacing: 12) {
                    MetricGauge(value: model.presentation.cpu.usagePercent, label: model.presentation.cpu.usage, accessibilityMetric: "CPU usage", tint: .blue)
                    VStack(alignment: .leading, spacing: 5) {
                        metricRow("Usage", model.presentation.cpu.usage)
                        metricRow("Idle", model.presentation.cpu.usagePercent.map { Self.percent(100 - $0) } ?? "—")
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
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 12) {
                            compactMetric("Used", model.presentation.memory.used)
                            compactMetric("Available", model.presentation.memory.available)
                        }
                        HStack(spacing: 12) {
                            compactMetric("Swap", model.presentation.memory.swap)
                            compactMetric("Pressure", model.presentation.memory.pressure)
                        }
                    }
                }
            }
        case .disk:
            DashboardSection(title: "Disk", icon: "internaldrive", freshness: model.presentation.disk.freshness) {
                HStack(alignment: .center, spacing: 16) {
                    MetricGauge(value: model.presentation.disk.usedPercent, label: model.presentation.disk.usedPercent.map(Self.percent) ?? "—", accessibilityMetric: "Disk used", tint: .cyan)
                    VStack(alignment: .leading, spacing: 7) {
                        metricRow(model.presentation.disk.name, model.presentation.disk.used)
                        metricRow("Available", model.presentation.disk.free)
                    }
                }
                trendMetrics(
                    firstTitle: "Read", firstValue: model.presentation.disk.read, firstColor: .blue,
                    secondTitle: "Write", secondValue: model.presentation.disk.write, secondColor: .orange,
                    samples: model.history.disk.map { ($0.readBytesPerSecond, $0.writeBytesPerSecond) },
                    label: "System disk I/O, read \(model.presentation.disk.read), write \(model.presentation.disk.write)"
                )
            }
        case .network:
            DashboardSection(title: "Network", icon: "network", freshness: model.presentation.network.freshness) {
                trendMetrics(
                    firstTitle: "Download", firstValue: model.presentation.network.download, firstColor: .blue,
                    secondTitle: "Upload", secondValue: model.presentation.network.upload, secondColor: .orange,
                    samples: model.history.network.map { ($0.downloadBytesPerSecond, $0.uploadBytesPerSecond) },
                    label: "Recent network transfer, download \(model.presentation.network.download), upload \(model.presentation.network.upload)"
                )
                networkAddresses
            }
        case .battery:
            DashboardSection(title: "Battery", icon: "battery.75", freshness: model.presentation.battery.freshness) {
                HStack(alignment: .center, spacing: 12) {
                    MetricGauge(value: model.presentation.battery.levelPercent, label: model.presentation.battery.level, accessibilityMetric: "Battery level", tint: .green)
                    VStack(alignment: .leading, spacing: 3) {
                        compactInlineMetric("Level", model.presentation.battery.level)
                        compactInlineMetric("Status", model.presentation.battery.status)
                        compactInlineMetric("Health", model.presentation.battery.health)
                    }
                }
            }
        case .ai:
            DashboardSection(title: "AI usage", icon: "sparkles", freshness: nil) {
                if model.presentation.ai.isEmpty {
                    Text("No providers selected for the dashboard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.presentation.ai, id: \.provider) { provider in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: provider.provider.systemImage)
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.provider.displayName)
                                Text("\(provider.caption) · Usage \(provider.usageStatus.label) · Quota \(provider.quotaStatus.label)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(provider.value).monospacedDigit()
                                if let action = provider.action {
                                    Button(actionTitle(action)) { onProviderAction(provider.provider) }
                                        .buttonStyle(.borderless)
                                        .font(.caption)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(provider.provider.displayName), \(provider.caption), \(provider.value), usage \(provider.usageStatus.label), quota \(provider.quotaStatus.label)")

                        if let fable = provider.fable {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("Fable weekly")
                                    Spacer(minLength: 8)
                                    Text("\(fable.remaining) remaining").monospacedDigit()
                                }
                                Text("\(fable.resetCaption) · \(fable.freshness.label)")
                                    .font(.caption2)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 24)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var networkAddresses: some View {
        if let address = model.presentation.network.primaryLocalAddress {
            metricRow("Local IP", address).padding(.top, 9)
        }
        if !model.presentation.network.additionalLocalAddresses.isEmpty {
            DisclosureGroup("Additional addresses") {
                ForEach(model.presentation.network.additionalLocalAddresses, id: \.self) { address in
                    Text(address)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 4)
                }
            }
            .font(.caption)
            .padding(.top, 4)
        }
        if let publicIP = model.presentation.network.publicIPAddress {
            metricRow("Public IP", publicIP).padding(.top, 5)
        }
    }

    private func trendMetrics(
        firstTitle: String, firstValue: String, firstColor: Color,
        secondTitle: String, secondValue: String, secondColor: Color,
        samples: [(Double?, Double?)], label: String
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                trendLegend(firstTitle, firstValue, firstColor)
                trendLegend(secondTitle, secondValue, secondColor)
            }
            RecentTrendChart(samples: samples, firstColor: firstColor, secondColor: secondColor)
                .frame(height: 28)
                .accessibilityLabel(label)
        }
        .padding(.top, 3)
    }

    private func trendLegend(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value).font(.caption2.monospacedDigit())
        }
    }

    private func compactMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }

    private func compactInlineMetric(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 10)
            Text(value).font(.caption.monospacedDigit())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }

    private func actionTitle(_ action: ProviderAuthenticationAction) -> String {
        switch action {
        case let .browserLogin(title), let .openCursorSpending(title): title
        }
    }

    private static func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }
}
