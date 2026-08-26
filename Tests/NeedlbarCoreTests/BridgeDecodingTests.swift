import Foundation
import Testing
@testable import NeedlbarCore

@Test func usageEnvelopeDecodesKnownProviderAndIgnoresFutureFields() throws {
    let payload = """
    {
      "schemaVersion": "needlbar.v1",
      "ok": true,
      "generatedAt": "2026-08-14T12:34:56.789Z",
      "data": {
        "providers": [{
          "provider": "claude",
          "inputTokens": 1000,
          "outputTokens": 250,
          "cacheReadTokens": 400,
          "cacheWriteTokens": 100,
          "totalTokens": 1750,
          "estimatedCostUSD": 12.345,
          "today": { "inputTokens": 10, "outputTokens": 2, "cacheReadTokens": 3, "cacheWriteTokens": 4, "totalTokens": 19, "estimatedCostUSD": "0.123" },
          "last7Days": { "inputTokens": 20, "outputTokens": 4, "cacheReadTokens": 6, "cacheWriteTokens": 8, "totalTokens": 38, "estimatedCostUSD": "0.456" },
          "last7DaysDaily": [{ "date": "2026-08-08", "totalTokens": 12 }, { "date": "2026-08-09", "totalTokens": 26 }],
          "last30Days": { "inputTokens": 30, "outputTokens": 6, "cacheReadTokens": 9, "cacheWriteTokens": 12, "totalTokens": 57, "estimatedCostUSD": "0.789" },
          "futureProviderField": "ignored"
        }],
        "futurePayloadField": true
      },
      "errors": [],
      "futureField": { "introducedBy": "v2" }
    }
    """

    let envelope = try BridgeDecoder().decodeUsageEnvelope(Data(payload.utf8))
    let provider = try #require(envelope.data?.providers.first)
    let generatedAt = try #require(BridgeDecoder.date("2026-08-14T12:34:56.789Z"))

    #expect(envelope.schemaVersion == "needlbar.v1")
    #expect(envelope.generatedAt == generatedAt)
    #expect(provider.providerID == .claude)
    #expect(provider.usage.estimatedCostUSD == Decimal(string: "12.345"))
    #expect(provider.usage.today.estimatedCostUSD == Decimal(string: "0.123"))
    #expect(provider.usage.last7DaysDaily.map(\.totalTokens) == [12, 26])
}

@Test func usageEnvelopeAcceptsAnAbsentAdditiveDailySeries() throws {
    let payload = """
    {
      "schemaVersion": "needlbar.v1", "ok": true, "generatedAt": "2026-08-14T12:34:56Z", "errors": [],
      "data": { "providers": [{
        "provider": "claude", "inputTokens": 0, "outputTokens": 0, "cacheReadTokens": 0, "cacheWriteTokens": 0, "totalTokens": 0, "estimatedCostUSD": 0,
        "today": { "inputTokens": 0, "outputTokens": 0, "cacheReadTokens": 0, "cacheWriteTokens": 0, "totalTokens": 0, "estimatedCostUSD": 0 },
        "last7Days": { "inputTokens": 0, "outputTokens": 0, "cacheReadTokens": 0, "cacheWriteTokens": 0, "totalTokens": 0, "estimatedCostUSD": 0 },
        "last30Days": { "inputTokens": 0, "outputTokens": 0, "cacheReadTokens": 0, "cacheWriteTokens": 0, "totalTokens": 0, "estimatedCostUSD": 0 }
      }] }
    }
    """

    let envelope = try BridgeDecoder().decodeUsageEnvelope(Data(payload.utf8))
    #expect(envelope.data?.providers.first?.usage.last7DaysDaily == [])
}

@Test func bridgeErrorsTreatRetiredCursorConnectActionAsUnknown() throws {
    let payload = """
    {"schemaVersion":"needlbar.v1","ok":false,"generatedAt":"2026-08-26T12:00:00Z","data":null,"errors":[{"provider":"cursor","code":"providerUnavailable","message":"Unavailable","action":"connectCursor"}]}
    """

    let envelope = try BridgeDecoder().decodeUsageEnvelope(Data(payload.utf8))

    #expect(envelope.errors.first?.action == .unknown("connectCursor"))
}

