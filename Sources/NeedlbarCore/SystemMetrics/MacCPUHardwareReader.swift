@preconcurrency import Darwin
import Foundation

struct MacCPUHardwareReader: @unchecked Sendable {
    typealias StringQuery = (_ name: String, _ maximumByteCount: Int) -> String?
    typealias IntegerQuery = (_ name: String, _ expectedByteCount: Int) -> Int?

    private let stringQuery: StringQuery
    private let integerQuery: IntegerQuery

    init() {
        stringQuery = Self.readString
        integerQuery = Self.readInteger
    }

    init(stringQuery: @escaping StringQuery, integerQuery: @escaping IntegerQuery) {
        self.stringQuery = stringQuery
        self.integerQuery = integerQuery
    }

    func read() -> CPUHardwareInfo? {
        let name = stringQuery("machdep.cpu.brand_string", 4_096)
        let physicalCoreCount = integerQuery("hw.physicalcpu", MemoryLayout<Int32>.size)
        let logicalCoreCount = integerQuery("hw.logicalcpu", MemoryLayout<Int32>.size)
        let performanceLevelCount = integerQuery("hw.nperflevels", MemoryLayout<Int32>.size)

        let groups: [CPUHardwareInfo.CoreGroup]
        if let performanceLevelCount, (1...32).contains(performanceLevelCount) {
            groups = (0..<performanceLevelCount).compactMap { index in
                CPUHardwareInfo.CoreGroup(
                    name: stringQuery("hw.perflevel\(index).name", 4_096),
                    physicalCoreCount: integerQuery(
                        "hw.perflevel\(index).physicalcpu", MemoryLayout<Int32>.size))
            }
        } else {
            groups = []
        }

        let hardware = CPUHardwareInfo(
            name: name,
            physicalCoreCount: physicalCoreCount,
            logicalCoreCount: logicalCoreCount,
            coreGroups: groups)
        guard hardware.name != nil || hardware.physicalCoreCount != nil
            || hardware.logicalCoreCount != nil || !hardware.coreGroups.isEmpty else { return nil }
        return hardware
    }

    private static func readString(name: String, maximumByteCount: Int) -> String? {
        guard (1...4_096).contains(maximumByteCount) else { return nil }
        var buffer = [CChar](repeating: 0, count: maximumByteCount)
        var byteCount = maximumByteCount
        let result = name.withCString { key in
            buffer.withUnsafeMutableBufferPointer { bytes in
                sysctlbyname(key, bytes.baseAddress, &byteCount, nil, 0)
            }
        }
        guard result == 0, byteCount > 0, byteCount <= maximumByteCount else { return nil }
        let value = buffer.prefix(byteCount).prefix { $0 != 0 }.map(UInt8.init(bitPattern:))
        return String(decoding: value, as: UTF8.self)
    }

    private static func readInteger(name: String, expectedByteCount: Int) -> Int? {
        guard expectedByteCount == MemoryLayout<Int32>.size else { return nil }
        var value: Int32 = 0
        var byteCount = expectedByteCount
        let result = name.withCString { key in
            withUnsafeMutablePointer(to: &value) { pointer in
                sysctlbyname(key, pointer, &byteCount, nil, 0)
            }
        }
        guard result == 0, byteCount == expectedByteCount else { return nil }
        return Int(value)
    }
}
