# Glanceable Overview widget

**Date:** 2026-11-06

**Status:** Approved by the user in conversation on 2026-11-06 (layout A from the visual
companion). It authorizes an implementation plan only. Implementation, merge, installation,
tag, and release each still need the user's separate request.

**Scope:** The medium **Overview** widget's view only. The projection the app writes, the
App Group contract, refresh behaviour, the widget's family, and its tap target are unchanged.

## 1. Problem

On the installed build the widget showed every line at the same visual weight: two quota
rows, their reset dates, "Fresh" lines with timestamps, a Cursor line, a header reading
**Stale**, and two "Today" lines. The user said the needed information did not stand out.
The header read **Stale** while both quota rows were fresh, because it required every usage
row, including Cursor's local cache, to be fresh.

The user chose remaining usage as the one thing the widget must show at a glance.

## 2. Layout

Two equal columns, then one footer line.

| Area | Content |
|---|---|
| Left column | **Claude**, the remaining percent of its headline window in a large figure, a thin bar, then one small line |
| Right column | **Codex**, the same |
| Small line, normal | `<window> · resets in <time>`, for example `Weekly · resets in 6d` |
| Footer | `Today <tokens> tokens` on the left, the estimated cost on the right |

- **Headline window:** each column shows the existing headline window: the allowlisted
  window with the least remaining, as the projection already selects it.
- **Window labels:** the existing fixed category labels (`Session`, `Weekly`, `Primary`,
  `Secondary`).
- **Fable:** not shown, because the projection has no Fable value. The dashboard and
  Settings still show it.
- **Removed:** the header's **Fresh**/**Stale** label, per-row "Fresh · <time>" lines, the
  Cursor row, and the "Today updated" line.

## 3. Formatting

- **Percent:** the remaining percent, rounded to a whole number. The widget always shows
  remaining, regardless of the app's shared **Display value** setting.
- **Reset countdown:** at least 1 day shows whole days (`6d`), at least 1 hour shows whole
  hours (`5h`), otherwise `<1h`. Values are rounded down.
- **Tokens:** compact with one decimal place below 100 units (`1.2K`, `878M`, `1.4B`).
- **Cost:** two decimal places with `$`, the same estimate the widget shows today.
- **Today:** the footer sums the providers whose today total is current, as today. The
  `Partial`/`Complete` and `Fresh`/`Stale` words are dropped. With no current contributor
  the footer is hidden.

## 4. States

| State | Large figure | Small line |
|---|---|---|
| Fresh | percent, normal | `<window> · resets in <time>` |
| Stale (older than 20 minutes for Claude, 15 for Codex, as now) | percent, normal | `Last checked <time>` |
| Reset time passed | percent, dimmed | `Awaiting fresh reading` |
| No displayable value | `—` | `Quota unavailable` |

- **Low remaining:** below 20 percent the figure and bar use the system orange; below 10
  percent, the system red. Unavailable values have no colour.
- **Last checked:** the time only when it is today, otherwise the short date and time.
- **No invented values:** an unavailable value is never shown as zero.

## 5. Updating

The widget's timeline reloads at the earliest of the existing deadlines (a freshness
boundary, a reset, local midnight) and the next moment the countdown text would change.
While a reset is more than a day away that is the next whole-day boundary before it; within
a day, the next whole hour. No reload is scheduled more often than once a minute.

## 6. Accessibility and appearance

- Each column reads as one VoiceOver element, for example "Claude, 77 percent remaining,
  weekly, resets in 6 days", or "Claude, quota unavailable".
- Colours are system colours and work in light and dark appearance. The bar uses a provider
  accent (Claude orange, Codex blue), as in the approved mock-up; the low-remaining colours in
  §4 replace it. The widget has no title row.
- **Bar shape (dated note, 2026-11-08):** the track is a 2-point line and the fill a 6-point bar,
  in every appearance. With the desktop not in front, macOS removed the widget's colour and the
  fill rendered darker than a full-height track, so the bar read backwards; shape stays readable
  whatever happens to the colours. A branch on `widgetRenderingMode` had no visible effect there
  and was removed. The accent and the low-remaining colours in §4 are lost in that state, so the
  percent itself is the signal.

## 7. Testing

- **Automated:** pure presentation functions in `NeedlbarWidgetSupport` cover the countdown
  rounding and boundaries, compact token text, the colour thresholds at 20 and 10 percent,
  each state in §4, the hidden footer, and the next reload time. The widget extension's
  existing build and search-guard checks still pass.
- **Manual:** the user checks the installed widget in light and dark appearance, with a
  fresh and an old value if one occurs.

## 8. Specification changes

`docs/superpowers/specs/2026-08-31-needlbar-v0.2.1-widgets-notifications-design.md` §3.1
gains a dated note: the title's freshness indicator and the fixed Cursor row are removed, the
today summary shows no completeness word, and stale rows show **Last checked** instead of a
separate freshness line. Its other rules stand: the headline selection, fixed labels, no raw
titles or errors, **Quota unavailable** instead of zero, and the fixed tap URL.
