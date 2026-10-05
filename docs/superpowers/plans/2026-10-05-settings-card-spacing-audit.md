# Settings card spacing audit implementation plan

> **For agentic workers:** Use subagent-driven-development; one implementation task and independent specification/quality reviews.

**Goal:** Consistent card clearance and visually checked Settings coverage.
**Architecture:** Shared SwiftUI card shell owns outer gutters; existing content owns internal separation. Parameterized production content permits safe synthetic hosting.
**Tech Stack:** SwiftUI, AppKit hosting, Swift Testing, existing Make verification wrapper.

### Task 1: Normalize card gutters and verify all Settings screens

Files: `Sources/Needlbar/Settings/SettingsStudioComponents.swift`,
`SettingsView.swift`, CPU/RAM/Disk/Network information views;
`Tests/NeedlbarTests/ClaudeUsageConnectionRowLayoutTests.swift` and a focused
`SettingsCardSpacingLayoutTests.swift` / test-only capture utility as needed.

- [x] Add real-hosted shell/content edge-clearance regression. Capture affected
  baseline cards and watch the new assertion fail before production changes.
  Measure the production-used internal `SettingsStudioCard` surface, not
  section-minus-content: the latter includes the title and external 12pt gap.
  Extracting the unchanged surface first is allowed to isolate that boundary.
- [x] Run `PATH=/Users/taejunoh/.cargo/bin:$PATH make swift-test SWIFT_TEST_FILTER=SettingsCardSpacingLayoutTests`.
- [x] Apply `.padding(.horizontal, 24).padding(.vertical, 20)` before the shared
  background. Remove Claude row's local8h/20v, Cursor12v, information
  VStacks'11/11/11/13v. Convert status-line and billing post-divider12v to12top.
  Retain caption6bottom and row54 minimum. Add export feedback spacing only if
  the populated/failure render reproduces crowding.
- [x] Keep the previous Claude regression protecting total clearance after
  moving padding ownership; do not replace meaningful expectations with
  tautological assertions. Use a production-used internal parameterized page
  content boundary if necessary; do not add public fixture navigation knobs.
- [x] Render all28 page/tab combinations at default/minimum size and both
  appearances with isolated synthetic snapshots and inert dependencies;
  save full body/viewport images under `/tmp/needlbar-settings-spacing-review`.
  Verify long and missing values without real provider reads or actions.
- [x] Run focused tests GREEN, inspect actual images, correct only reproduced
  layout failures, then independent scope and code-quality reviews.
- [x] Run `PATH=/Users/taejunoh/.cargo/bin:$PATH make test`, `git diff --check`;
  update `docs/STATUS.md` with measured coverage, test results and deployment
  boundary. Commit focused changes locally; no push/install/release.
