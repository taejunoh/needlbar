import SwiftUI
import NeedlbarCore

public struct QuotaWindowRow: View {
    private let window: QuotaWindow
    private let isLastKnown: Bool

    public init(window: QuotaWindow, isLastKnown: Bool = false) {
        self.window = window
        self.isLastKnown = isLastKnown
    }

    public var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(window.title)
                if let reset = MetricFormatter.reset(window.resetsAt) {
                    Text(isLastKnown ? "Last known · Resets \(reset)" : "Resets \(reset)")
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
