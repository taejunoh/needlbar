import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import NeedlbarApp
@testable import NeedlbarCore

@MainActor
@Test func exportCapturesOnceBeforePanelAndPassesExactJSONURLToCore() async throws {
    let events = ExportEventLog()
    let captureSource = FakeCaptureSource(capture: validExportCapture(), events: events)
    let destination = URL(fileURLWithPath: "/tmp/backup.json")
    let presenter = FakeSavePanelPresenter(result: destination, events: events)
    let action = RecordingCoreExportAction(result: .committed, events: events)
    let controller = SnapshotExportController(
        captureSource: captureSource,
        savePanelPresenter: presenter,
        coreExportAction: action,
        captureClock: { fixedExportDate }
    )

    controller.exportSnapshot()

    #expect(await eventually { controller.state == .exported })
    #expect(await captureSource.callCount == 1)
    #expect(presenter.filenames == ["Needlbar-Snapshot-20260829T123456000Z.json"])
    #expect(await action.destinations == [destination])
    #expect(events.values == ["capture", "panel", "core"])
}

@MainActor
@Test func cancellationRestoresPriorStateAndDoesNotInvokeCore() async {
    let action = RecordingCoreExportAction(result: .committed)
    let controller = makeController(panelResult: nil, action: action)

    controller.exportSnapshot()

    #expect(await eventually { controller.state == .idle })
    #expect(await action.callCount == 0)
}

@MainActor
@Test func reentryWhileExportingRunsOnlyOneCapturePanelAndCoreAction() async {
    let captureSource = FakeCaptureSource(capture: validExportCapture())
    let presenter = FakeSavePanelPresenter(result: URL(fileURLWithPath: "/tmp/backup.json"))
    let action = RecordingCoreExportAction(result: .committed)
    let controller = SnapshotExportController(
        captureSource: captureSource,
        savePanelPresenter: presenter,
        coreExportAction: action,
        captureClock: { fixedExportDate }
    )

    controller.exportSnapshot()
    controller.exportSnapshot()

    #expect(await eventually { controller.state == .exported })
    #expect(await captureSource.callCount == 1)
    #expect(presenter.callCount == 1)
    #expect(await action.callCount == 1)
}

@MainActor
@Test(arguments: [
    URL(string: "https://example.com/backup.json")!,
    URL(fileURLWithPath: "/tmp/backup.txt"),
])
func invalidDestinationFailsBeforeInvokingCore(_ destination: URL) async {
    let action = RecordingCoreExportAction(result: .committed)
    let controller = makeController(panelResult: destination, action: action)

    controller.exportSnapshot()

    #expect(await eventually { controller.state == .failed })
    #expect(await action.callCount == 0)
}

@MainActor
@Test func coreFailureProducesOnlyFailedState() async {
    let action = RecordingCoreExportAction(error: SnapshotFileWriteError.writeFailed)
    let controller = makeController(
        panelResult: URL(fileURLWithPath: "/tmp/backup.json"),
        action: action
    )

    controller.exportSnapshot()

    #expect(await eventually { controller.state == .failed })
}

@MainActor
@Test func durabilityWarningIsPresentedAsExported() async {
    let action = RecordingCoreExportAction(result: .committedWithDurabilityWarning)
    let controller = makeController(
        panelResult: URL(fileURLWithPath: "/tmp/backup.json"),
        action: action
    )

    controller.exportSnapshot()

    #expect(await eventually { controller.state == .exported })
}

@MainActor
@Test func savePanelPresenterRestrictsToJSONAndUsesExactDefaultName() {
    let panel = RecordingSavePanel()
    let presenter = NSSavePanelPresenter(panelFactory: { panel })
    let name = "Needlbar-Snapshot-20260829T123456000Z.json"

    #expect(presenter.selectDestination(defaultFilename: name) == nil)
    #expect(panel.allowedContentTypes == [.json])
    #expect(panel.allowsOtherFileTypes == false)
    #expect(panel.nameFieldStringValue == name)
}

