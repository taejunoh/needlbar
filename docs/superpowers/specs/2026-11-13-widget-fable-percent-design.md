# Fable percent on the Overview widget

**Date:** 2026-11-13

**Status:** Approved by the user in conversation on 2026-11-13: the remaining Fable percent
appears as small text on the Claude column's name line, with no reset time. It authorizes an
implementation plan only. Implementation, merge, installation, tag, and release each still
need the user's separate request.

**Amendment (2026-11-13):** after the first version was installed, the user chose to move the
text beside the big Claude figure, because at the end of the name line it sat closer to the
Codex title and could read as Codex's. §2 "Where", §4 "Layout" and §6 are amended below;
the rest stands. The text as first approved read `Fable 71%` on the name line.

**Scope:** The medium **Overview** widget and the projection the app writes for it. It amends
`docs/superpowers/specs/2026-11-06-glanceable-overview-widget-design.md`, which left Fable
out. The widget's family, tap target, refresh behaviour, columns, figures, bars, captions and
footer are unchanged, and so is how the Claude headline is chosen.

## 1. Problem

The widget shows, for Claude, the remaining percent of its headline window (the lower of
session and weekly), and for Codex its primary window. Fable has its own weekly limit inside
the Claude account, and the user now spends it through a Fable-based agent, so they want to see
it on the widget. On 2026-11-06 the user chose to leave it out; on 2026-11-13 they asked for it
as secondary information, small.

## 2. Decision

- **Where (amended 2026-11-13):** `Fable 71%` beside the big Claude figure, baseline-aligned
  with it, in caption size. The name line is the plain title again. The widget gains no height:
  the row stays the figure's height, about 43 points. (First approved at the right end of the
  name line, where it read as Codex's on the installed widget.)
- **What:** the remaining Fable percent only, rounded to a whole number like the other figures.
  No reset time. The user's reading is that Fable resets with the weekly window shown below;
  the repository does not confirm this, and the usage report gives Fable its own reset time,
  which may also be absent (for example when Fable is unused). The widget still uses that reset
  time internally (§4, §5).
- **The big Claude number stays the headline**, the lower of session and weekly, even when
  Fable is lower. Fable is part of the weekly pool, not separate capacity, so a big "Claude 5%"
  would be wrong while other models still have room. The menu-bar headline also excludes Fable
  (`HeadlineQuotaSelector.swift`).

**Options not taken:**

- A line under the Claude caption, with or without the reset. It costs about one caption line
  of height; with the footer showing, the medium widget would overflow by an estimated 5 points
  and need tighter spacing.
- A third, equal column, and promoting Fable to the big number only when low. The user chose
  small secondary information.

## 3. Data

The Claude quota row in the projection gains one optional reading, `fable`, with the remaining
percent and an optional reset time. It carries no window ID and no timestamp of its own: Fable
comes from the same `/usage` report as the Claude headline, and the app replaces the whole
snapshot with one timestamp, so the row's freshness and last successful time apply to it.

- **Schema version stays 1.** The widget decodes the projection with synthesized `Decodable`
  types that ignore unknown keys, and a missing or `null` `fable` decodes as no value. A widget
  process from before this change reads a new file without the Fable text; a new widget reads
  an old file the same way. A projection with no Fable value encodes exactly as today.
- **Both decode paths and both validators carry the field**: the row's own initializers and
  the raw row used by the projection decoder, and the row and projection validation.
- **Validation**, rejecting the projection like any other invalid row: `fable` only on the
  Claude row; percent finite and within 0 to 100; reset time finite when present; the row has
  a last successful time.
- **Mapper:** emits Fable only for the Claude provider, from the window `claude.fable.weekly`
  in the direct quota snapshot. It drops Fable, and never throws, when there are zero or
  several matching windows, the reset is not finite, or the row has no last successful time.
  The app publishes the projection with `try?`, so a throw would stop all widget updates.
- The headline allowlist is unchanged, so Fable never becomes the headline, and older widgets
  never see an unknown headline ID.

## 4. States

One rule decides whether the text shows: **the Fable text appears only when the Claude column
shows a figure and the row has a Fable value.** Its content depends only on its own value and
reset; the column's caption carries freshness. This rule was adopted at the spec review on
2026-11-13 so a days-old Fable value never sits beside **Quota unavailable** without a
**Last checked** cue; it follows the user's choice to hide the text when there is no value.

| State | Fable text | Added to the column's VoiceOver label |
|---|---|---|
| Value present, reset in the future or absent | `Fable 71%` | ", Fable 71 percent remaining" |
| Claude reading stale | `Fable 71%`; the caption says **Last checked**, or **Awaiting fresh reading** if the headline reset passed | ", Fable 71 percent remaining" |
| Headline reset passed, Fable reset not | `Fable 71%`, not dimmed, while the figure and bar dim | ", Fable 71 percent remaining" |
| Fable reset passed (fresh or stale, headline valid or not) | `Fable —` | ", Fable awaiting fresh reading" |
| No Fable value (a report with no Fable row, an unmatched label, an older file) | hidden | nothing |
| No projection, or the Claude column shows `—` | hidden | nothing |
| Codex column | never | nothing |

