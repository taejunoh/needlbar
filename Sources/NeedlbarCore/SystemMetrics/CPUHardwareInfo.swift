import Foundation

public struct CPUHardwareInfo: Equatable, Sendable {
    public struct CoreGroup: Equatable, Sendable {
        public let name: String
        public let physicalCoreCount: Int

        public init?(name: String?, physicalCoreCount: Int?) {
            let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard
                let name = trimmedName,
                !name.isEmpty,
                let physicalCoreCount,
                physicalCoreCount > 0
            else { return nil }

            self.name = name
            self.physicalCoreCount = physicalCoreCount
        }
    }

    public let name: String?
    public let physicalCoreCount: Int?
    public let logicalCoreCount: Int?
    public let coreGroups: [CoreGroup]

    public init(
        name: String?,
        physicalCoreCount: Int?,
        logicalCoreCount: Int?,
        coreGroups: [CoreGroup] = []
    ) {
        self.name = Self.normalizedName(name)
        self.physicalCoreCount = physicalCoreCount.flatMap { $0 > 0 ? $0 : nil }
        self.logicalCoreCount = logicalCoreCount.flatMap { $0 > 0 ? $0 : nil }
        self.coreGroups = coreGroups
    }

    private static func normalizedName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
