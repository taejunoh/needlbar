public enum HeadlineQuotaSelector {
    public static func mostConstrained(_ snapshots: [ProviderSnapshot]) -> QuotaWindow? {
        snapshots
            .filter { $0.provider == .claude || $0.provider == .codex }
            .flatMap { snapshot in
                snapshot.quota?.windows.filter {
                    !(snapshot.provider == .claude && $0.id == QuotaWindow.claudeFableWeeklyID)
                } ?? []
            }
            .min { $0.remainingPercent < $1.remainingPercent }
    }
}
