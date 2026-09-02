import Foundation
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

#if NEEDLBAR_ACCEPTANCE_DRIVER
@Suite("AcceptanceFixtureTests", .serialized)
struct AcceptanceFixtureTests {
    @Test func validFixtureMapsOnlyCanonicalSnapshots() throws {
        let fixture = try AcceptanceFixtureParser.parse(data: validFixtureData())
        #expect(fixture.events.count == 2)
        #expect(fixture.events[0].usage[.claude]?.today.totalTokens == 800)
        #expect(fixture.events[0].quota[.claude]?.windows.map(\.id) == ["claude.session"])
        #expect(fixture.events[0].quota[.cursor] == nil)
        #expect(fixture.events[0].usage[.claude]?.today.estimatedCostUSD == Decimal(string: "1.20"))
    }

    @Test(arguments: [
        ("{\"schemaVersion\":1,\"schemaVersion\":1}", "fixtureDuplicateKey", nil),
        ("{\"schemaVersion\":1,\"unknown\":true}", "fixtureUnknownKey", nil),
        ("{\"schemaVersion\":1,\"timeZone\":\"America/New_York\",\"startAt\":\"bad\",\"events\":[]}", "fixtureInvalidValue", nil),
        ("{\"schemaVersion\":1,\"timeZone\":\"America/New_York\",\"startAt\":\"2026-09-01T12:00:00.000Z\",\"events\":[{\"delaySeconds\":0,\"localDay\":\"2026-09-01\",\"usage\":{},\"quota\":{\"cursor\":[]}}]}", "fixtureUnknownID", 0),
        ("{\"schemaVersion\":1,\"timeZone\":\"America/New_York\",\"startAt\":\"2026-09-01T12:00:00.000Z\",\"events\":[{\"delaySeconds\":0,\"localDay\":\"2026-09-01\",\"usage\":{\"claude\":{\"tokens\":1,\"costUSD\":\"1.00\",\"note\":\"secret\"}},\"quota\":{}}]}", "fixtureCanaryDetected", 0),
    ]) func malformedValuesReturnOnlyStableCode(_ text: String, _ code: String, _ index: Int?) {
        #expect(throws: AcceptanceFixtureFailure.self) {
            _ = try AcceptanceFixtureParser.parse(data: Data(text.utf8))
        }
        do {
            _ = try AcceptanceFixtureParser.parse(data: Data(text.utf8))
        } catch let failure as AcceptanceFixtureFailure {
            #expect(failure.code.rawValue == code)
            #expect(failure.eventIndex == index)
            #expect(failure.description == index.map { "\(code): event \($0)" } ?? code)
            #expect(!failure.description.contains("secret"))
        } catch {
            Issue.record("unexpected error type")
        }
    }

    @Test func filePathMustBeRegularAndContainedWithoutSymlinkEscape() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("needlbar-input-\(UUID().uuidString)")
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("needlbar-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let file = root.appendingPathComponent("fixture.json")
        try validFixtureData().write(to: file)
        let outsideFile = outside.appendingPathComponent("fixture.json")
        try validFixtureData().write(to: outsideFile)
        let escaped = root.appendingPathComponent("escaped.json")
        try FileManager.default.createSymbolicLink(at: escaped, withDestinationURL: outsideFile)
        #expect(try AcceptanceFixturePath.validate(file, beneath: root) == file.resolvingSymlinksInPath())
        #expect(throws: AcceptanceFixtureFailure.fixturePathInvalid) {
            _ = try AcceptanceFixturePath.validate(escaped, beneath: root)
        }
    }

    @Test func driverWaitsForEachPriorDelayAndOnlyUsesStoreApplyAPIs() async throws {
        let recorder = AcceptanceSleeperRecorder()
        let store = ProviderSnapshotStore()
        let driver = AcceptanceFixtureDriver(
            fixture: try AcceptanceFixtureParser.parse(data: validFixtureData()),
            store: store,
            sleeper: recorder
        )
        await driver.start()
        #expect(await recorder.durations == [.seconds(0), .seconds(1)])
        #expect(await store.currentQuotaAlertSample(for: .claude).revision == 2)
    }

    @Test func omittedStreamMarksOnlyThatExistingStreamFailedAndRetainsLastGoodValue() async throws {
        let store = ProviderSnapshotStore()
        let fixture = try AcceptanceFixtureParser.parse(data: failureIsolationFixtureData())
        await AcceptanceFixtureDriver(fixture: fixture, store: store, sleeper: ImmediateAcceptanceSleeper()).start()
        let claude = await store.snapshot(for: .claude)
        #expect(claude.usage?.today.totalTokens == 800)
        #expect(claude.usageStatus != .fresh)
        #expect(claude.quota?.windows.first?.remainingPercent == 20)
        #expect(claude.quotaStatus == .fresh)
    }

    @Test func omittedQuotaMarksOnlyQuotaFailedAndRetainsLastGoodUsage() async throws {
        let store = ProviderSnapshotStore()
        let fixture = try AcceptanceFixtureParser.parse(data: quotaFailureIsolationFixtureData())
        await AcceptanceFixtureDriver(fixture: fixture, store: store, sleeper: ImmediateAcceptanceSleeper()).start()
        let claude = await store.snapshot(for: .claude)
        #expect(claude.usage?.today.totalTokens == 900)
        #expect(claude.usageStatus == .fresh)
        #expect(claude.quota?.windows.first?.remainingPercent == 80)
        #expect(claude.quotaStatus != .fresh)
    }

    @Test func newLocalDayDoesNotReusePriorUsageProvenance() async throws {
        let store = ProviderSnapshotStore()
        let fixture = try AcceptanceFixtureParser.parse(data: midnightFixtureData())
        await AcceptanceFixtureDriver(fixture: fixture, store: store, sleeper: ImmediateAcceptanceSleeper()).start()
        let capture = await store.captureForWidget(exportedAt: fixture.events.last!.eventDate)
        let claude = try #require(capture.providers.first(where: { $0.provider == .claude }))
        #expect(claude.usageDayProvenance?.provenContext?.dayKey == "2026-09-02")
        #expect(claude.usage?.today.totalTokens == 25)
    }
}

