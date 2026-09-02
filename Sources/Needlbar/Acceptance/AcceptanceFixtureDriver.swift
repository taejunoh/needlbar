#if NEEDLBAR_ACCEPTANCE_DRIVER
import Foundation
import NeedlbarCore

protocol AcceptanceFixtureSleeping: Sendable {
    func sleep(for duration: Duration) async throws
}

struct SystemAcceptanceSleeper: AcceptanceFixtureSleeping {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

actor AcceptanceFixtureDriver {
    private let fixture: AcceptanceFixture
    private let store: ProviderSnapshotStore
    private let sleeper: any AcceptanceFixtureSleeping
    private var task: Task<Void, Never>?

    init(
        fixture: AcceptanceFixture,
        store: ProviderSnapshotStore,
        sleeper: any AcceptanceFixtureSleeping = SystemAcceptanceSleeper()
    ) {
        self.fixture = fixture
        self.store = store
        self.sleeper = sleeper
    }

    func start() async {
        guard task == nil else { return }
        let fixture = fixture
        let store = store
        let sleeper = sleeper
        task = Task {
            for event in fixture.events {
                guard !Task.isCancelled else { return }
                do {
                    try await sleeper.sleep(for: event.delay)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await Self.apply(event, to: store, timeZone: fixture.timeZone)
            }
        }
        await task?.value
        task = nil
    }

    func stop() async {
        let running = task
        task = nil
        running?.cancel()
        await running?.value
    }

    private static func apply(
        _ event: AcceptanceFixtureEvent,
        to store: ProviderSnapshotStore,
        timeZone: TimeZone
    ) async {
        let context = WidgetUsageDayContext(
            dayKey: event.localDay,
            timeZoneIdentifier: timeZone.identifier,
            utcOffsetSeconds: timeZone.secondsFromGMT(for: event.eventDate)
        )
        let provenance = WidgetUsageDayProvenance(
            startedAt: event.eventDate,
            startedContext: context,
            endedAt: event.eventDate,
            endedContext: context
        )

        for provider in ProviderID.allCases {
            if let usage = event.usage[provider] {
                await store.applyUsage(
                    usage,
                    for: provider,
                    at: event.eventDate,
                    widgetDayProvenance: provenance
                )
            } else if await store.snapshot(for: provider).usage != nil {
                await store.markUsageFailure(
                    for: provider,
                    status: .error(message: "Fixture usage unavailable.", lastSuccessfulAt: nil),
                    at: event.eventDate
                )
            }

            if let quota = event.quota[provider] {
                await store.applyQuota(quota, for: provider, at: event.eventDate)
            } else if provider != .cursor, await store.snapshot(for: provider).quota != nil {
                await store.markQuotaFailure(
                    for: provider,
                    status: .error(message: "Fixture quota unavailable.", lastSuccessfulAt: nil),
                    at: event.eventDate
                )
            }
        }
    }
}
#endif
