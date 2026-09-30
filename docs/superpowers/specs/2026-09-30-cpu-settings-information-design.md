# CPU Settings Information

Date: 2026-09-30
Scope: Settings → SYSTEM → CPU only
State: Proposed layout approved in conversation; written-spec review pending.

## Problem and approved direction

CPU collection already supplies total and per-core usage to the dashboard.
Settings currently exposes only surface visibility controls, so selecting CPU
does not explain the hardware or its current state. The user approved adding
hardware information, live usage, and sample freshness above those controls.
This is a deliberate CPU-only extension to the approved Settings Module Studio
design, not a redesign of other modules or provider connections.

## Screen contract

Keep the existing sidebar, CPU title, and Menu bar / Dashboard / Alerts tabs.
Below the tabs and above the selected surface's controls, show one read-only
CPU information area on every CPU tab:

1. Hardware summary: detected CPU/chip name; physical and logical core counts
   with explicit labels; detected core-group names and physical counts when
   available. Hide unknown group details rather than inventing them.
2. Current activity: prominent total Usage percentage, subordinate Idle
   percentage, and compact per-core bars. Use the existing CPU blue accent;
   separate hardware and activity with spacing and clear section labels.
3. Freshness: last successful sample time, or a concise explanation when
   activity is warming up, stale, or unavailable.

The existing menu-bar/dashboard visibility controls remain below this area.
Alerts still truthfully states that system threshold alerts are unavailable;
the information area does not imply alert support. No new fourth tab is added.
The page scrolls at the existing minimum window size rather than clipping.

The actual machine reports Apple M5 Pro, 15 physical and logical cores, and
groups named Super (5) and Performance (10). These are examples, not constants.
Do not assume an Efficiency/Performance-only architecture, or associate a
per-core bar with a hardware group without a verified core mapping.

## Data boundaries

- Extend the normalized Swift Core CPU snapshot with optional hardware
  metadata. Existing callers and fixtures can omit it; existing decoding must
  remain compatible with snapshots that lack the new fields.
- Read hardware through bounded native sysctl queries in the macOS collector
  layer. Cache successful/static hardware discovery for the collector lifetime;
  do not launch shell commands or repeat hardware probes every second.
- Hardware fields are independently optional and validate positive core
  counts. A failed hardware query must not prevent activity collection, and
  valid hardware may display before the first activity delta is available.
- Continue the existing SystemMetricsService collection loop and the existing
  CombinedUsageSnapshot delivery into Settings. The Settings information view
  derives presentation from the delivered snapshot only.
- Presentation formatting belongs in the Settings layer. Reuse existing
  normalized percentages and freshness semantics; add no Rust/bridge logic.

Likely touch points are the system metric models and macOS collector in
`Sources/NeedlbarCore`, and a focused CPU information presentation/view in
`Sources/Needlbar/Settings` integrated into `SettingsStudioConfigurationPane`.
Keep the existing snapshot injection through `SettingsView` and
`SettingsWindowController`; only add wiring if necessary.

## Unavailable and stale states

- The first tick has no prior CPU counters. Show a warming-up state and `—`
  usage, not fabricated 0% usage or 100% idle.
- With fresh valid activity, Idle is 100 minus total Usage. All percentages
  retain existing validation and formatting.
- Retained activity may display only when it has a known successful sample
  time, clearly labeled Last known. Never label a failed collection attempt's
  timestamp as the last successful sample.
- With no retained activity, show `—` and the unavailable explanation. Hardware
  information remains visible if independently known.
- Unavailable core metadata is not inferred from an empty per-core array.
  Per-core bars use the sampled array, without unsupported group labels.
- A Settings visibility toggle must not stop CPU background collection.

## Exclusions

No RAM, Disk, Network, Battery, or provider page changes; no new refresh timer,
network request, credential access, authentication flow, or browser action.
No temperature, clock speed, top-process list, new chart history, interval
picker, styling options, thresholds, or CPU alert implementation. No release,
push, reinstall, or duplicate application bundle creation is part of this
design-review step. Maintain the macOS 14 deployment target.

## Verification and acceptance

1. Hardware decoding/query tests cover complete, partial, unsupported, and
   malformed values; group names are data-driven. Existing snapshot fixtures
   and callers remain compatible.
2. Presentation tests cover fresh usage/idle, per-core samples, initial
   warmup, stale retained values, absent values, and distinct successful versus
   failed-attempt timestamps.
3. Settings tests confirm CPU information appears on CPU tabs only, controls
   retain their persistence/meaning, Alerts does not claim threshold support,
   and opening or switching Settings does not start a collection loop.
4. Run focused tests during implementation, then require `make test` exit 0.
5. Inspect the real CPU Settings window at normal and minimum sizes, in light
   and dark appearances where the native inspection surface permits it. Check
   wrapping, contrast, labels, and accessibility text for the per-core bars.
   Report any native checks that cannot be performed; test success is not a
   substitute for visual verification.
6. Update `docs/STATUS.md` with results and the next continuation point. Do
   not claim the installed public app contains this feature until a separately
   verified installation has occurred.

## Next step

After written-spec approval, prepare a CPU-only implementation plan with
test-first tasks, explicit file ownership, and independent review. Implement
and verify CPU before proposing the next SYSTEM page.
