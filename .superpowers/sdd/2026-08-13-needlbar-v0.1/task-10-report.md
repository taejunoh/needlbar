# Task 10 report — Refresh coordination and file triggers

## Files

- `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`
- `Sources/NeedlbarCore/Refresh/UsageFileWatcher.swift`
- `Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift`
- `Tests/NeedlbarCoreTests/UsageFileWatcherTests.swift`

## RED evidence

1. Before production implementation, `swift test --filter RefreshCoordinatorTests` exited nonzero because `ClockLike`, `RefreshCoordinator`, `UsageFileWatcher`, and `UsageFileEventSource` did not exist.
2. During the concurrency audit, `swift test --filter restartDoesNotOverlapARefreshCancelledDuringStop` failed with `usage.callCount == 2` after `stop()` followed by `start()`, demonstrating a second synchronous usage refresh could overlap the cancelled-but-still-running call.

## GREEN evidence

- `swift test --filter RefreshCoordinatorTests` — 5 passed.
- `swift test --filter UsageFileWatcherTests` — 4 passed.
- `swift test` — 17 passed.
- `source /Users/taejunoh/.cargo/env && make test` — passed; Rust workspace tests and Swift's 17 tests passed.
- `git diff --check` — passed before commit.

## Implementation notes

- The coordinator is an actor with one tracked task per usage/quota stream. Stop cancels cadence tasks and in-flight tasks, while retaining an uncooperative synchronous repository call until it returns; a restart queues exactly one follow-up rather than overlapping it.
- Manual refresh waits for an existing usage task and schedules one forced next cycle. The quota popover boundary is strictly older than 60 seconds; five-minute cadence and one-second debounce use injected `ClockLike` implementations in tests.
- The watcher only discovers existing approved roots: Claude projects/transcripts, configured-or-default Codex sessions/archived sessions, and the tokscale-compatible Cursor cache. It uses directory descriptors and `DispatchSourceFileSystemObject`, with exact-once descriptor closure guarded by a lock and cancellation handler.

## Deviation / concern

Task 9's `UsageRepository` API and the current Rust C ABI expose no force-Cursor-sync operation. `RefreshCoordinator` therefore injects an optional async `forceCursorSync` operation so ordering is testable; production wiring is a no-op unless a future bridge/repository change supplies that operation. Adding the necessary Rust ABI was outside Task 10 ownership.

## Commit

`cba429c` — `feat: coordinate bounded usage and quota refresh`

## Fix round 1

Expanded ownership was necessary to complete the approved manual-refresh contract vertically: the bridge now exports `needlbar_forced_usage_snapshot_json`, which retains the existing string ownership/panic-envelope behavior while collecting usage with `sync_cursor_cache(true)`. Swift `RustBridge` selects that ABI only for `UsageRepository.refresh(forceCursorSync: true)`, and `RefreshCoordinator.manualRefresh()` calls the repository force path rather than an optional no-op closure.

Additional RED evidence: the stop/start overlap regression failed with a second in-flight synchronous usage call; the all-provider-error quota path previously advanced the popover freshness timestamp. GREEN: force seam unit test, `RefreshCoordinatorTests` (6), `UsageFileWatcherTests` (4), full Swift tests (18), bridge Clippy, and diff check passed. `make test` is running at report update time.

Fix-round commit: `4675a40` — `fix: force cursor sync through refresh bridge`. `make test` completed successfully after the report's initial update. A broad `cargo fmt` was immediately corrected by restoring only its accidental changes under the pinned vendor submodule; scoped `cargo fmt -p needlbar-bridge -- --check` then passed.

Fix round 2 commit: `06aff57` — `fix: guard refresh effects by run generation`. Safety tasks and watcher callbacks now capture their run generation; stale callbacks are rejected. Refresh results recheck generation before each store mutation, and manual refresh avoids queuing a second forced cycle when one is already active. Focused refresh (6) and watcher (4) tests passed.

Fix round 3 commit: `8a873e4` — `fix: coalesce forced refresh requests`. A manual call that joins an already-forced usage refresh now treats that task as fulfillment instead of starting another refresh after awaiting it. The coordinator also exposes a generation-bound usage-refresh callback for watcher wiring and rejects no-token usage requests while stopped. Focused refresh/watcher and full Swift (18) passed; final `make test` was launched after these edits.

## Fix round 4

RED: `manualRefreshBurstDoesNotStartAnotherForcedCycleAfterItsQueuedCycleCompletes` reproduced a non-forced manual burst as `[false, true, true]` (three usage calls) rather than the required `[false, true]`. The watcher lifecycle test did not compile before the refactor because neither coordinator ownership nor a mandatory receiver lifecycle existed.

GREEN: each manual waiter records whether a forced cycle was already active or queued before awaiting, and only an unsatisfied requirement may start a forced request. `RefreshCoordinator` now owns an injected `UsageFileWatching` component: every `start()` gives it a fresh, generation-bound `UsageRefreshRequestToken`; `stop()` invalidates/stops it; a restart receives a new token. `UsageFileWatcher` cannot start without that token. The final receiver rechecks the coordinator generation after an old debounced watcher delivery is deliberately paused across stop/restart. Watcher and coordinator API comments document the lifecycle.

The controllable clocks now track per-sleeper deadlines: tests prove the safety cadence does not fire at 299 seconds and the debounce does not fire at 0.999 seconds. Focused results: refresh 7, watcher 5; full Swift 20. Stability checks ran each new race test 20 times successfully. Final `make test` and diff/vendor verification follow this report update.

## Fix round 5

RED: `staleWatcherStartupCannotStopTheWatcherInstalledByANewerRun` held G1 inside `UsageFileWatching.start`, then stopped and restarted the coordinator so G2 installed its receiver. Resuming G1 reproduced the bug: the stale continuation invoked a second shared watcher `stop`, producing lifecycle `start-1, stop, start-2, stop`; G2 became inactive and its event did not request the expected second usage refresh.

GREEN: after `stop()` has invalidated G1 and stopped its watcher, a stale G1 `start()` continuation now only returns. It never stops the shared watcher, so G2 remains active and a G2 event requests exactly one additional usage refresh. The regression test asserts lifecycle order/count and the observable G2 refresh behavior.

Verification: the focused race test passed 20 consecutive runs; `swift test --filter RefreshCoordinatorTests` passed 8 tests; `swift test --filter UsageFileWatcherTests` passed 5 tests; full `swift test` passed 21 tests; and a fresh `source /Users/taejunoh/.cargo/env && make test` passed.