@Test func quotaEnvelopeRejectsOutOfRangePercentages() throws {
    let payload = """
    {
      "schemaVersion": "needlbar.v1",
      "ok": true,
      "generatedAt": "2026-08-14T12:34:56Z",
      "data": {
        "providers": [{
          "provider": "cursor",
          "windows": [{ "id": "cursor.plan", "title": "Plan", "usedPercent": 101, "resetsAt": null }]
        }]
      },
      "errors": []
    }
    """

    #expect(throws: DecodingError.self) {
        _ = try BridgeDecoder().decodeQuotaEnvelope(Data(payload.utf8))
    }
}

@Test func rustBridgeFreesReturnedPointerWhenJSONIsInvalidUTF8() throws {
    let bytes: [CChar] = [-1, 0]
    let recorder = FreeRecorder()
    let bridge = RustBridge(
        usageCall: { makeCString(bytes) },
        quotaCall: { nil },
        free: { pointer in recorder.release(pointer) }
    )

    #expect(throws: BridgeFailure.invalidUTF8) {
        _ = try bridge.usageEnvelope()
    }
    #expect(recorder.count == 1)
}

@Test func rustBridgeFreesReturnedPointerWhenDecodingFails() throws {
    let recorder = FreeRecorder()
    let bridge = RustBridge(
        usageCall: { makeCString(Array("{".utf8).map(CChar.init) + [0]) },
        quotaCall: { nil },
        free: { pointer in recorder.release(pointer) }
    )

    #expect(throws: DecodingError.self) {
        _ = try bridge.usageEnvelope()
    }
    #expect(recorder.count == 1)
}

@Test func rustUsageRepositoryUsesTheSingleUsageBridgeCall() throws {
    let calls = CallRecorder()
    let frees = FreeRecorder()
    let returnedPointer = try CStringPointer(usageCString(provider: "claude"))
    let bridge = RustBridge(
        usageCall: { calls.record("usage"); return returnedPointer.pointer },
        free: { frees.release($0) }
    )

    let result = try RustUsageRepository(bridge: bridge).refresh()

    #expect(calls.values == ["usage"])
    #expect(Set(result.snapshots.keys) == [.claude])
    #expect(frees.count == 1)
    #expect(frees.pointerIdentities == [pointerIdentity(returnedPointer.pointer)])
}

@Test func backgroundQuotaRefreshUsesOnlyTheAggregateBridgeCall() throws {
    let calls = CallRecorder()
    let frees = FreeRecorder()
    let returnedPointer = try CStringPointer(quotaCString(provider: "claude"))
    let bridge = RustBridge(
        quotaCall: { calls.record("background"); return returnedPointer.pointer },
        claudeUserInitiatedQuotaCall: { calls.record("claude"); return quotaCString(provider: "claude") },
        codexQuotaCall: { calls.record("codex"); return quotaCString(provider: "codex") },
        free: { frees.release($0) }
    )

    _ = try RustQuotaRepository(bridge: bridge).refresh(intent: .backgroundAll)

    #expect(calls.values == ["background"])
    #expect(frees.count == 1)
    #expect(frees.pointerIdentities == [pointerIdentity(returnedPointer.pointer)])
}

@Test func claudeUserInitiatedQuotaRefreshUsesOnlyClaudeBridgeCallAndFreesOnce() throws {
    let calls = CallRecorder()
    let frees = FreeRecorder()
    let returnedPointer = try CStringPointer(quotaCString(provider: "claude"))
    let bridge = RustBridge(
        quotaCall: { calls.record("background"); return quotaCString(provider: "claude") },
        claudeUserInitiatedQuotaCall: { calls.record("claude"); return returnedPointer.pointer },
        codexQuotaCall: { calls.record("codex"); return quotaCString(provider: "codex") },
        free: { frees.release($0) }
    )

    let result = try RustQuotaRepository(bridge: bridge).refresh(intent: .userInitiated(provider: .claude))

    #expect(calls.values == ["claude"])
    #expect(Set(result.snapshots.keys) == [.claude])
    #expect(frees.count == 1)
    #expect(frees.pointerIdentities == [pointerIdentity(returnedPointer.pointer)])
}

@Test func codexUserInitiatedQuotaRefreshUsesOnlyCodexBridgeCallAndFreesOnce() throws {
    let calls = CallRecorder()
    let frees = FreeRecorder()
    let returnedPointer = try CStringPointer(quotaCString(provider: "codex"))
    let bridge = RustBridge(
        quotaCall: { calls.record("background"); return quotaCString(provider: "claude") },
        claudeUserInitiatedQuotaCall: { calls.record("claude"); return quotaCString(provider: "claude") },
        codexQuotaCall: { calls.record("codex"); return returnedPointer.pointer },
        free: { frees.release($0) }
    )

    let result = try RustQuotaRepository(bridge: bridge).refresh(intent: .userInitiated(provider: .codex))

    #expect(calls.values == ["codex"])
    #expect(Set(result.snapshots.keys) == [.codex])
    #expect(frees.count == 1)
    #expect(frees.pointerIdentities == [pointerIdentity(returnedPointer.pointer)])
}

