# Claude Refresh Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make retained Claude quota age honestly, recover overdue refreshes after wake/connectivity recovery, and expose safe local evidence of actual refresh progress.

**Architecture:** Keep the existing aggregate quota repository, direct/bridge separation, and physical single-flight coordinator. Add one shared per-window freshness projection, generation-fenced recovery inputs, and host-local typed liveness reporting. Reproject cached UI state on a view-local clock without fetching quota.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI/AppKit, Foundation, Network/NWPathMonitor, existing Rust C bridge unchanged; deployment target macOS 14.

---

## Approval, scope, and execution baseline

The user approved the written design on October 7 (`승인`). Read
`docs/superpowers/specs/2026-10-07-claude-refresh-reliability-design.md` in full,
then the approved September 15 passive-recovery and September 25 bridge designs.
This plan implements only the first reliability increment. Compact quota UI
(Phase 2) and cost/quota workflow (Phase 3) need their own plans.

Use the attached checkout on `codex/claude-refresh-reliability`. At planning
time `docs/STATUS.md` is dirty and the competitor research file is untracked.
Preserve both. Do not stage either file in the implementation commits below;
the orchestrator updates STATUS separately after reviewing each completed task.
Do not run the installed app, provider auth commands, live quota calls, or a
Claude model request as a test. No installation, release, or publication here.

Run commands with the existing PATH preserved:

```bash
env PATH=/Users/taejunoh/.cargo/bin:"$PATH" MACOSX_DEPLOYMENT_TARGET=14.0 make swift-test SWIFT_TEST_FILTER=ClaudeQuotaPresentationSelectorTests
env PATH=/Users/taejunoh/.cargo/bin:"$PATH" MACOSX_DEPLOYMENT_TARGET=14.0 make test
git diff --check
```

`make swift-test` builds the fixture bridge, runs Swift tests, restores the
production archive, and cleans Swift products. Use its filter argument rather
than calling a production-linked test executable that might access credentials.
Run the complete `make test` before completing **each** numbered task. Expected
GREEN means the command exits 0 and the intended tests actually ran, with no
missing-tool/skipped-contract messages. Existing test-process `kill: ... No such
process` output and the existing `MacSystemMetricsCollector.swift` local-variable
warning are not new feature failures. Do not change the toolchain or deployment
target to silence warnings.

## Global constraints — approved contract

The following requirements are copied from the approved specification and apply
to every task, including tests, diagnostics, and legacy presentation paths.

For each Claude quota window, evaluate the direct observation and the
status-line observation independently against the injected current time. A
direct observation is current only when all of the following are true:

- The direct quota stream's current status is valid and fresh.
- Its actual last-success timestamp exists, is finite, is not in the future,
  and is less than 15 minutes old (`now >= timestamp` and
  `now - timestamp < 15 minutes`). Missing and future timestamps are not fresh.
- If a reset timestamp exists, it is later than now; a reset at or before now makes the
  observation last-known. Without one, the remaining value may be fresh while
  its reset label says `Reset unavailable`.

Keep the actual last-success timestamp when refresh fails; never replace it
with the attempt time. Apply the same age, future-time, and passed-reset checks
to direct Fable using its own timestamp and reset. Fable remains independently
fresh, stale, or unavailable; status-line data cannot refresh or timestamp it.

Preserve bridge semantics: only a valid active-generation record is eligible;
identical observations do not extend recency; its 15-minute recency and reset
rules remain unchanged. Receipt time is local, not proof of a provider fetch
or server observation.

Select a value for each window in this order:

1. A current direct observation.
2. A current status-line observation.
3. The most recently observed valid last-known observation from either source.

For equal observation times, prefer direct quota. A valid retained value without
a usable timestamp remains displayable as last-known but ranks behind values
with finite timestamps not later than now. Missing, non-finite, and future times
are unusable for both freshness and ranking. If both retained values lack usable
times, prefer direct quota without inventing or displaying an unusable time.
If neither source has a valid value, show unavailable without a percentage,
zero, timestamp, or reset.

Use this policy in the dashboard, provider popover, and Settings. Re-evaluate
age/reset boundaries while a surface remains open without a provider request.

On app start, system wake, and offline-to-online transition, read the local
status-line cache and apply it only if schema, active generation, and window
values validate. This neither launches Claude Code nor makes a provider
request. Wake and connectivity recovery may request one direct quota catch-up
only after five minutes since the actual prior background quota attempt.
Startup retains the existing initial-refresh policy; recovery events must not
duplicate it before any prior attempt exists. Preserve the normal five-minute
cadence and existing quota refresh boundary, without a separate Claude-only
request pipeline.

Coalesce wake/connectivity/popover triggers to one in-flight direct request and
at most one pending catch-up. Clear or reconcile pending work on stop; restart
begins a new generation. Recheck recovery eligibility when pending work drains:
a newer attempt can make queued recovery unnecessary. Coincident periodic and
recovery requests must share one attempt instead of running back-to-back.
Preserve physical single-flight across stop/restart; fencing a result does not
prove its synchronous call was cancelled. Remove lifecycle observers on stop
and register them at most once on start. Ignore results and bridge reads from
old run or connection generations. Add no faster retry, sign-in prompt, model request, or
Claude authentication/configuration write.

Freshness is not a request timeout. Synchronous Keychain access has no
established deadline. Do not claim to bound HTTP/Keychain duration, fix a hung
Security call, or guarantee unattended renewal. Deadline-bounded credential
lookup requires a separate design, including credential and process-isolation
implications.

Make in-progress quota attempts inspectable in local diagnostics. Emit an
attempt-start immediately before the repository call, with an allowlisted
trigger (`startup`, `scheduled`, `wake`, `connectivity`, `popover`, `manual`)
and local attempt timestamp. Emit completion only after applying a result from
the current generation; a stopped/superseded generation cannot report success.

