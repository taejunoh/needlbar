# System dashboard readability refresh

**Date:** 2026-09-03

**Status:** Approved. The user selected the balanced-density layout, selected
the bright high-contrast adaptive material, selected the main system dashboard
popover as the only surface in scope, and approved hiding `Fresh` when data is
normal.

## Purpose and authority

This specification defines the readability refresh for Needlbar's main system
dashboard popover. It translates the approved visual comparison into a native
SwiftUI/AppKit implementation while preserving the existing snapshot model,
native collectors, refresh cadence, provider behavior, and panel interaction
contracts.

The approved v0.1 design and the existing dashboard-readability and menu-bar
specifications remain authoritative for product boundaries, metric meaning,
privacy, provider actions, Fable treatment, menu-bar presentation, and data
freshness. This document supersedes only the main system dashboard popover's
visual hierarchy, material, grid alignment, and status-label presentation.

## Approved outcome

The main popover is a compact, scannable dashboard with six system sections:
CPU, RAM, Disk, Network, Battery, and AI usage. It uses the balanced-density
arrangement from the approved comparison: visual gauges remain where they
communicate a percentage, compact details share a consistent two-column grid,
and charts remain small and subordinate to current values.

The popover remains exactly 360 points wide. Its maximum height remains 680
points, and a shorter available height remains a fixed header/footer shell with
scrollable section content. Existing section order and saved configuration
continue to determine which sections are presented.

The surface uses the approved bright, high-contrast material. In light mode it
layers a high-opacity light system surface over the native material with dark
primary text. In dark mode it uses the corresponding high-opacity adaptive
system surface with light primary text. A controlled hint of material remains,
but no desktop wallpaper or window behind the popover is allowed to reduce text
contrast. Tint colors are supplemental and must not be the sole carrier of
meaning.

## User-visible layout

### Header and footer

The fixed header keeps the existing Needlbar identity, `System dashboard`
subtitle, and live-update indication. The identity is visually stronger than
the subtitle, and the update indication remains accessible without competing
with metric values.

The fixed footer keeps `Settings` on the leading side and `Analytics…` on the
trailing side. Both retain their existing actions, labels, keyboard reachability,
and accessibility names. The footer never scrolls with section content.

### Shared section structure

Every section has a leading icon, a bold section title, and an optional status
label at the trailing edge. Normal data has no visible status label. A section
shows only `Updating`, `Stale`, or `Error` when that section is currently in one
of those states. Status text uses high-contrast adaptive colors and is also
included in the section's accessibility description.

Current values use a shared two-column grid:

- The leading column contains the metric label in a high-contrast secondary
  color.
- The trailing column contains the value, aligned to the trailing edge of the
  same column across rows in that section.
- Values use semibold text with monospaced digits so changing numbers do not
  visibly change their digit geometry.
- Labels and values share a first-text-baseline alignment where a row has one
  line; multi-line supporting text uses the same leading and trailing edges.
- A value that is unavailable is rendered as `—`, never as zero or a fabricated
  current reading.

The grid has a finite minimum separation so labels cannot collide with values.
When a value is longer than the available trailing column, it is truncated at
the middle for address-like strings or at the tail for ordinary text. The full
value is available through the existing tooltip/help presentation and through
the accessibility value. Truncation never removes a unit, sign, percentage
meaning, or error state from the accessible representation.

### CPU

CPU keeps its circular usage gauge and per-core activity bars. The gauge center
shows the integer usage percentage with monospaced digits. The adjacent grid
shows `Usage` and `Idle`, with their values right-aligned. Core bars remain
below the current-value row and retain one accessible label per core.

### RAM

RAM keeps its used-percentage gauge. Its details use the common grid with
`Used`, `Available`, `Swap`, and `Pressure` labels. Binary memory units remain
GiB/MiB according to the existing formatter. `Pressure` remains the native
pressure value and is not inferred from the percentage gauge.

### Disk

Disk keeps its used-percentage gauge and volume name/details. The grid shows the
volume name with `Used` and `Available` values. The compact read/write legend
and recent trend chart remain below the current values, with contrasting
`Read`/`Write` labels and their existing decimal transfer units. Missing
throughput remains unavailable and is represented by a gap in the chart rather
than a zero.

### Network

Network remains one section with both transfer directions in the same compact
visual block. `Download` and `Upload` are separate labeled rows with
right-aligned values and their existing direction colors; color is reinforced
by text labels. The bounded recent trend chart remains below those rows.

Local IP remains hidden unless the existing local-IP preference is enabled.
When enabled, the primary IPv4 address is shown first and additional addresses
remain behind the existing disclosure. Public IP remains governed by its
separate existing opt-in. Addresses are never logged or exported by this
refresh.

### Battery

Battery keeps its level gauge and uses the common grid for `Level`, `Status`,
and `Health`. Charging and on-battery states retain their existing meanings.
Unavailable level or health stays `—`; no health percentage is invented when
native capacity data is absent.

### AI usage

AI usage keeps the configured provider order and visibility. Each provider row
shows the provider name, the selected existing metric, and a right-aligned
value. The selected metric remains the existing remaining quota, tokens today,
estimated cost today, or connection status. Remaining quota is the existing
default and continues to use the most-constrained eligible quota window.

