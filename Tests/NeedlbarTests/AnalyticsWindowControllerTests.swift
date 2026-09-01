import AppKit
import Foundation
import Testing
import SwiftUI
@testable import NeedlbarApp
@testable import NeedlbarCore

@Suite("AnalyticsWindowControllerTests", .serialized)
@MainActor
struct AnalyticsWindowControllerTests {
    @Test func createsTheNativeAnalyticsWindowWithStablePresentationContract() {
        let repository = TestAnalyticsRepository()
        let controller = AnalyticsWindowController(
            store: AnalyticsSnapshotStore(),
            repository: repository
        )

        let window = controller.window

        #expect(window?.title == "Needlbar Analytics")
        #expect(window?.frame.size == NSSize(width: 760, height: 520))
        #expect(window?.styleMask.contains(.titled) == true)
        #expect(window?.styleMask.contains(.closable) == true)
        #expect(window?.styleMask.contains(.miniaturizable) == true)
        #expect(window?.styleMask.contains(.resizable) == true)
        #expect(window?.isReleasedWhenClosed == false)
        #expect(controller.viewModel.presentationState == .idle)
    }

    @Test func repeatedPresentationReusesTheWindowAndStartsOneInitialRefresh() async {
        let repository = TestAnalyticsRepository()
        let controller = AnalyticsWindowController(
            store: AnalyticsSnapshotStore(),
            repository: repository
        )

        controller.showAnalytics()
        await repository.waitForCall(1)
        let firstWindow = controller.window
        controller.showAnalytics()
        await Task.yield()

        #expect(controller.window === firstWindow)
        #expect(await repository.callCount == 1)

        await repository.completeNext(with: .success(testAnalyticsSnapshot()))
        #expect(await eventually { controller.viewModel.isLoading == false })
    }

    @Test func refreshIsDisabledWhileLoadingAndRunsOnceAfterThePriorCallCompletes() async {
        let repository = TestAnalyticsRepository()
        let controller = AnalyticsWindowController(
            store: AnalyticsSnapshotStore(),
            repository: repository
        )

        controller.showAnalytics()
        await repository.waitForCall(1)
        #expect(controller.viewModel.isLoading)

        controller.refreshAnalytics()
        await Task.yield()
        #expect(await repository.callCount == 1)

        await repository.completeNext(with: .success(testAnalyticsSnapshot()))
        #expect(await eventually { controller.viewModel.isLoading == false })

        controller.refreshAnalytics()
        await repository.waitForCall(2)
        #expect(await repository.callCount == 2)
        await repository.completeNext(with: .success(testAnalyticsSnapshot()))
        #expect(await eventually { controller.viewModel.isLoading == false })
    }

    @Test func closeAndReopenDoesNotStartAnotherInitialRefreshOrDuplicateObservers() async {
        let repository = TestAnalyticsRepository()
        let controller = AnalyticsWindowController(
            store: AnalyticsSnapshotStore(),
            repository: repository
        )

        controller.showAnalytics()
        await repository.waitForCall(1)
        await repository.completeNext(with: .success(testAnalyticsSnapshot()))
        #expect(await eventually { controller.viewModel.isLoading == false })

        controller.window?.close()
        controller.showAnalytics()
        await Task.yield()

        #expect(await repository.callCount == 1)
    }

    @Test func failedRefreshUsesFixedSafeStaleCopyWithoutRawErrorText() async {
        let repository = TestAnalyticsRepository()
        let controller = AnalyticsWindowController(
            store: AnalyticsSnapshotStore(),
            repository: repository
        )

        controller.showAnalytics()
        await repository.waitForCall(1)
        await repository.completeNext(with: .success(testAnalyticsSnapshot()))
        #expect(await eventually { controller.viewModel.isLoading == false })

        controller.refreshAnalytics()
        await repository.waitForCall(2)
        await repository.completeNext(with: .failure(TestAnalyticsError(raw: "/Users/private/.git stderr secret")))
        #expect(await eventually { controller.viewModel.isLoading == false })

        #expect(controller.viewModel.presentationState == .stale)
        #expect(controller.viewModel.statusCopy == "Showing the last successful local analysis. Refresh to try again.")
        #expect(!controller.viewModel.statusCopy.contains("private"))
        #expect(!controller.viewModel.statusCopy.contains("stderr"))
    }

