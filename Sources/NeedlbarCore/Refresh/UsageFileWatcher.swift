import Darwin
import Dispatch
import Foundation

public protocol UsageFileEventSource: AnyObject, Sendable {
    func start(onEvent: @escaping @Sendable () -> Void)
    func stop()
}

public typealias UsageFileEventSourceFactory = @Sendable (URL) -> (any UsageFileEventSource)?
public typealias UsageRefreshRequestCallback = @Sendable () async -> Void

public actor UsageFileWatcher {
    public static let debounceInterval: Duration = .seconds(1)

    private let homeDirectory: URL
    private let environment: [String: String]
    private let cursorCacheDirectory: URL
    private let clock: any ClockLike
    private let sourceFactory: UsageFileEventSourceFactory
    private let onUsageRefreshRequested: UsageRefreshRequestCallback

    private var sources: [any UsageFileEventSource] = []
    private var debounceTask: Task<Void, Never>?
    private var debounceGeneration: UInt64 = 0
    private var isRunning = false

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        cursorCacheDirectory: URL? = nil,
        clock: any ClockLike = SystemClock(),
        sourceFactory: UsageFileEventSourceFactory? = nil,
        onUsageRefreshRequested: @escaping UsageRefreshRequestCallback
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.environment = environment
        self.cursorCacheDirectory = (cursorCacheDirectory
            ?? homeDirectory.appending(path: ".config/tokscale/cursor-cache", directoryHint: .isDirectory))
            .standardizedFileURL
        self.clock = clock
        self.sourceFactory = sourceFactory ?? { DirectoryFileEventSource(directory: $0) }
        self.onUsageRefreshRequested = onUsageRefreshRequested
    }

    deinit {
        debounceTask?.cancel()
        sources.forEach { $0.stop() }
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        sources = Self.discoverExistingRoots(
            homeDirectory: homeDirectory,
            environment: environment,
            cursorCacheDirectory: cursorCacheDirectory
        ).compactMap(sourceFactory)
        for source in sources {
            source.start { [weak self] in
                Task { await self?.receivedFileSystemEvent() }
            }
        }
    }

    public func stop() {
        guard isRunning || !sources.isEmpty || debounceTask != nil else { return }
        isRunning = false
        debounceGeneration &+= 1
        debounceTask?.cancel()
        debounceTask = nil
        sources.forEach { $0.stop() }
        sources.removeAll()
    }

    public static func discoverExistingRoots(
        homeDirectory: URL,
        environment: [String: String],
        cursorCacheDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> [URL] {
        let home = homeDirectory.standardizedFileURL
        let codexHome: URL
        if let configured = environment["CODEX_HOME"], !configured.isEmpty {
            codexHome = URL(fileURLWithPath: configured, isDirectory: true).standardizedFileURL
        } else {
            codexHome = home.appending(path: ".codex", directoryHint: .isDirectory)
        }
        let cursorCache = (cursorCacheDirectory
            ?? home.appending(path: ".config/tokscale/cursor-cache", directoryHint: .isDirectory))
            .standardizedFileURL
        let candidates = [
            home.appending(path: ".claude/projects", directoryHint: .isDirectory),
            home.appending(path: ".claude/transcripts", directoryHint: .isDirectory),
            codexHome.appending(path: "sessions", directoryHint: .isDirectory),
            codexHome.appending(path: "archived_sessions", directoryHint: .isDirectory),
            cursorCache,
        ]
        return candidates.filter { path in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return false
            }
            return (try? path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
        }
    }

    private func receivedFileSystemEvent() {
        guard isRunning else { return }
        debounceGeneration &+= 1
        let generation = debounceGeneration
        debounceTask?.cancel()
        let clock = clock
        debounceTask = Task { [weak self, clock] in
            do {
                try await clock.sleep(for: Self.debounceInterval)
            } catch is CancellationError {
                return
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.requestDebouncedRefresh(generation: generation)
        }
    }

    private func requestDebouncedRefresh(generation: UInt64) async {
        guard isRunning, debounceGeneration == generation else { return }
        debounceTask = nil
        await onUsageRefreshRequested()
    }
}

private final class DirectoryFileEventSource: UsageFileEventSource, @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.needlbar.usage-file-watcher")
    private let descriptorLease: DescriptorLease
    private var source: DispatchSourceFileSystemObject?
    private var cancellationScheduled = false

    init?(directory: URL) {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        self.descriptorLease = DescriptorLease(descriptor: descriptor)
    }

    deinit {
        stop()
    }

    func start(onEvent: @escaping @Sendable () -> Void) {
        let source: DispatchSourceFileSystemObject? = lock.withLock {
            guard self.source == nil, let descriptor = descriptorLease.descriptor else { return nil }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename, .extend, .attrib, .link, .revoke],
                queue: queue
            )
            source.setEventHandler(handler: onEvent)
            source.setCancelHandler { [descriptorLease] in
                descriptorLease.closeOnce()
            }
            self.source = source
            self.cancellationScheduled = true
            return source
        }
        source?.resume()
    }

    func stop() {
        let (source, closeImmediately): (DispatchSourceFileSystemObject?, Bool) = lock.withLock {
            let source = self.source
            self.source = nil
            return (source, source == nil && !cancellationScheduled)
        }
        if let source {
            source.cancel()
        } else if closeImmediately {
            descriptorLease.closeOnce()
        }
    }

    private final class DescriptorLease: @unchecked Sendable {
        private let lock = NSLock()
        private var fileDescriptor: Int32?

        init(descriptor: Int32) {
            fileDescriptor = descriptor
        }

        var descriptor: Int32? {
            lock.withLock { fileDescriptor }
        }

        func closeOnce() {
            let descriptor = lock.withLock { () -> Int32? in
                defer { fileDescriptor = nil }
                return fileDescriptor
            }
            if let descriptor {
                Darwin.close(descriptor)
            }
        }
    }
}
