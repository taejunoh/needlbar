# Claude provider

Needlbar treats Claude usage and Claude quota as separate sources.

## Usage source

The pinned `tokscale-core` engine reads the documented Claude local roots:

- `~/.claude/projects`
- `~/.claude/transcripts`

Needlbar delegates discovery, parsing, deduplication, aggregation, and cost estimation to that engine. It does not copy Claude transcript parsing into the application or display transcript content.

## Authentication source and precedence

For background quota refresh, Needlbar reads existing file-based Claude OAuth evidence only:

1. `CLAUDE_CONFIG_DIR/.credentials.json` when `CLAUDE_CONFIG_DIR` is set and non-empty.
2. `~/.claude/.credentials.json` otherwise.

The raw credential stays in the Rust quota adapter. It is never placed in Swift presentation state, diagnostics, logs, or bridge error messages. Needlbar does not trigger an unsolicited Keychain prompt or crawl browser profiles.

Claude Code's current macOS OAuth credential is also stored by Claude Code in the exact
generic-password service `Claude Code-credentials`. Needlbar does not enumerate the
Keychain. After the user explicitly clicks **Sign in with Claude** and the provider-owned
login command completes, Needlbar may request that exact item for Claude-only quota
verification. macOS may show a permission prompt at that point. The raw credential remains
ephemeral Rust-internal data, held in a zeroizing secret wrapper and never persisted by
Needlbar, sent through Swift, or included in the C ABI, diagnostics, logs, or errors.

## Quota and fallback

Quota is requested directly from Anthropic's OAuth usage endpoint over bounded HTTPS. A valid existing OAuth credential is used when available; known expired evidence is reported as `authenticationExpired`. Missing or unusable evidence is reported as `requiresAuthentication`.

The Settings **Sign in with Claude** button launches the installed provider command
`claude auth login --claudeai`; Claude Code owns the browser flow, OAuth callback, refresh,
and credential storage. There is no browser-cookie fallback and no interactive login in
the v0.1 background refresh path. Usage can remain visible when quota authentication fails
because the two streams are independent.

## Recovery and disconnect

If the Claude CLI is missing, install or repair the provider-supported Claude Code CLI and
retry. Otherwise click **Sign in with Claude**, complete the provider-owned browser flow,
and allow the exact macOS Keychain item only if you want immediate quota verification.
If Keychain access is denied or cancelled, retry after adjusting macOS permission or
complete provider re-authentication. If a custom `CLAUDE_CONFIG_DIR` is used, make sure it
points to the provider's intended configuration before retrying. Usage remains independently
available while quota recovers.

Needlbar does not own Claude credentials and therefore does not provide a Claude Disconnect button. Sign out or revoke the provider session through Claude's supported controls; Needlbar will then show the safe authentication-required state on the next refresh.