    @Test func displayFormattingKeepsLargeCanonicalNumbersSafeAndMarksMissingMetricsUnavailable() {
        #expect(AnalyticsDisplayFormatter.tokens("1000") == "1K")
        #expect(AnalyticsDisplayFormatter.tokens("18446744073709551615") != "Unavailable")
        #expect(AnalyticsDisplayFormatter.tokens("not-a-number") == "Unavailable")
        #expect(AnalyticsDisplayFormatter.duration(nil) == "Unavailable")
        #expect(AnalyticsDisplayFormatter.metric(nil) == nil)
        #expect(AnalyticsDisplayFormatter.metric("") == nil)
    }

    @Test func unavailableRepositoryGetsExplicitSafeStatePresentation() {
        let snapshot = populatedAnalyticsSnapshot()
        let unavailable = snapshot.repositories.first { $0.state == "unavailable" }

        #expect(unavailable != nil)
        #expect(AnalyticsDisplayFormatter.repositoryState(unavailable?.state) == "Unavailable")
        #expect(AnalyticsDisplayFormatter.repositoryStateCopy(unavailable?.state) == "Git metadata could not be safely read.")
    }

    @Test func partialAnalyticsPresentationExplainsCoverageWithoutRawCodes() {
        let snapshot = populatedAnalyticsSnapshot()
        let repository = snapshot.repositories[0]
        let model = repository.providerModels[0]

        #expect(AnalyticsDisplayFormatter.repositoryCostCoverage(repository.coverage) == "Partial")
        #expect(AnalyticsDisplayFormatter.repositoryTimingCoverage(repository.coverage) == "Missing duration")
        #expect(AnalyticsDisplayFormatter.providerCoverage(model.costCoverage) == "Partial")
        #expect(AnalyticsDisplayFormatter.providerTimingCoverage(model.timingCoverage) == "Missing duration")
        #expect(AnalyticsDisplayFormatter.metric(model.costPer1KTokens) == nil)
        #expect(AnalyticsDisplayFormatter.correlationCoverage(repository.coverage).contains("Assigned 2"))
        #expect(AnalyticsDisplayFormatter.correlationCoverage(repository.coverage).contains("Unassigned 1"))

        let reasons = AnalyticsDisplayFormatter.unattributedReasonCopy(snapshot.unattributed.reasons)
        #expect(reasons.map(\.displayText).contains("Missing workspace (2)"))
        #expect(reasons.map(\.displayText).contains("Pending 4-hour window (1)"))
        #expect(reasons.map(\.displayText).contains("Git timeout (1)"))
        #expect(reasons.map(\.displayText).contains("Record/output limit (3)"))
        #expect(reasons.allSatisfy { !$0.id.contains("raw-canary") && !$0.displayText.contains("gitTimedOut") })
    }

    @Test func aboutEstimatesUsesExactTruthfulTerminology() {
        let copy = AnalyticsDisplayFormatter.aboutEstimates

        #expect(copy.contains("Estimated cost uses local engine pricing and is not an invoice or subscription charge."))
        #expect(copy.contains("Observed active AI-session time uses timestamp gaps no greater than three minutes and is not human coding time, keyboard time, or elapsed wall time."))
        #expect(copy.contains("Correlated estimated AI cost is a deterministic same-repository four-hour association, not causal or measured commit cost."))
        #expect(copy.contains("Coverage indicates eligible workspace, timestamp, pricing, duration, and Git evidence."))
        #expect(copy.contains("A local PR number is metadata-only; it has no remote validation."))
    }

