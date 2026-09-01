import Foundation
import Testing
@testable import NeedlbarCore

private let analyticsFixture = """
{
  "schemaVersion":"needlbar.analytics.v1",
  "ok":true,
  "generatedAt":"2026-09-01T12:00:00.000Z",
  "data":{
    "analysisRange":{"start":"2026-08-02T12:00:00.000Z","end":"2026-09-01T12:00:00.000Z"},
    "repositories":[{
      "repositoryID":"r00000001","label":"needlbar","state":"available",
      "usage":{"inputTokens":"10","outputTokens":"20","cacheReadTokens":"30","cacheWriteTokens":"40","reasoningTokens":"5","totalTokens":"105","estimatedCostUSD":"1.25"},
      "observedActiveTimeSeconds":"60",
      "providerModels":[{"provider":"claude","model":"claude-3-5-sonnet","usage":{"inputTokens":"10","outputTokens":"20","cacheReadTokens":"30","cacheWriteTokens":"40","reasoningTokens":"5","totalTokens":"105","estimatedCostUSD":"1.25"},"costPer1KTokens":"11.9047619","tokensPerObservedActiveHour":"6300","millisecondsPer1KTokens":null,"costCoverage":"complete","timingCoverage":"partial"}],
      "commits":[{"commitID":"abcdef012345","committedAt":"2026-09-01T10:00:00.000Z","correlatedUsage":{"inputTokens":"10","outputTokens":"20","cacheReadTokens":"30","cacheWriteTokens":"40","reasoningTokens":"5","totalTokens":"105","estimatedCostUSD":"1.25"},"pullRequestNumber":42,"coverage":"complete"}],
      "coverage":{"assignedFragments":1,"unassignedFragments":0,"timingPartial":false,"reasons":{}}
    }],
    "unattributed":{"usage":{"inputTokens":"0","outputTokens":"0","cacheReadTokens":"0","cacheWriteTokens":"0","reasoningTokens":"0","totalTokens":"0","estimatedCostUSD":"0"},"fragments":0,"reasons":{}},
    "coverage":{"attributedFragments":1,"unattributedFragments":0,"reasons":{}},
    "errors":[]
  },
  "errors":[]
}
"""

private func analyticsData(_ text: String = analyticsFixture) -> Data { Data(text.utf8) }

private final class AnalyticsFreeRecorder: @unchecked Sendable {
    private let lock = NSLock(); private(set) var count = 0
    func release(_ pointer: UnsafePointer<CChar>?) { lock.lock(); count += 1; lock.unlock(); pointer?.deallocate() }
}

private final class AnalyticsCStringPointer: @unchecked Sendable {
    let pointer: UnsafePointer<CChar>
    init(_ string: String) throws {
        guard let pointer = strdup(string) else { throw NSError(domain: "analytics", code: 1) }
        self.pointer = UnsafePointer(pointer)
    }
}

private final class AnalyticsRawPointer: @unchecked Sendable {
    let pointer: UnsafePointer<CChar>
    init(_ bytes: [CChar]) {
        let value = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count)
        for (index, byte) in bytes.enumerated() { value[index] = byte }
        pointer = UnsafePointer(value)
    }
}

@Test func decodesPopulatedAnalyticsEnvelopeAndPreservesCanonicalNumbers() throws {
    let snapshot = try AnalyticsBridgeDecoder().decodeSnapshot(analyticsData())
    #expect(snapshot.schemaVersion == "needlbar.analytics.v1")
    #expect(snapshot.ok)
    #expect(snapshot.analysisRange.end == snapshot.generatedAt)
    #expect(snapshot.analysisRange.start.timeIntervalSince(snapshot.generatedAt) == -30 * 24 * 60 * 60)
    #expect(snapshot.repositories.first?.usage.estimatedCostUSD == "1.25")
    #expect(snapshot.repositories.first?.usage.totalTokensValue == 105)
    #expect(snapshot.repositories.first?.providerModels.first?.millisecondsPer1KTokens == nil)
    #expect(snapshot.repositories.first?.commits.first?.commitID == "abcdef012345")
}

@Test func rejectsUnknownSchemaAndInvalidEnvelopeConsistency() {
    #expect(throws: Error.self) { _ = try AnalyticsBridgeDecoder().decodeSnapshot(analyticsData(analyticsFixture.replacingOccurrences(of: "needlbar.analytics.v1", with: "needlbar.v2"))) }
    #expect(throws: Error.self) { _ = try AnalyticsBridgeDecoder().decodeSnapshot(analyticsData(analyticsFixture.replacingOccurrences(of: "\"ok\":true", with: "\"ok\":false"))) }
}

@Test func rejectsNonCanonicalNumbersAndInvalidTimestampOrCommitID() {
    for replacement in [
        ("\"inputTokens\":\"10\"", "\"inputTokens\":\"010\""),
        ("\"estimatedCostUSD\":\"1.25\"", "\"estimatedCostUSD\":\"1.250\""),
        ("\"estimatedCostUSD\":\"1.25\"", "\"estimatedCostUSD\":\"1e0\""),
        ("2026-09-01T10:00:00.000Z", "2026-09-01T10:00:00Z"),
        ("abcdef012345", "ABCDEF012345")
    ] {
        #expect(throws: Error.self) { _ = try AnalyticsBridgeDecoder().decodeSnapshot(analyticsData(analyticsFixture.replacingOccurrences(of: replacement.0, with: replacement.1))) }
    }
}

@Test func rejectsUnknownScopeProviderStateCoverageOrderingAndDuplicateCommit() {
    let replacements = [
        ("\"errors\":[]", "\"errors\":[{\"scope\":\"future\",\"code\":\"x\"}]"),
        ("\"provider\":\"claude\"", "\"provider\":\"future\""),
        ("\"state\":\"available\"", "\"state\":\"future\""),
        ("\"costCoverage\":\"complete\"", "\"costCoverage\":\"future\""),
        ("\"commitID\":\"abcdef012345\"", "\"commitID\":\"abcdef012345\",\"extra\":true")
    ]
    for replacement in replacements {
        #expect(throws: Error.self) { _ = try AnalyticsBridgeDecoder().decodeSnapshot(analyticsData(analyticsFixture.replacingOccurrences(of: replacement.0, with: replacement.1))) }
    }
}

@Test func rejectsControlLabelAndOversizedDocument() {
    let control = analyticsFixture.replacingOccurrences(of: "needlbar", with: "need\u{0001}bar")
    #expect(throws: Error.self) { _ = try AnalyticsBridgeDecoder().decodeSnapshot(analyticsData(control)) }
    #expect(throws: Error.self) { _ = try AnalyticsBridgeDecoder().decodeSnapshot(Data(repeating: 0x20, count: 256 * 1024 + 1)) }
}

@Test func rustBridgeAnalyticsCallFreesInvalidUTF8AndDecoderFailureExactlyOnce() throws {
    let recorder = AnalyticsFreeRecorder()
    let invalid = AnalyticsRawPointer([-1, 0])
    let bridge = RustBridge(analyticsCall: { invalid.pointer }, free: { recorder.release($0) })
    #expect(throws: BridgeFailure.invalidUTF8) { _ = try bridge.analyticsEnvelope() }
    #expect(recorder.count == 1)

    let malformed = try AnalyticsCStringPointer("{")
    let second = AnalyticsFreeRecorder()
    let malformedBridge = RustBridge(analyticsCall: { malformed.pointer }, free: { second.release($0) })
    #expect(throws: Error.self) { _ = try malformedBridge.analyticsEnvelope() }
    #expect(second.count == 1)
}
