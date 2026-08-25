import Combine
import Darwin
import Foundation
import NeedlbarCore

public enum ProviderLoginState: Equatable, Sendable {
    case idle
    case launching
    case awaitingBrowser
    case refreshingQuota
    case connected
    case failed(ProviderLoginFailure)
}

public enum ProviderLoginFailure: Error, Equatable, Sendable {
    case unsupportedProvider
    case cliNotInstalled
    case launchFailed
    case cancelled
    case timedOut
    case providerRejected
    case verificationFailed
}

public struct ProviderLoginCommand: Equatable, Sendable {
    public let provider: ProviderID
    public let executableURL: URL
    public let arguments: [String]
    public let environment: [String: String]

    public init(provider: ProviderID, executableURL: URL, arguments: [String], environment: [String: String]) {
        self.provider = provider
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
    }
}

public enum ProviderLoginCommandResolutionError: Error, Equatable, Sendable {
    case unsupportedProvider
    case cliNotInstalled
}

public protocol ProviderLoginCommandResolving: Sendable {
    func command(for provider: ProviderID) throws -> ProviderLoginCommand
}

public struct ProviderLoginCommandResolver: ProviderLoginCommandResolving, Sendable {
    public static let allowedEnvironmentKeys: Set<String> = [
        "HOME", "USER", "LOGNAME", "TMPDIR", "PATH", "LANG", "LANGUAGE", "LC_ALL",
        "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "http_proxy", "https_proxy",
        "all_proxy", "no_proxy", "SSL_CERT_FILE", "SSL_CERT_DIR", "REQUESTS_CA_BUNDLE",
        "CURL_CA_BUNDLE", "NODE_EXTRA_CA_CERTS", "CLAUDE_CONFIG_DIR", "CODEX_HOME",
    ]

    private let environment: [String: String]
    private let homeDirectory: URL
    private let executablePredicate: @Sendable (URL) -> Bool
    private let directoryContents: @Sendable (URL) -> [URL]

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        executablePredicate: @escaping @Sendable (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) },
        directoryContents: @escaping @Sendable (URL) -> [URL] = {
            (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? []
        }
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.executablePredicate = executablePredicate
        self.directoryContents = directoryContents
    }

    public func command(for provider: ProviderID) throws -> ProviderLoginCommand {
        let arguments: [String]
        switch provider {
        case .claude:
            arguments = ["auth", "login", "--claudeai"]
        case .codex:
            arguments = ["login"]
        case .cursor:
            throw ProviderLoginCommandResolutionError.unsupportedProvider
        }

        guard let executableURL = candidateURLs(for: provider).first(where: executablePredicate) else {
            throw ProviderLoginCommandResolutionError.cliNotInstalled
        }
        let standardizedURL = executableURL.standardizedFileURL
        return ProviderLoginCommand(
            provider: provider,
            executableURL: standardizedURL,
            arguments: arguments,
            environment: childEnvironment(for: provider, executableURL: standardizedURL)
        )
    }

    public func candidateURLs(for provider: ProviderID) -> [URL] {
        let executableName: String
        switch provider {
        case .claude: executableName = "claude"
        case .codex: executableName = "codex"
        case .cursor: return []
        }

        let pathDirectories = (environment["PATH"] ?? "").split(separator: ":").map {
            URL(fileURLWithPath: String($0), isDirectory: true)
        }
        let fixedDirectories = [
            homeDirectory.appendingPathComponent(".local/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".volta/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".bun/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".asdf/shims", isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
        ]
        let nvmRoot = homeDirectory.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        let nvmDirectories = directoryContents(nvmRoot)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { $0.appendingPathComponent("bin", isDirectory: true) }

        return (pathDirectories + fixedDirectories + nvmDirectories).map {
            $0.appendingPathComponent(executableName, isDirectory: false).standardizedFileURL
        }
    }

    private func childEnvironment(for provider: ProviderID, executableURL: URL) -> [String: String] {
        var child: [String: String] = [:]
        for (key, value) in environment where Self.permitsEnvironmentKey(key) {
            child[key] = value
        }
        child["CLAUDE_CONFIG_DIR"] = provider == .claude ? environment["CLAUDE_CONFIG_DIR"] : nil
        child["CODEX_HOME"] = provider == .codex ? environment["CODEX_HOME"] : nil

        let parent = executableURL.deletingLastPathComponent().path
        let inheritedPath = environment["PATH"] ?? ""
        child["PATH"] = inheritedPath.isEmpty ? parent : "\(parent):\(inheritedPath)"
        return child
    }

    private static func permitsEnvironmentKey(_ key: String) -> Bool {
        allowedEnvironmentKeys.contains(key) || key.hasPrefix("LC_")
    }
}

