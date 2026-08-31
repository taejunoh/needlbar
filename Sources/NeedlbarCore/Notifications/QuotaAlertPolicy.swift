import Foundation

public enum QuotaAlertStage: Int, Codable, CaseIterable, Sendable {
    case twenty = 20
    case ten = 10
}

public struct QuotaAlertKey: Codable, Hashable, Sendable {
    public let provider: ProviderID
    public let windowID: String

    public init(provider: ProviderID, windowID: String) throws {
        guard Self.isAllowed(provider: provider, windowID: windowID) else {
            throw QuotaAlertLedgerStoreError.corrupt
        }
        self.provider = provider
        self.windowID = windowID
    }

    static func isAllowed(provider: ProviderID, windowID: String) -> Bool {
        allowedWindowIDs[provider]?.contains(windowID) == true
    }

    private static let allowedWindowIDs: [ProviderID: Set<String>] = [
        .claude: ["claude.session", "claude.weekly"],
        .codex: ["codex.primary", "codex.secondary"],
    ]
}

public struct QuotaAlertObservation: Sendable {
    public let key: QuotaAlertKey
    public let remainingPercent: Double
    public let resetsAt: Date?
    public let successfulAt: Date
    public let revision: UInt64

    public init(
        key: QuotaAlertKey,
        remainingPercent: Double,
        resetsAt: Date?,
        successfulAt: Date,
        revision: UInt64
    ) {
        self.key = key
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.successfulAt = successfulAt
        self.revision = revision
    }
}

public struct QuotaAlertRecord: Codable, Equatable, Sendable {
    public let key: QuotaAlertKey
    public var lastRemainingPercent: Double
    public var lastSuccessfulAt: Date
    public var pinnedResetAt: Date?
    public var consumedStages: Set<QuotaAlertStage>
    public var reservedStages: Set<QuotaAlertStage>

    public init(
        key: QuotaAlertKey,
        lastRemainingPercent: Double,
        lastSuccessfulAt: Date,
        pinnedResetAt: Date?,
        consumedStages: Set<QuotaAlertStage>,
        reservedStages: Set<QuotaAlertStage>
    ) {
        self.key = key
        self.lastRemainingPercent = lastRemainingPercent
        self.lastSuccessfulAt = lastSuccessfulAt
        self.pinnedResetAt = pinnedResetAt
        self.consumedStages = consumedStages
        self.reservedStages = reservedStages
    }
}

public struct QuotaAlertLedger: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public var records: [QuotaAlertRecord]

    public static let empty = QuotaAlertLedger(schemaVersion: currentSchemaVersion, records: [])

    public init(schemaVersion: Int, records: [QuotaAlertRecord]) {
        self.schemaVersion = schemaVersion
        self.records = records
    }

    public func record(for key: QuotaAlertKey) -> QuotaAlertRecord? {
        records.first { $0.key == key }
    }

    mutating func replace(_ record: QuotaAlertRecord) {
        records.removeAll { $0.key == record.key }
        records.append(record)
        records.sort {
            ($0.key.provider.rawValue, $0.key.windowID) < ($1.key.provider.rawValue, $1.key.windowID)
        }
    }
}

public struct QuotaAlertDecision: Sendable {
    public let ledger: QuotaAlertLedger
    public let stage: QuotaAlertStage?

    public init(ledger: QuotaAlertLedger, stage: QuotaAlertStage?) {
        self.ledger = ledger
        self.stage = stage
    }
}

public struct QuotaAlertPolicy: Sendable {
    public init() {}

    public func observe(
        _ observation: QuotaAlertObservation,
        ledger: QuotaAlertLedger,
        now: Date,
        processHasEstablishedBaseline: Bool
    ) -> QuotaAlertDecision {
        guard isAdmissible(observation, now: now) else {
            return QuotaAlertDecision(ledger: ledger, stage: nil)
        }

        var next = ledger
        let isNewRecord = next.record(for: observation.key) == nil
        var record = next.record(for: observation.key) ?? QuotaAlertRecord(
            key: observation.key,
            lastRemainingPercent: observation.remainingPercent,
            lastSuccessfulAt: observation.successfulAt,
            pinnedResetAt: nil,
            consumedStages: [],
            reservedStages: []
        )

        guard isNewRecord || observation.successfulAt >= record.lastSuccessfulAt else {
            return QuotaAlertDecision(ledger: ledger, stage: nil)
        }

        if record.pinnedResetAt == nil, let reset = observation.resetsAt, reset > now {
            record.pinnedResetAt = reset
        }

        if isNewRecord || !processHasEstablishedBaseline {
            consumeReachedStages(of: observation.remainingPercent, in: &record)
            record.lastRemainingPercent = observation.remainingPercent
            record.lastSuccessfulAt = observation.successfulAt
            next.replace(record)
            return QuotaAlertDecision(ledger: next, stage: nil)
        }

        if shouldRearm(record: record, observation: observation, now: now) {
            record.pinnedResetAt = observation.resetsAt
            record.consumedStages = []
            record.reservedStages = []
            record.lastRemainingPercent = observation.remainingPercent
            record.lastSuccessfulAt = observation.successfulAt
            next.replace(record)
            return QuotaAlertDecision(ledger: next, stage: nil)
        }

        let stage = nextStage(for: observation.remainingPercent, from: record.lastRemainingPercent, record: &record)
        record.lastRemainingPercent = observation.remainingPercent
        record.lastSuccessfulAt = observation.successfulAt
        next.replace(record)
        return QuotaAlertDecision(ledger: next, stage: stage)
    }

    private func isAdmissible(_ observation: QuotaAlertObservation, now: Date) -> Bool {
        observation.remainingPercent.isFinite
            && (0 ... 100).contains(observation.remainingPercent)
            && observation.successfulAt.timeIntervalSinceReferenceDate.isFinite
            && observation.successfulAt <= now
            && now.timeIntervalSince(observation.successfulAt) < 15 * 60
            && (observation.resetsAt?.timeIntervalSinceReferenceDate.isFinite ?? true)
    }

    private func shouldRearm(
        record: QuotaAlertRecord,
        observation: QuotaAlertObservation,
        now: Date
    ) -> Bool {
        guard let anchor = record.pinnedResetAt,
              anchor <= now,
              let reset = observation.resetsAt,
              reset > anchor,
              reset > now
        else {
            return false
        }
        return observation.remainingPercent > 20
    }

    private func nextStage(
        for remaining: Double,
        from previous: Double,
        record: inout QuotaAlertRecord
    ) -> QuotaAlertStage? {
        if previous > 20, remaining <= 10, !record.consumedStages.contains(.ten) {
            record.consumedStages.formUnion([.twenty, .ten])
            record.reservedStages.insert(.ten)
            return .ten
        }
        if previous > 20, remaining <= 20, !record.consumedStages.contains(.twenty) {
            record.consumedStages.insert(.twenty)
            record.reservedStages.insert(.twenty)
            return .twenty
        }
        if previous > 10, remaining <= 10, !record.consumedStages.contains(.ten) {
            record.consumedStages.insert(.ten)
            record.reservedStages.insert(.ten)
            return .ten
        }
        return nil
    }

    private func consumeReachedStages(of remaining: Double, in record: inout QuotaAlertRecord) {
        if remaining <= 20 {
            record.consumedStages.insert(.twenty)
        }
        if remaining <= 10 {
            record.consumedStages.insert(.ten)
        }
    }
}
