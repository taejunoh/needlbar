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
                    .accessibilityLabel("Refresh analytics")
                    .accessibilityValue(AnalyticsDisplayFormatter.refreshAccessibilityValue(isLoading: viewModel.isLoading))
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)], alignment: .leading, spacing: 10) {
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
                    LazyVStack(alignment: .leading, spacing: 10) {
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
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(AnalyticsDisplayFormatter.unattributedReasonCopy(snapshot.unattributed.reasons)) { reason in
                                Text(reason.displayText)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func repositoryRow(_ repository: AnalyticsRepositoryAnalytics) -> some View {
        let gitReasons = AnalyticsDisplayFormatter.gitReasonCopy(repository.coverage.reasons)
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
                Text(AnalyticsDisplayFormatter.cost(repository.usage.estimatedCostUSDValue ?? .zero))
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
                DisclosureGroup(AnalyticsDisplayFormatter.disclosureAccessibilityLabels.providerAndModel) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(repository.providerModels.enumerated()), id: \.offset) { _, model in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(model.provider) · \(model.model)")
                                    .font(.subheadline.weight(.medium))
                                LabeledContent("Estimated cost", value: AnalyticsDisplayFormatter.cost(model.usage.estimatedCostUSDValue ?? .zero))
                                LabeledContent("Cost coverage", value: AnalyticsDisplayFormatter.providerCoverage(model.costCoverage))
                                LabeledContent("Timing coverage", value: AnalyticsDisplayFormatter.providerTimingCoverage(model.timingCoverage))
                                LabeledContent("Cost per 1K tokens", value: AnalyticsDisplayFormatter.metric(model.costPer1KTokens) ?? "Unavailable")
                                LabeledContent("Tokens per observed active hour", value: AnalyticsDisplayFormatter.metric(model.tokensPerObservedActiveHour) ?? "Unavailable")
                                LabeledContent("Milliseconds per 1K tokens", value: AnalyticsDisplayFormatter.metric(model.millisecondsPer1KTokens) ?? "Unavailable")
                            }
                            .lineLimit(1)
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("\(model.provider) \(model.model)")
                            .accessibilityValue(AnalyticsDisplayFormatter.modelAccessibilityValue(model))
                            .accessibilityHint(AnalyticsDisplayFormatter.disclosureAccessibilityHint)
                        }
                    }
                }
                .accessibilityLabel(AnalyticsDisplayFormatter.disclosureAccessibilityLabels.providerAndModel)
                .accessibilityHint(AnalyticsDisplayFormatter.disclosureAccessibilityHint)
            }
            if !repository.commits.isEmpty {
                DisclosureGroup(AnalyticsDisplayFormatter.disclosureAccessibilityLabels.commits) {
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
                                LabeledContent("Correlated estimated AI cost", value: AnalyticsDisplayFormatter.cost(commit.correlatedUsage.estimatedCostUSDValue ?? .zero))
                                if let number = commit.pullRequestNumber {
                                    Text("PR #\(number) (local metadata)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .lineLimit(1)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Commit \(commit.commitID)")
                            .accessibilityValue(AnalyticsDisplayFormatter.commitAccessibilityValue(commit))
                        }
                    }
                }
                .accessibilityLabel(AnalyticsDisplayFormatter.disclosureAccessibilityLabels.commits)
                .accessibilityHint(AnalyticsDisplayFormatter.disclosureAccessibilityHint)
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
        let counts = "\(coverage.attributedFragments) attributed · \(coverage.unattributedFragments) unattributed"
        return coverage.reasons.isEmpty ? "\(value) · \(counts)" : "\(value) · \(counts) · Partial"
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
        commits: "Commits"
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
