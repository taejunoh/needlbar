# Needlbar Provider-Managed Browser Login Design

> **SUPERSEDED FOR CURSOR — 2026-08-26:** This document is retained as historical design
> record only. Its Cursor session-token, remote usage/quota, and paste/connection
> requirements are inactive. The approved amendment
> [`2026-08-26-cursor-local-usage-dashboard-quota-design.md`](2026-08-26-cursor-local-usage-dashboard-quota-design.md)
> is authoritative for Cursor. Claude and Codex requirements below remain active unless
> that amendment explicitly changes them.

**Status:** Approved on 2026-08-25
**Scope:** Post-v0.1 design amendment for Claude and Codex authentication UX
**Base contract:** `docs/superpowers/specs/2026-08-13-needlbar-v0.1-design.md`

## 1. Decision

Needlbar will offer explicit browser-login actions for Claude and Codex from its own UI, while the providers continue to own the browser flow, OAuth callback, refresh tokens, and credential storage.

- Claude uses the installed Claude Code CLI command `claude auth login --claudeai`.
- Codex uses the installed Codex CLI command `codex login`.
- Cursor keeps the existing explicit Needlbar session-token Connect/Reconnect/Disconnect flow.

This amendment does not turn Needlbar into an OAuth client. Needlbar does not register redirect URIs, receive authorization codes, read browser profiles, duplicate provider tokens into its own store, or persist login output.

On macOS, current Claude Code stores subscription OAuth credentials in the encrypted macOS Keychain. The user approved a narrow exception required for quota verification: after an explicit `Sign in with Claude` action, the Rust quota layer may request access to the exact provider-owned `Claude Code-credentials` item. The raw credential is parsed, used, and discarded inside Rust; it never crosses the C ABI or enters Swift state, diagnostics, logs, preferences, or a Needlbar credential store. Background refresh may attempt only non-interactive Keychain access and must fail without displaying UI when macOS would require a prompt.

The split is deliberate. Cursor documents a provider-managed CLI browser login, but it does not document a personal usage/quota interface or credential handoff that Needlbar can use after that login. Running `cursor-agent login` would therefore not establish the existing Cursor usage/quota data path. Cursor remains on the explicit, validated session-token path until Cursor publishes a suitable integration contract.

## 2. User Experience

### 2.1 Settings

The Connections section presents three distinct provider rows.

- Claude: `Sign in with Claude` starts the Claude Code browser flow.
- Codex: `Sign in with ChatGPT` starts the Codex browser flow.
- Cursor: the existing secure session-token field and Connect/Reconnect/Disconnect actions remain unchanged.

Claude and Codex show transient, non-persistent states:

- idle,
- opening the provider login,
- waiting for browser completion,
- refreshing quota,
- connected after quota verification,
- safe failure.

After Claude's browser flow completes, macOS may display a Keychain access prompt. That prompt belongs to the same explicit connection action. Cancelling or denying it leaves prior quota intact and shows a safe permission/verification failure.

Failure copy is actionable but generic. It may state that the CLI is not installed, the login was cancelled, the provider rejected the login, or the operation timed out. It must not contain child-process output, login URLs, device codes, account identifiers, filesystem paths, or credentials.

### 2.2 Provider popovers

When Claude or Codex quota is `requiresAuthentication`, the provider popover exposes the corresponding browser-login action instead of only telling the user to switch to another app.

Cursor continues to direct the user to its explicit Settings connection flow. Rate limits, network failures, schema changes, and other non-authentication errors must not be presented as login failures or trigger a login CTA.

### 2.3 Completion semantics

A zero exit status from the provider CLI means only that the provider-managed login flow completed. Needlbar then performs one coalesced, provider-specific quota refresh. Claude uses the explicitly user-initiated Keychain-capable path; Codex uses its existing provider-native auth/app-server path. Fresh provider quota is the product-level confirmation that the connection is usable; otherwise the login state becomes a safe verification failure and the existing quota state remains authoritative.

The login action does not force a usage refresh. Claude and Codex usage is local-history based, and the existing manual refresh also forces Cursor source synchronization. Authentication completion must not create that unrelated work.

