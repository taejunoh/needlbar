# Provider brand icons

**Date:** 2026-09-04

**Status:** Approved for implementation planning. The user selected the mixed
brand treatment and approved the Codex label/icon convention.

## Purpose

Use recognizable provider marks in Needlbar's AI-related surfaces so that
Claude, Codex, and Cursor can be identified at a glance. The change replaces
provider iconography only. Provider names, metrics, data, actions, layout
rules, and refresh behavior remain the existing product contract.

## Authority and scope

This is a presentation-only amendment to the current AI Usage and provider
presentation. The existing approved specifications remain authoritative for
provider data, quota and usage semantics, authentication, visibility/order
preferences, adaptive sizing, accessibility, and native interaction.

In scope:

- Claude uses the official Claude mark in its distinctive orange treatment.
- Codex keeps the visible label `Codex` and uses the official OpenAI Blossom
  mark rendered as a system-monochrome icon.
- Cursor uses the official two-dimensional Cursor mark rendered as a
  system-monochrome icon.
- Every provider mark is displayed at 18 × 18 points, preserving its source
  aspect ratio and artwork without distortion.
- A shared `ProviderBrandIcon` component owns asset selection, rendering mode,
  accessibility label, and SF Symbol fallback behavior.

Out of scope:

- Renaming Codex to ChatGPT or changing any other provider label.
- Changing provider identity, ordering, visibility, selected metrics, values,
  quota windows, reset text, freshness/error/authentication copy, or actions.
- Changing dashboard width/height, spacing, typography, section hierarchy,
  menu-bar layout, widgets, notifications, exports, analytics, or release
  metadata.
- Adding a new provider, remote asset download, web view, account flow,
  provider API, credential, or persistence migration.

Fable is a subordinate Claude quota detail, not an independent provider. It
does not receive a separate provider mark or a new icon slot.

## Approved provider treatment

The provider row keeps its current text and data. Only the leading icon is
replaced by the corresponding brand mark:

| Provider | Label | Mark | Rendering |
| --- | --- | --- | --- |
| Claude | `Claude` | Official Claude mark | Distinctive official orange |
| Codex | `Codex` | Official OpenAI Blossom mark | System monochrome |
| Cursor | `Cursor` | Official two-dimensional Cursor mark | System monochrome |

The term “system monochrome” means the mark is rendered with the current
system foreground/tint appropriate to the light or dark appearance. The
implementation must use an official monochrome source variant when the
provider supplies one. If no such variant exists, the unmodified official
asset may be rendered through the platform's template/tint mechanism; no
manual path edits, redraw, gradients, shadows, or recoloring logic may be
added. Claude's orange treatment is the explicit exception and must not be
converted to the system tint.

All three marks are optically centered in an 18-point square frame. The
original artwork's aspect ratio is retained; transparent padding inside an
official asset is allowed and is not cropped solely to enlarge the mark. The
frame must not grow or shrink based on the current provider value.

The logical bundled resource identifiers are fixed as `provider-brand-claude`,
`provider-brand-openai-blossom`, and `provider-brand-cursor-2d`. File format
and platform catalog syntax may follow the existing asset pipeline, but these
three identities must not vary by surface or appearance.

## Official asset and trademark requirements

Assets must come from the provider's official brand or developer asset
distribution. The source file is copied into the repository/app resources
without modifying its paths, proportions, or artwork. The implementation
records the source page or package identifier and the asset variant used in
the implementation plan or resource manifest so a reviewer can verify
provenance. Do not use a search-result image, an unofficial icon library, or a
recreated approximation.

The repository must include a short attribution/trademark note alongside the
resource manifest or provider-icon documentation: Claude, OpenAI/Blossom,
and Cursor marks are owned by their respective trademark holders; Needlbar is
not sponsored by, endorsed by, or affiliated with those providers. The note
must not imply that the marks or provider names are Needlbar property. Asset
licenses and any provider usage restrictions remain in force; implementation
must not remove required notices.

## Shared component boundary

`ProviderBrandIcon` is the only component that maps a provider identity to a
brand resource. Callers pass the normalized provider identity; the component
always owns the fixed 18-point frame. Callers do not select files, colors, or
SF Symbols directly.
The component:

1. selects the official resource for Claude, Codex, or Cursor;
2. applies the approved rendering mode (Claude orange, otherwise system
   monochrome);
3. preserves aspect ratio and produces an 18 × 18-point layout result;
4. supplies a provider-specific accessibility label such as `Claude`,
   `Codex`, or `Cursor`; and
5. falls back to the existing provider-appropriate SF Symbol only when the
   official resource cannot be loaded or rendered.

