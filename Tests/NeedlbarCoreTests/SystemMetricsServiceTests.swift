import Foundation
import Testing

@testable import NeedlbarCore

@Test func serviceDoesNotCallPublicIPWhenTheToggleIsOff() async {
  let publicIP = FakePublicIPProvider(result: .success("203.0.113.8"))
  let collector = FakeSystemCollector(snapshot: fixtureSnapshot())
  let service = SystemMetricsService(
    collector: collector,
    publicIPProvider: publicIP,
    clock: TestClock(start: Date(timeIntervalSince1970: 10_000))
  )

  await service.start(publicIPEnabled: false)
  await service.tickForTesting()

  #expect(await publicIP.calls == 0)
  #expect(await collector.calls == 1)
}

@Test func publicIPToggleUpdatesAStartedServiceWithoutRestartingTheLoop() async throws {
  let publicIP = FakePublicIPProvider(result: .success("203.0.113.8"))
  let service = SystemMetricsService(
    collector: FakeSystemCollector(snapshot: fixtureSnapshot()),
    publicIPProvider: publicIP,
    clock: TestClock(start: Date(timeIntervalSince1970: 10_000))
  )

  await service.start(publicIPEnabled: false)
  await service.setPublicIPEnabled(true)
  await service.tickForTesting()
  let snapshot = try #require(await service.currentSnapshot())

  #expect(snapshot.network.publicIPAddress == "203.0.113.8")
  #expect(await publicIP.calls == 1)
}

@Test func publicIPUsesFiveMinuteCacheAndDoesNotAmplifyTheOneSecondTick() async {
  let clock = TestClock(start: Date(timeIntervalSince1970: 10_000))
  let publicIP = FakePublicIPProvider(result: .success("203.0.113.8"))
  let service = SystemMetricsService(
    collector: FakeSystemCollector(snapshot: fixtureSnapshot()),
    publicIPProvider: publicIP,
    clock: clock
  )

  await service.start(publicIPEnabled: true)
  await service.tickForTesting()
  await service.tickForTesting()
  #expect(await publicIP.calls == 1)

  clock.advance(by: 301)
  await service.tickForTesting()
  #expect(await publicIP.calls == 2)
}

@Test func collectorFailureRetainsLastSnapshotAsStaleAndDoesNotStopService() async throws {
  let start = Date(timeIntervalSince1970: 10_000)
  let collector = FakeSystemCollector(
    snapshot: fixtureSnapshot(), then: .failure(TestFailure.collector))
  let service = SystemMetricsService(
    collector: collector,
    publicIPProvider: FakePublicIPProvider(result: .success("203.0.113.8")),
    clock: TestClock(start: start)
  )

  await service.start(publicIPEnabled: false)
  await service.tickForTesting()
  let fresh = try #require(await service.currentSnapshot())
  await service.tickForTesting()
  let stale = try #require(await service.currentSnapshot())

  #expect(stale.cpu.totalUsage == fresh.cpu.totalUsage)
  #expect(stale.availability[.cpu] == .stale(lastSuccessfulAt: start))
  #expect(stale.availability[.memory] == .stale(lastSuccessfulAt: start))
  #expect(await collector.calls == 2)
}

@Test func firstCollectorFailurePublishesUnavailableSnapshot() async throws {
  let service = SystemMetricsService(
    collector: FakeSystemCollector(result: .failure(TestFailure.collector)),
    publicIPProvider: FakePublicIPProvider(result: .success("203.0.113.8")),
    clock: TestClock(start: Date(timeIntervalSince1970: 10_000))
  )

  await service.start(publicIPEnabled: false)
  await service.tickForTesting()
  let snapshot = try #require(await service.currentSnapshot())

  #expect(snapshot.cpu.totalUsage == nil)
  #expect(snapshot.availability[.cpu] == .unavailable(code: "systemMetricsUnavailable"))
}

@Test func publicIPFailureIsBoundedAndDoesNotFailSystemCollector() async throws {
  let collector = FakeSystemCollector(snapshot: fixtureSnapshot())
  let publicIP = FakePublicIPProvider(result: .failure(TestFailure.publicIP))
  let service = SystemMetricsService(
    collector: collector,
    publicIPProvider: publicIP,
    clock: TestClock(start: Date(timeIntervalSince1970: 10_000))
  )

  await service.start(publicIPEnabled: true)
  await service.tickForTesting()
  let snapshot = try #require(await service.currentSnapshot())

  #expect(snapshot.cpu.totalUsage?.value == 24.5)
  #expect(snapshot.network.publicIPAddress == nil)
  #expect(snapshot.availability[.network] == .unavailable(code: "publicIPUnavailable"))
}

