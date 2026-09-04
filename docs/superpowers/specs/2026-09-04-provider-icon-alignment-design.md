# Provider icon and title alignment

**Date:** 2026-09-04

**Status:** Approved for implementation planning. The selected treatment is
option B: center the provider icon and title vertically as one row.

## Purpose

Correct the visible vertical misalignment between each provider brand icon and
its title in the main system-dashboard popover. The change is a presentation
alignment correction only; provider identity, data, actions, and the existing
dashboard layout contract remain unchanged.

## Root cause

`SystemDashboardPopoverView`'s provider title/header `HStack` still uses
`.firstTextBaseline`, which was appropriate for the former SF Symbol-based
icon. An 18 × 18 bitmap brand asset does not provide a text baseline, so its
bottom edge is aligned to the title's text baseline. The resulting visible
icon center is approximately 4.3 points too high relative to the title.

The official Claude PNG's transparent canvas/alpha placement is negligible
and is not the cause of the defect. It must not be cropped, redrawn, or
otherwise edited to compensate for the row alignment.

## Approved behavior

Change only the main dashboard provider title/header row to use vertical
center alignment. The icon and provider title must be centered against each
other as members of the same row. Apply the same rule uniformly to Claude,
Codex, and Cursor; do not add a provider-specific offset or exception.

The following existing behavior remains authoritative and unchanged:

- official provider assets, their rendering modes, and their fixed 18 × 18
  point frames;
- the 8-point horizontal spacing between the icon and title;
- provider labels, values, selected metrics, order, visibility, and actions;
- caption, status, quota, authentication, and Fable rows below the title;
- the 312-point dashboard width, adaptive content height, anchor, scrolling,
  and outside-click dismissal;
- light and dark appearance behavior; and
- all provider logic, refresh behavior, and authentication behavior.

The caption/status/Fable rows retain their current baseline alignment. This
amendment does not change their layout or text wrapping.

## Scope

### In scope

- the provider title/header `HStack` in `SystemDashboardPopoverView`;
- the shared vertical alignment rule for the existing Claude, Codex, and
  Cursor title rows; and
- focused geometry or semantic tests that verify the alignment contract.

### Out of scope

- editing, cropping, replacing, recoloring, or rescaling any provider asset;
- changing typography, font metrics, title text, or text layout;
- changing the provider icon component's mapping, fallback, accessibility, or
  rendering policy;
- changing captions, status/freshness text, quota/authentication text, or
  Fable presentation;
- changing Settings, Connections, Overview, provider-detail, widgets,
  notifications, menu-bar presentation, or other surfaces;
- changing popover width, height calculation, anchoring, scrolling, dismissal,
  or any provider action; and
- changing provider APIs, parsing, persistence, packaging paths, login flows,
  credentials, or release metadata.

Other surfaces that already use centered alignment remain unchanged. The
Connections surface may intentionally top-align a multi-line provider row;
that layout is not part of this correction.

## Geometry contract

For every rendered Claude, Codex, and Cursor provider title row in the main
system-dashboard popover:

1. The icon remains in its fixed 18 × 18 point frame.
2. The title and icon centers differ by no more than 1 point on the vertical
   axis.
3. The icon-to-title horizontal spacing remains approximately 8 points.
4. The title row's value/action column and all following rows retain their
   current positions and wrapping behavior.
5. The contract holds in both light and dark appearances and for the existing
   provider states covered by the dashboard fixtures.

The test must measure the layout result or inspect a stable semantic geometry
seam; a source-text grep or pixel-color assertion alone is insufficient.

## Implementation boundary

The implementation changes the alignment parameter of the existing main
dashboard provider title/header `HStack` only. Callers continue to obtain
provider icons through the existing shared brand-icon component. No caller
selects a resource, applies an offset, or changes the icon frame.

The title row remains non-interactive except for the existing controls already
attached to the row. No new gesture, action, state, or refresh path is added.

## Verification

Use test-first development: add or extend the focused presentation/geometry
test so it fails under the baseline first, then implement the smallest
alignment change and make the test pass.

Focused coverage must verify:

- Claude, Codex, and Cursor all use the same centered title-row alignment;
- icon/title vertical-center error is at most 1 point;
- the 18-point icon frame and approximately 8-point horizontal spacing are
  preserved;
- light and dark appearance fixtures retain the same geometry;
- caption/status/Fable baseline rows are unchanged; and
- 312-point width and adaptive-height regressions remain intact when provider
  visibility or content changes.

Run the focused alignment/presentation tests, then the repository's complete
`make test` gate. Native verification must inspect the exact packaged
development app and confirm the three provider rows visually at native scale
in both appearances. Native acceptance is supplementary to, not replaced by,
the geometry tests; native macOS 14 acceptance remains a separate deferred
gate.

## Non-goals and compatibility

This is a surgical visual correction. It must not alter provider values,
authentication state, quota semantics, selected metrics, actions, resource
provenance, accessibility identity, or any persisted preference. Existing
fallback behavior remains available if an asset cannot be loaded. No migration
or release metadata change is required.
