import Darwin
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

@MainActor
@Test func coordinatorStopBeforeTheSpawnedTaskPassesItsStartBarrierNeverLaunchesOrMutates() async {
    let startGate = SuspensionGate()
    let runner = CountingLoginRunner()
    let refresh = SuspendedQuotaRefresh()
    let finished = RunCompletionRecorder()
    let coordinator = ProviderLoginCoordinator(
        resolver: FixedLoginResolver(),
        runner: runner,
        refreshQuota: { provider in await refresh.refresh(provider) },
        beforeProcessStart: { _ in await startGate.wait() },
        runFinished: { provider in await finished.record(provider) }
    )

    #expect(coordinator.connect(.claude))
    await startGate.waitForEntry()
    await coordinator.stop()
    await startGate.release()
    await finished.wait(for: .claude)

    #expect(coordinator.state(for: .claude) == .idle)
    #expect(await runner.invocationCount() == 0)
    #expect(await refresh.callCount(for: .claude) == 0)
}

@Test(.serialized) func processRunnerPreventsALateLaunchWhenStoppedDuringPrelaunchRegistration() async throws {
    let fixture = try SignalFixture.make()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    let prelaunch = SuspensionGate()
    let starts = ProcessSignalRecorder()
    let runner = ProviderLoginProcessRunner(
        timeout: .seconds(30),
        terminationGrace: .milliseconds(10),
        preLaunch: { await prelaunch.wait() },
        processStarted: { pid in await starts.recordStart(pid) }
    )
    let task = Task { await runner.run(fixture.command(readyFile: fixture.directory.appendingPathComponent("unused-ready"))) }

    await prelaunch.waitForEntry()
    await runner.stop()
    await prelaunch.release()

    #expect(await task.value == .cancelled)
    #expect(await starts.startedPIDs().isEmpty)
    #expect(await starts.signals().isEmpty)
}

@Test(.serialized) func processRunnerSendsOnlyTERMToACompliantExactFixturePIDAndReapsIt() async throws {
    let fixture = try SignalFixture.make()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    let recorder = ProcessSignalRecorder()
    let runner = ProviderLoginProcessRunner(
        timeout: .seconds(30),
        terminationGrace: .seconds(1),
        signalObserved: { pid, signal in await recorder.send(pid, signal) },
        processStarted: { pid in await recorder.recordStart(pid) }
    )
    let readyFile = fixture.directory.appendingPathComponent("ready")
    let termFile = fixture.directory.appendingPathComponent("term")
    let task = Task { await runner.run(fixture.command(readyFile: readyFile, termFile: termFile)) }
    let pid = await recorder.waitForStart()
    try await waitForFixtureReady(at: readyFile)

    await runner.stop()
    #expect(await task.value == .cancelled)
    let signals = await recorder.signals()
    #expect((try? String(contentsOf: termFile, encoding: .utf8)) == "T")
    #expect(signals == [.init(pid: pid, signal: SIGTERM)], "actual signals: \(signals)")
    #expect(Darwin.kill(pid, 0) == -1)
}

@Test(.serialized) func processRunnerEscalatesOnlyTheTermIgnoringExactFixturePIDThenReapsIt() async throws {
    let fixture = try SignalFixture.make()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    let recorder = ProcessSignalRecorder(holdAfterTERM: true)
    let runner = ProviderLoginProcessRunner(
        timeout: .seconds(30),
        terminationGrace: .seconds(1),
        signalObserved: { pid, signal in await recorder.send(pid, signal) },
        processStarted: { pid in await recorder.recordStart(pid) }
    )
    let readyFile = fixture.directory.appendingPathComponent("ready")
    let task = Task { await runner.run(fixture.command(arguments: ["ignore-term"], readyFile: readyFile)) }
    let pid = await recorder.waitForStart()
    try await waitForFixtureReady(at: readyFile)
    #expect(Darwin.kill(pid, 0) == 0)

    let stop = Task { await runner.stop() }
    await recorder.waitForTERM()
    #expect(Darwin.kill(pid, 0) == 0)
    await recorder.releaseTERM()
    await stop.value
    #expect(await task.value == .cancelled)
    #expect(await recorder.signals() == [
        .init(pid: pid, signal: SIGTERM),
        .init(pid: pid, signal: SIGKILL),
    ])
    #expect(Darwin.kill(pid, 0) == -1)
}

