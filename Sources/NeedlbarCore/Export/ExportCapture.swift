import Foundation

public struct ExportCapture: Sendable, Equatable {
    public let exportedAt: Date
    public let providers: [ProviderExportState]
}

public struct ProviderExportState: Sendable, Equatable {
    public let provider: ProviderID
    public let usage: UsageSnapshot?
    public let quota: QuotaSnapshot?
    public let usageStatus: DataStatus
    public let quotaStatus: DataStatus
    public let usageLastSuccessfulAt: Date?
    public let quotaLastSuccessfulAt: Date?
    public let everUpdated: Bool
    public let updatedAt: Date?
}

public protocol ExportCaptureProviding: Sendable {
    func captureForExport(exportedAt: Date) async -> ExportCapture
}
