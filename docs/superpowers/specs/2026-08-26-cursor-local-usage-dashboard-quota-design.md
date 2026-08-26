# Needlbar Cursor Local Usage and Dashboard Quota Design

**Status:** Approved on 2026-08-26
**Scope:** Post-v0.1 amendment replacing Cursor session-token authentication, remote usage hydration, and personal quota retrieval
**Base contracts:**

- `docs/superpowers/specs/2026-08-13-needlbar-v0.1-design.md`
- `docs/superpowers/specs/2026-08-25-provider-managed-browser-login-design.md`
- `docs/superpowers/specs/2026-08-26-cursor-paste-command-design.md`

## 1. Decision

Needlbar will stop accepting, storing, validating, or replaying Cursor browser-session tokens. It will stop calling Cursor's private individual usage and quota endpoints.

Cursor support becomes two deliberately separate capabilities:

- Usage: read an already-existing local Tokscale-compatible Cursor cache at `~/.config/tokscale/cursor-cache/usage.csv` through the pinned `tokscale-core` engine.
- Quota: direct the user to Cursor's provider-owned Spending dashboard at the fixed URL `https://cursor.com/dashboard/spending`.

Needlbar does not claim that the local cache is current and does not create or refresh it. When the cache is absent, Cursor usage is unavailable. Cursor quota is unavailable inside Needlbar regardless of cache state.

This amendment supersedes every earlier requirement for Cursor session-token Connect/Reconnect/Disconnect, `/api/usage-summary`, remote usage-export hydration, `connectCursor`, forced Cursor synchronization, and Cursor token-field paste acceptance. It does not change Claude or Codex behavior.

## 2. Rationale and Rejected Alternatives

Live acceptance established that a current signed-in Cursor browser session could open the Spending dashboard, while replaying the copied session value to Needlbar's private endpoint path returned `requiresAuthentication` and persisted no session. Cursor's public individual-plan documentation points users to the Spending dashboard and does not publish a supported third-party personal usage/quota credential handoff.

The rejected alternatives are:

1. Keep the session field only for usage export. This preserves the same unsupported cookie-replay contract and leaves the user with an unreliable credential workflow.
2. Automate a browser or crawl browser profiles. This expands the privacy boundary, depends on browser internals, and contradicts the local-first contract.
3. Use team/admin API keys for all users. Cursor's documented API contract does not cover the personal-plan quota experience Needlbar is implementing.

The chosen design removes unsupported authentication behavior rather than presenting a connection state Needlbar cannot verify reliably.

## 3. User Experience

### 3.1 Settings

The Cursor connection row contains:

- title: `Cursor`,
- explanatory copy: `Usage is read from an existing local cache. Quota is available in Cursor Spending.`,
- button: `Open Cursor Spending`.

The row contains no secure field, Connect, Reconnect, Disconnect, Connected state, or token-related status copy. The button opens only `https://cursor.com/dashboard/spending` through the macOS workspace URL opener.

Claude and Codex connection rows remain unchanged.

### 3.2 Provider popover

Cursor quota-unavailable presentation offers `Open Cursor Spending`. It never offers `Open Settings` as an authentication recovery action and never asks for a session token.

Cursor usage remains visible when the existing local cache produces data. Quota unavailability must not erase or hide valid Cursor usage, and missing usage must not change the dashboard action.

### 3.3 Menu-bar metrics

Cursor's `quota remaining` title metric renders the existing unavailable state because Needlbar has no supported quota value. `tokens today` and `estimated cost today` continue to render when the local cache provides data.

Overview quota selection excludes Cursor because it has no eligible quota window. Existing Claude and Codex quota selection remains unchanged.

## 4. Architecture and Ownership

### 4.1 Rust usage path

`needlbar-bridge` asks `tokscale-core` to aggregate local sources without running Cursor source synchronization. The existing local cache path remains discoverable by the pinned engine.

The production and C ABI paths no longer distinguish normal and forced Cursor usage refreshes. Manual refresh re-reads local sources; it does not make a Cursor network request.

`needlbar-source-sync` has no remaining v0.1 responsibility after this amendment and is removed from the workspace. No replacement Cursor parser is added.

### 4.2 Rust quota path

The Cursor quota provider performs no credential, filesystem, or network I/O. It returns a provider-scoped `providerUnavailable` error with safe generic copy and no authentication action.

The following contracts are removed:

- `WorkosCursorSessionToken` handling,
- `https://cursor.com/api/usage-summary`,
- Cursor personal quota response parsing and fixtures,
- `CursorQuotaSource`,
- `QuotaAction::ConnectCursor`,
- `cursor.plan` and `cursor.onDemand` windows.

The all-provider quota envelope continues to include successful Claude/Codex data and a Cursor-scoped unavailable error. Usage and quota remain independently refreshable and independently fallible.

### 4.3 C ABI and NeedlbarCore

The following exports are removed:

```c
const char *needlbar_forced_usage_snapshot_json(void);
const char *needlbar_cursor_import_session_json(const char *session_token);
const char *needlbar_cursor_clear_session_json(void);
```

The normal `needlbar_usage_snapshot_json` export remains. `UsageRepository` and `RefreshCoordinator` remove forced-Cursor-sync parameters and queued forced-sync state. A manual refresh coalesces the same local usage read and quota refresh used elsewhere.