@Test(.serialized) func processRunnerSharesOneTerminationSequenceAcrossConcurrentCancellationAndStop() async throws {
    let fixture = try SignalFixture.make()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    let recorder = ProcessSignalRecorder(holdAfterTERM: true)
    let runner = ProviderLoginProcessRunner(
        timeout: .seconds(30),
        terminationGrace: .seconds(1),
        signalObserved: { pid, signal in await recorder.send(pid, signal) },
        processStarted: { pid in await recorder.recordStart(pid) },
        processFinished: { pid in await recorder.recordFinish(pid) }
    )
    let readyFile = fixture.directory.appendingPathComponent("ready")
    let task = Task { await runner.run(fixture.command(arguments: ["ignore-term"], readyFile: readyFile)) }
    let pid = await recorder.waitForStart()
    try await waitForFixtureReady(at: readyFile)

    let stop = Task { await runner.stop() }
    await recorder.waitForTERM()
    task.cancel()
    await recorder.releaseTERM()
    await stop.value

    #expect(await task.value == .cancelled)
    #expect(await recorder.signals() == [
        .init(pid: pid, signal: SIGTERM),
        .init(pid: pid, signal: SIGKILL),
    ])
    #expect(await recorder.finishedPIDs() == [pid])
    #expect(Darwin.kill(pid, 0) == -1)
}

@Test(.serialized) func processRunnerTaskCancellationTerminatesAndReapsADirectChild() async throws {
    let fixture = try SignalFixture.make()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    let recorder = ProcessSignalRecorder()
    let runner = ProviderLoginProcessRunner(
        timeout: .seconds(30),
        terminationGrace: .milliseconds(100),
        signalObserved: { pid, signal in await recorder.send(pid, signal) },
        processStarted: { pid in await recorder.recordStart(pid) },
        processFinished: { pid in await recorder.recordFinish(pid) }
    )
    let readyFile = fixture.directory.appendingPathComponent("ready")
    let task = Task { await runner.run(fixture.command(readyFile: readyFile)) }
    let pid = await recorder.waitForStart()
    try await waitForFixtureReady(at: readyFile)

    task.cancel()

    #expect(await task.value == .cancelled)
    let signals = await recorder.signals()
    #expect(signals == [.init(pid: pid, signal: SIGTERM)], "actual signals: \(signals)")
    #expect(await recorder.finishedPIDs() == [pid])
    #expect(Darwin.kill(pid, 0) == -1)
}

@Test(.serialized) func processRunnerTimeoutTerminatesAndReapsADirectChild() async throws {
    let fixture = try SignalFixture.make()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    let recorder = ProcessSignalRecorder()
    let timeoutGate = SuspensionGate()
    let runner = ProviderLoginProcessRunner(
        timeout: .milliseconds(10),
        terminationGrace: .milliseconds(100),
        timeoutSleeper: { _ in await timeoutGate.wait() },
        signalObserved: { pid, signal in await recorder.send(pid, signal) },
        processStarted: { pid in await recorder.recordStart(pid) },
        processFinished: { pid in await recorder.recordFinish(pid) }
    )
    let readyFile = fixture.directory.appendingPathComponent("ready")
    let task = Task { await runner.run(fixture.command(readyFile: readyFile)) }
    let pid = await recorder.waitForStart()
    try await waitForFixtureReady(at: readyFile)
    await timeoutGate.release()

    #expect(await task.value == .timedOut)
    let signals = await recorder.signals()
    #expect(signals == [.init(pid: pid, signal: SIGTERM)], "actual signals: \(signals)")
    #expect(await recorder.finishedPIDs() == [pid])
    #expect(Darwin.kill(pid, 0) == -1)
}

