import Foundation
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

@Test func resolverBuildsOnlyTheFixedClaudeAndCodexCommands() throws {
    let root = URL(fileURLWithPath: "/tmp/needlbar-login-tests")
    let resolver = ProviderLoginCommandResolver(
        environment: ["HOME": root.path, "PATH": "/usr/bin"],
        homeDirectory: root,
        executablePredicate: { url in url.lastPathComponent == "claude" || url.lastPathComponent == "codex" }
    )

    let claude = try resolver.command(for: .claude)
    let codex = try resolver.command(for: .codex)

    #expect(claude.arguments == ["auth", "login", "--claudeai"])
    #expect(codex.arguments == ["login"])
    #expect(claude.provider == .claude)
    #expect(codex.provider == .codex)
}

@Test func resolverRejectsCursorWithoutLookingForAnExecutable() {
    let resolver = ProviderLoginCommandResolver(
        environment: ["HOME": "/tmp/needlbar-login-tests"],
        homeDirectory: URL(fileURLWithPath: "/tmp/needlbar-login-tests"),
        executablePredicate: { _ in
            Issue.record("Cursor must not resolve an executable")
            return true
        }
    )

    #expect(throws: ProviderLoginCommandResolutionError.unsupportedProvider) {
        try resolver.command(for: .cursor)
    }
}

@Test func resolverUsesPathBeforeFixedFallbackLocations() throws {
    let home = URL(fileURLWithPath: "/tmp/needlbar-login-tests/home")
    let pathDirectory = URL(fileURLWithPath: "/tmp/needlbar-login-tests/path-bin")
    let expected = pathDirectory.appendingPathComponent("claude").standardizedFileURL
    let resolver = ProviderLoginCommandResolver(
        environment: ["HOME": home.path, "PATH": pathDirectory.path],
        homeDirectory: home,
        executablePredicate: { $0.standardizedFileURL == expected }
    )

    #expect(try resolver.command(for: .claude).executableURL == expected)
}

@Test func resolverExposesFixedCandidateSearchOrderIncludingVersionManagers() {
    let home = URL(fileURLWithPath: "/tmp/needlbar-login-tests/home")
    let resolver = ProviderLoginCommandResolver(
        environment: ["HOME": home.path, "PATH": "/first:/second"],
        homeDirectory: home,
        executablePredicate: { _ in false },
        directoryContents: { _ in [home.appendingPathComponent(".nvm/versions/node/v22.0.0", isDirectory: true)] }
    )

    let candidates = resolver.candidateURLs(for: .codex).map(\.path)

    #expect(candidates == [
        "/first/codex",
        "/second/codex",
        "/tmp/needlbar-login-tests/home/.local/bin/codex",
        "/tmp/needlbar-login-tests/home/.volta/bin/codex",
        "/tmp/needlbar-login-tests/home/.bun/bin/codex",
        "/tmp/needlbar-login-tests/home/.asdf/shims/codex",
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex",
        "/tmp/needlbar-login-tests/home/.nvm/versions/node/v22.0.0/bin/codex",
    ])
}

