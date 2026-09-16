# Claude provider

Needlbar treats Claude usage and Claude quota as separate sources.

## Usage source

The pinned `tokscale-core` engine reads the documented Claude local roots:

- `~/.claude/projects`
- `~/.claude/transcripts`

Needlbar delegates discovery, parsing, deduplication, aggregation, and cost estimation to that engine. It does not copy Claude transcript parsing into the application or display transcript content.

## Authentication source and precedence

For background quota refresh, Needlbar checks existing Claude OAuth evidence without allowing
macOS UI. On macOS it first asks for the exact Claude Code generic-password Keychain service
`Claude Code-credentials` with `BackgroundNoUI`; that query cannot display a permission prompt.
If the item is not found, it falls back to the provider's file evidence:

1. `CLAUDE_CONFIG_DIR/.credentials.json` when `CLAUDE_CONFIG_DIR` is set and non-empty.
2. `~/.claude/.credentials.json` otherwise.

The raw credential stays in the Rust quota adapter. It is never placed in Swift presentation
state, diagnostics, logs, or bridge error messages. Needlbar does not trigger an unsolicited
Keychain prompt or crawl browser profiles.

Needlbar does not enumerate the Keychain or run a routine Claude login from its recovery UI.
The raw credential remains ephemeral Rust-internal data, held in a zeroizing secret wrapper and
never persisted by Needlbar, sent through Swift, or included in the C ABI, diagnostics, logs, or
errors.

## Quota and fallback

Quota is requested directly from Anthropic's OAuth usage endpoint over bounded HTTPS. A valid existing OAuth credential is used when available; known expired evidence is reported as `authenticationExpired`. Missing or unusable evidence is reported as `requiresAuthentication`.

When a refresh cannot produce quota, Needlbar keeps a previous successful reading as **Last
known**, labels it with the local **Last checked** time, and shows one safe reason. An initial
failure instead shows **Quota unavailable** without a made-up value, reset, or timestamp. The
optional **View Claude usage** action opens only `https://claude.ai/settings/usage` after an
explicit click; it does not start a CLI login or an application-owned OAuth flow. Claude Code
continues to own any browser authentication, OAuth callback, refresh, and credential storage.
There is no browser-cookie fallback or interactive login in the background refresh path. Usage
can remain visible when quota authentication fails because the two streams are independent.

## Recovery and disconnect

If Claude quota remains unavailable, use **View Claude usage** to inspect the provider-owned
subscription page if desired. Needlbar does not instruct, launch, or retry provider login from
this recovery surface. A later scheduled quota refresh can replace the last-known reading when
it succeeds. Usage remains independently available while quota recovers.

Needlbar does not own Claude credentials and therefore does not provide a Claude Disconnect button. Sign out or revoke the provider session through Claude's supported controls; Needlbar will then show the safe authentication-required state on the next refresh.
