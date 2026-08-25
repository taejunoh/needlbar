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

    private let timeout: Duration
    private let terminationGrace: Duration
    private var processes: [UUID: Process] = [:]
    private var stoppedReasons: [UUID: StopReason] = [:]
    private var reapWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

    public init(timeout: Duration = .seconds(300), terminationGrace: Duration = .seconds(1)) {
        self.timeout = timeout
        self.terminationGrace = terminationGrace
    }

    public func run(_ command: ProviderLoginCommand) async -> ProviderLoginProcessOutcome {
        let identifier = UUID()
        let processRunner = self
        return await withTaskCancellationHandler(operation: {
            await withTaskGroup(of: RaceResult.self, returning: ProviderLoginProcessOutcome.self) { group in
                group.addTask { [self] in
                    .process(await waitForProcess(command, identifier: identifier))
                }
                group.addTask { [timeout] in
                    do {
                        try await Task.sleep(for: timeout)
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
                        await stopProcess(identifier, reason: .timedOut)
                        group.cancelAll()
                    case .cancelledTimer:
                        continue
                    }
                }
                return .cancelled
            }
        }, onCancel: {
            Task { await processRunner.stopProcess(identifier, reason: .cancelled) }
        })
    }

    public func stop() async {
        let active = Array(processes.keys)
        for identifier in active {
            await stopProcess(identifier, reason: .cancelled)
        }
        for identifier in active {
            await waitForReap(identifier)
        }
    }

    private func waitForProcess(_ command: ProviderLoginCommand, identifier: UUID) async -> ProviderLoginProcessOutcome {
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
                processes[identifier] = process
            } catch {
                continuation.resume(returning: nil)
            }
        }

        processes.removeValue(forKey: identifier)
        let waiters = reapWaiters.removeValue(forKey: identifier) ?? []
        waiters.forEach { $0.resume() }
        guard let status else { return .launchFailed }
        switch stoppedReasons.removeValue(forKey: identifier) {
        case .timedOut: return .timedOut
        case .cancelled: return .cancelled
        case nil: return .exited(status: status)
        }
    }

    private func stopProcess(_ identifier: UUID, reason: StopReason) async {
        guard let process = processes[identifier], process.isRunning else { return }
        let pid = process.processIdentifier
        stoppedReasons[identifier] = reason
        _ = Darwin.kill(pid, SIGTERM)
        try? await Task.sleep(for: terminationGrace)
        guard let current = processes[identifier], current.processIdentifier == pid, current.isRunning else { return }
        _ = Darwin.kill(pid, SIGKILL)
    }

    private func waitForReap(_ identifier: UUID) async {
        guard processes[identifier] != nil else { return }
        await withCheckedContinuation { continuation in
            reapWaiters[identifier, default: []].append(continuation)
        }
    }
}

@MainActor
public final class ProviderLoginCoordinator: ObservableObject {
    @Published private var states: [ProviderID: ProviderLoginState] = [:]

    private let resolver: any ProviderLoginCommandResolving
    private let runner: any ProviderLoginProcessRunning
    private let refreshQuota: @Sendable (ProviderID) async -> Bool
    private let stateObserver: @Sendable (ProviderID, ProviderLoginState) async -> Void
    private var tasks: [ProviderID: Task<Void, Never>] = [:]
    private var generations: [ProviderID: UInt64] = [:]

    public init(
        resolver: any ProviderLoginCommandResolving = ProviderLoginCommandResolver(),
        runner: any ProviderLoginProcessRunning = ProviderLoginProcessRunner(),
        refreshQuota: @escaping @Sendable (ProviderID) async -> Bool,
        stateObserver: @escaping @Sendable (ProviderID, ProviderLoginState) async -> Void = { _, _ in }
    ) {
        self.resolver = resolver
        self.runner = runner
        self.refreshQuota = refreshQuota
        self.stateObserver = stateObserver
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
