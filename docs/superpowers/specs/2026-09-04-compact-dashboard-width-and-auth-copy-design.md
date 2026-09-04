# Compact dashboard width and authentication copy

**Date:** 2026-09-04

**Status:** Approved for implementation planning (the user selected option B)

## Goal

Make the main Needlbar system-dashboard popover materially narrower while
keeping its content-driven sizing and existing presentation behavior. Shorten
the remaining-quota and authentication copy so the normal quota-authentication
state is readable on one line at the new width.

## Authority and scope

This is a focused amendment to the approved adaptive system-dashboard sizing
and system-dashboard readability specifications. It supersedes only the
dashboard popover's fixed width and the dashboard's remaining/authentication
display copy. The adaptive sizing rules, the readability hierarchy, and all
existing data and interaction contracts remain authoritative.

Only the main system-dashboard popover is in scope:

- Replace the fixed width of 340 points with a fixed width of 312 points.
- Keep content-driven natural height, the 180-point minimum, the 680-point
  invalid-measurement fallback, the existing 24-point screen allowance inset,
  and the screen-height clamp.
- Keep the fixed header and footer, scrollable section body, in-place resize,
  stable menu-bar anchor, and no-resize/no-representation churn for numeric
  updates that do not change measured height.
- Change the default remaining metric caption from `Most constrained quota
  remaining` to `Quota remaining`.
- Render a single quota-authentication status as `Sign-in required`.
- Render the visible dashboard login control as `Sign in`.

The change does not add a preference, migration, provider, data source, timer,
network request, or alternate dashboard mode.

## Approved user-visible behavior

### Width and height

The popover frame is exactly 312 points wide in both the measurement host and
the visible host. Measurement continues to use the same rendered dashboard
hierarchy consumed by the visible view, so width-sensitive wrapping contributes
to the same natural content height. Natural height remains bounded by the
existing policy:

1. use a finite, positive natural measurement when available;
2. otherwise use the existing 680-point fallback;
3. clamp to at least 180 points, unless the screen allowance is smaller;
4. clamp to the current screen's available height minus the existing 24-point
   safe margin.

When content exceeds the allowance, the header and footer remain fixed and only
the body scrolls. The panel is resized in place and remains anchored beneath
the same existing menu-bar button. Resizing does not recreate the hosting
controller, reset provider refresh work, reset disclosure state, or reset the
scroll position.

### Remaining metric caption

When the existing provider metric selection is Remaining, the dashboard
caption is exactly `Quota remaining`. The value continues to be the existing
most-constrained eligible quota window and continues to be `—` when no quota
is available. Missing quota never falls back to token usage.

Captions for the explicitly selected Usage, Cost, and Connection metrics are
unchanged (`Tokens today`, `Estimated cost today`, and `Connection`). This
amendment does not change metric selection, persisted choices, provider order,
or provider visibility.

### Authentication and qualified status copy

The compact status policy applies only to the dashboard presentation layer.
Fresh and unavailable streams continue to suppress a status suffix. For a
provider stream that is not normal, use these compact status phrases. The
lower-case token is used when statuses are qualified with `Usage` or `Quota`;
the standalone display string is explicitly title-cased as shown:

| Stream state | Qualified token | Standalone display |
| --- | --- | --- |
| stale | `stale` | `Stale` |
| concrete error | `error` | `Error` |
| authentication required | `sign-in required` | `Sign-in required` |

If exactly one stream is abnormal, show only its standalone display string.
Therefore a fresh Usage stream with an authentication-required Quota stream
renders exactly `Sign-in required` (one status, with no `Quota` prefix and no
`Authentication required` wording).

If both Usage and Quota are abnormal, preserve provenance by qualifying both
phrases with their stream names and joining them with ` · `. The canonical
format is `Usage <phrase> · Quota <phrase>`, for example:

- `Usage stale · Quota error`
- `Usage error · Quota sign-in required`
- `Usage stale · Quota stale`

