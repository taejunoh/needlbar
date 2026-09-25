# Claude Code status-line quota bridge

**Date:** 2026-09-25

**Status:** Written design for review; not yet implemented.

**Scope:** Restore unattended, clearly timestamped Claude subscription-quota
readings without asking users to log in to Needlbar repeatedly or letting
Needlbar manage Claude credentials.

## Context and decision

The installed v0.3.4 app repeatedly reports `keychainCredentialExpired` on its
five-minute direct quota refresh. Claude Code can still report `loggedIn: true`:
that reports its own login state, not that the access token Needlbar found is
currently usable. The browser usage page can likewise be signed in while the
direct Needlbar lookup fails. Neither observation proves a Needlbar quota
refresh. The current last-known UI avoids inventing freshness, but it does not
solve the missing new observations.

Claude Code's documented status-line JSON provides `rate_limits.five_hour` and
`rate_limits.seven_day` `used_percentage` and `resets_at`. It does **not**
document a Fable-specific rate-limit field. Claude Code owns the production of
this JSON and its authentication. We will offer an explicit, reversible local
status-line bridge as a second quota source. The user's existing status-line
command must keep running and producing the same visible output. This is not a
polling API: updates occur only when Claude Code emits status-line data during
an active session, including its documented event or configured timer triggers.
Needlbar must not claim background liveness while no new data is emitted.

Alternatives considered:

1. **Status-line bridge (selected):** receive provider-emitted, allowlisted
   quota numbers; preserve the existing status line and keep separate source
   timestamps. No new token read, login flow, or refresh-token rotation.
2. **Needlbar-owned OAuth renewal (rejected):** would collect/intermediate
   credentials, create rotation races with Claude Code, and expand the existing
   integration across a provider credential-use boundary.
3. **Keep only last-known values (insufficient):** honest when retrieval fails
   but does not meet the request to see updated quota without repeated action.

The existing direct quota path remains unchanged in this project increment.
Its success can still provide 5-hour, 7-day, and Fable readings. This design
does not establish that path as a provider-supported third-party API; a
separate compatibility review may retire or replace it. The bridge must never
read or store Claude OAuth access/refresh tokens, browser cookies, or raw
credential files.

## Opt-in, installation, and restoration

- Add one Claude Settings control, initially off, explaining that it connects
  Claude Code's local status-line data and only updates while Claude Code emits
  it. Enabling requires one explicit user action. Do not silently change any
  Claude Code settings during app launch, refresh, upgrade, or uninstall.
- Before installation, inspect the effective user `statusLine` entry and
  require `type: command`. If absent, offer an ordinary Needlbar-provided
  status line. If present, preserve the **entire** original object and exact
  command string in a private, mode-0600 local backup, with no logging or
  analytics of that string. The entry may contain user-authored shell code or
  secrets; it is never shown in diagnostic output.
- Install a Needlbar-owned local helper/wrapper by an atomic, narrow edit of
  the single `statusLine` object. Re-read and compare the settings immediately
  before replacement; abort rather than lose a concurrent user edit. Retain
  unrelated `settings.json` fields and
  preserve non-command status-line options (such as `padding` and
  `refreshInterval`). Never add a timer implicitly or change the user's
  existing refresh cadence. The wrapper path must survive normal app upgrades,
  or the app must detect and repair only its own stale path with the user's
  connection still enabled. A signed, versioned helper and its lifecycle are
  part of implementation planning; do not rely on a temporary build path.
- The wrapper reads Claude Code's stdin once, parses only the documented quota
  fields into a bounded local record, then forwards the **original stdin** to
  the original command and forwards that command's stdout/stderr and exit
  status. Stream all stdin to the original command while retaining only a
  bounded side copy for parsing; on overflow, skip extraction but still
  forward every byte. Preserve working directory, environment, shell
  invocation semantics, signals, and backpressure. The original command must
  run even when parsing or writing the Needlbar record fails. Avoid shell
  interpolating the original command into the replacement settings value;
  load it from the private backup instead.
- If the user's current status-line object no longer matches the installed
  Needlbar wrapper, do not overwrite it. Surface a brief `Configuration
  changed` state and require explicit reconnection. Turning the bridge off
  restores the exact original object only when ownership still matches;
  otherwise leave user edits untouched and remove only Needlbar-owned state.
  For an originally absent entry, remove only the owned entry. Installation
  and restoration must be idempotent and recover from process interruption.
  In-flight wrappers retain immutable invocation metadata long enough to
  finish the original command. A connection generation is checked immediately
  before cache publication, so an old wrapper cannot recreate the cache after
  disconnect or overwrite a later reconnection.
- Limit one-time config backup and cache files to the user's local account,
  with restrictive permissions and atomic replacement. Never persist or log
  the full status-line JSON, cwd, repository, model, session ID, or the
  original command's stdin/output. Disconnect removes the Needlbar quota cache
  after in-flight publications are fenced; it does not delete the user's
  original status-line script. Remove the private backup only when no running
  wrapper still needs it.
- Initial scope is the default Claude Code user configuration. Detect a
  nondefault `CLAUDE_CONFIG_DIR` when visible and report that this
  configuration is not yet connected; do not modify an unverified directory.
  Project-level settings may override the user entry. Connection means the
  wrapper is installed, not that an active session has emitted data; show
  `Waiting for Claude Code data` until an actual observation arrives.

