# Codex provider

Needlbar treats Codex local usage and Codex quota as independent streams.

## Usage source

The pinned `tokscale-core` engine reads the documented Codex local roots:

- `~/.codex/sessions`
- archived Codex sessions when available

Discovery, parsing, deduplication, aggregation, and pricing remain in `tokscale-core`. Needlbar presents normalized counts and cost, not session text or source-code content.

## Authentication source and precedence

For the primary quota request, existing Codex OAuth/auth evidence is resolved in this order:

1. `$CODEX_HOME/auth.json` when `CODEX_HOME` is set and non-empty.
2. `~/.codex/auth.json` otherwise.

Credential material remains in the Rust adapter. It is not copied into Swift state, diagnostics, logs, or bridge errors. Needlbar does not persist a replacement Codex credential or crawl browser cookies.

## Quota and fallback

The Settings **Sign in with ChatGPT** button launches the installed provider command
`codex login`; Codex owns the browser flow, OAuth callback, refresh, and credential storage.
After a successful provider login, Needlbar performs a Codex-only quota verification. It
first calls the direct Codex/OpenAI quota endpoint over bounded HTTPS using valid existing
auth evidence. When the API route reports missing or expired authentication, and the
installed CLI is available, it uses the read-only Codex app-server RPC fallback. The
fallback is bounded, uses no interactive TUI or login flow, and asks only for account/rate-
limit data. If neither route is viable, the provider reports `requiresAuthentication` or a
safe provider-unavailable state.

Usage remains available if quota retrieval fails, and quota remains independently refreshable from usage.

## Recovery and disconnect

If the Codex CLI is missing or cannot be launched, install or repair the provider-supported
Codex CLI and retry. Otherwise click **Sign in with ChatGPT**, complete the provider-owned
browser flow, and let Needlbar verify the provider quota. Ensure the intended `CODEX_HOME`
is selected. The app-server fallback also requires the `codex` executable to be installed
and discoverable. A quota verification failure does not erase a previous valid snapshot.

Needlbar does not own Codex credentials and has no Codex Disconnect button. Sign out or revoke the provider session through Codex/OpenAI-supported controls; the next Needlbar refresh will reflect the resulting authentication state.
