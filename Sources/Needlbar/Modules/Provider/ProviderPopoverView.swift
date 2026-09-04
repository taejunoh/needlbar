import SwiftUI
import NeedlbarCore

public enum ProviderAuthenticationAction: Equatable, Sendable {
    case browserLogin(title: String)
    case openCursorSpending(title: String)
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
    }

    public var requiresProviderSignIn: Bool {
        quotaFreshness == .requiresAuthentication
    }

    public var authenticationAction: ProviderAuthenticationAction? {
        if provider == .cursor, quotaWindows.isEmpty, quotaFreshness != .fresh {
            return .openCursorSpending(title: "Open Cursor Spending")
        }

        guard requiresProviderSignIn else { return nil }
        switch provider {
        case .claude:
            return .browserLogin(title: "Sign in with Claude")
        case .codex:
            return .browserLogin(title: "Sign in with ChatGPT")
        case .cursor:
            return nil
        }
    }
}

public struct ProviderPopoverView: View {
    private let presentation: ProviderPopoverPresentation
    private let onRetry: () -> Void
    private let onAuthenticationAction: (ProviderAuthenticationAction) -> Void

    public init(
        snapshot: ProviderSnapshot,
        onRetry: @escaping () -> Void = {},
        onAuthenticationAction: @escaping (ProviderAuthenticationAction) -> Void = { _ in }
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
            if presentation.quotaWindows.isEmpty {
                Text(presentation.quotaFreshness.label).foregroundStyle(.secondary)
            } else {
                ForEach(presentation.quotaWindows) { window in
                    QuotaWindowRow(window: window)
                }
            }

            if let authenticationAction = presentation.authenticationAction {
                Button(authenticationAction.title) {
                    onAuthenticationAction(authenticationAction)
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
        case let .browserLogin(title), let .openCursorSpending(title): title
        }
    }
}
