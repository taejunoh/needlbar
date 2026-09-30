# Disk Settings Information Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show system-volume capacity and backing-device Read/Write activity truthfully above existing Disk Settings controls.

**Architecture:** Preserve actual optional Total from the existing root-volume resource read with a pure signed-capacity validator. Derive a single Disk Settings presentation on the existing controller stream; no new collector, timer, cache, permissions or provider changes.

**Tech Stack:** Swift 6, Foundation/IOKit, Swift Testing, SwiftUI/AppKit, macOS 14 minimum.

## Execution contract

Approved spec: `docs/superpowers/specs/2026-09-30-disk-settings-information-design.md`.
Worktree: `/Users/taejunoh/.codex/worktrees/claude-statusline-hybrid/needlbar`.
Branch: `codex/disk-settings-information`, based on RAM `7546602`.
CPU PR #10 and RAM PR #11 remain separate dependencies, unchanged.
The user selected delegated implementation; execute continuously without
additional design gates. Fresh implementer per task, independent spec review
then quality review, resolve Important findings before continuing.
Workers are not alone; preserve others' edits. Main owns documentation.
No push, PR, merge, install, release, new worktree or persistent app bundle.

Build ownership is exclusive. Use `source /Users/taejunoh/.cargo/env && make
swift-test SWIFT_TEST_FILTER=SuiteName` for one focused suite at a time: Make
supplies fixture ABI. Do not use unquoted pipe-separated filters or direct
Swift tests against the restored production archive. Each task requires full
`make test` exit 0 before completion. Record RED failures before production.

- [x] Baseline full `make test`: exit 0, `/tmp/needlbar-disk-settings-baseline-test.log`.

## Task 1: Retain actual Total and validate native capacity

Ownership:
- Modify `Sources/NeedlbarCore/SystemMetrics/SystemMetricModels.swift` (DiskVolume only).
- Create `Sources/NeedlbarCore/SystemMetrics/DiskSnapshotBuilder.swift`.
- Modify `Sources/NeedlbarCore/SystemMetrics/MacSystemMetricsCollector.swift` (collectDisks only).
- Create `Tests/NeedlbarCoreTests/DiskSnapshotBuilderTests.swift`.
- Modify `Tests/NeedlbarCoreTests/SystemMetricModelTests.swift`.
- Modify `Tests/NeedlbarCoreTests/SystemMetricsServiceTests.swift` (Disk retention assertions).

- [x] Write failing tests for optional `totalBytes` and old initializer
  compatibility. Add builder tests: nil total/available, zero/negative total,
  negative or excessive available, positive Int.max, zero Used, zero Available.
  Literal valid case total 32768, available 8192 → Used 24576, Available 8192,
  actual Total 32768; independent rates initially nil.
- [x] Run builder/model tests and capture expected missing-symbol RED.
- [x] Add `public let totalBytes: UInt64?` and trailing initializer argument
  `totalBytes: UInt64? = nil`, preserving existing arguments and assignments.
- [x] Implement the exact small pure seam:

```swift
enum DiskSnapshotBuilder {
    static func make(name: String, totalCapacity: Int?, availableCapacity: Int?)
        -> SystemMetricsSnapshot.DiskVolume? {
        guard let totalCapacity, totalCapacity > 0,
              let availableCapacity, availableCapacity >= 0,
              availableCapacity <= totalCapacity else { return nil }
        return .init(name: name, usedBytes: UInt64(totalCapacity - availableCapacity),
            freeBytes: UInt64(availableCapacity), readBytesPerSecond: nil,
            writeBytesPerSecond: nil, totalBytes: UInt64(totalCapacity))
    }
}
```

- [x] In collectDisks, pass existing resource values into builder; nil → `[]`
  before existing counter reads. Remove current clamping. Keep single query,
  original name fallback, IORegistry query, rate conversion and baseline logic.
  Forward builder Used/Available/Total into final record with existing rates.
  No service production changes or partial native capacity records.
- [x] Extend success→failure service fixture with Total 10000, Used 8000,
  Available 2000, Read 10, Write 5. Distinct failed-attempt time must preserve
  all fields and successful stale date. Use existing clock injection.
- [x] Run builder/model/conversion/service suites, full `make test`, self-review,
  commit Task 1 only as `feat: retain and validate system volume capacity`.
