import SwiftUI
import NeedlbarCore

public enum ProviderAuthenticationAction: Equatable, Sendable {
    case browserLogin(title: String)
    case openCursorSpending(title: String)
    case openClaudeUsage(title: String)
}

public struct ClaudePopoverQuotaDetail: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let remaining: String
    public let resetCaption: String?
    public let isLastKnown: Bool
    public let sourceLabel: String
    public let observationLabel: String
    public let observedAt: Date?

    init(id: String, title: String, window: DisplayedClaudeWindow) {
        self.id = id
        self.title = title
        remaining = MetricFormatter.quotaRemaining(window.remainingPercent)
        isLastKnown = window.isLastKnown
        sourceLabel = window.source == .claudeCodeStatusLine ? "Reported by Claude Code" : "Claude usage"
        observationLabel = window.source == .claudeCodeStatusLine ? "Received locally" : "Last checked"
        observedAt = window.observedAt
        resetCaption = window.isLastKnown ? nil : MetricFormatter.reset(window.resetsAt).map { "Resets \($0)" } ?? "Reset unavailable"
    }
}

public struct ProviderPopoverPresentation: Equatable, Sendable {
    public let provider: ProviderID
    public let tokensToday: String?
    public let estimatedCostToday: String?
    public let inputTokens: String?
    public let outputTokens: String?
    public let cacheReadTokens: String?
    public let cacheWriteTokens: String?
    public let quotaWindows: [QuotaWindow]
    public let headlineQuotaRemaining: String?
    public let lastKnownQuotaRemaining: String?
    public let usageFreshness: PresentationFreshness
    public let quotaFreshness: PresentationFreshness
    public let quotaIsLastKnown: Bool
    public let quotaUnavailable: Bool
    public let quotaFailureReasonText: String?
    public let quotaLastCheckedText: String?
    public let quotaSourceText: String?
    public let quotaObservationLabel: String
    public let claudeFiveHour: ClaudePopoverQuotaDetail?
    public let claudeSevenDay: ClaudePopoverQuotaDetail?
    public let claudeFable: ClaudePopoverQuotaDetail?
    public let claudeOtherWindows: [ClaudePopoverQuotaDetail]
    public let fableIsLastKnown: Bool
    public let fableLastCheckedText: String?
    public let hasRecentClaudeQuota: Bool

