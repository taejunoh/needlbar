import Foundation

enum SystemMetricConversions {
  struct MemoryUsage: Equatable, Sendable {
    let usedBytes: UInt64
    let availableBytes: UInt64
  }

  struct ByteCounters: Equatable, Sendable {
    let readBytes: UInt64
    let writeBytes: UInt64
    let capturedAt: Date
    let sourceIDs: Set<String>
  }

  struct TransferRates: Equatable, Sendable {
    let readBytesPerSecond: UInt64
    let writeBytesPerSecond: UInt64
  }

  struct LocalAddress: Equatable, Sendable {
    let interface: String
    let address: String
    let isIPv4: Bool
  }

  /// Mirrors Activity Monitor's physical-memory accounting: file-backed and
  /// purgeable pages are reclaimable cache, while anonymous inactive pages
  /// remain consumed. Available is always the physical-memory complement.
  static func memoryUsage(
    physicalMemoryBytes: UInt64,
    pageSize: UInt64,
    activePages: UInt64,
    inactivePages: UInt64,
    wiredPages: UInt64,
    compressedPages: UInt64,
    purgeablePages: UInt64,
    fileBackedPages: UInt64
  ) -> MemoryUsage? {
    guard physicalMemoryBytes > 0, pageSize > 0,
      let occupiedPages = sum(activePages, inactivePages, wiredPages, compressedPages),
      let reclaimablePages = sum(purgeablePages, fileBackedPages),
      occupiedPages >= reclaimablePages,
      let consumedBytes = bytes(for: occupiedPages - reclaimablePages, pageSize: pageSize),
      consumedBytes <= physicalMemoryBytes
    else { return nil }
    return .init(usedBytes: consumedBytes, availableBytes: physicalMemoryBytes - consumedBytes)
  }

  static func swapUsedBytes(used: UInt64, total: UInt64) -> UInt64? {
    used <= total ? used : nil
  }

  /// Maps the read-only `kern.memorystatus_vm_pressure_level` sysctl output.
  /// XNU converts its internal 0...4 pressure enum to the public dispatch
  /// flags before returning it: normal = 1, warning/urgent = 2, critical = 4.
  /// https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_memorystatus_notify.c
  static func memoryPressure(sysctlValue: Int32) -> String? {
    switch sysctlValue {
    case 1: return "normal"
    case 2: return "warning"
    case 4: return "critical"
    default: return nil
    }
  }

  static func transferRates(
    current: ByteCounters,
    previous: ByteCounters?
  ) -> TransferRates? {
    guard let previous,
      current.capturedAt > previous.capturedAt,
      current.sourceIDs == previous.sourceIDs,
      current.readBytes >= previous.readBytes,
      current.writeBytes >= previous.writeBytes
    else { return nil }

    let elapsed = current.capturedAt.timeIntervalSince(previous.capturedAt)
    guard elapsed.isFinite, elapsed > 0 else { return nil }
    let readRate = Double(current.readBytes - previous.readBytes) / elapsed
    let writeRate = Double(current.writeBytes - previous.writeBytes) / elapsed
    guard readRate.isFinite, writeRate.isFinite,
      readRate <= Double(UInt64.max), writeRate <= Double(UInt64.max)
    else { return nil }
    return .init(
      readBytesPerSecond: UInt64(readRate),
      writeBytesPerSecond: UInt64(writeRate)
    )
  }

  static func batteryHealth(fullChargeCapacity: UInt64?, designCapacity: UInt64?) -> MetricPercentage? {
    guard let fullChargeCapacity, let designCapacity, designCapacity > 0 else { return nil }
    return MetricPercentage(min(Double(fullChargeCapacity) / Double(designCapacity) * 100, 100))
  }

  static func orderedLocalAddresses(
    _ addresses: [LocalAddress],
    primaryInterface: String?
  ) -> [String] {
    let sorted = addresses.sorted { lhs, rhs in
      let lhsPrimary = lhs.interface == primaryInterface
      let rhsPrimary = rhs.interface == primaryInterface
      if lhsPrimary != rhsPrimary { return lhsPrimary }
      if lhs.isIPv4 != rhs.isIPv4 { return lhs.isIPv4 }
      if lhs.interface != rhs.interface { return lhs.interface < rhs.interface }
      return lhs.address < rhs.address
    }
    return sorted.reduce(into: []) { result, address in
      if !result.contains(address.address) {
        result.append(address.address)
      }
    }
  }

  private static func sum(_ values: UInt64...) -> UInt64? {
    var total: UInt64 = 0
    for value in values {
      let result = total.addingReportingOverflow(value)
      guard !result.overflow else { return nil }
      total = result.partialValue
    }
    return total
  }

  private static func bytes(for pages: UInt64, pageSize: UInt64) -> UInt64? {
    let result = pages.multipliedReportingOverflow(by: pageSize)
    return result.overflow ? nil : result.partialValue
  }
}
