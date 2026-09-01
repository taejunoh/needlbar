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
      "commits":[{"commitID":"abcdef012345","committedAt":"2026-09-01T10:00:00.000Z","correlatedUsage":{"inputTokens":"10","outputTokens":"20","cacheReadTokens":"30","cacheWriteTokens":"40","reasoningTokens":"5","totalTokens":"105","estimatedCostUSD":"1.25"},"pullRequestNumber":42,"coverage":"correlated"}],
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

private let minimalAnalyticsFixture = """
{"schemaVersion":"needlbar.analytics.v1","ok":true,"generatedAt":"2026-09-01T12:00:00.000Z","data":{"analysisRange":{"start":"2026-08-02T12:00:00.000Z","end":"2026-09-01T12:00:00.000Z"},"repositories":[],"unattributed":{"usage":{"inputTokens":"0","outputTokens":"0","cacheReadTokens":"0","cacheWriteTokens":"0","reasoningTokens":"0","totalTokens":"0","estimatedCostUSD":"0"},"fragments":0,"reasons":{}},"coverage":{"attributedFragments":0,"unattributedFragments":0,"reasons":{}},"errors":[]},"errors":[]}
"""

private let minimalRepositoryFixture = """
{"schemaVersion":"needlbar.analytics.v1","ok":true,"generatedAt":"2026-09-01T12:00:00.000Z","data":{"analysisRange":{"start":"2026-08-02T12:00:00.000Z","end":"2026-09-01T12:00:00.000Z"},"repositories":[{"repositoryID":"r00000001","label":"repo","state":"available","usage":{"inputTokens":"0","outputTokens":"0","cacheReadTokens":"0","cacheWriteTokens":"0","reasoningTokens":"0","totalTokens":"0","estimatedCostUSD":"0"},"observedActiveTimeSeconds":"0","providerModels":[],"commits":[],"coverage":{"assignedFragments":0,"unassignedFragments":0,"timingPartial":false,"reasons":{}}}],"unattributed":{"usage":{"inputTokens":"0","outputTokens":"0","cacheReadTokens":"0","cacheWriteTokens":"0","reasoningTokens":"0","totalTokens":"0","estimatedCostUSD":"0"},"fragments":0,"reasons":{}},"coverage":{"attributedFragments":0,"unattributedFragments":0,"reasons":{}},"errors":[]},"errors":[]}
"""

private let repositoryOneJSON = "{\"repositoryID\":\"r00000001\",\"label\":\"one\",\"state\":\"available\",\"usage\":{\"inputTokens\":\"0\",\"outputTokens\":\"0\",\"cacheReadTokens\":\"0\",\"cacheWriteTokens\":\"0\",\"reasoningTokens\":\"0\",\"totalTokens\":\"0\",\"estimatedCostUSD\":\"2\"},\"observedActiveTimeSeconds\":\"0\",\"providerModels\":[],\"commits\":[],\"coverage\":{\"assignedFragments\":0,\"unassignedFragments\":0,\"timingPartial\":false,\"reasons\":{}}}"
private let repositoryTwoJSON = "{\"repositoryID\":\"r00000002\",\"label\":\"two\",\"state\":\"available\",\"usage\":{\"inputTokens\":\"0\",\"outputTokens\":\"0\",\"cacheReadTokens\":\"0\",\"cacheWriteTokens\":\"0\",\"reasoningTokens\":\"0\",\"totalTokens\":\"0\",\"estimatedCostUSD\":\"1\"},\"observedActiveTimeSeconds\":\"0\",\"providerModels\":[],\"commits\":[],\"coverage\":{\"assignedFragments\":0,\"unassignedFragments\":0,\"timingPartial\":false,\"reasons\":{}}}"
private let correlatedCommitJSON = "{\"commitID\":\"abcdef012345\",\"committedAt\":\"2026-09-01T10:00:00.000Z\",\"correlatedUsage\":{\"inputTokens\":\"0\",\"outputTokens\":\"0\",\"cacheReadTokens\":\"0\",\"cacheWriteTokens\":\"0\",\"reasoningTokens\":\"0\",\"totalTokens\":\"0\",\"estimatedCostUSD\":\"0\"},\"pullRequestNumber\":null,\"coverage\":\"correlated\"}"
private let providerModelJSON = "{\"provider\":\"claude\",\"model\":\"claude-3-5-sonnet\",\"usage\":{\"inputTokens\":\"0\",\"outputTokens\":\"0\",\"cacheReadTokens\":\"0\",\"cacheWriteTokens\":\"0\",\"reasoningTokens\":\"0\",\"totalTokens\":\"0\",\"estimatedCostUSD\":\"0\"},\"costPer1KTokens\":null,\"tokensPerObservedActiveHour\":null,\"millisecondsPer1KTokens\":null,\"costCoverage\":\"complete\",\"timingCoverage\":\"missingDuration\"}"