## 3. Architecture and Ownership

### 3.1 AppKit application layer

The `NeedlbarApp` target owns the login handoff because it is an explicit user-interface action and a child-process lifecycle concern.

A single application-lifetime `ProviderLoginCoordinator` will:

- resolve a supported provider CLI without invoking a shell,
- launch only a fixed provider command and fixed arguments through direct macOS `posix_spawn`,
- maintain at most one in-flight login per provider,
- allow Claude and Codex logins to proceed independently,
- publish transient provider login state to Settings and popovers,
- discard child stdout/stderr,
- enforce a bounded completion timeout,
- own the single session actor/lifecycle that polls `waitpid(WNOHANG)` and reaps active children during app termination,
- request a quota-only refresh after a successful child exit.

`AppDelegate` owns the coordinator and passes its actions/state into `MenuBarController`, `SettingsWindowController`, Settings, and provider popovers. UI views do not construct commands or touch credentials.

### 3.2 NeedlbarCore

`NeedlbarCore` keeps normalized provider data and refresh behavior. `QuotaRepository` gains a typed `QuotaRefreshIntent` with `.backgroundAll` and `.userInitiated(provider:)`. `RefreshCoordinator` gains `refreshQuota(afterUserAuthenticationFor:) async -> Bool`, a public coalesced quota-only entry point. It returns `true` only when the requested provider has fresh quota after the user-initiated refresh.

This entry point preserves the existing invariants:

- at most one quota refresh is in flight,
- a request arriving during a refresh queues at most one follow-up refresh,
- stale last-known-good quota remains visible on failure,
- usage state is not mutated,
- stop/restart generations prevent late work from updating a stopped coordinator.
- provider-specific success does not update the timestamp used to decide whether the all-provider background quota snapshot is fresh.
- every same-provider caller awaiting a coalesced login verification receives that provider's result exactly once; stop/restart resumes outstanding callers with `false`.

Provider login progress is not added to `DataStatus`, `ProviderSnapshot`, UserDefaults, diagnostics, or the Rust bridge envelope. It is ephemeral application state, not provider data freshness.

### 3.3 Rust crates and C bridge

No Rust or C ABI function launches login. Two narrowly named provider-specific quota functions are added so background and user-initiated Keychain behavior cannot be confused and Codex verification cannot fan out to unrelated providers:

```c
const char *needlbar_claude_user_initiated_quota_snapshot_json(void);
const char *needlbar_codex_quota_snapshot_json(void);
```

- `needlbar-quota` introduces `ClaudeCredentialAccess::BackgroundNoUI` and `ClaudeCredentialAccess::UserInitiatedAllowUI`.
- The existing all-provider quota call always uses `BackgroundNoUI` and must never display Keychain UI.
- The new Claude-only call always uses `UserInitiatedAllowUI`, returns the normal versioned envelope containing only Claude data/errors, and is called only after the explicit Claude login child exits successfully.
- The new Codex-only call is always non-interactive, returns only Codex data/errors, and prevents Codex verification from calling Claude or Cursor adapters.
- The macOS resolver queries only the exact `Claude Code-credentials` generic-password item through Security.framework. It does not run `/usr/bin/security`, enumerate Keychain contents, infer accounts, or search browser data.
- The raw Keychain payload bytes and every Needlbar-owned token-bearing string remain in non-logging zeroizing wrappers inside `needlbar-quota`. The Keychain parser ignores `refreshToken` without materializing it, moves the access token once into the secret wrapper, and drops the HTTP request promptly after the bounded Anthropic quota request. Third-party request internals are not claimed to provide formal zeroization.
- `needlbar-bridge` preserves its panic boundary, envelope contract, redaction, and Rust-owned string lifetime for the new export.
- `needlbar-source-sync` continues to own only Cursor usage hydration.

The Rust layer never launches interactive login, owns a provider callback, or stores a new Claude/Codex credential. The new export grants only user-initiated credential-read interaction for Claude quota verification.

### 3.4 Claude Keychain compatibility gate