Keep attempt start, direct-success time, failure-attempt time, and status-line
receipt time distinct. Completion reports only safe outcome and source; it
does not imply browser authentication. Log no raw errors, tokens, paths,
payloads, commands, or account identifiers. Diagnostics are local, not network
telemetry.

If synchronous Keychain lookup never returns, keep the local in-progress state
visible until stop or supersession. Do not fabricate a timeout or completion.

- `NeedlbarCore` owns per-window source selection/freshness and distinct direct
  success and status-line receipt timestamps.
- `RefreshCoordinator` owns coalescing, actual-attempt timing, single-flight
  execution, and run-generation fencing; periodic scheduling keeps the cadence.
- App lifecycle/connectivity signals start, wake, and offline-to-online events.
  Local cache reads remain separate from provider requests.
- Host-local diagnostics expose only allowlisted liveness fields and safe
  outcomes, without extending the Rust C-ABI/JSON diagnostics schema. UI uses
  shared Claude presentation policy, not separate source selection.
- No presentation logic moves to Rust; no provider or authentication component
  is added.

## Existing APIs and deliberate compatibility decisions

- `ProviderSnapshot` already accepts `quotaLastSuccessfulAt: Date?` and
  `claudeStatusLineQuota`. Do not change the persisted quota/bridge schema.
- `DisplayedClaudeWindow.observedAt` and `ClaudePopoverQuotaDetail.observedAt`
  currently require a Date; change these presentation-only properties to
  `Date?`. An optional is required to avoid inventing a successful observation.
- The direct limit is strictly `< 900` seconds. Preserve the bridge's existing
  `<= recentStatusLineInterval` boundary; the specification explicitly preserves
  its current recency rules. Test the two boundaries separately.
- Existing popover admission is 60 seconds since the last successful aggregate
  refresh, or another attempt when no success exists. Preserve those tests and
  explicit manual refresh behavior. The new five-minute gate is for automatic
  recovery, not a blanket throttle on user actions.
- Keep existing `queuedBackgroundTicket`/ahead/after waiter ordering and
  `claudeQuotaOperationCompleted` semantics. Add request metadata to that queue;
  do not replace it with a second request pipeline.
- Keychain expiry observed on October 7 is a **completed credential failure**,
  not evidence of a dead scheduler. A started-but-unfinished attempt must remain
  a distinct local diagnostic state.

## Task 1: Share source-aware freshness across existing Claude presentations

**Ownership:**

- Modify `Sources/NeedlbarCore/Presentation/ClaudeQuotaPresentationSelector.swift`.
- Modify `Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift`.
- Modify `Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift`.
- Modify `Tests/NeedlbarCoreTests/ClaudeQuotaPresentationSelectorTests.swift`.
- Modify `Tests/NeedlbarTests/ClaudeStatusLineFallbackIntegrationTests.swift`.
- Add `Tests/NeedlbarTests/ClaudeQuotaFreshnessPresentationTests.swift`.

- [ ] **Write executable RED tests using the current snapshot/selector API.**

Add this test inside the existing selector suite, which already imports
Foundation, Testing, NeedlbarCore and status-line support:

```swift
@Test(arguments: [899.0, 900.0, 901.0])
func directObservationExpiresAtStrictFifteenMinuteBoundary(age: Double) throws {
    let success = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshot = ProviderSnapshot(
        provider: .claude, usage: nil,
        quota: .init(windows: [try QuotaWindow(
            id: "claude.session", title: "Session", usedPercent: 25,
            resetsAt: success.addingTimeInterval(3_600))]),
        usageStatus: .unavailable, quotaStatus: .fresh,
        updatedAt: success.addingTimeInterval(age), quotaLastSuccessfulAt: success)
    let selected = ClaudeQuotaPresentationSelector.select(
        snapshot: snapshot, now: success.addingTimeInterval(age))
    #expect(selected.fiveHour?.remainingPercent == 75)
    #expect(selected.fiveHour?.isLastKnown == (age >= 900))
}

@Test func missingSuccessNeverUsesUpdatedAtAsObservationTime() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshot = ProviderSnapshot(
        provider: .claude, usage: nil,
        quota: .init(windows: [try QuotaWindow(
            id: "claude.session", title: "Session", usedPercent: 25, resetsAt: nil)]),
        usageStatus: .unavailable, quotaStatus: .fresh, updatedAt: now)
    let selected = ClaudeQuotaPresentationSelector.select(snapshot: snapshot, now: now)
    #expect(selected.fiveHour?.isLastKnown == true)
    #expect(selected.fiveHour?.observedAt == nil)
}
```

Run:

```bash
env PATH=/Users/taejunoh/.cargo/bin:"$PATH" MACOSX_DEPLOYMENT_TARGET=14.0 make swift-test SWIFT_TEST_FILTER=ClaudeQuotaPresentationSelectorTests
```

Expected RED: the 900/901-second examples remain fresh and the missing-time
example substitutes `updatedAt`. Do not accept a build/link failure as this RED.

- [ ] **Implement one reusable direct projection and optional observation time.**

Keep `select(snapshot:now:)` and its known-window IDs. Make `directWindow`
public so unknown/legacy direct windows use precisely the same policy. Use this
implementation, and update the presentation struct initializer to `Date?`:

