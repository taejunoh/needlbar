import Foundation
import NeedlbarCore
import SwiftUI

enum AnalyticsDashboardStatus: Equatable {
    case initialLoading
    case updating(String)
    case unavailable(String)
    case stale(String)
    case partial(String)
    case complete(String)

    static func resolve(
        isLoading: Bool,
        presentationState: AnalyticsViewModel.PresentationState,
        hasDisplayedSnapshot: Bool,
        hasPartialDisplayedSnapshot: Bool,
        statusCopy: String
    ) -> AnalyticsDashboardStatus {
        if isLoading {
            guard hasDisplayedSnapshot else { return .initialLoading }
            let caveat = hasPartialDisplayedSnapshot ? " Some local usage or repository coverage is partial." : ""
            return .updating("Refreshing local analysis. Showing the last captured snapshot.\(caveat)")
        }
        return switch presentationState {
        case .unavailable: .unavailable(statusCopy)
        case .stale: .stale(statusCopy)
        case .fresh: hasPartialDisplayedSnapshot ? .partial(statusCopy) : .complete(statusCopy)
        case .idle, .loading: .initialLoading
        }
    }

    var text: String {
        switch self {
        case .initialLoading: "Analyzing local repository data…"
        case let .updating(text), let .unavailable(text), let .stale(text), let .partial(text), let .complete(text): text
        }
    }

    var isWarning: Bool {
        switch self {
        case .partial, .stale, .unavailable: true
        case .initialLoading, .updating, .complete: false
        }
    }
}

@MainActor
enum AnalyticsDiagnosticsInteraction {
    static func reveal(diagnosticsExpanded: Binding<Bool>, scrollToDiagnostics: @escaping @MainActor () -> Void) {
        diagnosticsExpanded.wrappedValue = true
        DispatchQueue.main.async { scrollToDiagnostics() }
    }
}

public struct AnalyticsView: View {
    @ObservedObject private var viewModel: AnalyticsViewModel
    @State private var lastSuccessfulSnapshot: AnalyticsSnapshot?
    @State private var diagnosticsExpanded = false
    @State private var estimateDefinitionExpanded = false
    @State private var expandedSections: Set<String> = []

    public init(viewModel: AnalyticsViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }

