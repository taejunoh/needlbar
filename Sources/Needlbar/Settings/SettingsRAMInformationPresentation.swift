import Combine
import Foundation
import NeedlbarCore

enum SettingsRAMInformationStatus: Equatable {
    case fresh(capturedAt: Date)
    case stale(lastSuccessfulAt: Date)
    case unavailable
}

struct SettingsRAMInformationValue: Equatable {
    let totalBytes: UInt64?
    let usedBytes: UInt64?
    let availableBytes: UInt64?
    let compressedBytes: UInt64?
    let wiredBytes: UInt64?
    let swapUsedBytes: UInt64?
    let usedPercent: Double?
    let pressure: String?
    let successfulAt: Date?
    let status: SettingsRAMInformationStatus

    var stateLabel: String {
        switch status {
        case .fresh: "Sampled"
        case .stale: "Last known"
        case .unavailable: "Memory usage unavailable"
        }
    }
}

@MainActor
public final class SettingsRAMInformationPresentation: ObservableObject {
    @Published private(set) var value: SettingsRAMInformationValue

    init(snapshot: CombinedUsageSnapshot? = nil) {
        value = Self.presentation(for: snapshot)
    }

    func update(snapshot: CombinedUsageSnapshot) {
        value = Self.presentation(for: snapshot)
    }

    private static func presentation(for snapshot: CombinedUsageSnapshot?) -> SettingsRAMInformationValue {
        let memory = snapshot?.system?.memory
        let total = memory?.totalBytes.flatMap { $0 > 0 ? $0 : nil }
        let unavailable = SettingsRAMInformationValue(totalBytes: total, usedBytes: nil, availableBytes: nil,
            compressedBytes: nil, wiredBytes: nil, swapUsedBytes: nil, usedPercent: nil,
            pressure: nil, successfulAt: nil, status: .unavailable)
        guard let memory, let availability = snapshot?.systemAvailability[.memory],
              let used = memory.usedBytes, total.map({ used <= $0 }) ?? true else { return unavailable }
        let status: SettingsRAMInformationStatus
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
        func bounded(_ bytes: UInt64?) -> UInt64? {
            bytes.flatMap { bytes in total.map({ bytes <= $0 }) ?? true ? bytes : nil }
        }
        let available = bounded(memory.freeBytes)
        var percent: Double?
        if let available {
            let sum = used.addingReportingOverflow(available)
            if !sum.overflow, sum.partialValue > 0, total == nil || total == sum.partialValue {
                percent = 100 * Double(used) / Double(sum.partialValue)
            }
        }
        let pressure = memory.pressure.flatMap { ["normal", "warning", "critical"].contains($0) ? $0 : nil }
        return SettingsRAMInformationValue(totalBytes: total, usedBytes: used, availableBytes: available,
            compressedBytes: bounded(memory.compressedBytes), wiredBytes: bounded(memory.wiredBytes),
            swapUsedBytes: memory.swapUsedBytes, usedPercent: percent, pressure: pressure,
            successfulAt: successfulAt, status: status)
    }
}
