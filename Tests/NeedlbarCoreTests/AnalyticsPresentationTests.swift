import Foundation
import Testing
@testable import NeedlbarCore

private let fixedSeptemberFirst = Date(timeIntervalSince1970: 1_000_000)

private func usage(cost: String = "0") -> AnalyticsUsageAggregate {
    AnalyticsUsageAggregate(
        inputTokens: "0",
        outputTokens: "0",
        cacheReadTokens: "0",
        cacheWriteTokens: "0",
        reasoningTokens: "0",
        totalTokens: "0",
        estimatedCostUSD: cost
    )
}

private func repository(
    id: String = "fixture-repository",
    label: String = "Fixture",
    cost: String = "0",
    activeSeconds: String = "0",
    assignedFragments: UInt64 = 0,
    unassignedFragments: UInt64 = 1,
    timingPartial: Bool = false,
    reasons: [String: UInt64] = [:]
) -> AnalyticsRepositoryAnalytics {
    AnalyticsRepositoryAnalytics(
        repositoryID: id,
        label: label,
        state: "available",
        usage: usage(cost: cost),
        observedActiveTimeSeconds: activeSeconds,
        providerModels: [],
        commits: [],
        coverage: RepositoryCoverage(
            assignedFragments: assignedFragments,
            unassignedFragments: unassignedFragments,
            timingPartial: timingPartial,
            reasons: reasons
        )
    )
}

private func snapshot(
    repositories: [AnalyticsRepositoryAnalytics] = [],
    unattributedCost: String = "0",
    unattributedFragments: UInt64 = 0,
    attributedFragments: UInt64 = 0,
    coverageUnattributedFragments: UInt64? = nil,
    coverageReasons: [String: UInt64] = [:]
) -> AnalyticsSnapshot {
    let end = fixedSeptemberFirst
    return AnalyticsSnapshot(
        schemaVersion: "needlbar.analytics.v1",
        ok: true,
        generatedAt: end,
        analysisRange: AnalyticsDateRange(start: end.addingTimeInterval(-30 * 24 * 60 * 60), end: end),
        repositories: repositories,
        unattributed: AnalyticsAttributionBucket(
            usage: usage(cost: unattributedCost),
            fragments: unattributedFragments,
            reasons: coverageReasons
        ),
        coverage: AnalyticsCoverage(
            attributedFragments: attributedFragments,
            unattributedFragments: coverageUnattributedFragments ?? unattributedFragments,
            reasons: coverageReasons
        ),
        errors: []
    )
}

@Test("empty repositories keep repository cost and observed time unavailable")
func emptyRepositoriesKeepRepositoryCostAndObservedTimeUnavailable() {
    let result = AnalyticsPresentation.summary(for: snapshot(unattributedCost: "99", unattributedFragments: 446))

    #expect(result.repositoryAttributedCostUSD == nil)
    #expect(result.observedAIActivitySeconds == nil)
    #expect(result.repositoryCostIsKnownSubtotal == false)
    #expect(result.linkedRepositoryCount == 0)
    #expect(result.unlinkedFragmentCount == 446)
    #expect(result.eligibleFragmentCount == 446)
}

@Test("valid isolated zero remains a measured repository cost and active time")
func validIsolatedZeroRemainsMeasured() {
    let result = AnalyticsPresentation.summary(
        for: snapshot(
            repositories: [repository(assignedFragments: 1, unassignedFragments: 0)],
            attributedFragments: 1
        )
    )

    #expect(result.repositoryAttributedCostUSD == Decimal.zero)
    #expect(result.observedAIActivitySeconds == 0)
    #expect(result.linkedRepositoryCount == 1)
    #expect(result.unlinkedFragmentCount == 0)
    #expect(result.eligibleFragmentCount == 1)
}

@Test("no retained fragments make the eligible denominator unavailable")
func noRetainedFragmentsMakeEligibleDenominatorUnavailable() {
    let result = AnalyticsPresentation.summary(for: snapshot())

    #expect(result.repositoryAttributedCostUSD == nil)
    #expect(result.observedAIActivitySeconds == nil)
    #expect(result.eligibleFragmentCount == nil)
}

@Test("repository summary excludes unattributed cost and preserves partial pricing subtotal")
func repositorySummaryExcludesUnattributedCostAndPreservesPartialPricingSubtotal() {
    let result = AnalyticsPresentation.summary(
        for: snapshot(
            repositories: [
                repository(id: "repository-one", cost: "1.25", assignedFragments: 2, unassignedFragments: 0),
                repository(
                    id: "repository-two",
                    cost: "2.75",
                    assignedFragments: 3,
                    unassignedFragments: 1,
                    reasons: ["missingCost": 1]
                )
            ],
            unattributedCost: "1000",
            unattributedFragments: 7,
            attributedFragments: 5,
            coverageReasons: ["missingCost": 1]
        )
    )

    #expect(result.repositoryAttributedCostUSD == Decimal(string: "4.00", locale: Locale(identifier: "en_US_POSIX")))
    #expect(result.repositoryCostIsKnownSubtotal)
    #expect(result.observedAIActivitySeconds == 0)
    #expect(result.linkedRepositoryCount == 2)
    #expect(result.unlinkedFragmentCount == 7)
    #expect(result.eligibleFragmentCount == 12)
}

@Test("missing duration does not erase valid zero active time")
func missingDurationDoesNotEraseValidZeroActiveTime() {
    let result = AnalyticsPresentation.summary(
        for: snapshot(
            repositories: [
                repository(
                    activeSeconds: "0",
                    timingPartial: true,
                    reasons: ["missingDuration": 1]
                )
            ],
            attributedFragments: 1
        )
    )

    #expect(result.observedAIActivitySeconds == 0)
}