## Data contract and freshness

- Accept only finite `used_percentage` in `[0, 100]` and integer Unix-second
  `resets_at` values when present. Convert used to remaining as `100 - used`;
  never infer Fable from the 7-day field. Missing, malformed, or out-of-range
  windows are independently unavailable, not zero. Preserve provider reset
  timestamps separately from local receipt time.
- Serialize only the validated five-hour and seven-day windows plus a schema
  version and a separate local `receivedAt` per window in the local record.
  Missing or malformed data must not advance that window's timestamp. Bound
  the parsing side buffer and record size while leaving passthrough stdin
  intact; reject symlinks/unexpected ownership and permissions on files, and
  use atomic writes. An older or malformed record cannot replace a newer
  valid observation. Multiple concurrent Claude Code sessions must not
  regress the stored observation per window.
- Keep direct-source and status-line-source observations separate in the
  domain model. On a fresh direct success, show direct 5-hour/7-day/Fable.
  When direct lookup fails but recent status-line data exists, show its
  5-hour/7-day figures with source and local receipt time. Fable remains
  independently last-known or unavailable with its own last-success time.
  Do not copy the status-line timestamp to Fable.
- A status-line emission is not evidence of a new provider fetch. Use
  `Reported by Claude Code` rather than `Live` for this source, and treat
  `receivedAt` as local receipt time, not server-observation time. Repeated
  identical `(used, resetAt)` values may not extend the apparent freshness;
  record the first receipt of a stable value separately if needed. Set a
  bounded display recency limit in the implementation plan (proposed: 15
  minutes since a genuinely changed observation); beyond it show `Last known`.
  This is a recency heuristic, not a guarantee of server freshness. If a reset
  time passes without a newer window, mark it stale; do not turn an old
  0%-remaining observation into a fresh 100%. A direct request failure must
  not erase a valid status-line observation, and a status-line parse failure
  must not erase direct data.
- The app's existing five-minute quota refresh may read the local status-line
  record without launching Claude Code or causing model/API requests. File
  watching may improve latency, but must not bypass single-flight state
  application or increase provider network requests.

## Presentation

- The Claude row shows the best available *recently reported* main quota
  value with a precise provenance label (`Reported by Claude Code` or direct
  Claude usage) and actual source/receipt time; it must not imply the browser
  page and Needlbar share a session or claim a server fetch occurred.
  Stale values say `Last known` and display their actual observation time.
- Fable is a distinct line: fresh when the direct source succeeds, otherwise
  clearly `Last known` or `Unavailable`. Do not show a stale reset as a live
  countdown. A status-line observation cannot clear a Fable retrieval error.
- When no current source exists, show an unavailable state and keep the
  explicit `View Claude usage` link. Do not show `Sign-in required` merely
  because the direct Keychain token is expired while Claude Code is signed in
  and status-line data is available. Settings shows connection status for the
  **bridge**, not an assertion that Claude credentials are valid.
- No modal, alert, or repeated login prompt is introduced for normal stale
  data. Clearly explain in Settings that the first value may remain absent
  until an active Claude Code session emits status-line JSON.

## Verification and acceptance

Use synthetic status-line JSON and synthetic existing commands; do not use live
tokens or print the user's actual command. Test first, then run focused tests,
`make test`, and `git diff --check`.

- Parsing: complete, missing, null, malformed, out-of-range, oversized,
  older, concurrent, repeated-identical, and reset-passed cases; independent
  five-hour/seven-day timestamps and used-to-remaining conversion.
- Process compatibility: original command sees byte-for-byte stdin and
  environment and preserves stdout/stderr/exit behavior, including helper
  parse/write failure and cancellation. Oversized input still reaches the
  original command in full. No raw JSON leaks into cache/logs.
- Config lifecycle: existing/absent command, non-command entry, exact
  backup/restore, user edits after installation, repeated enable/disable,
  interruption recovery, concurrent user edit, project-level override,
  nondefault config directory, disconnect/reconnect during an active wrapper,
  app upgrade, bad permissions, and symlink attack.
- State/UI: direct success, direct failure with fresh status-line, stale
  status-line, no sample, Fable direct success/failure, reset expiry,
  provenance/receipt-time labels, and no repeated login prompts.
- Native acceptance on a diagnostic build: opt in once, compare 5-hour/7-day
  values with Claude Code's own usage display after a real status-line event,
  confirm the existing status line still renders, then disconnect and verify
  exact restoration. Do not describe this as installed or released until the
  corresponding packaging and live checks actually succeed.

## Sources and relation to prior designs

- [Claude Code status-line documentation](https://code.claude.com/docs/en/statusline)
  describes the JSON fields, shell-command/stdin contract, and event-driven
  refresh behavior.
- [Anthropic credential-use policy](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use)
  constrains third-party credential collection and intermediation.

This design amends the Claude quota-source and independent-Fable-freshness
portions of the approved 2026-09-15 passive-recovery design. The retained
direct token-reading path remains a separate, unresolved provider-policy and
compatibility concern; this bridge must not be described as approval of that
path or of the combined integration. This design does not authorize a new
OAuth client, a refresh-token fallback, repository analytics changes, public
release, or automatic modification of Claude Code settings.