public enum ProviderLoginProcessOutcome: Equatable, Sendable {
    case exited(status: Int32)
    case launchFailed
    case timedOut
    case cancelled
}

public struct ProviderLoginProcessIdentity: Equatable, Sendable {
    public let processIdentifier: Int32
    public let startSeconds: Int64
    public let startMicroseconds: Int64

    public init(processIdentifier: Int32, startSeconds: Int64, startMicroseconds: Int64) {
        self.processIdentifier = processIdentifier
        self.startSeconds = startSeconds
        self.startMicroseconds = startMicroseconds
    }
}

public protocol ProviderLoginProcessRunning: Sendable {
    func run(_ command: ProviderLoginCommand) async -> ProviderLoginProcessOutcome
    func stop() async
}

public actor ProviderLoginProcessRunner: ProviderLoginProcessRunning {
    private enum StopReason {
        case timedOut
        case cancelled
    }

    private enum RaceResult {
        case process(ProviderLoginProcessOutcome)
        case timeout
        case cancelledTimer
    }

    private struct RunningSession {
        let process: Process
        let identity: ProviderLoginProcessIdentity?
        var stopReason: StopReason?
        var terminationTask: Task<Void, Never>?
    }

    private enum Session {
        case pending(StopReason?)
        case running(RunningSession)

        var stopReason: StopReason? {
            switch self {
            case let .pending(reason): reason
            case let .running(session): session.stopReason
            }
        }
    }

    private let timeout: Duration
    private let terminationGrace: Duration
    private let timeoutSleeper: @Sendable (Duration) async throws -> Void
    private let preLaunch: @Sendable () async -> Void
    private let signalSender: @Sendable (Int32, Int32) async -> Int32
    private let processIdentity: @Sendable (Int32) -> ProviderLoginProcessIdentity?
    private let processStarted: @Sendable (Int32) async -> Void
    private let processFinished: @Sendable (Int32) async -> Void
    private var sessions: [UUID: Session] = [:]
    private var reapWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

    public init(
        timeout: Duration = .seconds(300),
        terminationGrace: Duration = .seconds(1),
        timeoutSleeper: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        preLaunch: @escaping @Sendable () async -> Void = {},
        signalSender: @escaping @Sendable (Int32, Int32) async -> Int32 = { Darwin.kill($0, $1) },
        processIdentity: (@Sendable (Int32) -> ProviderLoginProcessIdentity?)? = nil,
        processStarted: @escaping @Sendable (Int32) async -> Void = { _ in },
        processFinished: @escaping @Sendable (Int32) async -> Void = { _ in }
    ) {
        self.timeout = timeout
        self.terminationGrace = terminationGrace
        self.timeoutSleeper = timeoutSleeper
        self.preLaunch = preLaunch
        self.signalSender = signalSender
        let defaultIdentity: @Sendable (Int32) -> ProviderLoginProcessIdentity? = { pid in
            Self.liveProcessIdentity(for: pid)
        }
        self.processIdentity = processIdentity ?? defaultIdentity
        self.processStarted = processStarted
        self.processFinished = processFinished
    }

    public func run(_ command: ProviderLoginCommand) async -> ProviderLoginProcessOutcome {
        let identifier = UUID()
        sessions[identifier] = .pending(Task.isCancelled ? .cancelled : nil)
        if Task.isCancelled {
            sessions.removeValue(forKey: identifier)
            return .cancelled
        }
        let processRunner = self
        return await withTaskCancellationHandler(operation: {
            await withTaskGroup(of: RaceResult.self, returning: ProviderLoginProcessOutcome.self) { group in
                group.addTask { [self] in
                    .process(await waitForProcess(command, identifier: identifier))
                }
                group.addTask { [timeout, timeoutSleeper] in
                    do {
                        try await timeoutSleeper(timeout)
                        return .timeout
                    } catch {
                        return .cancelledTimer
                    }
                }

                while let result = await group.next() {
                    switch result {
                    case let .process(outcome):
                        group.cancelAll()
                        return outcome
                    case .timeout:
                        await requestTermination(identifier, reason: .timedOut)
                        group.cancelAll()
                    case .cancelledTimer:
                        continue
                    }
                }
                return .cancelled
            }
        }, onCancel: {
            Task { await processRunner.requestTermination(identifier, reason: .cancelled) }
        })
    }

    public func stop() async {
        let active = Array(sessions.keys)
        for identifier in active {
            await requestTermination(identifier, reason: .cancelled)
        }
    }

    private func waitForProcess(_ command: ProviderLoginCommand, identifier: UUID) async -> ProviderLoginProcessOutcome {
        await preLaunch()
        guard case let .pending(reason)? = sessions[identifier] else { return .cancelled }
        if let reason {
            completePendingSession(identifier)
            return outcome(for: reason)
        }

        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.environment = command.environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let status: Int32? = await withCheckedContinuation { continuation in
            process.terminationHandler = { terminated in
                continuation.resume(returning: terminated.terminationStatus)
            }
            do {
                try process.run()
                // No actor suspension occurs between spawning and registration. A stop request
                // therefore either prevents this launch while pending or targets this exact PID.
                sessions[identifier] = .running(.init(
                    process: process,
                    identity: processIdentity(process.processIdentifier),
                    stopReason: nil,
                    terminationTask: nil
                ))
                let observer = processStarted
                Task { await observer(process.processIdentifier) }
            } catch {
                continuation.resume(returning: nil)
            }
        }

        let finishedProcess = sessions[identifier].flatMap { session -> Process? in
            guard case let .running(running) = session else { return nil }
            return running.process
        }
        let stopReason = sessions.removeValue(forKey: identifier)?.stopReason
        resumeReapWaiters(for: identifier)
        if let finishedProcess {
            await processFinished(finishedProcess.processIdentifier)
        }
        guard let status else { return .launchFailed }
        if let stopReason { return outcome(for: stopReason) }
        return .exited(status: status)
    }

    private func requestTermination(_ identifier: UUID, reason: StopReason) async {
        guard let session = sessions[identifier] else { return }
        switch session {
        case .pending(let existingReason):
            sessions[identifier] = .pending(existingReason ?? reason)
            return
        case var .running(running):
            running.stopReason = running.stopReason ?? reason
            if let terminationTask = running.terminationTask {
                sessions[identifier] = .running(running)
                await terminationTask.value
                return
            }
            guard running.process.isRunning else {
                sessions[identifier] = .running(running)
                await waitForReap(identifier)
                return
            }

            let processRunner = self
            let terminationTask = Task {
                await processRunner.terminateAndReap(identifier)
            }
            running.terminationTask = terminationTask
            sessions[identifier] = .running(running)
            await terminationTask.value
        }
    }

    private func terminateAndReap(_ identifier: UUID) async {
        guard case let .running(running)? = sessions[identifier] else { return }
        let pid = running.process.processIdentifier
        _ = await signalSender(pid, SIGTERM)
        try? await Task.sleep(for: terminationGrace)
        guard case let .running(current)? = sessions[identifier], current.process.processIdentifier == pid else { return }
        guard current.process.isRunning, let identity = current.identity else {
            await waitForReap(identifier)
            return
        }
        // PID equality is never sufficient: the start-time token must still identify the same
        // child immediately before escalation. A missing or changed token fails closed.
        guard processIdentity(pid) == identity else {
            await waitForReap(identifier)
            return
        }
        _ = await signalSender(pid, SIGKILL)
        await waitForReap(identifier)
    }

    private func waitForReap(_ identifier: UUID) async {
        guard case .running? = sessions[identifier] else { return }
        await withCheckedContinuation { continuation in
            reapWaiters[identifier, default: []].append(continuation)
        }
    }

    private func completePendingSession(_ identifier: UUID) {
        sessions.removeValue(forKey: identifier)
        resumeReapWaiters(for: identifier)
    }

    private func resumeReapWaiters(for identifier: UUID) {
        let waiters = reapWaiters.removeValue(forKey: identifier) ?? []
        waiters.forEach { $0.resume() }
    }

    private func outcome(for reason: StopReason) -> ProviderLoginProcessOutcome {
        switch reason {
        case .timedOut: return .timedOut
        case .cancelled: return .cancelled
        }
    }

    private static func liveProcessIdentity(for pid: Int32) -> ProviderLoginProcessIdentity? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return ProviderLoginProcessIdentity(
            processIdentifier: pid,
            startSeconds: Int64(info.pbi_start_tvsec),
            startMicroseconds: Int64(info.pbi_start_tvusec)
        )
    }
}

