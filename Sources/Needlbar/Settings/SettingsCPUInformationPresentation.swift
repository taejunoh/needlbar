import Combine
import Foundation
import NeedlbarCore

enum SettingsCPUInformationStatus: Equatable {
    case fresh(capturedAt: Date)
    case stale(lastSuccessfulAt: Date)
    case warmingUp
    case unavailable
}

struct SettingsCPUInformationValue: Equatable {
    let hardware: CPUHardwareInfo?
    let totalUsagePercent: Double?
    let idlePercent: Double?
    let perCorePercents: [Double]?
    let status: SettingsCPUInformationStatus
    let lastSuccessfulAt: Date?
    let reason: String?
}

@MainActor
public final class SettingsCPUInformationPresentation: ObservableObject {
    @Published private(set) var value: SettingsCPUInformationValue

    init(snapshot: CombinedUsageSnapshot? = nil) {
        value = Self.presentation(for: snapshot)
    }

    func update(snapshot: CombinedUsageSnapshot) {
        value = Self.presentation(for: snapshot)
    }

    private static func presentation(for snapshot: CombinedUsageSnapshot?) -> SettingsCPUInformationValue {
        let unavailable = SettingsCPUInformationValue(
            hardware: snapshot?.system?.cpu.hardware,
            totalUsagePercent: nil,
            idlePercent: nil,
            perCorePercents: nil,
            status: .unavailable,
            lastSuccessfulAt: nil,
            reason: "CPU information is unavailable"
        )
        guard let snapshot, let system = snapshot.system else { return unavailable }

        let hardware = system.cpu.hardware
        guard let availability = snapshot.systemAvailability[.cpu] else { return unavailable }
        let status: SettingsCPUInformationStatus
        let lastSuccessfulAt: Date?
        switch availability {
        case let .fresh(capturedAt):
            status = .fresh(capturedAt: capturedAt)
            lastSuccessfulAt = capturedAt
        case let .stale(lastSuccessfulAtValue):
            status = .stale(lastSuccessfulAt: lastSuccessfulAtValue)
            lastSuccessfulAt = lastSuccessfulAtValue
        case let .unavailable(code):
            if code == "cpuWarmingUp" {
                return SettingsCPUInformationValue(
                    hardware: hardware,
                    totalUsagePercent: nil,
                    idlePercent: nil,
                    perCorePercents: nil,
                    status: .warmingUp,
                    lastSuccessfulAt: nil,
                    reason: "Waiting for the first CPU sample"
                )
            }
            return SettingsCPUInformationValue(
                hardware: hardware,
                totalUsagePercent: nil,
                idlePercent: nil,
                perCorePercents: nil,
                status: .unavailable,
                lastSuccessfulAt: nil,
                reason: "CPU information is unavailable"
            )
        }

        guard let usage = system.cpu.totalUsage?.value else {
            return SettingsCPUInformationValue(
                hardware: hardware,
                totalUsagePercent: nil,
                idlePercent: nil,
                perCorePercents: nil,
                status: .unavailable,
                lastSuccessfulAt: nil,
                reason: "CPU usage is unavailable"
            )
        }
        let perCore = system.cpu.perCoreUsage.map(\.value)
        return SettingsCPUInformationValue(
            hardware: hardware,
            totalUsagePercent: usage,
            idlePercent: 100 - usage,
            perCorePercents: perCore.isEmpty ? nil : perCore,
            status: status,
            lastSuccessfulAt: lastSuccessfulAt,
            reason: nil
        )
    }
}
