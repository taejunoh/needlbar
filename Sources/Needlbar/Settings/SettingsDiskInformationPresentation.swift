import Combine
import Foundation
import NeedlbarCore

enum SettingsDiskInformationStatus: Equatable {
    case fresh(capturedAt: Date)
    case stale(lastSuccessfulAt: Date)
    case unavailable

    var isStale: Bool {
        if case .stale = self { return true }
        return false
    }
}

struct SettingsDiskInformationValue: Equatable {
    let name: String?
    let totalBytes: UInt64?
    let usedBytes: UInt64?
    let availableBytes: UInt64?
    let usedPercent: Double?
    let readBytesPerSecond: UInt64?
    let writeBytesPerSecond: UInt64?
    let successfulAt: Date?
    let status: SettingsDiskInformationStatus

    var stateLabel: String {
        switch status {
        case .fresh: "Sampled"
        case .stale: "Last known"
        case .unavailable: "Disk activity unavailable"
        }
    }
}

@MainActor
public final class SettingsDiskInformationPresentation: ObservableObject {
    @Published private(set) var value: SettingsDiskInformationValue

    init(snapshot: CombinedUsageSnapshot? = nil) {
        value = Self.presentation(for: snapshot)
    }

    func update(snapshot: CombinedUsageSnapshot) {
        value = Self.presentation(for: snapshot)
    }

    private static func presentation(for snapshot: CombinedUsageSnapshot?) -> SettingsDiskInformationValue {
        let disk = snapshot?.system?.disks.first
        let name = disk.map { disk in
            let trimmed = disk.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed.rangeOfCharacter(from: .controlCharacters) != nil ? "System volume" : trimmed
        }
        let total = disk?.totalBytes.flatMap { $0 > 0 ? $0 : nil }
        let unavailable = SettingsDiskInformationValue(name: name, totalBytes: total, usedBytes: nil,
            availableBytes: nil, usedPercent: nil, readBytesPerSecond: nil, writeBytesPerSecond: nil,
            successfulAt: nil, status: .unavailable)
        guard let disk, disk.totalBytes != 0, let availability = snapshot?.systemAvailability[.disk],
              let used = disk.usedBytes, total.map({ used <= $0 }) ?? true else { return unavailable }
        let status: SettingsDiskInformationStatus
        let successfulAt: Date
        switch availability {
        case let .fresh(capturedAt):
            status = .fresh(capturedAt: capturedAt)
            successfulAt = capturedAt
        case let .stale(lastSuccessfulAt):
            status = .stale(lastSuccessfulAt: lastSuccessfulAt)
            successfulAt = lastSuccessfulAt
        case .unavailable: return unavailable
        }
        let available = disk.freeBytes.flatMap { bytes in total.map({ bytes <= $0 }) ?? true ? bytes : nil }
        var percent: Double?
        if let available {
            let sum = used.addingReportingOverflow(available)
            if !sum.overflow, sum.partialValue > 0, total == nil || total == sum.partialValue {
                percent = 100 * Double(used) / Double(sum.partialValue)
            }
        }
        return SettingsDiskInformationValue(name: name, totalBytes: total, usedBytes: used,
            availableBytes: available, usedPercent: percent, readBytesPerSecond: disk.readBytesPerSecond,
            writeBytesPerSecond: disk.writeBytesPerSecond, successfulAt: successfulAt, status: status)
    }
}
