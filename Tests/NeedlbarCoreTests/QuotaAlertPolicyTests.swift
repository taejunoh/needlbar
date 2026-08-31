import Darwin
import Foundation
import Testing
@testable import NeedlbarCore

@Suite("QuotaAlertPolicyTests")
struct QuotaAlertPolicyTests {
    @Test func firstLowBaselineThenDirectTenCrossingReservesOnlyTenAndConsumesBothStages() throws {
        let now = date("2026-08-31T12:00:00Z")
        let key = try QuotaAlertKey(provider: .claude, windowID: "claude.session")
        let policy = QuotaAlertPolicy()

        let first = policy.observe(observation(key, remaining: 8, at: now), ledger: .empty, now: now, processHasEstablishedBaseline: false)
        #expect(first.stage == nil)
        #expect(first.ledger.record(for: key)?.consumedStages == [.twenty, .ten])

        let recovered = policy.observe(observation(key, remaining: 80, at: now.addingTimeInterval(1)), ledger: first.ledger, now: now.addingTimeInterval(1), processHasEstablishedBaseline: true)
        let directTen = policy.observe(observation(key, remaining: 10, at: now.addingTimeInterval(2)), ledger: recovered.ledger, now: now.addingTimeInterval(2), processHasEstablishedBaseline: true)
        #expect(directTen.stage == nil)

        let baseline = policy.observe(observation(key, remaining: 80, at: now), ledger: .empty, now: now, processHasEstablishedBaseline: false)
        let jump = policy.observe(observation(key, remaining: 10, at: now.addingTimeInterval(1)), ledger: baseline.ledger, now: now.addingTimeInterval(1), processHasEstablishedBaseline: true)
        #expect(jump.stage == .ten)
        #expect(jump.ledger.record(for: key)?.consumedStages == [.twenty, .ten])
        #expect(jump.ledger.record(for: key)?.reservedStages == [.ten])
    }

    @Test func inclusiveThresholdsCrossDownwardOnly() throws {
        let now = date("2026-08-31T12:00:00Z")
        let key = try QuotaAlertKey(provider: .claude, windowID: "claude.weekly")
        let policy = QuotaAlertPolicy()
        let baseline = policy.observe(observation(key, remaining: 21, at: now), ledger: .empty, now: now, processHasEstablishedBaseline: false)
        let twenty = policy.observe(observation(key, remaining: 20, at: now.addingTimeInterval(1)), ledger: baseline.ledger, now: now.addingTimeInterval(1), processHasEstablishedBaseline: true)
        #expect(twenty.stage == .twenty)
        let ten = policy.observe(observation(key, remaining: 10, at: now.addingTimeInterval(2)), ledger: twenty.ledger, now: now.addingTimeInterval(2), processHasEstablishedBaseline: true)
        #expect(ten.stage == .ten)
        let upward = policy.observe(observation(key, remaining: 90, at: now.addingTimeInterval(3)), ledger: ten.ledger, now: now.addingTimeInterval(3), processHasEstablishedBaseline: true)
        #expect(upward.stage == nil)
    }

    @Test func restartAndResetDriftDoNotRearmButConservativeNewCycleDoes() throws {
        let start = date("2026-08-31T12:00:00Z")
        let oldReset = start.addingTimeInterval(60)
        let newReset = start.addingTimeInterval(180)
        let key = try QuotaAlertKey(provider: .codex, windowID: "codex.primary")
        let policy = QuotaAlertPolicy()
        let baseline = policy.observe(observation(key, remaining: 80, reset: oldReset, at: start), ledger: .empty, now: start, processHasEstablishedBaseline: false)
        let twenty = policy.observe(observation(key, remaining: 20, reset: oldReset, at: start.addingTimeInterval(1)), ledger: baseline.ledger, now: start.addingTimeInterval(1), processHasEstablishedBaseline: true)
        let restart = policy.observe(observation(key, remaining: 10, reset: newReset, at: start.addingTimeInterval(2)), ledger: twenty.ledger, now: start.addingTimeInterval(2), processHasEstablishedBaseline: false)
        #expect(restart.stage == nil)
        #expect(restart.ledger.record(for: key)?.reservedStages == [.twenty])
        let drift = policy.observe(observation(key, remaining: 80, reset: newReset, at: start.addingTimeInterval(3)), ledger: restart.ledger, now: start.addingTimeInterval(3), processHasEstablishedBaseline: true)
        #expect(drift.ledger.record(for: key)?.pinnedResetAt == oldReset)
        let rearm = policy.observe(observation(key, remaining: 80, reset: newReset, at: start.addingTimeInterval(61)), ledger: drift.ledger, now: start.addingTimeInterval(61), processHasEstablishedBaseline: true)
        #expect(rearm.stage == nil)
        #expect(rearm.ledger.record(for: key)?.consumedStages == [])
        #expect(rearm.ledger.record(for: key)?.pinnedResetAt == newReset)
    }

