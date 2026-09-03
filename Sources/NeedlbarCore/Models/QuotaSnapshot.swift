import Foundation

public struct QuotaSnapshot: Codable, Sendable, Equatable {
    public let windows: [QuotaWindow]

    public init(windows: [QuotaWindow]) {
        self.windows = windows
    }
}

public struct QuotaWindow: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let usedPercent: Double
    public let resetsAt: Date?

    public var remainingPercent: Double { 100 - usedPercent }

    public init(id: String, title: String, usedPercent: Double, resetsAt: Date?) throws {
        guard usedPercent.isFinite, (0 ... 100).contains(usedPercent) else {
            throw QuotaWindowValidationError.invalidUsedPercent(usedPercent)
        }
        self.id = id
        self.title = title
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, usedPercent, resetsAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let title = try container.decode(String.self, forKey: .title)
        let usedPercent = try container.decode(Double.self, forKey: .usedPercent)
        let resetsAt = try container.decodeIfPresent(Date.self, forKey: .resetsAt)
        guard usedPercent.isFinite, (0 ... 100).contains(usedPercent) else {
            throw DecodingError.dataCorruptedError(
                forKey: .usedPercent,
                in: container,
                debugDescription: "Quota percent must be finite and within 0...100."
            )
        }
        self.id = id
        self.title = title
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

public extension QuotaWindow {
    static let claudeFableWeeklyID = "claude.fable.weekly"
}

public enum QuotaWindowValidationError: Error, Sendable, Equatable {
    case invalidUsedPercent(Double)
}
