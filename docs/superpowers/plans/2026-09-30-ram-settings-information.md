# RAM Settings Information Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show truthful RAM capacity, live usage, compressed/Wired details, OS pressure, and sample freshness above existing Settings controls.

**Architecture:** Extend the existing Swift memory snapshot with three optional fields, normalizing the already-read VM counters in a small pure builder. Add a focused RAM Settings presentation/view on the existing controller update stream. No process enumeration, new timer/collector, or Rust changes.

**Tech Stack:** Swift 6, existing Darwin VM read, Swift Testing, SwiftUI/AppKit; macOS 14 minimum.

---

## Context, ownership, and verification setup

Worktree: `/Users/taejunoh/.codex/worktrees/claude-statusline-hybrid/needlbar`
Branch: `codex/ram-settings-information`
CPU dependency/base: `524e05c`, separate open CPU PR #10.
Approved spec: `docs/superpowers/specs/2026-09-30-ram-settings-information-design.md`.
The user has approved the written spec and chosen delegated implementation
through AGENTS. Execute all tasks continuously, sequentially, with independent
spec review followed by quality review between implementation tasks.

Task 1 owns Core memory model/normalization/collector/tests. Task 2 owns RAM
Settings presentation/view/wiring/review fixtures/tests. Main owns documents
and final verification. Workers are not alone; preserve others' edits.
No new worktree, app bundle installation, push, merge, or release in this plan.

Use `source /Users/taejunoh/.cargo/env && make swift-test
SWIFT_TEST_FILTER=SuiteName` for narrow tests (one shell command/one filter).
The repository target supplies the test-only Rust fixture ABI and restores
the production archive afterward. Direct `swift test` after production archive
restoration may fail to link fixture symbols. Do not use a shell `|` in the
unquoted Make filter. Run unfiltered `make swift-test` for all Swift suites.
Builds must not overlap with other builds or the native review executable.

## Task 1: Preserve physical capacity and normalize existing VM details

**Files:**
- Modify: `Sources/NeedlbarCore/SystemMetrics/SystemMetricModels.swift` (Memory only)
- Create: `Sources/NeedlbarCore/SystemMetrics/MemorySnapshotBuilder.swift`
- Modify: `Sources/NeedlbarCore/SystemMetrics/MacSystemMetricsCollector.swift` (memory only)
- Create: `Tests/NeedlbarCoreTests/MemorySnapshotBuilderTests.swift`
- Modify: `Tests/NeedlbarCoreTests/SystemMetricModelTests.swift`
- Modify: `Tests/NeedlbarCoreTests/SystemMetricsServiceTests.swift` (memory preservation assertion)
- Reuse unchanged: `SystemMetricConversions.memoryUsage`; its formula remains authoritative.

- [ ] Write RED tests for source-compatible initializer defaults and pure
  `MemorySnapshotBuilder.make(physicalMemory:pageSize:counters:)`. Define
  internal nested `Counters` with six UInt64 properties: `active`, `inactive`,
  `wired`, `compressed`, `purgeable`, `fileBacked`. Expectations are literal:

```swift
@Test func vmDetailsDoNotDoubleCountUsedMemory() {
    let memory = MemorySnapshotBuilder.make(physicalMemory: 32_768,
        pageSize: 4_096, counters: .init(active: 3, inactive: 2,
        wired: 2, compressed: 1, purgeable: 1, fileBacked: 1))
    #expect(memory.totalBytes == 32_768)
    #expect(memory.usedBytes == 24_576)
    #expect(memory.freeBytes == 8_192)
    #expect(memory.wiredBytes == 8_192)
    #expect(memory.compressedBytes == 4_096)
}

@Test func missingVMStatsPreservesOnlyCapacity() {
    let memory = MemorySnapshotBuilder.make(physicalMemory: 32_768,
        pageSize: nil, counters: nil)
    #expect(memory.totalBytes == 32_768)
    #expect(memory.usedBytes == nil)
    #expect(memory.compressedBytes == nil)
    #expect(memory.wiredBytes == nil)
    #expect(memory.swapUsedBytes == nil)
    #expect(memory.pressure == nil)
}
```

  Additional cases: nil/zero page size; absent counters; zero physical total;
  aggregate subtraction/overflow/exceeds-total failure (Total only); genuine
  zero Used/details; detail >Total while original aggregate remains valid;
  detail multiplication overflow while original aggregate remains valid
  (wired=purgeable=UInt64.max, other counters=0). Missing optional detail must
  not invalidate valid Used/Available. Old initializer omits all three fields.
