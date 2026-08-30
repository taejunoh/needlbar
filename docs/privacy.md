# Privacy and data handling

Needlbar v0.1 is local-first.

- There is no Needlbar backend, account, hosted sync service, or telemetry.
- Needlbar does not upload token history, prompts, assistant responses, source code, file paths, account identifiers, or provider credentials.
- It does not display prompt/response text or source-code content. The local usage engine reads known provider sources only to derive token metadata and cost information.
- Claude and Codex quota requests go directly to their providers. Needlbar does not proxy or relay those requests.
- Claude and Codex browser sign-in is explicit. Their buttons launch the installed provider
  CLI, which owns browser navigation, OAuth callbacks, refresh, and credential storage.
  Needlbar never implements a duplicate OAuth flow or silently crawls browser profiles for
  cookies.
- Cursor has no Needlbar credential integration, private endpoint, or remote usage hydration.
  Its usage is local-only, and its quota action opens the fixed provider-owned Spending
  dashboard URL.

## Local reads

The following are the documented v0.1 boundaries. Paths are examples relative to the current user's home directory; they are not emitted in diagnostics or bridge errors.

| Provider | Usage metadata | Quota/authentication evidence |
| --- | --- | --- |
| Claude | `~/.claude/projects` and `~/.claude/transcripts`, delegated to the pinned `tokscale-core` engine | Background refresh uses existing file evidence from `CLAUDE_CONFIG_DIR/.credentials.json` when set, otherwise `~/.claude/.credentials.json`. After an explicit provider sign-in, macOS may authorize one exact `Claude Code-credentials` Keychain item for Claude quota verification. |
| Codex | `~/.codex/sessions` and archived sessions when available, delegated to `tokscale-core` | `$CODEX_HOME/auth.json` when `CODEX_HOME` is set; otherwise `~/.codex/auth.json` |
| Cursor | An existing compatible local cache at `~/.config/tokscale/cursor-cache/usage.csv`, read by `tokscale-core` | None. Cursor quota is unavailable inside Needlbar and is represented by the fixed Spending dashboard action. |

Needlbar does not create or refresh the Cursor cache and does not read Cursor.app credentials,
browser profiles, or browser cookies. The bridge migration may remove only the obsolete
Needlbar-owned `~/Library/Application Support/Needlbar/cursor-session.json` file without
reading it; an absent file is success, and the local usage cache is never removed. Raw
credentials are never copied into Swift or UserDefaults, and diagnostics expose fixed source
labels rather than paths.

## Local JSON export

Settings exposes one user-initiated JSON export for the current normalized snapshot. The destination is selected by the user and remains a local file; Needlbar does not upload it, refresh provider data, or authenticate while exporting. The writer creates or replaces the selected file with mode `0600`, using a private same-directory temporary file and an atomic commit.

The document contains only normalized usage and quota values, UTC timestamps, fixed non-user-specific quota category labels (`claude.session`, `claude.weekly`, `codex.primary`, and `codex.secondary`), and safe freshness/status codes. These labels are schema categories, not identity data. The export excludes credentials, account IDs, user IDs, organization IDs, device IDs, provider-generated IDs, raw local paths, raw provider responses or diagnostics, prompts, assistant responses, and source code. Quota window titles and underlying error messages are not exported.

## Network requests

Usage and quota have separate network behavior:

- Claude quota uses the Anthropic OAuth usage endpoint with existing local OAuth evidence.
  Background Keychain access is interaction-forbidden and never prompts. Only the explicit
  post-login Claude verification path may allow a macOS Keychain permission prompt.
- Codex quota tries the provider usage API first and can use the installed Codex CLI app-server RPC fallback when the API credential route is unavailable.
- Cursor makes no authentication, usage-export, or personal-quota request. Clicking
  `Open Cursor Spending` hands only `https://cursor.com/dashboard/spending` to the macOS
  workspace URL opener.

Requests are bounded and errors are redacted. Needlbar does not log authorization headers,
cookies, response bodies, prompt text, response text, or source code. Raw Claude credential
material is held only ephemerally inside the Rust quota adapter, with zeroizing storage where
Needlbar owns the buffer; it is not persisted by Needlbar, copied into Swift, or exposed
through the C ABI. A failed request leaves the previous valid snapshot available where the
subsystem supports last-known-good behavior.

## User controls and recovery

Claude and Codex use provider-native CLI/browser sign-in. Needlbar does not own their
credentials and has no separate disconnect action; sign out or revoke access through the
provider's supported app/CLI controls, then retry in Needlbar. If the CLI is not installed,
Needlbar reports a provider-scoped failure and leaves other providers available. If Claude
Keychain access is denied or cancelled, grant access in macOS when appropriate or complete
provider re-authentication, then retry; Needlbar does not broaden the Keychain query or fall
back to browser-cookie crawling.

Cursor Settings contains one `Open Cursor Spending` action and no credential field or
connection controls. The provider popover offers the same action when Cursor quota is
unavailable. The action opens exactly `https://cursor.com/dashboard/spending`; a failure to
open it is transient UI state and does not mutate usage or quota snapshots.

## What may leave the machine

Only the minimum normalized data needed for Claude and Codex quota requests leaves the machine,
and those requests go directly to their providers. Opening Cursor Spending navigates the
user's browser to Cursor's provider-owned page; Needlbar sends no Cursor credential, local
usage cache, or private endpoint request. Needlbar has no destination to receive telemetry or
content uploads. The app presents normalized counts, estimated costs, quota percentages, reset
timestamps, freshness, and safe error states—not conversation or source content.