Claude, Codex, and Cursor retain their current provider action policy. A
browser-login action, Cursor Spending action, unavailable state, stale state,
or error state is presented using its existing meaning; no action is inferred
from a generic failure.

Claude's Fable weekly window remains a separate subordinate row under Claude
when the existing Claude Remaining configuration and Fable data permit it.
Fable does not become a top-level provider, does not enter the headline value,
and does not alter Usage or Cost projections. Its remaining value, reset
caption, and freshness continue to be shown independently.

## Freshness and error behavior

The popover consumes the existing independently refreshed system, usage, and
quota snapshots. This refresh does not add a timer, network request, retry, or
refresh trigger. A combined model update reconciles the already-open view while
preserving disclosure and scroll state.

For each system section and each provider stream, presentation maps existing
status values as follows:

- A successful current value shows no status badge or suffix.
- An in-flight refresh shows `Updating` while retaining the last-known-good
  value when one exists.
- A value past its freshness threshold shows `Stale` while retaining the
  last-known-good value.
- A stream with no usable value shows `—` and `Error` when the source reports a
  concrete error; a source that is simply unavailable keeps `—` and its existing
  unavailable/action behavior.

Usage and quota remain independent. A fresh quota with stale usage, or fresh
usage with an authentication-required quota, displays each stream's existing
value and status without replacing one stream with the other. Missing data is
unknown, not zero, and the popover does not silently fall back from remaining
quota to token usage.

## Component boundaries and data flow

The existing data flow remains:

```text
CombinedUsageSnapshot + SystemMonitorConfiguration
        -> SystemDashboardModel
        -> SystemDashboardPresentation
        -> SystemDashboardPopoverView
        -> section/grid/gauge/chart SwiftUI components
```

`SystemDashboardModel` remains the observable owner of the current presentation
and bounded in-memory disk/network history. `SystemDashboardPresentation`
continues to format normalized values, preserve provider/Fable semantics, and
honor IP preferences. The view and its private display components own only
layout, typography, adaptive colors/material, truncation, tooltips, and
accessibility composition.

Native collectors, Rust bridge functions, usage aggregation, quota retrieval,
authentication, provider action routing, and refresh scheduling are outside
this change. No raw provider response or credential data crosses into the
readability components.

## Interaction and accessibility contract

The existing scroll view, fixed header/footer, Settings action, Analytics
action, provider actions, panel anchor, and outside-click dismissal remain
unchanged. The popover is not presented again during a live update, and no new
child hit-test region or auxiliary window is introduced.

Every gauge, chart, row, disclosure, provider action, and status message has a
meaningful accessibility label or combined value. Labels include the complete
untruncated value and current status. Decorative icons and chart colors are
hidden from the accessibility tree when their adjacent text already conveys
the meaning. Keyboard and pointer activation continue to reach the same
actions as before.

## Verification and acceptance

Automated Swift tests must cover the following behavior without depending on
wall-clock timing or network access:

1. The view fits at 360×680 and retains the fixed header/footer shell at
   360×400 with section content scrollable.
2. Labels and values use the shared two-column alignment, right-aligned
   semibold monospaced values, and finite row spacing for representative short
   and long values.
3. Long volume names, IP addresses, status words, error messages, units, and
   provider values truncate without layout collision while full tooltip and
   accessibility content remain available.
4. Fresh, updating, stale, unavailable, and error fixtures show exactly the
   permitted status text and preserve last-known-good values where applicable.
5. CPU, RAM, disk, network, battery, AI, Claude Fable, local-IP privacy, and
   provider-action regressions preserve their current data and behavior.
6. Light and dark appearances use adaptive high-contrast material and text
   without hardcoded desktop colors.

Native acceptance must inspect the exact development build at native scale and
record evidence for:

- readable label/value hierarchy and consistent value-column alignment;
- stable layout across ordinary live numeric updates;
- light/dark and pressed-state contrast;
- scroll behavior at a short available height;
- complete tooltip text for truncated content;
- unchanged one-button click behavior and panel anchoring;
- outside-click dismissal and unchanged Settings/Analytics/provider actions.

Native macOS 14 acceptance remains separately deferred. Menu-bar status-item
layout, notch/overflow behavior, widgets, notifications, export, analytics,
settings redesign, provider authentication, and release packaging are not
acceptance criteria for this popover-only refresh.

## Non-goals

- Do not change the 360-point width or 680-point maximum height.
- Do not change collectors, formulas, units, snapshot schemas, refresh cadence,
  provider endpoints, authentication, or quota calculations.
- Do not change configured visibility/order, menu-bar headline behavior, or the
  separate menu-bar two-line implementation.
- Do not add providers, metrics, charts beyond the existing bounded trends, or
  a new preference for this visual style.
- Do not redesign Analytics, Settings, widgets, notifications, export, or
  release surfaces.
- Do not make Fable a top-level AI provider or include it in headline Usage or
  Cost.
- Do not attempt to solve menu-bar notch overflow or reposition the status item.