- **Colour:** judged on the whole percent shown, as for the big figure: system orange below 20
  percent, system red below 10 percent, otherwise the secondary colour. So 19.5 shows `20%`
  uncoloured, 99.6 shows `100%`, 0.4 shows `0%`. `Fable —` uses the secondary colour. There is
  no bar and no size change. With the desktop not in front macOS removes the colour, so the
  percent is the signal there.
- **Never invented:** a missing value is hidden, never shown as zero, and Fable is never
  estimated from the weekly value. Fable can read higher than the weekly figure; it is shown as
  reported.
- **Layout (amended 2026-11-13):** the Fable text sits beside the Claude figure, aligned to its
  baseline, in caption size with monospaced digits. The figure never shrinks because of
  Fable. The ladder is: one line (`Fable 71%`); then two lines (`Fable` over the value, the
  value on the figure's baseline); then hidden. The row height stays the figure's, about 43
  points. Measured, one line fits for every one- and two-digit Claude figure except beside
  `Fable 100%` at a column of about 141 points; Claude `100%` uses two lines, and the text is
  hidden only if the column is under about 139 points with Claude at `100%`. (As first
  approved: a first-baseline row of the name, a spacer and the Fable text on the name line,
  scaling down to 0.8; measured with AppKit, "Claude" at the headline font about 45 points and
  "Fable 100%" at caption size about 57 points, against a column of about 141 points from a
  329-point widget with default margins.)

## 5. Updating

When the row has a Fable reset time, it joins the widget's reload deadlines while it is in the
future, so the widget redraws when it passes and shows `Fable —`. A reset already passed is not
a deadline. Fable adds no countdown text, so it adds no countdown deadlines. This adds at most
one timeline reload per Fable reset, and none when it equals the headline's reset. Fable adds
no reloads from the app: every successful `/usage` run already rewrites the projection.

## 6. Testing

- **Projection** (`NeedlbarWidgetSupport`):
  - a round trip with Fable, and with Fable and no reset;
  - an old file without the key, a `"fable": null`, and a row with an unknown extra key each
    decode; the last is what keeping schema version 1 rests on;
  - a projection without Fable encodes without the key;
  - rejected: Fable on the Codex row; a percent of 101 or −1; a NaN percent (through the
    initializer, since JSON cannot carry it); a non-finite reset; Fable without a last
    successful time;
  - accepted: a stale row with Fable.
- **Mapper** (`NeedlbarCore`): Fable is copied from `claude.fable.weekly`, including a nil
  reset; no Fable and no throw when the snapshot has none, two, or one with a non-finite reset,
  and when a Fable window appears in the Codex snapshot; the existing test with Fable lower
  than the headline is extended to show the headline unchanged and Fable copied.
- **Presentation:** the text and VoiceOver suffix for each state in §4; the colour at 20 and
  10 percent on the whole percent shown; the Fable reset as a reload deadline only while in the
  future; no countdown step from Fable.
- The widget extension's build and search-guard checks still pass. The search guard rejects
  certain words anywhere in the widget sources, comments included.
- **Not automated, checked by the user on the installed widget** after a tagless Developer ID
  build and installation (both separate requests): light and dark appearance; `Fable 100%`
  reads as Claude's, on one line normally and on two lines when Claude is at `100%`, without
  truncation; the text reads as part of the Claude column; the low colour, when it occurs.

## 7. Risks

- **A widget process left from before installation** shows no Fable text, which looks like a
  missing value. Stop it by its process ID and check its executable after installing.
- **Label dependence:** Fable is matched in the usage report by its display name. If Anthropic
  renames it, the text disappears from the widget without notice, while the dashboard shows
  Fable as unavailable.
- **No last-known Fable:** each report replaces the snapshot, so a report without Fable removes
  the text at once.
- **Unused limit:** whether accounts without Fable use receive an inactive row, which would
  show `Fable 100%`, is not verified.

## 8. Documentation

Dated notes, each saying what changed and why:

- `docs/superpowers/specs/2026-11-06-glanceable-overview-widget-design.md`: the scope line that
  says the projection is unchanged, §2 "Fable: not shown", §4 states, §6 VoiceOver, and §7
  testing.
- `docs/superpowers/specs/2026-08-31-needlbar-v0.2.1-widgets-notifications-design.md`: §3.1
  (the headline rules stand; a fixed-label Fable text is added) and §4.2 "Sanitized Shared
  Projection", whose "contains only" list is the privacy allowlist and gains the Fable percent
  and reset time.
- `docs/superpowers/specs/2026-09-02-claude-fable-quota-design.md`: "Fable is not exported,
  widgeted, or notified" becomes shown on the widget as secondary text, still not exported or
  notified.
- `README.md`: the Fable section that says the widget is unchanged, and the widget section.
- `docs/HANDOFF.md` widget mentions, and a new `docs/STATUS.md` entry marked prepared, not
  released.

`docs/architecture.md` and `docs/privacy.md` describe the projection only in general terms and
stay unchanged. The acceptance driver's fixtures stay unchanged; the Fable text is a manual
check.
