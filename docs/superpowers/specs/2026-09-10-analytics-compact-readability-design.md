# Analytics compact readability amendment

## Approval and scope

The user selected A (Compact rows) in the local visual comparison, then approved
the four-part design summary on 2026-09-10. This document records that direction;
written-spec review precedes implementation planning.

This supersedes only conflicting presentation details of
`2026-09-09-analytics-balanced-dashboard-design.md`. Keep its single-column
evidence layout, 960 pt content cap, 24 pt horizontal insets, 760 × 520 pt default
window and 640 × 400 pt minimum. Keep native SwiftUI/AppKit and system appearance.
No parsers, schema, ABI, sources, calculations, refresh ownership, settings,
permissions, menu-bar behavior, packaging, installation or release changes.

The comparison at `.superpowers/brainstorm/49572-1789070053/content/readability-comparison.html`
is a private static design reference, not production data or native acceptance.
Its simplified reference panel is not a screenshot of the previous app.
The rules below override illustrative wording and incomplete mock interactions.

## Reading order and hierarchy

1. Compact header: Analytics, period/capture metadata and Refresh.
2. Existing three summary metrics: repository-attributed estimated cost,
   repository count with separately labelled unlinked fragments, observed activity.
3. Full-width repository comparison rows.
4. Separate full-width Unattributed / Unlinked usage card.
5. Diagnostics and estimate definitions, initially collapsed in a new window.

Retain blue/teal/purple summary identities and readable light/dark contrast.
Use existing native typography; body text must not shrink below 11 pt to fit.
Reduce repetition and align columns before adding decoration. No invented
charts, percentages, aggregate diagnostics counts or decorative severity colors.

## Header states

Replace the prominent partial-coverage banner with one compact status row using
an amber symbol, concise text and a Diagnostics navigation control. Retain the
full qualification in accessible detail, without repeating it across panels.
Loading, updating, unavailable, stale and partial remain distinct; errors and
stale last-good data must remain clearly visible. Preserve existing priority,
serialized Refresh behavior and last-good snapshot retention. Do not derive a
verified-period claim merely from partial attribution or remove timestamp caveats.

## Repository comparison

Use aligned columns: Repository | Estimated cost | Tokens. Right-align numeric
columns with monospaced digits. Retain existing repository order and formatters.
Long names wrap and narrower windows adapt without horizontal clipping.
The collapsed row retains an accessible disclosure affordance and a compact
quality marker whenever cost or timing evidence is partial/unavailable.

Expand a repository to reach its existing timing, attribution/commit qualifications,
provider/model metrics and commit details. Do not replace these with the mockup's
generic filler sentence. Preserve existing identities and disclosure state across
refresh. Rows scroll with the outer content; no new nested fixed-height list.

## Unlinked usage

Keep this bucket below repositories and separate from attributed estimates.
Display an explicitly labelled estimated amount and the separately labelled
unlinked fragment count. Use existing currency formatting with grouping.
Keep “Estimated cost · not a bill” visible near the amount, rather than relying
on a distant definition disclosure. Do not add the two cost buckets into a total.
At narrow widths, stack content; at wider widths, use a compact horizontal card.

Preserve missing-timestamp qualification: when the existing presentation reports
it, visibly say the amount is not a verified 30-day total. Unavailable remains
unavailable, not zero. No fabricated explanation for failure to link repositories.

## Diagnostics and definitions

Expanded Diagnostics uses stable aligned Cause | Count and unit | Short context
rows with subtle separators. At narrow widths the context moves below the cause
and count; units may wrap. Keep every original diagnostic's distinct unit,
including fragments, observations, mixed bounded processing and inspection
failures. Never add counters, calculate percentages or imply an exclusive breakdown.

Each row has an accessible explanation disclosure, collapsed initially, exposing
the existing allowlisted full caveat. Preserve all original diagnostics; do not
drop unknown/unavailable evidence or interpret a code more strongly than its
current presentation supports. In particular, bounded processing does not prove
lost cost or a single stopping cause; missing response duration is distinct from
observed activity; Git unavailability can mean unavailable or incomplete inspection.
Keep Pending 4-hour window wording and semantics, not a generic pending label.

Show the shared counts limitation once above the rows. Avoid repeating identical
generic explanatory paragraphs in every collapsed row. Retain specific limitations
in each row's expanded detail. Estimate definitions remain a separate compact
disclosure; all invoice, observed-time and non-causal commit-correlation caveats
stay reachable. View diagnostics expands and scrolls to Diagnostics without a fetch.

## Implementation boundaries

Reuse existing presentation models, formatters, snapshot and refresh state.
Keep view-only copy/layout/disclosure policy in the Analytics presentation layer.
Do not change the meaning of valid zero activity, known subtotals, partial timing,
repository linkage or any source-derived count. Small pure presentation helpers
are allowed only if consumed by the real view and useful for focused tests.

## Verification

- Test compact presentation, original diagnostic units/caveats, unavailable and
  zero distinctions, missing-timestamp warning, and refresh/disclosure preservation.
- Exercise actual view policy rather than an unused test-only layout helper.
- Run focused Analytics tests, then `make test` and `git diff --check`.
- Inspect native UI at default/minimum/wide widths in light and dark appearances:
  populated, empty, long-name, partial, loading, stale and unavailable states.
- Verify repository details, per-diagnostic expansion, keyboard/accessibility,
  final scroll reachability and no clipping/overlap. HTML is not native proof.
- Installation remains a separate authorized step. Record evidence and any
  untested scenarios honestly; do not repeatedly reinstall to force observation.
