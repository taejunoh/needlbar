# CPU Settings Information Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show truthful hardware, live activity, and freshness on Settings → CPU while preserving existing controls and collection behavior.

**Architecture:** Extend the Swift Core CPU snapshot with optional cached hardware metadata. Feed a focused Settings presentation through the existing controller update path; render it above the surface-specific detail pane on all three CPU tabs. No Settings collector, new timer, provider refresh, or Rust changes.

**Tech Stack:** Swift 6, Darwin sysctl, existing actor-based system collector, SwiftUI/AppKit, Swift Testing.

---

## Context and ownership

Worktree: `/Users/taejunoh/.codex/worktrees/claude-statusline-hybrid/needlbar`
Branch: `codex/cpu-settings-information`
Approved spec: `docs/superpowers/specs/2026-09-30-cpu-settings-information-design.md`.
The user has chosen delegated implementation through repository AGENTS rules.
Do not create another worktree or app bundle, install, publish, or push.

Task 1 owns Core models/collector and its tests. Task 2 owns Settings
presentation/view/controller wiring and its tests. Execute tasks sequentially,
with spec compliance followed by quality review before starting the next task.
Main owns this plan and final status documentation.

Existing `SystemMetricsSnapshot` is not Codable and has no CPU hardware wire
format to migrate. Preserve source compatibility through a defaulted optional
initializer parameter; do not add serialization solely for this feature.

## Task 1: Optional hardware metadata and one-time native discovery

**Files:**
- Modify: `Sources/NeedlbarCore/SystemMetrics/SystemMetricModels.swift` (CPU only)
- Create: `Sources/NeedlbarCore/SystemMetrics/CPUHardwareInfo.swift`
- Create: `Sources/NeedlbarCore/SystemMetrics/MacCPUHardwareReader.swift`
- Modify: `Sources/NeedlbarCore/SystemMetrics/MacSystemMetricsCollector.swift` (CPU only)
- Create: `Tests/NeedlbarCoreTests/CPUHardwareInfoTests.swift`
- Modify: `Tests/NeedlbarCoreTests/SystemMetricModelTests.swift`

- [ ] Write failing tests for consumer-visible hardware normalization, query
  discovery, bounded queries, one-time collector discovery, and existing CPU
  initializer compatibility. Use injected sysctl values rather than host-specific
  assertions. Required fixtures: Apple M5 Pro / 15 / 15 / Super 5 / Performance
  10; missing name with counts; missing groups with valid name; all queries
  absent; blank name; zero/negative counts; excessive perf-level count. A
  malformed field does not erase independently valid fields.

```swift
@Test func hardwareNormalizesInvalidIndependentFields() {
    let value = CPUHardwareInfo(name: "  ", physicalCoreCount: 0,
        logicalCoreCount: 15, coreGroups: [])
    #expect(value.name == nil)
    #expect(value.physicalCoreCount == nil)
    #expect(value.logicalCoreCount == 15)
}

@Test func existingCPUInitializerDoesNotRequireHardware() {
    let cpu = SystemMetricsSnapshot.CPU(totalUsage: MetricPercentage(25),
        perCoreUsage: [MetricPercentage(25)!])
    #expect(cpu.hardware == nil)
    #expect(cpu.totalUsage?.value == 25)
}
```

- [ ] Run `swift test --filter CPUHardwareInfoTests` and
  `swift test --filter SystemMetricModelTests`. Record RED output showing the
  missing new behavior before implementation; fix incidental syntax errors
  before treating a failure as evidence.
- [ ] Implement `CPUHardwareInfo: Equatable, Sendable` with independently
  optional trimmed `name`, positive `physicalCoreCount`, positive
  `logicalCoreCount`, and validated `CoreGroup(name:physicalCoreCount:)` values.
  Group entries require both a nonblank name and positive count. Add this
  backward-compatible CPU field and initializer:

```swift
public let hardware: CPUHardwareInfo?

public init(totalUsage: MetricPercentage?, perCoreUsage: [MetricPercentage],
            hardware: CPUHardwareInfo? = nil) {
    self.totalUsage = totalUsage
    self.perCoreUsage = perCoreUsage
    self.hardware = hardware
}
```

- [ ] Implement `MacCPUHardwareReader` with small injectable string/integer
  query closures and `read() -> CPUHardwareInfo?`. Use native `sysctlbyname`,
  cap string allocation at 4096 bytes, require expected integer byte size,
  and query exactly `machdep.cpu.brand_string`, `hw.physicalcpu`,
  `hw.logicalcpu`, `hw.nperflevels`, and group `.name` / `.physicalcpu`
  under `hw.perflevelN`. Accept 1...32 perf levels; outside that range skip
  groups. Never probe guessed group slots. Return nil if every field is absent.
  Use an internal dependency initializer for tests; do not expose a new public
  configurable hardware-query API.

```swift
let groupCount = integer("hw.nperflevels")
let indexes = groupCount.flatMap { (1...32).contains($0) ? Array(0..<$0) : nil } ?? []
let groups = indexes.compactMap { index in
    CPUHardwareInfo.CoreGroup(name: string("hw.perflevel\(index).name"),
        physicalCoreCount: integer("hw.perflevel\(index).physicalcpu"))
}
```

- [ ] In the collector, discover hardware once on the first collection,
  cache the result including unsupported/partial results for its lifetime,
  and attach it to every CPU result, including tick failures and initial
  warmup. Keep default public initialization unchanged. Do not query on the
  Settings/UI thread, derive counts from sampled bars, or change non-CPU paths.
  Distinguish initial lack of tick baseline with availability code
  `cpuWarmingUp`; actual `host_processor_info` failure remains
  `cpuUnavailable`. Do not fabricate a fresh percentage for either case.