    @Test func nullOrExpiredResetDoesNotBlockAnUnusedTenCrossing() throws {
        let now = date("2026-08-31T12:00:00Z")
        let key = try QuotaAlertKey(provider: .claude, windowID: "claude.weekly")
        let policy = QuotaAlertPolicy()
        let baseline = policy.observe(observation(key, remaining: 80, at: now), ledger: .empty, now: now, processHasEstablishedBaseline: false)
        let twenty = policy.observe(observation(key, remaining: 20, at: now.addingTimeInterval(1)), ledger: baseline.ledger, now: now.addingTimeInterval(1), processHasEstablishedBaseline: true)
        let ten = policy.observe(observation(key, remaining: 10, reset: now.addingTimeInterval(-1), at: now.addingTimeInterval(2)), ledger: twenty.ledger, now: now.addingTimeInterval(2), processHasEstablishedBaseline: true)
        #expect(twenty.stage == .twenty)
        #expect(ten.stage == .ten)
    }

    @Test func policyRejectsInvalidAndFutureObservationsWithoutChangingTheLedger() throws {
        let now = date("2026-08-31T12:00:00Z")
        let key = try QuotaAlertKey(provider: .claude, windowID: "claude.session")
        let policy = QuotaAlertPolicy()
        let baseline = policy.observe(observation(key, remaining: 80, at: now), ledger: .empty, now: now, processHasEstablishedBaseline: false).ledger
        let future = policy.observe(observation(key, remaining: 20, at: now.addingTimeInterval(1)), ledger: baseline, now: now, processHasEstablishedBaseline: true)
        #expect(future.stage == nil)
        #expect(future.ledger == baseline)
        let invalid = policy.observe(observation(key, remaining: 101, at: now), ledger: baseline, now: now, processHasEstablishedBaseline: true)
        #expect(invalid.stage == nil)
        #expect(invalid.ledger == baseline)
    }

    @Test func keyAllowsOnlyFourKnownProviderWindows() throws {
        #expect(try QuotaAlertKey(provider: .claude, windowID: "claude.session").windowID == "claude.session")
        #expect(try QuotaAlertKey(provider: .claude, windowID: "claude.weekly").windowID == "claude.weekly")
        #expect(try QuotaAlertKey(provider: .codex, windowID: "codex.primary").windowID == "codex.primary")
        #expect(try QuotaAlertKey(provider: .codex, windowID: "codex.secondary").windowID == "codex.secondary")
        #expect(throws: QuotaAlertLedgerStoreError.self) { _ = try QuotaAlertKey(provider: .cursor, windowID: "cursor.primary") }
        #expect(throws: QuotaAlertLedgerStoreError.self) { _ = try QuotaAlertKey(provider: .claude, windowID: "untrusted") }
    }

    @Test func realLedgerStoreTreatsMissingCorruptAndInvalidLedgersAsEmptyAndWritesPrivateFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ledger.json")
        let store = QuotaAlertLedgerStore(url: url, writer: POSIXSnapshotFileWriter())
        #expect(try await store.load() == .empty)

        try Data("{broken".utf8).write(to: url)
        #expect(try await store.load() == .empty)
        try Data("""
        {"schemaVersion":1,"records":[
          {"key":{"provider":"claude","windowID":"claude.session"},"lastRemainingPercent":50,"lastSuccessfulAt":778248000,"pinnedResetAt":null,"consumedStages":[],"reservedStages":[]},
          {"key":{"provider":"claude","windowID":"claude.session"},"lastRemainingPercent":50,"lastSuccessfulAt":778248000,"pinnedResetAt":null,"consumedStages":[],"reservedStages":[]}
        ]}
        """.utf8).write(to: url)
        #expect(try await store.load() == .empty)
        try Data(repeating: 0, count: 16 * 1024 + 1).write(to: url)
        #expect(try await store.load() == .empty)

