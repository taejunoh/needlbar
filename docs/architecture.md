# Needlbar architecture

Needlbar is a native macOS menu-bar application with a Swift presentation shell and Rust-owned provider integrations. The bridge is deliberately narrow: Swift receives versioned JSON snapshots, while provider credentials and raw provider responses remain on the Rust side.

## Runtime layers

```text
Needlbar.app
├── AppKit / NSStatusItem shell
├── SwiftUI overview, provider, and Settings surfaces
└── NeedlbarCore
    ├── normalized ProviderSnapshot state
    ├── independent usage and quota repositories
    ├── refresh scheduling and file watching
    ├── last-known-good and stale-state handling
    └── module configuration and UI-free formatting
        │
        └── narrow C ABI / UTF-8 JSON envelopes
            │
            └── needlbar-bridge
                ├── tokscale-core usage adapter
                ├── quota aggregation
                ├── panic/error boundary
                └── Rust-owned allocation/freeing
                    ├── needlbar-quota
                        │   └── Claude, Codex, and Cursor quota/auth adapters
                    └── vendor/tokscale-core
                        └── pinned local usage discovery/parsing/aggregation
```

Needlbar's AppKit layer also owns `ProviderLoginCoordinator`. It launches only the fixed
provider commands through the installed executable's direct path, while the provider CLI
owns browser navigation, OAuth callbacks, refresh, and credential storage. The coordinator
does not capture provider stdout or stderr and reports only safe login states to SwiftUI.

### Ownership

`tokscale-core` owns local session discovery, parsing, deduplication, aggregation, model pricing, cost estimation, and normalized usage values. Needlbar passes it the selected home and client scope; it does not duplicate provider token-history parsers.

Cursor usage has no Needlbar-owned hydration layer. The pinned `tokscale-core` engine reads an already-existing compatible cache at `~/.config/tokscale/cursor-cache/usage.csv`; Needlbar does not create or refresh that cache. A bridge-private startup migration may remove only the obsolete Needlbar-owned Cursor session file without reading it, and never touches the usage cache.

`needlbar-quota` owns provider quota retrieval, reset windows, authentication discovery, bounded provider HTTP/RPC fallbacks, and provider-specific quota parsing. It does not parse token-history files.

`needlbar-bridge` owns the C-callable ABI, JSON serialization, schema versioning, panic containment, and Rust allocation lifetime. It contains no presentation logic.

`NeedlbarCore` decodes bridge envelopes, merges usage and quota streams, records last-known-good values and failure status, schedules refreshes, and provides presentation-neutral formatting and module configuration. It never re-parses provider files or raw authentication formats.

`Needlbar` owns AppKit lifecycle, status items, popovers, Settings, and native window presentation.

## Independent refresh streams

Usage and quota are separate repository calls and separate state streams. A provider can have fresh usage with unavailable quota, or fresh quota with stale usage. A failed refresh records the latest safe failure while preserving the previous successful snapshot. The UI labels stale/error/authentication states without replacing a known value with zero or an empty payload.

The overview aggregates today's usage and cost from available usage snapshots. Its quota headline selects the lowest remaining percentage among eligible enabled-provider windows. Provider popovers preserve all quota windows and reset timestamps rather than collapsing them into one value.

## Provider data flow

```text
Claude local session roots ───────────────┐
Codex local session roots ────────────────┼─> tokscale-core -> usage envelope
Cursor existing local cache ──────────────┘

Claude OAuth evidence -> Anthropic usage API ───────┐
Codex OAuth -> OpenAI usage API -> CLI RPC fallback ├─> quota envelope
Cursor quota unavailable; Settings/popover open Spending dashboard ─┘
```

Quota collection runs providers independently and preserves usable partial results and provider-scoped safe errors. Cursor quota performs no credential, filesystem, or network I/O and returns a provider-scoped unavailable result. Cursor usage is a local read only; manual refresh does not imply remote synchronization.

Claude and Codex login are explicit user actions. After a successful provider CLI exit,
`NeedlbarCore` requests a quota-only refresh for that provider. Claude's dedicated
post-authentication bridge path may allow the exact provider-owned macOS Keychain item to
be read; ordinary background refresh always uses interaction-forbidden access. Codex uses
its provider-specific quota path. A failed verification preserves the last-known-good
quota state and does not mark all-provider background refresh fresh.

## Bridge contract

The stable C surface is:

```c
const char *needlbar_usage_snapshot_json(void);
const char *needlbar_quota_snapshot_json(void);
const char *needlbar_claude_user_initiated_quota_snapshot_json(void);
const char *needlbar_codex_quota_snapshot_json(void);
const char *needlbar_diagnostics_json(void);
void needlbar_free_string(const char *ptr);
```

Each snapshot is a UTF-8 JSON envelope with `schemaVersion`, `ok`, `generatedAt`, `data`, and `errors`. Rust owns each returned string; Swift frees every non-null pointer exactly once through `needlbar_free_string`. Panics do not unwind across the ABI. Errors contain provider-safe codes and messages only.

Diagnostics use fixed subsystem/provider status and source labels. They do not include credentials, cookies, account identifiers, raw local paths, provider payloads, prompts, responses, or source-code content.

## Local and network boundaries

Known local provider roots are read only for usage token metadata or authentication evidence. Provider quota calls go directly to the relevant provider endpoint; there is no Needlbar relay or backend.

Credential resolution and provider responses stay in Rust and are redacted before any error crosses the bridge. The raw Claude credential is ephemeral and zeroizing inside
`needlbar-quota`; it is never persisted by Needlbar or exported through the C ABI. Cursor
has no credential integration or private endpoint path. Its only external action is the
fixed Spending dashboard URL, and its local usage cache is never sent over a new network
boundary.

If an active provider login child cannot be reaped within the bounded cleanup policy, the
application can reject termination while the coordinator retains that exact child for
background reaping. A later termination request retries cleanup; the app does not report
successful shutdown before its provider child has been reaped.

See [`docs/privacy.md`](privacy.md) and the provider runbooks for exact documented locations and recovery behavior.
