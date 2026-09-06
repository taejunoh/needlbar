import AppKit
import Darwin
import Foundation
import NeedlbarApp
import NeedlbarCore
import NeedlbarSettingsStudioReviewSupport

guard SettingsStudioReviewLaunch.isOptedIn(arguments: CommandLine.arguments) else {
    fputs("NeedlbarSettingsStudioReview requires --settings-studio-review\n", stderr)
    exit(64)
}

@MainActor
fileprivate final class SettingsStudioReviewHost: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let application: NSApplication
    private let suiteName = "NeedlbarSettingsStudioReview.\(UUID().uuidString)"
    private var defaults: UserDefaults?
    private var configuration: ModuleConfiguration?
    private var preferences: QuotaNotificationPreferences?
    private var notificationService: QuotaNotificationService?
    private var actions: SettingsActions?
    private var controllers: [SettingsWindowController] = []
    private var configurationObserver: NSObjectProtocol?
    private var timeoutTimer: Timer?
    private var openWindowCount = 0
    private var didLaunch = false
    private var isFinishing = false
    private var timedOut = false

    init(application: NSApplication) {
        self.application = application
        super.init()
    }

    var exitCode: Int32 { timedOut ? 1 : 0 }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !didLaunch else { return }
        didLaunch = true
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            finish(timedOut: true)
            return
        }

        let configuration = ModuleConfiguration(defaults: defaults)
        let preferences = QuotaNotificationPreferences(defaults: defaults)
        let snapshotStore = ProviderSnapshotStore()
        let notificationService = QuotaNotificationService(
            store: snapshotStore,
            preferences: preferences,
            client: SettingsStudioInertNotificationClient()
        )
        let actions = settingsStudioReviewActions(delay: .seconds(8))
        let emptySnapshot = CombinedUsageSnapshot(
            system: nil,
            providers: [],
            capturedAt: .distantPast,
            systemAvailability: [:]
        )

        self.defaults = defaults
        self.configuration = configuration
        self.preferences = preferences
        self.notificationService = notificationService
        self.actions = actions
        application.setActivationPolicy(.regular)

        let fixtures: [(NSAppearance.Name, String, NSSize)] = [
            (.aqua, "Light · Default", NSSize(width: 960, height: 720)),
            (.darkAqua, "Dark · Minimum", NSSize(width: 760, height: 560)),
        ]
        openWindowCount = fixtures.count
        for (appearance, label, size) in fixtures {
            let controller = SettingsWindowController(
                configuration: configuration,
                actions: actions,
                notificationPreferences: preferences,
                notificationService: notificationService,
                openCursorSpending: {}
            )
            guard let window = controller.window else {
                finish(timedOut: true)
                return
            }
            window.delegate = self
            window.title = "Needlbar Settings Review — \(label)"
            window.appearance = NSAppearance(named: appearance)
            window.setContentSize(size)
            window.center()
            controller.update(snapshot: emptySnapshot, configuration: configuration.systemMonitor)
            controller.showSettings()
            controllers.append(controller)
            print("SETTINGS_REVIEW pid=\(ProcessInfo.processInfo.processIdentifier) content=\(window.contentLayoutRect.size) minimum=\(window.contentMinSize) title=\(window.title)")
        }

        configurationObserver = NotificationCenter.default.addObserver(
            forName: ModuleConfiguration.systemMonitorDidChangeNotification,
            object: configuration,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updatePreviews()
            }
        }

        printConfiguration(configuration)
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.finish(timedOut: true)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func windowWillClose(_ notification: Notification) {
        guard !isFinishing else { return }
        openWindowCount = max(0, openWindowCount - 1)
        if openWindowCount == 0 {
            finish(timedOut: false)
        }
    }

    func cleanupAfterRun() {
        finish(timedOut: timedOut)
        controllers.removeAll()
        actions = nil
        notificationService?.stop()
        notificationService = nil
        preferences = nil
        configuration = nil
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private func updatePreviews() {
        guard let configuration else { return }
        let snapshot = CombinedUsageSnapshot(
            system: nil,
            providers: [],
            capturedAt: .distantPast,
            systemAvailability: [:]
        )
        for controller in controllers {
            controller.update(snapshot: snapshot, configuration: configuration.systemMonitor)
        }
        printConfiguration(configuration)
    }

    private func printConfiguration(_ configuration: ModuleConfiguration) {
        let value = configuration.systemMonitor
        print("SETTINGS_REVIEW_CONFIG menu=\(value.menuBarVisibleModules.map(\.rawValue).sorted()) dashboard=\(value.dashboardVisibleModules.map(\.rawValue).sorted()) order=\(value.order.map(\.rawValue)) aiOrder=\(value.aiOrder.map(\.rawValue))")
    }

    private func finish(timedOut: Bool) {
        guard !isFinishing else { return }
        isFinishing = true
        self.timedOut = timedOut
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        for controller in controllers where controller.window?.isVisible == true {
            controller.close()
        }
        application.stop(nil)
        if let event = NSEvent.otherEvent(
            with: .applicationDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 0,
            data1: 0,
            data2: 0
        ) {
            application.postEvent(event, atStart: false)
        }
    }
}

let application = NSApplication.shared
fileprivate let reviewHost = SettingsStudioReviewHost(application: application)
application.delegate = reviewHost
application.run()
let status = reviewHost.exitCode
reviewHost.cleanupAfterRun()
exit(status)
