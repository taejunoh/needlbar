import AppKit
import NeedlbarCore
import SwiftUI

@MainActor
public final class SettingsWindowController: NSWindowController {
    public init(configuration: ModuleConfiguration) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Needlbar Settings"
        window.contentView = NSHostingView(rootView: SettingsView(configuration: configuration))
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func showSettings() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