- [ ] Run the builder/model suites with `make swift-test` and record RED
  failure for missing fields/builder before writing production code.
- [ ] Add `totalBytes`, `compressedBytes`, `wiredBytes: UInt64?` to Memory
  with defaulted trailing initializer parameters. Preserve all old fields:

```swift
public init(usedBytes: UInt64?, freeBytes: UInt64?,
            swapUsedBytes: UInt64?, pressure: String?,
            totalBytes: UInt64? = nil, compressedBytes: UInt64? = nil,
            wiredBytes: UInt64? = nil) {
    self.usedBytes = usedBytes
    self.freeBytes = freeBytes
    self.swapUsedBytes = swapUsedBytes
    self.pressure = pressure
    self.totalBytes = totalBytes
    self.compressedBytes = compressedBytes
    self.wiredBytes = wiredBytes
}
```

- [ ] Implement the small internal pure builder. No query closures or public
  native API additions are needed. Its contract is:

```swift
enum MemorySnapshotBuilder {
    struct Counters {
        let active, inactive, wired, compressed, purgeable, fileBacked: UInt64
    }

    static func make(physicalMemory: UInt64, pageSize: UInt64?,
                     counters: Counters?) -> SystemMetricsSnapshot.Memory {
        let total = physicalMemory > 0 ? physicalMemory : nil
        let unavailable = SystemMetricsSnapshot.Memory(usedBytes: nil,
            freeBytes: nil, swapUsedBytes: nil, pressure: nil, totalBytes: total)
        guard let total, let pageSize, pageSize > 0, let counters,
              let usage = SystemMetricConversions.memoryUsage(
                physicalMemoryBytes: total, pageSize: pageSize,
                activePages: counters.active, inactivePages: counters.inactive,
                wiredPages: counters.wired, compressedPages: counters.compressed,
                purgeablePages: counters.purgeable,
                fileBackedPages: counters.fileBacked) else { return unavailable }
        return .init(usedBytes: usage.usedBytes, freeBytes: usage.availableBytes,
            swapUsedBytes: nil, pressure: nil, totalBytes: total,
            compressedBytes: detailBytes(counters.compressed,
                pageSize: pageSize, total: total),
            wiredBytes: detailBytes(counters.wired, pageSize: pageSize, total: total))
    }

    private static func detailBytes(_ pages: UInt64, pageSize: UInt64,
                                    total: UInt64) -> UInt64? {
        let result = pages.multipliedReportingOverflow(by: pageSize)
        return !result.overflow && result.partialValue <= total
            ? result.partialValue : nil
    }
}
```

  Reuse `SystemMetricConversions.MemoryUsage` unchanged.
- [ ] Capture physicalMemory once at the beginning of `collectMemory`.
  Replace early stats/page-size returns with the builder's Total-only result.
  On successful stats/page-size, map the existing six VM counters into the
  builder. If its Used is nil, return it without swap/pressure reads. Otherwise
  retain existing swap/pressure calls and forward all three added fields:

```swift
return .init(usedBytes: memory.usedBytes, freeBytes: memory.freeBytes,
    swapUsedBytes: collectSwapUsedBytes(), pressure: collectMemoryPressure(),
    totalBytes: memory.totalBytes, compressedBytes: memory.compressedBytes,
    wiredBytes: memory.wiredBytes)
```

  Keep existing helper names without renaming them. Do not use uncompressed logical
  compressor counters. Memory availability still depends on Used, not Total.
- [ ] Extend existing fake-service success→failure coverage with nonnil Total,
  Compressed, Wired values and assert stale snapshots preserve them and the
  successful availability timestamp. Keep whole-struct copy paths unchanged
  unless a test exposes loss. Add no native-failure flags to production.
- [ ] Run builder, model, conversion and service suites, then `make test`
  (including all Swift suites); require exit 0 before calling Task 1 complete.
  Report honest native-limit distinction: pure builder failure tests are not
  injected real Mach failures. Self-review; commit only Task 1 files as
  `feat: retain RAM capacity and VM memory details`. Request independent spec
  review, then quality review; resolve Important issues before Task 2.

## Task 2: RAM information card and existing Settings update stream