private func replaceFirst(_ source: String, _ needle: String, _ replacement: String) -> String {
    guard let range = source.range(of: needle) else { return source }
    return source.replacingCharacters(in: range, with: replacement)
}

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

@Test func acceptsAtMostThirtyEightSignificantCostDigits() throws {
    let accepted = String(repeating: "9", count: 38)
    let acceptedReplacement = "\"estimatedCostUSD\":\"\(accepted)\""
    _ = try AnalyticsBridgeDecoder().decodeSnapshot(analyticsData(analyticsFixture.replacingOccurrences(of: "\"estimatedCostUSD\":\"1.25\"", with: acceptedReplacement)))

    let rejected = String(repeating: "9", count: 39)
    let rejectedReplacement = "\"estimatedCostUSD\":\"\(rejected)\""
    #expect(throws: Error.self) {
        _ = try AnalyticsBridgeDecoder().decodeSnapshot(analyticsData(analyticsFixture.replacingOccurrences(of: "\"estimatedCostUSD\":\"1.25\"", with: rejectedReplacement)))
    }
}

@Test func acceptsTheFixedRecordLimitCoverageReason() throws {
    let partial = analyticsFixture
        .replacingOccurrences(of: "\"coverage\":{\"attributedFragments\":1,\"unattributedFragments\":0,\"reasons\":{}}", with: "\"coverage\":{\"attributedFragments\":1,\"unattributedFragments\":0,\"reasons\":{\"recordLimitReached\":1}}")
        .replacingOccurrences(of: "    \"errors\":[]\n  },", with: "    \"errors\":[{\"scope\":\"analytics\",\"code\":\"recordLimitReached\"}]\n  },")
    let snapshot = try AnalyticsBridgeDecoder().decodeSnapshot(analyticsData(partial))
    #expect(snapshot.coverage.reasons["recordLimitReached"] == 1)
    #expect(snapshot.errors.contains(.init(scope: "analytics", code: "recordLimitReached")))
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

@Test func acceptsEveryCoverageValueProducedByRustAndRejectsUnknownValues() throws {
    for value in ["complete", "partial", "none"] {
        let changed = analyticsFixture.replacingOccurrences(of: "\"costCoverage\":\"complete\"", with: "\"costCoverage\":\"\(value)\"")
        _ = try AnalyticsBridgeDecoder().decodeSnapshot(analyticsData(changed))
    }
    for value in ["complete", "partial", "missingDuration"] {
        let changed = analyticsFixture.replacingOccurrences(of: "\"timingCoverage\":\"partial\"", with: "\"timingCoverage\":\"\(value)\"")
        _ = try AnalyticsBridgeDecoder().decodeSnapshot(analyticsData(changed))
    }
    for value in ["correlated", "partial"] {
        let changed = analyticsFixture.replacingOccurrences(of: "\"coverage\":\"correlated\"", with: "\"coverage\":\"\(value)\"")
        _ = try AnalyticsBridgeDecoder().decodeSnapshot(analyticsData(changed))
    }
    for mutation in [
        ("\"costCoverage\":\"complete\"", "\"costCoverage\":\"unknown\""),
        ("\"timingCoverage\":\"partial\"", "\"timingCoverage\":\"unknown\""),
        ("\"coverage\":\"correlated\"", "\"coverage\":\"complete\"")
    ] {
        #expect(throws: Error.self) { _ = try AnalyticsBridgeDecoder().decodeSnapshot(analyticsData(analyticsFixture.replacingOccurrences(of: mutation.0, with: mutation.1))) }
    }
}

@Test func rejectsWrongTypesForRequiredArraysAndUnicodeC1Label() {
    #expect(throws: Error.self) { _ = try AnalyticsBridgeDecoder().decodeSnapshot(analyticsData(minimalAnalyticsFixture.replacingOccurrences(of: "\"repositories\":[]", with: "\"repositories\":{}"))) }
    #expect(throws: Error.self) { _ = try AnalyticsBridgeDecoder().decodeSnapshot(analyticsData(minimalRepositoryFixture.replacingOccurrences(of: "\"providerModels\":[]", with: "\"providerModels\":{}"))) }
    #expect(throws: Error.self) { _ = try AnalyticsBridgeDecoder().decodeSnapshot(analyticsData(minimalRepositoryFixture.replacingOccurrences(of: "\"commits\":[]", with: "\"commits\":{}"))) }
    let c1Label = analyticsFixture.replacingOccurrences(of: "\"label\":\"needlbar\"", with: "\"label\":\"repo\u{0085}name\"")
    #expect(throws: Error.self) { _ = try AnalyticsBridgeDecoder().decodeSnapshot(analyticsData(c1Label)) }
}

@Test func rejectsReversedRepositoryCostIDOrderAndDuplicateCommitID() throws {
    let sorted = minimalAnalyticsFixture.replacingOccurrences(of: "\"repositories\":[]", with: "\"repositories\":[\(repositoryOneJSON),\(repositoryTwoJSON)]")
    _ = try AnalyticsBridgeDecoder().decodeSnapshot(analyticsData(sorted))
    let reversed = minimalAnalyticsFixture.replacingOccurrences(of: "\"repositories\":[]", with: "\"repositories\":[\(repositoryTwoJSON),\(repositoryOneJSON)]")
    #expect(throws: Error.self) { _ = try AnalyticsBridgeDecoder().decodeSnapshot(analyticsData(reversed)) }
    let duplicate = minimalRepositoryFixture.replacingOccurrences(of: "\"commits\":[]", with: "\"commits\":[\(correlatedCommitJSON),\(correlatedCommitJSON)]")
    #expect(throws: Error.self) { _ = try AnalyticsBridgeDecoder().decodeSnapshot(analyticsData(duplicate)) }
}

@Test func acceptsValidGregorianLeapDateAndRejectsNormalizedOrImpossibleUTCDate() throws {
    let leap = minimalAnalyticsFixture
        .replacingOccurrences(of: "2026-09-01T12:00:00.000Z", with: "2028-02-29T12:00:00.000Z")
        .replacingOccurrences(of: "2026-08-02T12:00:00.000Z", with: "2028-01-30T12:00:00.000Z")
    _ = try AnalyticsBridgeDecoder().decodeSnapshot(analyticsData(leap))
    for invalid in ["2026-02-29T12:00:00.000Z", "2026-09-01T24:00:00.000Z", "2026-13-01T12:00:00.000Z", "2026-09-00T12:00:00.000Z", "2026-09-32T12:00:00.000Z"] {
        let changed = minimalAnalyticsFixture.replacingOccurrences(of: "2026-09-01T12:00:00.000Z", with: invalid)
        #expect(throws: Error.self) { _ = try AnalyticsBridgeDecoder().decodeSnapshot(analyticsData(changed)) }
    }
    let invalidCommit = analyticsFixture.replacingOccurrences(of: "2026-09-01T10:00:00.000Z", with: "2026-02-29T10:00:00.000Z")
    #expect(throws: Error.self) { _ = try AnalyticsBridgeDecoder().decodeSnapshot(analyticsData(invalidCommit)) }
}

@Test func rejectsDuplicateProviderModelAndErrorRows() {
    let duplicateModels = minimalRepositoryFixture.replacingOccurrences(of: "\"providerModels\":[]", with: "\"providerModels\":[\(providerModelJSON),\(providerModelJSON)]")
    #expect(throws: Error.self) { _ = try AnalyticsBridgeDecoder().decodeSnapshot(analyticsData(duplicateModels)) }
    let duplicateError = "{\"scope\":\"analytics\",\"code\":\"internalError\"}"
    let duplicateErrors = replaceFirst(minimalAnalyticsFixture, "\"errors\":[]", "\"errors\":[\(duplicateError),\(duplicateError)]")
    #expect(throws: Error.self) { _ = try AnalyticsBridgeDecoder().decodeSnapshot(analyticsData(duplicateErrors)) }
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
