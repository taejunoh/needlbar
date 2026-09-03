import SwiftUI

enum DashboardReadabilityPolicy {
    static func systemStatus(_ freshness: DashboardFreshness) -> String? {
        switch freshness {
        case .fresh, .unavailable: nil
        case .stale: "Stale"
        }
    }

    static func providerStatus(usage: PresentationFreshness, quota: PresentationFreshness) -> String? {
        var result: [String] = []
        for status in [usage, quota] {
            let label: String?
            switch status {
            case .fresh, .unavailable: label = nil
            case .stale: label = "Stale"
            case .requiresAuthentication: label = "Authentication required"
            case .error: label = "Error"
            }
            if let label, !result.contains(label) { result.append(label) }
        }
        return result.isEmpty ? nil : result.joined(separator: " · ")
    }
}

struct DashboardMetricValue {
    let fullValue: String
    let truncation: Text.TruncationMode

    init(_ fullValue: String, truncation: Text.TruncationMode = .tail) {
        self.fullValue = fullValue
        self.truncation = truncation
    }

    var helpValue: String { fullValue }
    var accessibilityValue: String { fullValue }
}

struct DashboardSurface<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background {
                ZStack {
                    Rectangle().fill(.regularMaterial)
                    Rectangle().fill(Color(nsColor: .windowBackgroundColor).opacity(0.94))
                }
            }
    }
}

struct DashboardSection<Content: View>: View {
    let title: String
    let icon: String
    let freshness: DashboardFreshness?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: icon)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(title).font(.headline.weight(.semibold))
                Spacer(minLength: 8)
                if let freshness, let status = DashboardReadabilityPolicy.systemStatus(freshness) {
                    Text(status)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                        .accessibilityLabel("\(title) data \(status)")
                }
            }
            content()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }
}

struct DashboardMetricRow: View {
    let label: String
    let value: DashboardMetricValue

    var body: some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .gridColumnAlignment(.leading)
                .layoutPriority(1)
            Text(value.fullValue)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(value.truncation)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .gridColumnAlignment(.trailing)
                .help(value.helpValue)
                .accessibilityValue(value.accessibilityValue)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value.accessibilityValue)")
    }
}

struct DashboardMetricGrid<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
            content()
        }
        .frame(maxWidth: .infinity)
    }
}

struct DashboardMetricText: View {
    let value: DashboardMetricValue

    var body: some View {
        Text(value.fullValue)
            .fontWeight(.semibold)
            .monospacedDigit()
            .lineLimit(1)
            .truncationMode(value.truncation)
            .help(value.helpValue)
            .accessibilityValue(value.accessibilityValue)
    }
}

struct MetricGauge: View {
    let value: Double?
    let label: String
    let accessibilityMetric: String
    let tint: Color

    var body: some View {
        ZStack {
            if let value {
                Circle().stroke(tint.opacity(0.18), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, min(1, value / 100))))
                    .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle().strokeBorder(.tertiary, lineWidth: 7)
            }
            Text(label).font(.caption.weight(.semibold).monospacedDigit())
        }
        .frame(width: 52, height: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.map { _ in "\(accessibilityMetric), \(label)" } ?? "\(accessibilityMetric) unavailable")
    }
}

struct PerCoreActivityBars: View {
    let values: [Double]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                GeometryReader { proxy in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.primary.opacity(0.10))
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.blue)
                            .frame(height: proxy.size.height * max(0, min(1, value / 100)))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("CPU core \(index + 1), \(Int(value.rounded()))%")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
        .accessibilityElement(children: .contain)
    }
}

struct DashboardTrendMetrics: View {
    let firstTitle: String
    let firstValue: DashboardMetricValue
    let firstColor: Color
    let secondTitle: String
    let secondValue: DashboardMetricValue
    let secondColor: Color
    let samples: [(Double?, Double?)]
    let accessibilityLabel: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                legend(firstTitle, firstValue, firstColor)
                legend(secondTitle, secondValue, secondColor)
            }
            RecentTrendChart(samples: samples, firstColor: firstColor, secondColor: secondColor)
                .frame(height: 34)
                .accessibilityLabel(accessibilityLabel)
        }
        .padding(.top, 3)
    }

    private func legend(_ title: String, _ value: DashboardMetricValue, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            DashboardMetricText(value: value).font(.caption2)
        }
    }
}
