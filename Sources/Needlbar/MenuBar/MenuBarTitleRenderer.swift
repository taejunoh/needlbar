import Foundation
import NeedlbarCore

public enum MenuBarTitleRenderer {
    public static func render(
        module: MenuBarModule,
        snapshot: ProviderSnapshot?,
        allSnapshots: [ProviderSnapshot],
        configuration: ModuleConfiguration
    ) -> String {
        let settings = configuration.settings(for: module.id)
        let metricValue: String?

        if module.id == .overview {
            metricValue = overviewMetric(
                settings.metric,
                snapshots: allSnapshots,
                configuration: configuration
            )
        } else {
            metricValue = providerMetric(settings.metric, snapshot: snapshot)
        }

        guard let metricValue else { return "\(module.title) —" }
        return "\(module.title) \(metricValue)"
    }

    private static func overviewMetric(
        _ metric: MenuBarMetric,
        snapshots: [ProviderSnapshot],
        configuration: ModuleConfiguration
    ) -> String? {
        switch metric {
        case .quotaRemaining:
            let enabledProviderSnapshots = snapshots.filter { snapshot in
                guard let module = MenuModuleID(rawValue: snapshot.provider.rawValue) else { return false }
                return configuration.settings(for: module).isEnabled
            }
            return HeadlineQuotaSelector.mostConstrained(enabledProviderSnapshots)
                .map { MetricFormatter.quotaRemaining($0.remainingPercent) }
        case .tokensToday:
            let tokenValues = snapshots.compactMap(\.usage?.today.totalTokens)
            guard let total = checkedTokenTotal(tokenValues) else { return nil }
            return MetricFormatter.tokens(total)
        case .costToday:
            let costValues = snapshots.compactMap(\.usage?.today.estimatedCostUSD)
            guard !costValues.isEmpty else { return nil }
            let total = costValues.reduce(Decimal.zero, +)
            return MetricFormatter.costUSD(total)
        }
    }

    private static func checkedTokenTotal(_ values: [UInt64]) -> UInt64? {
        guard !values.isEmpty else { return nil }

        var total: UInt64 = 0
        for value in values {
            let (nextTotal, overflow) = total.addingReportingOverflow(value)
            guard !overflow else { return nil }
            total = nextTotal
        }
        return total
    }

    private static func providerMetric(_ metric: MenuBarMetric, snapshot: ProviderSnapshot?) -> String? {
        guard let snapshot else { return nil }

        switch metric {
        case .quotaRemaining:
            return HeadlineQuotaSelector.mostConstrained([snapshot])
                .map { MetricFormatter.quotaRemaining($0.remainingPercent) }
        case .tokensToday:
            return snapshot.usage.map { MetricFormatter.tokens($0.today.totalTokens) }
        case .costToday:
            return snapshot.usage.map { MetricFormatter.costUSD($0.today.estimatedCostUSD) }
        }
    }
}
