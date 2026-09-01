import AppKit
import Foundation
import Testing
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
