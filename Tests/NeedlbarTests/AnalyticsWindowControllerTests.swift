import AppKit
import Foundation
import Testing
import SwiftUI
@testable import NeedlbarApp
@testable import NeedlbarCore

@Suite("AnalyticsWindowControllerTests", .serialized)
@MainActor
struct AnalyticsWindowControllerTests {
    @Test func balancedStatusResolverUsesTheApprovedSinglePriorityOrder() {
        #expect(AnalyticsDashboardStatus.resolve(isLoading: true, presentationState: .loading, hasDisplayedSnapshot: false, hasPartialDisplayedSnapshot: false, statusCopy: "ignored") == .initialLoading)
        let updating = AnalyticsDashboardStatus.resolve(isLoading: true, presentationState: .loading, hasDisplayedSnapshot: true, hasPartialDisplayedSnapshot: true, statusCopy: "ignored")
        #expect(updating.text.contains("last captured snapshot"))
        #expect(updating.text.contains("partial"))
        #expect(AnalyticsDashboardStatus.resolve(isLoading: false, presentationState: .unavailable, hasDisplayedSnapshot: false, hasPartialDisplayedSnapshot: false, statusCopy: "Analytics unavailable. Refresh to try again.").isWarning)
        #expect(AnalyticsDashboardStatus.resolve(isLoading: false, presentationState: .stale, hasDisplayedSnapshot: true, hasPartialDisplayedSnapshot: true, statusCopy: "Showing the last successful local analysis. Refresh to try again.").isWarning)
        #expect(AnalyticsDashboardStatus.resolve(isLoading: false, presentationState: .fresh, hasDisplayedSnapshot: true, hasPartialDisplayedSnapshot: true, statusCopy: "Some local usage or repository coverage is partial.").isWarning)
        #expect(AnalyticsDashboardStatus.resolve(isLoading: false, presentationState: .fresh, hasDisplayedSnapshot: true, hasPartialDisplayedSnapshot: false, statusCopy: "Local analysis complete.").isWarning == false)
    }

    @Test func viewDiagnosticsExpandsThenScrollsWithoutFetching() async {
        let repository = TestAnalyticsRepository()
        let controller = AnalyticsWindowController(store: AnalyticsSnapshotStore(), repository: repository)
        controller.showAnalytics()
        await repository.waitForCall(1)
        await repository.completeNext(with: .success(populatedAnalyticsSnapshot()))
        #expect(await eventually { controller.viewModel.presentationState == .fresh })

        var expanded = false
        let spy = AnalyticsScrollSpy()
        AnalyticsDiagnosticsInteraction.reveal(
            diagnosticsExpanded: Binding(get: { expanded }, set: { expanded = $0 }),
            scrollToDiagnostics: { spy.targets.append("analytics-diagnostics") }
        )

        #expect(expanded)
        #expect(await eventually { spy.targets == ["analytics-diagnostics"] })
        #expect(await repository.callCount == 1)
        #expect(controller.viewModel.isLoading == false)
    }

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

    @Test func summaryFirstFormattingKeepsAbsentEvidenceDistinctFromMeasuredZero() {
        #expect(AnalyticsDisplayFormatter.repositoryAttributedEstimate(nil, knownSubtotal: false) == "—")
        #expect(AnalyticsDisplayFormatter.repositoryAttributedEstimate(.zero, knownSubtotal: false) == "$0.00")
        #expect(AnalyticsDisplayFormatter.repositoryAttributedEstimate(Decimal(string: "1.25")!, knownSubtotal: true) == "$1.25 (known subtotal)")
        #expect(AnalyticsDisplayFormatter.observedAIActivity(nil) == "—")
        #expect(AnalyticsDisplayFormatter.observedAIActivity(0) == "0s")
    }