@MainActor
@Test func settingsDataExportActionRoutesToControllerAndDisablesDuringExport() async {
    let refreshOrLoginCounter = InvocationCounter()
    let action = RecordingCoreExportAction(result: .committed)
    let controller = makeController(
        panelResult: URL(fileURLWithPath: "/tmp/backup.json"),
        action: action
    )
    let view = SettingsView(
        configuration: ModuleConfiguration(defaults: freshSettingsDefaults()),
        loginCoordinator: ProviderLoginCoordinator(refreshQuota: { _ in
            await refreshOrLoginCounter.increment()
            return true
        }),
        snapshotExportController: controller
    )

    view.exportSnapshot()

    #expect(view.isExportButtonDisabled)
    #expect(await eventually { controller.state == .exported })
    #expect(!view.isExportButtonDisabled)
    #expect(await action.callCount == 1)
    #expect(await refreshOrLoginCounter.value == 0)
}

@MainActor
private func makeController(
    panelResult: URL?,
    action: RecordingCoreExportAction
) -> SnapshotExportController {
    SnapshotExportController(
        captureSource: FakeCaptureSource(capture: validExportCapture()),
        savePanelPresenter: FakeSavePanelPresenter(result: panelResult),
        coreExportAction: action,
        captureClock: { fixedExportDate }
    )
}

private let fixedExportDate = Date(timeIntervalSince1970: 1_788_006_896)

private func validExportCapture() -> ExportCapture {
    ExportCapture(exportedAt: fixedExportDate, providers: [])
}

@MainActor
private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0 ..< 100 {
        if condition() { return true }
        await Task.yield()
    }
    return false
}

@MainActor
private final class ExportEventLog {
    private(set) var values: [String] = []

    func record(_ event: String) {
        values.append(event)
    }
}

private actor InvocationCounter {
    private var storage = 0

    func increment() {
        storage += 1
    }

    var value: Int { storage }
}

private actor FakeCaptureSource: ExportCaptureProviding {
    private let capture: ExportCapture
    private let events: ExportEventLog?
    private(set) var callCount = 0

    init(capture: ExportCapture, events: ExportEventLog? = nil) {
        self.capture = capture
        self.events = events
    }

    func captureForExport(exportedAt _: Date) async -> ExportCapture {
        callCount += 1
        await events?.record("capture")
        return capture
    }
}

@MainActor
private final class FakeSavePanelPresenter: SavePanelPresenter {
    private let result: URL?
    private let events: ExportEventLog?
    private(set) var filenames: [String] = []
    private(set) var callCount = 0

    init(result: URL?, events: ExportEventLog? = nil) {
        self.result = result
        self.events = events
    }

    func selectDestination(defaultFilename: String) -> URL? {
        filenames.append(defaultFilename)
        callCount += 1
        events?.record("panel")
        return result
    }
}

private actor RecordingCoreExportAction: CoreExportAction {
    private let result: AtomicWriteResult?
    private let error: (any Error)?
    private let events: ExportEventLog?
    private(set) var destinations: [URL] = []

    init(result: AtomicWriteResult, events: ExportEventLog? = nil) {
        self.result = result
        error = nil
        self.events = events
    }

    init(error: any Error) {
        result = nil
        self.error = error
        events = nil
    }

    var callCount: Int { destinations.count }

    func export(_ capture: ExportCapture, to destination: URL) async throws -> AtomicWriteResult {
        destinations.append(destination)
        await events?.record("core")
        if let error { throw error }
        return result!
    }
}

@MainActor
private final class RecordingSavePanel: NSSavePanel {
    override func runModal() -> NSApplication.ModalResponse {
        .cancel
    }
}

private func freshSettingsDefaults() -> UserDefaults {
    let suiteName = "SnapshotExportControllerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