        let now = Date()
        let key = try QuotaAlertKey(provider: .claude, windowID: "claude.session")
        let passedAnchorKey = try QuotaAlertKey(provider: .codex, windowID: "codex.primary")
        let ledger = QuotaAlertLedger(schemaVersion: 1, records: [
            QuotaAlertRecord(key: key, lastRemainingPercent: 80, lastSuccessfulAt: now, pinnedResetAt: now.addingTimeInterval(60), consumedStages: [], reservedStages: []),
            QuotaAlertRecord(key: passedAnchorKey, lastRemainingPercent: 80, lastSuccessfulAt: now, pinnedResetAt: now.addingTimeInterval(-60), consumedStages: [], reservedStages: []),
        ])
        try await store.save(ledger)
        #expect(try await store.load() == ledger)
        var metadata = stat()
        #expect(url.path.withCString { Darwin.lstat($0, &metadata) } == 0)
        #expect(Int(metadata.st_mode & 0o777) == 0o600)
    }

    @Test func ledgerValidationRejectsUnknownWindowTooManyRecordsInvalidPercentFutureSampleAndBadReservation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ledger.json")
        let store = QuotaAlertLedgerStore(url: url, writer: POSIXSnapshotFileWriter())
        let now = Date()
        let invalids = [
            "{\"schemaVersion\":2,\"records\":[]}",
            "{\"schemaVersion\":1,\"records\":[{\"key\":{\"provider\":\"claude\",\"windowID\":\"unknown\"},\"lastRemainingPercent\":80,\"lastSuccessfulAt\":0,\"pinnedResetAt\":null,\"consumedStages\":[],\"reservedStages\":[]}]}",
            "{\"schemaVersion\":1,\"records\":[{\"key\":{\"provider\":\"claude\",\"windowID\":\"claude.session\"},\"lastRemainingPercent\":101,\"lastSuccessfulAt\":0,\"pinnedResetAt\":null,\"consumedStages\":[],\"reservedStages\":[]}]}",
            "{\"schemaVersion\":1,\"records\":[{\"key\":{\"provider\":\"claude\",\"windowID\":\"claude.session\"},\"lastRemainingPercent\":80,\"lastSuccessfulAt\":9999999999,\"pinnedResetAt\":null,\"consumedStages\":[],\"reservedStages\":[]}]}",
            "{\"schemaVersion\":1,\"records\":[{\"key\":{\"provider\":\"claude\",\"windowID\":\"claude.session\"},\"lastRemainingPercent\":80,\"lastSuccessfulAt\":0,\"pinnedResetAt\":null,\"consumedStages\":[],\"reservedStages\":[10]}]}"
        ]
        for bytes in invalids {
            try Data(bytes.utf8).write(to: url)
            #expect(try await store.load() == .empty)
        }
        let key = try QuotaAlertKey(provider: .claude, windowID: "claude.session")
        let record = QuotaAlertRecord(key: key, lastRemainingPercent: 80, lastSuccessfulAt: now, pinnedResetAt: now.addingTimeInterval(-60), consumedStages: [], reservedStages: [])
        do {
            try await store.save(QuotaAlertLedger(schemaVersion: 1, records: Array(repeating: record, count: 5)))
            Issue.record("expected invalid ledger to be rejected")
        } catch let error as QuotaAlertLedgerStoreError {
            #expect(error == .corrupt)
        }
        let nonfiniteDate = QuotaAlertLedger(schemaVersion: 1, records: [QuotaAlertRecord(key: key, lastRemainingPercent: .nan, lastSuccessfulAt: Date(timeIntervalSinceReferenceDate: .nan), pinnedResetAt: nil, consumedStages: [], reservedStages: [])])
        await #expect(throws: QuotaAlertLedgerStoreError.corrupt) { try await store.save(nonfiniteDate) }
    }

    @Test func storeRejectsDurabilityWarningAsNonDurable() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = QuotaAlertLedgerStore(url: url, writer: DurabilityWarningWriter())
        await #expect(throws: QuotaAlertLedgerStoreError.writeFailed) { try await store.save(.empty) }
    }
}

private struct DurabilityWarningWriter: SnapshotFileWriter {
    func writeAtomically(_ bytes: Data, to destination: URL) throws -> AtomicWriteResult {
        _ = bytes
        _ = destination
        return .committedWithDurabilityWarning
    }
}

private func observation(_ key: QuotaAlertKey, remaining: Double, reset: Date? = nil, at: Date) -> QuotaAlertObservation {
    QuotaAlertObservation(key: key, remainingPercent: remaining, resetsAt: reset, successfulAt: at, revision: 1)
}

private func date(_ string: String) -> Date {
    try! #require(BridgeDecoder.date(string))
}
