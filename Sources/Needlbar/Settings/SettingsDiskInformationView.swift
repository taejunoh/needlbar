import SwiftUI

@MainActor
struct SettingsDiskInformationView: View {
    @ObservedObject var presentation: SettingsDiskInformationPresentation
    private var value: SettingsDiskInformationValue { presentation.value }

    var body: some View {
        SettingsStudioSection(title: "Disk information") {
            VStack(alignment: .leading, spacing: 9) {
                Text("System volume (/)").font(.caption).foregroundStyle(.secondary)
                Text(value.name ?? "—").font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("System volume name").accessibilityValue(value.name ?? "Unavailable")
                HStack {
                    metric("Total", bytes: value.totalBytes)
                    Spacer(minLength: 0)
                    Text(value.usedPercent.map { "\(Int($0.rounded()))% used" } ?? "— used")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit().foregroundStyle(.cyan)
                        .accessibilityLabel("Disk used")
                        .accessibilityValue(value.usedPercent.map { "\(lastKnownPrefix)\(Int($0.rounded())) percent" } ?? "Unavailable")
                }
                HStack {
                    metric("Used", bytes: value.usedBytes, dynamic: true)
                    Spacer(minLength: 8)
                    metric("Available", bytes: value.availableBytes, dynamic: true)
                }
                if let percent = value.usedPercent {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.15))
                            Capsule().fill(Color.cyan).frame(width: geometry.size.width * percent / 100)
                        }
                    }.frame(height: 6)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Used versus available disk space")
                        .accessibilityValue("\(lastKnownPrefix)\(Int(percent.rounded())) percent used, \(Int((100 - percent).rounded())) percent available")
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { rates }
                    VStack(alignment: .leading, spacing: 6) { rates }
                }
                Text(freshnessText).font(.caption).foregroundStyle(.secondary)
                Text("Capacity is for the system volume. I/O is for its backing device and may include other volumes.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(.vertical, 11)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(value.status.isStale ? "Disk information, Last known" : "Disk information")
        }
    }

    @ViewBuilder private var rates: some View {
        rate("Read", bytes: value.readBytesPerSecond, color: .blue)
        rate("Write", bytes: value.writeBytesPerSecond, color: .orange)
    }

    private var lastKnownPrefix: String { value.status.isStale ? "Last known, " : "" }

    private func metric(_ title: String, bytes: UInt64?, dynamic: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Self.bytesText(bytes)).font(.system(.subheadline, design: .monospaced).weight(.medium))
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore).accessibilityLabel(title)
        .accessibilityValue(bytes.map { "\(dynamic ? lastKnownPrefix : "")\(Self.bytesText($0))" } ?? "Unavailable")
    }

    private func rate(_ title: String, bytes: UInt64?, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(color)
            Text(Self.rateText(bytes)).font(.system(.subheadline, design: .monospaced).weight(.medium))
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore).accessibilityLabel("Disk \(title.lowercased()) rate")
        .accessibilityValue(bytes.map { "\(lastKnownPrefix)\(Self.rateText($0))" } ?? "Unavailable")
    }

    var freshnessText: String {
        guard let date = value.successfulAt else { return value.stateLabel }
        return "\(value.stateLabel) · \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    static func rateText(_ bytes: UInt64?) -> String {
        guard bytes != nil else { return "—" }
        return "\(bytesText(bytes))/s"
    }

    private static func bytesText(_ bytes: UInt64?) -> String {
        guard let bytes else { return "—" }
        let units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB"]
        var amount = Double(bytes)
        var index = 0
        while amount >= 1024 && index < units.count - 1 { amount /= 1024; index += 1 }
        return "\(amount.formatted(.number.precision(.fractionLength(index == 0 ? 0 : 1)))) \(units[index])"
    }
}
