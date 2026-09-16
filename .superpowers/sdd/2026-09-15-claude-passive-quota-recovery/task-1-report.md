# Task 1 report — Claude passive quota recovery

## DONE

- Added Core-only allowlisted Claude quota failure metadata. Successful quota timestamps are
  retained only by successful quota application and do not enter exports, widgets, diagnostics,
  or logs.
- Mapped returned errors, bridge failures, and untyped failures to the approved safe reasons
  without inspecting raw messages. Codex and Cursor behavior remains unchanged.
- Replaced Claude recovery login CTAs with the explicit `View Claude usage` action, whose only
  destination is `https://claude.ai/settings/usage`. Dashboard, provider popover, and Settings
  retain local fixed feedback when that explicit URL cannot open.
- Added last-known/unavailable presentation, locale-formatted successful check time, and stale
  Fable marking without repeating the provider reason. Updated the scoped Claude documentation.

## Verification

- RED evidence recorded before Core and presentation production changes: missing safe metadata
  and presentation/action symbols caused the new tests to fail to compile; implementation then
  made the focused seams green.
- Focused suites: ProviderSnapshotStore (8), RefreshCoordinator (30), PopoverPresentation (12),
  SystemDashboardPopover (33), MenuBarController (36), SettingsStudio (10), SnapshotExporter
  (9).
- Initial full gate reached the final `notarize-app-tests` check and failed only because its
  historical live-README assertion required the removed v0.3.2 login wording. The narrow
  assertion now requires the approved passive-recovery limitation while retaining release and
  authentication guards; its focused run passed.
- Final full gate: `PATH=/Users/taejunoh/.cargo/bin:$PATH make test` passed; log:
  `/tmp/needlbar-passive-full-gate-final.log`.
- Review follow-up RED: after adding the Settings row test, `PATH=/Users/taejunoh/.cargo/bin:$PATH
  swift test --filter SettingsStudioTests` exited 1 with `cannot find
  'SettingsClaudeUsageRowState' in scope` (`/tmp/needlbar-passive-review-red-settings.log`).
  After the bridge test-runtime build and implementation, focused Settings (11), Popover (12),
  and Dashboard (33) suites passed. The post-review full gate passed with exit 0; log:
  `/tmp/needlbar-passive-review-full-final.log`.
- Final-review RED: `PATH=/Users/taejunoh/.cargo/bin:$PATH swift test --filter
  SystemDashboardPopoverTests` exited 1 because `FableQuotaDetail` had no `statusText`
  presentation seam (`/tmp/needlbar-passive-finalreview-red-dashboard-meaningful.log`).
  The model now owns that text and suppresses the secondary Fable `Error` or `Authentication
  required` status whenever the parent Claude snapshot has an approved safe fallback reason,
  while retaining Fable freshness, `Last known`, and reset text. The focused Dashboard suite
  passed 34 tests (`/tmp/needlbar-passive-finalreview-green-dashboard.log`). Per final-review
  task assignment, the root agent owns the post-commit whole-suite gate.
- `git diff --check` passed before the full gate.

## CONCERNS

- No live authentication, Keychain read, CLI login, network account request, app launch, or
  installation was performed. Native visual acceptance remains separately authorized work.
- Existing Rust static-library linker warnings report objects built for macOS 27 while linking
  for macOS 14; the focused suites and prior baseline show the same warning.
