# Network Settings Information Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development
> or executing-plans to implement this plan. Steps use checkbox syntax.

**Goal:** Add an honest, compact read-only Network Settings card with existing
aggregate rates, reported interface names and existing-option-gated IP metadata.

**Architecture:** Retain one optional field from the existing native interface
set. Derive one MainActor presentation value from the existing combined stream.
Mount a Network-only card above controls on all tabs; derive IP visibility from
the current Dashboard tab and current configuration, never cached preferences.

**Tech Stack:** Swift, SwiftUI/AppKit, Combine, Darwin, Swift Testing, Make.

**Authoritative contract:**
`docs/superpowers/specs/2026-09-30-network-settings-information-design.md`.
This plan does not authorize push, PR, merge, installation or release.
Worktree: `/Users/taejunoh/.codex/worktrees/claude-statusline-hybrid/needlbar`.
Branch: `codex/network-settings-information`, based on Disk `b138836`.
Pre-implementation `make test` exited 0, explicit `MAKE_TEST_EXIT=0`, log
`/tmp/needlbar-network-settings-baseline-test.log`.

## Execution rules

Sequential implementation tasks, no concurrent builds. Workers own only the
listed files, preserve existing edits, use apply_patch, and receive full task
instructions rather than being asked to retrieve this plan. Each task has a
test-first implementer, independent spec review, then independent quality
review. Fix Important/Critical findings before proceeding. Root owns docs,
final native inspection and final project-wide verification. Reuse existing
isolated worktree; do not create an app bundle or touch the installed app.

Use `source /Users/taejunoh/.cargo/env` before Make. Focused Swift tests use
`make swift-test SWIFT_TEST_FILTER=SuiteName`; do not pipe filter expressions.
Retain build session and exit status. Full command:

```sh
source /Users/taejunoh/.cargo/env && make test > /tmp/needlbar-network-task-test.log 2>&1
network_test_exit=$?
printf '\nMAKE_TEST_EXIT=%s\n' "$network_test_exit"
exit "$network_test_exit"
```

### Task 1: Preserve reported interface names in Core

**Files (worker ownership):**

- Modify `Sources/NeedlbarCore/SystemMetrics/SystemMetricModels.swift`
- Modify `Sources/NeedlbarCore/SystemMetrics/MacSystemMetricsCollector.swift`
- Modify `Sources/NeedlbarCore/SystemMetrics/SystemMetricsService.swift`
- Modify `Tests/NeedlbarCoreTests/SystemMetricModelTests.swift`
- Modify `Tests/NeedlbarCoreTests/SystemMetricsServiceTests.swift`

- [ ] Add failing model tests: original initializer defaults to nil; explicit
  empty array remains empty; an explicit array survives unchanged. Representative:

```swift
let legacy = SystemMetricsSnapshot.Network(uploadBytesPerSecond: nil,
    downloadBytesPerSecond: nil, localIPAddresses: [], publicIPAddress: nil)
#expect(legacy.interfaceNames == nil)
let empty = SystemMetricsSnapshot.Network(uploadBytesPerSecond: nil,
    downloadBytesPerSecond: nil, localIPAddresses: [], publicIPAddress: nil,
    interfaceNames: [])
#expect(empty.interfaceNames == [])
let named = SystemMetricsSnapshot.Network(uploadBytesPerSecond: 128,
    downloadBytesPerSecond: 0, localIPAddresses: [], publicIPAddress: nil,
    interfaceNames: ["en0", "utun3"])
#expect(named.interfaceNames == ["en0", "utun3"])
```

- [ ] Extend existing fake-service fixtures/tests so public-IP disabled,
  enabled-success and enabled-failure reconstruction each preserve names.
  Success→whole-collector-throw must retain names and original successful
  Network timestamp. Reuse existing fake clock/collector conventions; avoid
  live getifaddrs or real addresses. Observe the focused tests fail because
  the field does not exist or is not preserved, not unrelated build errors.