@Test func resolverBuildsMinimalProviderScopedEnvironment() throws {
    let home = URL(fileURLWithPath: "/tmp/needlbar-login-tests/home")
    let selected = URL(fileURLWithPath: "/tmp/needlbar-login-tests/wrapper/bin/claude")
    let inherited = [
        "HOME": home.path,
        "USER": "test-user",
        "LOGNAME": "test-login",
        "TMPDIR": "/tmp/needlbar-login-tests/tmp",
        "LANG": "en_US.UTF-8",
        "HTTPS_PROXY": "http://proxy.invalid",
        "SSL_CERT_FILE": "/tmp/cert.pem",
        "PATH": "/tmp/needlbar-login-tests/wrapper/bin",
        "CLAUDE_CONFIG_DIR": "/tmp/claude-config",
        "CODEX_HOME": "/tmp/codex-home",
        "ANTHROPIC_API_KEY": "must-not-leak",
        "ANTHROPIC_AUTH_TOKEN": "must-not-leak",
        "CLAUDE_CODE_OAUTH_TOKEN": "must-not-leak",
        "OPENAI_API_KEY": "must-not-leak",
        "FIXTURE_SECRET": "must-not-leak",
    ]
    let resolver = ProviderLoginCommandResolver(
        environment: inherited,
        homeDirectory: home,
        executablePredicate: { $0.standardizedFileURL == selected.standardizedFileURL }
    )

    let environment = try resolver.command(for: .claude).environment

    #expect(environment["PATH"] == "/tmp/needlbar-login-tests/wrapper/bin:/tmp/needlbar-login-tests/wrapper/bin")
    #expect(environment["CLAUDE_CONFIG_DIR"] == "/tmp/claude-config")
    #expect(environment["CODEX_HOME"] == nil)
    #expect(environment["ANTHROPIC_API_KEY"] == nil)
    #expect(environment["ANTHROPIC_AUTH_TOKEN"] == nil)
    #expect(environment["CLAUDE_CODE_OAUTH_TOKEN"] == nil)
    #expect(environment["OPENAI_API_KEY"] == nil)
    #expect(environment["FIXTURE_SECRET"] == nil)
    #expect(Set(environment.keys).isSubset(of: ProviderLoginCommandResolver.allowedEnvironmentKeys))
}

@MainActor
@Test func coordinatorRejectsDuplicateProviderButAllowsClaudeAndCodexTogether() async {
    let runner = SuspendedLoginRunner()
    let states = LoginStateRecorder()
    let coordinator = ProviderLoginCoordinator(
        resolver: FixedLoginResolver(),
        runner: runner,
        refreshQuota: { _ in true },
        stateObserver: { provider, state in await states.record(provider, state) }
    )

    #expect(coordinator.connect(.claude))
    #expect(!coordinator.connect(.claude))
    #expect(coordinator.connect(.codex))
    await runner.waitForStart(.claude)
    await runner.waitForStart(.codex)
    await states.wait(for: .claude, state: .awaitingBrowser)
    await states.wait(for: .codex, state: .awaitingBrowser)

    #expect(coordinator.state(for: .claude) == .awaitingBrowser)
    #expect(coordinator.state(for: .codex) == .awaitingBrowser)
    await coordinator.stop()
}

@MainActor
@Test func coordinatorVerifiesExactlyOnceAfterAZeroExit() async {
    let runner = SuspendedLoginRunner()
    let refresh = SuspendedQuotaRefresh()
    let states = LoginStateRecorder()
    let coordinator = ProviderLoginCoordinator(
        resolver: FixedLoginResolver(),
        runner: runner,
        refreshQuota: { provider in await refresh.refresh(provider) },
        stateObserver: { provider, state in await states.record(provider, state) }
    )

    #expect(coordinator.connect(.claude))
    await runner.waitForStart(.claude)
    await runner.complete(.claude, with: .exited(status: 0))
    await refresh.waitForCall(.claude)
    await states.wait(for: .claude, state: .refreshingQuota)
    #expect(await refresh.callCount(for: .claude) == 1)

    await refresh.complete(.claude, with: true)
    await states.wait(for: .claude, state: .connected)
    #expect(coordinator.state(for: .claude) == .connected)
}

@MainActor
@Test func coordinatorFailsVerificationWithoutOverwritingTheRunnerOutcome() async {
    let runner = SuspendedLoginRunner()
    let refresh = SuspendedQuotaRefresh()
    let states = LoginStateRecorder()
    let coordinator = ProviderLoginCoordinator(
        resolver: FixedLoginResolver(),
        runner: runner,
        refreshQuota: { provider in await refresh.refresh(provider) },
        stateObserver: { provider, state in await states.record(provider, state) }
    )

    #expect(coordinator.connect(.codex))
    await runner.waitForStart(.codex)
    await runner.complete(.codex, with: .exited(status: 0))
    await refresh.waitForCall(.codex)
    await refresh.complete(.codex, with: false)
    await states.wait(for: .codex, state: .failed(.verificationFailed))

    #expect(coordinator.state(for: .codex) == .failed(.verificationFailed))
}

