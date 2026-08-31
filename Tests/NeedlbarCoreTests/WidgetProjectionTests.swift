import Foundation
import Testing
@testable import NeedlbarCore
import NeedlbarWidgetSupport

@Test func directUsageApplicationHasUnknownWidgetDay() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = ProviderSnapshotStore(now: { now })
    await store.applyUsage(fixtureUsage(todayTokens: 44, dailyDay: "2027-01-15"), for: .claude)
    let capture = await store.captureForWidget(exportedAt: now)
    let document = try WidgetProjectionMapper(now: now).map(capture)
    #expect(document.usageRows[0].todayTokens == nil)
    #expect(document.today.completeness == .unavailable)
}

@Test func changedDayOrZoneCannotEstablishUsageDay() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let before = WidgetUsageDayContext(dayKey: "2027-01-15", timeZoneIdentifier: "America/New_York", utcOffsetSeconds: -18_000)
    let after = WidgetUsageDayContext(dayKey: "2027-01-16", timeZoneIdentifier: "Asia/Tokyo", utcOffsetSeconds: 32_400)
    let proof = WidgetUsageDayProvenance(startedAt: start, startedContext: before, endedAt: start.addingTimeInterval(1), endedContext: after)
    #expect(proof.provenContext == nil)
}

@Test(arguments: [
    ("stable", 1.0, true, true),
    ("changed-day", 1.0, false, true),
    ("changed-zone", 1.0, true, false),
    ("too-long", WidgetUsageDayProvenance.maximumInterval + 1, true, true),
]) func usageDayProofRequiresStableBoundedGregorianContext(
    _: String,
    interval: TimeInterval,
    sameDay: Bool,
    sameZone: Bool
) {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let before = WidgetUsageDayContext(dayKey: "2027-01-15", timeZoneIdentifier: "America/New_York", utcOffsetSeconds: -18_000)
    let after = WidgetUsageDayContext(
        dayKey: sameDay ? before.dayKey : "2027-01-16",
        timeZoneIdentifier: sameZone ? before.timeZoneIdentifier : "Asia/Tokyo",
        utcOffsetSeconds: sameZone ? before.utcOffsetSeconds : 32_400
    )
    let proof = WidgetUsageDayProvenance(startedAt: start, startedContext: before, endedAt: start.addingTimeInterval(interval), endedContext: after)
    #expect((proof.provenContext != nil) == (interval <= WidgetUsageDayProvenance.maximumInterval && sameDay && sameZone))
}

@Test func mapperFiltersProviderAndBreaksHeadlineTiesByLexicalID() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let claudeQuota = QuotaSnapshot(windows: [
        try QuotaWindow(id: "claude.weekly", title: "private", usedPercent: 80, resetsAt: now.addingTimeInterval(3600)),
        try QuotaWindow(id: "claude.session", title: "private", usedPercent: 80, resetsAt: now.addingTimeInterval(3600)),
        try QuotaWindow(id: "codex.primary", title: "private", usedPercent: 99, resetsAt: now.addingTimeInterval(3600))
    ])
    let codexQuota = QuotaSnapshot(windows: [
        try QuotaWindow(id: "claude.session", title: "private", usedPercent: 99, resetsAt: now.addingTimeInterval(3600)),
        try QuotaWindow(id: "codex.secondary", title: "private", usedPercent: 50, resetsAt: now.addingTimeInterval(3600)),
        try QuotaWindow(id: "codex.primary", title: "private", usedPercent: 50, resetsAt: now.addingTimeInterval(3600))
    ])
    let projection = try WidgetProjectionMapper(now: now).map(makeWidgetCapture(now: now, claudeQuota: claudeQuota, codexQuota: codexQuota))
    #expect(projection.quotaRows[0].headline?.id == .claudeSession)
    #expect(projection.quotaRows[1].headline?.id == .codexPrimary)
}

@Test func publisherSkipsByteIdenticalProjectionAndReloadsOnce() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let writer = FixtureWidgetWriter()
    let reloader = FixtureWidgetReloader()
    let publisher = WidgetProjectionPublisher(writer: writer, reloader: reloader, destination: URL(fileURLWithPath: "/tmp/needlbar-widget-fixture.json"), now: { now })
    let capture = try makeWidgetCapture(now: now)
    await publisher.publish(capture)
    await publisher.publish(capture)
    #expect(writer.attempts == 1)
    #expect(writer.committed.count == 1)
    #expect(await reloader.reloadCount == 1)
}

