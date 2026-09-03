# Dashboard Readability Implementation Plan

> For agentic workers: use subagent-driven-development with explicit file
> ownership. User AGENTS.md requests parallel independent work; the three
> implementation lanes below form one integration task. Do not commit another
> worker's edits or run concurrent Swift builds.

**Goal:** Deliver a compact, live, legible dashboard with verified native values.

**Architecture:** Existing combined snapshots feed one observable presentation
model and bounded memory-only history. Native collectors stay in NeedlbarCore;
SwiftUI/AppKit own graphs, rendering, width budgets, and interactions.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Darwin, IOKit, Swift Testing.

## Task 1: Implement and verify the approved screenshot follow-up

### A. Collector corrections (deep-reasoner)

Files: `Sources/NeedlbarCore/SystemMetrics/MacSystemMetricsCollector.swift`, new
pure conversion helpers alongside it, and focused collector tests under
`Tests/NeedlbarCoreTests/`. Coordinate any additive snapshot model fields before
editing the model file owned by lane C.

- [x] Trace memory, swap, disk throughput, battery health, and primary-interface
  data from native inputs; document exact causes before edits.
- [x] Add fixture regressions for actual faulty conversions, nil readings,
  counter reset/first sample, and capacity denominators.
- [x] Correct collector implementation using native APIs and safe counter deltas.
  Keep samples and IP values memory-only and failures module-local.

### B. Popover and presentation (deep-reasoner)

Files: `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift`, new
`SystemDashboardModel.swift`, chart/presentation helpers in that directory,
and `Tests/NeedlbarTests/SystemDashboardPopoverTests.swift` plus history tests.

- [x] Add observable model with this integration seam:

```swift
@MainActor public final class SystemDashboardModel: ObservableObject {
    // init(snapshot: CombinedUsageSnapshot, configuration: SystemMonitorConfiguration)
    // update(snapshot: CombinedUsageSnapshot, configuration: SystemMonitorConfiguration)
    // Published presentation and at most 60 fresh samples, deduped by capture time.
}
```

- [x] Preserve the existing snapshot/configuration view initializer for tests;
  add `init(model: SystemDashboardModel, maximumHeight: CGFloat = 680,
  onShowSettings: ..., onShowAnalytics: ..., onProviderAction: ...)`.
- [x] Build gauges, core bars, two-channel transfer trends, a restrained opaque
  background, metric captions and status badges, fixed header/footer, and
  screen-bounded scrollable content. Add local-IP disclosure using the new
  `configuration.localIPEnabled` field from lane C.
- [x] Cover stale/missing values, bounded history, repeated provider updates,
  provider action policy, and privacy in meaningful presentation tests.

### C. Compact menu, settings, and live integration (fast-worker)

Files: `MenuBarDashboardRenderer.swift`, `MenuBarController.swift`,
`SystemMonitorSettingsView.swift`, `ModuleConfiguration.swift`, configuration
portion of `SystemMetricModels.swift`, associated menu/config/settings tests.

- [x] Add `localIPEnabled: Bool = false` and persist it under
  `needlbar.systemMonitor.localIP`. Default visible modules become CPU/RAM/AI;
  preserve explicitly persisted values. Add a local-IP setting and compact
  defaults action without silently overwriting existing preferences.
- [x] Measure titles with AppKit menu font, cap width at 240 points and three
  displayed modules, use short values/overflow indication and a full tooltip.
  Respect configured order and handle budgets too narrow for numeric content.
- [x] Own one lazy SystemDashboardModel in MenuBarController, update it from
  reconcile, pass it when opening the panel, and use anchor visible height to
  cap content. Keep panel anchor/dismissal-generation behavior intact.
- [x] Test real measured widths, legacy settings, all-provider overflow,
  controller live-model updates, and settings round trips.

### D. Integration review, package, and native confirmation (orchestrator)

- [x] Run focused regression suites serially through `make swift-test` with
  `SWIFT_TEST_FILTER`, fixing concrete failures in the owning lane.
- [x] Review spec compliance, then code quality through independent review.
- [ ] Run `source /Users/taejunoh/.cargo/env && make test` and require exit 0.
- [ ] Run `make package` and `make smoke`; relaunch the exact local bundle and
  inspect dashboard width, visual hierarchy, live updates, disclosure and dismissal.
- [x] Update README, privacy/architecture descriptions as needed and STATUS with
  verified outcomes and exact continuation. The reviewed checkpoint was
  committed and fast-forward merged locally into `main` at `d719402` under the
  user's explicit authorization despite the known unchanged process-fixture
  failures. Release publication remains gated on a green `make test`.

Integration note (2026-09-02): packaging/smoke and current-host visual checks
passed. All six sections fit the saved one-provider configuration; the open
panel updates live and Settings works. Local-IP settings were restored off.
Explicit expanded-disclosure/outside-click checks remain unclaimed. The final
default full gate has existing shell/process-fixture deadline failures. The
reviewed checkpoint is merged into `main` at `d719402`; no assertion of remote
publication is made here, and release publication remains gated on a green full
test run. See `docs/STATUS.md` for exact attempts and evidence.

Self-review: all approved follow-up requirements have an owner. UI history is
bounded and contains no IP; local-IP opt-in never enables a public request.
Collectors do not affect Rust or acceptance fixture construction. Current-host
visual confirmation and deferred native macOS 14 acceptance are separate claims.