- [ ] Add `public let interfaceNames: [String]?` and trailing
  `interfaceNames: [String]? = nil` initializer parameter; assign it directly.
- [ ] In collectNetwork's successful return add
  `interfaceNames: trafficInterfaces.sorted()`. Failure uses default nil.
  No additional query, filtering, builder, counters or baseline changes.
- [ ] In replacingPublicIP forward
  `interfaceNames: snapshot.network.interfaceNames`. Whole-record stale copy
  already preserves the field; do not change its policy.
- [ ] Focused model/service and existing conversion tests; full `make test`
  with an explicit exit marker. Inspect diff for incidental changes.
- [ ] Commit `feat: preserve reported network interface names`.
- [ ] Independent spec then quality review; repair and reverify if needed.

### Task 2: Derive and mount the Network Settings card

**Files (worker ownership):**

- Create `Sources/Needlbar/Settings/SettingsNetworkInformationPresentation.swift`
- Create `Sources/Needlbar/Settings/SettingsNetworkInformationView.swift`
- Create `Tests/NeedlbarTests/SettingsNetworkInformationTests.swift`
- Modify `Sources/Needlbar/Settings/SettingsView.swift`
- Modify `Sources/Needlbar/Settings/SettingsWindowController.swift`
- Modify `Tests/NeedlbarTests/SettingsStudioTests.swift`
- Modify `Sources/NeedlbarSettingsStudioReviewSupport/SettingsStudioReviewFixtures.swift`

**Presentation API:** Follow the existing CPU/RAM/Disk structure with
`SettingsNetworkInformationStatus` cases fresh(capturedAt),
stale(lastSuccessfulAt), unavailable; `SettingsNetworkInformationValue`
containing optional download/upload bytes-per-second, optional successfulAt,
status, optional normalized interfaceNames, namesOmitted Bool,
metadataIsStale Bool, validated localIPAddresses and optional publicIPAddress.
`SettingsNetworkInformationPresentation` is a public MainActor ObservableObject,
one `@Published private(set) var value`, compatible `init(snapshot: ... = nil)`
and `update(snapshot:)`. Internal value APIs need not be public.

- [ ] Add failing tests using existing combined/system fixture factories for
  fresh two rates, independent one rate, real zero, both nil, stale cross-day,
  unavailable/missing availability with orphan data, stale nil rates, missing
  system, success→unavailable→recovery clearing. Assert each data and timestamp
  field, not just state. Example expectations on a fixture with fresh rates:

```swift
#expect(presentation.value.downloadBytesPerSecond == 1_048_576)
#expect(presentation.value.uploadBytesPerSecond == 0)
#expect(presentation.value.successfulAt == capturedAt)
// After unavailable update with orphan rates:
#expect(presentation.value.downloadBytesPerSecond == nil)
#expect(presentation.value.uploadBytesPerSecond == nil)
#expect(presentation.value.successfulAt == nil)
```

- [ ] Test names independent of traffic: first-sample names with no rates,
  stale names/no rates, nil vs explicit [], missing-system clearing, trimming,
  case-sensitive dedup/sort, empty/control/over-64-UTF8-byte rejection,
  limit 16 with omission, nonempty-all-rejected becomes nil+omission. Duplicate
  collapse alone is not an omission warning. No truncation of identifiers.
- [ ] Test numeric IPv4/IPv6 validation and local ordered dedup: trim,
  empty/control/over-45-byte/malformed literals reject, documentation
  literals preserved, missing system clears, stale metadata marked. Use
  Darwin inet_pton (no DNS). No tests read actual user addresses.
- [ ] Implement derivation. Metadata stale is read from original availability
  independently of traffic eligibility. Traffic requires system + explicit
  fresh/stale availability + one nonnil rate. Missing/unavailable/both nil
  clears both rates and date. Fresh date uses capturedAt, stale date uses
  lastSuccessfulAt. No UI cache, task, timer, fetch or collection.