@Test func publisherWriterFailurePreservesLastBytesAndReloadCount() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let writer = FixtureWidgetWriter()
    let reloader = FixtureWidgetReloader()
    let publisher = WidgetProjectionPublisher(writer: writer, reloader: reloader, destination: URL(fileURLWithPath: "/tmp/needlbar-widget-fixture.json"), now: { now })
    await publisher.publish(try makeWidgetCapture(now: now))
    let previousBytes = writer.committed[0]
    writer.setFailing(true)
    let changedQuota = QuotaSnapshot(windows: [try QuotaWindow(id: "claude.session", title: "private", usedPercent: 90, resetsAt: now.addingTimeInterval(3600))])
    await publisher.publish(try makeWidgetCapture(now: now, claudeQuota: changedQuota))
    #expect(writer.attempts == 2)
    #expect(writer.committed == [previousBytes])
    #expect(await reloader.reloadCount == 1)
}

@Test func mapperRequiresExactlyOneMatchingDailyWitness() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let cases: [(UsageSnapshot, Bool)] = [
        (fixtureUsage(todayTokens: 10, dailyDay: "2027-01-15"), true),
        (fixtureUsage(todayTokens: 10, dailyDay: "2027-01-14"), false),
        (usage(todayTokens: 10, daily: [.init(date: "2027-01-15", totalTokens: 10), .init(date: "2027-01-15", totalTokens: 10)]), false),
        (usage(todayTokens: 10, daily: [.init(date: "2027-01-15", totalTokens: 9)]), false),
    ]
    for (usage, expected) in cases {
        var capture = try makeWidgetCapture(now: now)
        capture = replacing(capture, provider: .claude, usage: usage)
        let row = try WidgetProjectionMapper(now: now).map(capture).usageRows[0]
        #expect((row.todayTokens != nil) == expected)
    }
}

@Test func mapperPreservesStaleLastGoodUsageInAggregate() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let context = WidgetUsageDayContext(dayKey: "2027-01-15", timeZoneIdentifier: "America/New_York", utcOffsetSeconds: -18_000)
    let proof = WidgetUsageDayProvenance(startedAt: now, startedContext: context, endedAt: now, endedContext: context)
    let store = ProviderSnapshotStore(now: { now })
    await store.applyUsage(fixtureUsage(todayTokens: 44, dailyDay: context.dayKey), for: .claude, widgetDayProvenance: proof)
    await store.markUsageFailure(for: .claude, status: .error(message: "offline", lastSuccessfulAt: nil))
    let projection = try WidgetProjectionMapper(now: now).map(await store.captureForWidget(exportedAt: now))
    #expect(projection.usageRows[0].stream == .stale)
    #expect(projection.usageRows[0].todayTokens == 44)
    #expect(projection.today.totalTokens == 44)
    #expect(projection.today.completeness == .partial)
}

@Test func mapperKeepsUsageAndQuotaErrorsIndependentAndExcludesCursorQuota() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var capture = try makeWidgetCapture(now: now)
    capture = replacing(capture, provider: .claude, quotaStatus: .error(message: "offline", lastSuccessfulAt: now))
    capture = replacing(capture, provider: .cursor, quota: QuotaSnapshot(windows: [try QuotaWindow(id: "codex.primary", title: "private", usedPercent: 20, resetsAt: now)]), quotaStatus: .fresh, quotaLastSuccessfulAt: now)
    let projection = try WidgetProjectionMapper(now: now).map(capture)
    #expect(projection.usageRows[0].stream == .fresh)
    #expect(projection.quotaRows[0].stream == .stale)
    #expect(projection.quotaRows.count == 2)
}

@Test func mapperRejectsOverflowingTodayAggregate() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var capture = try makeWidgetCapture(now: now)
    capture = replacing(capture, provider: .claude, usage: fixtureUsage(todayTokens: .max, dailyDay: "2027-01-15"))
    #expect(throws: WidgetProjectionError.invalidTodaySummary) {
        _ = try WidgetProjectionMapper(now: now).map(capture)
    }
}

@Test func publisherDoesNotReplacePriorBytesWhenMappingFails() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let writer = FixtureWidgetWriter()
    let reloader = FixtureWidgetReloader()
    let publisher = WidgetProjectionPublisher(writer: writer, reloader: reloader, destination: fixtureDestination(), now: { now })
    let capture = try makeWidgetCapture(now: now)
    await publisher.publish(capture)
    let committed = writer.committed
    await publisher.publish(.init(exportedAt: now, providers: []))
    #expect(writer.committed == committed)
    #expect(await reloader.reloadCount == 1)
}

@Test func publisherDoesNotWriteOrReloadFromCancelledTask() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let writer = FixtureWidgetWriter()
    let reloader = FixtureWidgetReloader()
    let publisher = WidgetProjectionPublisher(writer: writer, reloader: reloader, destination: fixtureDestination(), now: { now })
    let capture = try makeWidgetCapture(now: now)
    let task = Task {
        try? await Task.sleep(for: .seconds(60))
        await publisher.publish(capture)
    }
    task.cancel()
    await task.value
    #expect(writer.attempts == 0)
    #expect(await reloader.reloadCount == 0)
}

