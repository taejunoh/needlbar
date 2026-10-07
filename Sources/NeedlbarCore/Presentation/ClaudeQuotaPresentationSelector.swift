import Foundation
import NeedlbarClaudeStatusLineSupport

public enum ClaudeWindowSource: Equatable, Sendable {
    case direct
    case claudeCodeStatusLine
}

public struct DisplayedClaudeWindow: Equatable, Sendable {
    public let remainingPercent: Double
    public let source: ClaudeWindowSource
    public let observedAt: Date?
    public let resetsAt: Date?
    public let isLastKnown: Bool

    public init(remainingPercent: Double, source: ClaudeWindowSource, observedAt: Date?, resetsAt: Date?, isLastKnown: Bool) {
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
    public static let recentDirectInterval: TimeInterval = 15 * 60

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
        case let (.some(direct), .some(bridge)):
            switch (direct.observedAt, bridge.observedAt) {
            case let (.some(a), .some(b)): return a >= b ? direct : bridge
            case (.some, nil): return direct
            case (nil, .some): return bridge
            case (nil, nil): return direct
            }
        case let (.some(direct), nil): return direct
        case let (nil, .some(bridge)): return bridge
        case (nil, nil): return nil
        }
    }

    private static func usableTime(_ date: Date?, now: Date) -> Date? {
        guard now.timeIntervalSince1970.isFinite, let date,
              date.timeIntervalSince1970.isFinite, date <= now else { return nil }
        return date
    }

    public static func directWindow(
        _ window: QuotaWindow, snapshot: ProviderSnapshot, now: Date
    ) -> DisplayedClaudeWindow {
        let observed = usableTime(snapshot.quotaLastSuccessfulAt, now: now)
        let recent = observed.map { now.timeIntervalSince($0) < recentDirectInterval } ?? false
        let resetValid = window.resetsAt.map {
            $0.timeIntervalSince1970.isFinite && $0 > now
        } ?? true
        return DisplayedClaudeWindow(
            remainingPercent: window.remainingPercent,
            source: .direct,
            observedAt: observed,
            resetsAt: window.resetsAt.flatMap { $0.timeIntervalSince1970.isFinite ? $0 : nil },
            isLastKnown: snapshot.quotaStatus != .fresh || !recent || !resetValid
        )
    }

    private static func statusLineWindow(_ window: StatusLineWindowObservation, now: Date) -> DisplayedClaudeWindow? {
        guard window.usedPercent.isFinite, (0...100).contains(window.usedPercent),
              window.resetsAt?.timeIntervalSince1970.isFinite ?? true else { return nil }
        let observed = usableTime(window.receivedAt, now: now)
        let age = observed.map { now.timeIntervalSince($0) }
        let recentlyReported = age.map { $0 <= recentStatusLineInterval } == true
            && (window.resetsAt.map { $0 > now } ?? true)
        return DisplayedClaudeWindow(
            remainingPercent: 100 - window.usedPercent,
            source: .claudeCodeStatusLine,
            observedAt: observed,
            resetsAt: window.resetsAt.flatMap { $0.timeIntervalSince1970.isFinite ? $0 : nil },
            isLastKnown: !recentlyReported
        )
    }
}