private actor AcceptanceSleeperRecorder: AcceptanceFixtureSleeping {
    private(set) var durations: [Duration] = []

    func sleep(for duration: Duration) async throws {
        durations.append(duration)
    }
}

private struct ImmediateAcceptanceSleeper: AcceptanceFixtureSleeping {
    func sleep(for duration: Duration) async throws {}
}

private func validFixtureData() -> Data {
    Data(#"""
    {
      "schemaVersion": 1,
      "timeZone": "America/New_York",
      "startAt": "2026-09-01T12:00:00.000Z",
      "events": [
        {
          "delaySeconds": 0,
          "localDay": "2026-09-01",
          "usage": {
            "claude": {"tokens": 800, "costUSD": "1.20"},
            "codex": {"tokens": 600, "costUSD": "0.90"},
            "cursor": {"tokens": 200, "costUSD": "0.30"}
          },
          "quota": {
            "claude": [{"id": "claude.session", "remainingPercent": 80, "resetsAt": "2026-09-02T12:00:00.000Z"}],
            "codex": [{"id": "codex.primary", "remainingPercent": 80, "resetsAt": "2026-09-02T12:00:00.000Z"}]
          }
        },
        {
          "delaySeconds": 1,
          "localDay": "2026-09-01",
          "usage": {
            "claude": {"tokens": 900, "costUSD": "1.35"},
            "codex": {"tokens": 600, "costUSD": "0.90"},
            "cursor": {"tokens": 200, "costUSD": "0.30"}
          },
          "quota": {
            "claude": [{"id": "claude.session", "remainingPercent": 20, "resetsAt": "2026-09-02T12:00:00.000Z"}],
            "codex": [{"id": "codex.primary", "remainingPercent": 80, "resetsAt": "2026-09-02T12:00:00.000Z"}]
          }
        }
      ]
    }
    """#.utf8)
}

private func failureIsolationFixtureData() -> Data {
    Data(#"""
    {
      "schemaVersion": 1,
      "timeZone": "America/New_York",
      "startAt": "2026-09-01T12:00:00.000Z",
      "events": [
        {"delaySeconds": 0, "localDay": "2026-09-01", "usage": {"claude": {"tokens": 800, "costUSD": "1.20"}}, "quota": {"claude": [{"id": "claude.session", "remainingPercent": 80, "resetsAt": "2026-09-02T12:00:00.000Z"}]}},
        {"delaySeconds": 1, "localDay": "2026-09-01", "usage": {}, "quota": {"claude": [{"id": "claude.session", "remainingPercent": 20, "resetsAt": "2026-09-02T12:00:00.000Z"}]}}
      ]
    }
    """#.utf8)
}

private func quotaFailureIsolationFixtureData() -> Data {
    Data(#"""
    {
      "schemaVersion": 1,
      "timeZone": "America/New_York",
      "startAt": "2026-09-01T12:00:00.000Z",
      "events": [
        {"delaySeconds": 0, "localDay": "2026-09-01", "usage": {"claude": {"tokens": 800, "costUSD": "1.20"}}, "quota": {"claude": [{"id": "claude.session", "remainingPercent": 80, "resetsAt": "2026-09-02T12:00:00.000Z"}]}},
        {"delaySeconds": 1, "localDay": "2026-09-01", "usage": {"claude": {"tokens": 900, "costUSD": "1.35"}}, "quota": {}}
      ]
    }
    """#.utf8)
}

private func midnightFixtureData() -> Data {
    Data(#"""
    {
      "schemaVersion": 1,
      "timeZone": "America/New_York",
      "startAt": "2026-09-02T03:59:59.000Z",
      "events": [
        {"delaySeconds": 0, "localDay": "2026-09-01", "usage": {"claude": {"tokens": 800, "costUSD": "1.20"}}, "quota": {}},
        {"delaySeconds": 1, "localDay": "2026-09-02", "usage": {"claude": {"tokens": 25, "costUSD": "0.04"}}, "quota": {}}
      ]
    }
    """#.utf8)
}
#endif
