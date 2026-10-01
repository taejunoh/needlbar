import Foundation
import Testing

@testable import NeedlbarCore

@Test func vmDetailsDoNotDoubleCountUsedMemory() {
  let memory = MemorySnapshotBuilder.make(
    physicalMemory: 32_768,
    pageSize: 4_096,
    counters: .init(active: 3, inactive: 2, wired: 2, compressed: 1, purgeable: 1, fileBacked: 1)
  )

  #expect(memory.totalBytes == 32_768)
  #expect(memory.usedBytes == 24_576)
  #expect(memory.freeBytes == 8_192)
  #expect(memory.wiredBytes == 8_192)
  #expect(memory.compressedBytes == 4_096)
}

@Test func missingVMStatsPreservesOnlyCapacity() {
  let memory = MemorySnapshotBuilder.make(physicalMemory: 32_768, pageSize: nil, counters: nil)

  #expect(memory.totalBytes == 32_768)
  #expect(memory.usedBytes == nil)
  #expect(memory.compressedBytes == nil)
  #expect(memory.wiredBytes == nil)
  #expect(memory.swapUsedBytes == nil)
  #expect(memory.pressure == nil)
}

@Test func missingOrZeroPageSizePreservesOnlyCapacity() {
  let counters = MemorySnapshotBuilder.Counters(
    active: 1, inactive: 1, wired: 1, compressed: 1, purgeable: 0, fileBacked: 0)

  for pageSize in [UInt64?.none, 0] {
    let memory = MemorySnapshotBuilder.make(
      physicalMemory: 32_768, pageSize: pageSize, counters: counters)
    #expect(memory.totalBytes == 32_768)
    #expect(memory.usedBytes == nil)
    #expect(memory.compressedBytes == nil)
    #expect(memory.wiredBytes == nil)
  }
}

@Test func invalidAggregatePreservesOnlyPositiveCapacity() {
  let cases: [MemorySnapshotBuilder.Counters] = [
    .init(active: .max, inactive: 1, wired: 0, compressed: 0, purgeable: 0, fileBacked: 0),
    .init(active: 1, inactive: 0, wired: 0, compressed: 0, purgeable: 2, fileBacked: 0),
    .init(active: 9, inactive: 0, wired: 0, compressed: 0, purgeable: 0, fileBacked: 0),
  ]
  let physicalMemory: UInt64 = 8 * 4_096

  for counters in cases {
    let memory = MemorySnapshotBuilder.make(
      physicalMemory: physicalMemory, pageSize: 4_096, counters: counters)
    #expect(memory.totalBytes == physicalMemory)
    #expect(memory.usedBytes == nil)
    #expect(memory.freeBytes == nil)
    #expect(memory.compressedBytes == nil)
    #expect(memory.wiredBytes == nil)
  }

  let zeroCapacity = MemorySnapshotBuilder.make(physicalMemory: 0, pageSize: 4_096, counters: nil)
  #expect(zeroCapacity.totalBytes == nil)
  #expect(zeroCapacity.usedBytes == nil)
}

@Test func genuineZeroUsageAndVMDetailsRemainAvailable() {
  let memory = MemorySnapshotBuilder.make(
    physicalMemory: 32_768,
    pageSize: 4_096,
    counters: .init(active: 0, inactive: 0, wired: 0, compressed: 0, purgeable: 0, fileBacked: 0)
  )

  #expect(memory.usedBytes == 0)
  #expect(memory.freeBytes == 32_768)
  #expect(memory.compressedBytes == 0)
  #expect(memory.wiredBytes == 0)
}

@Test func impossibleDetailDoesNotInvalidateAggregateOrOtherDetails() {
  let memory = MemorySnapshotBuilder.make(
    physicalMemory: 8 * 4_096,
    pageSize: 4_096,
    counters: .init(active: 8, inactive: 0, wired: 9, compressed: 0, purgeable: 9, fileBacked: 0)
  )

  #expect(memory.usedBytes == 32_768)
  #expect(memory.freeBytes == 0)
  #expect(memory.wiredBytes == nil)
  #expect(memory.compressedBytes == 0)
}

@Test func detailMultiplicationOverflowDoesNotInvalidateAggregate() {
  let memory = MemorySnapshotBuilder.make(
    physicalMemory: 32_768,
    pageSize: 4_096,
    counters: .init(active: 0, inactive: 0, wired: .max, compressed: 0, purgeable: .max, fileBacked: 0)
  )

  #expect(memory.usedBytes == 0)
  #expect(memory.freeBytes == 32_768)
  #expect(memory.wiredBytes == nil)
  #expect(memory.compressedBytes == 0)
}