**Files:**
- Create: `Sources/Needlbar/Settings/SettingsRAMInformationPresentation.swift`
- Create: `Sources/Needlbar/Settings/SettingsRAMInformationView.swift`
- Modify: `Sources/Needlbar/Settings/SettingsView.swift`
- Modify: `Sources/Needlbar/Settings/SettingsWindowController.swift`
- Create: `Tests/NeedlbarTests/SettingsRAMInformationTests.swift`
- Modify: `Tests/NeedlbarTests/SettingsStudioTests.swift`
- Modify: `Sources/NeedlbarSettingsStudioReviewSupport/SettingsStudioReviewFixtures.swift`
- Modify: `Sources/NeedlbarSettingsStudioReview/main.swift`
- Reuse: native section styling, CPU presentation/controller pattern and
  existing binary byte formatting where its access level permits. Do not
  refactor unrelated Overview/CPU formatting simply to share a helper.

- [ ] Write RED presentation/controller tests. Fixture: actual Total 48 GiB,
  Used 36 GiB, Available 12 GiB, Compressed 8 GiB, Wired 6 GiB, Swap 2 GiB,
  pressure normal, successful T. Expect 75% (not Used+details), all details
  visible, Total independent, and original timestamp T. Zero is real; nil is
  unknown. Older snapshots with no Total can derive a valid percentage from
  Used+Available but do not display inferred physical Total. Cases: stale
  T with attempt T+60; same time on two different dates; nil system;
  unavailable/missing availability with orphan values; fresh→unavailable
  update; pressure missing/warning/critical; missing Available; zero/overflow
  denominator; mismatched Total; Used>Total; Used nil with Total; stale
  availability without usable Used; high percentage with normal pressure.

```swift
let presentation = SettingsRAMInformationPresentation(snapshot: freshFixture)
#expect(presentation.value.usedPercent == 75)
#expect(presentation.value.totalBytes == 51_539_607_552)
#expect(presentation.value.compressedBytes == 8_589_934_592)
presentation.update(snapshot: unavailableFixture)
#expect(presentation.value.usedPercent == nil)
#expect(presentation.value.usedBytes == nil)
#expect(presentation.value.successfulAt == nil)
#expect(presentation.value.totalBytes == 51_539_607_552)
```

  Construct full CombinedUsageSnapshot test fixtures from existing CPU helpers;
  test the controller's updated presentation state even with RAM visibility off.
- [ ] Run `make swift-test SWIFT_TEST_FILTER=SettingsRAMInformationTests`;
  record expected RED for missing presentation before production edits.
- [ ] Implement the pure display value and `@MainActor ObservableObject`
  presentation, following CPU's default-compatible injection pattern. Public
  class only if necessary for public SettingsView initializer; keep DTO internal.
  Display fields are independently optional Total/Used/Available/Compressed/
  Wired/Swap bytes, `usedPercent: Double?`, raw normalized `pressure: String?`,
  `successfulAt: Date?`, and fresh/stale/unavailable state. Derive a `stateLabel`
  for native UI text from that state without storing a second status cache.
  Store one published value; no new tasks, collector or last-known cache.
  Dynamic eligibility requires `.fresh` or `.stale` and nonnil Used, no greater
  than valid positive Total. Other fields remain independently optional.
  Percentage uses checked Used+Available >0, and requires sum==Total where
  known; otherwise nil/no bar. Malformed new details beyond Total become nil.
  Stale keeps successful T and an explicit Last known state for all dynamic
  values including pressure. Unavailable/absent availability hides every
  dynamic value/time; independently valid Total may remain. No RAM warmup.

```swift
let sum = used.addingReportingOverflow(available)
if !sum.overflow, sum.partialValue > 0,
   totalBytes == nil || totalBytes == sum.partialValue {
    usedPercent = 100 * Double(used) / Double(sum.partialValue)
} else {
    usedPercent = nil
}
```

- [ ] Implement one responsive native section. Show labeled Total, prominent
  purple used percentage, Used/Available and labeled usage bar, then a compact
  Compressed/Wired/Swap group, labeled OS pressure, and full successful date/time.
  Reuse the existing section shape/spacing; wrap values at narrow widths. Help
  text explains details overlap Used and Swap is disk-backed. Pressure uses
  Normal green / Warning orange / Critical red plus text; Unknown never green.
  Unavailable shows dashes, not zero. Use monospaced digits and explicit
  accessibility labels on values/bar. No additive compressed/Wired stack.

