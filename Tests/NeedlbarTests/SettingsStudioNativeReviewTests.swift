import AppKit
import Combine
import Foundation
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

// Opt-in review host only. Never starts AppDelegate, collectors, provider login,
// export writers, or the notification service. Close both windows to finish.
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["NEEDLBAR_SETTINGS_NATIVE_REVIEW"] == "1"))
func settingsStudioNativeReview() throws {
    let name = "SettingsStudio.native.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let configuration = ModuleConfiguration(defaults: defaults)
    let preferences = QuotaNotificationPreferences(defaults: defaults)
    let service = QuotaNotificationService(store: ProviderSnapshotStore(),
        preferences: preferences, client: SettingsStudioInertNotificationClient())
    let snapshot = CombinedUsageSnapshot(system: nil, providers: [],
        capturedAt: .distantPast, systemAvailability: [:])
    let application = NSApplication.shared
    let previousPolicy = application.activationPolicy()
    let previousDelegate = application.delegate
    let reviewDelegate = SettingsStudioReviewDelegate()
    application.delegate = reviewDelegate
    application.setActivationPolicy(.regular)
    defer {
        application.delegate = previousDelegate
        application.setActivationPolicy(previousPolicy)
    }
    var controllers: [SettingsWindowController] = []
    for (appearance, title, size) in [
        (NSAppearance.Name.aqua, "Light · Default", NSSize(width: 960, height: 720)),
        (NSAppearance.Name.darkAqua, "Dark · Minimum", NSSize(width: 760, height: 560)),
    ] {
        let controller = SettingsWindowController(configuration: configuration,
            actions: SettingsActions(), notificationPreferences: preferences,
            notificationService: service, openCursorSpending: {})
        let window = try #require(controller.window)
        window.delegate = reviewDelegate
        window.title = "Needlbar Settings Fixture — \(title)"
        window.appearance = NSAppearance(named: appearance)
        window.setContentSize(size)
        window.center()
        controller.update(snapshot: snapshot, configuration: configuration.systemMonitor)
        controller.showSettings()
        controllers.append(controller)
        print("SETTINGS_FIXTURE pid=\(ProcessInfo.processInfo.processIdentifier) window=\(window.windowNumber) content=\(window.contentLayoutRect.size) minimum=\(window.contentMinSize)")
    }
    defer { controllers.forEach { $0.close() } }
    let subscription = NotificationCenter.default.publisher(
        for: ModuleConfiguration.systemMonitorDidChangeNotification).sink { note in
            guard let changed = note.object as? ModuleConfiguration, changed === configuration else { return }
            for controller in controllers {
                controller.update(snapshot: snapshot, configuration: configuration.systemMonitor)
            }
            let value = configuration.systemMonitor
            print("SETTINGS_FIXTURE menu=\(value.menuBarVisibleModules.map(\.rawValue).sorted()) dashboard=\(value.dashboardVisibleModules.map(\.rawValue).sorted()) claudeMenu=\(value.ai[.claude]?.menuBarVisible == true) claudeDashboard=\(value.ai[.claude]?.dashboardVisible == true) order=\(value.order.map(\.rawValue))")
        }
    defer { subscription.cancel() }
    let timeout = Timer.scheduledTimer(withTimeInterval: 600, repeats: false) { _ in
        MainActor.assumeIsolated {
            reviewDelegate.timedOut = true
            reviewDelegate.stopReview()
        }
    }
    defer { timeout.invalidate() }
    application.run()
    // Only asserts fixture teardown safety; visual/interaction results are recorded
    // separately. A skipped or timed-out review is not native acceptance evidence.
    #expect(preferences.state == .off)
    #expect(!reviewDelegate.timedOut)
}

@MainActor
private final class SettingsStudioReviewDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var remainingWindows = 2
    var timedOut = false
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func windowWillClose(_ notification: Notification) {
        remainingWindows -= 1
        if remainingWindows == 0 { stopReview() }
    }
    func stopReview() {
        NSApplication.shared.stop(nil)
        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            subtype: 0, data1: 0, data2: 0) {
            NSApplication.shared.postEvent(event, atStart: false)
        }
    }
}

private struct SettingsStudioInertNotificationClient: QuotaNotificationClient {
    func currentAuthorization() async -> QuotaNotificationAuthorization { .denied }
    func requestAuthorization() async -> QuotaNotificationAuthorization { .denied }
    func submit(body: String) async -> QuotaNotificationSubmission { .failed }
}
