import SwiftUI

public struct SevenDayUsageChart: View {
    private let tokens: [UInt64]?

    public init(tokens: [UInt64]?) {
        self.tokens = tokens
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last 7 days").font(.caption).foregroundStyle(.secondary)
            if let tokens {
                GeometryReader { geometry in
                    Path { path in
                        guard !tokens.isEmpty else { return }
                        let maximum = max(tokens.max() ?? 0, 1)
                        let step = tokens.count > 1 ? geometry.size.width / CGFloat(tokens.count - 1) : 0
                        for (index, value) in tokens.enumerated() {
                            let x = CGFloat(index) * step
                            let y = geometry.size.height * (1 - CGFloat(Double(value) / Double(maximum)))
                            index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    .stroke(.tint, lineWidth: 2)
                }
                .frame(height: 52)
            } else {
                Text("Usage history unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
