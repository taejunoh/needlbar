import AppKit
import Foundation

public enum CursorSpendingAction {
    public static let dashboardURL = URL(string: "https://cursor.com/dashboard/spending")!

    @discardableResult
    public static func open(using opener: (URL) -> Bool = NSWorkspace.shared.open) -> Bool {
        opener(dashboardURL)
    }
}