@Test func processRunnerRetriesInterruptedWaitsAndSignalsWithoutLaunchingASecondChild() async {
    let system = ScriptedPOSIXSystem(
        spawn: .spawned(pid: 41),
        waits: [.interrupted, .running, .exited(status: 0)],
        signals: []
    )
    let runner = ProviderLoginProcessRunner(
        timeout: .seconds(30),
        pollSleeper: { _ in },
        system: system
    )

    #expect(await runner.run(scriptedCommand()) == .exited(status: 0))
    #expect(system.spawnCount == 1)
    #expect(system.waitCount == 3)
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

private actor CountingLoginRunner: ProviderLoginProcessRunning {
    private var calls = 0

    func run(_ command: ProviderLoginCommand) async -> ProviderLoginProcessOutcome {
        calls += 1
        return .exited(status: 0)
    }

    func stop() async {}
    func invocationCount() -> Int { calls }
}

private actor RunCompletionRecorder {
    private var providers: Set<ProviderID> = []
    private var waiters: [ProviderID: [CheckedContinuation<Void, Never>]] = [:]

    func record(_ provider: ProviderID) {
        providers.insert(provider)
        let providerWaiters = waiters.removeValue(forKey: provider) ?? []
        providerWaiters.forEach { $0.resume() }
    }

    func wait(for provider: ProviderID) async {
        if providers.contains(provider) { return }
        await withCheckedContinuation { continuation in waiters[provider, default: []].append(continuation) }
    }
}

private actor SuspensionGate {
    private var entered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = false

    func wait() async {
        entered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if released { return }
        await withCheckedContinuation { continuation in releaseWaiters.append(continuation) }
    }

    func waitForEntry() async {
        if entered { return }
        await withCheckedContinuation { continuation in entryWaiters.append(continuation) }
    }

    func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private actor ProcessSignalRecorder {
    struct Signal: Equatable, Sendable {
        let pid: Int32
        let signal: Int32
    }

    private var started: [Int32] = []
    private var startWaiters: [CheckedContinuation<Int32, Never>] = []
    private var sent: [Signal] = []
    private var finished: [Int32] = []
    private let holdAfterTERM: Bool
    private var termWaiters: [CheckedContinuation<Void, Never>] = []
    private var heldTERM: CheckedContinuation<Void, Never>?

    init(holdAfterTERM: Bool = false) {
        self.holdAfterTERM = holdAfterTERM
    }

    func recordStart(_ pid: Int32) {
        started.append(pid)
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume(returning: pid) }
    }

    func recordFinish(_ pid: Int32) {
        finished.append(pid)
    }

    func waitForStart() async -> Int32 {
        if let pid = started.first { return pid }
        return await withCheckedContinuation { continuation in startWaiters.append(continuation) }
    }

    func send(_ pid: Int32, _ signal: Int32) async {
        sent.append(.init(pid: pid, signal: signal))
        guard holdAfterTERM, signal == SIGTERM else { return }
        let waiters = termWaiters
        termWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in heldTERM = continuation }
    }

    func waitForTERM() async {
        if sent.contains(where: { $0.signal == SIGTERM }) { return }
        await withCheckedContinuation { continuation in termWaiters.append(continuation) }
    }

    func releaseTERM() {
        heldTERM?.resume()
        heldTERM = nil
    }

    func startedPIDs() -> [Int32] { started }
    func finishedPIDs() -> [Int32] { finished }
    func signals() -> [Signal] { sent }
}

private final class ScriptedPOSIXSystem: ProviderLoginProcessSystem, @unchecked Sendable {
    private let lock = NSLock()
    private let spawnResult: ProviderLoginSpawnResult
    private var waits: [ProviderLoginWaitResult]
    private var signalResults: [ProviderLoginSignalResult]
    private(set) var spawnCount = 0
    private(set) var waitCount = 0
    private(set) var sentSignals: [(Int32, Int32)] = []