    @Test func populatedPresentationIncludesCorrelationAndSafeGitCopy() {
        let snapshot = populatedAnalyticsSnapshot()
        let repository = snapshot.repositories[0]
        let commit = repository.commits[0]

        #expect(commit.pullRequestNumber == 42)
        #expect(commit.coverage == "partial")
        let gitReasons = AnalyticsDisplayFormatter.gitReasonCopy(repository.coverage.reasons)
        #expect(gitReasons.map(\.displayText).contains("Git timeout (1)"))
        #expect(gitReasons.map(\.displayText).contains("Repository inspection stopped at a safe limit (3)"))
        #expect(AnalyticsDisplayFormatter.repositoryStateCopy(snapshot.repositories[1].state) == "Git metadata could not be safely read.")
    }

    @Test func recordAndOutputLimitReasonsKeepDistinctStableIDs() {
        let reasons = AnalyticsDisplayFormatter.unattributedReasonCopy([
            "recordLimitReached": 2,
            "gitOutputLimitReached": 2,
        ])

        #expect(reasons.count == 2)
        #expect(Set(reasons.map(\.id)) == ["gitOutputLimitReached", "recordLimitReached"])
        #expect(reasons.map(\.displayText) == ["Record/output limit (2)", "Record/output limit (2)"])
    }

    @Test func compactFormattersBoundLongCanonicalValuesAndReuseTheUTCDateFormatter() {
        let longTokens = "12345678901234567890123456789012345678"
        let longCost = "12345678901234567890123456789012345678.99"

        #expect(AnalyticsDisplayFormatter.compactTokens(longTokens).count <= 8)
        #expect(AnalyticsDisplayFormatter.tokensAccessibilityValue(longTokens) == "\(longTokens) tokens")
        #expect(AnalyticsDisplayFormatter.compactCost(longCost).count <= 10)
        #expect(AnalyticsDisplayFormatter.dateFormatterIdentity == AnalyticsDisplayFormatter.dateFormatterIdentity)
        #expect(AnalyticsDisplayFormatter.refreshAccessibilityValue(isLoading: true) == "Loading; Refresh unavailable")
        #expect(AnalyticsDisplayFormatter.refreshAccessibilityValue(isLoading: false) == "Ready")
    }

    @Test func analyticsDisclosuresRemainIndependentlyIdentifiedAndActionable() {
        let labels = AnalyticsDisplayFormatter.disclosureAccessibilityLabels

        #expect(labels.providerAndModel != labels.commits)
        #expect(labels.providerAndModel == "Provider and model metrics")
        #expect(labels.commits == "Commits")
        #expect(AnalyticsDisplayFormatter.disclosureAccessibilityHint == "Expand or collapse this section")
    }

    @Test func modelAccessibilityCopyIncludesEveryVisibleMetricAndUnavailableValues() {
        let model = populatedAnalyticsSnapshot().repositories[0].providerModels[0]
        let copy = AnalyticsDisplayFormatter.modelAccessibilityValue(model)

        #expect(copy.contains("Estimated cost"))
        #expect(copy.contains("Cost coverage Partial"))
        #expect(copy.contains("Timing coverage Missing duration"))
        #expect(copy.contains("Cost per 1K tokens Unavailable"))
        #expect(copy.contains("Tokens per observed active hour Unavailable"))
        #expect(copy.contains("Milliseconds per 1K tokens Unavailable"))
    }

    @Test func maximumSnapshotCanHostAtTheWindowSizeWithoutEagerMaterializationFailure() async {
        let started = ContinuousClock.now
        let snapshot = maximumAnalyticsSnapshot()
        let repository = ImmediateAnalyticsRepository(snapshot: snapshot)
        let viewModel = AnalyticsViewModel(store: AnalyticsSnapshotStore(), repository: repository)
        viewModel.loadIfNeeded()
        #expect(await eventually { viewModel.snapshot != nil })
        let hostingView = NSHostingView(rootView: AnalyticsView(viewModel: viewModel))
        hostingView.frame = NSRect(x: 0, y: 0, width: 760, height: 520)
        hostingView.layoutSubtreeIfNeeded()
        let elapsed = started.duration(to: .now)

        #expect(snapshot.repositories.count == 64)
        #expect(snapshot.repositories.allSatisfy { $0.commits.count == 200 })
        #expect(hostingView.frame.size == NSSize(width: 760, height: 520))
        #expect(elapsed < .seconds(10))
    }
}

