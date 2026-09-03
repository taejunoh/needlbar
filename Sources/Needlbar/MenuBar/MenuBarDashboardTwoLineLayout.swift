import AppKit
import CoreText
import NeedlbarCore

enum MenuBarTextRole: Equatable {
    case label
    case value
}

@MainActor
enum MenuBarGlyphs {
    static func font(for role: MenuBarTextRole) -> NSFont {
        switch role {
        case .label:
            return .systemFont(ofSize: 7.5, weight: .regular)
        case .value:
            return .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        }
    }

    static func line(_ text: String, role: MenuBarTextRole) -> CTLine {
        let string = NSAttributedString(
            string: text,
            attributes: [
                .font: font(for: role),
                .foregroundColor: NSColor.black,
            ]
        )
        return CTLineCreateWithAttributedString(string as CFAttributedString)
    }

    static func advance(_ text: String, role: MenuBarTextRole) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line(text, role: role), nil, nil, nil))
    }

    static func bounds(_ text: String, role: MenuBarTextRole) -> CGRect {
        guard !text.isEmpty else { return .zero }
        let bounds = CTLineGetBoundsWithOptions(line(text, role: role), .useGlyphPathBounds)
        guard !bounds.isNull,
              bounds.origin.x.isFinite,
              bounds.origin.y.isFinite,
              bounds.width.isFinite,
              bounds.height.isFinite else {
            return .zero
        }
        return bounds
    }
}

struct MenuBarDashboardTwoLineLayout: Equatable {
    struct Run: Equatable {
        let text: String
        let role: MenuBarTextRole
        let baseline: CGPoint
        let inkRect: CGRect

        init(text: String, role: MenuBarTextRole, baseline: CGPoint, inkRect: CGRect) {
            self.text = text
            self.role = role
            self.baseline = baseline
            self.inkRect = inkRect
        }
    }

    static let chrome: CGFloat = 8
    private static let gap: CGFloat = 8
    private static let partGap: CGFloat = 3
    private static let verticalBandGlyphs = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789↑↓$%—+.,/"

    let size: CGSize
    let moduleIDs: [MonitorModuleID]
    let columnOrigins: [CGFloat]
    let runs: [Run]

    private init(size: CGSize, moduleIDs: [MonitorModuleID], columnOrigins: [CGFloat], runs: [Run]) {
        self.size = size
        self.moduleIDs = moduleIDs
        self.columnOrigins = columnOrigins
        self.runs = runs
    }

    @MainActor static func fit(
        segments: [MenuBarDashboardSegment],
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat
    ) -> Self? {
        guard (width.isFinite || width == .infinity),
              height.isFinite,
              height > 0,
              scale.isFinite,
              scale > 0,
              !segments.isEmpty else {
            return nil
        }
        let budget = width == .infinity ? CGFloat(240) : min(CGFloat(240), width)
        guard budget >= 22 else { return nil }

        let labels = segments.flatMap { segment in
            [segment.label, segment.compactLabel].map { label in
                labelWithOverflow(label, count: segment.providerOverflowCount)
            }
        }
        let values = segments.flatMap { segment in
            [segment.primary.text] + segment.primary.widthSamples
                + [segment.secondary?.text].compactMap { $0 }
                + (segment.secondary?.widthSamples ?? [])
        }
        let labelBand = unionBounds(labels, role: .label)
        let valueBand = unionBounds(values, role: .value)
        let inset = max(1, 1 / scale)
        let valueBaseline = inset - valueBand.minY
        let labelBaseline = height - inset - labelBand.maxY
        guard labelBaseline + labelBand.minY >= valueBaseline + valueBand.maxY + 1 else {
            return nil
        }

        let maximum = min(3, segments.count)
        for count in stride(from: maximum, through: 1, by: -1) {
            let shown = Array(segments.prefix(count))
            let omittedCount = segments.count - count
            for compact in [false, true] {
                guard let candidate = candidate(
                    shown: shown,
                    omittedCount: omittedCount,
                    compact: compact,
                    height: height,
                    scale: scale,
                    labelBaseline: labelBaseline,
                    valueBaseline: valueBaseline
                ), candidate.size.width + chrome <= budget else {
                    continue
                }
                return candidate
            }
        }
        return nil
    }

