import Foundation
import Testing
@testable import NeedlbarCore
import NeedlbarWidgetSupport

// Increment 1 of docs/superpowers/specs/2026-10-22-claude-credential-renewal-design.md,
// acceptance criteria 1, 2, 3, 5 and 6 (core side). Every input is synthetic:
// fake quota repositories, fake diagnostics reads, a manual clock and canary
// payloads. Nothing here touches credentials, the Keychain, the network or the
// claude CLI.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ClaudeAccessExpiredReasonTests {
    static let start = Date(timeIntervalSince1970: 1_792_400_000) // a whole second

    // MARK: - §5.1 Mapping table

    @Test func onlyLocalExpiryOriginsWithAuthenticationExpiredProduceTheNewReason() async throws {
        let codes = ["authenticationExpired", "requiresAuthentication", "permissionDenied", "networkUnavailable", "unknown-code"]
        let codeMapping: [String: ClaudeQuotaFailureReason] = [
            "authenticationExpired": .quotaAccessUnavailable,
            "requiresAuthentication": .quotaAccessUnavailable,
            "permissionDenied": .credentialAccessUnavailable,
            "networkUnavailable": .connectionUnavailable,
            "unknown-code": .couldNotUpdateQuota,
        ]
        let newReasonPairs: Set<String> = [
            "authenticationExpired|keychainCredentialExpired",
            "authenticationExpired|fileCredentialExpired",
        ]
        // Seven closed origins, a missing origin, and an undecodable origin.
        let origins: [String?] = ClaudeQuotaFailureOrigin.allCasesForTest.map(\.rawValue) + [nil, "futureOrigin"]

        var newReasonCount = 0
        for code in codes {
            for origin in origins {
                let harness = Harness(results: [.result(claudeError(code))])
                harness.diagnostics.script { now in diagnosticsRead(origin: origin, lastAttemptAt: now) }
                await harness.coordinator.popoverOpened()
                await harness.waitUntilCompleted(1)
                let reason = await harness.store.snapshot(for: .claude).claudeQuotaFailureReason
                let key = "\(code)|\(origin ?? "nil")"
                let expected: ClaudeQuotaFailureReason = newReasonPairs.contains(key)
                    ? .claudeCodeAccessExpired
                    : try #require(codeMapping[code])
                #expect(reason == expected, "code \(code) with origin \(origin ?? "nil") stored \(String(describing: reason))")
                if reason == .claudeCodeAccessExpired { newReasonCount += 1 }
                await harness.coordinator.stop()
            }
        }
        #expect(newReasonCount == 2)
    }

    @Test func failedDiagnosticsReadFallsBackToTheCodeMapping() async throws {
        let harness = Harness(results: [.result(claudeError("authenticationExpired"))])
        harness.diagnostics.script { _ in .failure(BridgeFailure.nullPointer) }
        await harness.coordinator.popoverOpened()
        await harness.waitUntilCompleted(1)
        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == .quotaAccessUnavailable)
    }

    @Test func wholeCallBridgeFailureUsesTheSameOriginAwareMapping() async throws {
        let harness = Harness(results: [.failure(BridgeFailure.bridgeFailed([
            .init(provider: "claude", code: "authenticationExpired", message: canaryMessage, action: nil),
        ]))])
        harness.diagnostics.script { now in diagnosticsRead(origin: "fileCredentialExpired", lastAttemptAt: now) }
        await harness.coordinator.popoverOpened()
        await harness.waitUntilCompleted(1)
        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == .claudeCodeAccessExpired)
    }

    @Test func mappingFunctionMatchesTheTableDirectly() {
        for origin in ClaudeQuotaFailureOrigin.allCasesForTest + [nil] {
            let local = origin == .keychainCredentialExpired || origin == .fileCredentialExpired
            #expect(ClaudeQuotaFailureReason(errorCode: "authenticationExpired", associatedOrigin: origin)
                == (local ? .claudeCodeAccessExpired : .quotaAccessUnavailable))
            #expect(ClaudeQuotaFailureReason(errorCode: "requiresAuthentication", associatedOrigin: origin) == .quotaAccessUnavailable)
            #expect(ClaudeQuotaFailureReason(errorCode: "permissionDenied", associatedOrigin: origin) == .credentialAccessUnavailable)
            #expect(ClaudeQuotaFailureReason(errorCode: "networkUnavailable", associatedOrigin: origin) == .connectionUnavailable)
            #expect(ClaudeQuotaFailureReason(errorCode: "rateLimited", associatedOrigin: origin) == .temporarilyLimited)
            #expect(ClaudeQuotaFailureReason(errorCode: "unknown-code", associatedOrigin: origin) == .couldNotUpdateQuota)
        }
    }

    // MARK: - §5.2 Association

    @Test func originFromAnAttemptBeforeTheCurrentStartIsRejected() async throws {
        let attemptStart = Self.start.addingTimeInterval(0.5)
        let harness = Harness(results: [.result(claudeError("authenticationExpired"))], now: attemptStart)
        harness.diagnostics.script { _ in
            diagnosticsRead(origin: "keychainCredentialExpired", lastAttemptAt: Self.start.addingTimeInterval(-1))
        }
        await harness.coordinator.popoverOpened()
        await harness.waitUntilCompleted(1)
        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == .quotaAccessUnavailable)
    }

    @Test func wholeSecondRecordOfTheSameAttemptIsAcceptedAfterTruncatingTheStart() async throws {
        // The bridge writes lastAttemptAt in whole seconds, so a record taken
        // 0.9 s into the same second must still match its attempt.
        let attemptStart = Self.start.addingTimeInterval(0.9)
        let harness = Harness(results: [.result(claudeError("authenticationExpired"))], now: attemptStart)
        harness.diagnostics.script { _ in
            diagnosticsRead(origin: "keychainCredentialExpired", lastAttemptAt: Self.start)
        }
        await harness.coordinator.popoverOpened()
        await harness.waitUntilCompleted(1)
        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == .claudeCodeAccessExpired)
    }

    @Test func associationGuardsRejectEachMismatch() throws {
        let record = diagnosticsRead(origin: "keychainCredentialExpired", lastAttemptAt: Self.start)
        let accepted = ClaudeQuotaFailureOriginAssociation.origin(
            in: record, attemptStartedAt: Self.start.addingTimeInterval(0.4),
            attemptGeneration: 3, currentGeneration: 3, claudeResultFailed: true)
        #expect(accepted == .keychainCredentialExpired)

        let cases: [(String, ClaudeQuotaFailureOrigin?)] = [
            ("predates start", ClaudeQuotaFailureOriginAssociation.origin(
                in: record, attemptStartedAt: Self.start.addingTimeInterval(1),
                attemptGeneration: 3, currentGeneration: 3, claudeResultFailed: true)),
            ("old generation", ClaudeQuotaFailureOriginAssociation.origin(
                in: record, attemptStartedAt: Self.start,
                attemptGeneration: 2, currentGeneration: 3, claudeResultFailed: true)),
            ("claude succeeded", ClaudeQuotaFailureOriginAssociation.origin(
                in: record, attemptStartedAt: Self.start,
                attemptGeneration: 3, currentGeneration: 3, claudeResultFailed: false)),
            ("no read", ClaudeQuotaFailureOriginAssociation.origin(
                in: nil, attemptStartedAt: Self.start,
                attemptGeneration: 3, currentGeneration: 3, claudeResultFailed: true)),
            ("failed read", ClaudeQuotaFailureOriginAssociation.origin(
                in: .failure(BridgeFailure.nullPointer), attemptStartedAt: Self.start,
                attemptGeneration: 3, currentGeneration: 3, claudeResultFailed: true)),
            ("no attempt time", ClaudeQuotaFailureOriginAssociation.origin(
                in: diagnosticsRead(origin: "keychainCredentialExpired", lastAttemptAt: nil),
                attemptStartedAt: Self.start, attemptGeneration: 3, currentGeneration: 3, claudeResultFailed: true)),
            ("record available", ClaudeQuotaFailureOriginAssociation.origin(
                in: diagnosticsRead(origin: "keychainCredentialExpired", lastAttemptAt: Self.start, quotaStatus: "available"),
                attemptStartedAt: Self.start, attemptGeneration: 3, currentGeneration: 3, claudeResultFailed: true)),
        ]
        for (name, origin) in cases {
            #expect(origin == nil, "\(name) must not associate an origin")
        }
    }

    @Test func succeededClaudeResultIgnoresAnExpiredOriginInTheRecord() async throws {
        let harness = Harness(results: [.result(.init(snapshots: [.claude: try claudeQuota()], errors: [:]))])
        harness.diagnostics.script { now in diagnosticsRead(origin: "keychainCredentialExpired", lastAttemptAt: now) }
        await harness.coordinator.popoverOpened()
        await harness.waitUntilCompleted(1)
        let snapshot = await harness.store.snapshot(for: .claude)
        #expect(snapshot.claudeQuotaFailureReason == nil)
        #expect(snapshot.quota != nil)
    }

    @Test func diagnosticsAreReadExactlyOncePerCompletedClaudeOperationAndSharedWithTheReporter() async throws {
        let harness = Harness(results: [
            .result(claudeError("authenticationExpired")),
            .result(claudeError("authenticationExpired")),
            .result(claudeError("authenticationExpired")),
            .result(.init(snapshots: [:], errors: [.codex: .init(provider: "codex", code: "networkUnavailable", message: canaryMessage, action: nil)])),
        ])
        harness.diagnostics.script { now in diagnosticsRead(origin: "keychainCredentialExpired", lastAttemptAt: now) }
        await harness.coordinator.start()
        await harness.waitUntilCompleted(1)
        #expect(await harness.coordinator.refreshQuota(afterUserAuthenticationFor: .claude) == false)
        await harness.waitUntilCompleted(2)
        #expect(await harness.coordinator.preflightClaudeLogin() == .requiresAuthentication)
        await harness.waitUntilCompleted(3)
        #expect(await harness.coordinator.refreshQuota(afterUserAuthenticationFor: .codex) == false)
        await pollUntil { await harness.store.snapshot(for: .codex).quotaStatus != .unavailable }

        #expect(harness.quota.intents == [.backgroundAll, .userInitiated(provider: .claude), .claudePreflight, .userInitiated(provider: .codex)])
        #expect(harness.quota.callCount == 4)
        #expect(harness.diagnostics.readCount == 3)
        // The reporter receives exactly the values that were read, in order.
        #expect(harness.diagnostics.reportedGeneratedAt == harness.diagnostics.readGeneratedAt)
        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == .claudeCodeAccessExpired)
        await harness.coordinator.stop()
    }

    @Test func stopDuringTheReadDropsTheOldResultAndRestartDoesNotReuseItsOrigin() async throws {
        let harness = Harness(results: [
            .result(claudeError("authenticationExpired")),
            .result(claudeError("authenticationExpired")),
        ])
        let oldAttemptAt = Self.start
        // Both reads return the old attempt's record: the bridge was not
        // reached again, or its record is from before this generation.
        harness.diagnostics.script { _ in diagnosticsRead(origin: "keychainCredentialExpired", lastAttemptAt: oldAttemptAt) }
        harness.diagnostics.holdFirstRead()
        await harness.coordinator.start()
        await harness.waitUntil { harness.diagnostics.readCount >= 1 || harness.completions.value >= 1 }
        await harness.coordinator.stop()
        let completedBeforeRestart = harness.completions.value
        harness.clock.setNowWithoutWakingSleepers(Self.start.addingTimeInterval(10))
        await harness.coordinator.start()
        harness.diagnostics.releaseHeldRead()
        await pollUntil { await harness.store.snapshot(for: .claude).updatedAt == Self.start.addingTimeInterval(10) }
        await harness.waitUntilCompleted(completedBeforeRestart + 1)

        // The held read belonged to the stopped generation: it is not applied,
        // completed or reported.
        #expect(completedBeforeRestart == 0)
        #expect(harness.diagnostics.readCount == 2)
        #expect(harness.diagnostics.reportCount == 1)
        #expect(harness.quota.callCount == 2)
        let snapshot = await harness.store.snapshot(for: .claude)
        #expect(snapshot.claudeQuotaFailureReason == .quotaAccessUnavailable)
        await harness.coordinator.stop()
    }

    // MARK: - §5.3 Transitions

    @Test func expiredExpiredThenSuccessClearsTheReasonOnTheScheduledCadence() async throws {
        let harness = Harness(results: [
            .result(claudeError("authenticationExpired")),
            .result(claudeError("authenticationExpired")),
            .result(.init(snapshots: [.claude: try claudeQuota()], errors: [:])),
        ])
        let diagnostics = harness.diagnostics
        diagnostics.script { now in
            diagnostics.readCount < 2
                ? diagnosticsRead(origin: "keychainCredentialExpired", lastAttemptAt: now)
                : diagnosticsRead(origin: nil, lastAttemptAt: now, quotaStatus: "available")
        }
        await harness.coordinator.start()
        await harness.waitUntilCompleted(1)
        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == .claudeCodeAccessExpired)

        await harness.clock.waitUntilSleeperCount(2)
        harness.clock.advance(by: 300)
        await harness.waitUntilCompleted(2)
        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == .claudeCodeAccessExpired)

        await harness.clock.waitUntilSleeperCount(2)
        harness.clock.advance(by: 300)
        await harness.waitUntilCompleted(3)
        let recovered = await harness.store.snapshot(for: .claude)
        #expect(recovered.claudeQuotaFailureReason == nil)
        #expect(recovered.quotaLastSuccessfulAt == Self.start.addingTimeInterval(600))
        #expect(harness.quota.intents == [.backgroundAll, .backgroundAll, .backgroundAll])
        await harness.coordinator.stop()
    }

    @Test func expiredThenUsageEndpointRejectionReturnsToTheGenericReason() async throws {
        let harness = Harness(results: [
            .result(claudeError("authenticationExpired")),
            .result(claudeError("authenticationExpired")),
        ])
        let diagnostics = harness.diagnostics
        diagnostics.script { now in
            diagnosticsRead(origin: diagnostics.readCount < 1 ? "keychainCredentialExpired" : "usageEndpointUnauthorized",
                            lastAttemptAt: now)
        }
        await harness.coordinator.popoverOpened()
        await harness.waitUntilCompleted(1)
        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == .claudeCodeAccessExpired)
        harness.clock.setNowWithoutWakingSleepers(Self.start.addingTimeInterval(120))
        await harness.coordinator.popoverOpened()
        await harness.waitUntilCompleted(2)
        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == .quotaAccessUnavailable)
    }

    // MARK: - §5.5 Export and widget stay byte-identical; §5.6 privacy

    @Test func exportWidgetAndAlertSamplesMatchThePreChangeOutput() async throws {
        let t0 = try #require(BridgeDecoder.date("2026-10-22T09:00:00Z"))
        let t1 = t0.addingTimeInterval(600)
        let exportedAt = t1.addingTimeInterval(60)

        // The same scripted failure, once with a local-expiry origin (new
        // reason) and once with no usable origin (the pre-change reason).
        var outputs: [(reason: ClaudeQuotaFailureReason?, export: Data, widget: Data, alerts: [QuotaAlertSample])] = []
        for origin in ["keychainCredentialExpired", nil] as [String?] {
            let harness = Harness(results: [.result(claudeError("authenticationExpired"))], now: t1)
            await harness.store.applyQuota(try claudeQuota(resetBase: t0), for: .claude, at: t0)
            await harness.store.applyQuota(QuotaSnapshot(windows: [
                try QuotaWindow(id: "codex.primary", title: "Primary", usedPercent: 25, resetsAt: t0.addingTimeInterval(3_600)),
            ]), for: .codex, at: t0)
            harness.diagnostics.script { now in diagnosticsRead(origin: origin, lastAttemptAt: now) }
            await harness.coordinator.popoverOpened()
            await harness.waitUntilCompleted(1)
            outputs.append((
                await harness.store.snapshot(for: .claude).claudeQuotaFailureReason,
                try SnapshotExporter().encode(await harness.store.captureForExport(exportedAt: exportedAt)),
                try WidgetProjection.encode(
                    try WidgetProjectionMapper(now: exportedAt).map(await harness.store.captureForWidget(exportedAt: exportedAt))),
                await harness.store.quotaAlertCapture()
            ))
        }

        #expect(outputs[0].reason == .claudeCodeAccessExpired)
        #expect(outputs[1].reason == .quotaAccessUnavailable)
        for output in outputs {
            #expect(output.export == Data(preChangeExportFixture.utf8))
            #expect(output.widget == Data(preChangeWidgetFixture.utf8))
            let text = String(decoding: output.export + output.widget, as: UTF8.self)
            for marker in canaryMarkers + ["claudeCodeAccessExpired", "Claude Code access on this Mac expired", "renew"] {
                #expect(!text.contains(marker), "\(marker) leaked into an export or widget payload")
            }
        }
        // Notifications evaluate only these samples.
        #expect(outputs[0].alerts == outputs[1].alerts)
    }

    @Test func canaryPayloadsNeverReachTheStoreOrTheReasonText() async throws {
        let harness = Harness(results: [.result(claudeError("authenticationExpired"))])
        harness.diagnostics.script { now in diagnosticsRead(origin: "keychainCredentialExpired", lastAttemptAt: now) }
        await harness.coordinator.popoverOpened()
        await harness.waitUntilCompleted(1)
        let snapshot = await harness.store.snapshot(for: .claude)
        #expect(snapshot.claudeQuotaFailureReason == .claudeCodeAccessExpired)
        let rendered = [
            String(describing: snapshot),
            String(reflecting: snapshot.claudeQuotaFailureReason),
            snapshot.claudeQuotaFailureReason?.displayText ?? "",
            snapshot.claudeQuotaFailureReason?.detailText ?? "",
        ].joined(separator: "\n")
        for marker in canaryMarkers {
            #expect(!rendered.contains(marker), "\(marker) leaked into the store or reason text")
        }
    }

    // MARK: - §5.7 Copy and localization

    @Test func copyIsTheApprovedTextFromLocalizableKeys() throws {
        #expect(ClaudeQuotaFailureReason.claudeCodeAccessExpired.displayText == "Claude Code access on this Mac expired")
        #expect(ClaudeQuotaFailureReason.claudeCodeAccessExpired.detailText
            == "Needlbar reads the access the Claude Code command-line tool saves on this Mac. The Claude desktop app does not renew it, so it updates after Claude Code runs in Terminal.")
        for reason in [ClaudeQuotaFailureReason.quotaAccessUnavailable, .credentialAccessUnavailable,
                       .connectionUnavailable, .temporarilyLimited, .couldNotUpdateQuota] {
            #expect(reason.detailText == nil)
        }

        // A strings table keyed by the new keys replaces both texts.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("needlbar-access-expired-\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let table = """
        "claudeQuota.reason.claudeCodeAccessExpired" = "SHORT-TRANSLATED";
        "claudeQuota.reason.claudeCodeAccessExpired.detail" = "DETAIL-TRANSLATED";
        """
        try Data(table.utf8).write(to: directory.appendingPathComponent("Localizable.strings"))
        let bundle = try #require(Bundle(url: directory))
        #expect(ClaudeQuotaFailureReason.claudeCodeAccessExpired.localizedDisplayText(bundle: bundle) == "SHORT-TRANSLATED")
        #expect(ClaudeQuotaFailureReason.claudeCodeAccessExpired.localizedDetailText(bundle: bundle) == "DETAIL-TRANSLATED")
        #expect(ClaudeQuotaFailureReason.quotaAccessUnavailable.localizedDetailText(bundle: bundle) == nil)

        for text in [ClaudeQuotaFailureReason.claudeCodeAccessExpired.displayText,
                     ClaudeQuotaFailureReason.claudeCodeAccessExpired.detailText ?? ""] {
            for forbidden in forbiddenCopy {
                #expect(!text.localizedCaseInsensitiveContains(forbidden), "copy must not contain \(forbidden)")
            }
        }
    }
}

// MARK: - Fixtures

private let canaryMessage = "RAW_ERROR_TOKEN_PATH_CANARY"
private let canaryMarkers = [canaryMessage, "CLAUDE-CANARY-SECRET", "/private/canary", "sk-ant-canary"]
// Terminal appears in the approved detail only as a fact; instructions stay forbidden.
private let forbiddenCopy = ["Sign in", "Log in", "Login", "Open Terminal", "run claude", "run ", "prompt"]

private let preChangeExportFixture = """
{"exportedAt":"2026-10-22T09:11:00.000Z","providers":[{"provider":"claude","quota":{"data":{"windows":[{"id":"claude.session","resetsAt":"2026-10-22T11:00:00.000Z","usedPercent":30},{"id":"claude.weekly","resetsAt":"2026-10-23T09:00:00.000Z","usedPercent":40}]},"status":{"errorCode":"refreshFailed","lastSuccessfulAt":"2026-10-22T09:00:00.000Z","state":"error"}},"updatedAt":"2026-10-22T09:10:00.000Z","usage":{"data":null,"status":{"errorCode":null,"lastSuccessfulAt":null,"state":"unavailable"}}},{"provider":"codex","quota":{"data":{"windows":[{"id":"codex.primary","resetsAt":"2026-10-22T10:00:00.000Z","usedPercent":25}]},"status":{"errorCode":null,"lastSuccessfulAt":"2026-10-22T09:00:00.000Z","state":"fresh"}},"updatedAt":"2026-10-22T09:00:00.000Z","usage":{"data":null,"status":{"errorCode":null,"lastSuccessfulAt":null,"state":"unavailable"}}},{"provider":"cursor","quota":{"data":null,"status":{"errorCode":null,"lastSuccessfulAt":null,"state":"unavailable"}},"updatedAt":null,"usage":{"data":null,"status":{"errorCode":null,"lastSuccessfulAt":null,"state":"unavailable"}}}],"schemaVersion":1}

