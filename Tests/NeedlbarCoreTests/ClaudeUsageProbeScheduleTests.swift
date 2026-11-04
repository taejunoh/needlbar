import Foundation
import Testing
@testable import NeedlbarCore

@Suite("ClaudeUsageProbeSchedule")
struct ClaudeUsageProbeScheduleTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    @Test func theFirstAutomaticRequestStartsAtOnce() {
        var schedule = ClaudeUsageProbeSchedule()
        #expect(schedule.request(.startup, now: start, inFlight: false) == .start)
    }

    @Test func automaticRunsAreAtLeastFiveMinutesApartAndARefusedChangeStaysPending() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.recordStart(at: start)
        #expect(schedule.request(.usageRecordsChanged, now: at(299), inFlight: false) == .none)
        #expect(schedule.pendingTrigger == .usageRecordsChanged)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(299), inFlight: false) == nil)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(300), inFlight: false) == .usageRecordsChanged)
        schedule.recordStart(at: at(300))
        #expect(schedule.pendingTrigger == nil)
    }

    @Test func onlyOneRunAtATime() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.recordStart(at: start)
        #expect(schedule.request(.startup, now: at(600), inFlight: true) == .none)
        #expect(schedule.pendingTrigger == .startup)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(600), inFlight: true) == nil)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(600), inFlight: false) == .startup)
    }

    @Test func manualSkipsIntervalAndBackoffButJoinsARunInFlight() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.recordStart(at: start)
        schedule.recordFailure(trigger: .startup, at: start, retriesWhenBackoffEnds: true)
        #expect(schedule.request(.manual, now: at(1), inFlight: false) == .start)
        #expect(schedule.request(.manual, now: at(1), inFlight: true) == .none)
        #expect(schedule.pendingTrigger == nil, "joining leaves nothing queued")
    }

    @Test func backoffIsFiveTenTwentyThenThirtyMinutesAndAnySuccessResetsIt() {
        var schedule = ClaudeUsageProbeSchedule()
        var clock: TimeInterval = 0
        for wait in [300.0, 600, 1_200, 1_800, 1_800] {
            schedule.recordStart(at: at(clock))
            schedule.recordFailure(trigger: .backoffRetry, at: at(clock), retriesWhenBackoffEnds: true)
            #expect(schedule.dueTrigger(resetTimes: [], now: at(clock + wait - 1), inFlight: false) == nil)
            #expect(schedule.dueTrigger(resetTimes: [], now: at(clock + wait), inFlight: false) == .backoffRetry)
            clock += wait
        }
        schedule.recordStart(at: at(clock))
        schedule.recordSuccess()
        schedule.recordFailure(trigger: .usageRecordsChanged, at: at(clock), retriesWhenBackoffEnds: true)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(clock + 300), inFlight: false) == .backoffRetry,
                "the count restarted at five minutes")
    }

    @Test func aManualFailureNeitherCountsNorClearsAutomaticBackoff() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.recordStart(at: start)
        schedule.recordFailure(trigger: .startup, at: start, retriesWhenBackoffEnds: true)
        schedule.recordStart(at: at(10))
        schedule.recordFailure(trigger: .manual, at: at(10), retriesWhenBackoffEnds: true)
        #expect(schedule.consecutiveAutomaticFailures == 1)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(299), inFlight: false) == nil)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(310), inFlight: false) == .backoffRetry)
    }

    @Test func notInstalledAndSignedOutDoNotRetryWhenBackoffEndsButRunOnTheNextTrigger() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.recordStart(at: start)
        schedule.recordFailure(trigger: .startup, at: start, retriesWhenBackoffEnds: false)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(300), inFlight: false) == nil, "backoff ended, no retry")
        #expect(schedule.dueTrigger(resetTimes: [], now: at(899), inFlight: false) == nil)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(900), inFlight: false) == .periodic,
                "the periodic run is a trigger like any other")
        #expect(schedule.request(.usageRecordsChanged, now: at(299), inFlight: false) == .none)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(300), inFlight: false) == .usageRecordsChanged)
    }

    @Test func aPassedResetIsDueOncePerRun() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.recordStart(at: start)
        let reset = at(400)
        #expect(schedule.dueTrigger(resetTimes: [reset], now: at(399), inFlight: false) == nil)
        #expect(schedule.dueTrigger(resetTimes: [reset], now: at(400), inFlight: false) == .windowReset)
        schedule.recordStart(at: at(400))
        #expect(schedule.dueTrigger(resetTimes: [reset], now: at(1_299), inFlight: false) == nil)
        #expect(schedule.dueTrigger(resetTimes: [reset], now: at(9_000), inFlight: false) != .windowReset,
                "a run that started at or after the reset has covered it, whatever it returned")
    }

    @Test func aResetInsideTheIntervalWaitsForTheInterval() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.recordStart(at: start)
        #expect(schedule.dueTrigger(resetTimes: [at(100)], now: at(200), inFlight: false) == nil)
        #expect(schedule.dueTrigger(resetTimes: [at(100)], now: at(300), inFlight: false) == .windowReset)
    }

    @Test func aClockSetBackwardsDoesNotBlockAutomaticRuns() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.recordStart(at: start)
        schedule.recordFailure(trigger: .startup, at: start, retriesWhenBackoffEnds: true)
        #expect(schedule.request(.usageRecordsChanged, now: at(-86_400), inFlight: false) == .start)
    }

    // MARK: - Periodic

    @Test func aQuietScheduleIsDueEveryFifteenMinutes() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.recordStart(at: start)
        schedule.recordSuccess()
        #expect(schedule.dueTrigger(resetTimes: [], now: at(899), inFlight: false) == nil)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(900), inFlight: false) == .periodic)
        schedule.recordStart(at: at(900))
        schedule.recordSuccess()
        #expect(schedule.dueTrigger(resetTimes: [], now: at(1_799), inFlight: false) == nil)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(1_800), inFlight: false) == .periodic)
    }

    @Test func thereIsNoPeriodicRunBeforeTheFirstRun() {
        let schedule = ClaudeUsageProbeSchedule()
        #expect(schedule.dueTrigger(resetTimes: [], now: at(86_400), inFlight: false) == nil)
    }

    @Test func thePeriodicRunComesLastInPriority() {
        var pending = ClaudeUsageProbeSchedule()
        pending.recordStart(at: start)
        _ = pending.request(.usageRecordsChanged, now: at(1), inFlight: false)
        #expect(pending.dueTrigger(resetTimes: [], now: at(900), inFlight: false) == .usageRecordsChanged)

        var reset = ClaudeUsageProbeSchedule()
        reset.recordStart(at: start)
        #expect(reset.dueTrigger(resetTimes: [at(500)], now: at(900), inFlight: false) == .windowReset)

        var retry = ClaudeUsageProbeSchedule()
        retry.recordStart(at: start)
        retry.recordFailure(trigger: .startup, at: start, retriesWhenBackoffEnds: true)
        #expect(retry.dueTrigger(resetTimes: [], now: at(900), inFlight: false) == .backoffRetry)
    }

    @Test func thePeriodicRunStaysBehindBackoffAndASingleRun() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.recordStart(at: start)
        for _ in 0 ..< 3 {
            schedule.recordFailure(trigger: .startup, at: start, retriesWhenBackoffEnds: false)
        }
        #expect(schedule.dueTrigger(resetTimes: [], now: at(900), inFlight: false) == nil, "twenty minutes of backoff")
        #expect(schedule.dueTrigger(resetTimes: [], now: at(1_199), inFlight: false) == nil)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(1_200), inFlight: false) == .periodic)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(1_200), inFlight: true) == nil)
    }

    @Test func aClockSetBackwardsNeverMakesThePeriodicRunDue() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.recordStart(at: start)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(-1), inFlight: false) == nil)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(-86_400), inFlight: false) == nil)
    }
}
