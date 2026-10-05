# Settings card spacing audit

The user requested inspection and correction of all Settings screens after
approving the Claude connection card's 24pt horizontal / 20pt vertical inset.
This extends that spacing treatment, not the product or authentication design.

## Diagnosis and chosen approach

`SettingsStudioSection` owns a rounded background and 16pt horizontal inset,
but no vertical inset. Some children compensate with 11–20pt vertical padding;
others have none. A minimum row height centers a simple control but does not
protect top-aligned multi-line content or feedback against the card edges.

Use one shared shell with 24pt horizontal and 20pt vertical insets. Remove
child padding that duplicates this outer gutter. Keep internal row spacings,
minimum control heights, the Claude caption's 6pt gap, and 12pt above text
following a divider. Claude's previously corrected total inset stays unchanged.
Individual missing-row patches would perpetuate inconsistent ownership;
a broader visual redesign would exceed this repair's scope.

## Scope and acceptance

- Inspect Layout (2 tabs), CPU/RAM/Disk/Network/Battery (3 tabs each),
  Claude/Codex/Cursor (3 tabs each), Notifications, and Data: 28 states.
- Render real SwiftUI content at 960×720 and 760×560 in aqua/darkAqua,
  with scroll-body captures when full content exceeds the viewport.
- Inspect populated, unavailable/last-known information and longer provider
  and export feedback where relevant. Missing values remain missing.
- Correct reproduced clipping/wrapping within these Settings screens only.
- Preserve all controls, order, action ownership, preferences, collection,
  authentication, quota retrieval and refresh timers.
- Fixture renders use isolated defaults, inert actions/notification client,
  no-op browser openers and a temporary Claude status-line root. Do not read
  real provider settings or credentials for this audit.
- Add real hosted layout regressions; require narrow RED/GREEN and `make test`.
- Record actual coverage and remaining limits. No installed-app replacement,
  public push, merge or release is part of this request.

## Rendering boundary

If needed, expose parameterized internal page content that production itself
uses, without public review/test-only initial-selection options. Test utilities
own bitmap capture, fixture state, dimensions and teardown.
