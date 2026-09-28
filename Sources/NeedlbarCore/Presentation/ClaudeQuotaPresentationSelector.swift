import Foundation
import NeedlbarClaudeStatusLineSupport

public enum ClaudeWindowSource: Equatable, Sendable {
    case direct
    case claudeCodeStatusLine
}

public struct DisplayedClaudeWindow: Equatable, Sendable {
    public let remainingPercent: Double
    public let source: ClaudeWindowSource
    public let observedAt: Date
    public let resetsAt: Date?
    public let isLastKnown: Bool

    public init(remainingPercent: Double, source: ClaudeWindowSource, observedAt: Date, resetsAt: Date?, isLastKnown: Bool) {
        self.remainingPercent = remainingPercent
        self.source = source
        self.observedAt = observedAt
        self.resetsAt = resetsAt
        self.isLastKnown = isLastKnown
    }
}

public struct ClaudeQuotaSelection: Equatable, Sendable {
    public let fiveHour: DisplayedClaudeWindow?
    public let sevenDay: DisplayedClaudeWindow?
    public let fable: DisplayedClaudeWindow?
}

public enum ClaudeQuotaPresentationSelector {
    public static let recentStatusLineInterval: TimeInterval = 15 * 60

    public static func select(snapshot: ProviderSnapshot, now: Date) -> ClaudeQuotaSelection {
        guard snapshot.provider == .claude else {
            return ClaudeQuotaSelection(fiveHour: nil, sevenDay: nil, fable: nil)
        }
        let direct = snapshot.quota?.windows ?? []
        let fiveHour = direct.first { $0.id == "claude.session" }
        let sevenDay = direct.first { $0.id == "claude.weekly" }
        let fable = direct.first { $0.id == QuotaWindow.claudeFableWeeklyID }
        return ClaudeQuotaSelection(
            fiveHour: choose(direct: fiveHour, statusLine: snapshot.claudeStatusLineQuota?.fiveHour, snapshot: snapshot, now: now),
            sevenDay: choose(direct: sevenDay, statusLine: snapshot.claudeStatusLineQuota?.sevenDay, snapshot: snapshot, now: now),
            fable: fable.map { directWindow($0, snapshot: snapshot, now: now) }
        )
    }

    private static func choose(
        direct: QuotaWindow?,
        statusLine: StatusLineWindowObservation?,
        snapshot: ProviderSnapshot,
        now: Date
    ) -> DisplayedClaudeWindow? {
        let directDisplay = direct.map { directWindow($0, snapshot: snapshot, now: now) }
        let statusDisplay = statusLine.flatMap { statusLineWindow($0, now: now) }
        if let directDisplay, !directDisplay.isLastKnown { return directDisplay }
        if let statusDisplay, !statusDisplay.isLastKnown { return statusDisplay }
        switch (directDisplay, statusDisplay) {
        case let (.some(lhs), .some(rhs)):
            return lhs.observedAt >= rhs.observedAt ? lhs : rhs
        case let (.some(lhs), nil): return lhs
        case let (nil, .some(rhs)): return rhs
        case (nil, nil): return nil
        }
    }

    private static func directWindow(_ window: QuotaWindow, snapshot: ProviderSnapshot, now: Date) -> DisplayedClaudeWindow {
        let observedAt = snapshot.quotaLastSuccessfulAt ?? snapshot.updatedAt
        return DisplayedClaudeWindow(
            remainingPercent: window.remainingPercent,
            source: .direct,
            observedAt: observedAt,
            resetsAt: window.resetsAt,
            isLastKnown: snapshot.quotaStatus != .fresh || (window.resetsAt.map { now >= $0 } ?? false)
        )
    }

    private static func statusLineWindow(_ window: StatusLineWindowObservation, now: Date) -> DisplayedClaudeWindow? {
        guard window.usedPercent.isFinite, (0...100).contains(window.usedPercent),
              window.receivedAt.timeIntervalSince1970.isFinite,
              window.resetsAt?.timeIntervalSince1970.isFinite ?? true else { return nil }
        let age = now.timeIntervalSince(window.receivedAt)
        let recentlyReported = age >= 0 && age <= recentStatusLineInterval && (window.resetsAt.map { now < $0 } ?? true)
        return DisplayedClaudeWindow(
            remainingPercent: 100 - window.usedPercent,
            source: .claudeCodeStatusLine,
            observedAt: window.receivedAt,
            resetsAt: window.resetsAt,
            isLastKnown: !recentlyReported
        )
    }
}
