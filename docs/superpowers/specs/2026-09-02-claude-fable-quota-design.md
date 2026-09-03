# Claude Fable remaining quota and reset

**Status:** Written design approved by the user on 2026-09-03. The implementation
plan is `docs/superpowers/plans/2026-09-03-claude-fable-quota.md`.
Implementation remains blocked on the numeric semantics gate described below.

**Date:** 2026-09-02

## Decision

Add one separately labeled Fable weekly remaining/reset row beneath the
existing Claude quota headline. The menu-bar title and headline remain
unchanged. Fable is an additional view of the existing Claude subscription
quota response, not a new provider or a second quota system.

The implementation reuses the existing Claude quota endpoint, provider
authentication, background refresh ownership, Rust normalization, Swift store,
and Claude popover. It adds no login flow, browser-cookie path, polling timer,
OAuth refresh, provider, or persisted raw response. Secrets and raw HTTP bodies
must not enter logs, state, exports, diagnostics, widgets, or notifications.

## Evidence and the blocking semantics gate

Two bounded, non-interactive Rust requests used the current production exact
resolver in its `BackgroundNoUI` path. Both returned HTTP 200 from the existing HTTPS usage
endpoint. The requests used the existing 15-second cap, no redirects, and a
64 KiB response limit. Sanitized inspection confirmed a `limits` array of three
entries: `session`, `weekly_all`, and `weekly_scoped`. The Fable entry had this
identity:

```text
kind: weekly_scoped
group: weekly
scope.model.display_name: Fable
scope.model.id: null
scope.surface: null
is_active: true
percent: number
resets_at: RFC3339
```

`seven_day_overage_included` was absent. The model identity is therefore
verified, but the captured agent output did not include the actual Fable
numeric value. More importantly, the meaning of `percent` is not yet verified.
Before implementing `remaining = 100 - percent`, a first-party usage UI/client
mapping or an equivalent response comparison must establish that this field is
used/utilization percentage (for example, the same response's generic limit
percentage must be shown to mean five-hour or seven-day utilization). Until
that evidence exists, Fable numeric output fails closed as unavailable; no
placeholder, inferred current percentage, or token-based substitute is allowed.

On 2026-09-03 the diagnostic's corrected allowlisted value extraction passed a
synthetic check (session 37, weekly 64, Fable 13). One live follow-up attempt
produced no output and exceeded 30 seconds despite the HTTP client's 15-second
timeout. Its exact process was terminated and confirmed gone, and the helper
was returned to Trash without retry. No live status, body, comparison, or Fable
numeric value was obtained; the cause of the delay is not established. This
does not close the semantics gate. Future diagnosis must bound credential
resolution and transport together, not assume the HTTP timeout covers both.

## Source and normalization contract

The quota adapter selects exactly one entry matching all of:

- `kind == "weekly_scoped"`;
- `group == "weekly"`;
- `scope.model.display_name == "Fable"`; and
- `scope.surface == null`.

`is_active` is opaque provider metadata and is not required for availability or
selection. `scope.model.id` is not used for matching and may be null; no model ID
is copied into normalized state. Omelette, Cowork, legacy aliases, model IDs,
and raw model names are never treated as Fable. Missing, null, invalid, or
ambiguous matching entries omit only Fable while preserving a valid base
Claude snapshot and its freshness. Unknown additional fields are ignored, and
optional-data decoding must not fail the whole payload.

The normalized domain adds one generic quota window:

```text
id:    claude.fable.weekly
title: Fable weekly
```

It uses the existing Rust percent normalization and RFC3339 reset parsing.
Once the semantics gate verifies that the source number is used/utilization,
the domain stores it as normalized `usedPercent`; presentation derives remaining
with the existing `100 - usedPercent` rule. It never stores a remaining value in
the used-percent field. Otherwise the window is unavailable. Missing/null reset
maps to no reset timestamp; a malformed non-null timestamp omits only Fable.
There is one Fable family window, not separate Fable 5
and 5.1 windows. No quota is calculated from tokens, cost, a whole weekly
window, or a `50% * total` formula.

Anthropic's [Claude Fable models on your plan](https://support.claude.com/en/articles/15424964-claude-fable-models-on-your-plan)
documentation explains that, for Max and premium Team/Enterprise seats,
Fable usage can consume up to 50% of the weekly usage limits, but Fable and
other models draw from the same weekly pool and the account cannot exceed that
weekly limit. Pro and standard Team/Enterprise seats use usage credits for
Fable rather than receiving invented subscription capacity. These plan
semantics explain the label; they are not a formula for Needlbar's value.

## Presentation and freshness

The existing Claude headline remains the most-constrained eligible quota. The
new child row appears only when Claude is visible and its configured metric is
`remaining`; it does not alter menu-bar rendering, full tooltip content, or the
main headline. The row label is localized `Fable weekly`, followed by the
remaining percentage and an absolute localized reset date using the existing
formatters. A valid value with a missing/null reset remains displayable with an
explicit unknown-reset state.

Missing or semantically unverified Fable renders `—` with unavailable copy; it
never becomes 0%, 100%, a token total, or a new authentication CTA. A stale
last-known-good Claude refresh may show the prior Fable row with the existing
quota freshness/stale label. If a successful response omits Fable, the old row
is cleared to unavailable rather than retained as fresh. A failure before any
Fable data leaves the row unavailable.

The fixed dashboard width, height, scrolling, and layout contracts do not
change. Existing Claude provider detail already renders all supported quota
windows, so the same normalized Fable window may appear there under that
existing contract. Menu, tooltip, and headline exclusions apply only to the
exact new ID `claude.fable.weekly` for Claude; no broad four-window-ID allowlist
is added.

## Existing consumers and privacy boundary

The v1 export projection excludes only the known `claude.fable.weekly` window
for Claude. Unknown IDs continue to fail closed under the existing export
contract. Widget and notification ID allowlists remain unchanged: Fable is not
exported, widgeted, or notified, and tests must prove that unknown IDs retain
the existing ignore/reject behavior. No Settings or preference flag is added.

All other providers, authentication behavior, refresh ownership, bridge
envelope, and provider action policy remain unchanged.

## Alternatives considered

The selected design is a third generic quota window with a targeted Claude
projection. A provider-specific sidecar was rejected because it would duplicate
bridge/state/freshness machinery. Matching raw code-name aliases was rejected
because their Fable identity and semantics are unverified.

## Acceptance gates before implementation

The implementation plan must cover sanitized synthetic fixtures
for valid, missing, null, invalid, and ambiguous Fable entries; unchanged
Claude headline behavior including Fable at 0%; export byte identity and
unknown-ID rejection; unchanged widget/notification allowlists; Swift
bridge/store last-known-good behavior; and layout/accessibility behavior. A
native comparison must verify the current Fable value and reset only after the
numeric semantics gate closes. Tests must remain fixture-only and contain no
credentials or captured real HTTP bodies; provider-shaped synthetic JSON is
permitted.

Run plain `make test` and report its actual known fixture failures, with a
separate serial full-test diagnostic if needed. Do not claim CI or native
macOS 14 acceptance from these checks. No implementation starts until this
approved spec's source `percent` meaning is corroborated.
