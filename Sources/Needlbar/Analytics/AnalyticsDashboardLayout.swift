import SwiftUI

enum AnalyticsDashboardLayout {
    static let horizontalInset: CGFloat = 24
    static let maximumContentWidth: CGFloat = 960
    static let sectionSpacing: CGFloat = 16
    static let gridSpacing: CGFloat = 12
    static let minimumCardWidth: CGFloat = 180
    static let summaryWideBreakpoint: CGFloat = 600
    static let evidenceTwoColumnBreakpoint: CGFloat = 800

    static func contentColumnWidth(forWindowContentWidth width: CGFloat) -> CGFloat {
        min(max(0, width - horizontalInset * 2), maximumContentWidth)
    }

    static func summaryColumnCount(forContentWidth width: CGFloat) -> Int {
        if width >= summaryWideBreakpoint { return 3 }
        return width >= minimumCardWidth * 2 + gridSpacing ? 2 : 1
    }

    static func evidencePanelColumnCount(forContentWidth width: CGFloat) -> Int {
        width >= evidenceTwoColumnBreakpoint ? 2 : 1
    }

    static func summaryValuePointSize(for value: String) -> CGFloat {
        value.count > 12 ? 24 : 28
    }

    static func equalTracks(count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: minimumCardWidth), spacing: gridSpacing), count: count)
    }
}

enum AnalyticsDashboardCardKind: CaseIterable {
    case repositoryEstimate
    case repositoryLinkage
    case observedActivity

    var accent: Color {
        switch self {
        case .repositoryEstimate: .blue
        case .repositoryLinkage: .teal
        case .observedActivity: .purple
        }
    }

    var symbolName: String {
        switch self {
        case .repositoryEstimate: "dollarsign.circle"
        case .repositoryLinkage: "link.circle"
        case .observedActivity: "sparkles"
        }
    }
}

struct AnalyticsDashboardCard: View {
    let kind: AnalyticsDashboardCardKind
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle()
                .fill(kind.accent)
                .frame(height: 3)
                .accessibilityHidden(true)
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    Text(value)
                        .font(.system(size: AnalyticsDashboardLayout.summaryValuePointSize(for: value), weight: .semibold))
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: kind.symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(kind.accent.opacity(0.14), in: Circle())
                    .foregroundStyle(kind.accent)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(kind.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(kind.accent.opacity(0.30), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct AnalyticsDashboardPanel<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.30), lineWidth: 1)
        }
    }
}
