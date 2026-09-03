# Two-line menu-bar readability

**Date:** 2026-09-03

**Status:** Visual direction A approved by the user (“A안 괜찮네”); written
specification awaiting review before implementation planning.

## Purpose and authority

Make Needlbar's menu-bar values as easy to scan as the user's Stats reference:
small labels above prominent numbers, rather than a sentence of equally
weighted labels and values. The approved comparison uses `CPU / 24%`,
`RAM / 72%`, and `Claude / 8%`. These are synthetic examples, not live values.

This amends only the adaptive menu-bar presentation from
`2026-09-02-dashboard-readability-design.md`. That document's width limits,
configuration defaults, overflow handling, and metric semantics remain in
force. The Fable design's exact headline exclusion remains in force. The
browser preview approves visual hierarchy, not native font metrics or a
guaranteed 160-point width / 28-point height.

## Approved appearance

- Each visible module is a column: a small regular label above a larger,
  semibold value. Align the label and value to the same leading edge.
- Use native system fonts and monospaced digits. Begin native tuning around
  7.5-point labels and 11-point values; measure actual glyph/line bounds before
  accepting these sizes. Do not shrink text indefinitely to force a fit.
- Separate modules with consistent horizontal gaps, not `·` separators.
  Begin with 8-point gaps and symmetric outer padding, included in measurement.
- System labels remain CPU, RAM, Disk, NET, and BAT. For the AI module, show
  the name of the provider selected by the existing logic, such as Claude,
  instead of the redundant `AI CL`. Do not add extra provider slots or change
  provider selection. When no provider is selected, retain neutral `AI`.
- Use monochrome system-tinted foregrounds without a custom background. Small
  labels and heavier values establish hierarchy; color is not required.
- This is the new default presentation, not an additional style setting.
  The alternative single-line design is not a user-selectable new feature.

## Space and stability

Keep exactly one existing `NSStatusItem`, configured order, and a maximum of
three selected top-level modules. The effective width ceiling remains the
smaller of 240 points and the current available-width estimate. This estimate
does not guarantee visibility against every arrangement of other apps' items.

Try the selected prefix in two-line form first. If it is too wide, apply the
existing compact-spelling and prefix-reduction policy with an overflow
indicator. Omitted modules remain represented by that indication and the full
tooltip (or by the existing accessible icon fallback). If
native height cannot hold both lines legibly, use a measured single-line
fallback with the same values/order. If no meaningful text layout fits, use
the existing accessible Needlbar icon fallback. Its minimum 22-point clickable
width is retained even when the reported budget is smaller; 22 is not a
hardcoded menu-bar height.

Derive vertical space from the actual button bounds. Neither line, including
percent signs, direction arrows, and unit suffixes, may be clipped or overlap.
Measure the same fonts and padding used to draw. Never truncate digits or units
to manufacture a fit.

Reserve deterministic value widths by metric family, not by the latest value's
string width. Unknown and stale states use the same reservation as fresh data.
The finite baseline envelopes to lock down in layout tests are `100%` for
percentages, the widest compact token string through `999.99B`, a grouped
currency string through `$999,999.99`, and the widest compact network rate
through `999.9G` independently for each direction. Measure suffix alternatives
rather than assuming one letter is widest. Connection status reserves the
widest existing status word. Include the actual label width in each column.

These reservations are finite. A longer valid value expands its required
width and goes through normal fitting/overflow handling; it is not clipped,
rounded differently, or replaced with a fabricated number. Configuration,
provider, screen geometry, or an out-of-envelope value may therefore change
layout. Ordinary percentage changes, compact-unit changes inside the reserved
envelope, and unavailable-to-fresh transitions must not shift neighboring
columns. Do not retain a historical maximum or add persistent layout state.

## Value and failure semantics

- CPU, RAM, disk, battery, and AI Remaining keep current integer-percentage
  formatting and meaning. Missing values stay `—`, never zero.
- AI Usage keeps current K/M/B token formatting; Cost keeps the existing USD
  currency formatter, including grouping and precision. No new currency
  abbreviation or metric calculation is introduced.
- Connection keeps the existing Connected, Stale, Sign in, Unavailable, and
  Error meanings. A shorter label is not permission to infer a new state.
- Network remains one module with both upload and download on its value row.
  Preserve compact transfer formatting and visible `↑` / `↓` direction glyphs;
  independently reserve the two values. This task adds no colored dots or
  additional menu-bar item.
- Last-known-good values and existing freshness rules remain unchanged.
  Preserve current tooltip semantics and full, uncropped text for modules that
  do not fit. Do not add a new refresh trigger, freshness calculation, or poll.
- Claude Fable stays out of the menu-bar headline and tooltip, as before.
  Its separate dashboard child is unchanged.

## Architecture and native interaction

Keep the existing normalized snapshot/configuration inputs. Extend the pure
presentation boundary to return structured label/value segments and fitting
decisions; do not parse the old joined title to recover module identity. Keep
text output available for the fallback, tooltip, accessibility, and existing
legacy consumers. No AppKit code belongs in NeedlbarCore or the Rust bridge.

Render the approved monochrome layout into a template `NSImage` on the existing
`NSStatusBarButton` in image-only mode. AppKit owns foreground tint and native
pressed/selected appearance. Do not bake desktop/background colors into the
image. Native drawing remains in a focused presentation helper, separate from
pure fitting/formatting and controller lifecycle.

Regenerate the image for changed displayed content, relevant button geometry,
backing scale, or effective appearance. An optional cache must be bounded and
keyed by those inputs, not by unbounded snapshot history. Prevent size-change
feedback loops by reassigning geometry only when the chosen size changes.

Retain the same native button, target/action, click handling, tooltip,
accessibility element/label, and panel anchor source. An image must not make
the button unnamed to accessibility. Do not introduce child hit-test regions,
replace the button with a custom window, or change outside-click dismissal.
An image creation failure falls back to existing text/icon behavior.

## Scope boundaries

No settings migration, visibility/order change, new metrics, provider refresh,
authentication action, collector formula, dashboard redesign, widget,
notification, export, analytics, or release change is included. Saved user
choices stay intact. No new dependency, web font, runtime browser, or helper
service is needed. Do not restart or alter the separate public-release app
when verifying the development build.

## Verification and acceptance

1. Test pure segment output, provider identity, configured prefix/order,
   max-three selection, overflow, and tooltip completeness. Preserve the
   exact Fable headline exclusion and independent Usage/Quota behavior.
2. Test percentage 0/9/10/99/100, missing and stale transitions, token unit
   boundaries, currency grouping, connection words, both network directions,
   long values, width budgets through 240, and the 22-point icon exception.
   Verify neighboring positions remain stable within each envelope.
3. Test native measured bounds and image output at supported backing scales,
   sufficient/insufficient heights, geometry/appearance changes, and fallback
   transitions. Exercise image-to-text-to-image cleanup, target/action,
   tooltip/AX, and unchanged panel anchoring/dismissal seams.
4. Run focused tests, then plain `make test`, `make package`, and `make smoke`.
   Do not claim success from a browser screenshot or an earlier test run.
5. Inspect the exact development build on the current Mac at native scale:
   small-label/bold-value hierarchy, unclipped glyphs, stable live updates,
   light/dark and pressed contrast, narrow-space fallback, one-button click,
   tooltip, and panel placement/dismissal. Record which observations were
   actually possible; screenshot current-host results without private data.

The feature is accepted when the current Mac's native menu bar reproduces A's
readability within these constraints and automated gates pass. Native macOS 14
acceptance remains a separately deferred item, not a reason to expand this
task or claim an unperformed OS test.
