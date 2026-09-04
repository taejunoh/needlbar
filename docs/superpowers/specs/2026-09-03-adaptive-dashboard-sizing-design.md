# Adaptive system dashboard sizing design

**Date:** 2026-09-03  
**Status:** Approved for implementation planning

## Goal

Make the main Needlbar system-dashboard popover narrower and size its height to
the content that is actually enabled. On a sufficiently tall display, the
default configuration must show CPU, RAM, Disk, Network, Battery, and the full
AI Usage section—including Claude, Codex, Cursor, and Claude's subordinate
Fable row—without requiring a scroll. On a shorter display, the same content
must remain available through the existing scrolling body.

## Scope

This change applies only to the main system-dashboard popover. The menu-bar
status item, two-line headline, notch/overflow behavior, provider data and
authentication, collectors, refresh cadence, Settings, Analytics, widgets,
notifications, exports, and release packaging remain unchanged.

The popover width changes from 360 points to a fixed 340 points. Height becomes
content-driven rather than using a fixed 680-point cap as the normal displayed
height. The minimum remains 180 points. The maximum is the current screen's
available height minus the existing safe margin.

## User-visible behavior

- The popover opens at 340 points wide.
- When all default modules and AI providers fit on the current display, every
  enabled section and provider row is visible without scrolling.
- Hiding a system module or AI provider in Settings shortens the popover to the
  new natural content height. Showing one lengthens it again when space allows.
- The Fable weekly row contributes to height only when the existing Claude
  presentation rules make that row visible.
- If natural content height exceeds the current screen allowance, the header
  and footer remain fixed and only the section body scrolls.
- The panel stays anchored beneath the same menu-bar button after resizing.
- Resizing is not animated. Ordinary numeric updates that do not change the
  measured height do not move or resize the panel.
- Existing one-line value truncation, help text, accessibility values, status
  wording, provider actions, IP privacy gates, and outside-click dismissal are
  preserved.

## Measurement architecture

The displayed view and the measurement path share one dashboard-content
component so measurement cannot drift from the rendered layout. Before first
presentation, `MenuBarController` hosts that content at the fixed 340-point
width in a measurement-only SwiftUI host and reads its natural fitting height.
It then passes the bounded result to the visible popover, avoiding an initial
680-point panel followed by a visible size jump.

While the panel is open, existing model or configuration updates trigger a
remeasurement. The controller compares the newly bounded height with the
current panel height and changes the panel frame only when the value has
materially changed. Resizing the existing panel must not replace the visible
hosting controller, restart refresh work, reset disclosure state, or reset the
scroll position.

The height policy is a small deterministic boundary with these inputs:

- measured natural content height;
- minimum height of 180 points;
- fallback height of 680 points;
- the current screen's available height and existing safe margin.

It returns a finite height clamped to the minimum and screen allowance. A zero,
negative, non-finite, or otherwise unusable measurement falls back to the
existing 680-point reference before the same screen clamp is applied. If the
screen allowance itself is smaller than the normal minimum, the available
screen height wins so the panel never extends outside the visible frame.

## Component responsibilities

`SystemDashboardPopoverView` keeps the fixed header, scrollable body, fixed
footer, existing module order, provider/Fable presentation, callbacks, and
privacy conditions. Its reusable content is factored only as far as needed for
the measurement host and visible host to consume the same hierarchy.

`MenuBarController` remains responsible for resolving the button and screen
anchor. It performs the initial measurement, applies the height policy, and
requests an in-place panel resize after structural presentation changes.

`MenuPanelPresenter` continues to own placement and dismissal. Its boundary may
gain a narrowly scoped resize operation for the currently displayed panel. It
must reuse the existing placement policy and must not create a second panel or
restart presentation.

No snapshot, provider, bridge, collector, quota, export, or persistence model
changes are part of this design. The selected width and calculated height are
not new user preferences.

## Update and failure behavior

Remeasurement may run after any existing dashboard presentation update because
the measured result is compared before mutating the panel. This keeps the
correct behavior for structural changes without requiring a second parallel
model of which captions wrap or which provider rows exist.

Measurement failure is presentation-only. The existing data remains visible,
and the controller uses the bounded 680-point fallback. Failure does not start
a retry timer, network request, provider refresh, or authentication flow.
Placement failure retains the presenter's existing safe behavior.

## Verification

Automated tests must cover:

1. the fixed 340-point width;
2. finite height clamping, the 180-point minimum, screen-limited maximum, and
   invalid-measurement fallback;
3. a full default fixture whose natural height includes all six modules,
   Claude, Codex, Cursor, and Fable;
4. shorter measured height when modules or providers are hidden;
5. no scroll requirement when natural content fits and body scrolling with
   fixed header/footer when it exceeds the screen allowance;
6. no panel frame mutation when a live update leaves measured height unchanged;
7. in-place resize and unchanged anchor when measured height changes;
8. preservation of Settings, Analytics, provider actions, Fable semantics, IP
   privacy, accessibility/help values, and outside-click dismissal.

Current-host native acceptance must inspect the exact development bundle and
record sanitized evidence for the 340-point width, full AI Usage visibility on
a tall screen, height reduction after hiding configured content, short-screen
scroll behavior, dark-mode contrast, stable anchoring, and outside-click
dismissal. Capabilities that cannot be observed must be recorded as unobserved
rather than inferred from automated tests. Native macOS 14 acceptance remains
separately deferred.

README wording may be updated after native acceptance. A screenshot may be
replaced only with a sanitized capture from the real development app; no
browser mockup or synthetic native screenshot may be presented as evidence.

## Non-goals

- Do not redesign module contents, typography, colors, charts, or gauges.
- Do not add collapse controls or a new compact/expanded preference.
- Do not change module/provider ordering or visibility defaults.
- Do not solve menu-bar notch overflow or status-item placement.
- Do not add data requests, timers, stored layout values, or dependencies.
- Do not change provider actions, quota selection, Fable calculations, or IP
  collection and disclosure rules.