    init(spawn: ProviderLoginSpawnResult, waits: [ProviderLoginWaitResult], signals: [ProviderLoginSignalResult]) {
        self.spawnResult = spawn
        self.waits = waits
        self.signalResults = signals
    }

    func spawn(_ command: ProviderLoginCommand) -> ProviderLoginSpawnResult {
        lock.lock(); defer { lock.unlock() }
        spawnCount += 1
        return spawnResult
    }

    func waitForChild(_ pid: Int32) -> ProviderLoginWaitResult {
        lock.lock(); defer { lock.unlock() }
        waitCount += 1
        return waits.isEmpty ? .running : waits.removeFirst()
    }

    func sendSignal(_ signal: Int32, to pid: Int32) -> ProviderLoginSignalResult {
        lock.lock(); defer { lock.unlock() }
        sentSignals.append((pid, signal))
        return signalResults.isEmpty ? .sent : signalResults.removeFirst()
    }
}

private func scriptedCommand() -> ProviderLoginCommand {
    ProviderLoginCommand(
        provider: .claude,
        executableURL: URL(fileURLWithPath: "/tmp/needlbar-login-tests/scripted"),
        arguments: [],
        environment: [:]
    )
}

private struct SignalFixture {
    let directory: URL
    let executable: URL

    static func make() throws -> SignalFixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let source = directory.appendingPathComponent("signal-fixture.c")
            let executable = directory.appendingPathComponent("signal-fixture")
            try """
        #include <signal.h>
        #include <fcntl.h>
        #include <stdlib.h>
        #include <unistd.h>
        static int term_fd = -1;
        static void exit_on_term(int ignored) { if (term_fd >= 0) write(term_fd, "T", 1); _exit(0); }
        int main(int argc, char **argv) {
            signal(SIGTERM, exit_on_term);
            if (argc == 2 && argv[1][0] == 'i') signal(SIGTERM, SIG_IGN);
            const char *term = getenv("NEEDLBAR_FIXTURE_TERM");
            if (term) term_fd = open(term, O_WRONLY | O_CREAT, 0600);
            const char *ready = getenv("NEEDLBAR_FIXTURE_READY");
            if (ready) {
                int fd = open(ready, O_WRONLY | O_CREAT, 0600);
                if (fd >= 0) { write(fd, "1", 1); close(fd); }
            }
            for (;;) sleep(1);
        }
        """.write(to: source, atomically: true, encoding: .utf8)

            let compiler = Process()
            compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            compiler.arguments = ["clang", source.path, "-o", executable.path]
            compiler.standardInput = FileHandle.nullDevice
            compiler.standardOutput = FileHandle.nullDevice
            compiler.standardError = FileHandle.nullDevice
            try compiler.run()
            compiler.waitUntilExit()
            guard compiler.terminationStatus == 0 else { throw SignalFixtureError.compilationFailed }
            return SignalFixture(directory: directory, executable: executable)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func command(arguments: [String] = [], readyFile: URL, termFile: URL? = nil) -> ProviderLoginCommand {
        var environment = ["NEEDLBAR_FIXTURE_READY": readyFile.path]
        if let termFile { environment["NEEDLBAR_FIXTURE_TERM"] = termFile.path }
        return ProviderLoginCommand(
            provider: .claude,
            executableURL: executable,
            arguments: arguments,
            environment: environment
        )
    }
}

private func waitForFixtureReady(at url: URL) async throws {
    for _ in 0..<1_000 {
        if FileManager.default.fileExists(atPath: url.path) { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    throw SignalFixtureError.readyTimedOut
}

private enum SignalFixtureError: Error {
    case compilationFailed
    case readyTimedOut
}

private enum CleanupEvent: Equatable, Sendable {
    case term(ProviderID)
    case kill(ProviderID)
    case reaped(ProviderID)
}
