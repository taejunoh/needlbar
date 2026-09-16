import SwiftUI
import NeedlbarCore

public enum ProviderAuthenticationAction: Equatable, Sendable {
    case browserLogin(title: String)
    case openCursorSpending(title: String)
    case openClaudeUsage(title: String)
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
    public let usageFreshness: PresentationFreshness
    public let quotaFreshness: PresentationFreshness
    public let quotaIsLastKnown: Bool
    public let quotaUnavailable: Bool
    public let quotaFailureReasonText: String?
    public let quotaLastCheckedText: String?

    public init(snapshot: ProviderSnapshot) {
        provider = snapshot.provider
        tokensToday = snapshot.usage.map { MetricFormatter.tokens($0.today.totalTokens) }
        estimatedCostToday = snapshot.usage.map { MetricFormatter.costUSD($0.today.estimatedCostUSD) }
        inputTokens = snapshot.usage.map { MetricFormatter.tokens($0.today.inputTokens) }
        outputTokens = snapshot.usage.map { MetricFormatter.tokens($0.today.outputTokens) }
        cacheReadTokens = snapshot.usage.map { MetricFormatter.tokens($0.today.cacheReadTokens) }
        // A present usage snapshot makes even a zero cache-write value explicitly known.
        cacheWriteTokens = snapshot.usage.map { MetricFormatter.tokens($0.today.cacheWriteTokens) }
        quotaWindows = snapshot.quota?.windows ?? []
        headlineQuotaRemaining = HeadlineQuotaSelector.mostConstrained([snapshot]).map { MetricFormatter.quotaRemaining($0.remainingPercent) }
        usageFreshness = PresentationFreshness(snapshot.usageStatus)
        quotaFreshness = PresentationFreshness(snapshot.quotaStatus)
        let claudeFallback = snapshot.provider == .claude
            && (snapshot.claudeQuotaFailureReason != nil || snapshot.quotaStatus != .fresh)
        quotaIsLastKnown = claudeFallback && snapshot.quota != nil
        quotaUnavailable = claudeFallback && snapshot.quota == nil
        quotaFailureReasonText = snapshot.claudeQuotaFailureReason?.displayText
        quotaLastCheckedText = quotaIsLastKnown
            ? snapshot.quotaLastSuccessfulAt.map(Self.localizedDateTime)
            : nil
    }

    public var requiresProviderSignIn: Bool {
        provider != .claude && quotaFreshness == .requiresAuthentication
    }

    public var authenticationAction: ProviderAuthenticationAction? {
        if provider == .claude, quotaFailureReasonText != nil {
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
            Text("Usage: \(presentation.usageFreshness.label) · Quota: \(presentation.quotaFreshness.label)")
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
            if presentation.quotaUnavailable {
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
            if let lastChecked = presentation.quotaLastCheckedText {
                Text("Last checked \(lastChecked)").font(.caption).foregroundStyle(.secondary)
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
                    Button("Retry") {
                        claudeUsageOpenFailed = !onAuthenticationAction(authenticationAction)
                    }
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
}

private extension ProviderAuthenticationAction {
    var title: String {
        switch self {
        case let .browserLogin(title), let .openCursorSpending(title), let .openClaudeUsage(title): title
        }
    }
}