@Test func publicIPFetchIsCancelledAtTheTwoSecondBoundary() async throws {
  let service = SystemMetricsService(
    collector: FakeSystemCollector(snapshot: fixtureSnapshot()),
    publicIPProvider: HangingPublicIPProvider(),
    clock: TestClock(
      start: Date(timeIntervalSince1970: 10_000), returnImmediatelyForTwoSeconds: true)
  )

  await service.start(publicIPEnabled: true)
  await service.tickForTesting()
  let snapshot = try #require(await service.currentSnapshot())

  #expect(snapshot.network.publicIPAddress == nil)
  #expect(snapshot.availability[.network] == .unavailable(code: "publicIPUnavailable"))
}

private func fixtureSnapshot(capturedAt: Date = Date(timeIntervalSince1970: 10_000))
  -> SystemMetricsSnapshot
{
  SystemMetricsSnapshot(
    capturedAt: capturedAt,
    cpu: .init(totalUsage: MetricPercentage(24.5), perCoreUsage: [MetricPercentage(24.5)!]),
    memory: .init(usedBytes: 4_000, freeBytes: 6_000, swapUsedBytes: 0, pressure: "normal"),
    disks: [
      .init(
        name: "Macintosh HD", usedBytes: 8_000, freeBytes: 2_000, readBytesPerSecond: 10,
        writeBytesPerSecond: 5)
    ],
    network: .init(
      uploadBytesPerSecond: 100, downloadBytesPerSecond: 200, localIPAddresses: ["192.0.2.4"],
      publicIPAddress: nil),
    battery: .init(level: MetricPercentage(100), isCharging: true, health: MetricPercentage(96)),
    availability: Dictionary(
      uniqueKeysWithValues: MonitorModuleID.allCases.map { ($0, .fresh(capturedAt: capturedAt)) })
  )
}

private enum TestFailure: Error {
  case collector
  case publicIP
}

private final actor FakeSystemCollector: SystemMetricsCollecting {
  private var results: [Result<SystemMetricsSnapshot, Error>]
  private let fallback: Result<SystemMetricsSnapshot, Error>
  private(set) var calls = 0

  init(snapshot: SystemMetricsSnapshot) {
    results = [.success(snapshot)]
    fallback = .success(snapshot)
  }

  init(snapshot: SystemMetricsSnapshot, then next: Result<SystemMetricsSnapshot, Error>) {
    results = [.success(snapshot), next]
    fallback = next
  }

  init(result: Result<SystemMetricsSnapshot, Error>) {
    results = [result]
    fallback = result
  }

  func collect(at _: Date) async throws -> SystemMetricsSnapshot {
    calls += 1
    let result: Result<SystemMetricsSnapshot, Error>
    if results.isEmpty {
      result = fallback
    } else {
      result = results.removeFirst()
    }
    return try result.get()
  }
}

private final actor FakePublicIPProvider: PublicIPProviding {
  let result: Result<String, Error>
  private(set) var calls = 0

  init(result: Result<String, Error>) {
    self.result = result
  }

  func fetchPublicIP() async throws -> String {
    calls += 1
    return try result.get()
  }
}

private final actor HangingPublicIPProvider: PublicIPProviding {
  func fetchPublicIP() async throws -> String {
    try await Task.sleep(for: .seconds(3600))
    return "203.0.113.8"
  }
}

private final class TestClock: NeedlbarClock, @unchecked Sendable {
  private let lock = NSLock()
  private var value: Date
  private let returnImmediatelyForTwoSeconds: Bool

  init(start: Date, returnImmediatelyForTwoSeconds: Bool = false) {
    value = start
    self.returnImmediatelyForTwoSeconds = returnImmediatelyForTwoSeconds
  }

  var now: Date {
    lock.withLock { value }
  }

  func advance(by seconds: TimeInterval) {
    lock.withLock { value = value.addingTimeInterval(seconds) }
  }

  func sleep(for duration: Duration) async throws {
    if returnImmediatelyForTwoSeconds, duration == .seconds(2) { return }
    try await Task.sleep(for: .seconds(3600))
  }
}

extension NSLock {
  fileprivate func withLock<T>(_ operation: () -> T) -> T {
    lock()
    defer { unlock() }
    return operation()
  }
}