private func fixtureUsage(todayTokens: UInt64, dailyDay: String, cost: Decimal = Decimal(string: "1.00")!) -> UsageSnapshot {
    let period = UsagePeriod(inputTokens: todayTokens, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, totalTokens: todayTokens, estimatedCostUSD: cost)
    return UsageSnapshot(inputTokens: todayTokens, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, totalTokens: todayTokens, estimatedCostUSD: cost, today: period, last7Days: period, last7DaysDaily: [.init(date: dailyDay, totalTokens: todayTokens)], last30Days: period)
}

private func usage(todayTokens: UInt64, daily: [DailyUsagePoint]) -> UsageSnapshot {
    let period = UsagePeriod(inputTokens: todayTokens, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, totalTokens: todayTokens, estimatedCostUSD: Decimal(string: "1.00")!)
    return UsageSnapshot(inputTokens: todayTokens, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, totalTokens: todayTokens, estimatedCostUSD: Decimal(string: "1.00")!, today: period, last7Days: period, last7DaysDaily: daily, last30Days: period)
}

private func makeWidgetCapture(now: Date, claudeQuota: QuotaSnapshot? = nil, codexQuota: QuotaSnapshot? = nil) throws -> WidgetStoreCapture {
    let context = WidgetUsageDayContext(dayKey: "2027-01-15", timeZoneIdentifier: "America/New_York", utcOffsetSeconds: -18_000)
    let proof = WidgetUsageDayProvenance(startedAt: now, startedContext: context, endedAt: now, endedContext: context)
    func provider(_ id: ProviderID, quota: QuotaSnapshot?) -> WidgetProviderCapture {
        .init(provider: id, usage: fixtureUsage(todayTokens: 10, dailyDay: "2027-01-15"), quota: quota, usageStatus: .fresh, quotaStatus: quota == nil ? .unavailable : .fresh, usageLastSuccessfulAt: now, quotaLastSuccessfulAt: quota == nil ? nil : now, usageDayProvenance: proof)
    }
    let defaultClaude = QuotaSnapshot(windows: [try QuotaWindow(id: "claude.session", title: "private", usedPercent: 20, resetsAt: now.addingTimeInterval(3600))])
    let defaultCodex = QuotaSnapshot(windows: [try QuotaWindow(id: "codex.primary", title: "private", usedPercent: 20, resetsAt: now.addingTimeInterval(3600))])
    return .init(exportedAt: now, providers: [provider(.claude, quota: claudeQuota ?? defaultClaude), provider(.codex, quota: codexQuota ?? defaultCodex), provider(.cursor, quota: nil)])
}

private func replacing(
    _ capture: WidgetStoreCapture,
    provider target: ProviderID,
    usage: UsageSnapshot? = nil,
    quota: QuotaSnapshot? = nil,
    usageStatus: DataStatus? = nil,
    quotaStatus: DataStatus? = nil,
    quotaLastSuccessfulAt: Date? = nil
) -> WidgetStoreCapture {
    .init(exportedAt: capture.exportedAt, providers: capture.providers.map { value in
        guard value.provider == target else { return value }
        return .init(
            provider: value.provider,
            usage: usage ?? value.usage,
            quota: quota ?? value.quota,
            usageStatus: usageStatus ?? value.usageStatus,
            quotaStatus: quotaStatus ?? value.quotaStatus,
            usageLastSuccessfulAt: value.usageLastSuccessfulAt,
            quotaLastSuccessfulAt: quotaLastSuccessfulAt ?? value.quotaLastSuccessfulAt,
            usageDayProvenance: value.usageDayProvenance
        )
    })
}

private func fixtureDestination() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("needlbar-widget-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("NeedlbarWidgetProjection.json")
}

private enum FixtureWidgetWriterError: Error, Sendable { case failed }

private final class FixtureWidgetWriter: WidgetProjectionWriting, @unchecked Sendable {
    private var failing = false
    private(set) var attempts = 0
    private(set) var committed: [Data] = []
    func setFailing(_ value: Bool) { failing = value }
    func write(_ bytes: Data, to destination: URL) throws -> AtomicWriteResult {
        attempts += 1
        guard !failing else { throw FixtureWidgetWriterError.failed }
        committed.append(bytes)
        return .committed
    }
}

private actor FixtureWidgetReloader: WidgetTimelineReloading {
    private(set) var reloadCount = 0
    func reloadOverview() { reloadCount += 1 }
}
