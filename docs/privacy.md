# Privacy and data handling

Needlbar v0.1 is local-first.

- There is no Needlbar backend, account, hosted sync service, or telemetry.
- Needlbar does not upload token history, prompts, assistant responses, source code, file paths, account identifiers, or provider credentials.
- It does not display prompt/response text or source-code content. The local usage engine reads known provider sources only to derive token metadata and cost information.
- Quota network requests go directly to the relevant provider. Needlbar does not proxy or relay those requests.
- Cursor browser/session import is explicit. Needlbar never silently crawls browser profiles for cookies.

## Local reads

The following are the documented v0.1 boundaries. Paths are examples relative to the current user's home directory; they are not emitted in diagnostics or bridge errors.

| Provider | Usage metadata | Quota/authentication evidence |
| --- | --- | --- |
| Claude | `~/.claude/projects` and `~/.claude/transcripts`, delegated to the pinned `tokscale-core` engine | `CLAUDE_CONFIG_DIR/.credentials.json` when `CLAUDE_CONFIG_DIR` is set; otherwise `~/.claude/.credentials.json` |
| Codex | `~/.codex/sessions` and archived sessions when available, delegated to `tokscale-core` | `$CODEX_HOME/auth.json` when `CODEX_HOME` is set; otherwise `~/.codex/auth.json` |
| Cursor | Cursor usage export hydrated into `~/.config/tokscale/cursor-cache/usage.csv`; sync attempt marker is stored beside it | Needlbar-owned `~/Library/Application Support/Needlbar/cursor-session.json`, created only by explicit Settings connection |

Reads are bounded to these known provider locations. Needlbar does not copy raw credentials into Swift or UserDefaults, and diagnostics expose fixed source labels rather than paths. Cursor's session and cache files are private local files; the session file is removed by Cursor Disconnect, while provider account access is not revoked by Needlbar.

## Network requests

Usage and quota have separate network behavior:

- Claude quota uses the Anthropic OAuth usage endpoint with existing local OAuth evidence.
- Codex quota tries the provider usage API first and can use the installed Codex CLI app-server RPC fallback when the API credential route is unavailable.
- Cursor usage export and quota use direct Cursor HTTPS endpoints. The Cursor session is sent only to Cursor's endpoint in the required cookie header.

Requests are bounded and errors are redacted. Needlbar does not log authorization headers, cookies, response bodies, prompt text, response text, or source code. A failed request leaves the previous valid local usage cache or snapshot available where the subsystem supports last-known-good behavior.

## User controls and recovery

Claude and Codex use provider-native app/CLI sign-in. Needlbar does not own their credentials and has no separate disconnect action; sign out or revoke access through the provider's supported app/CLI controls, then retry in Needlbar.

Cursor Connect/Reconnect is an explicit Settings action. The entered session value is submitted directly to the Rust bridge for verification and is cleared from the form immediately. Cursor Disconnect removes Needlbar's stored session evidence; it does not revoke a Cursor account or imply deletion of the local usage cache. Connect again with a current provider-supported session when quota needs authentication.

## What may leave the machine

Only the minimum normalized data needed for direct provider quota requests leaves the machine: provider-authenticated quota requests and Cursor's explicit usage export. Needlbar has no destination to receive telemetry or content uploads. The app presents normalized counts, estimated cost, quota percentages, reset timestamps, freshness, and safe error states—not conversation or source content.
