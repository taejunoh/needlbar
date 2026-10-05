# Claude Connection Card Padding

Status: User approved the proposed spacing on 2026-10-05 with “진행해”.

## Scope

Improve only the Claude connection card in Settings. Preserve the native
appearance, content, actions, quota state, and authentication behavior. Do not
change shared card insets for unrelated providers or SYSTEM cards.

## Layout contract

- Give the Claude row 20pt top and bottom insets inside the rounded card.
- Give its content a total 24pt horizontal inset. The existing section owns
  16pt, so the Claude row adds 8pt on each side.
- Add 6pt below the explanatory caption, in addition to the existing 2pt
  stack spacing, to separate it from the first quota metadata line.
- Preserve intrinsic content height and wrapping; do not introduce a fixed
  height or truncate quota, timestamp, failure, or Fable information.
- Keep the existing usage button and provider icon top-aligned.

## Verification

Use the real SwiftUI connection-row view in an AppKit hosting view with
synthetic quota/Fable data. Check top/bottom and horizontal clearance, plus
growth at narrow widths and for longer metadata. Demonstrate the regression
before the fix, then verify the corrected layout and run `make test`.
Render light and dark fixtures for visual inspection, without accessing user
credentials or changing the installed app. Update `docs/STATUS.md` with exact
verification and any remaining limitation.

## Delivery boundary

This is a local presentation change, not a new release, a provider repair,
or an installed-app replacement. Those actions are not claimed by this work.