"""

private let preChangeWidgetFixture = """
{"quotaRows":[{"headline":{"id":"claude.weekly","remainingPercent":60,"resetsAt":"2026-10-23T09:00:00Z"},"lastSuccessfulAt":"2026-10-22T09:00:00Z","provider":"claude","stream":"stale"},{"headline":{"id":"codex.primary","remainingPercent":75,"resetsAt":"2026-10-22T10:00:00Z"},"lastSuccessfulAt":"2026-10-22T09:00:00Z","provider":"codex","stream":"fresh"}],"schemaVersion":1,"today":{"completeness":"unavailable"},"usageRows":[{"provider":"claude","stream":"unavailable"},{"provider":"codex","stream":"unavailable"},{"provider":"cursor","stream":"unavailable"}]}
"""

private func claudeError(_ code: String) -> QuotaRefreshResult {
    .init(snapshots: [:], errors: [.claude: .init(provider: "claude", code: code, message: canaryMessage, action: nil)])
}

private func claudeQuota(resetBase: Date = ClaudeAccessExpiredReasonTests.start) throws -> QuotaSnapshot {
    QuotaSnapshot(windows: [
        try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 30, resetsAt: resetBase.addingTimeInterval(7_200)),
        try QuotaWindow(id: "claude.weekly", title: "Weekly", usedPercent: 40, resetsAt: resetBase.addingTimeInterval(86_400)),
        try QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "Fable weekly", usedPercent: 50,
                        resetsAt: resetBase.addingTimeInterval(86_400)),
    ])
}

/// Builds a diagnostics read the way the bridge reports it: whole-second
/// RFC3339 attempt time, closed origin, and extra canary fields that a correct
/// consumer must ignore.
private func diagnosticsRead(
    origin: String?,
    lastAttemptAt: Date?,
    quotaStatus: String = "error"
) -> ClaudeQuotaDiagnosticsRead {
    let formatter = ISO8601DateFormatter()
    let attemptField = lastAttemptAt.map {
        "\"lastAttemptAt\":\"\(formatter.string(from: Date(timeIntervalSince1970: floor($0.timeIntervalSince1970))))\","
    } ?? ""
    let originField = origin.map { "\"claudeQuotaFailureOrigin\":\"\($0)\"," } ?? ""
    let generated = formatter.string(from: Date(timeIntervalSince1970: 1_800_000_000))
    let json = """
    {"schemaVersion":"needlbar.v1","ok":true,"generatedAt":"\(generated)","data":{"providers":[{"provider":"claude","usageStatus":"available","quotaStatus":"\(quotaStatus)","usageSource":"local","quotaSource":"oauth",\(attemptField)\(originField)"rawSecretCanary":"CLAUDE-CANARY-SECRET","accountPath":"/private/canary","refreshToken":"sk-ant-canary"}]},"errors":[{"provider":"claude","code":"authenticationExpired","message":"\(canaryMessage)"}]}
    """
    return Result { try BridgeDecoder().decodeDiagnosticsEnvelope(Data(json.utf8)) }
}

private extension ClaudeQuotaFailureOrigin {
    static let allCasesForTest: [Self] = [
        .credentialMissing, .keychainCredentialExpired, .fileCredentialExpired, .credentialAccessDenied,
        .usageEndpointUnauthorized, .usageEndpointForbidden, .otherFailure,
    ]
}

// MARK: - Test doubles

private struct Harness {
    let store: ProviderSnapshotStore
    let quota: ScriptedQuotaRepository
    let diagnostics: FakeClaudeDiagnostics
    let clock: ManualClock
    let completions: CompletionCounter
    let coordinator: RefreshCoordinator

    init(results: [ScriptedQuotaRepository.Outcome], now: Date = ClaudeAccessExpiredReasonTests.start) {
        let clock = ManualClock(now: now)
        let diagnostics = FakeClaudeDiagnostics(clock: clock)
        let completions = CompletionCounter()
        store = ProviderSnapshotStore(now: { clock.now })
        quota = ScriptedQuotaRepository(results)
        self.diagnostics = diagnostics
        self.clock = clock
        self.completions = completions
        // The existing completion callback runs after the report, so it marks a
        // fully completed Claude operation both before and after the change.
        coordinator = RefreshCoordinator(
            usageRepository: EmptyUsageRepository(),
            quotaRepository: quota,
            store: store,
            clock: clock,
            claudeQuotaOperationCompleted: { completions.increment() },
            claudeQuotaDiagnostics: diagnostics.completion
        )
    }

    func waitUntilCompleted(_ expected: Int) async {
        await completions.waits.wait { completions.value >= expected }
    }

    /// Polls the fakes' state until the condition holds or the test is cancelled.
    func waitUntil(_ condition: @escaping @Sendable () -> Bool) async {
        while !Task.isCancelled, !condition() {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}

private final class CompletionCounter: @unchecked Sendable {
    private let lock = NSLock()
    let waits = ConditionWaiters()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() {
        lock.withLock { count += 1 }
        waits.signal()
    }
}

private struct EmptyUsageRepository: UsageRepository {
    func refresh() throws -> UsageRefreshResult { .init(snapshots: [:], errors: [:]) }
}

private final class ScriptedQuotaRepository: QuotaRepository, @unchecked Sendable {
    enum Outcome {
        case result(QuotaRefreshResult)
        case failure(any Error)
    }

    private let lock = NSLock()
    private var outcomes: [Outcome]
    private var recorded: [QuotaRefreshIntent] = []

    init(_ outcomes: [Outcome]) { self.outcomes = outcomes }

    var callCount: Int { lock.withLock { recorded.count } }
    var intents: [QuotaRefreshIntent] { lock.withLock { recorded } }

    func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult {
        let outcome = lock.withLock { () -> Outcome? in
            recorded.append(intent)
            return outcomes.isEmpty ? nil : outcomes.removeFirst()
        }
        switch outcome {
        case .result(let result): return result
        case .failure(let error): throw error
        case nil:
            Issue.record("unexpected extra quota repository call for \(intent)")
            return .init(snapshots: [:], errors: [:])
        }
    }
}

/// Stands in for the bridge diagnostics export and the OSLog reporter.
private final class FakeClaudeDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private let clock: ManualClock
    private var respond: @Sendable (Date) -> ClaudeQuotaDiagnosticsRead = { _ in .failure(BridgeFailure.nullPointer) }
    private var reads = 0
    private var reports = 0
    private var readStamps: [Date] = []
    private var reportStamps: [Date] = []
    private var holdNextRead = false
    private var heldRead: CheckedContinuation<Void, Never>?
    private var heldReleased = false

    init(clock: ManualClock) { self.clock = clock }

    var readCount: Int { lock.withLock { reads } }
    var reportCount: Int { lock.withLock { reports } }
    var readGeneratedAt: [Date] { lock.withLock { readStamps } }
    var reportedGeneratedAt: [Date] { lock.withLock { reportStamps } }

    func script(_ respond: @escaping @Sendable (Date) -> ClaudeQuotaDiagnosticsRead) {
        lock.withLock { self.respond = respond }
    }

    func holdFirstRead() { lock.withLock { holdNextRead = true } }

    func releaseHeldRead() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            heldReleased = true
            defer { heldRead = nil }
            return heldRead
        }
        continuation?.resume()
    }

    var completion: ClaudeQuotaCompletionDiagnostics {
        ClaudeQuotaCompletionDiagnostics(
            read: { await self.read() },
            report: { self.report($0) }
        )
    }

    private func read() async -> ClaudeQuotaDiagnosticsRead {
        let (respond, hold, index) = lock.withLock { () -> (@Sendable (Date) -> ClaudeQuotaDiagnosticsRead, Bool, Int) in
            let hold = holdNextRead
            holdNextRead = false
            return (self.respond, hold, reads)
        }
        // A distinct generatedAt per read lets the test match reads to reports.
        let stamped = Self.stamp(respond(clock.now), index: index)
        lock.withLock {
            reads += 1
            readStamps.append(Self.generatedAt(of: stamped) ?? .distantPast)
        }
        if hold {
            await withCheckedContinuation { continuation in
                let released = lock.withLock { () -> Bool in
                    if heldReleased { return true }
                    heldRead = continuation
                    return false
                }
                if released { continuation.resume() }
            }
        }
        return stamped
    }

    private func report(_ read: ClaudeQuotaDiagnosticsRead) {
        lock.withLock {
            reports += 1
            reportStamps.append(Self.generatedAt(of: read) ?? .distantPast)
        }
    }

    private static func stamp(_ read: ClaudeQuotaDiagnosticsRead, index: Int) -> ClaudeQuotaDiagnosticsRead {
        guard case .success(let envelope) = read else { return read }
        return .success(BridgeEnvelope(
            schemaVersion: envelope.schemaVersion, ok: envelope.ok,
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)),
            data: envelope.data, errors: envelope.errors))
    }

    private static func generatedAt(of read: ClaudeQuotaDiagnosticsRead) -> Date? {
        if case .success(let envelope) = read { return envelope.generatedAt }
        return nil
    }
}

private final class ManualClock: ClockLike, @unchecked Sendable {
    private struct Sleeper {
        let deadline: Date
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private let changes = ConditionWaiters()
    private var date: Date
    private var sleepers: [UUID: Sleeper] = [:]

    init(now: Date) { date = now }

    var now: Date { lock.withLock { date } }
    var sleeperCount: Int { lock.withLock { sleepers.count } }

    func setNowWithoutWakingSleepers(_ value: Date) { lock.withLock { date = value } }

    func waitUntilSleeperCount(_ expected: Int) async { await changes.wait { self.sleeperCount >= expected } }

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        let id = UUID()
        let seconds = TimeInterval(duration.components.seconds)
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let cancelled = lock.withLock { () -> Bool in
                    if Task.isCancelled { return true }
                    sleepers[id] = .init(deadline: date.addingTimeInterval(seconds), continuation: continuation)
                    return false
                }
                if cancelled { continuation.resume(throwing: CancellationError()) } else { changes.signal() }
            }
        }, onCancel: {
            lock.withLock { sleepers.removeValue(forKey: id) }?.continuation.resume(throwing: CancellationError())
        })
    }

    func advance(by interval: TimeInterval) {
        let due = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            date = date.addingTimeInterval(interval)
            let ready = sleepers.filter { $0.value.deadline <= date }
            ready.keys.forEach { sleepers.removeValue(forKey: $0) }
            return ready.values.map(\.continuation)
        }
        due.forEach { $0.resume() }
    }
}
