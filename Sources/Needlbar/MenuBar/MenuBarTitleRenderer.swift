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
            let total = snapshots.reduce(UInt64.zero) { $0 + ($1.usage?.today.totalTokens ?? 0) }
            return MetricFormatter.tokens(total)
        case .costToday:
            let total = snapshots.reduce(Decimal.zero) { $0 + ($1.usage?.today.estimatedCostUSD ?? 0) }
            return MetricFormatter.costUSD(total)
        }
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
