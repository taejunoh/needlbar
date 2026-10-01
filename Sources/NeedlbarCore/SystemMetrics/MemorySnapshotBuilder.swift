enum MemorySnapshotBuilder {
  struct Counters {
    let active: UInt64
    let inactive: UInt64
    let wired: UInt64
    let compressed: UInt64
    let purgeable: UInt64
    let fileBacked: UInt64
  }

  static func make(
    physicalMemory: UInt64,
    pageSize: UInt64?,
    counters: Counters?
  ) -> SystemMetricsSnapshot.Memory {
    let total = physicalMemory > 0 ? physicalMemory : nil
    let unavailable = SystemMetricsSnapshot.Memory(
      usedBytes: nil, freeBytes: nil, swapUsedBytes: nil, pressure: nil, totalBytes: total)
    guard let total, let pageSize, pageSize > 0, let counters,
      let usage = SystemMetricConversions.memoryUsage(
        physicalMemoryBytes: total,
        pageSize: pageSize,
        activePages: counters.active,
        inactivePages: counters.inactive,
        wiredPages: counters.wired,
        compressedPages: counters.compressed,
        purgeablePages: counters.purgeable,
        fileBackedPages: counters.fileBacked
      )
    else { return unavailable }

    return .init(
      usedBytes: usage.usedBytes,
      freeBytes: usage.availableBytes,
      swapUsedBytes: nil,
      pressure: nil,
      totalBytes: total,
      compressedBytes: detailBytes(counters.compressed, pageSize: pageSize, total: total),
      wiredBytes: detailBytes(counters.wired, pageSize: pageSize, total: total)
    )
  }

  private static func detailBytes(_ pages: UInt64, pageSize: UInt64, total: UInt64) -> UInt64? {
    let result = pages.multipliedReportingOverflow(by: pageSize)
    return !result.overflow && result.partialValue <= total ? result.partialValue : nil
  }
}