The stream names remain `Usage` and `Quota`; the lower-case compact phrases
are intentional. A stream that is merely unavailable does not become an
additional error label, and existing action/unavailable behavior remains the
source of truth.

The status remains supplementary to the provider value. Last-known-good
values remain visible for stale or in-flight/error states when the existing
model provides one; unavailable values remain `—`. The status is included in
the existing accessibility description even when the visual text is compact.
This provider-status policy does not rewrite Fable's subordinate reset or
freshness text; Fable's existing presentation and authentication/error
semantics remain unchanged. Fable remains a subordinate row under Claude,
stays out of the headline, and is not a top-level provider.

### Login control identity

Only the visible dashboard control label is shortened to `Sign in` for a
browser-login action. Provider-specific action identity and routing remain
unchanged:

- Claude's existing action title/help/accessibility identity remains `Sign in
  with Claude`.
- Codex's existing action title/help/accessibility identity remains `Sign in
  with ChatGPT`.
- The existing Claude and Codex callbacks and provider-managed browser-login
  flow are invoked exactly as before.
- Cursor's existing `Open Cursor Spending` action, identity, and callback are
  unchanged.

The provider name remains visible in the row, and the existing combined
provider accessibility element continues to expose provider, value, complete
status, and provider-specific help/action information. Settings login rows,
menu-bar actions, and any non-dashboard presentation retain their existing
labels.

## Preserved presentation and component boundaries

The data flow remains:

```text
CombinedUsageSnapshot + SystemMonitorConfiguration
        -> SystemDashboardModel
        -> SystemDashboardPresentation
        -> SystemDashboardPopoverView