@MainActor
private final class TestAnalyticsRepository: AnalyticsRepository, @unchecked Sendable {
    private var continuations: [CheckedContinuation<Result<AnalyticsSnapshot, Error>, Never>] = []
    private(set) var callCount = 0
    private var callWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func refreshAnalytics() async throws -> AnalyticsSnapshot {
        callCount += 1
        resumeCallWaiters()
        let result = await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
        return try result.get()
    }

    func waitForCall(_ expected: Int) async {
        guard callCount < expected else { return }
        await withCheckedContinuation { continuation in
            callWaiters.append((expected, continuation))
        }
    }

    func completeNext(with result: Result<AnalyticsSnapshot, Error>) {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume(returning: result)
    }

    private func resumeCallWaiters() {
        let pending = callWaiters
        callWaiters.removeAll()
        for (expected, continuation) in pending {
            if callCount >= expected {
                continuation.resume()
            } else {
                callWaiters.append((expected, continuation))
            }
        }
    }
}

private struct ImmediateAnalyticsRepository: AnalyticsRepository {
    let snapshot: AnalyticsSnapshot

    func refreshAnalytics() async throws -> AnalyticsSnapshot {
        snapshot
    }
}

private struct TestAnalyticsError: Error {
    let raw: String
}

@MainActor
private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<100 {
        if condition() { return true }
        await Task.yield()
    }
    return false
}

private func testAnalyticsSnapshot() -> AnalyticsSnapshot {
    let usage = AnalyticsUsageAggregate(
        inputTokens: "100", outputTokens: "50", cacheReadTokens: "0", cacheWriteTokens: "0",
        reasoningTokens: "0", totalTokens: "150", estimatedCostUSD: "1.25"
    )
    let generatedAt = Date(timeIntervalSince1970: 1_725_182_400)
    return AnalyticsSnapshot(
        schemaVersion: "needlbar.analytics.v1", ok: true, generatedAt: generatedAt,
        analysisRange: AnalyticsDateRange(start: generatedAt.addingTimeInterval(-30 * 24 * 60 * 60), end: generatedAt),
        repositories: [],
        unattributed: AnalyticsAttributionBucket(usage: usage, fragments: 0, reasons: [:]),
        coverage: AnalyticsCoverage(attributedFragments: 0, unattributedFragments: 0, reasons: [:]),
        errors: []
    )
}

