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
@Test func coordinatorRetainsAProvidersAdmissionUntilItsFailedChildIsReaped() async {
    let runner = DeferredReapingLoginRunner()
    let states = LoginStateRecorder()
    let finished = RunCompletionRecorder()
    let coordinator = ProviderLoginCoordinator(
        resolver: FixedLoginResolver(),
        runner: runner,
        refreshQuota: { _ in true },
        stateObserver: { provider, state in await states.record(provider, state) },
        runFinished: { provider in await finished.record(provider) }
    )

    #expect(coordinator.connect(.claude))
    #expect(coordinator.connect(.codex))
    await runner.waitForInvocation(of: .claude, count: 1)
    await runner.waitForInvocation(of: .codex, count: 1)
    await states.wait(for: .claude, state: .failed(.launchFailed))
    await states.wait(for: .codex, state: .failed(.launchFailed))
    await runner.waitForReapingWaiterCount(2)

    #expect(!coordinator.connect(.claude))
    #expect(await runner.invocationCount(for: .claude) == 1)

    await runner.completeNaturalExitAndReap(for: .claude)
    await finished.wait(for: .claude)

    #expect(coordinator.connect(.claude))
    await runner.waitForInvocation(of: .claude, count: 2)
    #expect(await runner.invocationCount(for: .claude) == 2)
    await runner.completeNaturalExitAndReap(for: .codex)
    await finished.wait(for: .codex)
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
@Test func coordinatorReportsPendingReapUntilEveryStoppedProviderHasReaped() async {
    let runner = CleanupResultLoginRunner(pendingReap: [.claude])
    let coordinator = ProviderLoginCoordinator(
        resolver: FixedLoginResolver(),
        runner: runner,
        refreshQuota: { _ in true }
    )

    #expect(coordinator.connect(.claude))
    #expect(coordinator.connect(.codex))
    await runner.waitForStart(.claude, count: 1)
    await runner.waitForStart(.codex, count: 1)

    #expect(await coordinator.stop() == .pendingReap)
    #expect(!coordinator.connect(.claude))
    #expect(await runner.stopCallCount() == 1)

    coordinator.resumeAfterDeniedTermination()
    await runner.completeBackgroundReap(for: .claude)
    var reconnected = false
    for _ in 0..<100 {
        if coordinator.connect(.claude) {
            reconnected = true
            break
        }
        await Task.yield()
    }
    #expect(reconnected)
    await runner.waitForStart(.claude, count: 2)

    #expect(await coordinator.stop() == .complete)
    #expect(await runner.stopCallCount() == 2)
}

@MainActor
@Test func coordinatorRetainsStoppedProvidersAdmissionThroughTerminationAndBackgroundReaping() async {
    let runner = StopAndReapLoginRunner()
    let finished = RunCompletionRecorder()
    let coordinator = ProviderLoginCoordinator(
        resolver: FixedLoginResolver(),
        runner: runner,
        refreshQuota: { _ in true },
        runFinished: { provider in await finished.record(provider) }
    )

    #expect(coordinator.connect(.claude))
    await runner.waitForStart(.claude)

    let stop = Task { await coordinator.stop() }
    await runner.waitForStopStart()

    #expect(!coordinator.connect(.claude))
    #expect(await runner.invocationCount(for: .claude) == 1)

    #expect(!coordinator.connect(.codex))
    #expect(await runner.invocationCount(for: .codex) == 0)

    await runner.releaseTerminationGrace()
    await stop.value
    await runner.waitForReapingWaiterCount(for: .claude, count: 2)

    coordinator.resumeAfterDeniedTermination()
    #expect(coordinator.connect(.codex))
    await runner.waitForStart(.codex)
    #expect(await runner.invocationCount(for: .codex) == 1)

    #expect(!coordinator.connect(.claude))
    #expect(await runner.invocationCount(for: .claude) == 1)

    await runner.completeNaturalExitAndReap(for: .claude)
    await finished.wait(for: .claude)

    #expect(coordinator.connect(.claude))
    await runner.waitForInvocation(of: .claude, count: 2)
    await runner.complete(.claude, with: .cancelled)
    await finished.wait(for: .claude, count: 2)
    await runner.complete(.codex, with: .cancelled)
    await finished.wait(for: .codex)
}

@MainActor
@Test func coordinatorNeverLetsDelayedStoppedCleanupClearANewerAdmission() async {
    let runner = StopAndReapLoginRunner()
    let finished = RunCompletionRecorder()
    let coordinator = ProviderLoginCoordinator(
        resolver: FixedLoginResolver(),
        runner: runner,
        refreshQuota: { _ in true },
        runFinished: { provider in await finished.record(provider) }
    )

    #expect(coordinator.connect(.claude))
    await runner.waitForStart(.claude)
    await runner.holdStopReturn()
    let stop = Task { await coordinator.stop() }
    await runner.waitForStopStart()
    await runner.releaseTerminationGrace()
    await runner.waitForReapingWaiterCount(for: .claude, count: 1)
    await runner.releaseStopReturn()
    await stop.value
    await runner.waitForReapingWaiterCount(for: .claude, count: 2)

    coordinator.resumeAfterDeniedTermination()

    await runner.completeOneReapingWaiter(for: .claude)
    await finished.wait(for: .claude)

    #expect(coordinator.connect(.claude))
    await runner.waitForInvocation(of: .claude, count: 2)

    await runner.completeRemainingReapingWaiters(for: .claude)
    try? await Task.sleep(for: .milliseconds(20))

    let secondReconnect = coordinator.connect(.claude)
    #expect(!secondReconnect)
    #expect(await runner.invocationCount(for: .claude) == 2)

    await runner.completeAll(.claude, with: .cancelled)
    await finished.wait(for: .claude, count: secondReconnect ? 3 : 2)
}

@MainActor
@Test func coordinatorClosesAllAdmissionsBeforeAwaitingStopAndKeepsCompleteTerminationClosed() async {
    let resolver = CountingLoginResolver()
    let runner = TerminationAdmissionRunner(results: [.complete])
    let states = LoginStateRecorder()
    let coordinator = ProviderLoginCoordinator(
        resolver: resolver,
        runner: runner,
        refreshQuota: { _ in true },
        stateObserver: { provider, state in await states.record(provider, state) }
    )

    #expect(coordinator.connect(.claude))
    await runner.waitForStart(.claude, count: 1)
    let firstStop = Task { await coordinator.stop() }
    await runner.waitForStopStart(count: 1)

    #expect(!coordinator.connect(.codex))
    #expect(resolver.commandCount() == 1)
    #expect(await runner.invocationCount(for: .codex) == 0)
    #expect(coordinator.state(for: .codex) == .idle)

    let concurrentStop = Task { await coordinator.stop() }
    await Task.yield()
    #expect(await runner.stopCallCount() == 1)
    await runner.releaseNextStop()

    #expect(await firstStop.value == .complete)
    #expect(await concurrentStop.value == .complete)
    #expect(!coordinator.connect(.codex))
    #expect(resolver.commandCount() == 1)
    #expect(await runner.invocationCount(for: .codex) == 0)
}

@MainActor
@Test func coordinatorReopensOnlyAfterDeniedTerminationAndRetainsPendingProviderAdmission() async {
    let resolver = CountingLoginResolver()
    let runner = TerminationAdmissionRunner(results: [.pendingReap, .complete], pendingReap: [.claude])
    let coordinator = ProviderLoginCoordinator(
        resolver: resolver,
        runner: runner,
        refreshQuota: { _ in true }
    )

    #expect(coordinator.connect(.claude))
    await runner.waitForStart(.claude, count: 1)
    let firstStop = Task { await coordinator.stop() }
    await runner.waitForStopStart(count: 1)

    #expect(!coordinator.connect(.codex))
    #expect(resolver.commandCount() == 1)
    await runner.releaseNextStop()
    #expect(await firstStop.value == .pendingReap)
    await runner.waitForReapingWaiter(for: .claude)

    #expect(!coordinator.connect(.codex))
    coordinator.resumeAfterDeniedTermination()
    #expect(!coordinator.connect(.claude))
    #expect(coordinator.connect(.codex))
    await runner.waitForStart(.codex, count: 1)
    #expect(resolver.commandCount() == 2)

    await runner.completeBackgroundReap(for: .claude)
    await Task.yield()

    let laterStop = Task { await coordinator.stop() }
    await runner.waitForStopStart(count: 2)
    #expect(!coordinator.connect(.codex))
    await runner.releaseNextStop()
    #expect(await laterStop.value == .complete)
    #expect(!coordinator.connect(.codex))
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

@Suite(.serialized)
private struct ProviderLoginProcessRunnerTests {
@Test func processRunnerPreventsALateLaunchWhenStoppedDuringPrelaunchRegistration() async throws {
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
    let task = Task.detached { await runner.run(fixture.command(readyFile: fixture.directory.appendingPathComponent("unused-ready"))) }

    await prelaunch.waitForEntry()
    await runner.stop()
    await prelaunch.release()

    #expect(await task.value == .cancelled)
    #expect(await starts.startedPIDs().isEmpty)
    #expect(await starts.signals().isEmpty)
}

@Test func processRunnerSendsOnlyTERMToACompliantExactFixturePIDAndReapsIt() async throws {
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
    let task = Task.detached { await runner.run(fixture.command(readyFile: readyFile, termFile: termFile)) }
    let pid = await recorder.waitForStart()
    try await waitForFixtureReady(at: readyFile)

    #expect(await runner.stop() == .complete)
    #expect(await task.value == .cancelled)
    let signals = await recorder.signals()
    #expect((try? String(contentsOf: termFile, encoding: .utf8)) == "T")
    #expect(signals == [.init(pid: pid, signal: SIGTERM)], "actual signals: \(signals)")
    #expect(Darwin.kill(pid, 0) == -1)
}

@Test func processRunnerStopsACompliantFixtureWithoutLifecycleObservers() async throws {
    let fixture = try SignalFixture.make()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    let runner = ProviderLoginProcessRunner(
        timeout: .seconds(30),
        terminationGrace: .seconds(1)
    )
    let readyFile = fixture.directory.appendingPathComponent("ready")
    let task = Task.detached { await runner.run(fixture.command(readyFile: readyFile)) }
    try await waitForFixtureReady(at: readyFile)

    await runner.stop()
    #expect(await task.value == .cancelled)
}

@Test func processRunnerEscalatesOnlyTheTermIgnoringExactFixturePIDThenReapsIt() async throws {
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
    let task = Task.detached { await runner.run(fixture.command(arguments: ["ignore-term"], readyFile: readyFile)) }
    let pid = await recorder.waitForStart()
    try await waitForFixtureReady(at: readyFile)
    #expect(Darwin.kill(pid, 0) == 0)

    let stop = Task.detached { await runner.stop() }
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

@Test func processRunnerSharesOneTerminationSequenceAcrossConcurrentCancellationAndStop() async throws {
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
    let task = Task.detached { await runner.run(fixture.command(arguments: ["ignore-term"], readyFile: readyFile)) }
    let pid = await recorder.waitForStart()
    try await waitForFixtureReady(at: readyFile)

    let stop = Task.detached { await runner.stop() }
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

@Test func processRunnerTaskCancellationTerminatesAndReapsADirectChild() async throws {
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
    let task = Task.detached { await runner.run(fixture.command(readyFile: readyFile)) }
    let pid = await recorder.waitForStart()
    try await waitForFixtureReady(at: readyFile)

    task.cancel()

    #expect(await task.value == .cancelled)
    let signals = await recorder.signals()
    #expect(signals == [.init(pid: pid, signal: SIGTERM)], "actual signals: \(signals)")
    #expect(await recorder.finishedPIDs() == [pid])
    #expect(Darwin.kill(pid, 0) == -1)
}

@Test func processRunnerTimeoutTerminatesAndReapsADirectChild() async throws {
    let fixture = try SignalFixture.make()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    let recorder = ProcessSignalRecorder()
    let runner = ProviderLoginProcessRunner(
        timeout: .seconds(2),
        terminationGrace: .milliseconds(100),
        signalObserved: { pid, signal in await recorder.send(pid, signal) },
        processStarted: { pid in await recorder.recordStart(pid) },
        processFinished: { pid in await recorder.recordFinish(pid) }
    )
    let readyFile = fixture.directory.appendingPathComponent("ready")
    let task = Task.detached { await runner.run(fixture.command(readyFile: readyFile)) }
    let pid = await recorder.waitForStart()
    try await waitForFixtureReady(at: readyFile)

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

@MainActor
@Test func coordinatorRetainsAdmissionAfterAGenericWaitFailureUntilTheBackgroundReaperConfirmsExit() async {
    let system = FailedWaitThenExitPOSIXSystem(pid: 72)
    let reaperPoll = SuspensionGate()
    let runner = ProviderLoginProcessRunner(
        timeout: .seconds(30),
        pollSleeper: { _ in await reaperPoll.wait() },
        system: system
    )
    let states = LoginStateRecorder()
    let coordinator = ProviderLoginCoordinator(
        resolver: FixedLoginResolver(),
        runner: runner,
        refreshQuota: { _ in true },
        stateObserver: { provider, state in await states.record(provider, state) }
    )

    #expect(coordinator.connect(.claude))
    await states.wait(for: .claude, state: .failed(.launchFailed))

    let retryBeforeReap = coordinator.connect(.claude)
    #expect(!retryBeforeReap)
    guard !retryBeforeReap else { return }
    await reaperPoll.waitForEntry()
    #expect(await system.spawnCount() == 1)
    #expect(await system.sentSignals().isEmpty)

    await reaperPoll.release()
    #expect(await eventually { coordinator.connect(.claude) })
    #expect(await eventually { await system.spawnCount() >= 2 })
    #expect(await system.spawnCount() == 2)
    #expect(await system.sentSignals().isEmpty)
    await states.wait(for: .claude, state: .failed(.providerRejected))
}

@Test func processRunnerReturnsBoundedSafeFailureAfterPersistentTERMFailureAndRetainsTheSoleReaper() async {
    let system = StagedPOSIXSystem(
        pid: 52,
        normalWaits: [.running],
        terminationWaits: Array(repeating: .interrupted, count: 4) + [.exited(status: 0)],
        signals: [.failed, .failed, .failed]
    )
    let normalPoll = SuspensionGate()
    let runner = ProviderLoginProcessRunner(
        timeout: .seconds(30),
        pollSleeper: { _ in await normalPoll.wait() },
        system: system
    )
    let task = Task.detached { await runner.run(scriptedCommand()) }

    await system.waitForNormalPoll()
    let firstStop = Task.detached { await runner.stop() }
    await system.waitForTERM()
    let secondStop = Task.detached { await runner.stop() }
    #expect(await firstStop.value == .pendingReap)
    #expect(await secondStop.value == .pendingReap)
    await normalPoll.release()

    let outcome = await task.value
    await runner.waitForReaping(for: .claude)
    #expect(await runner.stop() == .complete)
    #expect(outcome == .launchFailed, "actual outcome: \(outcome)")
    #expect(system.sentSignals.count == 3)
    #expect(system.sentSignals.allSatisfy { $0.pid == 52 && $0.signal == SIGTERM })
    #expect(system.normalWaitCount == 1)
    #expect(system.terminationWaitCount == 5)
}

@Test func processRunnerDoesNotSignalAReusedPIDAfterTheOriginalSessionCompletesDuringBeforeSignal() async {
    let system = PIDReusePOSIXSystem(waits: [.running, .exited(status: 0), .exited(status: 0)])
    let poll = SuspensionGate()
    let signalBarrier = SuspensionGate()
    let starts = SecondStartBarrier()
    let runner = ProviderLoginProcessRunner(
        timeout: .seconds(30),
        pollSleeper: { _ in await poll.wait() },
        system: system,
        beforeSignal: { _, _ in await signalBarrier.wait() },
        processStarted: { _ in await starts.recordAndHoldSecond() }
    )

    let first = Task.detached { await runner.run(scriptedCommand()) }
    await starts.waitForCount(1)
    await poll.waitForEntry()

    let stop = Task.detached { await runner.stop() }
    await signalBarrier.waitForEntry()
    await poll.release()
    #expect(await first.value == .cancelled)

    let second = Task.detached {
        await runner.run(ProviderLoginCommand(
            provider: .codex,
            executableURL: URL(fileURLWithPath: "/tmp/needlbar-pid-reuse"),
            arguments: [],
            environment: [:]
        ))
    }
    await starts.waitForCount(2)

    await signalBarrier.release()
    #expect(await stop.value == .complete)
    #expect(await system.sentSignals().isEmpty)

    await starts.releaseSecond()
    #expect(await second.value == .exited(status: 0))
}

@Test func processRunnerDoesNotWaitAgainAfterTerminationAlreadyReapedTheSession() async {
    let system = ScriptedPOSIXSystem(
        spawn: .spawned(pid: 83),
        waits: [.running, .exited(status: 0)],
        signals: [.sent]
    )
    let poll = SuspensionGate()
    let runner = ProviderLoginProcessRunner(
        timeout: .seconds(30),
        terminationGrace: .zero,
        pollSleeper: { _ in await poll.wait() },
        system: system
    )
    let task = Task.detached { await runner.run(scriptedCommand()) }

    await system.waitForSpawn()
    await poll.waitForEntry()
    task.cancel()
    await poll.release()

    #expect(await task.value == .cancelled)
    #expect(system.waitCount == 2)
    #expect(system.sentSignals.count == 1)
    #expect(system.sentSignals.first?.0 == 83)
    #expect(system.sentSignals.first?.1 == SIGTERM)
}

@Test func processRunnerBoundsPersistentKILLFailureAndLetsItsSoleReaperObserveNaturalExit() async {
    let system = StagedPOSIXSystem(
        pid: 53,
        normalWaits: [.running],
        terminationWaits: [.interrupted] + Array(repeating: .interrupted, count: 8) + [.exited(status: 0)],
        signals: [.sent, .failed, .failed, .failed]
    )
    let normalPoll = SuspensionGate()
    let runner = ProviderLoginProcessRunner(
        timeout: .seconds(30),
        terminationGrace: .zero,
        pollSleeper: { duration in if duration != .zero { await normalPoll.wait() } },
        system: system
    )
    let task = Task.detached { await runner.run(scriptedCommand()) }

    await system.waitForNormalPoll()
    let stop = Task.detached { await runner.stop() }
    await system.waitForTERM()
    #expect(await stop.value == .pendingReap)
    await normalPoll.release()

    let killOutcome = await task.value
    await runner.waitForReaping(for: .claude)
    #expect(await runner.stop() == .complete)
    #expect(killOutcome == .launchFailed, "actual outcome: \(killOutcome)")
    #expect(system.sentSignals == [.init(pid: 53, signal: SIGTERM), .init(pid: 53, signal: SIGKILL), .init(pid: 53, signal: SIGKILL), .init(pid: 53, signal: SIGKILL)])
    #expect(system.normalWaitCount == 1)
    #expect(system.terminationWaitCount == 10)
}

@Test func processRunnerTreatsECHILDAsAnInvariantFailureWithoutSignaling() async {
    let system = ScriptedPOSIXSystem(spawn: .spawned(pid: 61), waits: [.noChild], signals: [])
    let runner = ProviderLoginProcessRunner(timeout: .seconds(30), system: system)

    #expect(await runner.run(scriptedCommand()) == .launchFailed)
    #expect(system.sentSignals.isEmpty)
    #expect(system.waitCount == 1)
}

@Test func processRunnerConfirmsESRCHByReapingWithoutEscalating() async {
    let system = ScriptedPOSIXSystem(
        spawn: .spawned(pid: 62),
        waits: [.running, .exited(status: 0)],
        signals: [.noSuchProcess]
    )
    let sleeper = SuspensionGate()
    let runner = ProviderLoginProcessRunner(timeout: .seconds(30), pollSleeper: { _ in await sleeper.wait() }, system: system)
    let task = Task.detached { await runner.run(scriptedCommand()) }

    await system.waitForSpawn()
    await sleeper.waitForEntry()
    let stop = Task.detached { await runner.stop() }
    await system.waitForSignal()
    await sleeper.release()
    await stop.value

    #expect(await task.value == .cancelled)
    #expect(system.sentSignals.count == 1)
    #expect(system.sentSignals.first?.0 == 62)
    #expect(system.sentSignals.first?.1 == SIGTERM)
}

@Test func posixSpawnRejectsInteriorNULBeforeLaunching() {
    let system = ProviderLoginPOSIXSystem()
    let base = scriptedCommand()
    let argumentNUL = ProviderLoginCommand(provider: base.provider, executableURL: base.executableURL, arguments: ["bad\0argument"], environment: [:])
    let environmentNUL = ProviderLoginCommand(provider: base.provider, executableURL: base.executableURL, arguments: [], environment: ["SAFE": "bad\0value"])

    #expect(system.spawn(argumentNUL) == .failed)
    #expect(system.spawn(environmentNUL) == .failed)
}

@Test func spawnSpecificationPreservesTheDirectExecutableArgvEnvironmentAndFileActions() {
    let command = ProviderLoginCommand(
        provider: .claude,
        executableURL: URL(fileURLWithPath: "/opt/test/bin/claude"),
        arguments: ["auth", "login", "--claudeai"],
        environment: ["HOME": "/tmp/home", "PATH": "/opt/test/bin:/usr/bin"]
    )
    let specification = ProviderLoginSpawnSpecification(command)

    #expect(specification?.executablePath == "/opt/test/bin/claude")
    #expect(specification?.argv == ["/opt/test/bin/claude", "auth", "login", "--claudeai"])
    #expect(specification?.environment == ["HOME=/tmp/home", "PATH=/opt/test/bin:/usr/bin"])
    #expect(specification?.fileActions == [
        .openNullForRead(descriptor: STDIN_FILENO),
        .openNullForWrite(descriptor: STDOUT_FILENO),
        .openNullForWrite(descriptor: STDERR_FILENO),
    ])
    #expect(specification?.closeOnExecByDefault == true)
    #expect(specification?.clearsSignalMask == true)
}

@Test func processRunnerReapsAHarmlessDirectChildThatExitsNormally() async throws {
    let fixture = try SignalFixture.make()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let recorder = ProcessSignalRecorder()
    let runner = ProviderLoginProcessRunner(processStarted: { pid in await recorder.recordStart(pid) }, processFinished: { pid in await recorder.recordFinish(pid) })
    let task = Task.detached { await runner.run(fixture.command(arguments: ["exit"], readyFile: fixture.directory.appendingPathComponent("ready"))) }
    let pid = await recorder.waitForStart()

    #expect(await task.value == .exited(status: 0))
    #expect(await recorder.signals().isEmpty)
    #expect(await recorder.finishedPIDs() == [pid])
    #expect(Darwin.kill(pid, 0) == -1)
}

@Test func processRunnerSignalsOnlyTheDirectFixtureWhenItHasADescendant() async throws {
    let fixture = try SignalFixture.make()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let recorder = ProcessSignalRecorder()
    let ready = fixture.directory.appendingPathComponent("descendant-ready")
    let runner = ProviderLoginProcessRunner(terminationGrace: .milliseconds(100), signalObserved: { pid, signal in await recorder.send(pid, signal) }, processStarted: { pid in await recorder.recordStart(pid) })
    let task = Task.detached { await runner.run(fixture.command(arguments: ["descendant"], readyFile: ready)) }
    let directPID = await recorder.waitForStart()
    let pids = try await fixture.pids(at: ready)
    defer { _ = Darwin.kill(pids.child, SIGKILL) }

    await runner.stop()
    #expect(await task.value == .cancelled)
    #expect(await recorder.signals() == [.init(pid: directPID, signal: SIGTERM)])
    #expect(directPID == pids.parent)
    #expect(pids.child != directPID)
    #expect(Darwin.kill(pids.child, 0) == 0)
}
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

private final class CountingLoginResolver: ProviderLoginCommandResolving, @unchecked Sendable {
    private let lock = NSLock()
    private var commands = 0

    func command(for provider: ProviderID) throws -> ProviderLoginCommand {
        lock.lock()
        commands += 1
        lock.unlock()
        guard provider != .cursor else { throw ProviderLoginCommandResolutionError.unsupportedProvider }
        return ProviderLoginCommand(
            provider: provider,
            executableURL: URL(fileURLWithPath: "/tmp/needlbar-login-tests/bin/\(provider.rawValue)"),
            arguments: provider == .claude ? ["auth", "login", "--claudeai"] : ["login"],
            environment: [:]
        )
    }

    func commandCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return commands
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

    func stop() async -> ProviderLoginCleanupResult {
        for provider: ProviderID in [.claude, .codex] where continuations[provider] != nil {
            events.append(.term(provider))
            events.append(.kill(provider))
            continuations.removeValue(forKey: provider)?.resume(returning: .cancelled)
            events.append(.reaped(provider))
        }
        return .complete
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

    func stop() async -> ProviderLoginCleanupResult { .complete }
    func commands() -> [ProviderLoginCommand] { launched }
}

private actor DeferredReapingLoginRunner: ProviderLoginProcessRunning {
    private var invocations: [ProviderID: Int] = [:]
    private var invocationWaiters: [ProviderID: [(Int, CheckedContinuation<Void, Never>)]] = [:]
    private var activeReapingProviders: Set<ProviderID> = []
    private var providerReapingWaiters: [ProviderID: [CheckedContinuation<Void, Never>]] = [:]
    private var globalReapingWaiters: [CheckedContinuation<Void, Never>] = []
    private var reapingWaiterObservers: [(Int, CheckedContinuation<Void, Never>)] = []

    func run(_ command: ProviderLoginCommand) async -> ProviderLoginProcessOutcome {
        invocations[command.provider, default: 0] += 1
        let count = invocations[command.provider, default: 0]
        let waiters = invocationWaiters.removeValue(forKey: command.provider) ?? []
        for (expectedCount, continuation) in waiters where count >= expectedCount {
            continuation.resume()
        }
        if count == 1 {
            activeReapingProviders.insert(command.provider)
            return .launchFailed
        }
        return .exited(status: 1)
    }

    func stop() async -> ProviderLoginCleanupResult { .complete }

    func waitForReaping() async {
        observeReapingWaiter()
        await withCheckedContinuation { globalReapingWaiters.append($0) }
    }

    func waitForReaping(for provider: ProviderID) async {
        observeReapingWaiter()
        await withCheckedContinuation { providerReapingWaiters[provider, default: []].append($0) }
    }

    func waitForInvocation(of provider: ProviderID, count: Int) async {
        if invocations[provider, default: 0] >= count { return }
        await withCheckedContinuation { invocationWaiters[provider, default: []].append((count, $0)) }
    }

    func waitForReapingWaiterCount(_ count: Int) async {
        if reapingWaiterCount >= count { return }
        await withCheckedContinuation { reapingWaiterObservers.append((count, $0)) }
    }

    func completeNaturalExitAndReap(for provider: ProviderID) {
        activeReapingProviders.remove(provider)
        let waiters = providerReapingWaiters.removeValue(forKey: provider) ?? []
        waiters.forEach { $0.resume() }
        guard activeReapingProviders.isEmpty else { return }
        let globalWaiters = globalReapingWaiters
        globalReapingWaiters.removeAll()
        globalWaiters.forEach { $0.resume() }
    }

    func invocationCount(for provider: ProviderID) -> Int { invocations[provider, default: 0] }

    private var reapingWaiterCount: Int {
        globalReapingWaiters.count + providerReapingWaiters.values.reduce(0) { $0 + $1.count }
    }

    private func observeReapingWaiter() {
        let matching = reapingWaiterObservers.enumerated().filter { reapingWaiterCount + 1 >= $0.element.0 }
        for match in matching.reversed() {
            reapingWaiterObservers.remove(at: match.offset).1.resume()
        }
    }
}

private actor StopAndReapLoginRunner: ProviderLoginProcessRunning {
    private var invocations: [ProviderID: Int] = [:]
    private var invocationWaiters: [ProviderID: [(Int, CheckedContinuation<Void, Never>)]] = [:]
    private var active: [ProviderID: [CheckedContinuation<ProviderLoginProcessOutcome, Never>]] = [:]
    private var starts: Set<ProviderID> = []
    private var startWaiters: [ProviderID: [CheckedContinuation<Void, Never>]] = [:]
    private var stopStarted = false
    private var stopStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var terminationGraceWaiters: [CheckedContinuation<Void, Never>] = []
    private var terminationGraceReleased = false
    private var holdsStopReturn = false
    private var stopReturnWaiters: [CheckedContinuation<Void, Never>] = []
    private var stopReturnReleased = false
    private var reapedProviders: Set<ProviderID> = []
    private var reapingWaiters: [ProviderID: [CheckedContinuation<Void, Never>]] = [:]
    private var reapingWaiterObservers: [ProviderID: [(Int, CheckedContinuation<Void, Never>)]] = [:]

    func run(_ command: ProviderLoginCommand) async -> ProviderLoginProcessOutcome {
        let provider = command.provider
        invocations[provider, default: 0] += 1
        let count = invocations[provider, default: 0]
        resumeInvocationWaiters(for: provider, count: count)
        starts.insert(provider)
        let startWaiters = startWaiters.removeValue(forKey: provider) ?? []
        startWaiters.forEach { $0.resume() }
        return await withCheckedContinuation { active[provider, default: []].append($0) }
    }

    func stop() async -> ProviderLoginCleanupResult {
        stopStarted = true
        let waiters = stopStartWaiters
        stopStartWaiters.removeAll()
        waiters.forEach { $0.resume() }
        let stopping = active.values.flatMap { $0 }
        active.removeAll()
        if !terminationGraceReleased {
            await withCheckedContinuation { terminationGraceWaiters.append($0) }
        }
        stopping.forEach { $0.resume(returning: .launchFailed) }
        if holdsStopReturn && !stopReturnReleased {
            await withCheckedContinuation { stopReturnWaiters.append($0) }
        }
        return .pendingReap
    }

    func waitForReaping(for provider: ProviderID) async {
        if reapedProviders.contains(provider) { return }
        observeReapingWaiter(for: provider)
        await withCheckedContinuation { reapingWaiters[provider, default: []].append($0) }
    }

    func waitForStart(_ provider: ProviderID) async {
        if starts.contains(provider) { return }
        await withCheckedContinuation { startWaiters[provider, default: []].append($0) }
    }

    func waitForStopStart() async {
        if stopStarted { return }
        await withCheckedContinuation { stopStartWaiters.append($0) }
    }

    func releaseTerminationGrace() {
        terminationGraceReleased = true
        let waiters = terminationGraceWaiters
        terminationGraceWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func releaseStopReturn() {
        stopReturnReleased = true
        let waiters = stopReturnWaiters
        stopReturnWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func holdStopReturn() {
        holdsStopReturn = true
    }

    func waitForInvocation(of provider: ProviderID, count: Int) async {
        if invocations[provider, default: 0] >= count { return }
        await withCheckedContinuation { invocationWaiters[provider, default: []].append((count, $0)) }
    }

    func invocationCount(for provider: ProviderID) -> Int { invocations[provider, default: 0] }

    func waitForReapingWaiterCount(for provider: ProviderID, count: Int) async {
        if reapingWaiters[provider, default: []].count >= count { return }
        await withCheckedContinuation { reapingWaiterObservers[provider, default: []].append((count, $0)) }
    }

    func completeNaturalExitAndReap(for provider: ProviderID) {
        reapedProviders.insert(provider)
        let waiters = reapingWaiters.removeValue(forKey: provider) ?? []
        waiters.forEach { $0.resume() }
    }

    func completeOneReapingWaiter(for provider: ProviderID) {
        reapedProviders.insert(provider)
        guard !reapingWaiters[provider, default: []].isEmpty else { return }
        reapingWaiters[provider]?.removeFirst().resume()
    }

    func completeRemainingReapingWaiters(for provider: ProviderID) {
        reapedProviders.insert(provider)
        let waiters = reapingWaiters.removeValue(forKey: provider) ?? []
        waiters.forEach { $0.resume() }
    }

    func complete(_ provider: ProviderID, with outcome: ProviderLoginProcessOutcome) {
        active[provider]?.removeFirst().resume(returning: outcome)
        if active[provider]?.isEmpty == true { active[provider] = nil }
    }

    func completeAll(_ provider: ProviderID, with outcome: ProviderLoginProcessOutcome) {
        let continuations = active.removeValue(forKey: provider) ?? []
        continuations.forEach { $0.resume(returning: outcome) }
    }

    private func resumeInvocationWaiters(for provider: ProviderID, count: Int) {
        let matching = (invocationWaiters[provider] ?? []).enumerated().filter { count >= $0.element.0 }
        for match in matching.reversed() {
            invocationWaiters[provider]?.remove(at: match.offset).1.resume()
        }
    }

    private func observeReapingWaiter(for provider: ProviderID) {
        let currentCount = reapingWaiters[provider, default: []].count
        let matching = (reapingWaiterObservers[provider] ?? []).enumerated().filter { currentCount + 1 >= $0.element.0 }
        for match in matching.reversed() {
            reapingWaiterObservers[provider]?.remove(at: match.offset).1.resume()
        }
    }
}

private actor CountingLoginRunner: ProviderLoginProcessRunning {
    private var calls = 0

    func run(_ command: ProviderLoginCommand) async -> ProviderLoginProcessOutcome {
        calls += 1
        return .exited(status: 0)
    }

    func stop() async -> ProviderLoginCleanupResult { .complete }
    func invocationCount() -> Int { calls }
}

private actor CleanupResultLoginRunner: ProviderLoginProcessRunning {
    private var pendingReap: Set<ProviderID>
    private var active: [ProviderID: [CheckedContinuation<ProviderLoginProcessOutcome, Never>]] = [:]
    private var starts: [ProviderID: Int] = [:]
    private var startWaiters: [ProviderID: [(Int, CheckedContinuation<Void, Never>)]] = [:]
    private var reapingWaiters: [ProviderID: [CheckedContinuation<Void, Never>]] = [:]
    private var stopCalls = 0

    init(pendingReap: Set<ProviderID>) {
        self.pendingReap = pendingReap
    }

    func run(_ command: ProviderLoginCommand) async -> ProviderLoginProcessOutcome {
        let provider = command.provider
        starts[provider, default: 0] += 1
        let count = starts[provider, default: 0]
        let matching = (startWaiters[provider] ?? []).enumerated().filter { count >= $0.element.0 }
        for match in matching.reversed() {
            startWaiters[provider]?.remove(at: match.offset).1.resume()
        }
        return await withCheckedContinuation { continuation in
            active[provider, default: []].append(continuation)
        }
    }

    func stop() async -> ProviderLoginCleanupResult {
        stopCalls += 1
        let outcome: ProviderLoginProcessOutcome = pendingReap.isEmpty ? .cancelled : .launchFailed
        let continuations = active
        active.removeAll()
        for providerContinuations in continuations.values {
            providerContinuations.forEach { $0.resume(returning: outcome) }
        }
        return pendingReap.isEmpty ? .complete : .pendingReap
    }

    func waitForReaping(for provider: ProviderID) async {
        guard pendingReap.contains(provider) else { return }
        await withCheckedContinuation { reapingWaiters[provider, default: []].append($0) }
    }

    func waitForStart(_ provider: ProviderID, count: Int) async {
        if starts[provider, default: 0] >= count { return }
        await withCheckedContinuation { startWaiters[provider, default: []].append((count, $0)) }
    }

    func completeBackgroundReap(for provider: ProviderID) {
        pendingReap.remove(provider)
        let waiters = reapingWaiters.removeValue(forKey: provider) ?? []
        waiters.forEach { $0.resume() }
    }

    func stopCallCount() -> Int { stopCalls }
}

private actor TerminationAdmissionRunner: ProviderLoginProcessRunning {
    private var results: [ProviderLoginCleanupResult]
    private var pendingReap: Set<ProviderID>
    private var active: [ProviderID: [CheckedContinuation<ProviderLoginProcessOutcome, Never>]] = [:]
    private var starts: [ProviderID: Int] = [:]
    private var startWaiters: [ProviderID: [(Int, CheckedContinuation<Void, Never>)]] = [:]
    private var stopCalls = 0
    private var stopStartWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var stopReleaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var reapingWaiters: [ProviderID: [CheckedContinuation<Void, Never>]] = [:]
    private var reapingWaiterObservers: [ProviderID: [CheckedContinuation<Void, Never>]] = [:]

    init(results: [ProviderLoginCleanupResult], pendingReap: Set<ProviderID> = []) {
        self.results = results
        self.pendingReap = pendingReap
    }

    func run(_ command: ProviderLoginCommand) async -> ProviderLoginProcessOutcome {
        let provider = command.provider
        starts[provider, default: 0] += 1
        let count = starts[provider, default: 0]
        let matching = (startWaiters[provider] ?? []).enumerated().filter { count >= $0.element.0 }
        for match in matching.reversed() {
            startWaiters[provider]?.remove(at: match.offset).1.resume()
        }
        return await withCheckedContinuation { continuation in
            active[provider, default: []].append(continuation)
        }
    }

    func stop() async -> ProviderLoginCleanupResult {
        stopCalls += 1
        let count = stopCalls
        let matching = stopStartWaiters.enumerated().filter { count >= $0.element.0 }
        for match in matching.reversed() {
            stopStartWaiters.remove(at: match.offset).1.resume()
        }
        await withCheckedContinuation { stopReleaseWaiters.append($0) }
        let result = results.isEmpty ? .complete : results.removeFirst()
        let outcome: ProviderLoginProcessOutcome = result == .pendingReap ? .launchFailed : .cancelled
        let continuations = active
        active.removeAll()
        for providerContinuations in continuations.values {
            providerContinuations.forEach { $0.resume(returning: outcome) }
        }
        return result
    }

    func waitForReaping(for provider: ProviderID) async {
        guard pendingReap.contains(provider) else { return }
        let observers = reapingWaiterObservers.removeValue(forKey: provider) ?? []
        observers.forEach { $0.resume() }
        await withCheckedContinuation { reapingWaiters[provider, default: []].append($0) }
    }

    func waitForStart(_ provider: ProviderID, count: Int) async {
        if starts[provider, default: 0] >= count { return }
        await withCheckedContinuation { startWaiters[provider, default: []].append((count, $0)) }
    }

    func waitForStopStart(count: Int) async {
        if stopCalls >= count { return }
        await withCheckedContinuation { stopStartWaiters.append((count, $0)) }
    }

    func releaseNextStop() {
        guard !stopReleaseWaiters.isEmpty else { return }
        stopReleaseWaiters.removeFirst().resume()
    }

    func waitForReapingWaiter(for provider: ProviderID) async {
        if !reapingWaiters[provider, default: []].isEmpty { return }
        await withCheckedContinuation { reapingWaiterObservers[provider, default: []].append($0) }
    }

    func completeBackgroundReap(for provider: ProviderID) {
        pendingReap.remove(provider)
        let waiters = reapingWaiters.removeValue(forKey: provider) ?? []
        waiters.forEach { $0.resume() }
    }

    func invocationCount(for provider: ProviderID) -> Int { starts[provider, default: 0] }
    func stopCallCount() -> Int { stopCalls }
}

private actor RunCompletionRecorder {
    private var completions: [ProviderID: Int] = [:]
    private var waiters: [ProviderID: [(Int, CheckedContinuation<Void, Never>)]] = [:]

    func record(_ provider: ProviderID) {
        completions[provider, default: 0] += 1
        let count = completions[provider, default: 0]
        let matching = (waiters[provider] ?? []).enumerated().filter { count >= $0.element.0 }
        for match in matching.reversed() {
            waiters[provider]?.remove(at: match.offset).1.resume()
        }
    }

    func wait(for provider: ProviderID, count: Int = 1) async {
        if completions[provider, default: 0] >= count { return }
        await withCheckedContinuation { continuation in waiters[provider, default: []].append((count, continuation)) }
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

private actor SecondStartBarrier {
    private var starts = 0
    private var countWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var secondReleased = false
    private var secondWaiters: [CheckedContinuation<Void, Never>] = []

    func recordAndHoldSecond() async {
        starts += 1
        let matching = countWaiters.enumerated().filter { starts >= $0.element.0 }
        for match in matching.reversed() {
            countWaiters.remove(at: match.offset).1.resume()
        }
        guard starts == 2, !secondReleased else { return }
        await withCheckedContinuation { secondWaiters.append($0) }
    }

    func waitForCount(_ count: Int) async {
        if starts >= count { return }
        await withCheckedContinuation { countWaiters.append((count, $0)) }
    }

    func releaseSecond() {
        secondReleased = true
        let waiters = secondWaiters
        secondWaiters.removeAll()
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
    private var spawnWaiters: [CheckedContinuation<Void, Never>] = []
    private var signalWaiters: [CheckedContinuation<Void, Never>] = []

    init(spawn: ProviderLoginSpawnResult, waits: [ProviderLoginWaitResult], signals: [ProviderLoginSignalResult]) {
        self.spawnResult = spawn
        self.waits = waits
        self.signalResults = signals
    }

    func spawn(_ command: ProviderLoginCommand) -> ProviderLoginSpawnResult {
        lock.lock(); defer { lock.unlock() }
        spawnCount += 1
        let waiters = spawnWaiters
        spawnWaiters.removeAll()
        waiters.forEach { $0.resume() }
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
        let waiters = signalWaiters
        signalWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return signalResults.isEmpty ? .sent : signalResults.removeFirst()
    }

    func waitForSpawn() async {
        if hasSpawned() { return }
        await withCheckedContinuation { continuation in
            lock.lock()
            if spawnCount > 0 {
                lock.unlock()
                continuation.resume()
                return
            }
            spawnWaiters.append(continuation)
            lock.unlock()
        }
    }

    private func hasSpawned() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return spawnCount > 0
    }

    func waitForSignal() async {
        if hasSignal() { return }
        await withCheckedContinuation { continuation in
            lock.lock()
            if !sentSignals.isEmpty {
                lock.unlock()
                continuation.resume()
                return
            }
            signalWaiters.append(continuation)
            lock.unlock()
        }
    }

    private func hasSignal() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return !sentSignals.isEmpty
    }
}

private final class PIDReusePOSIXSystem: ProviderLoginProcessSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var waits: [ProviderLoginWaitResult]
    private var signals: [(Int32, Int32)] = []

    init(waits: [ProviderLoginWaitResult]) {
        self.waits = waits
    }

    func spawn(_ command: ProviderLoginCommand) -> ProviderLoginSpawnResult {
        .spawned(pid: 82)
    }

    func waitForChild(_ pid: Int32) -> ProviderLoginWaitResult {
        lock.lock(); defer { lock.unlock() }
        return waits.isEmpty ? .running : waits.removeFirst()
    }

    func sendSignal(_ signal: Int32, to pid: Int32) -> ProviderLoginSignalResult {
        lock.lock(); defer { lock.unlock() }
        signals.append((pid, signal))
        return .sent
    }

    func sentSignals() -> [(Int32, Int32)] {
        lock.lock(); defer { lock.unlock() }
        return signals
    }
}

private final class StagedPOSIXSystem: ProviderLoginProcessSystem, @unchecked Sendable {
    struct Signal: Equatable { let pid: Int32; let signal: Int32 }
    private let lock = NSLock()
    private let pid: Int32
    private var normalWaits: [ProviderLoginWaitResult]
    private var terminationWaits: [ProviderLoginWaitResult]
    private var signalResults: [ProviderLoginSignalResult]
    private var terminating = false
    private var normalPollWaiters: [CheckedContinuation<Void, Never>] = []
    private var termWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var sentSignals: [Signal] = []
    private(set) var normalWaitCount = 0
    private(set) var terminationWaitCount = 0

    init(pid: Int32, normalWaits: [ProviderLoginWaitResult], terminationWaits: [ProviderLoginWaitResult], signals: [ProviderLoginSignalResult]) {
        self.pid = pid
        self.normalWaits = normalWaits
        self.terminationWaits = terminationWaits
        self.signalResults = signals
    }

    func spawn(_ command: ProviderLoginCommand) -> ProviderLoginSpawnResult { .spawned(pid: pid) }

    func waitForChild(_ pid: Int32) -> ProviderLoginWaitResult {
        lock.lock(); defer { lock.unlock() }
        if terminating {
            terminationWaitCount += 1
            return terminationWaits.isEmpty ? .running : terminationWaits.removeFirst()
        }
        normalWaitCount += 1
        let waiters = normalPollWaiters
        normalPollWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return normalWaits.isEmpty ? .running : normalWaits.removeFirst()
    }

    func sendSignal(_ signal: Int32, to pid: Int32) -> ProviderLoginSignalResult {
        lock.lock(); defer { lock.unlock() }
        sentSignals.append(.init(pid: pid, signal: signal))
        if signal == SIGTERM {
            terminating = true
            let waiters = termWaiters
            termWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
        return signalResults.isEmpty ? .sent : signalResults.removeFirst()
    }

    func waitForNormalPoll() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if normalWaitCount > 0 { lock.unlock(); continuation.resume(); return }
            normalPollWaiters.append(continuation)
            lock.unlock()
        }
    }

    func waitForTERM() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if terminating { lock.unlock(); continuation.resume(); return }
            termWaiters.append(continuation)
            lock.unlock()
        }
    }
}

private final class FailedWaitThenExitPOSIXSystem: ProviderLoginProcessSystem, @unchecked Sendable {
    private let lock = NSLock()
    private let pid: Int32
    private var spawnInvocations = 0
    private var waitInvocations = 0
    private var signals: [(Int32, Int32)] = []

    init(pid: Int32) {
        self.pid = pid
    }

    func spawn(_ command: ProviderLoginCommand) -> ProviderLoginSpawnResult {
        lock.lock(); defer { lock.unlock() }
        spawnInvocations += 1
        return .spawned(pid: pid)
    }

    func waitForChild(_ pid: Int32) -> ProviderLoginWaitResult {
        lock.lock(); defer { lock.unlock() }
        if spawnInvocations > 1 { return .exited(status: 1) }
        waitInvocations += 1
        switch waitInvocations {
        case 1, 2: return .failed
        case 3: return .running
        default: return .exited(status: 1)
        }
    }

    func sendSignal(_ signal: Int32, to pid: Int32) -> ProviderLoginSignalResult {
        lock.lock(); defer { lock.unlock() }
        signals.append((pid, signal))
        return .sent
    }

    func spawnCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return spawnInvocations
    }

    func sentSignals() -> [(Int32, Int32)] {
        lock.lock(); defer { lock.unlock() }
        return signals
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

@MainActor
private func eventually(_ condition: @escaping @MainActor () async -> Bool) async -> Bool {
    for _ in 0..<100 {
        if await condition() { return true }
        await Task.yield()
    }
    return false
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
        #include <stdio.h>
        #include <stdlib.h>
        #include <unistd.h>
        static int term_fd = -1;
        static void exit_on_term(int ignored) { if (term_fd >= 0) write(term_fd, "T", 1); _exit(0); }
        int main(int argc, char **argv) {
            int descendant_mode = argc == 2 && argv[1][0] == 'd';
            int exit_mode = argc == 2 && argv[1][0] == 'e';
            signal(SIGTERM, exit_on_term);
            if (argc == 2 && argv[1][0] == 'i') signal(SIGTERM, SIG_IGN);
            pid_t descendant = 0;
            if (descendant_mode) {
                descendant = fork();
                if (descendant == 0) { signal(SIGTERM, SIG_IGN); for (;;) sleep(1); }
            }
            const char *term = getenv("NEEDLBAR_FIXTURE_TERM");
            if (term) term_fd = open(term, O_WRONLY | O_CREAT, 0600);
            const char *ready = getenv("NEEDLBAR_FIXTURE_READY");
            if (ready) {
                int fd = open(ready, O_WRONLY | O_CREAT, 0600);
                if (fd >= 0) { if (descendant_mode) dprintf(fd, "%d %d", (int)getpid(), (int)descendant); else write(fd, "1", 1); close(fd); }
            }
            if (exit_mode) return 0;
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

    func pids(at url: URL) async throws -> (parent: Int32, child: Int32) {
        try await waitForFixtureReady(at: url)
        let parts = try String(contentsOf: url, encoding: .utf8).split(separator: " ").map { Int32($0) }
        guard parts.count == 2, let parent = parts[0], let child = parts[1] else { throw SignalFixtureError.readyTimedOut }
        return (parent, child)
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
