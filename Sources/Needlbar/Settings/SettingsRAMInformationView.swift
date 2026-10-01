import SwiftUI

@MainActor
struct SettingsRAMInformationView: View {
    @ObservedObject var presentation: SettingsRAMInformationPresentation
    private var value: SettingsRAMInformationValue { presentation.value }

    var body: some View {
        SettingsStudioSection(title: "RAM information") {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    metric("Total", bytes: value.totalBytes)
                    Spacer(minLength: 0)
                    Text(value.usedPercent.map { "\(Int($0.rounded()))% used" } ?? "— used")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit().foregroundStyle(.purple)
                        .accessibilityLabel("Memory used")
                        .accessibilityValue(value.usedPercent.map { "\(Int($0.rounded())) percent" } ?? "Unavailable")
                }
                HStack {
                    metric("Used", bytes: value.usedBytes)
                    Spacer(minLength: 8)
                    metric("Available", bytes: value.availableBytes)
                }
                if let percent = value.usedPercent {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.15))
                            Capsule().fill(Color.purple)
                                .frame(width: geometry.size.width * percent / 100)
                        }
                    }.frame(height: 6)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Used versus available memory")
                        .accessibilityValue("\(Int(percent.rounded())) percent used, \(Int((100 - percent).rounded())) percent available")
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { details }
                    VStack(alignment: .leading, spacing: 6) { details }
                }
                Text("Pressure: \(value.pressure?.capitalized ?? "Unknown")")
                    .font(.subheadline.weight(.medium)).foregroundStyle(pressureColor)
                    .accessibilityLabel("Memory pressure")
                    .accessibilityValue("\(value.status.isStale ? "Last known, " : "")\(value.pressure?.capitalized ?? "Unknown")")
                Text(freshnessText).font(.caption).foregroundStyle(.secondary)
                Text("Compressed and Wired are included in Used. Swap uses disk space.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(.vertical, 11)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(value.status.isStale ? "RAM information, Last known" : "RAM information")
        }
    }

    @ViewBuilder private var details: some View {
        metric("Compressed", bytes: value.compressedBytes)
        metric("Wired", bytes: value.wiredBytes)
        metric("Swap", bytes: value.swapUsedBytes)
    }

    private func metric(_ title: String, bytes: UInt64?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(bytesText(bytes)).font(.subheadline.weight(.medium)).monospacedDigit()
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(bytes.map { bytesText($0) } ?? "Unavailable")
    }

    var freshnessText: String {
        guard let date = value.successfulAt else { return value.stateLabel }
        return "\(value.stateLabel) · \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private var pressureColor: Color {
        switch value.pressure {
        case "normal": .green
        case "warning": .orange
        case "critical": .red
        default: .secondary
        }
    }

    private func bytesText(_ bytes: UInt64?) -> String {
        guard let bytes else { return "—" }
        let units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB"]
        var amount = Double(bytes)
        var index = 0
        while amount >= 1024 && index < units.count - 1 { amount /= 1024; index += 1 }
        return "\(amount.formatted(.number.precision(.fractionLength(index == 0 ? 0 : 1)))) \(units[index])"
    }
}

private extension SettingsRAMInformationStatus {
    var isStale: Bool {
        if case .stale = self { return true }
        return false
    }
}
