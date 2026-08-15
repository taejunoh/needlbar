# Cursor provider

Cursor is the only v0.1 provider with a Needlbar-owned explicit session connection. Its usage export and quota are still separate refresh streams.

## Usage source and local storage

Needlbar requests Cursor's token usage export directly and validates it before writing the pinned engine's compatible cache:

```text
https://cursor.com/api/dashboard/export-usage-events-csv?strategy=tokens
```

The cache is:

```text
~/.config/tokscale/cursor-cache/usage.csv
```

Needlbar also keeps an attempt marker beside the cache to enforce the five-minute source-sync freshness window. Writes are bounded, private, atomic, and preserve the previous valid cache when a refresh fails. `tokscale-core` then owns parsing, deduplication, aggregation, and cost estimation.

## Authentication source and precedence

Cursor has no environment-variable credential precedence in Needlbar v0.1. The only Needlbar-owned session store is:

```text
~/Library/Application Support/Needlbar/cursor-session.json
```

It is created or replaced only by the explicit Connect/Reconnect action in Settings, after the session is verified against Cursor. The session value is never exposed through Swift snapshots, diagnostics, logs, or bridge errors. Needlbar does not silently read browser cookies.

## Quota and fallback

Cursor quota uses the stored session for a direct bounded HTTPS request to:

```text
https://cursor.com/api/usage-summary
```

The provider reports its plan and on-demand windows when enabled, including reset information when supplied. Missing, invalid, or rejected session evidence returns a structured `connectCursor` action so Settings can offer Connect/Retry. Browser/session import is an explicit user action, not an automatic fallback.

## Recovery and disconnect

Use Connect or Reconnect in Needlbar Settings with a current provider-supported Cursor session, then wait for verification to complete. The form clears the submitted value immediately and duplicate connection operations are ignored while one is in flight.

Disconnect removes the Needlbar-owned session file. It does not revoke the Cursor account and does not erase the local usage cache. Reconnect when quota or source synchronization needs authentication; a prior valid cache may remain visible as stale/last-known-good usage while refresh recovers.