@Test func cursorUserInitiatedQuotaRefreshFailsClosedWithoutAnyBridgeCall() throws {
    let calls = CallRecorder()
    let bridge = RustBridge(
        quotaCall: { calls.record("background"); return quotaCString(provider: "cursor") },
        claudeUserInitiatedQuotaCall: { calls.record("claude"); return quotaCString(provider: "claude") },
        codexQuotaCall: { calls.record("codex"); return quotaCString(provider: "codex") }
    )

    #expect(throws: BridgeFailure.self) {
        _ = try RustQuotaRepository(bridge: bridge).refresh(intent: .userInitiated(provider: .cursor))
    }
    #expect(calls.values.isEmpty)
}

@Test func dedicatedQuotaRefreshRejectsAnUnexpectedProviderInsteadOfFilteringIt() throws {
    let frees = FreeRecorder()
    let bridge = RustBridge(
        quotaCall: { quotaCString(provider: "claude") },
        claudeUserInitiatedQuotaCall: { quotaCString(provider: "codex") },
        codexQuotaCall: { quotaCString(provider: "claude") },
        free: { frees.release($0) }
    )

    #expect(throws: BridgeFailure.self) {
        _ = try RustQuotaRepository(bridge: bridge).refresh(intent: .userInitiated(provider: .claude))
    }
    #expect(frees.count == 1)
}

@Test func dedicatedQuotaRefreshRejectsAnUnknownProviderErrorInsteadOfDroppingIt() throws {
    let frees = FreeRecorder()
    let payload = """
    {"schemaVersion":"needlbar.v1","ok":true,"generatedAt":"2026-08-25T12:00:00Z","data":{"providers":[]},"errors":[{"provider":"other","code":"permissionDenied","message":"denied"}]}
    """
    let bridge = RustBridge(
        claudeUserInitiatedQuotaCall: { makeCString(Array(payload.utf8).map(CChar.init) + [0]) },
        free: { frees.release($0) }
    )

    #expect(throws: BridgeFailure.self) {
        _ = try RustQuotaRepository(bridge: bridge).refresh(intent: .userInitiated(provider: .claude))
    }
    #expect(frees.count == 1)
}

@Test func dedicatedQuotaRefreshRejectsAnEmptySuccessfulEnvelopeAndFreesThatExactPointer() throws {
    let frees = FreeRecorder()
    let payload = """
    {"schemaVersion":"needlbar.v1","ok":true,"generatedAt":"2026-08-25T12:00:00Z","data":{"providers":[]},"errors":[]}
    """
    let returnedPointer = try CStringPointer(makeCString(Array(payload.utf8).map(CChar.init) + [0]))
    let bridge = RustBridge(
        claudeUserInitiatedQuotaCall: { returnedPointer.pointer },
        free: { frees.release($0) }
    )

    #expect(throws: BridgeFailure.self) {
        _ = try RustQuotaRepository(bridge: bridge).refresh(intent: .userInitiated(provider: .claude))
    }
    #expect(frees.count == 1)
    #expect(frees.pointerIdentities == [pointerIdentity(returnedPointer.pointer)])
}

@Test func dedicatedQuotaRefreshNormalizesABridgeWideErrorToTheRequestedProvider() throws {
    let frees = FreeRecorder()
    let payload = """
    {"schemaVersion":"needlbar.v1","ok":true,"generatedAt":"2026-08-25T12:00:00Z","data":{"providers":[]},"errors":[{"provider":null,"code":"permissionDenied","message":"denied"}]}
    """
    let returnedPointer = try CStringPointer(makeCString(Array(payload.utf8).map(CChar.init) + [0]))
    let bridge = RustBridge(
        claudeUserInitiatedQuotaCall: { returnedPointer.pointer },
        free: { frees.release($0) }
    )

    let result = try RustQuotaRepository(bridge: bridge).refresh(intent: .userInitiated(provider: .claude))

    #expect(result.snapshots.isEmpty)
    #expect(result.errors[.claude]?.provider == ProviderID.claude.rawValue)
    #expect(result.errors[.claude]?.code == "permissionDenied")
    #expect(frees.count == 1)
    #expect(frees.pointerIdentities == [pointerIdentity(returnedPointer.pointer)])
}

