# Dashboard readability and trustworthy metrics

Status: approved direction in the user's “진행해” following the screenshot comparison.

This amendment makes the v0.3 monitor usable at a glance on the user's Mac. It
overrides the earlier all-modules default title and exclusion of charts only to
permit a bounded, memory-only recent trend. Existing provider, export, widget,
notification, privacy, and panel dismissal contracts remain authoritative.

## Behavior

- One menu item has a conservative maximum width, measured using the real menu
  font. Start with CPU, RAM, and AI for new settings. Preserve saved choices and
  order, fit at most three selected summaries, and indicate overflow. If space
  is too narrow, show an accessible small Needlbar fallback. Full text belongs
  in the tooltip. The icon-only fallback retains a 22-point clickable target
  when a supplied budget is too small even for a glyph; it never disappears
  into a zero-width item. RAM and disk use percentages; large AI token values
  use B/M/K.
- The popover is approximately 360 points wide, height capped by the current
  screen, with fixed header/footer and scrollable sections. Use opaque adaptive
  system colors for legibility. CPU, RAM, disk, and battery have visual gauges;
  CPU cores have individual bars. Network and disk show labeled, contrasting
  read/write or upload/download trends using at most 60 recent samples in RAM.
  Missing and stale samples are gaps, never invented zeros or current readings.
- Keep all six sections and configured order. Main values are prominent;
  captions, dividers, and spacing establish hierarchy. Accessibility labels
  communicate both metric and value; color is supplemental.
- Reconcile the open popover on every combined update via an observable model,
  without presenting it again or losing disclosure/scroll state. Provider-only
  updates do not duplicate system samples. No additional timers or provider
  refreshes are created.
- Local IP display is optional, off by default. When enabled show the active
  IPv4 preferentially; additional addresses appear only in a disclosure. Public
  IP keeps its independent, existing explicit opt-in. Never log/export addresses.
- Provider rows explain their selected metric (tokens today, remaining, cost
  today, connection), include freshness, and use existing provider action
  policy rather than labeling every failure as Connect.

## Metric correction

### Approved AI-default follow-up — 2026-09-02

The user approved remaining subscription quota as the default AI value in both
the menu bar and dashboard, instead of today's token total. Reuse the existing
most-constrained quota selector and its availability rules. Missing quota must
remain unknown, not silently switch to tokens; existing provider actions remain
the source of truth (including Cursor Spending). Usage and estimated cost stay
available as explicit selections and in Analytics. Preserve valid persisted
choices when changing application defaults. Separately apply Remaining to the
current Mac's provider metric selections, without changing visibility/order.
No new provider endpoints, reset-time UI, or quota calculations are introduced.

The implementation follow-up is
`docs/superpowers/plans/2026-09-02-ai-remaining-default.md`.

### Native system metrics

Investigate current native collectors before changing formulas. Memory must
distinguish reclaimable cache from consumed physical memory and report actual
swap. Storage throughput must use real counter deltas or remain unavailable.
Battery health must compare compatible full-charge/design capacities; absence
is unavailable, never a fabricated 100%. Counter warmup/reset and unavailable
hardware remain explicit. Define units consistently in the implementation and
documentation; validate against native readings, not hardcoded Stats values.

Memory uses GiB/MiB (powers of 1024), with consumed memory excluding file-backed
and purgeable cache and Available as its physical-capacity complement. Storage
uses GB/TB and throughput KB/s/MB/s (powers of 1000), matching their decimal
labels. This explicitly amends the v0.3 spec's ambiguous binary-unit wording.

## Verification

Regression tests cover width budgets (including all providers and narrow
widths), saved preferences, fresh-only bounded trends, live updates, IP privacy,
provider actions, collector conversions and counter resets. Run make test once
the integrated source is stable, build the local package, inspect it natively,
and record the actual visual outcome. Native macOS 14 acceptance remains deferred.
