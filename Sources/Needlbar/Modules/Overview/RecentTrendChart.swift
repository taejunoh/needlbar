import SwiftUI

struct RecentTrendChart: View {
    let samples: [(Double?, Double?)]
    let firstColor: Color
    let secondColor: Color

    var body: some View {
        Canvas { context, size in
            let values = samples.flatMap { [$0.0, $0.1] }.compactMap { $0 }
            guard let maximum = values.max(), maximum > 0, samples.count > 1 else { return }
            drawSeries(samples.map(\.0), color: firstColor, maximum: maximum, size: size, context: &context)
            drawSeries(samples.map(\.1), color: secondColor, maximum: maximum, size: size, context: &context)
        }
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityHidden(true)
    }

    private func drawSeries(
        _ values: [Double?], color: Color, maximum: Double, size: CGSize, context: inout GraphicsContext
    ) {
        var path = Path()
        var hasOpenSegment = false
        for (index, value) in values.enumerated() {
            guard let value else {
                hasOpenSegment = false
                continue
            }
            let x = size.width * CGFloat(index) / CGFloat(max(1, values.count - 1))
            let y = size.height * (1 - CGFloat(value / maximum))
            if hasOpenSegment {
                path.addLine(to: CGPoint(x: x, y: y))
            } else {
                path.move(to: CGPoint(x: x, y: y))
                hasOpenSegment = true
            }
        }
        context.stroke(path, with: .color(color), lineWidth: 1.5)
    }
}
