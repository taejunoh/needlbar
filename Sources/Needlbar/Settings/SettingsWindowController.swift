import AppKit
import NeedlbarCore
import SwiftUI

@MainActor
public final class SettingsWindowController: NSWindowController {
    private let preview: SettingsPreviewModel
    private var screenObservation: SettingsScreenObservation?

    var previewResult: MenuBarDashboardRenderResult { preview.result }

    public init(
        configuration: ModuleConfiguration,
        actions: SettingsActions,
        notificationPreferences: QuotaNotificationPreferences,
        notificationService: QuotaNotificationService,
        openCursorSpending: @escaping () -> Void = { _ = CursorSpendingAction.open() }
    ) {
        let preview = SettingsPreviewModel()
        self.preview = preview
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Needlbar Settings"
        let hostingView = NSHostingView(rootView: SettingsView(
            configuration: configuration,
            actions: actions,
            notificationPreferences: notificationPreferences,
            notificationService: notificationService,
            openCursorSpending: openCursorSpending,
            preview: preview
        ))
        // AppKit owns the screen-safe limits; intrinsic SwiftUI sizing must not
        // overwrite them when a detail pane or its content changes.
        hostingView.sizingOptions = []
        let container = NSView(frame: window.contentLayoutRect)
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        window.contentView = container
        window.isReleasedWhenClosed = false
        super.init(window: window)
        screenObservation = SettingsScreenObservation(window: window) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.window?.isVisible == true else { return }
                self.fitToCurrentScreen()
            }
        }
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
        fitToCurrentScreen()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func update(snapshot: CombinedUsageSnapshot, configuration: SystemMonitorConfiguration) {
        preview.update(snapshot: snapshot, configuration: configuration)
    }

    static func fittedFrame(_ desired: NSRect, in screen: NSRect) -> NSRect {
        let width = min(max(1, desired.width), max(1, screen.width))
        let height = min(max(1, desired.height), max(1, screen.height))
        return NSRect(
            x: min(max(desired.minX, screen.minX), screen.maxX - width),
            y: min(max(desired.minY, screen.minY), screen.maxY - height),
            width: width,
            height: height
        )
    }

    private func fitToCurrentScreen() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let available = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let chrome = window.frame.height - window.contentLayoutRect.height
        window.contentMinSize = NSSize(width: min(760, available.width),
                                      height: min(560, max(1, available.height - chrome)))
        window.maxSize = available.size
        window.setFrame(Self.fittedFrame(window.frame, in: available), display: false)
    }
}

private final class SettingsScreenObservation {
    private let tokens: [NSObjectProtocol]

    init(window: NSWindow, _ change: @escaping @Sendable () -> Void) {
        let center = NotificationCenter.default
        tokens = [
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                               object: nil, queue: .main) { _ in change() },
            center.addObserver(forName: NSWindow.didChangeScreenNotification,
                               object: window, queue: .main) { _ in change() },
        ]
    }

    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }
}