```

`SystemDashboardPanelSizing` owns the 312-point width constant and retains the
existing finite height policy. `SystemDashboardPopoverMeasurement` continues
to measure the same content hierarchy as the visible view. `MenuBarController`
continues to measure before first presentation and to request an in-place
resize only after a material height change. `MenuPanelPresenter` continues to
own placement and dismissal.

`SystemDashboardPresentation` owns the `Quota remaining` caption.
`DashboardReadabilityPolicy` in the dashboard display components owns compact
provider-status composition, and `SystemDashboardPopoverView` consumes that
policy. The view owns only the visible `Sign in` button label plus existing
layout and accessibility composition. No presentation logic moves into
collectors, the Rust bridge, quota adapters, or persistence.

The following presentation behavior is explicitly unchanged:

- CPU circular gauge, per-core graph bars, chart geometry, and current-value
  alignment;
- RAM, Disk, Network, Battery, and AI section hierarchy, typography, colors,
  value formatting, units, and configured order/visibility;
- provider metric selection, quota-window selection, freshness handling,
  stale/error/unavailable value behavior, and independent Usage/Quota refresh;
- Claude's subordinate Fable weekly row, reset caption, freshness, and
  remaining semantics; Fable remains under Claude, out of the headline, and
  is not a top-level provider;
- local/public IP preference gates, truncation, tooltip/help text, and full
  accessibility values;
- Settings, Analytics…, provider actions, outside-click dismissal, and panel
  anchoring;
- menu-bar status item and headline, widgets, notifications, exports,
  analytics, packaging, signing, notarization, and release metadata.

## Failure and update behavior

Width reduction is presentation-only. It does not change snapshot schemas,
collector cadence, provider refresh scheduling, authentication, quota
retrieval, retry behavior, or persisted data. Usage and quota remain
independently refreshable and independently fallible.

An invalid or unavailable natural-height measurement follows the existing
680-point fallback and screen clamp. A status-copy change never starts a
refresh or authentication flow. Combined updates reconcile the already-open
view while retaining disclosure and scroll state; numeric-only changes with an
unchanged measured height do not mutate the panel frame.

## Deterministic verification

Automated tests must avoid wall-clock timing, network access, credentials, and
screen-dependent assertions except through injected numeric inputs. Add or
update focused tests to cover:

1. `SystemDashboardPanelSizing.width == 312` and both measurement and visible
   fitting views report width 312.
2. Natural-height ordering, the 180-point minimum, the existing 680-point
   invalid-measurement fallback, the 24-point safe inset, and screen-limited
   height remain unchanged at 312 points.
3. An all-enabled fixture still includes CPU, RAM, Disk, Network, Battery,
   Claude, Codex, Cursor, and the eligible Claude Fable row; hiding configured
   content still shortens natural height.
4. Remaining uses caption `Quota remaining`; Usage, Cost, and Connection keep
   their existing captions; no-quota Remaining stays `—`.
5. Provider-status mapping asserts no status for fresh/unavailable, the exact
   singleton strings `Stale`, `Error`, and `Sign-in required`, and the exact
   qualified examples `Usage stale · Quota error` and
   `Usage error · Quota sign-in required` when both streams are abnormal.
6. The dashboard's browser-login control exposes visible text `Sign in`, while
   Claude/Codex action titles remain `Sign in with Claude` and `Sign in with
   ChatGPT`, their provider-specific accessibility/help values remain exact,
   and each existing callback fires exactly once. Cursor Spending remains
   `Open Cursor Spending`.
7. Fable semantics, CPU graph/value alignment, value truncation/help,
   accessibility completeness, Settings, Analytics…, outside-click dismissal,
   stable anchor, and in-place resize regressions remain green.
8. A numeric-only live update with equal measured height performs no panel
   resize or re-presentation; a structural width-sensitive change performs
   one in-place resize with the original anchor.

Run the focused dashboard tests followed by the repository verification
command `make test`. The implementation task must not claim success from a
partial focused run alone.

## Native acceptance

Inspect the exact packaged development app at native scale and record
sanitized, app-only evidence for:

- a frame exactly 312 points wide;
- the all-enabled dashboard with content-driven height, including the full AI
  section and eligible Fable row on a sufficiently tall screen;
- a compact configuration whose content height decreases after hiding
  configured sections/providers;
- short-screen behavior with fixed header/footer and a scrolling body;
- stable anchoring and no visible movement during ordinary numeric updates;
- dark/light readability and unchanged CPU graph/value alignment;
- an authentication-required quota fixture showing the single `Sign-in
  required` status on one visual line at 312 points, without
  `Quota Authentication required` wrapping;
- unchanged Settings, Analytics…, provider-action, and outside-click behavior
  wherever safely observable.

Do not trigger external browser login or Cursor Spending solely for evidence,
and do not record credentials, account identifiers, raw provider payloads, IP
addresses, or full-desktop content. If a forced authentication state cannot be
observed safely in the exact development app, record it as unobserved instead
of substituting a browser mockup, synthetic screenshot, or automated result as
native evidence. Native macOS 14 acceptance remains a separate deferred gate.

## Migration and documentation implications

No migration is required. The width and copy are not user preferences, and
existing saved metric selections, module/provider visibility, order, and IP
privacy settings remain valid. Existing installations receive the new
presentation on the next verified build without resetting state.

README text and `docs/images/system-dashboard.png` must not be changed as part
of implementation until native acceptance is complete. After verification,
documentation may update the screenshot/display width to 312 and describe the
short `Quota remaining`/`Sign-in required` copy using only a sanitized capture
from the exact development app. If a suitable native capture is unavailable,
retain the current screenshot and wording rather than using a synthetic image
or claiming native acceptance.

## Non-goals

- Do not change data models, collectors, Rust bridge, quota retrieval,
  authentication flow, refresh cadence, or persistence.
- Do not change Fable calculations, Fable visibility rules, CPU graph/value
  alignment, units, chart/gauge semantics, or provider metric choices.
- Do not redesign Settings, Analytics, menu-bar presentation, widgets,
  notifications, exports, packaging, signing, notarization, or release flow.
- Do not add a compact/expanded preference, alternate width, collapse control,
  or new provider/action.
