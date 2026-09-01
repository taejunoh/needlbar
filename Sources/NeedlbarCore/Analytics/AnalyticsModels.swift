import Foundation

public struct AnalyticsDateRange: Sendable, Equatable {
    public let start: Date
    public let end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = end }
}

public struct AnalyticsUsageAggregate: Sendable, Equatable {
    public let inputTokens: String
    public let outputTokens: String
    public let cacheReadTokens: String
    public let cacheWriteTokens: String
    public let reasoningTokens: String
    public let totalTokens: String
    public let estimatedCostUSD: String

    public init(inputTokens: String, outputTokens: String, cacheReadTokens: String, cacheWriteTokens: String,
                reasoningTokens: String, totalTokens: String, estimatedCostUSD: String) {
        self.inputTokens = inputTokens; self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens; self.cacheWriteTokens = cacheWriteTokens
        self.reasoningTokens = reasoningTokens; self.totalTokens = totalTokens
        self.estimatedCostUSD = estimatedCostUSD
    }

    public var inputTokensValue: UInt64? { UInt64(inputTokens) }
    public var outputTokensValue: UInt64? { UInt64(outputTokens) }
    public var cacheReadTokensValue: UInt64? { UInt64(cacheReadTokens) }
    public var cacheWriteTokensValue: UInt64? { UInt64(cacheWriteTokens) }
    public var reasoningTokensValue: UInt64? { UInt64(reasoningTokens) }
    public var totalTokensValue: UInt64? { UInt64(totalTokens) }
    public var estimatedCostUSDValue: Decimal? { Decimal(string: estimatedCostUSD, locale: Locale(identifier: "en_US_POSIX")) }
}

public struct AnalyticsProviderModelAnalytics: Sendable, Equatable {
    public let provider: String
    public let model: String
    public let usage: AnalyticsUsageAggregate
    public let costPer1KTokens: String?
    public let tokensPerObservedActiveHour: String?
    public let millisecondsPer1KTokens: String?
    public let costCoverage: String
    public let timingCoverage: String
    public init(provider: String, model: String, usage: AnalyticsUsageAggregate, costPer1KTokens: String?,
                tokensPerObservedActiveHour: String?, millisecondsPer1KTokens: String?, costCoverage: String,
                timingCoverage: String) {
        self.provider = provider; self.model = model; self.usage = usage
        self.costPer1KTokens = costPer1KTokens; self.tokensPerObservedActiveHour = tokensPerObservedActiveHour
        self.millisecondsPer1KTokens = millisecondsPer1KTokens; self.costCoverage = costCoverage
        self.timingCoverage = timingCoverage
    }
}

public struct AnalyticsCommitAnalytics: Sendable, Equatable {
    public let commitID: String
    public let committedAt: Date
    public let correlatedUsage: AnalyticsUsageAggregate
    public let pullRequestNumber: Int?
    public let coverage: String
    public init(commitID: String, committedAt: Date, correlatedUsage: AnalyticsUsageAggregate,
                pullRequestNumber: Int?, coverage: String) {
        self.commitID = commitID; self.committedAt = committedAt; self.correlatedUsage = correlatedUsage
        self.pullRequestNumber = pullRequestNumber; self.coverage = coverage
    }
}

public struct AnalyticsCoverage: Sendable, Equatable {
    public let attributedFragments: UInt64
    public let unattributedFragments: UInt64
    public let reasons: [String: UInt64]
    public init(attributedFragments: UInt64, unattributedFragments: UInt64, reasons: [String: UInt64]) {
        self.attributedFragments = attributedFragments; self.unattributedFragments = unattributedFragments; self.reasons = reasons
    }
}

public struct RepositoryCoverage: Sendable, Equatable {
    public let assignedFragments: UInt64
    public let unassignedFragments: UInt64
    public let timingPartial: Bool
    public let reasons: [String: UInt64]
    public init(assignedFragments: UInt64, unassignedFragments: UInt64, timingPartial: Bool, reasons: [String: UInt64]) {
        self.assignedFragments = assignedFragments; self.unassignedFragments = unassignedFragments
        self.timingPartial = timingPartial; self.reasons = reasons
    }
}

public struct AnalyticsAttributionBucket: Sendable, Equatable {
    public let usage: AnalyticsUsageAggregate
    public let fragments: UInt64
    public let reasons: [String: UInt64]
    public init(usage: AnalyticsUsageAggregate, fragments: UInt64, reasons: [String: UInt64]) {
        self.usage = usage; self.fragments = fragments; self.reasons = reasons
    }
}

