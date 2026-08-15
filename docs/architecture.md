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
                ├── Cursor source-sync adapter
                ├── quota aggregation
                ├── panic/error boundary
                └── Rust-owned allocation/freeing
                    ├── needlbar-source-sync
                    │   └── Cursor export hydration and cache freshness
                    ├── needlbar-quota
                    │   └── Claude, Codex, and Cursor quota/auth adapters
                    └── vendor/tokscale-core
                        └── pinned local usage discovery/parsing/aggregation
```

### Ownership

`tokscale-core` owns local session discovery, parsing, deduplication, aggregation, model pricing, cost estimation, and normalized usage values. Needlbar passes it the selected home and client scope; it does not duplicate provider token-history parsers.

`needlbar-source-sync` owns only provider-specific source hydration needed before usage parsing. In v0.1 that is Cursor's bounded usage-export request, atomic cache replacement, freshness marker, and safe local path handling. It does not calculate subscription quota.

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
Cursor export -> source-sync -> cache ────┘

Claude OAuth evidence -> Anthropic usage API ───────┐
Codex OAuth -> OpenAI usage API -> CLI RPC fallback ├─> quota envelope
Cursor Needlbar session -> Cursor usage API ───────┘
```

Quota collection runs providers independently and preserves usable partial results and provider-scoped safe errors. Cursor source synchronization runs before the usage scan; a failed sync can still leave a previous valid Cursor cache available to `tokscale-core`.

## Bridge contract

The stable C surface is:

```c
const char *needlbar_usage_snapshot_json(void);
const char *needlbar_quota_snapshot_json(void);
const char *needlbar_diagnostics_json(void);
void needlbar_free_string(const char *ptr);
```

Each snapshot is a UTF-8 JSON envelope with `schemaVersion`, `ok`, `generatedAt`, `data`, and `errors`. Rust owns each returned string; Swift frees every non-null pointer exactly once through `needlbar_free_string`. Panics do not unwind across the ABI. Errors contain provider-safe codes and messages only.

Diagnostics use fixed subsystem/provider status and source labels. They do not include credentials, cookies, account identifiers, raw local paths, provider payloads, prompts, responses, or source-code content.

## Local and network boundaries

Known local provider roots are read only for usage token metadata or authentication evidence. Provider quota calls go directly to the relevant provider endpoint; there is no Needlbar relay or backend. Credential resolution and provider responses stay in Rust and are redacted before any error crosses the bridge. Cursor session import is an explicit Settings action, not a silent browser-cookie scan.

See [`docs/privacy.md`](privacy.md) and the provider runbooks for exact documented locations and recovery behavior.
