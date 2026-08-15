# Task 12 implementation report

## Scope

Implemented only Task 12, **Build the Native Accessory App and Hybrid Status
Items**.

## TDD evidence

- RED: `swift test --filter MenuBarControllerTests` initially failed because
  `MenuBarController`, `StatusItemFactory`, and `StatusItemHandle` did not
  exist.
- GREEN: the focused suite passes seven tests: default Overview creation,
  additive Claude creation, targeted removal, intersection-only title/action
  updates, configuration observation, snapshot observation, and cancellation
  of an already queued configuration observation.
- RED: the snapshot-observation test failed while titles were only refreshed
  manually; the store update stream and cancellable observer made it pass.
- RED: the queued-configuration test failed before the observation generation
  guard; it passes after stop invalidates the generation.

## Implementation

- `main.swift` is a thin AppKit runner: it creates `NSApplication.shared`,
  installs `AppDelegate`, and enters `run()`.
- `AppDelegate` is `@MainActor`, owns one long-lived snapshot store,
  configuration, refresh coordinator (with Rust usage/quota repositories and a
  `UsageFileWatcher`), and menu-bar controller. It selects `.accessory` on
  launch, starts observation/refresh, and requests clean coordinator/controller
  shutdown on termination. No document window is created.
- `MenuBarController` uses a status-item factory/handle abstraction so tests do
  not create real `NSStatusItem`s. The AppKit implementation owns each native
  item and removes only the requested item. Reconciliation creates
  `required - existing`, removes `existing - required`, and preserves the
  intersection while updating its renderer title and activation closure.
- `ProviderSnapshotStore` exposes a buffer-newest-one `AsyncStream` of all
  provider snapshots. `ModuleConfiguration` posts one notification after a
  complete settings write. The controller observes both and uses generation
  checks plus cancellation to reject stale queued work after `stopObserving()`.
- Titles are delegated to the Task 11 pure renderer, retaining neutral values
  such as `AI —` and `Claude —` when data is unavailable.
- `Resources/Info.plist` already contained the approved `LSUIElement = true`;
  it was intentionally not changed.

## Verification

- `swift test --filter MenuBarControllerTests` — 7 passed.
- Focused menu-bar suite repeated 20 times — 20/20 passed.
- `swift test` — 39 passed.
- `make test` — passed (Rust workspace, pinned `tokscale-core`, and Swift).
- `make swift` — passed.
- Bounded launch smoke: `.build/debug/Needlbar` remained alive for two seconds
  as PID 61086 and was then sent `SIGTERM`; no Needlbar process remained.
- `git diff --check` passed; `vendor/tokscale-core` is clean.

The expected macOS menu-bar placement/no-Dock-window appearance remains a live
visual smoke check for a release environment; the bounded launch verifies the
entry point without leaving a process running.