@MainActor
public final class ProviderLoginCoordinator: ObservableObject {
    @Published private var states: [ProviderID: ProviderLoginState] = [:]

    private let resolver: any ProviderLoginCommandResolving
    private let runner: any ProviderLoginProcessRunning
    private let refreshQuota: @Sendable (ProviderID) async -> Bool
    private let beforeProcessStart: @Sendable (ProviderID) async -> Void
    private let stateObserver: @Sendable (ProviderID, ProviderLoginState) async -> Void
    private let runFinished: @Sendable (ProviderID) async -> Void
    private var tasks: [ProviderID: Task<Void, Never>] = [:]
    private var generations: [ProviderID: UInt64] = [:]

    public init(
        resolver: any ProviderLoginCommandResolving = ProviderLoginCommandResolver(),
        runner: any ProviderLoginProcessRunning = ProviderLoginProcessRunner(),
        refreshQuota: @escaping @Sendable (ProviderID) async -> Bool,
        stateObserver: @escaping @Sendable (ProviderID, ProviderLoginState) async -> Void = { _, _ in },
        beforeProcessStart: @escaping @Sendable (ProviderID) async -> Void = { _ in },
        runFinished: @escaping @Sendable (ProviderID) async -> Void = { _ in }
    ) {
        self.resolver = resolver
        self.runner = runner
        self.refreshQuota = refreshQuota
        self.stateObserver = stateObserver
        self.beforeProcessStart = beforeProcessStart
        self.runFinished = runFinished
    }

