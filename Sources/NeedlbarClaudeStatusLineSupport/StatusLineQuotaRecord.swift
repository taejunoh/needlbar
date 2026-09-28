import CoreFoundation
import Foundation

public struct StatusLineWindowObservation: Equatable, Sendable {
    public let usedPercent: Double
    public let resetsAt: Date?
    public let receivedAt: Date

    public init(usedPercent: Double, resetsAt: Date?, receivedAt: Date) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.receivedAt = receivedAt
    }
}

public struct StatusLineQuotaRecord: Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let generation: UUID
    public let fiveHour: StatusLineWindowObservation?
    public let sevenDay: StatusLineWindowObservation?

    public init(
        schemaVersion: Int,
        generation: UUID,
        fiveHour: StatusLineWindowObservation?,
        sevenDay: StatusLineWindowObservation?
    ) {
        self.schemaVersion = schemaVersion
        self.generation = generation
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }
}

public enum StatusLineQuotaParser {
    public static let maximumInputBytes = 256 * 1024

    public static func parse(_ data: Data, generation: UUID, receivedAt: Date) -> StatusLineQuotaRecord? {
        guard data.count <= maximumInputBytes,
              let root = try? JSONSerialization.jsonObject(with: data),
              let object = root as? [String: Any]
        else {
            return nil
        }

        let rateLimits = object["rate_limits"] as? [String: Any]
        return StatusLineQuotaRecord(
            schemaVersion: StatusLineQuotaRecord.currentSchemaVersion,
            generation: generation,
            fiveHour: observation(in: rateLimits?["five_hour"], receivedAt: receivedAt),
            sevenDay: observation(in: rateLimits?["seven_day"], receivedAt: receivedAt)
        )
    }

    private static func observation(in value: Any?, receivedAt: Date) -> StatusLineWindowObservation? {
        guard let window = value as? [String: Any],
              let usedNumber = window["used_percentage"] as? NSNumber,
              CFGetTypeID(usedNumber) != CFBooleanGetTypeID()
        else {
            return nil
        }

        let usedPercent = usedNumber.doubleValue
        guard usedPercent.isFinite, (0...100).contains(usedPercent) else {
            return nil
        }

        let resetsAt: Date?
        if let resetValue = window["resets_at"] {
            guard let resetNumber = resetValue as? NSNumber,
                  CFGetTypeID(resetNumber) != CFBooleanGetTypeID()
            else {
                return nil
            }

            let seconds = resetNumber.doubleValue
            guard seconds.isFinite, seconds.rounded(.towardZero) == seconds else {
                return nil
            }
            resetsAt = Date(timeIntervalSince1970: seconds)
        } else {
            resetsAt = nil
        }

        return StatusLineWindowObservation(
            usedPercent: usedPercent,
            resetsAt: resetsAt,
            receivedAt: receivedAt
        )
    }
}

public enum StatusLineQuotaMerger {
    public static func merge(existing: StatusLineQuotaRecord, incoming: StatusLineQuotaRecord) -> StatusLineQuotaRecord {
        guard existing.schemaVersion == StatusLineQuotaRecord.currentSchemaVersion,
              incoming.schemaVersion == StatusLineQuotaRecord.currentSchemaVersion,
              existing.generation == incoming.generation
        else {
            return incoming
        }

        return StatusLineQuotaRecord(
            schemaVersion: StatusLineQuotaRecord.currentSchemaVersion,
            generation: incoming.generation,
            fiveHour: mergeWindow(existing: existing.fiveHour, incoming: incoming.fiveHour),
            sevenDay: mergeWindow(existing: existing.sevenDay, incoming: incoming.sevenDay)
        )
    }

    private static func mergeWindow(
        existing: StatusLineWindowObservation?,
        incoming: StatusLineWindowObservation?
    ) -> StatusLineWindowObservation? {
        guard let incoming else { return existing }
        guard let existing else { return incoming }

        switch (existing.resetsAt, incoming.resetsAt) {
        case let (.some(existingReset), .some(incomingReset)):
            if incomingReset < existingReset { return existing }
            if incomingReset == existingReset, incoming.usedPercent <= existing.usedPercent { return existing }
        case (.some, .none):
            return existing
        case (.none, .none):
            if incoming.usedPercent <= existing.usedPercent { return existing }
        case (.none, .some):
            break
        }

        return incoming
    }
}
