# Analytics Balanced Dashboard Visual Amendment

**Status:** Visual direction approved; written specification awaiting user review.

## Authority, scope, and replacement

This amendment supersedes only the visual-presentation portions of
`2026-09-08-analytics-summary-first-design.md` for Analytics Task 3. In
particular, its earlier “structure, not decorations” limitation is replaced:
3 pt semantic accent top edges, borders/tints, icon badges, and alignment are mandatory
native acceptance criteria, not optional cosmetics.

The selected direction is **A: balanced dashboard**, represented by the balanced
layout in the approved comparison mockup. That mockup supplies visual intent and
static example values only; it is not a production source of metric values or native
acceptance evidence.

Reference in the main checkout:
`.superpowers/brainstorm/92301-1788996568/content/analytics-visual-directions.html`.

Scope is native Analytics-view presentation only. Preserve existing pure
NeedlbarCore semantics and all prior data contracts. Do not change parsers,
DTOs, ABI, sources, providers, settings, widgets, networking, refresh ownership,
or attribution behavior. Use native AppKit/SwiftUI controls only: no WebView.
Earlier Core/probe work is not to be redone. Existing review findings and native
acceptance gaps remain carried forward.

This does not authorize an installation, push, release, tag, or package update.
The separately user-approved preview may continue after a future implementation;
this amendment does not imply a current install.

## Window, content frame, and type

- Retain the existing window state. Minimum size remains **640 × 400 pt** and
  default size remains **760 × 520 pt**. Do not add a new window preference.
- Available content width is `min(window content width - 48 pt, 960 pt)`.
  Center this column, retaining at least 24 pt horizontal insets. The fixed
  header aligns to exactly the same column edges; scrolling content remains
  beneath it. Use 16 pt inter-section spacing and 12 pt between summary cards.
- Do not make controls or grid tracks expand simply to occupy very wide window
  space. The bounded column and row/card relationships remain legible at about
  1,400 pt wide windows.
- Summary main values use **28 pt** semibold monospaced digits, reducing only
  to **24 pt** for long formatted amounts before wrapping. Card titles/body
  labels use **13 pt**; secondary metadata uses **12 pt**, never below **11 pt**.
  Use native dynamic type
  behavior where available; long labels wrap rather than clip or overlap.

## Header and state signal

The fixed header contains Analytics, the fixed Last 30 days range, capture time,
and Refresh, all aligned to the content column. Preserve the single retained
window and serialized refresh behavior. Refresh is disabled in flight.

Show the primary capture/status warning in exactly one place, adjacent to the
header/content transition. Its priority is:

1. initial loading without a snapshot;
2. updating with an existing snapshot (retain its quality caveat in this area);
3. unavailable after failure without a snapshot;
4. stale last-good data;
5. partial data;
6. complete data.

Do not show a healthy dot unless the state is actually complete. Each state uses
text in addition to any semantic color, and a failed refresh retains last-good
content with a stale notice. Status presentation must not introduce a fetch or
collapse independently-refreshable usage/quota semantics.

## Balanced summary row

Render three equal cards for repository-attributed estimated cost, repository
linkage, and observed AI activity. At **available content width ≥600 pt**, use
three explicit equal columns. Below 600 pt, adapt to two or one columns with a
minimum card width of **180 pt**. Do not leave a vacant grid track on wide
windows.

Each card has a 3 pt semantic accent top edge, a thin outline, restrained tonal
tint, clear title/value alignment,
and a generic native SF Symbol icon badge of about **30 pt**. The badge is a
labelled visual aid, not the only state signal.

| Card | Required semantic accent | Meaning retained in text |
| --- | --- | --- |
| Repository-attributed estimate | Blue, cost-oriented tint/stroke | Estimate for linked repositories; never spend, invoice, or subscription charge |
| Repository linkage | Teal, linkage-oriented tint/stroke | Repository count and unlinked fragment count remain separately labelled |
| Observed AI activity | Purple, activity-oriented tint/stroke | Observed activity, not human coding time |

Use amber only for non-healthy warning states, always together with explanatory
text. Use suitable native light/dark backgrounds, tints, and strokes. For
unspecified accessibility/system colors, match this semantic intent and contrast;
do not require exact mockup hex values or override the global app theme/add a
theme setting.

## Truth and unavailable-value rules

- Repository cost is an estimate only. No eligible repository evidence shows `—`
  with “No linked repositories,” while a measured zero remains `$0.00` using
  the existing currency formatter and known-subtotal qualification.
- Repository count is distinct from fragment count; do not portray them as a
  common fraction or invent a percentage.
- Activity is observed session activity, not human coding time. No attributable
  evidence is `—`; a valid isolated timestamped event may be zero.
- All unavailable numeric values use a neutral presentation. Do not invent
  percentages, charts, trend lines, or graph-like placeholders.
- Unattributed cost remains separate from repository totals. When Core reports
  missing timestamp coverage (a positive `missingTimestamp` count), regardless
  of the cost value, explicitly say it is **not a
  verified 30-day total**. Do not infer that qualification from unrelated legacy
  reasons.
- Preserve mixed diagnostic units faithfully. Fragment, observation, and record
  limits/reasons stay distinct; never combine counters or imply a causal
  breakdown the snapshot does not establish.

## Evidence panels and repository list

Below the summary row, show two lower panels: **Repositories** and
**Unattributed**. At **available content width ≥800 pt**, they are equal columns;
below that they stack vertically. Both use the same panel border/tint/alignment
language as the summary, without turning absent data into a large empty card.

Repositories retain the existing populated order and details: descending cost,
then provider/model and local commits in the existing expanded rows with their
safety caveats. A maximum-valued snapshot must not force a huge card height.
Repository rows may grow for wrapped long labels and must scroll within the
overall Analytics content rather than clipping.

The empty state is concise and truthful: no usable local repository association
was established. It must not claim no repositories or no AI usage, show a fake
graph, add a folder picker, sign-in prompt, or a new linking workflow.

Unattributed content describes retained unlinked usage/cost and the timestamp
qualification above. Do not surface raw legacy reason strings beneath the bucket;
those belong only in the allowlisted diagnostics shown once.

## Disclosures, interaction, and accessibility

Place Diagnostics and Estimate definition as full-width, left-aligned disclosures
below the evidence panels. They are collapsed by default for a new window and
their controlled disclosure state survives refresh. Diagnostics contains the
allowlisted diagnostic details once; definitions do not duplicate it.

“View diagnostics” expands the diagnostics disclosure and scrolls to those exact
details. This navigation must not trigger analytics refreshes, source hydration,
or any new fetch. All disclosure controls expose accessible names and explicit
expanded/collapsed state. Keyboard users can reach the final disclosure and all
content; focus and contrast remain visible in both appearances.

## Required native visual acceptance

Build/tests demonstrate behavior but do not prove this visual amendment. Inspect
the actual native Analytics view in light and dark appearance at default,
minimum, and very-wide (~1,400 pt) widths. Cover fresh populated, empty, mixed,
loading, stale, and unavailable states; expanded repository details; long labels;
maximum fixtures; keyboard traversal; accessibility labels/state; and final
scroll reachability.

The current NSHosting accessibility-empty result and CUA observation timeout are
documented blockers, not grounds to waive acceptance. Record the observation
method and outcome when implementation is evaluated.
