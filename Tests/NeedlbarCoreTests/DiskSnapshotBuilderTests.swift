import Foundation
import Testing

@testable import NeedlbarCore

@Test func diskSnapshotBuilderRetainsValidatedVolumeCapacity() throws {
    let disk = try #require(
        DiskSnapshotBuilder.make(name: "Macintosh HD", totalCapacity: 32_768, availableCapacity: 8_192))

    #expect(disk.name == "Macintosh HD")
    #expect(disk.usedBytes == 24_576)
    #expect(disk.freeBytes == 8_192)
    #expect(disk.totalBytes == 32_768)
    #expect(disk.readBytesPerSecond == nil)
    #expect(disk.writeBytesPerSecond == nil)
}

@Test func diskSnapshotBuilderAcceptsZeroUsedAndAvailableCapacity() throws {
    let empty = try #require(
        DiskSnapshotBuilder.make(name: "Empty", totalCapacity: 32_768, availableCapacity: 32_768))
    let full = try #require(
        DiskSnapshotBuilder.make(name: "Full", totalCapacity: 32_768, availableCapacity: 0))

    #expect(empty.usedBytes == 0)
    #expect(empty.freeBytes == 32_768)
    #expect(full.usedBytes == 32_768)
    #expect(full.freeBytes == 0)
}

@Test(arguments: [
    (Optional<Int>.none, Optional<Int>.some(1)),
    (Optional<Int>.some(0), Optional<Int>.some(0)),
    (Optional<Int>.some(-1), Optional<Int>.some(0)),
    (Optional<Int>.some(10), Optional<Int>.none),
    (Optional<Int>.some(10), Optional<Int>.some(-1)),
    (Optional<Int>.some(10), Optional<Int>.some(11)),
])
func diskSnapshotBuilderRejectsMissingOrInconsistentCapacity(total: Int?, available: Int?) {
    #expect(DiskSnapshotBuilder.make(
        name: "Macintosh HD", totalCapacity: total, availableCapacity: available) == nil)
}

@Test func diskSnapshotBuilderAcceptsLargestPositiveIntWithoutOverflow() throws {
    let disk = try #require(
        DiskSnapshotBuilder.make(name: "Large", totalCapacity: Int.max, availableCapacity: 0))

    #expect(disk.usedBytes == UInt64(Int.max))
    #expect(disk.freeBytes == 0)
    #expect(disk.totalBytes == UInt64(Int.max))
}
