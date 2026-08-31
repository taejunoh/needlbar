import Foundation
import NeedlbarWidgetSupport

public protocol WidgetProjectionWriting: Sendable {
    func write(_ bytes: Data, to destination: URL) throws -> AtomicWriteResult
}

extension POSIXSnapshotFileWriter: WidgetProjectionWriting {
    public func write(_ bytes: Data, to destination: URL) throws -> AtomicWriteResult {
        try writeAtomically(bytes, to: destination)
    }
}

public protocol WidgetTimelineReloading: Sendable {
    func reloadOverview() async
}

public protocol WidgetProjectionCapturing: Sendable {
    func captureWidgetProjection(from store: ProviderSnapshotStore, exportedAt: Date) async -> WidgetStoreCapture
}

public struct ProviderSnapshotStoreWidgetCapturer: WidgetProjectionCapturing {
    public init() {}

    public func captureWidgetProjection(from store: ProviderSnapshotStore, exportedAt: Date) async -> WidgetStoreCapture {
        await store.captureForWidget(exportedAt: exportedAt)
    }
}

public actor WidgetProjectionPublisher {
    private let writer: any WidgetProjectionWriting
    private let reloader: any WidgetTimelineReloading
    private let capturer: any WidgetProjectionCapturing
    private let destination: URL
    private let now: @Sendable () -> Date
    private var observation: Task<Void, Never>?
    private var lastWritten: Data?

    public init(
        writer: any WidgetProjectionWriting = POSIXSnapshotFileWriter(),
        reloader: any WidgetTimelineReloading,
        destination: URL,
        now: @escaping @Sendable () -> Date = Date.init,
        capturer: any WidgetProjectionCapturing = ProviderSnapshotStoreWidgetCapturer()
    ) {
        self.writer = writer
        self.reloader = reloader
        self.capturer = capturer
        self.destination = destination
        self.now = now
    }

    public func start(observing store: ProviderSnapshotStore) {
        guard observation == nil else { return }
        observation = Task { [weak self] in
            let updates = await store.updates()
            for await _ in updates {
                guard let self, !Task.isCancelled else { return }
                let capture = await self.capturer.captureWidgetProjection(from: store, exportedAt: await self.currentDate())
                guard !Task.isCancelled else { return }
                await self.publish(capture)
            }
        }
    }

    public func stop() async {
        let task = observation
        observation = nil
        task?.cancel()
        await task?.value
    }

    public func publish(_ capture: WidgetStoreCapture) async {
        guard !Task.isCancelled else { return }
        guard let projection = try? WidgetProjectionMapper(now: capture.exportedAt).map(capture),
              let bytes = try? WidgetProjection.encode(projection),
              bytes != lastWritten,
              (try? writer.write(bytes, to: destination)) != nil else { return }
        guard !Task.isCancelled else { return }
        lastWritten = bytes
        await reloader.reloadOverview()
    }

    private func currentDate() -> Date { now() }
}