```swift
public static let recentDirectInterval: TimeInterval = 15 * 60

private static func usableTime(_ date: Date?, now: Date) -> Date? {
    guard now.timeIntervalSince1970.isFinite, let date,
          date.timeIntervalSince1970.isFinite, date <= now else { return nil }
    return date
}

public static func directWindow(
    _ window: QuotaWindow, snapshot: ProviderSnapshot, now: Date
) -> DisplayedClaudeWindow {
    let observed = usableTime(snapshot.quotaLastSuccessfulAt, now: now)
    let recent = observed.map { now.timeIntervalSince($0) < recentDirectInterval } ?? false
    let resetValid = window.resetsAt.map {
        $0.timeIntervalSince1970.isFinite && $0 > now
    } ?? true
    return DisplayedClaudeWindow(
        remainingPercent: window.remainingPercent, source: .direct,
        observedAt: observed,
        resetsAt: window.resetsAt.flatMap { $0.timeIntervalSince1970.isFinite ? $0 : nil },
        isLastKnown: snapshot.quotaStatus != .fresh || !recent || !resetValid)
}
```

For bridge projection retain percent validation, normalize the display time
through `usableTime`, and retain the value as last-known if time is unusable.
Reject an invalid percentage; never turn it into zero. Preserve the existing
finite-reset validation at the bridge boundary. Use the original non-nil reset
for freshness tests before normalizing display metadata. Retain the existing
`age <= recentStatusLineInterval` comparison.

Replace the stale-source ranking switch with:

```swift
switch (directDisplay, statusDisplay) {
case let (.some(direct), .some(bridge)):
    switch (direct.observedAt, bridge.observedAt) {
    case let (.some(a), .some(b)): return a >= b ? direct : bridge
    case (.some, nil): return direct
    case (nil, .some): return bridge
    case (nil, nil): return direct
    }
case let (.some(direct), nil): return direct
case let (nil, .some(bridge)): return bridge
case (nil, nil): return nil
}
```

- [ ] **Make all consumers use that projection, including fallback windows.**

In `ProviderPopoverPresentation`, replace direct fallback construction with
`ClaudeQuotaPresentationSelector.directWindow(window, snapshot: snapshot, now: now)`.
Derive `directFallback` from projected `!isLastKnown`, never raw `.fresh`.
For timestamp strings use optional chaining instead of fallback to `updatedAt`:

```swift
quotaLastCheckedText = primary?.observedAt.map(Self.localizedDateTime)
fableLastCheckedText = selected.fable.flatMap { window in
    window.isLastKnown ? window.observedAt.map(Self.localizedDateTime) : nil
}
```

For a legacy main window, select `primary` from the projected legacy details
when known main windows are absent, so it receives the same source/time policy.
Change `ClaudePopoverQuotaDetail.observedAt` to `Date?`; its view renders the
observation text only inside `if let observedAt = detail.observedAt`.
For a current window without a reset, set `resetCaption = "Reset unavailable"`;
for last-known use no live countdown. Change Fable's date formatting in
`SystemDashboardPresentation.fableDetail` to `window.observedAt.map`.
Derive Claude's `quotaFreshness` from the projected main values: `.fresh` if
there is a current main value; `.stale` when only retained values exist and the
underlying stream is `.fresh`; otherwise preserve the existing failure status.
This prevents `freshnessSummary` saying Fresh beside a Last known percentage.

- [ ] **Add the full deterministic matrix before declaring GREEN.**

Use `ProviderSnapshot(...)`, `StatusLineQuotaRecord(...)`, and
`StatusLineWindowObservation(...)` already used in the selector suite. Add
parameterized cases for nil/NaN/infinite/future/equal-now success times;
reset nil/before/equal/after now; `.fresh`, `.stale`, and failed streams;
direct versus bridge time ties; one usable timestamp versus none; neither
usable timestamp; neither value present; bridge invalid percentage; direct
last-known versus recent bridge; and bridge 899/900/901-second recency.
Add Fable with reset already passed while the main direct reset is still ahead,
and Fable last-known under fresh bridge main values. Do not invent per-window
direct timestamps: the existing direct snapshot supplies its actual success
time to its own windows, never the bridge receipt time.

In the new host test file import Testing, Foundation, `@testable NeedlbarApp`,
and NeedlbarCore. Construct one `CombinedUsageSnapshot(system:nil, providers:
[snapshot], capturedAt:now, systemAvailability:[:])`; compare
`ProviderPopoverPresentation(snapshot:now:)`,
`SystemDashboardPresentation(snapshot:configuration:now:)`, and
`SettingsClaudeQuotaPresentation(snapshot:now:)` on the MainActor. Cover the
unknown ID `claude.legacy` with missing success time: retained 75%, Last known,
no timestamp and no live reset, consistently. Assert missing reset copy and
zero `requiresProviderSignIn` for Claude. The existing fallback integration
test must still preserve Fable, direct failure reason, and last direct success.

- [ ] **Keep existing fresh fixtures explicit, then verify and commit owned changes.**

The strict success-time contract takes effect in this task, so existing host
tests that intentionally assert fresh Claude data may need fixture correction
now rather than waiting for Task 4. Update only their synthetic construction to
provide the actual intended success time and inject the corresponding `now`
where needed. Preserve assertions and failure-state fixtures. Report every
additional test path and stage it explicitly after diff review; no production
rule relaxation or entire-directory staging is allowed.

```bash
env PATH=/Users/taejunoh/.cargo/bin:"$PATH" MACOSX_DEPLOYMENT_TARGET=14.0 make swift-test SWIFT_TEST_FILTER='ClaudeQuotaPresentationSelectorTests|ClaudeQuotaFreshnessPresentationTests|ClaudeStatusLineFallbackIntegrationTests'
env PATH=/Users/taejunoh/.cargo/bin:"$PATH" MACOSX_DEPLOYMENT_TARGET=14.0 make test
git diff --check
git add Sources/NeedlbarCore/Presentation/ClaudeQuotaPresentationSelector.swift Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift Tests/NeedlbarCoreTests/ClaudeQuotaPresentationSelectorTests.swift Tests/NeedlbarTests/ClaudeStatusLineFallbackIntegrationTests.swift Tests/NeedlbarTests/ClaudeQuotaFreshnessPresentationTests.swift
git commit -m "fix: apply source-aware Claude quota freshness"
```

