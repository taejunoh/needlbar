import Foundation
import Testing

@testable import NeedlbarCore

@Test func consumedMemoryExcludesPurgeableAndFileBackedPages() throws {
  let memory = try #require(
    SystemMetricConversions.memoryUsage(
      physicalMemoryBytes: 1_000 * 4_096,
      pageSize: 4_096,
      activePages: 400,
      inactivePages: 300,
      wiredPages: 100,
      compressedPages: 200,
      purgeablePages: 50,
      fileBackedPages: 250
    ))

  #expect(memory.usedBytes == 700 * 4_096)
  #expect(memory.availableBytes == 300 * 4_096)
  #expect(memory.usedBytes + memory.availableBytes == 1_000 * 4_096)
}

@Test func consumedMemoryRejectsCountersThatCannotFitPhysicalMemory() {
  let memory = SystemMetricConversions.memoryUsage(
    physicalMemoryBytes: 100,
    pageSize: 10,
    activePages: 20,
    inactivePages: 20,
    wiredPages: 20,
    compressedPages: 20,
    purgeablePages: 0,
    fileBackedPages: 0
  )

  #expect(memory == nil)
}

@Test func swapUsageAcceptsAValidUsedValueIncludingZero() {
  #expect(SystemMetricConversions.swapUsedBytes(used: 512, total: 1_024) == 512)
  #expect(SystemMetricConversions.swapUsedBytes(used: 0, total: 0) == 0)
  #expect(SystemMetricConversions.swapUsedBytes(used: 1_025, total: 1_024) == nil)
}

@Test func memoryPressureUsesPublicSysctlDispatchFlags() {
  #expect(SystemMetricConversions.memoryPressure(sysctlValue: 1) == "normal")
  #expect(SystemMetricConversions.memoryPressure(sysctlValue: 2) == "warning")
  #expect(SystemMetricConversions.memoryPressure(sysctlValue: 4) == "critical")
  #expect(SystemMetricConversions.memoryPressure(sysctlValue: 0) == nil)
  #expect(SystemMetricConversions.memoryPressure(sysctlValue: 3) == nil)
  #expect(SystemMetricConversions.memoryPressure(sysctlValue: -1) == nil)
  #expect(SystemMetricConversions.memoryPressure(sysctlValue: 5) == nil)
}

@Test func transferRatesWarmUpAndRejectCounterResets() {
  let first = SystemMetricConversions.ByteCounters(
    readBytes: 100, writeBytes: 200, capturedAt: Date(timeIntervalSince1970: 10), sourceIDs: ["systemDisk"])
  let next = SystemMetricConversions.ByteCounters(
    readBytes: 400, writeBytes: 500, capturedAt: Date(timeIntervalSince1970: 12), sourceIDs: ["systemDisk"])
  let reset = SystemMetricConversions.ByteCounters(
    readBytes: 10, writeBytes: 20, capturedAt: Date(timeIntervalSince1970: 13), sourceIDs: ["systemDisk"])

  #expect(SystemMetricConversions.transferRates(current: first, previous: nil) == nil)
  #expect(
    SystemMetricConversions.transferRates(current: next, previous: first)
      == .init(readBytesPerSecond: 150, writeBytesPerSecond: 150))
  #expect(SystemMetricConversions.transferRates(current: reset, previous: next) == nil)
}

@Test func transferRatesRejectAnInterfaceSetDiscontinuity() {
  let previous = SystemMetricConversions.ByteCounters(
    readBytes: 100, writeBytes: 200, capturedAt: Date(timeIntervalSince1970: 10), sourceIDs: ["en0"])
  let changedInterfaces = SystemMetricConversions.ByteCounters(
    readBytes: 200, writeBytes: 300, capturedAt: Date(timeIntervalSince1970: 11), sourceIDs: ["en0", "utun7"])

  #expect(SystemMetricConversions.transferRates(current: changedInterfaces, previous: previous) == nil)
}

@Test func batteryHealthUsesFullChargeCapacityAndDesignCapacity() {
  let health = SystemMetricConversions.batteryHealth(fullChargeCapacity: 5_814, designCapacity: 6_249)
  #expect(health?.value ?? 0 > 93)
  #expect(health?.value ?? 100 < 94)
  #expect(SystemMetricConversions.batteryHealth(fullChargeCapacity: nil, designCapacity: 6_249) == nil)
  #expect(SystemMetricConversions.batteryHealth(fullChargeCapacity: 5_814, designCapacity: 0) == nil)
  #expect(SystemMetricConversions.batteryHealth(fullChargeCapacity: 1_200, designCapacity: 1_000)?.value == 100)
}

@Test func localAddressesPutThePrimaryInterfaceAndIPv4First() {
  let ordered = SystemMetricConversions.orderedLocalAddresses(
    [
      .init(interface: "utun7", address: "2001:db8::1", isIPv4: false),
      .init(interface: "en0", address: "2001:db8::2", isIPv4: false),
      .init(interface: "en0", address: "192.0.2.9", isIPv4: true),
    ],
    primaryInterface: "en0"
  )

  #expect(ordered == ["192.0.2.9", "2001:db8::2", "2001:db8::1"])
}
