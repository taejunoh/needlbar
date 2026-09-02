# AI Remaining Default Implementation Plan

> **For agentic workers:** Use subagent-driven-development with one implementation
> owner and sequential spec/quality reviews. Do not run concurrent Swift builds.

**Goal:** Make remaining subscription quota the default AI value in the menu bar
and dashboard, as approved by the user on 2026-09-02.

**Architecture:** Reuse the existing `.remaining` display mode and most-constrained
quota selector. Change model and persisted-configuration fallback defaults only;
explicitly stored metric selections remain valid. Unknown quota stays unknown
instead of falling back to token totals. Existing provider action policy remains
unchanged, including Cursor's Spending link.

**Tech Stack:** Swift 6, NeedlbarCore, UserDefaults, Swift Testing, native Settings.

## Task 1: Change and verify the AI default

Implementation owner: fast-worker. Root owns this plan, README/STATUS, final
verification, and the current Mac's Settings interaction.

Files: `Sources/NeedlbarCore/SystemMetrics/SystemMetricModels.swift`,
`Sources/NeedlbarCore/Configuration/ModuleConfiguration.swift`,
`Tests/NeedlbarCoreTests/ModuleConfigurationTests.swift`,
`Tests/NeedlbarCoreTests/SystemMetricModelTests.swift`,
`Tests/NeedlbarTests/MenuBarDashboardRendererTests.swift`,
`Tests/NeedlbarTests/SystemDashboardPopoverTests.swift`. Adjust an existing test
fixture that intentionally exercises `.usage` to select that mode explicitly.

- [x] Write regressions for fresh/default and invalid persisted metric values,
  plus preservation of explicit `.usage`/`.cost` selections. Assertions use
  literal `.remaining`, not `AIProviderDisplayPreference()` as the expected
  value. Add a consumer assertion showing a remaining-percent headline when
  token totals also exist and no token fallback when quota is unavailable.

  Example core expectation using the suite's isolated UserDefaults helper:

  ```swift
  let configuration = ModuleConfiguration(defaults: defaults)
  #expect(configuration.systemMonitor.ai[.claude]?.metric == .remaining)
  defaults.set("usage", forKey: "needlbar.systemMonitor.ai.claude.metric")
  #expect(configuration.systemMonitor.ai[.claude]?.metric == .usage)
  defaults.set("invalid", forKey: "needlbar.systemMonitor.ai.claude.metric")
  #expect(configuration.systemMonitor.ai[.claude]?.metric == .remaining)
  ```

- [x] Capture RED with `source /Users/taejunoh/.cargo/env && make swift-test
  SWIFT_TEST_FILTER=ModuleConfigurationTests`. Failure must be the old `.usage`
  default rather than a build/setup error.
- [x] Change `AIProviderDisplayPreference.init`'s `metric` default to
  `AIProviderDisplayMetric = .remaining`; change ModuleConfiguration's missing/
  invalid stored metric fallback from `?? .usage` to `?? .remaining`.
- [x] Run focused configuration and presentation tests; review spec compliance
  followed by code quality. No provider retrieval changes or new dashboard URLs.
- [x] Root runs `make test`, then `make package && make smoke`. Report any
  pre-existing process-fixture timeout separately, without weakening tests or
  calling the full gate green.
- [x] Set current Mac provider display metrics to Remaining through Needlbar
  Settings (or its exact UserDefaults keys if native picker automation is
  unavailable) while preserving visibility/order, IP settings, and other choices;
  verify menu/popover integration with the exact rebuilt local bundle.
- [ ] Update README/STATUS and this checklist with actual evidence. The user has
  explicitly authorized committing and pushing this reviewed development-branch
  checkpoint despite the known unchanged process-fixture timeout failures; keep
  main integration and release publication gated on a green `make test`, and do
  not describe the full gate as green.

Verification: 66 focused tests passed after the expected RED; both reviews
passed. Full `make test` still fails two pre-existing Codex process-fixture
deadline tests. Package/smoke passed. Native Settings shows Remaining for all
three providers; the live Claude row correctly shows unknown quota rather than
its available token total. After the user completed browser sign-in, a fresh
native capture confirmed Claude 22% remaining with Usage and Quota Fresh;
that screenshot is included in README. README/STATUS are updated. Development-branch
checkpoint publication is explicitly authorized despite the unchanged fixture
timeouts; main integration and release remain gated on a green full test run.

Self-review: both default construction paths are covered, saved choices are
preserved for other users, and the current Mac change is an explicitly approved
settings update rather than a destructive migration. No new quota computation,
provider integration, or layout redesign is introduced.
