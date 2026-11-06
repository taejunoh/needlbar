import AppKit
import SwiftUI
import Testing

/// Hosts a real view in an offscreen window and keeps it alive for `body`, so its
/// controls can be read and pressed through the accessibility tree. Nothing here
/// launches an app or touches the user's screen.
@MainActor
final class AccessibilityHostedView {
    struct Item: CustomStringConvertible {
        let role: String
        let label: String
        var description: String { "\(role)|\(label)" }
    }

    private let host: NSView
    private let window: NSWindow

    @discardableResult
    convenience init<Content: View>(
        _ content: Content,
        width: CGFloat = 320,
        body: (AccessibilityHostedView) throws -> Void = { _ in }
    ) throws {
        let hosting = NSHostingView(rootView: content.frame(width: width, alignment: .topLeading))
        try self.init(view: hosting, width: width, body: body)
    }

    @discardableResult
    init(
        view: NSView,
        width: CGFloat = 320,
        body: (AccessibilityHostedView) throws -> Void = { _ in }
    ) throws {
        let application = NSApplication.shared
        let wasEnhanced = application.value(forKey: "accessibilityEnhancedUserInterface") as? Bool ?? false
        application.setValue(true, forKey: "accessibilityEnhancedUserInterface")
        defer { application.setValue(wasEnhanced, forKey: "accessibilityEnhancedUserInterface") }

        let frame = NSRect(x: 0, y: 0, width: width, height: max(200, view.fittingSize.height))
        view.frame = frame
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        host = view
        self.window = window
        defer { window.close() }
        settle()
        try body(self)
    }

    func settle() {
        for _ in 0..<3 {
            window.display()
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }

    var items: [Item] { nodes.map(\.item) }

    var buttons: [String] { items.filter { $0.role == "AXButton" }.map(\.label) }

    func press(_ title: String) throws {
        let button = try #require(nodes.first { $0.item.role == "AXButton" && $0.item.label == title })
        let pressed = (button.node as? NSAccessibilityButton)?.accessibilityPerformPress()
            ?? (button.node.perform(NSSelectorFromString("accessibilityPerformPress")) != nil)
        #expect(pressed)
        settle()
    }

    private var nodes: [(item: Item, node: NSObject)] {
        var collected: [(item: Item, node: NSObject)] = []
        Self.walk(host, into: &collected, depth: 0)
        return collected
    }

    private static func walk(_ element: Any, into items: inout [(item: Item, node: NSObject)], depth: Int) {
        guard depth < 40, let node = element as? NSObject else { return }
        let role = (node.value(forKey: "accessibilityRole") as? String) ?? ""
        let label = (node.value(forKey: "accessibilityLabel") as? String) ?? ""
        if !(node is NSView) { items.append((Item(role: role, label: label), node)) }
        for child in (node.value(forKey: "accessibilityChildren") as? [Any]) ?? [] {
            walk(child, into: &items, depth: depth + 1)
        }
    }
}
