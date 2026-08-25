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

public enum ProviderLoginSpawnResult: Equatable, Sendable {
    case spawned(pid: Int32)
    case failed
}

public enum ProviderLoginWaitResult: Equatable, Sendable {
    case running
    case exited(status: Int32)
    case interrupted
    case noChild
    case failed
}

public enum ProviderLoginSignalResult: Equatable, Sendable {
    case sent
    case noSuchProcess
    case interrupted
    case failed
}

/// The runner owns this narrow syscall surface so the actor is the sole reaper of its child.
public protocol ProviderLoginProcessSystem: Sendable {
    func spawn(_ command: ProviderLoginCommand) -> ProviderLoginSpawnResult
    func waitForChild(_ pid: Int32) -> ProviderLoginWaitResult
    func sendSignal(_ signal: Int32, to pid: Int32) -> ProviderLoginSignalResult
}

public struct ProviderLoginPOSIXSystem: ProviderLoginProcessSystem, Sendable {
    public init() {}

    public func spawn(_ command: ProviderLoginCommand) -> ProviderLoginSpawnResult {
        let executable = command.executableURL.standardizedFileURL.path
        let values = [executable] + command.arguments
        let environment = command.environment
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
        guard values.allSatisfy({ !$0.utf8.contains(0) }), environment.allSatisfy({ !$0.utf8.contains(0) }) else {
            return .failed
        }

        let argv = values.map { Darwin.strdup($0) }
        let envp = environment.map { Darwin.strdup($0) }
        guard argv.allSatisfy({ $0 != nil }), envp.allSatisfy({ $0 != nil }) else {
            argv.forEach { Darwin.free($0) }
            envp.forEach { Darwin.free($0) }
            return .failed
        }
        defer {
            argv.forEach { Darwin.free($0) }
            envp.forEach { Darwin.free($0) }
        }

        var argvPointers = argv + [nil]
        var envpPointers = envp + [nil]
        var actions: posix_spawn_file_actions_t? = nil
        guard posix_spawn_file_actions_init(&actions) == 0 else { return .failed }
        defer { posix_spawn_file_actions_destroy(&actions) }
        let nullDevice = "/dev/null"
        guard posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, nullDevice, O_RDONLY, 0) == 0,
              posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, nullDevice, O_WRONLY, 0) == 0,
              posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, nullDevice, O_WRONLY, 0) == 0 else {
            return .failed
        }

        var attributes: posix_spawnattr_t? = nil
        guard posix_spawnattr_init(&attributes) == 0 else { return .failed }
        defer { posix_spawnattr_destroy(&attributes) }
        var signalMask = sigset_t()
        guard sigemptyset(&signalMask) == 0,
              posix_spawnattr_setsigmask(&attributes, &signalMask) == 0,
              posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK)) == 0 else {
            return .failed
        }

        var pid: pid_t = 0
        let result = executable.withCString { executablePointer in
            posix_spawn(&pid, executablePointer, &actions, &attributes, &argvPointers, &envpPointers)
        }
        return result == 0 ? .spawned(pid: pid) : .failed
    }

    public func waitForChild(_ pid: Int32) -> ProviderLoginWaitResult {
        var status: Int32 = 0
        let result = Darwin.waitpid(pid, &status, WNOHANG)
        if result == 0 { return .running }
        if result == pid {
            if (status & 0x7f) == 0 { return .exited(status: (status >> 8) & 0xff) }
            return .exited(status: 1)
        }
        switch errno {
        case EINTR: return .interrupted
        case ECHILD: return .noChild
        default: return .failed
        }
    }

    public func sendSignal(_ signal: Int32, to pid: Int32) -> ProviderLoginSignalResult {
        if Darwin.kill(pid, signal) == 0 { return .sent }
        switch errno {
        case EINTR: return .interrupted
        case ESRCH: return .noSuchProcess
        default: return .failed
        }
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
        let pid: Int32
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
    private let pollSleeper: @Sendable (Duration) async throws -> Void
    private let preLaunch: @Sendable () async -> Void
    private let system: any ProviderLoginProcessSystem
    private let beforeSignal: @Sendable (Int32, Int32) async -> Void
    private let signalObserved: @Sendable (Int32, Int32) async -> Void
    private let processStarted: @Sendable (Int32) async -> Void
    private let processFinished: @Sendable (Int32) async -> Void
    private var sessions: [UUID: Session] = [:]
    private var finished: [UUID: ProviderLoginProcessOutcome] = [:]

    public init(
        timeout: Duration = .seconds(300),
        terminationGrace: Duration = .seconds(1),
        timeoutSleeper: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        pollSleeper: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        preLaunch: @escaping @Sendable () async -> Void = {},
        system: any ProviderLoginProcessSystem = ProviderLoginPOSIXSystem(),
        beforeSignal: @escaping @Sendable (Int32, Int32) async -> Void = { _, _ in },
        signalObserved: @escaping @Sendable (Int32, Int32) async -> Void = { _, _ in },
        processStarted: @escaping @Sendable (Int32) async -> Void = { _ in },
        processFinished: @escaping @Sendable (Int32) async -> Void = { _ in }
    ) {
        self.timeout = timeout
        self.terminationGrace = terminationGrace
        self.timeoutSleeper = timeoutSleeper
        self.pollSleeper = pollSleeper
        self.preLaunch = preLaunch
        self.system = system
        self.beforeSignal = beforeSignal
        self.signalObserved = signalObserved
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
            let outcome = await withTaskGroup(of: RaceResult.self, returning: ProviderLoginProcessOutcome.self) { group in
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
            finished.removeValue(forKey: identifier)
            return outcome
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

        guard !Task.isCancelled else {
            sessions.removeValue(forKey: identifier)
            return .cancelled
        }
        guard case let .spawned(pid) = system.spawn(command) else {
            sessions.removeValue(forKey: identifier)
            return .launchFailed
        }
        // Actor isolation makes launch registration atomic with respect to stop: after spawn
        // there is no suspension until this exact PID is represented by the session.
        sessions[identifier] = .running(.init(pid: pid, stopReason: nil, terminationTask: nil))
        let observer = processStarted
        Task { await observer(pid) }
        return await waitForCompletion(identifier)
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
        let pid = running.pid
        switch await send(SIGTERM, to: pid) {
        case .sent:
            try? await pollSleeper(terminationGrace)
        case .noSuchProcess:
            _ = await reap(identifier, pid: pid, limit: 4)
            return
        case .failed, .interrupted:
            _ = await reap(identifier, pid: pid, limit: 4, failureOutcome: true)
            return
        }
        if await reap(identifier, pid: pid, limit: 1) { return }
        switch await send(SIGKILL, to: pid) {
        case .sent, .noSuchProcess:
            _ = await reap(identifier, pid: pid, limit: 8)
        case .failed, .interrupted:
            _ = await reap(identifier, pid: pid, limit: 8, failureOutcome: true)
        }
    }

    private func waitForCompletion(_ identifier: UUID) async -> ProviderLoginProcessOutcome {
        while true {
            if let outcome = finished[identifier] { return outcome }
            guard case let .running(running)? = sessions[identifier] else { return .cancelled }
            switch system.waitForChild(running.pid) {
            case .running:
                try? await pollSleeper(.milliseconds(5))
            case .interrupted:
                continue
            case let .exited(status):
                complete(identifier, pid: running.pid, outcome: running.stopReason.map(outcome(for:)) ?? .exited(status: status))
            case .noChild, .failed:
                complete(identifier, pid: running.pid, outcome: .launchFailed)
            }
        }
    }

    private func reap(_ identifier: UUID, pid: Int32, limit: Int, failureOutcome: Bool = false) async -> Bool {
        for _ in 0..<limit {
            if let outcome = finished[identifier] { return outcome != .launchFailed }
            guard case let .running(running)? = sessions[identifier], running.pid == pid else { return true }
            switch system.waitForChild(pid) {
            case let .exited(status):
                complete(identifier, pid: pid, outcome: failureOutcome ? .launchFailed : (running.stopReason.map(outcome(for:)) ?? .exited(status: status)))
                return true
            case .noChild, .failed:
                complete(identifier, pid: pid, outcome: .launchFailed)
                return true
            case .interrupted:
                continue
            case .running:
                try? await pollSleeper(.milliseconds(5))
            }
        }
        // Keep the session registered if a hostile OS failure prevented a reap. A later stop
        // can retry; this runner never forgets a known live child.
        return false
    }

    private func send(_ signal: Int32, to pid: Int32) async -> ProviderLoginSignalResult {
        for _ in 0..<3 {
            await beforeSignal(pid, signal)
            let result = system.sendSignal(signal, to: pid)
            if result == .sent { await signalObserved(pid, signal) }
            if result != .interrupted { return result }
        }
        return .failed
    }

    private func completePendingSession(_ identifier: UUID) {
        sessions.removeValue(forKey: identifier)
    }

    private func complete(_ identifier: UUID, pid: Int32, outcome: ProviderLoginProcessOutcome) {
        guard case let .running(running)? = sessions[identifier], running.pid == pid else { return }
        sessions.removeValue(forKey: identifier)
        finished[identifier] = outcome
        let observer = processFinished
        Task { await observer(pid) }
    }

    private func outcome(for reason: StopReason) -> ProviderLoginProcessOutcome {
        switch reason {
        case .timedOut: return .timedOut
        case .cancelled: return .cancelled
        }
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