    public init(snapshot: ProviderSnapshot, now: Date = .now) {
        provider = snapshot.provider
        tokensToday = snapshot.usage.map { MetricFormatter.tokens($0.today.totalTokens) }
        estimatedCostToday = snapshot.usage.map { MetricFormatter.costUSD($0.today.estimatedCostUSD) }
        inputTokens = snapshot.usage.map { MetricFormatter.tokens($0.today.inputTokens) }
        outputTokens = snapshot.usage.map { MetricFormatter.tokens($0.today.outputTokens) }
        cacheReadTokens = snapshot.usage.map { MetricFormatter.tokens($0.today.cacheReadTokens) }
        // A present usage snapshot makes even a zero cache-write value explicitly known.
        cacheWriteTokens = snapshot.usage.map { MetricFormatter.tokens($0.today.cacheWriteTokens) }
        quotaWindows = snapshot.quota?.windows ?? []
        usageFreshness = PresentationFreshness(snapshot.usageStatus)
        var resolvedQuotaFreshness = PresentationFreshness(snapshot.quotaStatus)
        if snapshot.provider == .claude {
            let selected = ClaudeQuotaPresentationSelector.select(snapshot: snapshot, now: now)
            claudeFiveHour = selected.fiveHour.map { .init(id: "claude.session", title: "Session", window: $0) }
            claudeSevenDay = selected.sevenDay.map { .init(id: "claude.weekly", title: "Weekly", window: $0) }
            claudeFable = selected.fable.map { .init(id: QuotaWindow.claudeFableWeeklyID, title: "Fable weekly", window: $0) }
            fableIsLastKnown = selected.fable?.isLastKnown ?? false
            fableLastCheckedText = selected.fable.flatMap { window in
                window.isLastKnown ? window.observedAt.map(Self.localizedDateTime) : nil
            }

            let main = [selected.fiveHour, selected.sevenDay].compactMap { $0 }
            let fallback = quotaWindows.filter { !["claude.session", "claude.weekly", QuotaWindow.claudeFableWeeklyID].contains($0.id) }
            let projectedFallback: [DisplayedClaudeWindow] = main.isEmpty
                ? fallback.map { ClaudeQuotaPresentationSelector.directWindow($0, snapshot: snapshot, now: now) }
                : []
            claudeOtherWindows = zip(fallback, projectedFallback).map { window, display in
                ClaudePopoverQuotaDetail(id: window.id, title: window.title, window: display)
            }
            let recent = main.filter { !$0.isLastKnown }
            let recentFallback = projectedFallback.filter { !$0.isLastKnown }
            hasRecentClaudeQuota = !recent.isEmpty || !recentFallback.isEmpty
            headlineQuotaRemaining = (recent.map(\.remainingPercent) + recentFallback.map(\.remainingPercent))
                .min().map(MetricFormatter.quotaRemaining)
            lastKnownQuotaRemaining = hasRecentClaudeQuota ? nil :
                (main.map(\.remainingPercent) + projectedFallback.map(\.remainingPercent))
                    .min().map(MetricFormatter.quotaRemaining)

            let primary = (recent + recentFallback).min { $0.remainingPercent < $1.remainingPercent }
                ?? (main + projectedFallback).min { $0.remainingPercent < $1.remainingPercent }
            quotaSourceText = primary.map { $0.source == .claudeCodeStatusLine ? "Reported by Claude Code" : "Claude usage" }
                ?? (!fallback.isEmpty ? "Claude usage" : nil)
            quotaObservationLabel = primary?.source == .claudeCodeStatusLine ? "Received locally" : "Last checked"
            quotaLastCheckedText = primary?.observedAt.map(Self.localizedDateTime)
            quotaIsLastKnown = !hasRecentClaudeQuota && (!main.isEmpty || !projectedFallback.isEmpty)
            quotaUnavailable = !hasRecentClaudeQuota && main.isEmpty && projectedFallback.isEmpty
            quotaFailureReasonText = hasRecentClaudeQuota ? nil : snapshot.claudeQuotaFailureReason?.displayText
            if hasRecentClaudeQuota {
                resolvedQuotaFreshness = .fresh
            } else if (!main.isEmpty || !projectedFallback.isEmpty), snapshot.quotaStatus == .fresh {
                resolvedQuotaFreshness = .stale
            }
        } else {
            claudeFiveHour = nil
            claudeSevenDay = nil
            claudeFable = nil
            claudeOtherWindows = []
            fableIsLastKnown = false
            fableLastCheckedText = nil
            hasRecentClaudeQuota = false
            quotaSourceText = nil
            quotaObservationLabel = "Last checked"
            headlineQuotaRemaining = HeadlineQuotaSelector.mostConstrained([snapshot], now: now)
                .map { MetricFormatter.quotaRemaining($0.remainingPercent) }
            lastKnownQuotaRemaining = nil
            quotaIsLastKnown = false
            quotaUnavailable = false
            quotaFailureReasonText = nil
            quotaLastCheckedText = nil
        }
        quotaFreshness = resolvedQuotaFreshness
    }

    public var requiresProviderSignIn: Bool {
        provider != .claude && quotaFreshness == .requiresAuthentication
    }

    public var freshnessSummary: String {
        let usage = "Usage: \(usageFreshness.label)"
        guard !(provider == .claude && (quotaFailureReasonText != nil
            || quotaSourceText == "Reported by Claude Code")) else { return usage }
        return "\(usage) · Quota: \(quotaFreshness.label)"
    }

    public var authenticationAction: ProviderAuthenticationAction? {
        if provider == .claude, !hasRecentClaudeQuota || quotaSourceText == "Reported by Claude Code" {
            return .openClaudeUsage(title: "View Claude usage")
        }
        if provider == .cursor, quotaWindows.isEmpty, quotaFreshness != .fresh {
            return .openCursorSpending(title: "Open Cursor Spending")
        }

        guard requiresProviderSignIn else { return nil }
        switch provider {
        case .claude:
            return nil
        case .codex:
            return .browserLogin(title: "Sign in with ChatGPT")
        case .cursor:
            return nil
        }
    }

    private static func localizedDateTime(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }
}

public struct ProviderPopoverView: View {
    private let presentation: ProviderPopoverPresentation
    private let onRetry: () -> Void
    private let onAuthenticationAction: (ProviderAuthenticationAction) -> Bool
    @State private var claudeUsageOpenFailed = false

