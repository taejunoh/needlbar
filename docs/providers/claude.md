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

## Quota and fallback

Quota is requested directly from Anthropic's OAuth usage endpoint over bounded HTTPS. A valid existing OAuth credential is used when available; known expired evidence is reported as `authenticationExpired`. Missing or unusable evidence is reported as `requiresAuthentication`.

There is no browser-cookie or interactive login fallback in the v0.1 background refresh path. Usage can remain visible when quota authentication fails because the two streams are independent.

## Recovery and disconnect

Sign in or refresh the session through the Claude Code-supported app/CLI flow, then choose Retry in the Needlbar provider popover. If a custom `CLAUDE_CONFIG_DIR` is used, make sure it points to the provider's intended configuration before retrying.

Needlbar does not own Claude credentials and therefore does not provide a Claude Disconnect button. Sign out or revoke the provider session through Claude's supported controls; Needlbar will then show the safe authentication-required state on the next refresh.