    public var body: some View {
        GeometryReader { windowProxy in
            let contentWidth = AnalyticsDashboardLayout.contentColumnWidth(forWindowContentWidth: windowProxy.size.width)
            let snapshot = displayedSnapshot
            let status = AnalyticsDashboardStatus.resolve(
                isLoading: viewModel.isLoading,
                presentationState: viewModel.presentationState,
                hasDisplayedSnapshot: snapshot != nil,
                hasPartialDisplayedSnapshot: snapshot.map(AnalyticsViewModel.isPartial) ?? false,
                statusCopy: viewModel.statusCopy
            )

            ScrollViewReader { proxy in
                let revealDiagnostics = {
                    AnalyticsDiagnosticsInteraction.reveal(diagnosticsExpanded: $diagnosticsExpanded) {
                        withAnimation { proxy.scrollTo("analytics-diagnostics", anchor: .top) }
                    }
                }
                VStack(spacing: 0) {
                    header(status, contentWidth: contentWidth, onViewDiagnostics: revealDiagnostics)
                        .padding(.vertical, 16)
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: AnalyticsDashboardLayout.sectionSpacing) {
                            if case .initialLoading = status {
                                ProgressView().controlSize(.small).accessibilityHidden(true)
                            }
                            if let snapshot {
                                AnalyticsDashboardContent(
                                    snapshot: snapshot,
                                    contentWidth: contentWidth,
                                    diagnosticsExpanded: $diagnosticsExpanded,
                                    estimateDefinitionExpanded: $estimateDefinitionExpanded,
                                    expandedSections: $expandedSections,
                                    onViewDiagnostics: revealDiagnostics
                                )
                            }
                        }
                        .frame(width: contentWidth, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, AnalyticsDashboardLayout.horizontalInset)
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .onReceive(viewModel.$state) { state in
            if case let .fresh(snapshot) = state { lastSuccessfulSnapshot = snapshot }
            if case let .stale(snapshot) = state { lastSuccessfulSnapshot = snapshot }
        }
    }

    private var displayedSnapshot: AnalyticsSnapshot? {
        viewModel.snapshot ?? (viewModel.isLoading ? lastSuccessfulSnapshot : nil)
    }

    private func header(
        _ status: AnalyticsDashboardStatus,
        contentWidth: CGFloat,
        onViewDiagnostics: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Analytics")
                        .font(.title2.weight(.semibold))
                    Text(captureCopy)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") { viewModel.refresh() }
                    .disabled(viewModel.isLoading)
                    .accessibilityLabel("Refresh analytics")
                    .accessibilityValue(AnalyticsDisplayFormatter.refreshAccessibilityValue(isLoading: viewModel.isLoading))
            }
            if status.isWarning {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(status.text, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    if displayedSnapshot != nil {
                        Button("View diagnostics", action: onViewDiagnostics)
                            .font(.system(size: 12, weight: .medium))
                            .accessibilityLabel("View analytics diagnostics")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Text(status.text).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .frame(width: contentWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var captureCopy: String {
        guard let snapshot = displayedSnapshot else { return "Last 30 days · Capture pending" }
        return "Last 30 days · Captured \(AnalyticsDisplayFormatter.date(snapshot.generatedAt))"
    }
}

struct AnalyticsDashboardContent: View {
    let snapshot: AnalyticsSnapshot
    let contentWidth: CGFloat
    @Binding var diagnosticsExpanded: Bool
    @Binding var estimateDefinitionExpanded: Bool
    @Binding var expandedSections: Set<String>
    let onViewDiagnostics: () -> Void

    var body: some View {
        let summary = AnalyticsPresentation.summary(for: snapshot)
        let diagnostics = AnalyticsPresentation.diagnostics(for: snapshot)

        VStack(alignment: .leading, spacing: AnalyticsDashboardLayout.sectionSpacing) {
            LazyVGrid(columns: AnalyticsDashboardLayout.summaryTracks(forContentWidth: contentWidth), alignment: .leading, spacing: AnalyticsDashboardLayout.gridSpacing) {
                AnalyticsDashboardCard(
                    kind: .repositoryEstimate,
                    title: "Repository-attributed estimate",
                    value: AnalyticsDisplayFormatter.repositoryAttributedEstimate(summary.repositoryAttributedCostUSD, knownSubtotal: false),
                    detail: repositoryEstimateDetail(summary)
                )
                AnalyticsDashboardCard(
                    kind: .repositoryLinkage,
                    title: "Repository linkage",
                    value: "\(summary.linkedRepositoryCount)",
                    detail: "Repositories · \(summary.unlinkedFragmentCount) unlinked fragments"
                )
                AnalyticsDashboardCard(
                    kind: .observedActivity,
                    title: "Observed AI activity",
                    value: AnalyticsDisplayFormatter.observedAIActivity(summary.observedAIActivitySeconds),
                    detail: summary.observedAIActivitySeconds == nil
                        ? "No repository-attributed timing evidence."
                        : diagnostics.contains(where: { $0.code == "missingDuration" })
                            ? "Some responses lack duration; observed activity remains separate."
                            : "Timestamp-gap observation, not coding hours."
                )
            }

            LazyVGrid(columns: AnalyticsDashboardLayout.evidencePanelTracks(forContentWidth: contentWidth), alignment: .leading, spacing: AnalyticsDashboardLayout.gridSpacing) {
                repositoriesPanel
                unattributedPanel(summary)
            }

            disclosures(diagnostics)
        }
        .frame(width: contentWidth, alignment: .leading)
    }

    private func repositoryEstimateDetail(_ summary: AnalyticsPresentationSummary) -> String {
        guard summary.repositoryAttributedCostUSD != nil else {
            return summary.linkedRepositoryCount == 0 ? "No linked repositories" : "No estimate available"
        }
        return summary.repositoryCostIsKnownSubtotal
            ? "Known subtotal; local coverage is limited."
            : "Local engine pricing; not an invoice."
    }

    private var repositoriesPanel: some View {
        AnalyticsDashboardPanel(title: "Repositories") {
            if snapshot.repositories.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("No usable local repository association was established for this capture.")
                        .font(.system(size: 13))
                    Text("This does not mean there were no repositories or AI usage.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("View diagnostics", action: onViewDiagnostics)
                        .font(.system(size: 12, weight: .medium))
                        .accessibilityLabel("View analytics diagnostics")
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(snapshot.repositories, id: \.repositoryID) { repository in
                        repositoryRow(repository)
                        if repository.repositoryID != snapshot.repositories.last?.repositoryID { Divider() }
                    }
                }
            }
        }
    }

    private func unattributedPanel(_ summary: AnalyticsPresentationSummary) -> some View {
        AnalyticsDashboardPanel(title: "Unattributed") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Unattributed estimated cost")
                    .font(.system(size: 13, weight: .medium))
                Text(unattributedCost)
                    .font(.system(size: AnalyticsDashboardLayout.summaryValuePointSize(for: unattributedCost), weight: .semibold))
                    .monospacedDigit()
                LabeledContent("Unlinked fragments", value: "\(snapshot.unattributed.fragments)")
                Text("Some retained local usage could not be matched to a repository.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if summary.unattributedTimestampCoverageIsIncomplete {
                    Label("Not a verified 30-day total", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.14), in: Capsule())
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var unattributedCost: String {
        guard let cost = snapshot.unattributed.usage.estimatedCostUSDValue else { return "—" }
        return AnalyticsDisplayFormatter.cost(cost)
    }

    private func disclosures(_ diagnostics: [AnalyticsPresentationDiagnostic]) -> some View {
        VStack(alignment: .leading, spacing: AnalyticsDashboardLayout.sectionSpacing) {
            DisclosureGroup(isExpanded: $diagnosticsExpanded) {
                diagnosticsContent(diagnostics).padding(.top, 6)
            } label: {
                Text(AnalyticsDisplayFormatter.disclosureAccessibilityLabels.diagnostics)
                    .font(.system(size: 13, weight: .semibold))
            }
            .id("analytics-diagnostics")
            .accessibilityLabel(AnalyticsDisplayFormatter.disclosureAccessibilityLabels.diagnostics)
            .accessibilityValue(AnalyticsDisplayFormatter.disclosureAccessibilityValue(isExpanded: diagnosticsExpanded))
            .accessibilityHint(AnalyticsDisplayFormatter.disclosureAccessibilityHint)

            DisclosureGroup(isExpanded: $estimateDefinitionExpanded) {
                estimateDefinition.padding(.top, 6)
            } label: {
                Text(AnalyticsDisplayFormatter.disclosureAccessibilityLabels.estimateDefinition)
                    .font(.system(size: 13, weight: .semibold))
            }
            .accessibilityLabel(AnalyticsDisplayFormatter.disclosureAccessibilityLabels.estimateDefinition)
            .accessibilityValue(AnalyticsDisplayFormatter.disclosureAccessibilityValue(isExpanded: estimateDefinitionExpanded))
            .accessibilityHint(AnalyticsDisplayFormatter.disclosureAccessibilityHint)
        }
    }

    private func diagnosticsContent(_ diagnostics: [AnalyticsPresentationDiagnostic]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if diagnostics.isEmpty {
                Text("No retained diagnostic counts for this capture.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(diagnostics, id: \.code) { diagnostic in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(AnalyticsDisplayFormatter.diagnosticTitle(diagnostic.code))
                                .font(.system(size: 13, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Text("\(diagnostic.count) \(AnalyticsDisplayFormatter.diagnosticUnit(diagnostic.unit))")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(AnalyticsDisplayFormatter.diagnosticExplanation(diagnostic.code))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var estimateDefinition: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Costs use local engine pricing and are estimates, not invoices or subscription charges.")
            Text("Observed activity uses timestamp gaps no greater than three minutes; it is not human coding or elapsed wall time.")
            Text("Commit correlation is a same-repository four-hour association, not causal or measured commit cost.")
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func disclosureBinding(_ identifier: String) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(identifier) },
            set: { isExpanded in
                if isExpanded {
                    expandedSections.insert(identifier)
                } else {
                    expandedSections.remove(identifier)
                }
            }
        )
    }

    private func repositoryRow(_ repository: AnalyticsRepositoryAnalytics) -> some View {
        let gitReasons = AnalyticsDisplayFormatter.gitReasonCopy(repository.coverage.reasons)
        let providerDisclosure = disclosureBinding("provider-model-\(repository.repositoryID)")
        let commitsDisclosure = disclosureBinding("commits-\(repository.repositoryID)")
        let providerAccessibilityLabel = "\(repository.label) \(AnalyticsDisplayFormatter.disclosureAccessibilityLabels.providerAndModel)"
        let commitsAccessibilityLabel = "\(repository.label) \(AnalyticsDisplayFormatter.disclosureAccessibilityLabels.commits)"
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(repository.label).font(.headline)
                Spacer()
                Text(AnalyticsDisplayFormatter.repositoryState(repository.state))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(repository.state == "available" ? Color.secondary.opacity(0.12) : Color.orange.opacity(0.2))
                    .clipShape(Capsule())
            }
            if repository.state == "unavailable" {
                Text(AnalyticsDisplayFormatter.repositoryStateCopy(repository.state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(AnalyticsDisplayFormatter.cost(repository.usage.estimatedCostUSDValue))
                    .font(.headline.monospacedDigit())
                Text("Estimated cost · \(AnalyticsDisplayFormatter.repositoryCostCoverage(repository.coverage, state: repository.state))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Text("\(AnalyticsDisplayFormatter.tokens(repository.usage.totalTokens)) tokens")
                    .accessibilityLabel("Tokens")
                    .accessibilityValue(AnalyticsDisplayFormatter.tokensAccessibilityValue(repository.usage.totalTokens))
                Text(AnalyticsDisplayFormatter.duration(repository.observedActiveTimeSecondsValue))
                Text("Timing \(AnalyticsDisplayFormatter.repositoryTimingCoverage(repository.coverage, state: repository.state))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(AnalyticsDisplayFormatter.correlationCoverage(repository.coverage))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !gitReasons.isEmpty {
                Text(gitReasons.map(\.displayText).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if repository.state == "available" && !repository.providerModels.isEmpty {
                DisclosureGroup(isExpanded: providerDisclosure) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(repository.providerModels.enumerated()), id: \.offset) { _, model in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(model.provider) · \(model.model)")
                                    .font(.subheadline.weight(.medium))
                                LabeledContent("Estimated cost", value: AnalyticsDisplayFormatter.cost(model.usage.estimatedCostUSDValue))
                                LabeledContent("Cost coverage", value: AnalyticsDisplayFormatter.providerCoverage(model.costCoverage))
                                LabeledContent("Timing coverage", value: AnalyticsDisplayFormatter.providerTimingCoverage(model.timingCoverage))
                                LabeledContent("Cost per 1K tokens", value: AnalyticsDisplayFormatter.metric(model.costPer1KTokens) ?? "Unavailable")
                                LabeledContent("Tokens per observed active hour", value: AnalyticsDisplayFormatter.metric(model.tokensPerObservedActiveHour) ?? "Unavailable")
                                LabeledContent("Milliseconds per 1K tokens", value: AnalyticsDisplayFormatter.metric(model.millisecondsPer1KTokens) ?? "Unavailable")
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("\(model.provider) \(model.model)")
                            .accessibilityValue(AnalyticsDisplayFormatter.modelAccessibilityValue(model))
                            .accessibilityHint(AnalyticsDisplayFormatter.disclosureAccessibilityHint)
                        }
                    }
                } label: {
                    Text(AnalyticsDisplayFormatter.disclosureAccessibilityLabels.providerAndModel)
                }
                .accessibilityLabel(providerAccessibilityLabel)
                .accessibilityValue(AnalyticsDisplayFormatter.disclosureAccessibilityValue(isExpanded: providerDisclosure.wrappedValue))
                .accessibilityHint(AnalyticsDisplayFormatter.disclosureAccessibilityHint)
            }
            if !repository.commits.isEmpty {
                DisclosureGroup(isExpanded: commitsDisclosure) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(repository.commits, id: \.commitID) { commit in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(commit.commitID)
                                        .font(.caption.monospaced())
                                    Spacer()
                                    Text(AnalyticsDisplayFormatter.date(commit.committedAt))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                LabeledContent("Correlated estimated AI cost", value: AnalyticsDisplayFormatter.cost(commit.correlatedUsage.estimatedCostUSDValue))
                                LabeledContent("Correlation coverage", value: AnalyticsDisplayFormatter.commitCoverage(commit.coverage))
                                if let number = commit.pullRequestNumber {
                                    Text("PR #\(number) (local metadata)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Commit \(commit.commitID)")
                            .accessibilityValue(AnalyticsDisplayFormatter.commitAccessibilityValue(commit))
                        }
                    }
                } label: {
                    Text(AnalyticsDisplayFormatter.disclosureAccessibilityLabels.commits)
                }
                .accessibilityLabel(commitsAccessibilityLabel)
                .accessibilityValue(AnalyticsDisplayFormatter.disclosureAccessibilityValue(isExpanded: commitsDisclosure.wrappedValue))
                .accessibilityHint(AnalyticsDisplayFormatter.disclosureAccessibilityHint)
            }
        }
        .padding(.vertical, 3)
    }

}

public struct AnalyticsReasonDisplay: Identifiable, Equatable, Sendable {
    public let id: String
    public let text: String
    public let count: UInt64

    public var displayText: String { "\(text) (\(count))" }

    public init(id: String, text: String, count: UInt64) {
        self.id = id
        self.text = text
        self.count = count
    }
}

public enum AnalyticsDisplayFormatter {
    public static let disclosureAccessibilityLabels = (
        providerAndModel: "Provider and model metrics",
        commits: "Commits",
        diagnostics: "Analytics diagnostics",
        estimateDefinition: "Estimate definition"
    )
    public static let disclosureAccessibilityHint = "Expand or collapse this section"

    private static let reasonLabels: [String: String] = [
        "missingWorkspace": "Missing workspace",
        "invalidWorkspace": "Invalid workspace",
        "nonRepositoryWorkspace": "Non-repository workspace",
        "ambiguousRepository": "Ambiguous repository",
        "repositoryUnavailable": "Repository unavailable",
        "missingTimestamp": "Missing timestamp",
        "missingCost": "Missing pricing",
        "missingDuration": "Missing duration",
        "noEligibleCommit": "No eligible commit",
        "pendingCommitWindow": "Pending 4-hour window",
        "recordLimitReached": "Record/output limit",
        "gitOutputLimitReached": "Record/output limit",
        "gitTimedOut": "Git timeout",
        "gitUnavailable": "Git unavailable",
    ]

    private static let utcDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    public static let aboutEstimates = """
    Estimated cost uses local engine pricing and is not an invoice or subscription charge.
    Observed active AI-session time uses timestamp gaps no greater than three minutes and is not human coding time, keyboard time, or elapsed wall time.
    Correlated estimated AI cost is a deterministic same-repository four-hour association, not causal or measured commit cost.
    Coverage indicates eligible workspace, timestamp, pricing, duration, and Git evidence.
    A local PR number is metadata-only; it has no remote validation.
    """

    public static func repositoryState(_ state: String?) -> String {
        state == "available" ? "Available" : "Unavailable"
    }

    public static func repositoryStateCopy(_ state: String?) -> String {
        state == "available" ? "Git metadata available." : "Git metadata could not be safely read."
    }

    public static func repositoryCostCoverage(_ coverage: RepositoryCoverage, state: String? = nil) -> String {
        guard state != "unavailable" else { return "Unavailable" }
        return coverage.reasons["missingCost"] == nil ? "Complete" : "Partial"
    }

    public static func repositoryTimingCoverage(_ coverage: RepositoryCoverage, state: String? = nil) -> String {
        guard state != "unavailable" else { return "Unavailable" }
        if coverage.reasons["missingDuration"] != nil { return "Missing duration" }
        return coverage.timingPartial ? "Partial" : "Complete"
    }

    public static func providerCoverage(_ coverage: String) -> String {
        switch coverage {
        case "complete": "Complete"
        case "partial": "Partial"
        default: "Unavailable"
        }
    }

    public static func providerTimingCoverage(_ coverage: String) -> String {
        switch coverage {
        case "complete": "Complete"
        case "partial": "Partial"
        case "missingDuration": "Missing duration"
        default: "Unavailable"
        }
    }

    public static func commitCoverage(_ coverage: String) -> String {
        switch coverage {
        case "correlated": "Correlated"
        case "partial": "Partial"
        default: "Unavailable"
        }
    }

    public static func correlationCoverage(_ coverage: RepositoryCoverage) -> String {
        let statusReasons = unattributedReasonCopy(
            coverage.reasons.filter { $0.key == "noEligibleCommit" || $0.key == "pendingCommitWindow" }
        )
        let status = statusReasons.isEmpty ? "" : " · " + statusReasons.map(\.displayText).joined(separator: ", ")
        return "Assigned \(coverage.assignedFragments) · Unassigned \(coverage.unassignedFragments)\(status)"
    }

    public static func unattributedReasonCopy(_ reasons: [String: UInt64]) -> [AnalyticsReasonDisplay] {
        reasons.keys.sorted().compactMap { key in
            guard let label = reasonLabels[key], let count = reasons[key] else { return nil }
            return AnalyticsReasonDisplay(id: key, text: label, count: count)
        }
    }

    public static func gitReasonCopy(_ reasons: [String: UInt64]) -> [AnalyticsReasonDisplay] {
        let gitReasons = Set(["recordLimitReached", "gitOutputLimitReached", "gitTimedOut", "gitUnavailable"])
        return reasons.keys.sorted().compactMap { key in
            guard gitReasons.contains(key), let count = reasons[key] else { return nil }
            if key == "recordLimitReached" || key == "gitOutputLimitReached" {
                return AnalyticsReasonDisplay(
                    id: key,
                    text: "Repository inspection stopped at a safe limit",
                    count: count
                )
            }
            guard let label = reasonLabels[key] else { return nil }
            return AnalyticsReasonDisplay(id: key, text: label, count: count)
        }
    }

    public static func repositoryAccessibilityValue(_ repository: AnalyticsRepositoryAnalytics) -> String {
        let state = repositoryState(repository.state)
        let cost = repositoryCostCoverage(repository.coverage, state: repository.state)
        let timing = repositoryTimingCoverage(repository.coverage, state: repository.state)
        return "\(state); Estimated cost \(cost); Timing \(timing); \(correlationCoverage(repository.coverage))"
    }

    public static func modelAccessibilityValue(_ model: AnalyticsProviderModelAnalytics) -> String {
        "Estimated cost \(cost(model.usage.estimatedCostUSDValue)); Cost coverage \(providerCoverage(model.costCoverage)); Timing coverage \(providerTimingCoverage(model.timingCoverage)); Cost per 1K tokens \(metric(model.costPer1KTokens) ?? "Unavailable"); Tokens per observed active hour \(metric(model.tokensPerObservedActiveHour) ?? "Unavailable"); Milliseconds per 1K tokens \(metric(model.millisecondsPer1KTokens) ?? "Unavailable")"
    }

    public static func commitAccessibilityValue(_ commit: AnalyticsCommitAnalytics) -> String {
        let pullRequest = commit.pullRequestNumber.map { "; PR #\($0), local metadata" } ?? ""
        return "\(date(commit.committedAt)); Correlated estimated AI cost \(cost(commit.correlatedUsage.estimatedCostUSDValue))\(pullRequest)"
    }

    public static func refreshAccessibilityValue(isLoading: Bool) -> String {
        isLoading ? "Loading; Refresh unavailable" : "Ready"
    }

    public static func disclosureAccessibilityValue(isExpanded: Bool) -> String {
        isExpanded ? "Expanded" : "Collapsed"
    }

    public static var dateFormatterIdentity: ObjectIdentifier {
        ObjectIdentifier(utcDateFormatter)
    }

    public static func summaryCost(_ cost: Decimal, snapshot: AnalyticsSnapshot) -> String {
        let hasPartialCost = snapshot.coverage.reasons["missingCost"] != nil ||
            snapshot.coverage.reasons["recordLimitReached"] != nil ||
            snapshot.coverage.reasons["gitOutputLimitReached"] != nil ||
            snapshot.repositories.contains { $0.coverage.reasons["missingCost"] != nil }
        return hasPartialCost ? "\(AnalyticsDisplayFormatter.cost(cost)) (known subtotal)" : AnalyticsDisplayFormatter.cost(cost)
    }

    public static func repositoryAttributedEstimate(_ cost: Decimal?, knownSubtotal: Bool) -> String {
        guard let cost else { return "—" }
        let formatted = AnalyticsDisplayFormatter.cost(cost)
        return knownSubtotal ? "\(formatted) (known subtotal)" : formatted
    }

    public static func observedAIActivity(_ seconds: UInt64?) -> String {
        guard let seconds else { return "—" }
        return duration(seconds)
    }

    public static func diagnosticTitle(_ code: String) -> String {
        switch code {
        case "recordLimitReached": "Bounded record processing"
        case "gitOutputLimitReached": "Repository inspection output limit"
        default: reasonLabels[code] ?? "Limited diagnostics"
        }
    }

    public static func diagnosticUnit(_ unit: AnalyticsDiagnosticUnit) -> String {
        switch unit {
        case .fragments: "fragments"
        case .observations: "observations"
        case .inspectionFailures: "inspection failures"
        case .mixedBoundedProcessing: "mixed bounded processing"
        }
    }

    public static func diagnosticExplanation(_ code: String) -> String {
        switch code {
        case "missingDuration":
            "Missing response duration is distinct from the evidence used for observed AI activity."
        case "recordLimitReached":
            "This bounded-processing count has mixed units and unavailable causes; it does not establish equal counts or lost cost."
        case "gitOutputLimitReached":
            "Repository inspection output was safely bounded; it is not a fragment count."
        case "gitTimedOut", "gitUnavailable":
            "Repository inspection was unavailable or incomplete; no source-level cause is inferred."
        case "missingTimestamp":
            "Without a normalized timestamp, time coverage and a verified 30-day total remain incomplete."
        default:
            "This retained local diagnostic describes a limitation in the captured evidence."
        }
    }

    public static func compactTokens(_ canonical: String) -> String {
        compactInteger(canonical)
    }

    public static func tokens(_ canonical: String) -> String {
        compactTokens(canonical)
    }

    public static func metric(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    public static func cost(_ decimal: Decimal?) -> String {
        guard let decimal else { return "Unavailable" }
        return compactCost(NSDecimalNumber(decimal: decimal).stringValue)
    }

    public static func compactCost(_ canonical: String) -> String {
        guard let separator = canonical.firstIndex(of: ".") else {
            guard compactInteger(canonical) != "Unavailable" else { return "Unavailable" }
            if canonical.count <= 6,
               let decimal = Decimal(string: canonical, locale: Locale(identifier: "en_US_POSIX")) {
                return MetricFormatter.costUSD(decimal)
            }
            return "$\(compactInteger(canonical))"
        }
        let integerPart = String(canonical[..<separator])
        let fractionPart = String(canonical[canonical.index(after: separator)...])
        guard compactInteger(integerPart) != "Unavailable",
              !fractionPart.isEmpty,
              fractionPart.allSatisfy(\.isNumber) else { return "Unavailable" }
        if integerPart.count <= 6 {
            guard let decimal = Decimal(string: canonical, locale: Locale(identifier: "en_US_POSIX")) else { return "Unavailable" }
            return MetricFormatter.costUSD(decimal)
        }
        return "$\(compactInteger(integerPart))"
    }

    public static func tokensAccessibilityValue(_ canonical: String) -> String {
        guard compactInteger(canonical) != "Unavailable" else { return "Unavailable" }
        return "\(canonical) tokens"
    }

    private static func compactInteger(_ canonical: String) -> String {
        guard canonical == "0" || (canonical.first.map { ("1"..."9").contains(String($0)) } == true && canonical.allSatisfy(\.isNumber)) else {
            return "Unavailable"
        }
        if canonical == "0" || canonical.count <= 3 { return canonical }
        let group = (canonical.count - 1) / 3
        guard group <= 4 else { return "9999T+" }
        let leadingCount = canonical.count - group * 3
        let leading = String(canonical.prefix(leadingCount))
        let fraction = String(canonical.dropFirst(leadingCount).prefix(2)).replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
        let suffix = ["", "K", "M", "B", "T"][group]
        return fraction.isEmpty ? leading + suffix : leading + "." + fraction + suffix
    }

    public static func duration(_ seconds: UInt64?) -> String {
        guard let seconds else { return "Unavailable" }
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    public static func date(_ date: Date) -> String {
        utcDateFormatter.string(from: date)
    }
}