    @Test func summaryFirstDisclosuresHaveDistinctAccessibleNamesAndStates() {
        let labels = AnalyticsDisplayFormatter.disclosureAccessibilityLabels

        #expect(labels.diagnostics == "Analytics diagnostics")
        #expect(labels.estimateDefinition == "Estimate definition")
        #expect(labels.diagnostics != labels.estimateDefinition)
        #expect(AnalyticsDisplayFormatter.disclosureAccessibilityValue(isExpanded: false) == "Collapsed")
        #expect(AnalyticsDisplayFormatter.disclosureAccessibilityValue(isExpanded: true) == "Expanded")
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
        #expect(AnalyticsDisplayFormatter.commitCoverage(commit.coverage) == "Partial")
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

    @Test func summaryFirstViewHostsScrollableContentAtDefaultAndMinimumWindowSizes() async {
        for snapshot in [testAnalyticsSnapshot(), populatedAnalyticsSnapshot(), maximumAnalyticsSnapshot()] {
            let repository = ImmediateAnalyticsRepository(snapshot: snapshot)
            let viewModel = AnalyticsViewModel(store: AnalyticsSnapshotStore(), repository: repository)
            viewModel.loadIfNeeded()
            #expect(await eventually { viewModel.snapshot != nil })

            for size in [NSSize(width: 760, height: 520), NSSize(width: 640, height: 400)] {
                let hostingView = NSHostingView(rootView: AnalyticsView(viewModel: viewModel))
                hostingView.frame = NSRect(origin: .zero, size: size)
                hostingView.layoutSubtreeIfNeeded()

                #expect(hostingView.bounds.size == size)
                #expect(hostingView.fittingSize.width >= 640)
                #expect(hostingView.fittingSize.height >= 400)
                #expect(hostingView.containsSubview(ofType: NSScrollView.self))
            }
        }
    }

    @Test func balancedDashboardUsesTheApprovedBoundedGridBreakpoints() {
        #expect(AnalyticsDashboardLayout.contentColumnWidth(forWindowContentWidth: 640) == 592)
        #expect(AnalyticsDashboardLayout.summaryColumnCount(forContentWidth: 592) == 2)
        #expect(AnalyticsDashboardLayout.contentColumnWidth(forWindowContentWidth: 760) == 712)
        #expect(AnalyticsDashboardLayout.summaryColumnCount(forContentWidth: 712) == 3)
        #expect(AnalyticsDashboardLayout.contentColumnWidth(forWindowContentWidth: 1_400) == 960)
        #expect(AnalyticsDashboardLayout.summaryColumnCount(forContentWidth: 960) == 3)
        #expect(AnalyticsDashboardLayout.evidencePanelColumnCount(forContentWidth: 592) == 1)
        #expect(AnalyticsDashboardLayout.evidencePanelColumnCount(forContentWidth: 712) == 1)
        #expect(AnalyticsDashboardLayout.evidencePanelColumnCount(forContentWidth: 960) == 2)
    }

    @Test func balancedDashboardCardStylesDriveTheRenderedSemanticTreatments() {
        let cost = AnalyticsDashboardCardKind.repositoryEstimate
        let linkage = AnalyticsDashboardCardKind.repositoryLinkage
        let activity = AnalyticsDashboardCardKind.observedActivity

        #expect(cost.accent == Color.blue)
        #expect(linkage.accent == Color.teal)
        #expect(activity.accent == Color.purple)
        #expect(cost.symbolName == "dollarsign.circle")
        #expect(linkage.symbolName == "link.circle")
        #expect(activity.symbolName == "sparkles")
        #expect(AnalyticsDashboardLayout.summaryValuePointSize(for: "$12.50") == 28)
        #expect(AnalyticsDashboardLayout.summaryValuePointSize(for: "$123,456,789.00") == 24)
    }

    @Test func balancedDashboardContentHasNaturalHeightAndReachesItsFinalDisclosure() throws {
        var diagnosticsExpanded = false
        var definitionExpanded = false
        var expandedSections: Set<String> = []
        let content = AnalyticsDashboardContent(
            snapshot: maximumAnalyticsSnapshot(),
            contentWidth: 592,
            diagnosticsExpanded: Binding(get: { diagnosticsExpanded }, set: { diagnosticsExpanded = $0 }),
            estimateDefinitionExpanded: Binding(get: { definitionExpanded }, set: { definitionExpanded = $0 }),
            expandedSections: Binding(get: { expandedSections }, set: { expandedSections = $0 }),
            onViewDiagnostics: {}
        )
        _ = NSApplication.shared
        let hosted = NSHostingView(rootView: ScrollView { content })
        hosted.frame = NSRect(x: 0, y: 0, width: 640, height: 400)
        let window = NSWindow(
            contentRect: hosted.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosted
        defer { window.close() }
        window.makeKeyAndOrderFront(nil)
        window.display()
        hosted.layoutSubtreeIfNeeded()

        let scroll = try #require(hosted.firstSubview(ofType: NSScrollView.self))
        let document = try #require(scroll.documentView)
        // SwiftUI attaches the AppKit document container on the next main-loop layout pass.
        for _ in 0..<5 where document.frame.height <= scroll.contentView.bounds.height {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            window.display()
            hosted.layoutSubtreeIfNeeded()
        }
        #expect(document.frame.height > scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.frame.height - scroll.contentView.bounds.height)))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(scroll.contentView.bounds.maxY >= document.bounds.maxY - 1)
    }

    @Test func balancedNativeFixturePixelMatrixCoversRequiredStatesWidthsAndAppearances() throws {
        let fixtures: [(name: String, snapshot: AnalyticsSnapshot)] = [
            ("empty", testAnalyticsSnapshot()),
            ("mixed", populatedAnalyticsSnapshot()),
            ("maximum", maximumAnalyticsSnapshot()),
        ]
        let widths: [CGFloat] = [640, 760, 1_400]
        let appearances: [(name: String, appearance: NSAppearance)] = [
            ("light", try #require(NSAppearance(named: .aqua))),
            ("dark", try #require(NSAppearance(named: .darkAqua))),
        ]

        for fixture in fixtures {
            for width in widths {
                for appearance in appearances {
                    let png = try renderAnalyticsFixturePNG(
                        snapshot: fixture.snapshot,
                        width: width,
                        appearance: appearance.appearance
                    )
                    #expect(png.count > 64, "\(fixture.name) at \(width) in \(appearance.name) must produce native pixels")
                    try png.write(
                        to: try analyticsPixelQAFile("\(fixture.name)-\(Int(width))-\(appearance.name).png"),
                        options: .atomic
                    )
                }
            }
        }
    }

    @Test func balancedNativeFixturePixelEvidenceIncludesExpandedLongAndMaximumEndpoints() throws {
        let light = try #require(NSAppearance(named: .aqua))
        let dark = try #require(NSAppearance(named: .darkAqua))
        let expandedSections: Set<String> = ["provider-model-repo-0", "commits-repo-0"]
        let fixtures: [(name: String, snapshot: AnalyticsSnapshot, appearance: NSAppearance, position: AnalyticsFixtureScrollPosition)] = [
            ("long-label-expanded-top-640-light", longLabelAnalyticsSnapshot(), light, .top),
            ("maximum-expanded-top-640-dark", maximumAnalyticsSnapshot(), dark, .top),
            ("maximum-expanded-bottom-640-dark", maximumAnalyticsSnapshot(), dark, .bottom),
        ]

        for fixture in fixtures {
            let png = try renderAnalyticsFixturePNG(
                snapshot: fixture.snapshot,
                width: 640,
                appearance: fixture.appearance,
                diagnosticsExpanded: true,
                estimateDefinitionExpanded: true,
                expandedSections: expandedSections,
                scrollPosition: fixture.position
            )
            #expect(png.count > 64, "\(fixture.name) must render mounted native pixels")
            try png.write(to: try analyticsPixelQAFile("\(fixture.name).png"), options: .atomic)
        }
    }

    @Test func balancedNativeShellPixelMatrixIncludesCompletePartialLoadingUpdatingStaleAndUnavailable() async throws {
        let widths: [CGFloat] = [640, 760, 1_400]
        let appearances: [(name: String, appearance: NSAppearance)] = [
            ("light", try #require(NSAppearance(named: .aqua))),
            ("dark", try #require(NSAppearance(named: .darkAqua))),
        ]

        for state in ["loading", "complete", "partial", "updating", "stale", "unavailable"] {
            let repository = TestAnalyticsRepository()
            let model = AnalyticsViewModel(store: AnalyticsSnapshotStore(), repository: repository)
            model.loadIfNeeded()
            await repository.waitForCall(1)
            let host = AnalyticsShellFixtureHost(viewModel: model)
            defer { host.close() }

            switch state {
            case "complete":
                await repository.completeNext(with: .success(testAnalyticsSnapshot()))
                #expect(await eventually { model.presentationState == .fresh && !model.isLoading })
            case "partial":
                await repository.completeNext(with: .success(populatedAnalyticsSnapshot()))
                #expect(await eventually { model.presentationState == .fresh && !model.isLoading })
            case "updating", "stale":
                await repository.completeNext(with: .success(populatedAnalyticsSnapshot()))
                #expect(await eventually { model.presentationState == .fresh && !model.isLoading })
                host.drainLayout()
                model.refresh()
                await repository.waitForCall(2)
                if state == "stale" {
                    await repository.completeNext(with: .failure(TestAnalyticsError(raw: "fixture stale")))
                    #expect(await eventually { model.presentationState == .stale && !model.isLoading })
                }
            case "unavailable":
                await repository.completeNext(with: .failure(TestAnalyticsError(raw: "fixture unavailable")))
                #expect(await eventually { model.presentationState == .unavailable && !model.isLoading })
            default:
                break
            }

            for width in widths {
                for appearance in appearances {
                    let png = try host.renderPNG(width: width, appearance: appearance.appearance)
                    #expect(png.count > 64, "\(state) at \(width) in \(appearance.name) must produce mounted native pixels")
                    try png.write(
                        to: try analyticsPixelQAFile("shell-\(state)-\(Int(width))-\(appearance.name).png"),
                        options: .atomic
                    )
                }
            }

            if state == "loading" || state == "updating" {
                await repository.completeNext(with: .success(populatedAnalyticsSnapshot()))
                #expect(await eventually { !model.isLoading })
            }
        }
    }

    @Test func balancedNativeFixtureCaptureHoldsAPartialFullShellOnlyWhenExplicitlyOptedIn() async throws {
        guard let captureDirectoryPath = ProcessInfo.processInfo.environment["NEEDLBAR_ANALYTICS_FIXTURE_CAPTURE_DIRECTORY"] else {
            return
        }
        guard captureDirectoryPath.hasPrefix("/") else {
            throw analyticsFixtureError("The fixture capture directory must be an absolute path.")
        }
        let captureDirectory = URL(fileURLWithPath: captureDirectoryPath, isDirectory: true)
        try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)

        let model = AnalyticsViewModel(
            store: AnalyticsSnapshotStore(),
            repository: ImmediateAnalyticsRepository(snapshot: populatedAnalyticsSnapshot())
        )
        model.loadIfNeeded()
        #expect(await eventually { model.presentationState == .fresh && !model.isLoading })

        let host = AnalyticsShellFixtureHost(viewModel: model, title: "Needlbar Analytics Fixture")
        defer { host.close() }
        host.setContentSize(NSSize(width: 760, height: 520), appearance: try #require(NSAppearance(named: .aqua)))
        try host.writeCaptureReady(in: captureDirectory)

        let releaseMarker = captureDirectory.appendingPathComponent("needlbar-analytics-fixture-release")
        let deadline = Date(timeIntervalSinceNow: 120)
        while !FileManager.default.fileExists(atPath: releaseMarker.path), Date() < deadline {
            host.drainLayout()
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(
            FileManager.default.fileExists(atPath: releaseMarker.path),
            "Fixture capture timed out after 120 seconds; create \(releaseMarker.path) after capture."
        )
    }
}

@MainActor
private final class AnalyticsScrollSpy {
    var targets: [String] = []
}

private enum AnalyticsFixtureScrollPosition {
    case top
    case bottom
}

@MainActor
private final class AnalyticsShellFixtureHost {
    private let hosted: NSHostingView<AnalyticsView>
    private let window: NSWindow

    init(viewModel: AnalyticsViewModel, title: String = "Needlbar Analytics Fixture") {
        _ = NSApplication.shared
        hosted = NSHostingView(rootView: AnalyticsView(viewModel: viewModel))
        hosted.frame = NSRect(x: 0, y: 0, width: 760, height: 520)
        window = NSWindow(
            contentRect: hosted.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = title
        window.contentView = hosted
        window.makeKeyAndOrderFront(nil)
        drainLayout()
    }

    func renderPNG(width: CGFloat, appearance: NSAppearance) throws -> Data {
        window.appearance = appearance
        hosted.appearance = appearance
        window.setContentSize(NSSize(width: width, height: analyticsFixtureHeight(for: width)))
        drainLayout()
        return try analyticsFixturePNG(from: hosted)
    }

    func setContentSize(_ size: NSSize, appearance: NSAppearance) {
        window.appearance = appearance
        hosted.appearance = appearance
        window.setContentSize(size)
        window.makeKeyAndOrderFront(nil)
        drainLayout()
    }

    func writeCaptureReady(in directory: URL) throws {
        let ready = directory.appendingPathComponent("needlbar-analytics-fixture-ready.json")
        let metadata: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "windowNumber": window.windowNumber,
            "title": window.title,
            "size": ["width": window.contentView?.bounds.width ?? 0, "height": window.contentView?.bounds.height ?? 0],
            "releaseMarker": directory.appendingPathComponent("needlbar-analytics-fixture-release").path,
        ]
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: ready, options: .atomic)
    }

    func drainLayout() {
        for _ in 0..<8 {
            window.display()
            hosted.layoutSubtreeIfNeeded()
            if attachedAnalyticsFixtureScrollView(in: hosted)?.documentView?.superview != nil { return }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }

    func close() {
        window.close()
    }
}

@MainActor
private func renderAnalyticsFixturePNG(
    snapshot: AnalyticsSnapshot,
    width: CGFloat,
    appearance: NSAppearance,
    diagnosticsExpanded: Bool = false,
    estimateDefinitionExpanded: Bool = false,
    expandedSections: Set<String> = [],
    scrollPosition: AnalyticsFixtureScrollPosition = .top
) throws -> Data {
    var diagnosticsExpanded = diagnosticsExpanded
    var estimateDefinitionExpanded = estimateDefinitionExpanded
    var expandedSections = expandedSections
    let root = ScrollView {
        AnalyticsDashboardContent(
            snapshot: snapshot,
            contentWidth: AnalyticsDashboardLayout.contentColumnWidth(forWindowContentWidth: width),
            diagnosticsExpanded: Binding(get: { diagnosticsExpanded }, set: { diagnosticsExpanded = $0 }),
            estimateDefinitionExpanded: Binding(get: { estimateDefinitionExpanded }, set: { estimateDefinitionExpanded = $0 }),
            expandedSections: Binding(get: { expandedSections }, set: { expandedSections = $0 }),
            onViewDiagnostics: {}
        )
    }
    return try renderMountedAnalyticsViewPNG(
        root,
        width: width,
        appearance: appearance,
        scrollPosition: scrollPosition
    )
}

@MainActor
private func renderMountedAnalyticsViewPNG<V: View>(
    _ root: V,
    width: CGFloat,
    appearance: NSAppearance,
    scrollPosition: AnalyticsFixtureScrollPosition
) throws -> Data {
    _ = NSApplication.shared
    let hosted = NSHostingView(rootView: root)
    hosted.appearance = appearance
    hosted.frame = NSRect(x: 0, y: 0, width: width, height: analyticsFixtureHeight(for: width))
    let window = NSWindow(
        contentRect: hosted.frame,
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.appearance = appearance
    window.contentView = hosted
    defer { window.close() }
    window.makeKeyAndOrderFront(nil)
    try drainAnalyticsFixtureLayout(window: window, hosted: hosted)

    if scrollPosition == .bottom {
        let scroll = try analyticsFixtureScrollView(in: hosted)
        let document = try analyticsFixtureDocumentView(in: scroll)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.bounds.height - scroll.contentView.bounds.height)))
        scroll.reflectScrolledClipView(scroll.contentView)
        try drainAnalyticsFixtureLayout(window: window, hosted: hosted)
        guard scroll.contentView.bounds.maxY >= document.bounds.maxY - 1 else {
            throw analyticsFixtureError("The mounted fixture did not reach its final scroll position.")
        }
    }

    return try analyticsFixturePNG(from: hosted)
}

@MainActor
private func drainAnalyticsFixtureLayout(window: NSWindow, hosted: NSView) throws {
    for _ in 0..<8 {
        window.display()
        hosted.layoutSubtreeIfNeeded()
        if attachedAnalyticsFixtureScrollView(in: hosted)?.documentView?.superview != nil { return }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }
    throw analyticsFixtureError("The native scroll document did not attach within the bounded layout drain.")
}

@MainActor
private func attachedAnalyticsFixtureScrollView(in hosted: NSView) -> NSScrollView? {
    hosted.firstSubview(ofType: NSScrollView.self)
}

@MainActor
private func analyticsFixtureScrollView(in hosted: NSView) throws -> NSScrollView {
    guard let scroll = attachedAnalyticsFixtureScrollView(in: hosted) else {
        throw analyticsFixtureError("The mounted native fixture has no scroll view.")
    }
    return scroll
}

@MainActor
private func analyticsFixtureDocumentView(in scroll: NSScrollView?) throws -> NSView {
    guard let document = scroll?.documentView else {
        throw analyticsFixtureError("The mounted native fixture has no scroll document.")
    }
    return document
}

@MainActor
private func analyticsFixturePNG(from hosted: NSView) throws -> Data {
    let width = Int(hosted.bounds.width)
    let height = Int(hosted.bounds.height)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw analyticsFixtureError("The native fixture bitmap could not be allocated.")
    }
    hosted.cacheDisplay(in: hosted.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw analyticsFixtureError("The native fixture bitmap could not be encoded as PNG.")
    }
    return png
}

private func analyticsFixtureHeight(for width: CGFloat) -> CGFloat {
    width == 640 ? 400 : 520
}

private func analyticsPixelQAFile(_ name: String) throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("needlbar-analytics-pixel-qa", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent(name)
}

private func analyticsFixtureError(_ description: String) -> NSError {
    NSError(domain: "NeedlbarAnalyticsFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
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

private extension NSView {
    func containsSubview<T: NSView>(ofType type: T.Type) -> Bool {
        subviews.contains { $0 is T || $0.containsSubview(ofType: type) }
    }

    func firstSubview<T: NSView>(ofType type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T { return match }
            if let match = subview.firstSubview(ofType: type) { return match }
        }
        return nil
    }
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

private func longLabelAnalyticsSnapshot() -> AnalyticsSnapshot {
    let snapshot = populatedAnalyticsSnapshot()
    let repository = snapshot.repositories[0]
    let longLabel = AnalyticsRepositoryAnalytics(
        repositoryID: repository.repositoryID,
        label: "Repository with an intentionally long local label that must wrap without clipping its evidence details",
        state: repository.state,
        usage: repository.usage,
        observedActiveTimeSeconds: repository.observedActiveTimeSeconds,
        providerModels: repository.providerModels,
        commits: repository.commits,
        coverage: repository.coverage
    )
    return AnalyticsSnapshot(
        schemaVersion: snapshot.schemaVersion,
        ok: snapshot.ok,
        generatedAt: snapshot.generatedAt,
        analysisRange: snapshot.analysisRange,
        repositories: [longLabel] + snapshot.repositories.dropFirst(),
        unattributed: snapshot.unattributed,
        coverage: snapshot.coverage,
        errors: snapshot.errors
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
