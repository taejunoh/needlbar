import Foundation
import NeedlbarWidgetSupport

public struct WidgetProjectionMapper: Sendable {
    private let now: Date

    public init(now: Date) { self.now = now }

    public func map(_ capture: WidgetStoreCapture) throws -> WidgetProjection {
        guard capture.providers.map(\.provider) == ProviderID.allCases else { throw WidgetProjectionError.invalidProviderOrder }
        let claude = capture.providers[0]
        let codex = capture.providers[1]
        let cursor = capture.providers[2]
        let quotaRows = try [mapQuota(claude, provider: .claude), mapQuota(codex, provider: .codex)]
        let usageRows = [mapUsage(claude, provider: .claude), mapUsage(codex, provider: .codex), mapUsage(cursor, provider: .cursor)]
        let values = usageRows.compactMap { row -> (UInt64, Decimal)? in
            guard let tokens = row.todayTokens, let cost = row.todayCostUSD else { return nil }
            return (tokens, cost)
        }
        var tokens: UInt64 = 0
        var cost = Decimal.zero
        for value in values {
            let (next, overflow) = tokens.addingReportingOverflow(value.0)
            guard !overflow else { throw WidgetProjectionError.invalidTodaySummary }
            tokens = next
            var left = cost
            var right = value.1
            var result = Decimal()
            guard NSDecimalAdd(&result, &left, &right, .plain) == .noError,
                  !result.isNaN,
                  result >= .zero else { throw WidgetProjectionError.invalidTodaySummary }
            cost = result
        }
        let completeness: WidgetTodaySummary.Completeness = values.isEmpty ? .unavailable : (values.count == 3 ? .complete : .partial)
        return try WidgetProjection(quotaRows: quotaRows, usageRows: usageRows, today: .init(completeness: completeness, totalTokens: values.isEmpty ? nil : tokens, estimatedCostUSD: values.isEmpty ? nil : cost))
    }

    private func mapQuota(_ capture: WidgetProviderCapture, provider: WidgetProvider) throws -> WidgetQuotaRow {
        guard capture.quotaLastSuccessfulAt.map({ $0 <= now && $0.timeIntervalSinceReferenceDate.isFinite }) ?? true else { throw WidgetProjectionError.invalidTimestamp }
        let stream = streamState(capture.quotaStatus, valueExists: capture.quota != nil, lastSuccessfulAt: capture.quotaLastSuccessfulAt)
        let candidates = (capture.quota?.windows ?? []).compactMap { window -> WidgetQuotaHeadline? in
            guard let id = WidgetQuotaWindowID(rawValue: window.id), id.provider == provider,
                  window.remainingPercent.isFinite, (0...100).contains(window.remainingPercent) else { return nil }
            return .init(id: id, remainingPercent: window.remainingPercent, resetsAt: window.resetsAt)
        }.sorted { $0.remainingPercent == $1.remainingPercent ? $0.id.rawValue < $1.id.rawValue : $0.remainingPercent < $1.remainingPercent }
        return try .init(provider: provider, stream: stream, lastSuccessfulAt: capture.quotaLastSuccessfulAt, headline: candidates.first)
    }

    private func mapUsage(_ capture: WidgetProviderCapture, provider: WidgetProvider) -> WidgetUsageRow {
        guard capture.usageLastSuccessfulAt.map({ $0 <= now && $0.timeIntervalSinceReferenceDate.isFinite }) ?? true else {
            return .init(provider: provider, stream: .unavailable, localDayKey: nil, utcOffsetSeconds: nil, lastSuccessfulAt: nil, todayTokens: nil, todayCostUSD: nil)
        }
        let stream = streamState(capture.usageStatus, valueExists: capture.usage != nil, lastSuccessfulAt: capture.usageLastSuccessfulAt)
        guard let usage = capture.usage,
              let proof = capture.usageDayProvenance?.provenContext,
              capture.usageLastSuccessfulAt != nil else {
            return .init(provider: provider, stream: .unavailable, localDayKey: nil, utcOffsetSeconds: nil, lastSuccessfulAt: nil, todayTokens: nil, todayCostUSD: nil)
        }
        let matches = usage.last7DaysDaily.filter { $0.date == proof.dayKey }
        guard matches.count == 1, matches[0].totalTokens == usage.today.totalTokens,
              !usage.today.estimatedCostUSD.isNaN, usage.today.estimatedCostUSD >= .zero else {
            return .init(provider: provider, stream: stream, localDayKey: nil, utcOffsetSeconds: nil, lastSuccessfulAt: capture.usageLastSuccessfulAt, todayTokens: nil, todayCostUSD: nil)
        }
        return .init(provider: provider, stream: stream, localDayKey: proof.dayKey, utcOffsetSeconds: proof.utcOffsetSeconds, lastSuccessfulAt: capture.usageLastSuccessfulAt, todayTokens: usage.today.totalTokens, todayCostUSD: usage.today.estimatedCostUSD)
    }

    private func streamState(_ status: DataStatus, valueExists: Bool, lastSuccessfulAt: Date?) -> WidgetStreamState {
        guard valueExists, let lastSuccessfulAt, lastSuccessfulAt <= now else { return .unavailable }
        if case .fresh = status { return .fresh }
        return .stale
    }
}
