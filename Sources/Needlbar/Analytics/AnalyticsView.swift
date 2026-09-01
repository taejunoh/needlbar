import Foundation
import NeedlbarCore
import SwiftUI

public struct AnalyticsView: View {
    @ObservedObject private var viewModel: AnalyticsViewModel

    public init(viewModel: AnalyticsViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if viewModel.isLoading {
                    ProgressView(viewModel.statusCopy)
                        .controlSize(.small)
                } else if let snapshot = viewModel.snapshot {
                    snapshotContent(snapshot)
                } else {
                    Text(viewModel.statusCopy)
                        .foregroundStyle(.secondary)
                }
                GroupBox("About these estimates") {
                    Text(AnalyticsDisplayFormatter.aboutEstimates)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 640, minHeight: 400)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Local repository analytics")
                        .font(.title2.weight(.semibold))
                    Text("Last 30 days")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") { viewModel.refresh() }
                    .disabled(viewModel.isLoading)
            }
            Text("Local-only estimates from observed AI sessions and repository metadata. This is not a live source-control view.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let snapshot = viewModel.snapshot {
                Text("Generated \(AnalyticsDisplayFormatter.date(snapshot.generatedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if viewModel.presentationState == .stale || viewModel.presentationState == .fresh && viewModel.statusCopy != "Local analysis complete." {
                Text(viewModel.statusCopy)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func snapshotContent(_ snapshot: AnalyticsSnapshot) -> some View {
        let totalCost = snapshot.repositories.reduce(Decimal.zero) {
            $0 + ($1.usage.estimatedCostUSDValue ?? .zero)
        }
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Summary") {
                HStack(spacing: 26) {
                    summaryMetric("Estimated cost", AnalyticsDisplayFormatter.summaryCost(totalCost, snapshot: snapshot))
                    summaryMetric("Observed active AI-session time", AnalyticsDisplayFormatter.duration(observedTime(in: snapshot.repositories)))
                    summaryMetric("Coverage", coverageCopy(snapshot.coverage))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            GroupBox("Repositories") {
                if snapshot.repositories.isEmpty {
                    Text("No observed repositories in this analysis range.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(snapshot.repositories, id: \.repositoryID) { repository in
                            repositoryRow(repository)
                        }
                    }
                }
            }

            GroupBox("Unattributed") {
                HStack {
                    Text(AnalyticsDisplayFormatter.cost(snapshot.unattributed.usage.estimatedCostUSDValue ?? .zero))
                        .font(.headline.monospacedDigit())
                    Text("Estimated cost")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(snapshot.unattributed.fragments) fragments")
                        .foregroundStyle(.secondary)
                }
                if !snapshot.unattributed.reasons.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Some local usage could not be matched to a repository or timestamp.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(AnalyticsDisplayFormatter.unattributedReasonCopy(snapshot.unattributed.reasons), id: \.self) { reason in
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func repositoryRow(_ repository: AnalyticsRepositoryAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
                Text(AnalyticsDisplayFormatter.cost(repository.usage.estimatedCostUSDValue ?? .zero))
                    .font(.headline.monospacedDigit())
                Text("Estimated cost · \(AnalyticsDisplayFormatter.repositoryCostCoverage(repository.coverage, state: repository.state))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Text("\(AnalyticsDisplayFormatter.tokens(repository.usage.totalTokens)) tokens")
                Text(AnalyticsDisplayFormatter.duration(repository.observedActiveTimeSecondsValue))
                Text("Timing \(AnalyticsDisplayFormatter.repositoryTimingCoverage(repository.coverage, state: repository.state))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(AnalyticsDisplayFormatter.correlationCoverage(repository.coverage))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !AnalyticsDisplayFormatter.gitReasonCopy(repository.coverage.reasons).isEmpty {
                Text(AnalyticsDisplayFormatter.gitReasonCopy(repository.coverage.reasons).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if repository.state == "available" && !repository.providerModels.isEmpty {
                DisclosureGroup("Provider and model metrics") {
                    ForEach(Array(repository.providerModels.enumerated()), id: \.offset) { _, model in
                        HStack {
                            Text("\(model.provider) · \(model.model)")
                            Spacer()
                            Text(AnalyticsDisplayFormatter.cost(model.usage.estimatedCostUSDValue ?? .zero))
                            Text("Cost \(AnalyticsDisplayFormatter.providerCoverage(model.costCoverage))")
                                .foregroundStyle(.secondary)
                            Text("Timing \(AnalyticsDisplayFormatter.providerTimingCoverage(model.timingCoverage))")
                                .foregroundStyle(.secondary)
                            Text(AnalyticsDisplayFormatter.metric(model.costPer1KTokens).map { "\($0)/1K" } ?? "Unavailable")
                                .foregroundStyle(.secondary)
                            Text(AnalyticsDisplayFormatter.metric(model.tokensPerObservedActiveHour).map { "\($0)/hr" } ?? "Unavailable")
                                .foregroundStyle(.secondary)
                            Text(AnalyticsDisplayFormatter.metric(model.millisecondsPer1KTokens).map { "\($0) ms/1K" } ?? "Unavailable")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }
            if !repository.commits.isEmpty {
                DisclosureGroup("Commits") {
                    ForEach(repository.commits, id: \.commitID) { commit in
                        HStack {
                            Text(commit.commitID)
                                .font(.caption.monospaced())
                            Text(AnalyticsDisplayFormatter.date(commit.committedAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(AnalyticsDisplayFormatter.cost(commit.correlatedUsage.estimatedCostUSDValue ?? .zero))
                            Text("Correlated estimated AI cost")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let number = commit.pullRequestNumber {
                                Text("PR #\(number) (local metadata)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func summaryMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
        }
    }

    private func coverageCopy(_ coverage: AnalyticsCoverage) -> String {
        let (total, overflow) = coverage.attributedFragments.addingReportingOverflow(coverage.unattributedFragments)
        guard !overflow, total > 0 else { return "Unavailable" }
        let percent = (Double(coverage.attributedFragments) / Double(total)) * 100
        let value = String(format: "%.0f%%", locale: Locale(identifier: "en_US_POSIX"), percent)
        return coverage.reasons.isEmpty ? value : "\(value) · Partial"
    }

    private func repositoryCoverageCopy(_ coverage: RepositoryCoverage) -> String {
        let (total, overflow) = coverage.assignedFragments.addingReportingOverflow(coverage.unassignedFragments)
        guard !overflow, total > 0 else { return "Unavailable" }
        let percent = (Double(coverage.assignedFragments) / Double(total)) * 100
        return String(format: "%.0f%%", locale: Locale(identifier: "en_US_POSIX"), percent)
    }

    private func observedTime(in repositories: [AnalyticsRepositoryAnalytics]) -> UInt64? {
        var total: UInt64 = 0
        for repository in repositories {
            guard let seconds = repository.observedActiveTimeSecondsValue else { return nil }
            let (next, overflow) = total.addingReportingOverflow(seconds)
            guard !overflow else { return nil }
            total = next
        }
        return total
    }
}

public enum AnalyticsDisplayFormatter {
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

    public static func correlationCoverage(_ coverage: RepositoryCoverage) -> String {
        let statusReasons = unattributedReasonCopy(
            coverage.reasons.filter { $0.key == "noEligibleCommit" || $0.key == "pendingCommitWindow" }
        )
        let status = statusReasons.isEmpty ? "" : " · " + statusReasons.joined(separator: ", ")
        return "Assigned \(coverage.assignedFragments) · Unassigned \(coverage.unassignedFragments)\(status)"
    }

    public static func unattributedReasonCopy(_ reasons: [String: UInt64]) -> [String] {
        reasons.keys.sorted().compactMap { key in
            guard let label = reasonLabels[key], let count = reasons[key] else { return nil }
            return "\(label) (\(count))"
        }
    }

    public static func gitReasonCopy(_ reasons: [String: UInt64]) -> [String] {
        let gitReasons = Set(["recordLimitReached", "gitOutputLimitReached", "gitTimedOut", "gitUnavailable"])
        return unattributedReasonCopy(reasons.filter { gitReasons.contains($0.key) })
            .map { value in
                guard value.hasPrefix("Record/output limit"),
                      let countStart = value.firstIndex(of: "(") else { return value }
                return "Repository inspection stopped at a safe limit " + String(value[countStart...])
            }
    }

    public static func summaryCost(_ cost: Decimal, snapshot: AnalyticsSnapshot) -> String {
        let hasPartialCost = snapshot.coverage.reasons["missingCost"] != nil ||
            snapshot.coverage.reasons["recordLimitReached"] != nil ||
            snapshot.coverage.reasons["gitOutputLimitReached"] != nil ||
            snapshot.repositories.contains { $0.coverage.reasons["missingCost"] != nil }
        return hasPartialCost ? "\(AnalyticsDisplayFormatter.cost(cost)) (known subtotal)" : AnalyticsDisplayFormatter.cost(cost)
    }

    public static func tokens(_ canonical: String) -> String {
        guard let value = UInt64(canonical) else { return "Unavailable" }
        return MetricFormatter.tokens(value)
    }

    public static func metric(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    public static func cost(_ decimal: Decimal?) -> String {
        guard let decimal else { return "Unavailable" }
        return MetricFormatter.costUSD(decimal)
    }

    public static func duration(_ seconds: UInt64?) -> String {
        guard let seconds else { return "Unavailable" }
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    public static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