@MainActor
@Test func coordinatorMapsSafeRunnerFailuresAndNeverLaunchesCursor() async {
    let runner = ImmediateLoginRunner(outcomes: [
        .claude: .launchFailed,
        .codex: .exited(status: 1),
    ])
    let states = LoginStateRecorder()
    let coordinator = ProviderLoginCoordinator(
        resolver: FixedLoginResolver(),
        runner: runner,
        refreshQuota: { _ in true },
        stateObserver: { provider, state in await states.record(provider, state) }
    )

    #expect(!coordinator.connect(.cursor))
    #expect(coordinator.connect(.claude))
    #expect(coordinator.connect(.codex))
    await states.wait(for: .cursor, state: .failed(.unsupportedProvider))
    await states.wait(for: .claude, state: .failed(.launchFailed))
    await states.wait(for: .codex, state: .failed(.providerRejected))

    #expect(await runner.commands().map(\.provider).sorted { $0.rawValue < $1.rawValue } == [.claude, .codex])
}

@MainActor
@Test func coordinatorMapsMissingCliTimeoutAndCancellationToFixedFailures() async {
    let states = LoginStateRecorder()
    let missingCLI = ProviderLoginCoordinator(
        resolver: MissingLoginResolver(),
        runner: ImmediateLoginRunner(outcomes: [:]),
        refreshQuota: { _ in true },
        stateObserver: { provider, state in await states.record(provider, state) }
    )
    #expect(!missingCLI.connect(.claude))
    await states.wait(for: .claude, state: .failed(.cliNotInstalled))

    let runner = ImmediateLoginRunner(outcomes: [.claude: .timedOut, .codex: .cancelled])
    let coordinator = ProviderLoginCoordinator(
        resolver: FixedLoginResolver(),
        runner: runner,
        refreshQuota: { _ in true },
        stateObserver: { provider, state in await states.record(provider, state) }
    )
    #expect(coordinator.connect(.claude))
    #expect(coordinator.connect(.codex))
    await states.wait(for: .claude, state: .failed(.timedOut))
    await states.wait(for: .codex, state: .failed(.cancelled))
}

@MainActor
@Test func coordinatorLeavesTheMainActorAvailableWhileTheChildIsSuspended() async {
    let runner = SuspendedLoginRunner()
    let coordinator = ProviderLoginCoordinator(
        resolver: FixedLoginResolver(),
        runner: runner,
        refreshQuota: { _ in true }
    )

    #expect(coordinator.connect(.claude))
    await runner.waitForStart(.claude)
    let mainActorMarker = Task { @MainActor in true }
    #expect(await mainActorMarker.value)
    await coordinator.stop()
}

@MainActor
@Test func coordinatorStopCancelsAndReapsChildrenAndRejectsLateRefresh() async {
    let runner = SuspendedLoginRunner()
    let refresh = SuspendedQuotaRefresh()
    let states = LoginStateRecorder()
    let coordinator = ProviderLoginCoordinator(
        resolver: FixedLoginResolver(),
        runner: runner,
        refreshQuota: { provider in await refresh.refresh(provider) },
        stateObserver: { provider, state in await states.record(provider, state) }
    )

    #expect(coordinator.connect(.claude))
    #expect(coordinator.connect(.codex))
    await runner.waitForStart(.claude)
    await runner.waitForStart(.codex)

    await coordinator.stop()
    #expect(await runner.cleanupEvents() == [.term(.claude), .kill(.claude), .reaped(.claude), .term(.codex), .kill(.codex), .reaped(.codex)])
    #expect(await refresh.callCount(for: .claude) == 0)
    #expect(await refresh.callCount(for: .codex) == 0)
    #expect(coordinator.state(for: .claude) == .idle)
    #expect(coordinator.state(for: .codex) == .idle)
}

private struct FixedLoginResolver: ProviderLoginCommandResolving {
    func command(for provider: ProviderID) throws -> ProviderLoginCommand {
        guard provider != .cursor else { throw ProviderLoginCommandResolutionError.unsupportedProvider }
        return ProviderLoginCommand(
            provider: provider,
            executableURL: URL(fileURLWithPath: "/tmp/needlbar-login-tests/bin/\(provider.rawValue)"),
            arguments: provider == .claude ? ["auth", "login", "--claudeai"] : ["login"],
            environment: [:]
        )
    }
}

