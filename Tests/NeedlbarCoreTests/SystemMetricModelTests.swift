import Foundation
import Testing
@testable import NeedlbarCore

@Test func metricPercentagesAreBoundedWithoutTurningUnknownIntoZero() {
    #expect(MetricPercentage(24.5)?.value == 24.5)
    #expect(MetricPercentage(-1) == nil)
    #expect(MetricPercentage(101) == nil)
    #expect(MetricPercentage(nil) == nil)
}

@Test func defaultMonitorOrderIsStable() {
    #expect(MonitorModuleID.defaultOrder == [.cpu, .memory, .disk, .network, .battery, .ai])
}

@Test func defaultAIProviderDisplayMetricIsRemaining() {
    #expect(AIProviderDisplayPreference().metric == .remaining)
}

@Test func metricSnapshotPreservesCanonicalValuesAndUnknownFields() {
    let capturedAt = Date(timeIntervalSince1970: 1_000)
    let snapshot = SystemMetricsSnapshot(
        capturedAt: capturedAt,
        cpu: .init(totalUsage: MetricPercentage(24.5), perCoreUsage: [MetricPercentage(24.5)!]),
        memory: .init(usedBytes: 8 * 1_024 * 1_024 * 1_024, freeBytes: nil, swapUsedBytes: 0, pressure: "normal"),
        disks: [.init(name: "Macintosh HD", usedBytes: 100, freeBytes: 200, readBytesPerSecond: nil, writeBytesPerSecond: nil)],
        network: .init(uploadBytesPerSecond: 50, downloadBytesPerSecond: 100, localIPAddresses: ["192.0.2.10"], publicIPAddress: nil),
        battery: .init(level: nil, isCharging: nil, health: nil),
        availability: [
            .cpu: .fresh(capturedAt: capturedAt),
            .memory: .fresh(capturedAt: capturedAt),
            .disk: .fresh(capturedAt: capturedAt),
            .network: .fresh(capturedAt: capturedAt),
            .battery: .unavailable(code: "batteryUnavailable"),
        ]
    )

    #expect(snapshot.capturedAt == capturedAt)
    #expect(snapshot.cpu.totalUsage?.value == 24.5)
    #expect(snapshot.memory.freeBytes == nil)
    #expect(snapshot.network.publicIPAddress == nil)
}

private func freshDefaults() -> UserDefaults {
    let suiteName = "SystemMetricModelTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
