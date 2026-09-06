# Settings Native Review Host — Task 7 Addendum

> **For agentic workers:** Use subagent-driven-development for the bounded implementation and sequential spec/quality reviews. This extends Task 7 of the approved Settings Module Studio Phase 1 plan; it does not redesign the product.

**Goal:** Run real Settings action-state UI on a normal AppKit main loop without invoking production side effects.

**Architecture:** A separate opt-in executable uses the public NeedlbarApp library. Shared review-only support supplies inert external boundaries to the real login/export coordinators. Swift Testing retains automated state assertions but does not own the executable's event loop.

**Tech stack:** SwiftPM, Swift 6, AppKit/SwiftUI, existing NeedlbarApp/Core APIs. macOS 14 deployment target is unchanged; current-host review does not establish macOS 14 acceptance.

## Approved boundary

The user approved the separate executable after the blocking Swift Testing loop prevented asynchronous action progress. Do not repeat the blocking test-loop or manually pumped test-loop experiments. Do not start production AppDelegate, collectors, quota fetches, external login, browser links, save panels, writers or notification services. No installation, signing, push, merge or release is included.

## Implementation task

- [x] Add review-only support target and executable product/target in Package.swift; add support to NeedlbarTests dependencies. Existing Needlbar product dependencies remain unchanged.

```swift
.executable(name: "NeedlbarSettingsStudioReview", targets: ["NeedlbarSettingsStudioReview"])
.target(name: "NeedlbarSettingsStudioReviewSupport", dependencies: ["NeedlbarApp", "NeedlbarCore"])
.executableTarget(name: "NeedlbarSettingsStudioReview", dependencies: ["NeedlbarApp", "NeedlbarCore", "NeedlbarSettingsStudioReviewSupport"])
```

- [x] Test explicit launch validation first: only `--settings-studio-review` is accepted. Missing/unknown arguments exit 64 before accessing NSApplication or defaults. Retain existing real-coordinator success/retry-failure assertions from SettingsStudioActionFixtures.swift.
- [x] Extract the existing fixture factory/doubles into `Sources/NeedlbarSettingsStudioReviewSupport/SettingsStudioReviewFixtures.swift`, with no Testing import. The tests import that support module. Empty exports use a fresh, empty ProviderSnapshotStore's public `captureForExport`; no product initializer visibility changes.
- [x] Add `Sources/NeedlbarSettingsStudioReview/main.swift` with a synchronous top-level `application.run()`, outside any Swift Testing/MainActor task. Own a UUID defaults suite, two real SettingsWindowControllers (light 960×720 / dark 760×560), passive empty snapshots, one shared configuration/action fixture, inert notifications and empty Cursor opener. Action phases wait eight seconds for manual inspection; automated tests use zero delay.
- [x] Observe only isolated configuration notifications to update both passive previews. Log PID/window sizes and safe state/order identifiers, never credentials, IPs or source paths.
- [x] End on last window close or a 600-second timeout. An idempotent finish path invalidates timer/subscriptions, closes owned windows and removes only the generated defaults suite. Stop/wake the AppKit loop, explicitly clean up after run returns, then exit 0 for normal close or nonzero for timeout.
- [x] Add the explicit non-packaging Make entry:

```make
settings-native-review: rust
	swift run NeedlbarSettingsStudioReview --settings-studio-review
```

## Verification sequence

- [x] Serial baseline/narrow tests via `make swift-test SWIFT_TEST_FILTER=settingsStudioActionFixtures` and any launch-validation filter. Record RED/GREEN, not just build success.
- [x] Build `swift build --product NeedlbarSettingsStudioReview` after normal Rust build; invoke without arguments and require exit 64 with no window.
- [x] Sequential independent spec and code-quality review; resolve important findings before native launch.
- [ ] Launch only the review executable. Inspect Claude/Codex idle, launching, awaiting browser, verifying, connected and rejected states; in-flight buttons disabled. Inspect export busy, success and failure. These are fixture observations, not real account/file acceptance.
  - Observed all listed Claude states; Codex idle/launching/awaiting-browser/connected/rejected and export busy/success/failure. Codex verifying appears in the coordinator log but its UI phase was not captured, so this complete-matrix item remains unchecked. Independent screenshot review found no clipping/overlap in six success/failure captures.
- [ ] Verify keyboard/reorder, drag and actual display transitions where available. Record tool/host limitations accurately; never translate a synthetic-input success into an acceptance pass.
  - Still pending. Earlier synthetic keyboard/drag attempts did not establish acceptance; this action-state run changed no OS settings and did not exercise display transitions.
- [x] Close owned windows and require normal process exit; confirm no temporary host remains.
- [x] Run `make test`, `make acceptance-test`, `git diff --check` serially. Update STATUS with exact evidence, unresolved items and the next continuation point. No integration action follows automatically.
  - Exit 0: 433 Swift tests in 19 suites plus standard Rust/vendor/shell gates; 9 acceptance tests in 1 suite. The opt-in native Swift test is skipped by default. Details and external log/capture paths are in STATUS.