## Task 2: Coalesce generation-fenced automatic recovery with existing refreshes

**Ownership:**

- Modify `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`.
- Add `Sources/NeedlbarCore/Refresh/QuotaRefreshActivity.swift`.
- Modify `Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift`.

- [ ] **Add typed request metadata and compile-only RED scaffolding.**

Define `QuotaRefreshTrigger: String, Sendable, Equatable` with exactly
`startup`, `scheduled`, `wake`, `connectivity`, `popover`, `manual`.
Write the behavioral tests below first. If the new API does not compile yet,
add only the following minimal no-op scaffolding to run those already-written
tests; a missing symbol is not sufficient behavioral RED verification:

```swift
public func recoveryRequestToken() -> QuotaRecoveryRequestToken {
    let generation = runGeneration
    return QuotaRecoveryRequestToken { [weak self] trigger in
        await self?.recoverQuota(trigger: trigger, generation: generation)
    }
}

private func recoverQuota(trigger: QuotaRefreshTrigger, generation: UInt64) {}
```

Define `QuotaRecoveryRequestToken` in the new file. Its complete interface is:

```swift
public struct QuotaRecoveryRequestToken: Sendable {
    private let action: @Sendable (QuotaRefreshTrigger) async -> Void
    public init(_ action: @escaping @Sendable (QuotaRefreshTrigger) async -> Void) {
        self.action = action
    }
    public func submit(_ trigger: QuotaRefreshTrigger) async {
        guard trigger == .wake || trigger == .connectivity else { return }
        await action(trigger)
    }
}
```

- [ ] **Write RED recovery tests inside the existing serialized coordinator suite.**

Reuse its private `ManualClock`, `BlockingIntentQuotaRepository`,
`UsageRefreshSpy`, `StatusLineCacheSpy`, `eventuallyAsync`, and `quotaResult`.
Do not copy private helpers into a different file or reference nonexistent APIs.
Add `ManualClock.setNowWithoutWakingSleepers(_:)` using its existing lock/date:
`lock.withLock { date = value }`. This separates a recovery event from a timer.

```swift
@Test func wakeReadsCacheImmediatelyButOnlyFetchesAtFiveMinutes() async throws {
    let now = Date(timeIntervalSince1970: 0)
    let clock = ManualClock(now: now)
    let quota = BlockingIntentQuotaRepository()
    let generation = UUID()
    let cache = StatusLineCacheSpy(generation: generation, record: .init(
        schemaVersion: 1, generation: generation, fiveHour: nil, sevenDay: nil))
    let coordinator = RefreshCoordinator(
        usageRepository: UsageRefreshSpy(result: .init(snapshots: [:], errors: [:])),
        quotaRepository: quota, store: ProviderSnapshotStore(), clock: clock,
        statusLineRepository: cache)
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: quotaResult(for: .claude))
    let token = await coordinator.recoveryRequestToken()
    await eventually { cache.readCount == 1 }
    clock.setNowWithoutWakingSleepers(now.addingTimeInterval(299))
    await token.submit(.wake)
    await eventually { cache.readCount == 2 }
    #expect(cache.readCount == 2)
    #expect(quota.callCount == 1)
    clock.setNowWithoutWakingSleepers(now.addingTimeInterval(300))
    await token.submit(.connectivity)
    await eventually { quota.callCount == 2 }
    #expect(quota.callCount == 2)
    if quota.callCount == 2 { try quota.releaseNext(with: quotaResult(for: .claude)) }
    await coordinator.stop()
}
```

Run the suite with `make swift-test SWIFT_TEST_FILTER=RefreshCoordinatorTests`
and the common environment. Expected RED is missing cache read/catch-up after
the no-op recovery body, not a hanging test. New negative assertions use bounded
`eventually` plus an explicit `#expect`; do not await an impossible call forever.

- [ ] **Record actual background starts in a small synchronous, locked object.**

Define `BackgroundQuotaAttemptClock` in the new file; it stores `Date?`, never
a numeric sentinel (epoch zero above is legitimate). It remains allocated for
the coordinator's lifetime and is not cleared by stop/restart:

```swift
final class BackgroundQuotaAttemptClock: @unchecked Sendable {
    private let lock = NSLock()
    private var lastStartedAt: Date?
    func record(_ date: Date) { lock.withLock { lastStartedAt = date } }
    var latest: Date? { lock.withLock { lastStartedAt } }
}
```

Capture it and `clock` in `beginQuotaRefresh`'s task; immediately before the
synchronous `repository.refresh(intent:)`, record `clock.now` only for
`.backgroundAll`. Keep `quotaTask` reserved from admission through actual
repository return and store application. Do not replace the call with an
unbounded number of detached operations or clear its handle on stop.

- [ ] **Admit and drain recovery through the existing queue.**

Add `trigger: QuotaRefreshTrigger` to the private `requestQuotaRefresh` and
`beginQuotaRefresh` APIs. Call sites: start→startup, safety loop→scheduled,
popover→popover, manualRefresh→manual; dedicated user/preflight operations use
manual for observation only and keep their existing `QuotaRefreshIntent`.
Keep the previous popover threshold and its no-success behavior.

Store one `pendingBackgroundTrigger: QuotaRefreshTrigger?` alongside the
existing background ticket. Preserve the first forced trigger (`startup`,
`manual`, `popover`); a forced request upgrades pending automatic recovery
without creating a second ticket or moving user waiters. Recovery sources
coalesce first-wins. The existing queue's ahead/after provider sets are retained.

