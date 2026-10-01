import Foundation

enum DiskSnapshotBuilder {
  static func make(
    name: String, totalCapacity: Int?, availableCapacity: Int?
  ) -> SystemMetricsSnapshot.DiskVolume? {
    guard let totalCapacity, totalCapacity > 0,
      let availableCapacity, availableCapacity >= 0,
      availableCapacity <= totalCapacity
    else { return nil }

    return .init(
      name: name,
      usedBytes: UInt64(totalCapacity - availableCapacity),
      freeBytes: UInt64(availableCapacity),
      readBytesPerSecond: nil,
      writeBytesPerSecond: nil,
      totalBytes: UInt64(totalCapacity)
    )
  }
}
