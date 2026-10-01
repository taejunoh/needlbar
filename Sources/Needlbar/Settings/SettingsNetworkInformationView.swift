import Foundation
import NeedlbarCore
import SwiftUI

struct SettingsNetworkIPVisibility: Equatable {
    let showsLocalIP: Bool
    let showsPublicIP: Bool

    init(tab: SettingsStudioTab, localEnabled: Bool, publicEnabled: Bool) {
        showsLocalIP = tab == .dashboard && localEnabled
        showsPublicIP = tab == .dashboard && publicEnabled
    }
}

@MainActor
struct SettingsNetworkInformationView: View {
    @ObservedObject var presentation: SettingsNetworkInformationPresentation
    let ipVisibility: SettingsNetworkIPVisibility

    private var value: SettingsNetworkInformationValue { presentation.value }

    var body: some View {
        SettingsStudioSection(title: "Network information") {
            VStack(alignment: .leading, spacing: 13) {
                rates
                Text("Combined traffic across reported network interfaces. May include loopback and VPN traffic.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(value.metadataIsStale ? "Last known reported interface names" : "Reported interface names")
                    .font(.subheadline.weight(.medium))
                interfaceNames
                if ipVisibility.showsLocalIP {
                    addressRow(title: "Local IP", values: value.localIPAddresses)
                }
                if ipVisibility.showsPublicIP {
                    addressRow(title: "Public IP", values: value.publicIPAddress.map { [$0] } ?? [])
                    Text("Public IP may be cached; the traffic sample time is not its lookup time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(Self.trafficTimeText(status: value.status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Self.trafficAccessibilityText(status: value.status))
            }
            .padding(.vertical, 13)
        }
    }

    private var rates: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 28) {
                rate(title: "Download", value: value.downloadBytesPerSecond, color: .blue)
                rate(title: "Upload", value: value.uploadBytesPerSecond, color: .orange)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                rate(title: "Download", value: value.downloadBytesPerSecond, color: .blue)
                rate(title: "Upload", value: value.uploadBytesPerSecond, color: .orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rate(title: String, value: UInt64?, color: Color) -> some View {
        let lastKnown: Bool
        if case .stale = self.value.status { lastKnown = true } else { lastKnown = false }
        return VStack(alignment: .leading, spacing: 2) {
            Text(lastKnown ? "Last known \(title)" : title).font(.caption).foregroundStyle(.secondary)
            Text(Self.rateText(value))
                .font(.system(size: 19, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityLabel(Self.rateAccessibilityText(title: title, value: value, status: self.value.status))
        }
    }

    @ViewBuilder private var interfaceNames: some View {
        if let names = value.interfaceNames {
            if names.isEmpty {
                Text(value.metadataIsStale ? "Last known · no interface names reported" : "No interface names reported")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(value.metadataIsStale ? "Last known reported interface names" : "Reported interface names"): no interface names reported")
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(names.joined(separator: " · "))
                        .font(.system(.body, design: .monospaced))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("\(value.metadataIsStale ? "Last known reported interface names" : "Reported interface names"): \(names.joined(separator: ", "))")
                    if value.interfaceNamesOmitted {
                        Text("Some reported names are not shown")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            Text(value.interfaceNamesOmitted ? "— · Some reported names are not shown" : "—")
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(value.metadataIsStale ? "Last known " : "")reported interface names unknown\(value.interfaceNamesOmitted ? ". Some reported names are not shown" : "")")
        }
    }

    private func addressRow(title: String, values: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(value.metadataIsStale ? "Last known \(title)" : title).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(values.isEmpty ? "—" : values.joined(separator: " · "))
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(values.joined(separator: ", "))
                .accessibilityLabel("\(value.metadataIsStale ? "Last known " : "")\(title) \(values.isEmpty ? "unavailable" : values.joined(separator: ", "))")
        }
    }

    static func rateText(_ value: UInt64?) -> String {
        guard let value else { return "—" }
        let units = ["B/s", "KiB/s", "MiB/s", "GiB/s", "TiB/s", "PiB/s", "EiB/s"]
        var amount = Double(value)
        var unitIndex = 0
        while amount >= 1_024, unitIndex < units.count - 1 {
            amount /= 1_024
            unitIndex += 1
        }
        if unitIndex == 0 || amount.rounded(.towardZero) == amount {
            return "\(UInt64(amount)) \(units[unitIndex])"
        }
        return String(format: "%.1f %@", amount, units[unitIndex])
    }

    static func trafficTimeText(status: SettingsNetworkInformationStatus) -> String {
        switch status {
        case let .fresh(capturedAt): "Traffic sampled · \(capturedAt.formatted(date: .complete, time: .shortened))"
        case let .stale(lastSuccessfulAt): "Last known traffic · \(lastSuccessfulAt.formatted(date: .complete, time: .shortened))"
        case .unavailable: "Traffic unavailable"
        }
    }

    static func rateAccessibilityText(
        title: String, value: UInt64?, status: SettingsNetworkInformationStatus
    ) -> String {
        let freshness: String
        if case .stale = status { freshness = "Last known " } else { freshness = "" }
        guard let value else { return "\(freshness)\(title) unavailable" }
        return "\(freshness)\(title) \(value) bytes per second, \(rateText(value))"
    }

    private static func trafficAccessibilityText(status: SettingsNetworkInformationStatus) -> String {
        switch status {
        case let .fresh(capturedAt): "Traffic sampled on \(capturedAt.formatted(date: .complete, time: .shortened))"
        case let .stale(lastSuccessfulAt): "Last known traffic from \(lastSuccessfulAt.formatted(date: .complete, time: .shortened))"
        case .unavailable: "Traffic unavailable"
        }
    }

}
