import NeedlbarCore
import SwiftUI

@MainActor
struct SettingsCPUInformationView: View {
    @ObservedObject var presentation: SettingsCPUInformationPresentation

    private var value: SettingsCPUInformationValue { presentation.value }

    var body: some View {
        SettingsStudioSection(title: "CPU information") {
            VStack(alignment: .leading, spacing: 9) {
                hardwareSummary
                activitySummary
                if let perCorePercents = value.perCorePercents {
                    PerCoreActivityBars(values: perCorePercents)
                        .accessibilityLabel("Per-core CPU activity")
                }
                Text(freshnessText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.vertical, 11)
        }
    }

    private var hardwareSummary: some View {
        ViewThatFits(in: .horizontal) {
            hardwareRow(horizontal: true)
            hardwareRow(horizontal: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func hardwareRow(horizontal: Bool) -> some View {
        let group = value.hardware?.coreGroups.map {
            "\($0.name) · \($0.physicalCoreCount) cores"
        }.joined(separator: "  ·  ")

        if horizontal {
            HStack(spacing: 8) {
                hardwareName
                hardwareCounts
                if let group { Text(group).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Spacer(minLength: 0)
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    hardwareName
                    hardwareCounts
                }
                if let group { Text(group).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
    }

    private var hardwareName: some View {
        Text(value.hardware?.name ?? "CPU")
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .lineLimit(1)
            .truncationMode(.middle)
            .layoutPriority(1)
            .accessibilityLabel("CPU model, \(value.hardware?.name ?? "CPU")")
    }

    private var hardwareCounts: some View {
        HStack(spacing: 6) {
            if let physical = value.hardware?.physicalCoreCount {
                Text("\(physical) physical")
            }
            if let logical = value.hardware?.logicalCoreCount {
                Text("\(logical) logical")
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var activitySummary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            metric(title: "Usage", percent: value.totalUsagePercent, prominent: true)
            metric(title: "Idle", percent: value.idlePercent, prominent: false)
            Spacer(minLength: 0)
        }
    }

    private func metric(title: String, percent: Double?, prominent: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(percent.map { "\(Int($0.rounded()))%" } ?? "—")
                .font(.system(size: prominent ? 19 : 14, weight: prominent ? .semibold : .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(prominent ? Color.blue : Color.secondary)
                .accessibilityLabel("\(title) \(percent.map { "\(Int($0.rounded())) percent" } ?? "unavailable")")
        }
    }

    private var freshnessText: String {
        switch value.status {
        case let .fresh(capturedAt): "Sampled \(capturedAt.formatted(date: .omitted, time: .shortened))"
        case let .stale(lastSuccessfulAt):
            "Last known · \(lastSuccessfulAt.formatted(date: .omitted, time: .shortened))"
        case .warmingUp: value.reason ?? "Waiting for the first CPU sample"
        case .unavailable: value.reason ?? "CPU information is unavailable"
        }
    }
}
