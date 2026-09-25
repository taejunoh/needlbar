import Foundation

public enum HeadlineQuotaSelector {
    public static func mostConstrained(_ snapshots: [ProviderSnapshot], now: Date = .now) -> QuotaWindow? {
        snapshots
            .filter { $0.provider == .claude || $0.provider == .codex }
            .flatMap { snapshot in
                guard snapshot.provider == .claude else { return snapshot.quota?.windows ?? [] }
                let selected = ClaudeQuotaPresentationSelector.select(snapshot: snapshot, now: now)
                let known: [QuotaWindow] = [
                    selected.fiveHour.flatMap { window in
                        window.isLastKnown && window.source == .claudeCodeStatusLine ? nil : try? QuotaWindow(id: "claude.session", title: "Session", usedPercent: 100 - window.remainingPercent, resetsAt: window.resetsAt)
                    },
                    selected.sevenDay.flatMap { window in
                        window.isLastKnown && window.source == .claudeCodeStatusLine ? nil : try? QuotaWindow(id: "claude.weekly", title: "Weekly", usedPercent: 100 - window.remainingPercent, resetsAt: window.resetsAt)
                    },
                ].compactMap { $0 }
                let other = snapshot.quota?.windows.filter {
                    !["claude.session", "claude.weekly", QuotaWindow.claudeFableWeeklyID].contains($0.id)
                } ?? []
                return known + other
            }
            .min { $0.remainingPercent < $1.remainingPercent }
    }
}