    @MainActor private static func candidate(
        shown: [MenuBarDashboardSegment],
        omittedCount: Int,
        compact: Bool,
        height: CGFloat,
        scale: CGFloat,
        labelBaseline: CGFloat,
        valueBaseline: CGFloat
    ) -> Self? {
        var columns: [(segment: MenuBarDashboardSegment?, label: String?, width: CGFloat)] = []
        for segment in shown {
            let label = labelWithOverflow(
                compact ? segment.compactLabel : segment.label,
                count: segment.providerOverflowCount
            )
            let primaryWidth = partWidth(segment.primary, scale: scale)
            let secondaryWidth = segment.secondary.map { partWidth($0, scale: scale) }
            let valuesWidth = primaryWidth + (secondaryWidth.map { partGap + $0 } ?? 0)
            let columnWidth = rounded(max(advance(label, role: .label) + 1, valuesWidth), scale: scale)
            columns.append((segment, label, columnWidth))
        }
        if omittedCount > 0 {
            let text = "+\(omittedCount)"
            columns.append((nil, nil, rounded(advance(text, role: .value) + 1, scale: scale)))
        }
        let total = rounded(
            8 + columns.reduce(CGFloat.zero) { $0 + $1.width } + gap * CGFloat(max(0, columns.count - 1)),
            scale: scale
        )
        var x: CGFloat = 4
        var origins: [CGFloat] = []
        var runs: [Run] = []
        for column in columns {
            origins.append(x)
            if let segment = column.segment, let label = column.label {
                appendRun(label, role: .label, leadingX: x, baselineY: labelBaseline, runs: &runs)
                appendRun(segment.primary.text, role: .value, leadingX: x, baselineY: valueBaseline, runs: &runs)
                if let secondary = segment.secondary {
                    let secondaryX = x + partWidth(segment.primary, scale: scale) + partGap
                    appendRun(secondary.text, role: .value, leadingX: secondaryX, baselineY: valueBaseline, runs: &runs)
                }
            } else {
                appendRun("+\(omittedCount)", role: .value, leadingX: x, baselineY: valueBaseline, runs: &runs)
            }
            x += column.width + gap
        }
        let size = CGSize(width: total, height: height)
        guard runs.allSatisfy({ run in
            run.inkRect.minX >= 0 && run.inkRect.minY >= 0
                && run.inkRect.maxX <= size.width && run.inkRect.maxY <= size.height
        }) else {
            return nil
        }
        return .init(size: size, moduleIDs: shown.map(\.moduleID), columnOrigins: origins, runs: runs)
    }

    @MainActor private static func appendRun(
        _ text: String,
        role: MenuBarTextRole,
        leadingX: CGFloat,
        baselineY: CGFloat,
        runs: inout [Run]
    ) {
        let glyphBounds = MenuBarGlyphs.bounds(text, role: role)
        let baseline = CGPoint(x: leadingX - glyphBounds.minX, y: baselineY)
        runs.append(.init(text: text, role: role, baseline: baseline, inkRect: glyphBounds.offsetBy(dx: baseline.x, dy: baseline.y)))
    }

    @MainActor private static func partWidth(_ part: MenuBarDashboardValuePart, scale: CGFloat) -> CGFloat {
        rounded((([part.text] + part.widthSamples).map { advance($0, role: .value) }.max() ?? 0) + 1, scale: scale)
    }

    @MainActor private static func unionBounds(_ texts: [String], role: MenuBarTextRole) -> CGRect {
        texts.reduce(MenuBarGlyphs.bounds(verticalBandGlyphs, role: role)) { partial, text in
            let bounds = MenuBarGlyphs.bounds(text, role: role)
            return partial.isNull ? bounds : partial.union(bounds)
        }
    }

    private static func labelWithOverflow(_ label: String, count: Int) -> String {
        count > 0 ? "\(label) +\(count)" : label
    }

    @MainActor private static func advance(_ text: String, role: MenuBarTextRole) -> CGFloat {
        MenuBarGlyphs.advance(text, role: role)
    }

    private static func rounded(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        ceil(value * scale) / scale
    }
}