```swift
SettingsStudioSection(title: "RAM information") {
    VStack(alignment: .leading, spacing: 9) {
        HStack {
            Text("Total")
            Spacer()
            Text(bytesText(value.totalBytes)).monospacedDigit()
        }
        Text(value.usedPercent.map {
            "\($0.formatted(.number.precision(.fractionLength(0))))% used"
        } ?? "— used")
        .font(.title2.bold()).foregroundStyle(.purple).monospacedDigit()
        if let percent = value.usedPercent {
            ProgressView(value: percent, total: 100).tint(.purple)
                .accessibilityLabel("Used versus available memory")
        }
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
            GridRow { Text("Used"); Text(bytesText(value.usedBytes)) }
            GridRow { Text("Available"); Text(bytesText(value.availableBytes)) }
            GridRow { Text("Compressed"); Text(bytesText(value.compressedBytes)) }
            GridRow { Text("Wired"); Text(bytesText(value.wiredBytes)) }
            GridRow { Text("Swap"); Text(bytesText(value.swapUsedBytes)) }
        }.monospacedDigit()
        Text("Pressure: \(value.pressure?.capitalized ?? "Unknown")")
            .foregroundStyle(pressureColor(value.pressure))
        Text(value.successfulAt.map {
            "\(value.stateLabel) · \($0.formatted(date: .abbreviated, time: .shortened))"
        } ?? "Memory usage unavailable")
        .font(.caption).foregroundStyle(.secondary)
        Text("Compressed and Wired are included in Used. Swap uses disk space.")
            .font(.caption).foregroundStyle(.secondary)
    }.padding(.vertical, 11)
}

private func pressureColor(_ pressure: String?) -> Color {
    switch pressure {
    case "normal": return .green
    case "warning": return .orange
    case "critical": return .red
    default: return .secondary
    }
}

private func bytesText(_ bytes: UInt64?) -> String {
    guard let bytes else { return "—" }
    let units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB"]
    var amount = Double(bytes)
    var index = 0
    while amount >= 1024 && index < units.count - 1 {
        amount /= 1024
        index += 1
    }
    return "\(amount.formatted(.number.precision(.fractionLength(index == 0 ? 0 : 1)))) \(units[index])"
}
```

  This gives the complete minimal native content; group the detail rows
  responsively for a compact card without changing their semantics or inventing
  additional information. Do not add a generic dashboard framework.
- [ ] Own one RAM presentation in SettingsWindowController and update beside
  preview/CPU/quota updates. Forward through both SettingsView initializers
  with optional default-compatible arguments and mount before detailPane:

```swift
if selectedPage == .module(.memory) {
    SettingsRAMInformationView(presentation: ramInformationPresentation)
}
```

  `.memory` is the existing MonitorModuleID case displayed as RAM. Preserve
  all CPU and RAM controls and Alerts copy.
- [ ] Add inert RAM fixture to existing review support: 48/36/12 GiB,
  Compressed 8, Wired 6, Swap 2 GiB, normal pressure, fresh timestamp.
  Use it in both initial and configuration-change combined snapshots so
  visibility toggles do not erase the card. Existing launch guard and isolated
  defaults remain unchanged. No live collection/provider access in review.
- [ ] Run focused RAM/Settings suites, SystemMonitorSettingsViewTests and
  SystemDashboardPopoverTests, then `make test` (including all Swift suites);
  require exit 0 before calling Task 2 complete. Capture attached-native-
  window light/dark RAM card PNGs using test-only helpers (CPU helper is the
  proven pattern; detached hosting-view cache alone produced invalid images).
  Report exact artifact paths, inspect real pixels, and do not call PNG width
  tests an accessibility or clipping pass. Self-review; commit Task 2 only as
  `feat: show RAM information in settings`. Request spec then quality review.

## Task 3: Final verification and documentation (main)

- [ ] Apply all Important review fixes with failing regression tests where
  appropriate; obtain final full-feature independent approval.
- [ ] Run `swift run NeedlbarSettingsStudioReview --settings-studio-review`
  with the existing guarded executable, no packaging. Native-inspect RAM at
  960×720 light and 760×560 dark, all three tabs, visibility-off retention,
  pressure/text, wrapping/help/accessibility where supported; CPU remains
  correct and other pages do not display RAM's card. Close review windows
  before build/test cleanup. Mark fixture evidence distinct from installed app.
- [ ] Run final `source /Users/taejunoh/.cargo/env && make test` with output
  `/tmp/needlbar-ram-settings-final-test.log`; require exit 0. Also require
  `git diff --check`. No silent omission of failing tests or native limitations.
- [ ] Update STATUS and this plan's checkboxes/results, commit documentation.
  Installed app, CPU PR #10 and public release remain unchanged. Present the
  finishing-branch integration choices; keep the reused worktree until chosen.