Anthropic publicly documents Keychain storage but does not publish the Keychain item attributes or payload schema as a stable third-party API. Needlbar therefore supports only the exact `Claude Code-credentials` contract verified against the supported Claude Code version. The implementation must fail closed on missing, multiple, inaccessible, or malformed matches and must not broaden the query.

Automated tests use an injected resolver and never access a real user Keychain. Before release, a user-authorized local acceptance check must confirm the service/payload contract against the installed supported Claude Code version without recording the credential value. If the contract is incompatible, Claude post-login quota remains a documented blocker rather than falling back to Keychain crawling.

## 4. Command Contract

Provider commands are data defined by the app, never assembled from user input.

| Provider | Executable | Arguments | Product label |
| --- | --- | --- | --- |
| Claude | `claude` | `auth login --claudeai` | Sign in with Claude |
| Codex | `codex` | `login` | Sign in with ChatGPT |

The executable locator checks, in order:

1. executable names available through the app's inherited `PATH`,
2. `~/.local/bin`, `~/.volta/bin`, `~/.bun/bin`, and common package-manager bins,
3. `/opt/homebrew/bin` and `/usr/local/bin`,
4. version-manager bin directories under `~/.nvm/versions/node/*/bin` and `~/.asdf/shims`.

The chosen path is standardized, must pass the executable check, and may remain a trusted user-installed wrapper or symlink required by a version manager. `PATH` lookup is an explicit trust decision over the user's own executable environment; arguments remain fixed by Needlbar. The resolved executable URL is converted to an exact filesystem path; it is passed as both `argv[0]` and the executable path to `posix_spawn` (never `posix_spawnp`). The executable path, fixed arguments, and allowlisted environment entries are validated to contain no NUL bytes before building `argv`/`envp`. No shell, AppleScript, or string interpolation into a command line is used.

The child receives a minimal allowlisted `envp`: `HOME`, `USER`, `LOGNAME`, `TMPDIR`, locale variables, proxy/certificate variables, and the selected provider's `CLAUDE_CONFIG_DIR` or `CODEX_HOME` when present. Its `PATH` is the inherited path with the selected executable's parent directory prepended so version-managed Node wrappers can resolve their runtime. `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, `OPENAI_API_KEY`, and other credential environment variables are not forwarded. Needlbar does not synthesize or inject tokens. `posix_spawn_file_actions` connects stdin to `/dev/null` opened read-only and stdout/stderr to `/dev/null` opened write-only; `POSIX_SPAWN_CLOEXEC_DEFAULT` is set. Login URLs, device codes, and account information therefore cannot enter Needlbar logs or state.

The operation timeout is five minutes. A single session actor is the sole owner of each child PID and its `waitpid` calls; no other task reaps or signals that child. It polls nonblocking `waitpid(pid, &status, WNOHANG)`, retrying `EINTR`. Until the child is reaped, its PID cannot be reused by the process table. Timeout, app termination, or explicit cancellation coalesces into `SIGTERM`, a short bounded grace period, `SIGKILL` if the exact direct child is still running, and a final reap of that same PID. `ECHILD` is an invariant violation and stops further signaling; `ESRCH` switches to reap confirmation; other signal failures produce a bounded safe failure and never an infinite wait. A persistent signal or wait failure transfers the exact PID to actor-owned background reaping and retains that provider's admission; it does not permit a shell, process-group signal, browser signal, descendant scan, or a new same-provider login. Needlbar never signals the browser process opened by the provider.

The supported Claude Code and Codex CLI versions must pass a separate, user-authorized manual compatibility gate proving these exact commands can start their browser flow from a non-TTY direct `posix_spawn` child with stdin connected to `/dev/null`. That gate is still pending and must not be claimed as run by implementation work. If either CLI requires terminal input or depends on parsing login output, the feature is blocked; Needlbar does not fall back to Terminal automation, stdout parsing, or a shell.

## 5. State and Error Model

The application-only state is provider scoped:

```swift
enum ProviderLoginState: Equatable, Sendable {
    case idle
    case launching
    case awaitingBrowser
    case refreshingQuota
    case connected
    case failed(ProviderLoginFailure)
}