- [ ] Run the focused tests and `swift test --filter SystemMetricsServiceTests`.
  Verify metadata survives the existing successful and failed snapshot copying
  paths; only repair a copying path if this addition exposes a loss. Leave
  the one-second service loop and visibility behavior unchanged.
- [ ] Self-review and commit only Task 1 files with
  `git commit -m "feat: collect cached CPU hardware information"`.
  Report RED/GREEN commands, commit, and any deviations. Request independent
  spec review then quality review before Task 2.

## Task 2: CPU presentation, information area, and live Settings wiring

**Files:**
- Create: `Sources/Needlbar/Settings/SettingsCPUInformationPresentation.swift`
- Create: `Sources/Needlbar/Settings/SettingsCPUInformationView.swift`
- Modify: `Sources/Needlbar/Settings/SettingsView.swift`
- Modify: `Sources/Needlbar/Settings/SettingsWindowController.swift`
- Create: `Tests/NeedlbarTests/SettingsCPUInformationTests.swift`
- Modify: `Tests/NeedlbarTests/SettingsStudioTests.swift`
- Reuse without unnecessary edits: `SettingsStudioComponents.swift`,
  `SystemDashboardDisplayComponents.swift` (`PerCoreActivityBars`).

- [ ] Write RED tests for a pure CPU display value plus observable
  `SettingsCPUInformationPresentation`, constructed/updated from
  `CombinedUsageSnapshot?`. Fixture expectations: fresh 25 → Usage 25%, Idle
  75%, original per-core values and availability timestamp; stale with last
  successful time T and attempt T+60 → Last known / T; unavailable with
  orphan percentage → no displayed number or bars; first tick
  `cpuWarmingUp` → warming up / no fabricated 0%; missing system → unavailable;
  hardware still shows when load is missing. Use existing snapshot test
  factories and hand-derived literal expectations.
- [ ] Write controller integration RED test: `update(snapshot:configuration:)`
  changes the CPU presentation as well as existing preview/provider state.
  Test snapshot updates remain independent of CPU visibility. Build the CPU
  info view into an NSHostingView to test accessible content at normal/minimum
  sizes and ensure existing controls/Alerts remain usable.
- [ ] Run `swift test --filter SettingsCPUInformationTests`, record expected RED.
- [ ] Implement the pure display derivation and `@MainActor ObservableObject`.
  Expose read-only display values (hardware, optional total/idle, core values,
  state label, optional successful time, reason). State is fresh only with
  valid usage plus `.fresh`; stale values require `.stale(lastSuccessfulAt:)`.
  `.unavailable`, absent availability, or missing system must not expose
  orphan percentages. Warmup reason comes from `cpuWarmingUp`, not merely
  hardware presence. Do not retain a second independent last-known cache.

```swift
switch availability {
case .fresh(let time) where cpu.totalUsage != nil:
    // Publish validated activity and time.
    successfulAt = time
case .stale(let time) where cpu.totalUsage != nil:
    // Publish retained activity, labeled Last known, and successful time.
    successfulAt = time
default:
    // Publish hardware only, no usage/idle/core values or successful time.
    successfulAt = nil
}
```

- [ ] Implement `SettingsCPUInformationView` using existing native section
  styling. The hardware header shows chip name (CPU fallback) and labeled
  physical/logical counts plus optional detected group line. Activity has
  prominent blue Usage, secondary Idle, accessible per-core bars, then a compact
  freshness/status line. No group labels on bars. Wrap hardware/metadata at
  narrow widths using vertical layout or `ViewThatFits`; unknown counts are
  omitted, not zero. Use semantic light/dark colors and monospaced digits.
- [ ] Own one presentation in `SettingsWindowController`, forward it through
  both `SettingsView` initializers using default-compatible optional arguments,
  and update it beside existing `preview.update` and quota update. In the
  shared scroll content, render only when `selectedPage == .module(.cpu)`:

```swift
if selectedPage == .module(.cpu) {
    SettingsCPUInformationView(presentation: cpuInformationPresentation)
}
detailPane
```

  Insert after the segmented picker and before `detailPane`, not solely in
  `SettingsStudioConfigurationPane`: Alerts has no display surface, and must
  still show the CPU summary. Preserve existing controls/Alerts copy and
  provider timer; add no CPU timers, tasks, collectors, or network calls.
- [ ] Run focused tests, `swift test --filter SettingsStudioTests`,
  `swift test --filter SystemMonitorSettingsViewTests`, and
  `swift test --filter SystemDashboardPopoverTests`.
- [ ] Render/capture normal (960×720) and minimum (760×560) CPU content in
  light/dark via native NSHostingView test rendering if no real window is
  accessible. Keep rendering helpers/test fixtures in tests; do not add app
  launch flags solely for screenshots or install another app. Clearly label
  fixture render versus installed-app inspection.
- [ ] Self-review and commit Task 2 files with
  `git commit -m "feat: show live CPU information in settings"`.
  Report tests and visual artifacts; request spec then quality review.

## Task 3: Final verification and handoff (main)

- [ ] Apply all important review fixes, with reproducing tests where needed.
- [ ] Run `source /Users/taejunoh/.cargo/env && make test`, logging output to
  `/tmp/needlbar-cpu-settings-final-test.log`; require exit 0. Run
  `git diff --check`; require no whitespace errors.
- [ ] Inspect rendered images and actual native CPU Settings if accessible;
  list unperformed real-device checks explicitly. A preview fixture is not
  proof of the installed public application's state.
- [ ] Update `docs/STATUS.md`, mark this plan's completed checkboxes, and record
  exact results/limits and continuation point. Final full-change independent
  review must pass. Keep branch ready for integration; no release or reinstall
  in this request.
