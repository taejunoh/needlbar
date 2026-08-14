import Foundation

public struct ProviderSnapshot: Sendable, Equatable {
    public let provider: ProviderID
    public let usage: UsageSnapshot?
    public let quota: QuotaSnapshot?
    public let usageStatus: DataStatus
    public let quotaStatus: DataStatus
    public let updatedAt: Date

    public init(
        provider: ProviderID,
        usage: UsageSnapshot?,
        quota: QuotaSnapshot?,
        usageStatus: DataStatus,
        quotaStatus: DataStatus,
        updatedAt: Date
    ) {
        self.provider = provider
        self.usage = usage
        self.quota = quota
        self.usageStatus = usageStatus
        self.quotaStatus = quotaStatus
        self.updatedAt = updatedAt
    }
}
