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

private final class FreeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var releases = 0

    var count: Int {
        lock.withLock { releases }
    }

    func release(_ pointer: UnsafePointer<CChar>?) {
        lock.withLock { releases += 1 }
        guard let pointer else { return }
        UnsafeMutablePointer(mutating: pointer).deallocate()
    }
}

private func makeCString(_ bytes: [CChar]) -> UnsafePointer<CChar>? {
    let pointer = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count)
    pointer.initialize(from: bytes, count: bytes.count)
    return UnsafePointer(pointer)
}
