import Foundation

public actor SystemMetricsService {
  private struct PublicIPCache: Sendable {
    let address: String
    let fetchedAt: Date
  }

  private let collector: any SystemMetricsCollecting
  private let publicIPProvider: any PublicIPProviding
  private let clock: any NeedlbarClock
  private let publicIPCacheLifetime: TimeInterval
  private var publicIPEnabled = false
  private var publicIPCache: PublicIPCache?
  private var latestSnapshot: SystemMetricsSnapshot?
  private var loopTask: Task<Void, Never>?
  private var updateContinuations: [UUID: AsyncStream<SystemMetricsSnapshot>.Continuation] = [:]

  public init(
    collector: any SystemMetricsCollecting = MacSystemMetricsCollector(),
    publicIPProvider: any PublicIPProviding = URLSessionPublicIPProvider(),
    clock: any NeedlbarClock = SystemMetricsClock(),
    publicIPCacheLifetime: TimeInterval = 300
  ) {
    self.collector = collector
    self.publicIPProvider = publicIPProvider
    self.clock = clock
    self.publicIPCacheLifetime = publicIPCacheLifetime
  }

  public func start(publicIPEnabled: Bool) {
    self.publicIPEnabled = publicIPEnabled
    guard loopTask == nil else { return }
    loopTask = Task { [weak self] in
      guard let self else { return }
      await self.runLoop()
    }
  }

  public func stop() {
    loopTask?.cancel()
    loopTask = nil
  }

  public func setPublicIPEnabled(_ enabled: Bool) {
    publicIPEnabled = enabled
    if !enabled {
      publicIPCache = nil
    }
  }

  public func updates() -> AsyncStream<SystemMetricsSnapshot> {
    let identifier = UUID()
    return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      updateContinuations[identifier] = continuation
      if let latestSnapshot {
        continuation.yield(latestSnapshot)
      }
      continuation.onTermination = { [weak self] _ in
        Task { await self?.removeUpdateContinuation(identifier) }
      }
    }
  }

  public func currentSnapshot() -> SystemMetricsSnapshot? {
    latestSnapshot
  }

  public func tickForTesting() async {
    await tick()
  }

  private func runLoop() async {
    while !Task.isCancelled {
      do {
        try await clock.sleep(for: .seconds(1))
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      await tick()
    }
  }

  private func tick() async {
    let timestamp = monotonicNow()
    do {
      var snapshot = try await collector.collect(at: timestamp)
      snapshot = normalized(snapshot, at: timestamp)
      if publicIPEnabled {
        snapshot = await applyingPublicIP(to: snapshot, at: timestamp)
      } else {
        snapshot = replacingPublicIP(in: snapshot, with: nil)
      }
      latestSnapshot = snapshot
    } catch {
      latestSnapshot = failedSnapshot(at: timestamp)
    }
    publishLatestSnapshot()
  }

  private func applyingPublicIP(
    to snapshot: SystemMetricsSnapshot,
    at timestamp: Date
  ) async -> SystemMetricsSnapshot {
    if let cache = publicIPCache,
      timestamp.timeIntervalSince(cache.fetchedAt) < publicIPCacheLifetime
    {
      return replacingPublicIP(in: snapshot, with: cache.address)
    }

    do {
      let address = try await fetchPublicIPWithTimeout()
      publicIPCache = PublicIPCache(address: address, fetchedAt: timestamp)
      return replacingPublicIP(in: snapshot, with: address)
    } catch {
      // Public-IP lookup is optional and independently fallible. It must not
      // hide a fresh local transfer-rate measurement from the same snapshot.
      return replacingPublicIP(in: snapshot, with: nil)
    }
  }

  private func fetchPublicIPWithTimeout() async throws -> String {
    try await withThrowingTaskGroup(of: String.self) { group in
      group.addTask { [publicIPProvider] in
        try await publicIPProvider.fetchPublicIP()
      }
      group.addTask { [clock] in
        try await clock.sleep(for: .seconds(2))
        throw PublicIPTimeoutError()
      }
      defer { group.cancelAll() }
      guard let result = try await group.next() else {
        throw PublicIPTimeoutError()
      }
      return result
    }
  }

  private func monotonicNow() -> Date {
    let current = clock.now
    guard let latestSnapshot else { return current }
    return max(current, latestSnapshot.capturedAt)
  }

  private func normalized(_ snapshot: SystemMetricsSnapshot, at timestamp: Date)
    -> SystemMetricsSnapshot
  {
    guard snapshot.capturedAt != timestamp else { return snapshot }
    let availability = Dictionary(
      uniqueKeysWithValues: MonitorModuleID.allCases.map { module in
        let value = snapshot.availability[module] ?? .fresh(capturedAt: timestamp)
        switch value {
        case .fresh:
          return (module, MetricAvailability.fresh(capturedAt: timestamp))
        case .stale, .unavailable:
          return (module, value)
        }
      })
    return SystemMetricsSnapshot(
      capturedAt: timestamp,
      cpu: snapshot.cpu,
      memory: snapshot.memory,
      disks: snapshot.disks,
      network: snapshot.network,
      battery: snapshot.battery,
      availability: availability
    )
  }

  private func failedSnapshot(at timestamp: Date) -> SystemMetricsSnapshot {
    guard let latestSnapshot else {
      return SystemMetricsSnapshot(
        capturedAt: timestamp,
        cpu: .init(totalUsage: nil, perCoreUsage: []),
        memory: .init(usedBytes: nil, freeBytes: nil, swapUsedBytes: nil, pressure: nil),
        disks: [],
        network: .init(
          uploadBytesPerSecond: nil, downloadBytesPerSecond: nil, localIPAddresses: [],
          publicIPAddress: nil),
        battery: .init(level: nil, isCharging: nil, health: nil),
        availability: unavailableAvailability(code: "systemMetricsUnavailable")
      )
    }

    let availability = Dictionary(
      uniqueKeysWithValues: MonitorModuleID.allCases.map { module in
        let previous = latestSnapshot.availability[module]
        let lastSuccessfulAt: Date
        switch previous {
        case .fresh(let capturedAt): lastSuccessfulAt = capturedAt
        case .stale(let date): lastSuccessfulAt = date
        case .unavailable, nil: lastSuccessfulAt = latestSnapshot.capturedAt
        }
        return (module, MetricAvailability.stale(lastSuccessfulAt: lastSuccessfulAt))
      })
    return SystemMetricsSnapshot(
      capturedAt: timestamp,
      cpu: latestSnapshot.cpu,
      memory: latestSnapshot.memory,
      disks: latestSnapshot.disks,
      network: latestSnapshot.network,
      battery: latestSnapshot.battery,
      availability: availability
    )
  }

  private func replacingPublicIP(in snapshot: SystemMetricsSnapshot, with address: String?)
    -> SystemMetricsSnapshot
  {
    SystemMetricsSnapshot(
      capturedAt: snapshot.capturedAt,
      cpu: snapshot.cpu,
      memory: snapshot.memory,
      disks: snapshot.disks,
      network: .init(
        uploadBytesPerSecond: snapshot.network.uploadBytesPerSecond,
        downloadBytesPerSecond: snapshot.network.downloadBytesPerSecond,
        localIPAddresses: snapshot.network.localIPAddresses,
        publicIPAddress: address
      ),
      battery: snapshot.battery,
      availability: snapshot.availability
    )
  }

  private func unavailableAvailability(code: String) -> [MonitorModuleID: MetricAvailability] {
    Dictionary(
      uniqueKeysWithValues: MonitorModuleID.allCases.map { ($0, .unavailable(code: code)) })
  }

  private func publishLatestSnapshot() {
    guard let latestSnapshot else { return }
    for continuation in updateContinuations.values {
      continuation.yield(latestSnapshot)
    }
  }

  private func removeUpdateContinuation(_ identifier: UUID) {
    updateContinuations.removeValue(forKey: identifier)
  }
}

private struct PublicIPTimeoutError: Error {}
