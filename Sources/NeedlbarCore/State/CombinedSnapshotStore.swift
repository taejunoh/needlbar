import Foundation

public struct CombinedUsageSnapshot: Equatable, Sendable {
  public let system: SystemMetricsSnapshot?
  public let providers: [ProviderSnapshot]
  public let capturedAt: Date
  public let systemAvailability: [MonitorModuleID: MetricAvailability]

  public init(
    system: SystemMetricsSnapshot?,
    providers: [ProviderSnapshot],
    capturedAt: Date,
    systemAvailability: [MonitorModuleID: MetricAvailability]
  ) {
    self.system = system
    self.providers = providers
    self.capturedAt = capturedAt
    self.systemAvailability = systemAvailability
  }
}

public actor CombinedSnapshotStore {
  private var systemSnapshot: SystemMetricsSnapshot?
  private var providerSnapshots: [ProviderID: ProviderSnapshot]
  private var latestCapturedAt: Date
  private var updateContinuations: [UUID: AsyncStream<CombinedUsageSnapshot>.Continuation] = [:]

  public init(now: Date = Date()) {
    latestCapturedAt = now
    providerSnapshots = Dictionary(
      uniqueKeysWithValues: ProviderID.allCases.map { provider in
        (
          provider,
          ProviderSnapshot(
            provider: provider,
            usage: nil,
            quota: nil,
            usageStatus: .unavailable,
            quotaStatus: .unavailable,
            updatedAt: now
          )
        )
      }
    )
  }

  public func applySystem(_ snapshot: SystemMetricsSnapshot, at date: Date? = nil) {
    systemSnapshot = snapshot
    let timestamp = max(date ?? snapshot.capturedAt, snapshot.capturedAt)
    latestCapturedAt = max(latestCapturedAt, timestamp)
    publish()
  }

  public func applyProviders(_ snapshots: [ProviderSnapshot], at date: Date? = nil) {
    for snapshot in snapshots {
      providerSnapshots[snapshot.provider] = snapshot
    }
    let timestamp = date ?? snapshots.map(\.updatedAt).max() ?? latestCapturedAt
    latestCapturedAt = max(latestCapturedAt, timestamp)
    publish()
  }

  public func snapshot() -> CombinedUsageSnapshot {
    CombinedUsageSnapshot(
      system: systemSnapshot,
      providers: ProviderID.allCases.compactMap { providerSnapshots[$0] },
      capturedAt: latestCapturedAt,
      systemAvailability: systemSnapshot?.availability ?? [:]
    )
  }

  public func updates() -> AsyncStream<CombinedUsageSnapshot> {
    let identifier = UUID()
    return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      updateContinuations[identifier] = continuation
      continuation.yield(snapshot())
      continuation.onTermination = { [weak self] _ in
        Task { await self?.removeUpdateContinuation(identifier) }
      }
    }
  }

  private func publish() {
    let current = snapshot()
    for continuation in updateContinuations.values {
      continuation.yield(current)
    }
  }

  private func removeUpdateContinuation(_ identifier: UUID) {
    updateContinuations.removeValue(forKey: identifier)
  }
}