The fallback is an operational resilience path, not a second visual choice.
It must use the same frame, tint policy, and accessibility label, and it must
not alter provider values or hide the row. Resource failure should be
diagnosable in existing safe diagnostics without exposing file contents,
credentials, or provider payloads.

No provider parsing, snapshot transformation, quota calculation, or network
request belongs in this component. No brand asset may be selected from a
current value, status, account, or authentication state.

## Required application surfaces

Use `ProviderBrandIcon` at every existing provider-icon location in these
surfaces, preserving each surface's current hierarchy and interaction:

- the AI Usage section in the main system-dashboard popover;
- Overview and other provider summary presentations that already show a
  provider icon;
- provider-detail content;
- system Settings provider rows and connection controls; and
- the Connections surface.

The component must be used consistently for every one of the three providers
that a given surface already renders. A surface that currently has no
provider icon does not gain an additional row, control, or section as part of
this change. The existing login and spending actions remain attached to their
existing controls, not to the icon, unless the current surface already makes
the whole row actionable.

## Appearance, accessibility, and failure behavior

The asset follows the surrounding surface's light/dark appearance without
changing the surface background or layout. Claude remains orange in both
appearances when that is the approved official treatment; Codex and Cursor
use the current system foreground in both appearances. The icon must not
reduce contrast below the existing provider-row text or become the sole
carrier of provider identity.

The provider label remains exposed as text and in the accessibility tree. The
icon has a concise provider-specific accessibility label or is marked
decorative when it is contained by an already-labelled provider row, avoiding
duplicate announcements. Existing row descriptions continue to expose the
provider, value, freshness/status, and action/help information. Loading a
fallback must not change those descriptions.

If an official resource is unavailable, malformed, or incompatible with the
current rendering scale, show the existing SF Symbol fallback and retain the
18-point frame. If both resource and fallback rendering fail, retain the
existing text/label behavior; never show a blank clickable region or invent a
brand mark. Such failure is local to the icon and must not block the dashboard
or Settings surface.

## Packaging and resource integrity

Official assets are bundled with the app rather than fetched at runtime. The
resource names are stable, provider-specific, and limited to the approved
three marks. The package gate must verify that every declared official
resource is present in the application bundle, has the expected image type,
and is not an empty or generated placeholder. The smoke gate must verify that
the production resource lookup table resolves Claude, Codex, and Cursor and
that the fallback symbols remain declared.

The package/smoke checks must not require network access, provider login, a
live quota response, or a particular account. They must not print raw asset
bytes or private application data. Existing signing, notarization, and
release boundaries are unchanged.

## Deterministic verification

Add focused tests at the component and presentation boundaries. Tests must
use local fixture assets or test doubles and must not contact provider sites.
Cover:

1. Each provider maps to the correct official resource and rendering mode;
   Codex's visible label remains exactly `Codex`.
2. Claude selects the orange treatment; Codex and Cursor select system
   monochrome in both light and dark appearances.
3. Every result is 18 × 18 points, preserves the source aspect ratio, and
   does not crop, stretch, or distort the artwork.
4. Missing, malformed, and incompatible resources use the correct SF Symbol
   fallback while retaining frame size and accessibility identity.
5. AI Usage, Overview, provider detail, Settings, and Connections use the
   shared component rather than independent provider-specific icon logic.
6. Provider values, selected metrics, labels, actions, visibility/order,
   freshness, quota/authentication states, and adaptive height are unchanged
   when only the icon resource changes.
7. Accessibility exposes provider identity once with the existing value,
   status, and action/help information; fallback does not alter it.
8. Package and smoke checks detect missing, empty, wrong-type, or undeclared
   official resources and pass with all three valid bundled assets.

Run the focused icon/presentation tests, then `make test`, `make package`, and
`make smoke`. A focused test run alone is insufficient for acceptance.

## Native acceptance

Inspect the exact packaged development app on the current Mac at native scale
and record only sanitized app-only evidence. Confirm the three marks are
recognizable, optically aligned, and 18 points in each required surface;
Claude is orange while Codex and Cursor are system monochrome; labels and
values remain readable in light and dark appearances; and the 312-point
dashboard remains unchanged in width, content height, anchor, scrolling, and
outside-click dismissal. Check Settings and Connections rows as well as the
AI Usage and Overview/provider-detail surfaces. Force a resource-missing test
fixture to observe the SF Symbol fallback without altering the normal app
bundle.

Native macOS 14 acceptance remains a separate deferred maintainer gate. Do
not infer native acceptance from a browser mockup, an automated image fixture,
or an unobserved operating-system version.
