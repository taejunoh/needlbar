import AppKit
import Combine
import Foundation
import NeedlbarCore
import UniformTypeIdentifiers

@MainActor
public protocol SavePanelPresenter: AnyObject {
    func selectDestination(defaultFilename: String) -> URL?
}

@MainActor
public final class NSSavePanelPresenter: SavePanelPresenter {
    private let panelFactory: @MainActor () -> NSSavePanel

    public init(panelFactory: @escaping @MainActor () -> NSSavePanel = { NSSavePanel() }) {
        self.panelFactory = panelFactory
    }

    public func selectDestination(defaultFilename: String) -> URL? {
        let panel = panelFactory()
        panel.allowedContentTypes = [.json]
        panel.allowsOtherFileTypes = false
        panel.nameFieldStringValue = defaultFilename
        return panel.runModal() == .OK ? panel.url : nil
    }
}

public enum SnapshotExportState: Equatable {
    case idle
    case exporting
    case exported
    case failed
}

public typealias CaptureClock = () -> Date

@MainActor
public final class SnapshotExportController: ObservableObject {
    @Published public private(set) var state: SnapshotExportState = .idle

    public var isExporting: Bool {
        state == .exporting
    }

    private let captureSource: any ExportCaptureProviding
    private let savePanelPresenter: any SavePanelPresenter
    private let coreExportAction: any CoreExportAction
    private let captureClock: CaptureClock

    public init(
        captureSource: any ExportCaptureProviding,
        savePanelPresenter: any SavePanelPresenter,
        coreExportAction: any CoreExportAction,
        captureClock: @escaping CaptureClock
    ) {
        self.captureSource = captureSource
        self.savePanelPresenter = savePanelPresenter
        self.coreExportAction = coreExportAction
        self.captureClock = captureClock
    }

    public func exportSnapshot() {
        guard !isExporting else { return }

        let priorState = state
        state = .exporting
        let exportedAt = captureClock()

        Task { @MainActor [weak self, captureSource, savePanelPresenter, coreExportAction] in
            let capture = await captureSource.captureForExport(exportedAt: exportedAt)
            guard let self else { return }
            guard let destination = savePanelPresenter.selectDestination(
                defaultFilename: Self.filename(for: exportedAt)
            ) else {
                self.state = priorState
                return
            }
            guard destination.isFileURL, destination.pathExtension.lowercased() == "json" else {
                self.state = .failed
                return
            }
            do {
                _ = try await coreExportAction.export(capture, to: destination)
                self.state = .exported
            } catch {
                self.state = .failed
            }
        }
    }

    private static func filename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmssSSS'Z'"
        return "Needlbar-Snapshot-\(formatter.string(from: date)).json"
    }
}