private func populatedAnalyticsSnapshot() -> AnalyticsSnapshot {
    let usage = AnalyticsUsageAggregate(
        inputTokens: "100", outputTokens: "50", cacheReadTokens: "0", cacheWriteTokens: "0",
        reasoningTokens: "0", totalTokens: "150", estimatedCostUSD: "1.25"
    )
    let generatedAt = Date(timeIntervalSince1970: 1_725_182_400)
    let model = AnalyticsProviderModelAnalytics(
        provider: "claude",
        model: "Other model",
        usage: usage,
        costPer1KTokens: nil,
        tokensPerObservedActiveHour: nil,
        millisecondsPer1KTokens: nil,
        costCoverage: "partial",
        timingCoverage: "missingDuration"
    )
    let commit = AnalyticsCommitAnalytics(
        commitID: "0123456789ab",
        committedAt: generatedAt,
        correlatedUsage: usage,
        pullRequestNumber: 42,
        coverage: "partial"
    )
    let available = AnalyticsRepositoryAnalytics(
        repositoryID: "repo-1",
        label: "Example",
        state: "available",
        usage: usage,
        observedActiveTimeSeconds: "120",
        providerModels: [model],
        commits: [commit],
        coverage: RepositoryCoverage(
            assignedFragments: 2,
            unassignedFragments: 1,
            timingPartial: true,
            reasons: [
                "missingCost": 1,
                "missingDuration": 1,
                "pendingCommitWindow": 1,
                "gitTimedOut": 1,
                "recordLimitReached": 3,
            ]
        )
    )
    let unavailable = AnalyticsRepositoryAnalytics(
        repositoryID: "repo-2",
        label: "Repository repo-2",
        state: "unavailable",
        usage: usage,
        observedActiveTimeSeconds: "0",
        providerModels: [],
        commits: [],
        coverage: RepositoryCoverage(
            assignedFragments: 0,
            unassignedFragments: 1,
            timingPartial: false,
            reasons: ["repositoryUnavailable": 1]
        )
    )
    return AnalyticsSnapshot(
        schemaVersion: "needlbar.analytics.v1",
        ok: true,
        generatedAt: generatedAt,
        analysisRange: AnalyticsDateRange(
            start: generatedAt.addingTimeInterval(-30 * 24 * 60 * 60),
            end: generatedAt
        ),
        repositories: [available, unavailable],
        unattributed: AnalyticsAttributionBucket(
            usage: usage,
            fragments: 7,
            reasons: [
                "missingWorkspace": 2,
                "pendingCommitWindow": 1,
                "gitTimedOut": 1,
                "recordLimitReached": 3,
                "raw-canary": 99,
            ]
        ),
        coverage: AnalyticsCoverage(
            attributedFragments: 3,
            unattributedFragments: 7,
            reasons: ["gitTimedOut": 1]
        ),
        errors: [AnalyticsBridgeError(scope: "git", code: "gitTimedOut")]
    )
}

private func maximumAnalyticsSnapshot() -> AnalyticsSnapshot {
    let usage = AnalyticsUsageAggregate(
        inputTokens: "12345678901234567890123456789012345678",
        outputTokens: "50",
        cacheReadTokens: "0",
        cacheWriteTokens: "0",
        reasoningTokens: "0",
        totalTokens: "12345678901234567890123456789012345678",
        estimatedCostUSD: "12345678901234567890123456789012345678"
    )
    let date = Date(timeIntervalSince1970: 1_725_182_400)
    let commit = AnalyticsCommitAnalytics(
        commitID: "0123456789ab",
        committedAt: date,
        correlatedUsage: usage,
        pullRequestNumber: nil,
        coverage: "correlated"
    )
    let repositories = (0..<64).map { index in
        AnalyticsRepositoryAnalytics(
            repositoryID: "repo-\(index)",
            label: "Repository \(index)",
            state: "available",
            usage: usage,
            observedActiveTimeSeconds: "120",
            providerModels: [
                AnalyticsProviderModelAnalytics(
                    provider: "claude",
                    model: "Other model",
                    usage: usage,
                    costPer1KTokens: nil,
                    tokensPerObservedActiveHour: nil,
                    millisecondsPer1KTokens: nil,
                    costCoverage: "partial",
                    timingCoverage: "missingDuration"
                ),
            ],
            commits: Array(repeating: commit, count: 200).enumerated().map { offset, item in
                AnalyticsCommitAnalytics(
                    commitID: String(format: "%012x", offset),
                    committedAt: item.committedAt,
                    correlatedUsage: item.correlatedUsage,
                    pullRequestNumber: nil,
                    coverage: item.coverage
                )
            },
            coverage: RepositoryCoverage(
                assignedFragments: 1,
                unassignedFragments: 1,
                timingPartial: true,
                reasons: ["missingCost": 1, "missingDuration": 1]
            )
        )
    }
    return AnalyticsSnapshot(
        schemaVersion: "needlbar.analytics.v1",
        ok: true,
        generatedAt: date,
        analysisRange: AnalyticsDateRange(start: date.addingTimeInterval(-30 * 24 * 60 * 60), end: date),
        repositories: repositories,
        unattributed: AnalyticsAttributionBucket(usage: usage, fragments: 1, reasons: [:]),
        coverage: AnalyticsCoverage(attributedFragments: 12800, unattributedFragments: 1, reasons: [:]),
        errors: []
    )
}
