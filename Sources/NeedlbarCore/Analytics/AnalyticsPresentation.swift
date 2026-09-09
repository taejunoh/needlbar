import Foundation

public enum AnalyticsDiagnosticUnit: Sendable, Equatable {
    case fragments
    case observations
    case inspectionFailures
    case mixedBoundedProcessing
}

public struct AnalyticsPresentationSummary: Sendable, Equatable {
    public let repositoryAttributedCostUSD: Decimal?
    public let repositoryCostIsKnownSubtotal: Bool
    public let observedAIActivitySeconds: UInt64?
    public let linkedRepositoryCount: UInt64
    public let unlinkedFragmentCount: UInt64
    public let eligibleFragmentCount: UInt64?
    public let unattributedTimestampCoverageIsIncomplete: Bool

    public init(
        repositoryAttributedCostUSD: Decimal?,
        repositoryCostIsKnownSubtotal: Bool,
        observedAIActivitySeconds: UInt64?,
        linkedRepositoryCount: UInt64,
        unlinkedFragmentCount: UInt64,
        eligibleFragmentCount: UInt64?,
        unattributedTimestampCoverageIsIncomplete: Bool
    ) {
        self.repositoryAttributedCostUSD = repositoryAttributedCostUSD
        self.repositoryCostIsKnownSubtotal = repositoryCostIsKnownSubtotal
        self.observedAIActivitySeconds = observedAIActivitySeconds
        self.linkedRepositoryCount = linkedRepositoryCount
        self.unlinkedFragmentCount = unlinkedFragmentCount
        self.eligibleFragmentCount = eligibleFragmentCount
        self.unattributedTimestampCoverageIsIncomplete = unattributedTimestampCoverageIsIncomplete
    }
}

public struct AnalyticsPresentationDiagnostic: Sendable, Equatable {
    public let code: String
    public let count: UInt64
    public let unit: AnalyticsDiagnosticUnit

    public init(code: String, count: UInt64, unit: AnalyticsDiagnosticUnit) {
        self.code = code
        self.count = count
        self.unit = unit
    }
}

public enum AnalyticsPresentation {
    public typealias Summary = AnalyticsPresentationSummary
    public typealias Diagnostic = AnalyticsPresentationDiagnostic

    private static let diagnosticOrder = [
        "missingWorkspace",
        "invalidWorkspace",
        "nonRepositoryWorkspace",
        "ambiguousRepository",
        "repositoryUnavailable",
        "missingTimestamp",
        "missingCost",
        "missingDuration",
        "noEligibleCommit",
        "pendingCommitWindow",
        "recordLimitReached",
        "gitOutputLimitReached",
        "gitTimedOut",
        "gitUnavailable"
    ]

    public static func summary(for snapshot: AnalyticsSnapshot) -> AnalyticsPresentationSummary {
        let repositories = snapshot.repositories
        let cost = repositories.isEmpty ? nil : repositoryCost(for: repositories)
        let activeTime = repositories.isEmpty ? nil : observedActiveTime(for: repositories)
        let eligibleFragments = snapshot.coverage.attributedFragments.addingReportingOverflow(
            snapshot.coverage.unattributedFragments
        )
        let eligibleFragmentCount = eligibleFragments.overflow || eligibleFragments.partialValue == 0
            ? nil
            : eligibleFragments.partialValue

        return AnalyticsPresentationSummary(
            repositoryAttributedCostUSD: cost,
            repositoryCostIsKnownSubtotal: hasPartialRepositoryCost(snapshot),
            observedAIActivitySeconds: activeTime,
            linkedRepositoryCount: UInt64(repositories.count),
            unlinkedFragmentCount: snapshot.unattributed.fragments,
            eligibleFragmentCount: eligibleFragmentCount,
            unattributedTimestampCoverageIsIncomplete: snapshot.coverage.reasons["missingTimestamp", default: 0] > 0
        )
    }

    public static func diagnostics(for snapshot: AnalyticsSnapshot) -> [AnalyticsPresentationDiagnostic] {
        diagnosticOrder.compactMap { code in
            guard let count = snapshot.coverage.reasons[code] else { return nil }
            return AnalyticsPresentationDiagnostic(code: code, count: count, unit: diagnosticUnit(for: code))
        }
    }

    private static func repositoryCost(for repositories: [AnalyticsRepositoryAnalytics]) -> Decimal? {
        var total = Decimal.zero
        for repository in repositories {
            guard var cost = repository.usage.estimatedCostUSDValue else { return nil }
            var next = Decimal.zero
            guard NSDecimalAdd(&next, &total, &cost, .plain) == .noError else { return nil }
            total = next
        }
        return total
    }

    private static func observedActiveTime(for repositories: [AnalyticsRepositoryAnalytics]) -> UInt64? {
        var total: UInt64 = 0
        for repository in repositories {
            guard let seconds = UInt64(repository.observedActiveTimeSeconds) else { return nil }
            let result = total.addingReportingOverflow(seconds)
            guard !result.overflow else { return nil }
            total = result.partialValue
        }
        return total
    }

    private static func hasPartialRepositoryCost(_ snapshot: AnalyticsSnapshot) -> Bool {
        snapshot.coverage.reasons["missingCost"] != nil ||
            snapshot.coverage.reasons["recordLimitReached"] != nil ||
            snapshot.coverage.reasons["gitOutputLimitReached"] != nil ||
            snapshot.repositories.contains { $0.coverage.reasons["missingCost"] != nil }
    }

    private static func diagnosticUnit(for code: String) -> AnalyticsDiagnosticUnit {
        switch code {
        case "missingDuration": .observations
        case "recordLimitReached": .mixedBoundedProcessing
        case "gitOutputLimitReached", "gitTimedOut", "gitUnavailable": .inspectionFailures
        default: .fragments
        }
    }
}