@Test func dedicatedQuotaRefreshRejectsAnUnexpectedProviderEvenWhenTheEnvelopeFails() throws {
    let frees = FreeRecorder()
    let payload = """
    {"schemaVersion":"needlbar.v1","ok":false,"generatedAt":"2026-08-25T12:00:00Z","data":{"providers":[{"provider":"claude","windows":[]}]},"errors":[{"provider":"codex","code":"permissionDenied","message":"denied"}]}
    """
    let returnedPointer = try CStringPointer(makeCString(Array(payload.utf8).map(CChar.init) + [0]))
    let bridge = RustBridge(
        claudeUserInitiatedQuotaCall: { returnedPointer.pointer },
        free: { frees.release($0) }
    )

    #expect(throws: BridgeFailure.self) {
        _ = try RustQuotaRepository(bridge: bridge).refresh(intent: .userInitiated(provider: .claude))
    }
    #expect(frees.count == 1)
    #expect(frees.pointerIdentities == [pointerIdentity(returnedPointer.pointer)])
}

@Test func intentOnlyQuotaRepositoryReceivesUserIntentWithoutAnyLegacyAggregateMethod() throws {
    let repository = IntentOnlyQuotaRepository()

    _ = try repository.refresh()
    _ = try repository.refresh(intent: .userInitiated(provider: .claude))

    #expect(repository.intents == [.backgroundAll, .userInitiated(provider: .claude)])
}

private final class FreeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var released: [UInt] = []

    var count: Int {
        lock.withLock { released.count }
    }

    var pointerIdentities: [UInt] {
        lock.withLock { released }
    }

    func release(_ pointer: UnsafePointer<CChar>?) {
        if let pointer {
            lock.withLock { released.append(pointerIdentity(pointer)) }
        }
        guard let pointer else { return }
        UnsafeMutablePointer(mutating: pointer).deallocate()
    }
}

private final class CStringPointer: @unchecked Sendable {
    let pointer: UnsafePointer<CChar>

    init(_ pointer: UnsafePointer<CChar>?) throws {
        self.pointer = try #require(pointer)
    }
}

private final class CallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []

    var values: [String] {
        lock.withLock { calls }
    }

    func record(_ call: String) {
        lock.withLock { calls.append(call) }
    }
}

private final class IntentOnlyQuotaRepository: QuotaRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [QuotaRefreshIntent] = []

    var intents: [QuotaRefreshIntent] {
        lock.withLock { calls }
    }

    func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult {
        lock.withLock { calls.append(intent) }
        return .init(snapshots: [:], errors: [:])
    }
}

private func makeCString(_ bytes: [CChar]) -> UnsafePointer<CChar>? {
    let pointer = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count)
    pointer.initialize(from: bytes, count: bytes.count)
    return UnsafePointer(pointer)
}

private func pointerIdentity(_ pointer: UnsafePointer<CChar>) -> UInt {
    UInt(bitPattern: pointer)
}

private func quotaCString(provider: String) -> UnsafePointer<CChar>? {
    let json = """
    {"schemaVersion":"needlbar.v1","ok":true,"generatedAt":"2026-08-25T12:00:00Z","data":{"providers":[{"provider":"\(provider)","windows":[]}]},"errors":[]}
    """
    return makeCString(Array(json.utf8).map(CChar.init) + [0])
}

private func usageCString(provider: String) -> UnsafePointer<CChar>? {
    let json = """
    {"schemaVersion":"needlbar.v1","ok":true,"generatedAt":"2026-08-26T12:00:00Z","data":{"providers":[{"provider":"\(provider)","inputTokens":0,"outputTokens":0,"cacheReadTokens":0,"cacheWriteTokens":0,"totalTokens":0,"estimatedCostUSD":0,"today":{"inputTokens":0,"outputTokens":0,"cacheReadTokens":0,"cacheWriteTokens":0,"totalTokens":0,"estimatedCostUSD":0},"last7Days":{"inputTokens":0,"outputTokens":0,"cacheReadTokens":0,"cacheWriteTokens":0,"totalTokens":0,"estimatedCostUSD":0},"last30Days":{"inputTokens":0,"outputTokens":0,"cacheReadTokens":0,"cacheWriteTokens":0,"totalTokens":0,"estimatedCostUSD":0}}]},"errors":[]}
    """
    return makeCString(Array(json.utf8).map(CChar.init) + [0])
}
