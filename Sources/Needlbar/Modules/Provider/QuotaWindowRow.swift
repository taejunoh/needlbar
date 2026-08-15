import SwiftUI
import NeedlbarCore

public struct QuotaWindowRow: View {
    private let window: QuotaWindow

    public init(window: QuotaWindow) {
        self.window = window
    }

    public var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(window.title)
                if let reset = MetricFormatter.reset(window.resetsAt) {
                    Text("Resets \(reset)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(MetricFormatter.quotaRemaining(window.remainingPercent))
                .monospacedDigit()
        }
    }
}
