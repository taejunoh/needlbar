public enum HeadlineQuotaSelector {
    public static func mostConstrained(_ snapshots: [ProviderSnapshot]) -> QuotaWindow? {
        snapshots
            .compactMap(\.quota)
            .flatMap(\.windows)
            .min { $0.remainingPercent < $1.remainingPercent }
    }
}