```swift
private func recoveryIsDue() -> Bool {
    guard let last = backgroundAttemptClock.latest else { return false }
    let age = clock.now.timeIntervalSince(last)
    return age.isFinite && age >= 300
}

private func recoverQuota(trigger: QuotaRefreshTrigger, generation: UInt64) {
    guard isRunning, generation == runGeneration else { return }
    requestStatusLineRead()
    guard recoveryIsDue() else { return }
    requestQuotaRefresh(trigger: trigger, generation: generation)
}
```

For periodic/recovery collision, retain the timer's fixed five-minute loop and
attach the timer slot's `dueAt` to a scheduled request. Capture it as
`clock.now.addingTimeInterval(300)` immediately before sleeping. A periodic
request is satisfied if a background attempt already started at or after its
`dueAt`; skip its network part but still read the local cache. Conversely a
pending wake/connectivity request is dropped if `recoveryIsDue()` is false at
drain. This handles either ordering at the same boundary without introducing a
global five-minute throttle on manual/popover calls. Carry the scheduled due
time with the queued trigger and clear it when a forced request replaces it.
Use optional Dates, not `0` or `.distantPast`, for absent request times.

At the existing background-ticket drain point, move the after-background user
set into the regular queue exactly as today, clear the ticket/metadata, then
recheck its eligibility. If no request remains necessary, continue draining
user requests instead of returning early or leaving their continuations stuck.
When an automatic request arrives during a current-generation background
attempt that started after the request's due boundary, that physical attempt
already fulfills it; do not queue a follow-up. Forced requests retain today's
one-follow-up behavior.

- [ ] **Preserve local read and stop/restart fencing under overlap.**

Add a generation-bound `statusLineReadRequestedWhileInFlight` flag. If a
recovery requests a cache read while one is active, remember one follow-up.
`finishStatusLineRead` clears its task and starts one follow-up only when the
same run is still active. Stop clears the flag. Preserve active connection
generation validation inside `ProviderSnapshotStore` and the existing
`statusLineApplicationWillApply` test gate. A stopped generation cannot apply
or clear a newer generation's read task.

`stop()` still cancels but retains `quotaTask` until the synchronous call
returns. Restart queues the normal startup request behind that physical call.
Old completion skips state/diagnostics application but its existing defer must
release the physical slot and drain current-generation work. Never reset the
actual-start clock merely because the run generation changes.

- [ ] **Add deterministic race tests using the same fixture APIs.**

| Test | Controlled sequence and required observation |
| --- | --- |
| Epoch-zero attempt | Test above: `Date(0)` is a real prior attempt; 299 skips, 300 admits. |
| Fresh popover attempt | Start at 0, complete, explicit popover at 100, complete; wake 399 skips and 400 admits. |
| Before startup starts | Recovery token submitted before `start` and immediately after start never adds a second initial fetch. |
| In-flight burst | Block initial call at 0; set clock 300; submit wake/connectivity/popover repeatedly; release; exactly one aggregate follow-up, no overlapping physical calls. |
| Pending reevaluation | Hold completion application with `QuotaApplicationGate`; queue recovery and a forced aggregate; after its actual start the queued recovery adds no extra attempt. |
| Periodic first | Wake sleepers at 300, wait for second call to register, then submit wake/connectivity; release; no third call. |
| Recovery first | Set date to 300 without waking sleepers, submit wake, wait for second registration; `advance(by: 0)` releases periodic sleeper; no third call. |
| Stop/restart | Block first call, retain old token, stop/start, submit old token; only one physical call until released; startup then runs once and old result is absent. |
| Cache overlap | Pause old cache apply, submit recovery, replace active connection generation, release; only active record applies and one follow-up reads it. |

Retain the existing tests for 60-second popover admission, retry after failure,
5-minute safety cadence, finite user-waiter batching, cancellation fencing, and
Claude completion callback ordering. Only new metadata accompanies those
contracts. Release all blocked fixture calls even after an assertion fails;
`forbidAdditionalCalls()` records accidental extra work without leaking a waiter.

- [ ] **Verify and commit.**

```bash
env PATH=/Users/taejunoh/.cargo/bin:"$PATH" MACOSX_DEPLOYMENT_TARGET=14.0 make swift-test SWIFT_TEST_FILTER=RefreshCoordinatorTests
env PATH=/Users/taejunoh/.cargo/bin:"$PATH" MACOSX_DEPLOYMENT_TARGET=14.0 make test
git diff --check
git add Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift Sources/NeedlbarCore/Refresh/QuotaRefreshActivity.swift Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift
git commit -m "fix: coalesce Claude quota lifecycle recovery"
```

## Task 3: Wire lifecycle signals and safe observable attempt evidence

**Ownership:**

- Modify `Sources/NeedlbarCore/Refresh/QuotaRefreshActivity.swift` and `RefreshCoordinator.swift`.
- Add `Sources/Needlbar/App/QuotaRecoveryMonitor.swift`.
- Add `Sources/Needlbar/Diagnostics/QuotaRefreshDiagnosticsReporter.swift`.
- Modify `Sources/Needlbar/App/AppDelegate.swift`.
- Add `Tests/NeedlbarTests/QuotaRecoveryMonitorTests.swift` and `QuotaRefreshDiagnosticsReporterTests.swift`.
- Modify `Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift` and `Tests/NeedlbarTests/AppDelegateLifecycleTests.swift`.

- [ ] **Define the injected host boundary; write tests against no-op scaffolding.**

`QuotaRecoveryMonitoring` is a MainActor protocol with `start(using:
QuotaRecoveryRequestToken)` and `stop()`. The production implementation receives
an injected wake `NotificationCenter` and an injected path-monitor factory.
Define the small path adapter protocol, backed in production by a fresh
`NWPathMonitor` per start (a cancelled monitor is not reusable):

```swift
@MainActor protocol QuotaPathMonitoring: AnyObject {
    func start(_ receive: @escaping @MainActor @Sendable (Bool) -> Void)
    func cancel()
}

@MainActor protocol QuotaRecoveryMonitoring: AnyObject {
    func start(using token: QuotaRecoveryRequestToken)
    func stop()
}
```