@Test("time parsing and checked addition return unavailable on malformed or overflowing input")
func timeParsingAndCheckedAdditionReturnUnavailableOnMalformedOrOverflowingInput() {
    let malformed = AnalyticsPresentation.summary(
        for: snapshot(repositories: [repository(activeSeconds: "not-a-number")])
    )
    #expect(malformed.observedAIActivitySeconds == nil)

    let overflowing = AnalyticsPresentation.summary(
        for: snapshot(repositories: [
            repository(id: "max", activeSeconds: String(UInt64.max)),
            repository(id: "one", activeSeconds: "1")
        ])
    )
    #expect(overflowing.observedAIActivitySeconds == nil)
}

@Test("cost parsing and checked decimal addition return unavailable on malformed or precision-losing input")
func costParsingAndCheckedDecimalAdditionReturnUnavailableOnMalformedOrPrecisionLoss() {
    let malformed = AnalyticsPresentation.summary(
        for: snapshot(repositories: [repository(cost: "not-a-cost")])
    )
    #expect(malformed.repositoryAttributedCostUSD == nil)

    let overflowing = AnalyticsPresentation.summary(
        for: snapshot(repositories: [
            repository(id: "large-one", cost: String(repeating: "9", count: 38)),
            repository(id: "fractional", cost: "0.1")
        ])
    )
    #expect(overflowing.repositoryAttributedCostUSD == nil)
}

@Test("eligible fragment denominator is unavailable on checked overflow")
func eligibleFragmentDenominatorIsUnavailableOnCheckedOverflow() {
    let result = AnalyticsPresentation.summary(
        for: snapshot(
            repositories: [repository(assignedFragments: UInt64.max, unassignedFragments: 0)],
            unattributedFragments: 1,
            attributedFragments: UInt64.max,
            coverageUnattributedFragments: 1
        )
    )

    #expect(result.repositoryAttributedCostUSD == Decimal.zero)
    #expect(result.observedAIActivitySeconds == 0)
    #expect(result.linkedRepositoryCount == 1)
    #expect(result.unlinkedFragmentCount == 1)
    #expect(result.eligibleFragmentCount == nil)
}

@Test("diagnostics use stable units and fixed ordering without exposing unknown raw keys")
func diagnosticsUseStableUnitsAndFixedOrderingWithoutExposingUnknownRawKeys() {
    let result = AnalyticsPresentation.diagnostics(
        for: snapshot(
            coverageReasons: [
                "gitUnavailable": 12,
                "unknownRawReason": 999,
                "missingDuration": 434,
                "recordLimitReached": 446,
                "missingTimestamp": 434,
                "missingCost": 2,
                "gitOutputLimitReached": 3,
                "gitTimedOut": 4,
                "pendingCommitWindow": 5
            ]
        )
    )

    #expect(result == [
        AnalyticsDiagnostic(code: "missingTimestamp", count: 434, unit: .fragments),
        AnalyticsDiagnostic(code: "missingCost", count: 2, unit: .fragments),
        AnalyticsDiagnostic(code: "missingDuration", count: 434, unit: .observations),
        AnalyticsDiagnostic(code: "pendingCommitWindow", count: 5, unit: .fragments),
        AnalyticsDiagnostic(code: "recordLimitReached", count: 446, unit: .mixedBoundedProcessing),
        AnalyticsDiagnostic(code: "gitOutputLimitReached", count: 3, unit: .inspectionFailures),
        AnalyticsDiagnostic(code: "gitTimedOut", count: 4, unit: .inspectionFailures),
        AnalyticsDiagnostic(code: "gitUnavailable", count: 12, unit: .inspectionFailures)
    ])
    #expect(result.allSatisfy { $0.code != "unknownRawReason" })
}

@Test("all-unlinked coverage remains fragment diagnostics with separate counts")
func allUnlinkedCoverageRemainsFragmentDiagnosticsWithSeparateCounts() {
    let source = snapshot(
        unattributedFragments: 446,
        attributedFragments: 0,
        coverageReasons: ["missingTimestamp": 434, "repositoryUnavailable": 12]
    )

    let summary = AnalyticsPresentation.summary(for: source)
    let diagnostics = AnalyticsPresentation.diagnostics(for: source)

    #expect(summary.repositoryAttributedCostUSD == nil)
    #expect(summary.observedAIActivitySeconds == nil)
    #expect(summary.linkedRepositoryCount == 0)
    #expect(summary.unlinkedFragmentCount == 446)
    #expect(summary.eligibleFragmentCount == 446)
    #expect(diagnostics == [
        AnalyticsDiagnostic(code: "repositoryUnavailable", count: 12, unit: .fragments),
        AnalyticsDiagnostic(code: "missingTimestamp", count: 434, unit: .fragments)
    ])
}

@Test("large counts and long labels do not change semantic projection")
func largeCountsAndLongLabelsDoNotChangeSemanticProjection() {
    let result = AnalyticsPresentation.summary(
        for: snapshot(
            repositories: [repository(
                label: String(repeating: "long-label-", count: 100),
                cost: "0",
                activeSeconds: String(UInt64.max),
                assignedFragments: UInt64.max,
                unassignedFragments: 0
            )],
            unattributedFragments: UInt64.max,
            attributedFragments: UInt64.max,
            coverageUnattributedFragments: UInt64.max
        )
    )

    #expect(result.repositoryAttributedCostUSD == Decimal.zero)
    #expect(result.observedAIActivitySeconds == UInt64.max)
    #expect(result.linkedRepositoryCount == 1)
    #expect(result.unlinkedFragmentCount == UInt64.max)
    #expect(result.eligibleFragmentCount == nil)
}
