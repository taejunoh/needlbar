import AppKit
import SwiftUI

public enum SystemDashboardPanelSizing {
    static let width: CGFloat = 340
    static let minimumHeight: CGFloat = 180
    public static let fallbackHeight: CGFloat = 680
    static let verticalScreenAllowanceInset: CGFloat = 24
    static let resizeEpsilon: CGFloat = 0.5

    static func height(
        naturalContentHeight: CGFloat?,
        visibleScreenHeight: CGFloat
    ) -> CGFloat {
        guard visibleScreenHeight.isFinite, visibleScreenHeight > 0 else {
            return 0
        }
        let allowance = max(0, visibleScreenHeight - verticalScreenAllowanceInset)
        guard allowance > 0 else { return 0 }

        let candidate: CGFloat
        if let naturalContentHeight,
           naturalContentHeight.isFinite,
           naturalContentHeight > 0 {
            candidate = naturalContentHeight
        } else {
            candidate = fallbackHeight
        }
        let effectiveMinimum = min(minimumHeight, allowance)
        return min(max(effectiveMinimum, candidate), allowance)
    }

    static func shouldResize(current: CGFloat, proposed: CGFloat) -> Bool {
        current.isFinite
            && proposed.isFinite
            && abs(current - proposed) >= resizeEpsilon
    }
}

@MainActor
final class SystemDashboardPopoverLayout: ObservableObject {
    @Published var height: CGFloat

    init(height: CGFloat) {
        self.height = height
    }
}

@MainActor
enum SystemDashboardPopoverMeasurement {
    static func naturalHeight(for model: SystemDashboardModel) -> CGFloat? {
        let controller = NSHostingController(
            rootView: SystemDashboardPopoverView(measuring: model)
        )
        controller.view.layoutSubtreeIfNeeded()
        let measured = controller.view.fittingSize.height
        guard measured.isFinite, measured > 0 else { return nil }
        return measured
    }
}