`QuotaRecoveryMonitor.init(center:makePath:)` defaults to
`NSWorkspace.shared.notificationCenter` and the NWPath adapter. Test with a
fresh `NotificationCenter()` and this complete fake; never start NWPathMonitor
or toggle real networking in tests:

```swift
@MainActor final class FakeQuotaPath: QuotaPathMonitoring {
    var receive: (@MainActor @Sendable (Bool) -> Void)?
    var starts = 0
    var cancels = 0
    func start(_ receive: @escaping @MainActor @Sendable (Bool) -> Void) {
        starts += 1
        self.receive = receive
    }
    func cancel() { cancels += 1 }
}

@Test @MainActor func pathRequiresObservedOfflineToOnlineTransition() async {
    let center = NotificationCenter()
    let path = FakeQuotaPath()
    let monitor = QuotaRecoveryMonitor(center: center, makePath: { path })
    let received = RecoveryTriggerRecorder()
    monitor.start(using: QuotaRecoveryRequestToken { await received.append($0) })
    path.receive?(true)
    path.receive?(true)
    await Task.yield()
    #expect(await received.values.isEmpty)
    path.receive?(false)
    path.receive?(true)
    for _ in 0..<100 where await received.values.isEmpty { await Task.yield() }
    #expect(await received.values == [.connectivity])
    monitor.stop()
    #expect(path.cancels == 1)
}

private actor RecoveryTriggerRecorder {
    var values: [QuotaRefreshTrigger] = []
    func append(_ value: QuotaRefreshTrigger) { values.append(value) }
}
```

Expected RED with a compiling no-op monitor: the one connectivity trigger and
cancel count are absent. Also test duplicate start, wake notification,
post-stop saved path callback, restart with a new fake, and old wake delivery.

- [ ] **Implement observer registration with two levels of generation fencing.**

Store one notification token, one path monitor, `lastSatisfied: Bool?`, and a
host generation counter. `start` is idempotent; `stop` increments generation,
removes the observer, cancels/releases the path monitor, and resets path state.
The notification closure hops to MainActor, verifies host generation, then
submits `.wake` using the captured Core token. The path callback only submits
`.connectivity` for `lastSatisfied == false && satisfied`; an initial satisfied
sample is not a recovery event. Capture host generation in both callbacks and
the Core token in every submitted Task so stop/restart rejects delayed work.

The Network adapter uses `monitor.pathUpdateHandler = { path in let satisfied =
path.status == .satisfied; Task { @MainActor in receive(satisfied) } }` and
`monitor.start(queue: DispatchQueue(label: "com.taejunoh.needlbar.quota-path"))`.
This observes reachability only; do not treat `.satisfied` as endpoint success.

In `AppDelegate` create the monitor only for `.production`. After
`await refreshCoordinator.start()`, obtain `recoveryRequestToken()` and start
the monitor. Stop the monitor before `await refreshCoordinator.stop()` in both
normal production teardown and the accepted-termination refresh-cleanup closure.
Do not stop it early during a termination attempt that can be denied by login
cleanup, unless the denial path restarts it. Keep acceptance-driver startup
free of network monitors. Extend the existing lifecycle fakes to verify order
and idempotence without constructing a production AppDelegate/provider bridge.

- [ ] **Define the closed local event schema and reporter before instrumentation.**

Put public Sendable/Equatable value types in `QuotaRefreshActivity.swift`:

```swift
public enum QuotaAttemptPhase: String, Sendable { case started, completed, invalidated }
public enum QuotaAttemptOutcome: String, Sendable { case success, failure, unavailable }
public enum QuotaObservationSource: String, Sendable { case direct, statusLine, unavailable }
public struct QuotaAttemptEvent: Sendable, Equatable {
    public let id: UUID
    public let generation: UInt64
    public let trigger: QuotaRefreshTrigger
    public let phase: QuotaAttemptPhase
    public let startedAt: Date
    public let completedAt: Date?
    public let outcome: QuotaAttemptOutcome?
    public let directLastSuccessfulAt: Date?
    public let failureAttemptAt: Date?
    public let fiveHourSource: QuotaObservationSource
    public let sevenDaySource: QuotaObservationSource
    public let fableSource: QuotaObservationSource
    public let fiveHourReceiptAt: Date?
    public let sevenDayReceiptAt: Date?
}
```

Add an explicit public initializer accepting these fields so the host test
target can build synthetic events. No arbitrary String/error/path/payload field
is permitted. `QuotaRefreshDiagnosticsReporter` owns an NSLock-protected latest
event and an injected `@Sendable (QuotaAttemptEvent) -> Void` sink, defaulting
to a bounded OSLog call. Its `record(_:)` updates state synchronously; its
`latestEvent()` is synchronous and callable without entering the coordinator
actor. Thus a blocked repository cannot prevent reading in-progress evidence.
Log only enum raw values and ISO8601 finite timestamps. IDs/generation are
in-memory correlation, not account/session identifiers; do not log UUIDs.

Test `record(started)` exposes an in-progress latest event without completion;
`record(invalidated)` is distinct from success or timeout; safe completed
failure preserves an older direct success and separate bridge receipts. Use
the injected sink to assert exact fields and absence of canary raw error text.
Retain the existing `ClaudeQuotaFailureDiagnosticsReporter` and all its tests
unchanged: it still supplies the narrower allowlisted credential-origin detail.

- [ ] **Instrument the real boundary and project results safely.**

