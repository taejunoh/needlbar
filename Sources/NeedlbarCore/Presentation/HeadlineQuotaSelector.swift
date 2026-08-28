public enum HeadlineQuotaSelector {
    public static func mostConstrained(_ snapshots: [ProviderSnapshot]) -> QuotaWindow? {
        snapshots
            .filter { $0.provider == .claude || $0.provider == .codex }
            .compactMap(\.quota)
            .flatMap(\.windows)
            .min { $0.remainingPercent < $1.remainingPercent }
    }
}