    public init(
        snapshot: ProviderSnapshot,
        onRetry: @escaping () -> Void = {},
        onAuthenticationAction: @escaping (ProviderAuthenticationAction) -> Bool = { _ in false }
    ) {
        presentation = ProviderPopoverPresentation(snapshot: snapshot)
        self.onRetry = onRetry
        self.onAuthenticationAction = onAuthenticationAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ProviderBrandIcon(provider: presentation.provider, accessibility: .decorative)
                Text(presentation.provider.displayName)
                    .font(.headline)
                Spacer()
            }
            Text(presentation.freshnessSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                metric("Today", presentation.tokensToday)
                metric("Cost", presentation.estimatedCostToday)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                tokenRow("Input", presentation.inputTokens)
                tokenRow("Output", presentation.outputTokens)
                tokenRow("Cache read", presentation.cacheReadTokens)
                if let cacheWriteTokens = presentation.cacheWriteTokens {
                    tokenRow("Cache write", cacheWriteTokens)
                }
            }

            Divider()
            Text("Quota").font(.subheadline.weight(.medium))
            if presentation.provider == .claude {
                if let source = presentation.quotaSourceText {
                    Text(source).font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel(source)
                }
                if presentation.quotaUnavailable {
                    Text("Quota unavailable").foregroundStyle(.secondary)
                }
                if presentation.quotaIsLastKnown {
                    Text("Last known").font(.caption).foregroundStyle(.secondary)
                }
                if let window = presentation.claudeFiveHour { claudeQuotaRow(window) }
                if let window = presentation.claudeSevenDay { claudeQuotaRow(window) }
                ForEach(presentation.claudeOtherWindows) { claudeQuotaRow($0) }
                if let window = presentation.claudeFable {
                    Text("Fable · \(window.isLastKnown ? "Last known" : "Claude usage")")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel("Fable · \(window.isLastKnown ? "Last known" : "Claude usage")")
                    claudeQuotaRow(window, showObservation: false)
                    if let checked = presentation.fableLastCheckedText {
                        Text("Last checked \(checked)").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Fable weekly · Unavailable").font(.caption).foregroundStyle(.secondary)
                }
            } else if presentation.quotaUnavailable {
                Text("Quota unavailable").foregroundStyle(.secondary)
            } else if presentation.quotaWindows.isEmpty {
                Text(presentation.quotaFreshness.label).foregroundStyle(.secondary)
            } else {
                if presentation.quotaIsLastKnown {
                    Text("Last known").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(presentation.quotaWindows) { window in
                    QuotaWindowRow(window: window, isLastKnown: presentation.quotaIsLastKnown)
                }
            }
            if let reason = presentation.quotaFailureReasonText {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
            if presentation.provider != .claude, let lastChecked = presentation.quotaLastCheckedText {
                Text("\(presentation.quotaObservationLabel) \(lastChecked)").font(.caption).foregroundStyle(.secondary)
            }

            if let authenticationAction = presentation.authenticationAction {
                Button(authenticationAction.title) {
                    if case .openClaudeUsage = authenticationAction {
                        claudeUsageOpenFailed = !onAuthenticationAction(authenticationAction)
                    } else {
                        _ = onAuthenticationAction(authenticationAction)
                    }
                }
                if claudeUsageOpenFailed {
                    Text("Couldn't open Claude usage. Try again.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Couldn't open Claude usage. Try again.")
                }
            } else if presentation.requiresProviderSignIn {
                Button("Retry", action: onRetry)
            }
        }
        .padding()
        .frame(width: 300)
    }

    @ViewBuilder
    private func metric(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value ?? "—").font(.title3.monospacedDigit())
        }
    }

    @ViewBuilder
    private func tokenRow(_ title: String, _ value: String?) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value ?? "—").monospacedDigit()
        }
    }

    @ViewBuilder
    private func claudeQuotaRow(_ detail: ClaudePopoverQuotaDetail, showObservation: Bool = true) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(detail.title)
                Text(detail.sourceLabel).font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel(detail.sourceLabel)
                if showObservation {
                    if let observedAt = detail.observedAt {
                        Text("\(detail.observationLabel) \(DateFormatter.localizedString(from: observedAt, dateStyle: .medium, timeStyle: .short))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if detail.isLastKnown {
                    Text("Last known").font(.caption).foregroundStyle(.secondary)
                }
                if let reset = detail.resetCaption {
                    Text(reset).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(detail.remaining).monospacedDigit()
        }
    }
}

private extension ProviderAuthenticationAction {
    var title: String {
        switch self {
        case let .browserLogin(title), let .openCursorSpending(title), let .openClaudeUsage(title): title
        }
    }
}
