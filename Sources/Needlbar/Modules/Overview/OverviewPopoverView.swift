import SwiftUI
import NeedlbarCore

public enum PresentationFreshness: Equatable, Sendable {
    case fresh
    case stale
    case unavailable
    case requiresAuthentication
    case error

    init(_ status: DataStatus) {
        switch status {
        case .fresh:
            self = .fresh
        case .stale:
            self = .stale
        case .unavailable:
            self = .unavailable
        case .requiresAuthentication:
            self = .requiresAuthentication
        case .error:
            self = .error
        }
    }

    var label: String {
        switch self {
        case .fresh: "Fresh"
        case .stale: "Stale"
        case .unavailable: "Unavailable"
        case .requiresAuthentication: "Authentication required"
        case .error: "Refresh failed"
        }
    }
}

public struct OverviewDailyUsagePoint: Equatable, Sendable {
    public let provider: ProviderID
    public let date: String
    public let totalTokens: UInt64

    public init(provider: ProviderID, date: String, totalTokens: UInt64) {
        self.provider = provider
        self.date = date
        self.totalTokens = totalTokens
    }
}

public struct OverviewPopoverPresentation: Equatable, Sendable {
    public let providerRows: [ProviderPopoverPresentation]
    public let tokensToday: String?
    public let estimatedCostToday: String?
    public let headlineQuotaRemaining: String?
    public let sevenDayTokens: [UInt64]?

    public init(
        snapshots: [ProviderSnapshot],
        dailyUsage: [OverviewDailyUsagePoint],
        enabledProviders: Set<ProviderID> = Set(ProviderID.allCases)
    ) {
        providerRows = ProviderID.allCases.map { provider in
            ProviderPopoverPresentation(snapshot: snapshots.first { $0.provider == provider } ?? .unavailable(for: provider))
        }
        let usages = snapshots.compactMap(\.usage)
        tokensToday = Self.checkedTokenTotal(usages.map(\.today.totalTokens)).map(MetricFormatter.tokens)
        estimatedCostToday = usages.isEmpty ? nil : MetricFormatter.costUSD(usages.reduce(Decimal.zero) { $0 + $1.today.estimatedCostUSD })
        headlineQuotaRemaining = HeadlineQuotaSelector.mostConstrained(
            snapshots.filter { enabledProviders.contains($0.provider) }
        ).map { MetricFormatter.quotaRemaining($0.remainingPercent) }
        sevenDayTokens = Self.dailyTotals(dailyUsage)
    }

    private static func checkedTokenTotal(_ values: [UInt64]) -> UInt64? {
        guard !values.isEmpty else { return nil }
        return values.reduce(Optional<UInt64>.some(0)) { total, value in
            guard let total else { return nil }
            let (next, overflow) = total.addingReportingOverflow(value)
            return overflow ? nil : next
        }
    }

    private static func dailyTotals(_ points: [OverviewDailyUsagePoint]) -> [UInt64]? {
        guard !points.isEmpty else { return nil }
        var totals: [String: UInt64] = [:]
        for point in points {
            let total = totals[point.date, default: 0]
            let (next, overflow) = total.addingReportingOverflow(point.totalTokens)
            guard !overflow else { return nil }
            totals[point.date] = next
        }
        return totals.keys.sorted().compactMap { totals[$0] }
    }
}

public struct OverviewPopoverView: View {
    private let presentation: OverviewPopoverPresentation
    private let onShowSettings: () -> Void
    private let onShowAnalytics: () -> Void

    public init(
        snapshots: [ProviderSnapshot],
        configuration: ModuleConfiguration,
        onShowSettings: @escaping () -> Void = {},
        onShowAnalytics: @escaping () -> Void = {}
    ) {
        let dailyUsage = snapshots.flatMap { snapshot in
            snapshot.usage?.last7DaysDaily.map {
                OverviewDailyUsagePoint(provider: snapshot.provider, date: $0.date, totalTokens: $0.totalTokens)
            } ?? []
        }
        let enabledProviders = Set(
            configuration.enabledModuleIDs.compactMap(\.provider)
        )
        presentation = OverviewPopoverPresentation(
            snapshots: snapshots,
            dailyUsage: dailyUsage,
            enabledProviders: enabledProviders
        )
        self.onShowSettings = onShowSettings
        self.onShowAnalytics = onShowAnalytics
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("AI Usage")
                    .font(.headline)
                Spacer()
                if let quota = presentation.headlineQuotaRemaining {
                    Text("Quota \(quota)")
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 16) {
                metric("Today", presentation.tokensToday)
                metric("Cost", presentation.estimatedCostToday)
            }

            SevenDayUsageChart(tokens: presentation.sevenDayTokens)

            Divider()
            ForEach(presentation.providerRows, id: \.provider) { row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        HStack(spacing: 6) {
                            ProviderBrandIcon(provider: row.provider, accessibility: .decorative)
                            Text(row.provider.displayName)
                        }
                        Spacer()
                        if let quota = row.headlineQuotaRemaining {
                            Text(quota)
                        } else {
                            Text(row.quotaFreshness.label)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if row.usageFreshness != .fresh || row.quotaFreshness != .fresh {
                        Text("Usage: \(row.usageFreshness.label) · Quota: \(row.quotaFreshness.label)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()
            HStack {
                Button("Settings", action: onShowSettings)
                Spacer()
                Button("Analytics…", action: onShowAnalytics)
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
}

extension ProviderID {
    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }
}

private extension ProviderSnapshot {
    static func unavailable(for provider: ProviderID) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: provider,
            usage: nil,
            quota: nil,
            usageStatus: .unavailable,
            quotaStatus: .unavailable,
            updatedAt: .now
        )
    }
}