Add an optional synchronous `@Sendable (QuotaAttemptEvent) -> Void` observer to
both coordinator initializers, default nil, and wire `reporter.record` from
AppDelegate. Generate the attempt ID once when admitting a physical call;
immediately before `repository.refresh`, capture `clock.now`, update the
background-start clock for `.backgroundAll`, and emit `.started`. No await or
provider call belongs between start emission and the repository call.
Use `.manual` for the existing explicitly invoked dedicated/preflight intents;
do not add auth actions. Keep the last known direct success/bridge receipts in
the reporter when merging a start event; starting a request is not data loss.

After existing store application and the existing Claude completion callback,
recheck `generation == runGeneration`, `isRunning`, and cancellation. Read the
Claude snapshot and project source fields through the Task 1 selector. Record
the original attempt start, current completion time, actual direct success
time, and bridge receipts separately. Use the following outcome mapping:

| Current operation result | Completion outcome | Failure time |
| --- | --- | --- |
| Claude snapshot present, no Claude error | success | nil |
| Claude BridgeError or thrown call that includes Claude | failure | original attempt start |
| No Claude snapshot/error in a Claude-including result | unavailable | original attempt start |
| Codex-only dedicated operation | its own safe success/failure; Claude source projection unchanged | no new Claude failure |

Never infer success from retained `snapshot.quota`, a recent bridge window,
`loggedIn`, or elapsed time. Map unknown thrown errors to `.failure` without
`String(describing:)`. At stop invalidate the active event once, keep its start
timestamp for inspection, and do not emit a completion when its old call later
returns. Synchronize event generation/invalidation with a small locked ledger
shared with the worker closure: a late task that has not started must fail a
generation claim before calling the repository; an already claimed physical
call remains reserved until return. This is fencing, not cancellation of FFI.

- [ ] **Exercise result/generation boundaries with existing blocking fixtures.**

Extend the coordinator suite with an NSLock-backed event collector and these
assertions: `.started` exists while `BlockingIntentQuotaRepository` is blocked;
no completion before `QuotaApplicationGate` resumes; stop while blocked produces
invalidation but no later success; restart's next attempt has a new ID and
generation; failed `authenticationExpired` preserves old success; later success
replaces it; status-line-only read produces no direct attempt/success; a
raw-message canary never enters event fields. Preserve the existing completion
callback ordering test and prove diagnostics read only the local reporter,
with zero repository/auth/config actions.

- [ ] **Verify and commit.**

```bash
env PATH=/Users/taejunoh/.cargo/bin:"$PATH" MACOSX_DEPLOYMENT_TARGET=14.0 make swift-test SWIFT_TEST_FILTER='QuotaRecoveryMonitorTests|QuotaRefreshDiagnosticsReporterTests|RefreshCoordinatorTests|AppDelegateLifecycleTests|reporter'
env PATH=/Users/taejunoh/.cargo/bin:"$PATH" MACOSX_DEPLOYMENT_TARGET=14.0 make test
git diff --check
git add Sources/NeedlbarCore/Refresh/QuotaRefreshActivity.swift Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift Sources/Needlbar/App/QuotaRecoveryMonitor.swift Sources/Needlbar/Diagnostics/QuotaRefreshDiagnosticsReporter.swift Sources/Needlbar/App/AppDelegate.swift Tests/NeedlbarTests/QuotaRecoveryMonitorTests.swift Tests/NeedlbarTests/QuotaRefreshDiagnosticsReporterTests.swift Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift Tests/NeedlbarTests/AppDelegateLifecycleTests.swift
git commit -m "feat: observe quota recovery and safe refresh progress"
```

## Task 4: Age open surfaces without fetching and finish deterministic acceptance

**Ownership:**

- Add `Sources/Needlbar/Modules/Provider/QuotaPresentationTicker.swift`.
- Modify `Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift`.
- Modify `Sources/Needlbar/Modules/Overview/OverviewPopoverView.swift`.
- Modify `Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift`.
- Modify `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift`.
- Modify `Sources/Needlbar/Settings/SettingsView.swift`.
- Modify `Tests/NeedlbarTests/ClaudeQuotaFreshnessPresentationTests.swift`.

- [ ] **Add one cancellation-bound local ticker and RED harness.**

The production system-metrics loop normally reprojects dashboard/Settings each
second, but it awaits collection and optional public-IP I/O. The legacy provider
view also stores a fixed presentation. Therefore use a view-local one-second
clock; do not add another provider cadence or depend on network completion.
Define `QuotaPresentationTicker.run(clock:update:)` with a no-op body first,
then add the executable test below. Its final implementation is:

```swift
@MainActor enum QuotaPresentationTicker {
    static func run(
        clock: any ClockLike = SystemClock(),
        update: @MainActor (Date) -> Void
    ) async {
        while !Task.isCancelled {
            update(clock.now)
            do { try await clock.sleep(for: .seconds(1)) }
            catch { return }
        }
    }
}
```

For the test use this finite synthetic clock (no real sleep):

```swift
private final class TwoFrameQuotaClock: ClockLike, @unchecked Sendable {
    private let lock = NSLock()
    private let initial: Date
    private var frame = 0
    init(initial: Date) { self.initial = initial }
    var now: Date { lock.withLock { initial.addingTimeInterval(Double(frame)) } }
    func sleep(for duration: Duration) async throws {
        let next = lock.withLock { frame += 1; return frame }
        if next > 1 { throw CancellationError() }
    }
}

@Test @MainActor func openSurfacesAgeWithoutAnotherRepositoryCall() async throws {
    let success = Date(timeIntervalSince1970: 1_800_000_000)
    let window = try QuotaWindow(id: "claude.session", title: "Session",
                                usedPercent: 25, resetsAt: nil)
    let snapshot = ProviderSnapshot(provider: .claude, usage: nil,
        quota: .init(windows: [window]), usageStatus: .unavailable,
        quotaStatus: .fresh, updatedAt: success, quotaLastSuccessfulAt: success)
    let combined = CombinedUsageSnapshot(system: nil, providers: [snapshot],
                                         capturedAt: success, systemAvailability: [:])
    let settings = SettingsClaudeQuotaPresentation(snapshot: combined, now: success)
    var frames: [[Bool]] = []
    await QuotaPresentationTicker.run(
        clock: TwoFrameQuotaClock(initial: success.addingTimeInterval(899))) { now in
        settings.update(snapshot: combined, now: now)
        let popover = ProviderPopoverPresentation(snapshot: snapshot, now: now)
        let dashboard = SystemDashboardPresentation(snapshot: combined,
                                                     configuration: .init(), now: now)
        frames.append([settings.value.quotaIsLastKnown, popover.quotaIsLastKnown,
                       dashboard.ai.first { $0.provider == .claude }?.quotaIsLastKnown ?? false])
    }
    #expect(frames == [[false, false, false], [true, true, true]])
}
```

