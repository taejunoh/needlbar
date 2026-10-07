# Task 1 report: source-aware Claude quota freshness

## Implementation

- Added a shared direct-window projection in `ClaudeQuotaPresentationSelector`.
  Direct values are current only with a fresh quota status, finite non-future
  success time younger than 900 seconds, and a future reset when a reset is
  present. Missing or invalid success time remains displayable as last-known
  without a fabricated timestamp.
- Made the direct projection public and reused it for legacy/unknown direct
  windows in the provider popover. Retained direct and bridge values rank by
  usable observation time, with direct winning ties and undated values ranking
  last.
- Kept bridge percentage and finite-reset validation, its inclusive 900-second
  recency boundary, and reset-based freshness. Unusable bridge receipt time
  retains a valid value as last-known without displaying that time.
- Updated popover, dashboard, and Settings-through-popover to share projected
  freshness. Resetless current values say “Reset unavailable”; last-known
  values have no live reset countdown. Fable keeps its independent direct
  timestamp and freshness.
- Kept the dashboard’s existing suppression for safe Claude failure labels and
  status-line source labels. Its quota state now comes from projected popover
  freshness, so retained values are not represented internally as fresh.
- Added an unknown `claude.legacy` cross-surface fixture. It remains 75% last
  known with no timestamp or reset, consistently across popover, dashboard,
  and Settings, and does not request Claude sign-in.

## RED evidence

Command:

```bash
env PATH=/Users/taejunoh/.cargo/bin:"$PATH" MACOSX_DEPLOYMENT_TARGET=14.0 make swift-test SWIFT_TEST_FILTER=ClaudeQuotaPresentationSelectorTests
```

The focused selector suite built and ran. It failed on the intended behavior:
the 900- and 901-second observations were reported as not last-known, and the
missing-success case reported `updatedAt` instead of `nil`. This was a behavior
failure, not a build or link failure.

## GREEN evidence

- `ClaudeQuotaPresentationSelectorTests`: 18 tests passed, including direct
  899/900/901-second boundaries, missing/NaN/infinite/future/equal success
  times, direct reset boundaries, status states, bridge 900-second recency,
  bridge reset and percent validation, ranking/ties, and Fable independence.
- `ClaudeQuotaFreshnessPresentationTests`: 2 tests passed for legacy missing
  success-time retention and resetless current copy.
- `ClaudeStatusLineFallbackIntegrationTests`: 1 test passed, preserving Fable,
  the direct failure reason, and the last direct success timestamp.
- Existing synthetic host fixtures were updated only where they represented
  successful current quota but omitted its time. Focused affected suites passed:
  `SystemDashboardPopoverTests` (43), `PopoverPresentationTests` (17), and
  `SettingsStudioTests` (18).
- Final command:
  `env PATH=/Users/taejunoh/.cargo/bin:"$PATH" MACOSX_DEPLOYMENT_TARGET=14.0 make test`
  exited **0**. Representative completion output was
  `notarize-app shell contracts passed`; the final vendor core test run reported
  `1379 passed; 1 ignored`. The command completed the Rust, bridge, vendor,
  Swift (including the affected suites listed above), widget, packaging, and
  notarization contracts.
- `git diff --check` completed with no output.

The first full run exposed 14 assertions in nine existing host tests whose
synthetic snapshots declared `.fresh` while omitting the actual success time,
or whose success time was historical relative to the real clock. The approved
fixture-only corrections made those snapshots explicit and used injected
historical clocks where available. No production freshness rule was relaxed.

## Files changed

Task 1 source and test paths:

- `Sources/NeedlbarCore/Presentation/ClaudeQuotaPresentationSelector.swift`
- `Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift`
- `Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift`
- `Tests/NeedlbarCoreTests/ClaudeQuotaPresentationSelectorTests.swift`
- `Tests/NeedlbarTests/ClaudeStatusLineFallbackIntegrationTests.swift` (already
  asserted the required failure/Fable/last-success behavior; no edit was
  necessary)
- `Tests/NeedlbarTests/ClaudeQuotaFreshnessPresentationTests.swift`

Additional synthetic fresh-fixture paths explicitly allowed by the brief:

- `Tests/NeedlbarTests/PopoverPresentationTests.swift`
- `Tests/NeedlbarTests/SystemDashboardPopoverTests.swift`
- `Tests/NeedlbarTests/SettingsStudioTests.swift`

The pre-existing dirty `docs/STATUS.md` and untracked competitor research were
preserved and not staged.

## Self-review and concerns

- The direct selector uses only `quotaLastSuccessfulAt`; `updatedAt` is never
  substituted. Missing/non-finite/future direct and bridge times cannot make a
  value current or appear in the UI.
- Direct Fable uses the same direct policy with its own reset. Bridge data does
  not refresh or timestamp Fable.
- Dashboard status text retains the previously approved safe-failure and
  status-line source suppression. For other Claude states, it uses the
  projected freshness from the shared presentation.
- No auth, provider request, Rust schema, or app installation path was changed.
- Existing compiler warnings and `kill: ... No such process` test-process
  output remain; they were already present in the supplied baseline.