enum ProviderLoginFailure: Error, Equatable, Sendable {
    case unsupportedProvider
    case cliNotInstalled
    case launchFailed
    case cancelled
    case timedOut
    case providerRejected
    case verificationFailed
}
```

Only Claude and Codex are valid inputs to the coordinator. Cursor uses its existing controller. An unsupported provider request fails closed without launching any process.

The state is replaced when a new provider request starts and returns to `idle` when the application restarts. Closing and recreating Settings observes the same application-lifetime coordinator state. The state is never written to preferences.

## 6. Security and Privacy

The existing local-first policy remains authoritative.

- Login begins only from an explicit user click.
- Needlbar never opens a provider login on background refresh, app launch, file-watcher activity, or popover presentation.
- The provider CLI owns browser navigation, callback handling, credential refresh, and credential storage.
- Needlbar does not parse or retain child stdout/stderr.
- No shell evaluates provider commands.
- Claude Keychain UI is allowed only by the dedicated user-initiated quota export after a successful explicit Claude login action.
- Background quota refresh uses interaction-forbidden Keychain access and never displays a prompt.
- The Keychain query uses the exact provider-owned service contract and never enumerates items or invokes the `security` CLI.
- Raw Claude credentials remain inside a redacting/zeroizing Rust secret boundary and never cross the C ABI.
- No account email, login URL, device code, access token, refresh token, cookie, or raw CLI path is added to diagnostics.
- Test fixtures and fake executables contain no real provider credentials and never contact provider services.
- Cursor browser profiles and cookies remain unread.

## 7. Failure and Concurrency Rules

- A missing CLI affects only that provider and produces `cliNotInstalled` UI state.
- A nonzero child exit produces `providerRejected` without exposing output.
- A five-minute expiry produces `timedOut` and terminates the child.
- A successful CLI exit followed by non-fresh quota produces `verificationFailed`; the provider quota status retains its existing detailed error/stale semantics.
- Claude Keychain item absence maps to `requiresAuthentication`; explicit user cancellation/denial maps to `permissionDenied`; malformed payload maps to `schemaChanged`; none erase last-known-good quota.
- Closing Settings does not cancel an application-owned login; reopening Settings observes the same transient state.
- Repeated clicks for the same provider while a login is active are ignored.
- Claude and Codex may each have one simultaneous login.
- App termination attempts bounded direct-child termination and reap for every active login. The runner and coordinator report either `allChildrenReaped` or `backgroundReaping` for that attempt. With `allChildrenReaped`, termination next awaits refresh shutdown and sends exactly one successful AppKit reply. With `backgroundReaping`, termination sends exactly one negative AppKit reply, keeps the application and coordinator alive, preserves the affected provider admission, and does not proceed to refresh shutdown. A later termination request is a new bounded attempt and may succeed after background reaping has completed. Repeated requests while one decision is in flight coalesce and must not duplicate cleanup or either reply.
- A late child completion from an older generation cannot overwrite newer state or request another refresh.
- Quota refresh failure after a successful CLI exit uses the existing quota/last-known-good state. The login UI reports that sign-in completed but verification failed, without replacing the quota error with invented success.

## 8. Testing Contract

Automated tests use injected executable locators, process launchers, quota-refresh intents, and Claude credential resolvers.

Required coverage:

- exact fixed commands for Claude and Codex,
- unsupported provider rejection,
- CLI-not-installed handling,
- same-provider duplicate suppression,
- independent Claude/Codex concurrency,
- exactly-once completion for every coalesced provider waiter and `false` completion for waiters stopped by a generation change,
- main-actor responsiveness while the child is active,
- zero exit followed by exactly one quota-only refresh,
- nonzero, timeout, cancellation, and launch failure mapping,
- stdout/stderr exclusion and safe UI copy,
- generation protection against late completion,
- app termination: successful reply only after all login children are reaped and refresh shutdown completes; persistent signal/wait failure gives one negative reply, retains background reaping/admission, and permits a later successful retry,
- provider-popover CTA policy,
- Cursor session workflow regression coverage,
- refresh coalescing without usage refresh,
- background Claude quota never allows Keychain UI,
- user-initiated Claude verification is the only path that allows Keychain UI,
- exact Keychain service query with no enumeration or heuristic fallback,
- missing, denied, cancelled, malformed, expired, and successful Keychain results,
- credential canaries absent from errors, envelopes, diagnostics, debug formatting, and Swift,
- new C ABI pointer/free/panic behavior,
- Codex-only verification that never invokes Claude or Cursor,
- provider-specific success that cannot mark the all-provider background refresh timestamp fresh,
- harmless real-child normal exit, TERM-only exit, TERM-to-KILL escalation, cancellation, timeout, and coalesced cancellation-plus-stop cleanup,
- syscall-seam coverage for `WNOHANG`, normal exit, `EINTR`, `ECHILD`, `ESRCH`, and signal failure,
- pre- and post-spawn cancellation,
- exact executable path/argv/envp, NUL validation, file descriptors, and `POSIX_SPAWN_CLOEXEC_DEFAULT`,
- descendant isolation proving cleanup never targets a provider-opened descendant,
- full `make test` success.

No automated test opens a real browser or runs a real provider login. Synthetic credential canaries are permitted; real credentials never enter tests. Manual acceptance first verifies the exact non-TTY CLI launch contract, then uses test accounts or the user's existing provider accounts and verifies that no credentials appear in Needlbar diagnostics or preferences.

## 9. Documentation Amendments

This document overrides only the authentication UX portions of the base v0.1 design:

- Claude fallback may now be initiated from Needlbar by explicitly launching provider-native Claude Code login.
- Explicit Claude completion may request access to the exact provider-owned Keychain item for quota verification; background refresh remains non-interactive.
- Codex fallback may now be initiated from Needlbar by explicitly launching provider-native Codex login.
- The prohibition on a duplicate Needlbar-owned OAuth flow remains unchanged.
- Cursor remains on its approved explicit session-token Connect flow.

The implementation must update:

- `README.md`,
- `docs/architecture.md`,
- `docs/privacy.md`,
- `docs/providers/claude.md`,
- `docs/providers/codex.md`,
- `docs/providers/cursor.md`,
- `docs/STATUS.md`.

## 10. Acceptance Criteria

1. A signed-out Claude user can click `Sign in with Claude`, complete the provider browser flow, approve Keychain access when macOS requires it, and receive a verified quota refresh without leaving Needlbar to start the CLI manually.
2. A signed-out Codex user can click `Sign in with ChatGPT`, complete the provider browser flow, and receive a quota-only refresh without leaving Needlbar to start the CLI manually.
3. Missing or broken provider CLIs produce safe, provider-scoped failures and do not affect other providers.
4. Cursor retains its explicit validated session-token workflow with no browser-cookie crawling.
5. Needlbar does not own OAuth callbacks or persist Claude/Codex credentials, login output, or login progress; Claude's raw Keychain credential remains Rust-internal and ephemeral.
6. Login work never blocks the main actor and is cleaned up during app termination.
7. Usage and quota independence and last-known-good behavior remain intact.
8. Background refresh cannot display Keychain UI, while only the explicit Claude post-authentication path can allow it.
9. The supported Claude Code Keychain contract passes a user-authorized local compatibility check or remains an explicit release blocker.
10. The supported Claude Code and Codex CLI versions pass the exact non-TTY direct `posix_spawn` browser-launch compatibility gate without shell or output parsing; this separate user-authorized gate remains pending until performed.
11. The full project test gate passes.

## 11. Official Provider References

- Anthropic documents browser login and macOS Keychain credential storage: <https://code.claude.com/docs/en/iam>
- OpenAI documents `codex login` as the default browser sign-in flow and `codex login status` for status checks: <https://developers.openai.com/codex/auth>
- Cursor documents `cursor-agent login` and `cursor-agent status`, but not a personal usage/quota handoff for third-party apps: <https://docs.cursor.com/en/cli/reference/authentication>
