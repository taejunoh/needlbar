# Cursor provider

Cursor support is local-only for usage and dashboard-only for quota. Needlbar does not
request, store, validate, refresh, or replay Cursor credentials, and it does not call
Cursor private usage or quota endpoints.

## Usage source and local storage

Needlbar reads an already-existing Tokscale-compatible cache:

```text
~/.config/tokscale/cursor-cache/usage.csv
```

The pinned `tokscale-core` engine owns discovery, parsing, deduplication, aggregation, and
cost estimation. Needlbar does not create, update, or claim freshness for this cache. If the
cache is absent or malformed, Cursor usage is unavailable while Claude and Codex remain
independent. Manual refresh re-reads local sources and does not trigger a Cursor network
request.

## Quota and dashboard action

Cursor personal quota is unavailable inside Needlbar. Settings and the Cursor provider
popover offer one `Open Cursor Spending` action, which opens exactly:

```text
https://cursor.com/dashboard/spending
```

The action is presentation-owned and uses the macOS workspace URL opener. It does not send a
Cursor credential or local usage data through Needlbar. A failure to open the page is a
transient UI state and does not change usage or quota snapshots.

## Obsolete-session cleanup

An older Needlbar build may have left this Needlbar-owned file:

```text
~/Library/Application Support/Needlbar/cursor-session.json
```

The bridge performs a one-shot, safe migration that removes only this obsolete file, without
reading or exposing its contents. An absent file is treated as success. The migration does
not modify Cursor.app, browser cookies, the Cursor account, or
`~/.config/tokscale/cursor-cache/usage.csv`; existing usage data remains preserved.

## Privacy boundary

Needlbar does not inspect Cursor.app credentials, browser profiles, browser cookies, or
session values. Do not provide a Cursor token to Needlbar. Use Cursor's own signed-in web
experience for the Spending dashboard.