- [ ] Add pure `SettingsNetworkIPVisibility` value with explicit initializer
  `init(tab: SettingsStudioTab, localEnabled: Bool, publicEnabled: Bool)` and
  `showsLocalIP`, `showsPublicIP`. Both require tab == .dashboard plus their
  own current flag. Test all tabs and independent booleans, including true→
  false while retaining the same presentation payload. This helper is invoked
  from SettingsView body with current selectedTab/systemMonitorModel.value;
  no preferences or tab state in the snapshot DTO.
- [ ] Implement card using existing SettingsStudioSection, no fixed height.
  Download blue/Upload orange, labeled prominent monospaced rates, binary
  B/s units, 0 B/s distinct from —, adaptive horizontal/vertical layout.
  Full localized Traffic sampled/Last known traffic date; unavailable copy
  without inferred error/warmup. Test rate formatting zero/nil/1MiB/s and
  freshness text includes actual successful date and stale label.
- [ ] Wrapped reported-name text, explicit empty/unknown and omission note,
  Last known metadata text when stale. Scope explanation exactly from spec.
  IP rows only if current visibility helper permits; — for enabled unknown,
  middle-truncated monospaced display with full help/accessibility. Public
  row explains caching without lookup timestamp. IPs never logged/exported.
  Explicit accessibility labels/values and stale prefixes for all data.
- [ ] Inject optional default-compatible presentation into both SettingsView
  initializers; mount only `.module(.network)` below picker above controls on
  all tabs. Controller owns, injects, exposes internal networkInformationState
  and updates from the same stream regardless of visibility. No change to
  existing options, services, Alerts text or CPU/RAM/Disk behavior.
- [ ] Add controller test with Network visibility disabled on both surfaces:
  state updates, stale transition, missing-system clearing still occur.
- [ ] Extend existing guarded review fixture without renaming cpuSnapshot:
  download 1_048_576, upload 131_072, names en0/lo0/utun3, local 192.0.2.10 and
  2001:db8::10, public 198.51.100.10, explicit fresh Network availability.
  Do not add live collection, an endpoint or additional persistent bundle.
- [ ] If practical reuse existing attached NSHostingView screenshot test
  pattern for light, minimum dark long-name/IPv6, stale and unavailable cards;
  images are supplemental to assertions, not proof of functional content.
- [ ] Run focused Network, SettingsStudio, CPU/RAM/Disk tests; full make test
  with explicit status. Commit `feat: add Network information to Settings`.
- [ ] Independent spec then cumulative quality review, repair/reverify.

### Task 3: Root native and final verification

**Files (root ownership):** `docs/STATUS.md`, this plan and approved spec if
recording evidence or a justified deviation. No new implementation scope.

- [ ] Read computer-use skill and full runtime guide before native operations.
- [ ] Run existing `swift run NeedlbarSettingsStudioReview --settings-studio-review`
  with isolated defaults/inert fixtures. Use native app window inspection.
- [ ] Inspect light 960×720 and dark 760×560 Network card on all three tabs.
  Toggle Local/Public IP independently on Dashboard; confirm immediate hiding
  with same fixture, no addresses on Menu/Alerts with flags on. Check wrapped
  long names/IPv6 fixtures, visibility-off card retention, unchanged Alerts
  explanation and CPU/RAM/Disk negative mount checks. Read supported AX output.
  Do not claim actual VoiceOver, measured contrast or macOS 14 hardware proof.
- [ ] Close only fixture review windows and confirm process exit before builds.
- [ ] Read verification-before-completion skill; run final full make test,
  inspect explicit exit marker, current diff/status and contract test output.
- [ ] Update STATUS: exact commits/tests/native evidence, known collection
  limitations, privacy scope and unchanged installed/public release state.
- [ ] Commit docs, read finishing-a-development-branch skill and offer local
  merge into Disk / push+stacked PR / retain branch. No unauthorized mutation.