- [x] Independent spec review, then quality review; resolve findings.

## Task 2: Disk card, presentation and native fixtures

Ownership:
- Create `Sources/Needlbar/Settings/SettingsDiskInformationPresentation.swift`.
- Create `Sources/Needlbar/Settings/SettingsDiskInformationView.swift`.
- Modify `Sources/Needlbar/Settings/SettingsView.swift` and `SettingsWindowController.swift`.
- Create `Tests/NeedlbarTests/SettingsDiskInformationTests.swift`.
- Modify `Tests/NeedlbarTests/SettingsStudioTests.swift`.
- Modify `Sources/NeedlbarSettingsStudioReviewSupport/SettingsStudioReviewFixtures.swift`.
- Modify `Sources/NeedlbarSettingsStudioReview/main.swift` only if fixture wiring requires it.

- [ ] Write RED presentation/controller tests, using RAM/CPU pattern. Fixture
  Total 1 TiB, Used 768 GiB, Available 256 GiB →75%; Read 12 MiB/s, Write
  3 MiB/s, Macintosh HD, successful T. Assert all literal values/date.
  Cover stale T vs attempt T+60 and cross-day formatted date; missing system,
  missing disk/availability, unavailable orphan, transition clearing; old nil
  Total vs explicit zero; nil Used, Used>Total, Available>Total, mismatch,
  overflow, all-zero denominator; zero/nil/one-sided rates; trimmed/empty/
  control-character/long names; disabled surface toggles still update card.
- [ ] Capture missing presentation/view RED before implementation.
- [ ] Add MainActor ObservableObject presentation with one published derived
  DTO, default-compatible initializers; update only from controller's existing
  CombinedUsageSnapshot stream. Use disks.first, never infer Total or cache.
  Name trims whitespace; empty/control characters →System volume. Missing
  record clears name/Total. Positive Total and valid name can survive current
  unavailable input; dynamics cannot. Explicit Total 0 suppresses dynamics.
  Usable dynamics require fresh/stale availability and nonnil Used≤known
  Total. Invalid Available alone becomes nil. Rates independently optional.
  Percent uses checked positive Used+Available; known Total additionally
  requires bounds and exact sum. Missing Total may yield percent but not Total.
  Dates come only from fresh capturedAt/stale lastSuccessfulAt after usable
  data guard, not snapshot date. Unavailable clears all dynamic fields/date.
- [ ] Add Disk-only card below picker and above controls on all tabs. Native
  section styling, System volume (/), wrapped display name, labeled Total,
  cyan prominent percent and compact capacity bar with Used/Available labels,
  Read blue/Write orange compact labeled rates, monospaced binary units,
  genuine `0 B/s`, unknown `—`. Whole stale dynamics explicitly Last known;
  successful full localized date/time. Short backing-device scope help.
  Explicit accessibility labels/values; preserve Alerts explanation, CPU/RAM
  cards and controls. No space-based health warning or unrelated refactor.
- [ ] Add deterministic Disk to existing inert CPU/RAM review snapshot with
  fresh Disk availability; keep guarded executable and isolated defaults.
  Add attached native rendering tests/helpers following existing RAM tests,
  writing ephemeral PNGs under `/tmp/needlbar-disk-settings-review` only.
- [ ] Run Disk/Settings Studio/CPU/RAM focused suites, all Swift tests and
  full `make test`. Inspect light/dark, stale/unavailable, narrow long-name
  PNGs. Self-review and commit Task 2 as `feat: add Disk information to Settings`.
- [ ] Independent spec review followed by cumulative quality review; fix and
  re-review Important findings before final verification.

## Final verification and handoff (main)

- [ ] Native guarded review only: light 960×720 and dark 760×560 content
  windows, all Disk tabs, visibility off, wrapping, CPU/RAM negative placement,
  available accessibility tree. Close review process before builds. Report
  tool/VoiceOver/macOS14/native failure-injection limits without overclaiming.
- [ ] Root fresh full `make test` exit 0; `git diff --check`; confirm bounded
  diff and independent review conclusions. Preserve unrelated shared-rate
  boundary and stale-service limitations; no opportunistic fix.
- [ ] Update STATUS and checkboxes with commits/logs/evidence, commit docs,
  offer integration choice. Installed v0.3.6 and public releases untouched.
