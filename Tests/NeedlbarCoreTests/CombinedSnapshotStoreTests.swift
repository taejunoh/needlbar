import Foundation
import Testing

@testable import NeedlbarCore

@Test func providerFailureDoesNotEraseFreshSystemMetrics() async {
  let date = Date(timeIntervalSince1970: 10_000)
  let store = CombinedSnapshotStore()
  await store.applySystem(fixtureSystemSnapshot(at: date), at: date)
  await store.applyProviders([failedProviderSnapshot(.claude, at: date)], at: date)

  let combined = await store.snapshot()
  #expect(combined.system?.cpu.totalUsage?.value == 24.5)
  #expect(
    combined.providers.first(where: { $0.provider == .claude })?.usageStatus
      == .error(message: "failed", lastSuccessfulAt: nil))
}

@Test func systemFailureStateRemainsIndependentOfProviderRefresh() async {
  let date = Date(timeIntervalSince1970: 10_000)
  let store = CombinedSnapshotStore()
  let fresh = fixtureSystemSnapshot(at: date)
  await store.applySystem(fresh, at: date)
  await store.applyProviders([failedProviderSnapshot(.codex, at: date)], at: date)

  let stale = SystemMetricsSnapshot(
    capturedAt: date.addingTimeInterval(1),
    cpu: fresh.cpu,
    memory: fresh.memory,
    disks: fresh.disks,
    network: fresh.network,
    battery: fresh.battery,
    availability: Dictionary(
      uniqueKeysWithValues: MonitorModuleID.allCases.map {
        ($0, .stale(lastSuccessfulAt: date))
      })
  )
  await store.applySystem(stale, at: date.addingTimeInterval(1))

  let combined = await store.snapshot()
  #expect(combined.systemAvailability[.cpu] == .stale(lastSuccessfulAt: date))
  #expect(
    combined.providers.first(where: { $0.provider == .codex })?.usageStatus
      == .error(message: "failed", lastSuccessfulAt: nil))
}

@Test func newSubscriberReceivesCurrentCombinedSnapshotImmediately() async throws {
  let date = Date(timeIntervalSince1970: 10_000)
  let store = CombinedSnapshotStore()
  await store.applySystem(fixtureSystemSnapshot(at: date), at: date)

  var iterator = await store.updates().makeAsyncIterator()
  let current = try #require(await iterator.next())
  #expect(current.system?.capturedAt == date)
  #expect(current.system?.cpu.totalUsage?.value == 24.5)
}

@Test func updateStreamKeepsOnlyNewestCombinedSnapshot() async throws {
  let firstDate = Date(timeIntervalSince1970: 10_000)
  let secondDate = firstDate.addingTimeInterval(1)
  let store = CombinedSnapshotStore()
  let stream = await store.updates()
  var iterator = stream.makeAsyncIterator()
  let initial = try #require(await iterator.next())
  await store.applySystem(fixtureSystemSnapshot(at: firstDate), at: firstDate)
  await store.applySystem(fixtureSystemSnapshot(at: secondDate), at: secondDate)

  let latest = try #require(await iterator.next())
  #expect(initial.system == nil)
  #expect(latest.system?.capturedAt == secondDate)
}

private func fixtureSystemSnapshot(at date: Date) -> SystemMetricsSnapshot {
  SystemMetricsSnapshot(
    capturedAt: date,
    cpu: .init(totalUsage: MetricPercentage(24.5), perCoreUsage: [MetricPercentage(24.5)!]),
    memory: .init(usedBytes: 4_000, freeBytes: 6_000, swapUsedBytes: 0, pressure: "normal"),
    disks: [],
    network: .init(
      uploadBytesPerSecond: 100, downloadBytesPerSecond: 200, localIPAddresses: [],
      publicIPAddress: nil),
    battery: .init(level: MetricPercentage(100), isCharging: true, health: MetricPercentage(96)),
    availability: Dictionary(
      uniqueKeysWithValues: MonitorModuleID.allCases.map {
        ($0, .fresh(capturedAt: date))
      })
  )
}

private func failedProviderSnapshot(_ provider: ProviderID, at date: Date) -> ProviderSnapshot {
  ProviderSnapshot(
    provider: provider,
    usage: nil,
    quota: nil,
    usageStatus: .error(message: "failed", lastSuccessfulAt: nil),
    quotaStatus: .unavailable,
    updatedAt: date
  )
}