public struct AnalyticsBridgeError: Sendable, Equatable {
    public let scope: String
    public let code: String
    public init(scope: String, code: String) { self.scope = scope; self.code = code }
}

public struct AnalyticsRepositoryAnalytics: Sendable, Equatable {
    public let repositoryID: String
    public let label: String
    public let state: String
    public let usage: AnalyticsUsageAggregate
    public let observedActiveTimeSeconds: String
    public let providerModels: [AnalyticsProviderModelAnalytics]
    public let commits: [AnalyticsCommitAnalytics]
    public let coverage: RepositoryCoverage
    public init(repositoryID: String, label: String, state: String, usage: AnalyticsUsageAggregate,
                observedActiveTimeSeconds: String, providerModels: [AnalyticsProviderModelAnalytics],
                commits: [AnalyticsCommitAnalytics], coverage: RepositoryCoverage) {
        self.repositoryID = repositoryID; self.label = label; self.state = state; self.usage = usage
        self.observedActiveTimeSeconds = observedActiveTimeSeconds; self.providerModels = providerModels
        self.commits = commits; self.coverage = coverage
    }
    public var observedActiveTimeSecondsValue: UInt64? { UInt64(observedActiveTimeSeconds) }
}

public struct AnalyticsSnapshot: Sendable, Equatable {
    public let schemaVersion: String
    public let ok: Bool
    public let generatedAt: Date
    public let analysisRange: AnalyticsDateRange
    public let repositories: [AnalyticsRepositoryAnalytics]
    public let unattributed: AnalyticsAttributionBucket
    public let coverage: AnalyticsCoverage
    public let errors: [AnalyticsBridgeError]
    public init(schemaVersion: String, ok: Bool, generatedAt: Date, analysisRange: AnalyticsDateRange,
                repositories: [AnalyticsRepositoryAnalytics], unattributed: AnalyticsAttributionBucket,
                coverage: AnalyticsCoverage, errors: [AnalyticsBridgeError]) {
        self.schemaVersion = schemaVersion; self.ok = ok; self.generatedAt = generatedAt; self.analysisRange = analysisRange
        self.repositories = repositories; self.unattributed = unattributed; self.coverage = coverage; self.errors = errors
    }
}

public enum AnalyticsRefreshState: Sendable, Equatable {
    case idle
    case loading
    case fresh(AnalyticsSnapshot)
    case stale(AnalyticsSnapshot)
    case unavailable
}

enum AnalyticsDecodeSupport {
    static let schema = "needlbar.analytics.v1"
    static let scopes: Set<String> = ["usage", "repository", "git", "analytics"]
    static let providers: Set<String> = ["claude", "codex", "cursor"]
    static let states: Set<String> = ["available", "unavailable"]
    static let coverage: Set<String> = ["complete", "partial", "none"]
    static let reasons: Set<String> = ["missingWorkspace", "invalidWorkspace", "nonRepositoryWorkspace", "ambiguousRepository", "repositoryUnavailable", "missingTimestamp", "missingCost", "missingDuration", "noEligibleCommit", "pendingCommitWindow", "recordLimitReached", "gitOutputLimitReached", "gitTimedOut", "gitUnavailable"]
    static let errorCodes = reasons.union(["internalError", "runtimeUnavailable", "usageReportUnavailable", "payloadTooLarge"])

    static func checkKeys<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ allowed: Set<String>) throws {
        let actual = Set(container.allKeys.map(\.stringValue))
        guard actual == allowed else { throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath, debugDescription: "Unknown or missing analytics field.")) }
    }
    static func canonicalInteger(_ value: String) -> UInt64? {
        guard value == "0" || (value.first.map { ("1"..."9").contains(String($0)) } == true && value.allSatisfy(\.isNumber)) else { return nil }
        return UInt64(value)
    }
    static func canonicalCost(_ value: String) -> Decimal? {
        guard value.range(of: #"^(0|[1-9][0-9]*)(\.[0-9]*[1-9])?$"#, options: .regularExpression) != nil else { return nil }
        let digits = value.filter(\.isNumber)
        let significantDigits = digits.drop(while: { $0 == "0" })
        guard significantDigits.count <= 38 else { return nil }
        return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }
    static func fail(_ path: [CodingKey], _ message: String) -> DecodingError { .dataCorrupted(.init(codingPath: path, debugDescription: message)) }
}
