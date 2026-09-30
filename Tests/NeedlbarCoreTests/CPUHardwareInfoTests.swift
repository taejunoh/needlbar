import Foundation
import Testing
@testable import NeedlbarCore

@Test func hardwareReaderDiscoversAppleSiliconCPUAndPerformanceGroups() {
    let reader = MacCPUHardwareReader(
        stringQuery: { key, _ in
            [
                "machdep.cpu.brand_string": " Apple M5 Pro ",
                "hw.perflevel0.name": "Super",
                "hw.perflevel1.name": "Performance",
            ][key]
        },
        integerQuery: { key, _ in
            [
                "hw.physicalcpu": 15,
                "hw.logicalcpu": 15,
                "hw.nperflevels": 2,
                "hw.perflevel0.physicalcpu": 5,
                "hw.perflevel1.physicalcpu": 10,
            ][key]
        })

    #expect(reader.read() == CPUHardwareInfo(
        name: "Apple M5 Pro",
        physicalCoreCount: 15,
        logicalCoreCount: 15,
        coreGroups: [
            CPUHardwareInfo.CoreGroup(name: "Super", physicalCoreCount: 5)!,
            CPUHardwareInfo.CoreGroup(name: "Performance", physicalCoreCount: 10)!,
        ]))
}

@Test func hardwareReaderPreservesValidFieldsWhenOtherQueriesAreMissing() {
    let reader = MacCPUHardwareReader(
        stringQuery: { key, _ in key == "machdep.cpu.brand_string" ? "Apple M5 Pro" : nil },
        integerQuery: { key, _ in key == "hw.logicalcpu" ? 15 : nil })

    #expect(reader.read() == CPUHardwareInfo(
        name: "Apple M5 Pro", physicalCoreCount: nil, logicalCoreCount: 15, coreGroups: []))
}

@Test func hardwareReaderReturnsNilWhenEveryQueryIsUnsupported() {
    let reader = MacCPUHardwareReader(stringQuery: { _, _ in nil }, integerQuery: { _, _ in nil })

    #expect(reader.read() == nil)
}

@Test func hardwareReaderSkipsMalformedValuesWithoutDiscardingValidSiblings() {
    let reader = MacCPUHardwareReader(
        stringQuery: { key, _ in
            ["machdep.cpu.brand_string": "  ", "hw.perflevel0.name": "  "][key]
        },
        integerQuery: { key, _ in
            [
                "hw.physicalcpu": 0,
                "hw.logicalcpu": 15,
                "hw.nperflevels": 1,
                "hw.perflevel0.physicalcpu": -2,
            ][key]
        })

    #expect(reader.read() == CPUHardwareInfo(
        name: nil, physicalCoreCount: nil, logicalCoreCount: 15, coreGroups: []))
}

@Test func hardwareReaderSkipsGroupsForInvalidPerformanceLevelCounts() {
    for invalidCount in [0, -1, 33] {
        var queriedGroupKey = false
        let reader = MacCPUHardwareReader(
            stringQuery: { key, _ in
                if key.hasPrefix("hw.perflevel") { queriedGroupKey = true }
                return nil
            },
            integerQuery: { key, _ in key == "hw.nperflevels" ? invalidCount : nil })

        #expect(reader.read() == nil)
        #expect(!queriedGroupKey)
    }
}

@Test func hardwareReaderBoundsStringQueriesAndRequiresExpectedIntegerSize() {
    var stringLimit: Int?
    var integerExpectedSize: Int?
    let reader = MacCPUHardwareReader(
        stringQuery: { _, limit in
            stringLimit = limit
            return "Apple M5 Pro"
        },
        integerQuery: { key, expectedSize in
            integerExpectedSize = expectedSize
            return key == "hw.physicalcpu" ? 15 : nil
        })

    #expect(reader.read() == CPUHardwareInfo(
        name: "Apple M5 Pro", physicalCoreCount: 15, logicalCoreCount: nil, coreGroups: []))
    #expect(stringLimit == 4096)
    #expect(integerExpectedSize == MemoryLayout<Int32>.size)
}

@Test func CPUHardwareInfoNormalizesInvalidIndependentFields() {
    let value = CPUHardwareInfo(name: "  ", physicalCoreCount: 0,
        logicalCoreCount: 15, coreGroups: [])

    #expect(value.name == nil)
    #expect(value.physicalCoreCount == nil)
    #expect(value.logicalCoreCount == 15)
}

@Test func CPUCoreGroupRequiresNonblankNameAndPositiveCount() {
    #expect(CPUHardwareInfo.CoreGroup(name: " ", physicalCoreCount: 4) == nil)
    #expect(CPUHardwareInfo.CoreGroup(name: "Efficiency", physicalCoreCount: 0) == nil)
    #expect(CPUHardwareInfo.CoreGroup(name: " Efficiency ", physicalCoreCount: 4)?.name == "Efficiency")
}

@Test func collectorReadsHardwareOnceAndIncludesItInInitialWarmup() async throws {
    let expected = CPUHardwareInfo(
        name: "Apple M5 Pro", physicalCoreCount: 15, logicalCoreCount: 15, coreGroups: [])
    let reader = CPUHardwareReadCounter(result: expected)
    let collector = MacSystemMetricsCollector(readCPUHardware: { reader.read() })

    let first = try await collector.collect(at: Date(timeIntervalSince1970: 1_000))
    let second = try await collector.collect(at: Date(timeIntervalSince1970: 1_001))

    #expect(first.cpu.hardware == expected)
    #expect(first.availability[.cpu] == MetricAvailability.unavailable(code: "cpuWarmingUp"))
    #expect(second.cpu.hardware == expected)
    #expect(reader.readCount == 1)
}

@Test func collectorCachesUnsupportedHardwareResult() async throws {
    let reader = CPUHardwareReadCounter(result: nil)
    let collector = MacSystemMetricsCollector(readCPUHardware: { reader.read() })

    _ = try await collector.collect(at: Date(timeIntervalSince1970: 1_000))
    _ = try await collector.collect(at: Date(timeIntervalSince1970: 1_001))

    #expect(reader.readCount == 1)
}

private final class CPUHardwareReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private let result: CPUHardwareInfo?
    private var count = 0

    init(result: CPUHardwareInfo?) {
        self.result = result
    }

    var readCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func read() -> CPUHardwareInfo? {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return result
    }
}
