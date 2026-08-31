# Notification Task N1 Report

## RED

Command:

```bash
source /Users/taejunoh/.cargo/env && make swift-test SWIFT_TEST_FILTER=ProviderSnapshotStoreTests
```

Outcome: exit 1 during Swift compilation, with the expected missing `ProviderSnapshotStore` members `quotaAlertChangeSignals`, `quotaAlertCapture`, `currentQuotaAlertSample`, and missing `QuotaAlertSample` type. The test additions therefore failed before the production seam existed.

## Focused GREEN

Command:

```bash
source /Users/taejunoh/.cargo/env && make swift-test SWIFT_TEST_FILTER=ProviderSnapshotStoreTests
```

Selected suite and tests:

- Suite `ProviderSnapshotStoreTests`: 4 tests, 0 failures.
- `authenticationFailureWithoutKnownQuotaRequiresAuthentication()` — passed.
- `usageAndQuotaFailuresPreserveIndependentLastKnownGoodValues()` — passed.
- `quotaAlertCaptureIsQuotaOnlyAndCoalescingStillCapturesBothProviders()` — passed.
- `currentQuotaAlertSampleReflectsAFailureAfterItsSuccessfulRevision()` — passed.

Literal outcome: `Test run with 4 tests in 1 suite passed`.

Command:

```bash
source /Users/taejunoh/.cargo/env && make swift-test SWIFT_TEST_FILTER=ExportCaptureTests
```

Selected test:

- `exportCaptureHasOneClockValueFixedProviderOrderAndIndependentStreamTimes()` — passed.

Literal outcome: `Test run with 1 test in 0 suites passed` (Swift Testing reports this global test as selected despite the legacy XCTest wrapper line).

## Full GREEN

Command:

```bash
source /Users/taejunoh/.cargo/env && make test
```

Full outcome: exit 0.

- Rust workspace: all listed bridge/source/quota tests passed; no failures.
- Pinned `tokscale-core`: `1372 passed; 0 failed; 1 ignored`.
- Swift: `Test run with 189 tests in 6 suites passed`.
- Widget extension contract: `widget-extension build/metadata contract passed`.
- Package contract: `package-app relink regression passed`.
- Notarization shell contract: `notarize-app shell contracts passed`.

## Changed files

- `Sources/NeedlbarCore/State/ProviderSnapshotStore.swift`
- `Tests/NeedlbarCoreTests/ProviderSnapshotStoreTests.swift`
- `docs/STATUS.md`

The additional requested report is this file.

## Self-review

- Added only the quota-specific `QuotaAlertSample`, per-provider `UInt64` revision, authoritative fixed-order capture/current lookup, and `.bufferingNewest(1)` `AsyncStream<Void>` wake-up.
- `applyUsage` does not advance quota revisions or publish quota wake-ups.
- The coalescing test captures the usage-only state before quota application and asserts no quota value and revision `0`.
- `markQuotaFailure` preserves the last successful revision/value while `currentQuotaAlertSample` exposes the current failure status.
- Existing `ProviderSnapshot`, `updates()`, widget capture, and `captureForExport(exportedAt:)` behavior remain unchanged.
- Tests use the explicit `ProviderSnapshotStoreTests` suite required by the focused filter; no ignored polling or `Task.yield` negative assertion was added.
- `git diff --check` passed before the final gate.

## Commit and caveats

Focused commit: `feat: expose authoritative quota alert samples` (hash recorded by git after this report is staged).

No provider calls, credentials, permissions, push, merge, tag, release, or live-provider acceptance were performed. Local linker output retains the known macOS 26.5-object versus macOS 14 deployment warning; this does not claim signed macOS 14 arm64 acceptance.