Diagnostics describe Cursor usage as `local` and Cursor quota as `unavailable`; they no longer report `cursorExport`, `session`, `cursorSyncFailed`, or a Cursor connection action.

### 4.4 AppKit presentation

The fixed dashboard action is presentation-owned. It is not serialized through Rust error envelopes because it is a stable product navigation rule, not provider data.

The URL opener is injected at the application/controller boundary for tests. UI code requests the typed Cursor Spending action and cannot provide an arbitrary URL.

## 5. Credential Cleanup Migration

An older Needlbar build may have created `~/Library/Application Support/Needlbar/cursor-session.json`. The updated app removes this Needlbar-owned credential copy once during startup or first bridge initialization, using the existing descriptor-relative no-follow session-store deletion behavior before that implementation is retired.

The migration:

- removes only Needlbar's own Cursor session file,
- does not modify Cursor.app, browser cookies, the Cursor account, or the local usage cache,
- treats an absent file as success,
- never reads, logs, serializes, or displays the credential value,
- records no credential-derived diagnostic data,
- fails safely if the path cannot be removed and never resumes using the credential.

After the cleanup path has run, no production code can create or consume that file. The implementation status will explicitly record whether a file was removed during local acceptance without exposing its contents.

## 6. Security and Privacy

- Needlbar does not request a Cursor session token.
- Needlbar does not read Cursor browser profiles, browser cookies, or Cursor.app credentials.
- Needlbar does not call private Cursor individual usage or quota endpoints.
- Needlbar opens only the fixed HTTPS Spending URL after an explicit user action.
- Existing local usage data never crosses a new network boundary.
- The obsolete Needlbar-owned session credential is deleted without reading it.
- Claude and Codex credential boundaries remain unchanged.

## 7. Failure and State Rules

- Existing valid Cursor cache data remains usable even though quota is unavailable.
- Missing or malformed local Cursor cache produces the existing provider-scoped usage failure without affecting Claude or Codex.
- Cursor quota consistently produces `providerUnavailable`; it is not `requiresAuthentication` and has no `connectCursor` action.
- Opening the Spending URL failure is transient presentation state and does not mutate usage or quota snapshots.
- Manual refresh cannot imply a forced remote Cursor refresh.
- Stale local cache files are not deleted by this amendment.
- The credential cleanup migration never blocks Claude/Codex refresh or application launch.

## 8. Testing Contract

Required automated coverage:

- an existing local Cursor cache still produces Cursor usage through `tokscale-core`,
- an absent local cache produces Cursor `noUsageData`,
- usage refresh performs no Cursor transport or session lookup,
- Cursor quota performs no transport/session I/O and returns `providerUnavailable`,
- the all-provider quota envelope preserves Claude/Codex data alongside Cursor unavailability,
- the removed C functions are absent from the public header and all Swift callers use the normal usage export,
- manual-refresh coalescing remains correct after forced-Cursor-sync state removal,
- Settings contains no Cursor token field or connection controls and requests the typed Spending action,
- the provider popover selects `Open Cursor Spending` for Cursor quota unavailability,
- the action opens exactly `https://cursor.com/dashboard/spending`,
- arbitrary URLs cannot enter the typed action,
- the credential cleanup migration is idempotent, rejects unsafe path shapes through the existing no-follow behavior, never reads the token, and leaves the usage cache untouched,
- diagnostics expose `local`/`unavailable` without obsolete session/export/action strings,
- credential canaries remain absent from envelopes, diagnostics, logs, and Swift state,
- `make test` and the packaged-app smoke pass.

Deleted tests and fixtures must be limited to behavior this amendment removes. The sanitized Cursor usage CSV fixture remains because it protects the local-cache behavior.

## 9. Documentation Amendments

Implementation updates:

- `README.md`,
- `docs/architecture.md`,
- `docs/privacy.md`,
- `docs/providers/cursor.md`,
- `docs/STATUS.md`,
- the prior browser-login and Cursor-paste amendment documents with clear superseded notes.

Documentation must not instruct users to find, copy, or paste Cursor cookies or session tokens.

## 10. Acceptance Criteria

1. Settings and provider popovers contain no Cursor credential input or connection workflow.
2. Both Cursor actions open the exact provider-owned Spending dashboard URL.
3. Needlbar makes no Cursor authentication, usage-export, or personal-quota network request.
4. An existing compatible local cache continues to provide Cursor usage through the pinned engine; an absent cache is reported honestly as unavailable.
5. Cursor quota is unavailable inside Needlbar and does not affect Claude/Codex quota or valid Cursor usage.
6. Manual refresh re-reads local usage without claiming or attempting remote Cursor synchronization.
7. Any obsolete Needlbar-owned Cursor session file is removed without reading or exposing it, while the usage cache is preserved.
8. Claude/Codex browser-login behavior, usage/quota independence, and last-known-good behavior remain intact.
9. Documentation contains no live instruction for session-token extraction or private Cursor endpoint use.
10. The complete project verification and packaged-app UI smoke pass.

## 11. Provider References

- Cursor individual usage and limits are presented through the Spending dashboard: <https://prod.cursor.com/help/models-and-usage/usage-limits>
- Cursor's documented Admin API is scoped to team administration rather than a personal-plan quota handoff: <https://docs.cursor.com/en/account/teams/admin-api>
- Cursor CLI browser authentication does not document a third-party personal usage/quota credential handoff: <https://docs.cursor.com/en/cli/reference/authentication>