Run the filtered host suite with the common environment. Expected RED with the
no-op ticker: no frames. The test constructs only cached snapshots; no repository
exists in this path. Add an integration variant with the existing synthetic
coordinator and a call-count spy frozen during both ticks to assert zero extra
provider calls explicitly.

- [ ] **Wire each open surface to cached reprojection only.**

`ProviderPopoverView` stores its input snapshot and `@State private var
presentationNow = Date()`. Its existing presentation becomes a computed
`ProviderPopoverPresentation(snapshot:snapshot, now:presentationNow)`. Attach
`.task { await QuotaPresentationTicker.run { presentationNow = $0 } }` to its
outer content. Do not route the ticker to `onRetry`.

Give `OverviewPopoverPresentation.init` a defaulted `now: Date = .now` and pass
it to every provider projection and `HeadlineQuotaSelector`. Its legacy view
stores the original snapshots/dailyUsage/enabledProviders, computes its
presentation with `presentationNow`, and uses the same cancellation-bound task.

In `SystemDashboardModel` cache the last input snapshot/configuration. Update
these in its existing initializer/update; add this method without appending a
duplicate system-history sample:

```swift
public func reproject(at now: Date) {
    presentation = SystemDashboardPresentation(
        snapshot: latestSnapshot, configuration: latestConfiguration, now: now)
}
```

Define `latestSnapshot: CombinedUsageSnapshot` and
`latestConfiguration: SystemMonitorConfiguration` as private stored properties
initialized from existing inputs. In the dashboard view's outer content use
`.task { guard !isMeasuring else { return }; await QuotaPresentationTicker.run
{ model.reproject(at: $0) } }`. Layout measurement must not start a persistent
timer. No model update should recreate the tick task through a changing ID.

`SettingsClaudeQuotaPresentation` similarly caches `CombinedUsageSnapshot?`
in its initializer/update and adds `reproject(at:)`, calling the existing
`Self.presentation(for:now:)`. Settings' outer view runs the same ticker and
calls only that method. Keep its existing 15-second bridge-configuration timer
unchanged; the new display ticker must not invoke `manager.recover()` or write
Claude settings. SwiftUI `.task` cancellation tears down all these view-local
loops when their surfaces disappear; no global observer is registered here.

- [ ] **Complete the cross-surface and lifecycle acceptance matrix.**

Repeat the two-frame test across a passed reset, bridge-only age boundary,
Fable-only reset expiry, and nil/future observation metadata. Test cached
dashboard and Settings `reproject(at:)` directly so timer-driven production
methods, not just initializer projections, are exercised. Capture dashboard
history before/after both ticks and require equality. Cancel a tick task with
an injected cancellation-aware clock and require no further updates. Cover
an active bridge generation being disconnected between ticks: the next store
snapshot clears its values, and a stale read cannot restore them (reuse Task 2
cache fencing tests rather than introducing real Claude files).

Run all touched suites plus existing popover/dashboard/Settings layout tests.
Existing fixture snapshots that explicitly expect fresh Claude data must now
provide a real `quotaLastSuccessfulAt`; change only those synthetic fixture
constructors, with a comment explaining the newly approved strict freshness
contract. Never weaken the production rule or restore `updatedAt` fallback to
make an old fixture pass. Add any such test file to the explicit staging list
after reviewing its diff; do not stage an entire test directory.

- [ ] **Verify, commit, and hand off evidence with limits.**

```bash
env PATH=/Users/taejunoh/.cargo/bin:"$PATH" MACOSX_DEPLOYMENT_TARGET=14.0 make swift-test SWIFT_TEST_FILTER='ClaudeQuotaFreshnessPresentationTests|ClaudeStatusLineFallbackIntegrationTests|SystemDashboardPopoverTests|ClaudeUsageConnectionRowLayoutTests|MenuBarControllerTests'
env PATH=/Users/taejunoh/.cargo/bin:"$PATH" MACOSX_DEPLOYMENT_TARGET=14.0 make test
git diff --check
git add Sources/Needlbar/Modules/Provider/QuotaPresentationTicker.swift Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift Sources/Needlbar/Modules/Overview/OverviewPopoverView.swift Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift Sources/Needlbar/Settings/SettingsView.swift Tests/NeedlbarTests/ClaudeQuotaFreshnessPresentationTests.swift
git commit -m "fix: age open Claude quota surfaces from cached state"
```

Return the actual RED/GREEN commands and results, test counts, changed paths,
and remaining limits to the orchestrator for review and the separate STATUS
update. Explicitly state that source tests establish selection, coalescing,
observer cleanup, and local liveness—not credential renewal or deployed
behavior. Native macOS acceptance, installation, reset-boundary/overnight
observation, and long-term unattended recovery remain unverified until a
separately authorized observation produces evidence. Watching existing normal
use may verify a future direct success; it must not manufacture paid prompts,
reauthentication, or CLI sessions to satisfy a reliability claim.
