import AppKit
import Foundation

public enum ClaudeUsageAction {
    public static let destination = URL(string: "https://claude.ai/settings/usage")!

    @discardableResult
    public static func open(using opener: (URL) -> Bool = NSWorkspace.shared.open) -> Bool {
        opener(destination)
    }
}