    @discardableResult
    public func connect(_ provider: ProviderID) -> Bool {
        guard tasks[provider] == nil else { return false }
        updateState(.launching, for: provider)

        let command: ProviderLoginCommand
        do {
            command = try resolver.command(for: provider)
        } catch let error as ProviderLoginCommandResolutionError {
            updateState(error == .unsupportedProvider ? .failed(.unsupportedProvider) : .failed(.cliNotInstalled), for: provider)
            return false
        } catch {
            updateState(.failed(.cliNotInstalled), for: provider)
            return false
        }

        let generation = nextGeneration(for: provider)
        tasks[provider] = Task { [weak self] in
            await self?.run(command, provider: provider, generation: generation)
        }
        return true
    }

    public func state(for provider: ProviderID) -> ProviderLoginState {
        states[provider] ?? .idle
    }

    public func stop() async {
        let activeProviders = Array(tasks.keys)
        for provider in activeProviders {
            _ = nextGeneration(for: provider)
            tasks.removeValue(forKey: provider)?.cancel()
            updateState(.idle, for: provider)
        }
        await runner.stop()
    }

    private func run(_ command: ProviderLoginCommand, provider: ProviderID, generation: UInt64) async {
        defer {
            let observer = runFinished
            Task { await observer(provider) }
        }
        await beforeProcessStart(provider)
        guard isCurrent(generation, for: provider), !Task.isCancelled else { return }
        updateState(.awaitingBrowser, for: provider)
        let outcome = await runner.run(command)
        guard isCurrent(generation, for: provider) else { return }

        switch outcome {
        case let .exited(status) where status == 0:
            updateState(.refreshingQuota, for: provider)
            let verified = await refreshQuota(provider)
            guard isCurrent(generation, for: provider) else { return }
            updateState(verified ? .connected : .failed(.verificationFailed), for: provider)
        case .exited:
            updateState(.failed(.providerRejected), for: provider)
        case .launchFailed:
            updateState(.failed(.launchFailed), for: provider)
        case .timedOut:
            updateState(.failed(.timedOut), for: provider)
        case .cancelled:
            updateState(.failed(.cancelled), for: provider)
        }
        if isCurrent(generation, for: provider) {
            tasks[provider] = nil
        }
    }

    private func nextGeneration(for provider: ProviderID) -> UInt64 {
        let next = (generations[provider] ?? 0) &+ 1
        generations[provider] = next
        return next
    }

    private func isCurrent(_ generation: UInt64, for provider: ProviderID) -> Bool {
        generations[provider] == generation
    }

    private func updateState(_ state: ProviderLoginState, for provider: ProviderID) {
        states[provider] = state
        let observer = stateObserver
        Task { await observer(provider, state) }
    }
}
