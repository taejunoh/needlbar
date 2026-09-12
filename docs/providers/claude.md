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

Needlbar does not enumerate the Keychain. When the user explicitly clicks **Sign in with
Claude**, Needlbar first runs a Claude-only no-UI check of the existing sign-in. A fresh result
connects without launching the CLI. Missing or expired authentication starts the provider-owned
CLI flow; a Keychain permission result performs exactly one user-initiated verification of the
same exact item, which may show a macOS prompt, without launching the CLI. Other failures stop
safely. After a successful CLI flow, Needlbar may likewise request that exact item once for
Claude-only quota verification. The raw credential remains ephemeral Rust-internal data, held in
a zeroizing secret wrapper and never persisted by Needlbar, sent through Swift, or included in
the C ABI, diagnostics, logs, or errors.

## Quota and fallback

Quota is requested directly from Anthropic's OAuth usage endpoint over bounded HTTPS. A valid existing OAuth credential is used when available; known expired evidence is reported as `authenticationExpired`. Missing or unusable evidence is reported as `requiresAuthentication`.

When that no-UI check finds missing or expired authentication, the Settings **Sign in with
Claude** button launches the installed provider command `claude auth login --claudeai`.
Claude Code owns the browser flow, OAuth callback, refresh, and credential storage. There is no
browser-cookie fallback and no interactive login in the v0.1 background refresh path. Usage can
remain visible when quota authentication fails because the two streams are independent.

## Recovery and disconnect

If the Claude CLI is missing, install or repair the provider-supported Claude Code CLI and
retry. Otherwise click **Sign in with Claude**, complete the provider-owned browser flow,
and allow the exact macOS Keychain item only if you want immediate quota verification.
If Keychain access is denied or cancelled, retry after adjusting macOS permission or
complete provider re-authentication. If a custom `CLAUDE_CONFIG_DIR` is used, make sure it
points to the provider's intended configuration before retrying. Usage remains independently
available while quota recovers.

Needlbar does not own Claude credentials and therefore does not provide a Claude Disconnect button. Sign out or revoke the provider session through Claude's supported controls; Needlbar will then show the safe authentication-required state on the next refresh.