private struct MissingLoginResolver: ProviderLoginCommandResolving {
    func command(for provider: ProviderID) throws -> ProviderLoginCommand {
        throw ProviderLoginCommandResolutionError.cliNotInstalled
    }
}

private actor LoginStateRecorder {
    private var recorded: [(ProviderID, ProviderLoginState)] = []
    private var waiters: [(ProviderID, ProviderLoginState, CheckedContinuation<Void, Never>)] = []

    func record(_ provider: ProviderID, _ state: ProviderLoginState) {
        recorded.append((provider, state))
        let matching = waiters.enumerated().filter { $0.element.0 == provider && $0.element.1 == state }
        for match in matching.reversed() {
            waiters.remove(at: match.offset).2.resume()
        }
    }

    func wait(for provider: ProviderID, state: ProviderLoginState) async {
        if recorded.contains(where: { $0.0 == provider && $0.1 == state }) { return }
        await withCheckedContinuation { waiter in waiters.append((provider, state, waiter)) }
    }
}

private actor SuspendedQuotaRefresh {
    private var calls: [ProviderID: Int] = [:]
    private var callWaiters: [ProviderID: [CheckedContinuation<Void, Never>]] = [:]
    private var continuations: [ProviderID: CheckedContinuation<Bool, Never>] = [:]

    func refresh(_ provider: ProviderID) async -> Bool {
        calls[provider, default: 0] += 1
        let waiters = callWaiters.removeValue(forKey: provider) ?? []
        waiters.forEach { $0.resume() }
        return await withCheckedContinuation { continuation in continuations[provider] = continuation }
    }

    func waitForCall(_ provider: ProviderID) async {
        if calls[provider, default: 0] > 0 { return }
        await withCheckedContinuation { continuation in callWaiters[provider, default: []].append(continuation) }
    }

    func callCount(for provider: ProviderID) -> Int { calls[provider, default: 0] }

    func complete(_ provider: ProviderID, with result: Bool) {
        continuations.removeValue(forKey: provider)?.resume(returning: result)
    }
}

private actor SuspendedLoginRunner: ProviderLoginProcessRunning {
    private var continuations: [ProviderID: CheckedContinuation<ProviderLoginProcessOutcome, Never>] = [:]
    private var starts: Set<ProviderID> = []
    private var startWaiters: [ProviderID: [CheckedContinuation<Void, Never>]] = [:]
    private var events: [CleanupEvent] = []

    func run(_ command: ProviderLoginCommand) async -> ProviderLoginProcessOutcome {
        starts.insert(command.provider)
        let waiters = startWaiters.removeValue(forKey: command.provider) ?? []
        waiters.forEach { $0.resume() }
        return await withCheckedContinuation { continuation in continuations[command.provider] = continuation }
    }

    func stop() async {
        for provider: ProviderID in [.claude, .codex] where continuations[provider] != nil {
            events.append(.term(provider))
            events.append(.kill(provider))
            continuations.removeValue(forKey: provider)?.resume(returning: .cancelled)
            events.append(.reaped(provider))
        }
    }

    func waitForStart(_ provider: ProviderID) async {
        if starts.contains(provider) { return }
        await withCheckedContinuation { continuation in startWaiters[provider, default: []].append(continuation) }
    }

    func complete(_ provider: ProviderID, with outcome: ProviderLoginProcessOutcome) {
        continuations.removeValue(forKey: provider)?.resume(returning: outcome)
    }

    func cleanupEvents() -> [CleanupEvent] { events }
}

private actor ImmediateLoginRunner: ProviderLoginProcessRunning {
    private let outcomes: [ProviderID: ProviderLoginProcessOutcome]
    private var launched: [ProviderLoginCommand] = []

    init(outcomes: [ProviderID: ProviderLoginProcessOutcome]) { self.outcomes = outcomes }

    func run(_ command: ProviderLoginCommand) async -> ProviderLoginProcessOutcome {
        launched.append(command)
        return outcomes[command.provider] ?? .launchFailed
    }

    func stop() async {}
    func commands() -> [ProviderLoginCommand] { launched }
}

private enum CleanupEvent: Equatable, Sendable {
    case term(ProviderID)
    case kill(ProviderID)
    case reaped(ProviderID)
}
