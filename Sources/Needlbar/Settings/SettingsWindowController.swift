import AppKit
import NeedlbarCore
import SwiftUI

@MainActor
public final class SettingsWindowController: NSWindowController {
    public init(
        configuration: ModuleConfiguration,
        actions: SettingsActions,
        notificationPreferences: QuotaNotificationPreferences,
        notificationService: QuotaNotificationService,
        openCursorSpending: @escaping () -> Void = { _ = CursorSpendingAction.open() }
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Needlbar Settings"
        window.contentView = NSHostingView(rootView: SettingsView(
            configuration: configuration,
            actions: actions,
            notificationPreferences: notificationPreferences,
            notificationService: notificationService,
            openCursorSpending: openCursorSpending
        ))
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    public convenience init(
        configuration: ModuleConfiguration,
        loginCoordinator: ProviderLoginCoordinator,
        snapshotExportController: SnapshotExportController,
        notificationPreferences: QuotaNotificationPreferences,
        notificationService: QuotaNotificationService,
        openCursorSpending: @escaping () -> Void = { _ = CursorSpendingAction.open() }
    ) {
        self.init(
            configuration: configuration,
            actions: SettingsActions(
                loginCoordinator: loginCoordinator,
                snapshotExportController: snapshotExportController
            ),
            notificationPreferences: notificationPreferences,
            notificationService: notificationService,
            openCursorSpending: openCursorSpending
        )
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
