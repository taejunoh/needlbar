# Claude credential renewal

**Date:** 2026-10-22

**Status:** Approved by the user on 2026-10-22 for option A (narrowed) and
increment 1 only, with the decisions recorded in §8. It authorizes no
renewal, installation, release, or authentication change, and amends only the
two specifications named in §4.

**Scope:** Decide how Needlbar responds when its direct Claude quota source
fails because the credential Claude Code saved on this Mac has passed its
expiry time. Compare explanation, renewal, CLI, and notification options
against the approved product boundaries, and recommend one bounded first
increment.

This proposal was prepared from repository code, specifications, STATUS, and
public documentation only. No credential, Keychain item, cookie, token, or
authentication file was read or inspected, no `claude` command was run, and no
model request was made.

## Summary

Within the approved boundaries Needlbar cannot renew the Claude credential,
and it should not try. The recommendation is a narrowed option A: carry the
existing allowlisted failure origin into presentation and, when the origin is a
local credential expiry, say so plainly. The copy explains that the access
Claude Code saved has expired and that Needlbar resumes after Claude Code
renews it. There is no sign-in prompt, Terminal launch, CLI invocation, or
notification. Option B (Needlbar redeems the refresh token) is rejected.
Option C (a non-model CLI renewal) is deferred because no such command is
documented. Option D (an expired-credential notification) is a possible opt-in
second phase that needs its own approval.

## 1. Problem and evidence

### Observed behaviour (aggregate)

From the maintainer's report and the app's local diagnostics on 2026-10-21
(STATUS, "2026-10-21 Test reliability follow-ups"):

- For more than a day, every direct Claude quota attempt on the five-minute
  cadence failed with origin `keychainCredentialExpired`. The attempts ran, so
  this was not a scheduler failure.
- The 5-hour and 7-day windows fell back to Claude Code status-line values.
  Fable, which only the direct source supplies, could only be last-known or
  unavailable.
- The user then ran one non-interactive Claude Code prompt in a terminal.
  Needlbar's next direct attempt, triggered by opening the popover, succeeded.
- Needlbar did not observe a renewal itself. The success implies that Claude
  Code replaced the expired saved credential while it served that prompt. The
  prompt was a model request that the user started and that counted against
  the user's own subscription.

The same origin appears in the 2026-09-25 and 2026-10-07 specifications, so
this failure keeps coming back.

### What the origin means

The closed origin enumeration is defined in Rust
(`crates/needlbar-quota/src/domain.rs:76-87`) and decoded in Swift
(`Sources/NeedlbarCore/Diagnostics/DiagnosticsSnapshot.swift:100-108`):
`credentialMissing`, `keychainCredentialExpired`, `fileCredentialExpired`,
`credentialAccessDenied`, `usageEndpointUnauthorized`,
`usageEndpointForbidden`, `otherFailure`.

`keychainCredentialExpired` is assigned only when all of these hold. The
Keychain lookup succeeded, the payload parsed, and its `expiresAt` is at or
before the local clock
(`crates/needlbar-quota/src/providers/claude_credentials.rs:159-161`,
relabelled at `:255-258`, mapped at
`crates/needlbar-quota/src/providers/claude.rs:231-236`). The resolver returns
before any HTTP request is built (`claude.rs:88-91`). Therefore:

- These attempts send nothing to the usage endpoint and put no load on the
  provider.
- The origin is not a provider rejection. A rejection is reported as
  `usageEndpointUnauthorized` or `usageEndpointForbidden` from HTTP 401/403
  (`claude.rs:273-286`).
- The origin says nothing about whether Claude Code's login can still be
  renewed. In the observed case it could: Claude Code renewed it without a new
  sign-in.

A wrong system clock can also produce a false local expiry. Claude Code's
troubleshooting guide notes that token validation depends on accurate time.

### How the origin reaches the user today

- Rust records the origin and attempt time in the bridge diagnostics record
  (`crates/needlbar-bridge/src/lib.rs:407-420`,
  `crates/needlbar-bridge/src/quota.rs:148-182`,
  `crates/needlbar-bridge/src/diagnostics.rs:412-447`). A success clears the
  origin (`diagnostics.rs:421-431`).
- After each completed Claude operation, Swift reads that record and emits one
  allowlisted OSLog event
  (`Sources/Needlbar/Diagnostics/ClaudeQuotaFailureDiagnosticsReporter.swift:29-60`,
  wired at `Sources/Needlbar/App/AppDelegate.swift:189-200`, invoked at
  `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift:692`).
- Presentation never sees the origin. The coordinator maps only the public
  error code to `ClaudeQuotaFailureReason` (`RefreshCoordinator.swift:886-894`).
  `authenticationExpired`, whether it comes from local expiry or from HTTP
  401/403, becomes "Quota access unavailable"
  (`Sources/NeedlbarCore/Models/ClaudeQuotaFailureReason.swift:1-17`).
- That reason is hidden whenever either source has a recent value
  (`Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift:106`; Settings
  renders the same field at `Sources/Needlbar/Settings/SettingsView.swift:288`).
  Fable's own status line is suppressed whenever a reason exists
  (`Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift:324-332`).

The result is that, in the observed state, the UI showed status-line numbers
and gave no reason why Fable had stopped updating. Diagnosing it needed the
unified log.

### Interpretation (not established)

Two explanations fit the evidence. Needlbar cannot tell them apart without
inspecting credential stores, which this design does not allow.

- **H1, idle owner.** During the failure period, no Claude Code process that
  uses the default store made an authenticated request. Claude Code's
  documentation describes automatic renewal that its own sessions coordinate,
  not renewal while no session is running, so the saved access token simply
  aged out.
- **H2, different credential source.** Claude Code sessions were active, but
  they authenticated from a source other than the item Needlbar reads. Status
  line `rate_limits` appear only after a session receives an API response, so
  a fresh fallback means some session was active. Candidates include a
  different `CLAUDE_CONFIG_DIR`, which Claude Code's documentation says keys a
  different Keychain entry, an environment OAuth token, or a host application
  that supplies its own credential. Such sessions would not renew the default
  item.

The maintainer can tell H1 from H2 without credential inspection, using the
existing allowlisted `QuotaRefreshDiagnostic` fields. If
`fiveHourSource=statusLine` with a recent `fiveHourReceipt` coincided with
expired-origin direct failures, sessions were active while the default item
stayed expired, which points to H2 (open question Q4). Under H2, advice to
"open Claude Code" would be wrong. The copy proposed below is accurate under
both explanations.

## 2. How the app obtains the Claude credential today

1. The background quota export
   (`crates/needlbar-bridge/src/lib.rs:329-333`) calls
   `ClaudeQuotaProvider::fetch`. That call always uses `BackgroundNoUI`
   (`crates/needlbar-quota/src/providers/claude.rs:145-151`).
2. `production_resolver` installs `MacClaudeCredentialResolver` on macOS, with
   the legacy file resolver as its fallback
   (`crates/needlbar-quota/src/providers/claude_credentials.rs:109-127`).
3. `resolve_keychain` (`claude_credentials.rs:217-259`) queries the exact
   generic-password service `Claude Code-credentials` (`:228`) with
   `kSecUseAuthenticationUIFail` for background access (`:229-234`, query
   built at `:276-337`). The query has two phases. The first gets a persistent
   reference and requires exactly one matching item. The second reads that
   item's data (`:235-254`). Security status codes map to a closed enum
   (`:394-413`).
4. Only a Keychain `NotFound` falls back to
   `CLAUDE_CONFIG_DIR/.credentials.json`, or to `~/.claude/.credentials.json`
   when that variable is unset (`claude_credentials.rs:204-215`, `:61-99`).
5. `parse_credential_payload` (`claude_credentials.rs:143-164`) deserializes
   only `claudeAiOauth.accessToken` and `expiresAt` (`:129-141`). It rejects
   tokens that are not header-safe and tokens that have expired. The access
   token is held in a zeroizing wrapper that has no `Debug`, `Clone`, or
   serialization (`:16-36`).
6. A valid token is used for one bounded HTTPS GET to the usage endpoint
   (`claude.rs:17-18`, `:92-113`). The token never reaches Swift, the C ABI,
   diagnostics, logs, or errors.
7. Only the explicit post-sign-in verification export uses
   `UserInitiatedAllowUI`, which may show a macOS Keychain prompt
   (`crates/needlbar-bridge/src/lib.rs:354-364`).

**Store read:** Claude Code's login-Keychain item for the default
configuration, or else the provider's credentials file. Access is read-only:
the quota crate calls only `SecItemCopyMatching`. It never calls
`SecItemAdd`, `SecItemUpdate`, or `SecItemDelete`, and it never writes a
credential file.

**Does Needlbar ever refresh an OAuth token itself? No.**

- The refresh token is never deserialized. The payload projection omits it,
  and `claude_credentials.rs:438-448` asserts that a refresh-token canary stays
  out of the typed projection.
- There is no token-endpoint client.
- There is no write path back to Claude Code's store.

There are three reasons:

1. Approved designs rejected Needlbar-owned renewal three times: the 2026-09-15
   passive-recovery design (alternative 3), the 2026-09-16 failure-origin
   design (rejected alternatives), and the 2026-09-25 status-line bridge design
   (alternative 2 and its closing paragraph). `docs/providers/claude.md`
   states that Claude Code owns refresh and credential storage.
2. The provider's credential-use policy forbids it (§3, option B).
3. Claude Code coordinates renewal among its own processes, and an outside
   renewer cannot join that coordination (§3, option B).

**Known limitation, out of scope.** The Keychain service name is fixed.
Claude Code's documentation says a non-default `CLAUDE_CONFIG_DIR` keys a
different Keychain entry, and a GUI app usually does not inherit shell
variables. The 2026-09-25 design already treats non-default configuration
directories as not yet connected.

## 3. Options and trade-offs

| Option | Product boundaries | Privacy | Security | Reliability | Testability | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| A. Origin-aware explanation | Copy only: narrow amendment of 2026-09-15. Terminal action: conflicts with 2026-09-15 | No new data; enum already decoded | Unchanged | Recovery unchanged; state becomes legible | Fully deterministic | **Recommended (narrowed)** |
| B. Needlbar redeems refresh token | Violates provider policy and three approved designs | Holds the long-lived credential | Expands blast radius; rotation race can revoke the login | Can break Claude Code's own login | Needs live credentials | **Rejected** |
| C. Non-model CLI renewal | No documented command; background use manufactures CLI sessions | Claude Code writes its own store | Delegates rotation to the owner | Unknown; depends on undocumented behaviour | Renewal not verifiable synthetically | **Deferred** |
| D. Expired-credential notification | Conflicts with approved notification and passive-recovery specs | Generic copy; local ledger | Unchanged | Awareness only; fatigue risk under H2 | Deterministic | **Possible opt-in phase 2** |

### A. Status quo plus clearer UX

The suggested form shows "Claude credential expired — open Claude Code to
refresh" with an action that opens Terminal or a documentation link.

- **Boundaries.**
  - An explanation alone fits the passive-recovery direction, but it amends
    that design's reason table.
  - A Terminal action conflicts with the approved 2026-09-15 rule that Claude
    surfaces do not tell the user to open a terminal, approve Keychain access,
    or keep pressing Retry. Needlbar also cannot know which terminal the user
    prefers.
  - "Open Claude Code to refresh" promises renewal on launch. Claude Code's
    documentation does not say that starting it, without a request, renews the
    saved access, and the only observed renewal followed a model request.
  - A user who follows that copy with a throwaway prompt spends subscription
    usage. Under H2 the advice does not help at all.
- **Privacy.** No new data. The origin is an allowlisted enum that Swift
  already decodes. No paths, raw errors, or identifiers are added.
- **Security.** No change to credential handling.
- **Reliability.** Recovery is not faster: it still depends on Claude Code.
  The state becomes self-explanatory and last-known semantics stay intact.
- **Testability.** Fully deterministic, using fake diagnostics and fake
  repositories.

The narrowed recommendation keeps the copy and drops the Terminal action. A
fixed documentation link is left to the user (Q3).

### B. Needlbar renews with the refresh token

- **Documentation.** Searches of Anthropic's public documentation sites found
  no documented token endpoint or third-party client registration for
  claude.ai logins. Implementing this would mean copying Claude Code's private
  client identity and endpoint, which have no stability contract.
- **Policy.** Anthropic's credential-use policy reserves subscription OAuth
  for ordinary use of Claude Code and native Anthropic applications. It does
  not permit third-party developers to offer Claude.ai login or to route
  requests through Free, Pro, or Max credentials, and it states that
  developers "may not collect, store, or intermediate Claude.ai credentials
  or session tokens." Renewal would require Needlbar to read, hold, and spend
  the refresh token as Claude Code's client. That is the excluded behaviour.
- **Security.** The refresh token is the long-lived half of the login. Today
  Needlbar never deserializes it. Option B would hold it in memory, send it,
  and receive a new token pair, so any leak in a log, a crash report, or a
  compromised Needlbar process becomes durable account access instead of a
  short-lived token.
- **Writing back to Claude Code's store.** A write is a cross-application
  Keychain write to an item that Claude Code created. Needlbar's signing
  identity may be denied, or may trigger a prompt, and changing the item's ACL
  is excluded by the 2026-09-15 design.
  - Not writing back is worse if the grant rotates: Claude Code's stored
    refresh token would then be stale. Claude Code's error reference says that
    when the OAuth service rejects the stored refresh token, Claude Code clears
    the saved credentials and the user must sign in again. Option B could
    cause exactly the re-login that the passive design was written to avoid.
- **Rotation race with Claude Code.** Claude Code's troubleshooting guide says
  parallel sessions share one saved login and coordinate renewal so that only
  one process refreshes at a time. Its error reference describes a shared
  refresh lock. The same guide records that, before v2.1.211, two sessions
  renewing with the same token after a wake revoked the saved login.
  - Needlbar cannot take part in that undocumented lock, so it would recreate
    this failure by design.
  - The documentation does not state the rotation policy explicitly, but the
    revocation incident shows a grant cannot safely be redeemed twice.
- **Testability.** The provider's behaviour cannot be validated without live
  credentials, and synthetic fixtures would test only Needlbar's assumptions.

**Verdict: rejected.** It remains excluded, as it is in the 2026-09-15 and
2026-09-25 designs.

### C. Non-model Claude Code CLI renewal

- **Documented commands.**
  - `claude auth status` reports authentication status as JSON with an exit
    code.
  - `claude doctor` prints read-only diagnostics without starting a session.
  - `claude auth login` and `claude setup-token` start browser authorization.
  - None of these is documented to renew a saved login without a model
    request. The 2026-09-15 design already found that `status` is not a
    demonstrated renewal mechanism.
- **Undocumented side effects.** Relying on one, for example `status`
  happening to renew, cannot be verified within this project's rules, which
  allow no `claude` runs. Any release could change it, and it would still be
  a Claude Code credential write that Needlbar triggered.
- **Boundaries.** A background invocation conflicts with the 2026-10-07
  design. That design adds no sign-in prompt, model request, or Claude
  authentication or configuration write to any recovery path, and a renewing
  invocation is exactly such a write. The 2026-10-07 plan also forbids
  manufacturing paid prompts, reauthentication, or CLI sessions to
  demonstrate reliability, so such an invocation could not even serve as
  evidence.
  - An explicit-click variant would resemble the approved login launcher:
    fixed command and arguments, direct `posix_spawn`, no shell, no output
    parsing.
  - It would at least leave rotation to Claude Code, which takes its own lock.
- **Cost and side effects.** A truly non-model command spends no model
  tokens, but it still:
  - starts a process;
  - may send network traffic for settings, feature flags, or update checks;
  - writes Claude Code's Keychain item and local state;
  - may run user hooks or plugins if it starts a session.
  Under H2 it would renew the default item but not the store the user's
  sessions use.
- **Testability.** Launching a process can be tested with fakes. Actual
  renewal cannot be verified without the real CLI.

**Verdict: deferred.** Revisit only if Anthropic documents a non-model
renewal command, and then only as an explicit user action, never in the
background.

### D. Notification after N minutes of expired-origin failures

- **Boundaries.** This conflicts with two approved designs:
  - The 2026-08-31 notifications design allows only threshold alerts from
    fresh successful samples. It never evaluates error or authentication
    states and has no notification actions.
  - The 2026-09-15 passive-recovery design adds no new notification.
  - Both would need explicit amendments.
- **Privacy.** Generic copy and a local, credential-free ledger.
- **Security.** Nothing new.
- **Reliability.** It improves awareness, not recovery. Under H2 it could fire
  once per episode, possibly daily, so it must be opt-in.
- **Testability.** Deterministic with an injected clock, a fake notification
  client, and the existing at-most-once ledger pattern.

If approved later, the sketch is:

- A separate opt-in setting, off by default and independent of quota-threshold
  alerts. It uses the existing authorization flow.
- It evaluates only completed current-generation attempts whose origin is
  `keychainCredentialExpired` or `fileCredentialExpired`.
- It becomes eligible once the first failure in the current consecutive
  local-expiry run is at least N minutes old (proposed N = 60).
- It sends at most one notification per episode. An episode is identified by
  the actual last direct success timestamp, durably recorded so that a restart
  cannot resend, and a direct success ends the episode.
- No retries, actions, sounds, or badges. It triggers no additional provider
  request or Keychain read.

**Verdict: optional phase 2,** after A and only with separate approval.

### Considered and not pursued here

- **Helper-process Keychain isolation or deadline.** This bounds a blocked
  Security call; it does not renew anything. It needs its own design, per
  the 2026-10-07 design.
- **Retiring the direct source.** This is the unresolved provider-policy and
  compatibility concern already recorded by the 2026-09-25 design. It needs a
  separate review (Q7). Retiring it would make Fable unavailable.

## 4. Recommendation and minimal first increment

Adopt option A in its narrowed form. Increment 1 is a presentation change in
`NeedlbarCore` and the app target. It makes no Rust, C ABI, or JSON-schema
change.

1. **Typed reason.** Add one `ClaudeQuotaFailureReason` case, named here
   `claudeCodeAccessExpired` (final name in the plan). Use it only when the
   completed attempt's Claude error code is `authenticationExpired` and its
   associated origin is `keychainCredentialExpired` or
   `fileCredentialExpired`. Every other combination keeps today's code-based
   mapping. Origins `usageEndpointUnauthorized` and `usageEndpointForbidden`
   keep "Quota access unavailable". The reason is never inferred from elapsed
   time, UI state, or status-line activity.
2. **Origin source and association.** Use the diagnostics snapshot that is
   already read after each Claude completion, read once and shared by the
   OSLog reporter and the coordinator. Accept the origin only when:
   - the Claude record's `lastAttemptAt` is not earlier than the current
     attempt's start, truncated to whole seconds;
   - the attempt belongs to the current run generation;
   - the attempt's Claude result is a failure.
   Otherwise keep the code-based reason. Add no extra quota call, Keychain
   read, or bridge export.
3. **Copy.** Proposed wording; the final wording is Q2.
   - Short reason: "Waiting for Claude Code to renew access".
   - Detail line, in the popover and Settings only: "Needlbar reads the access
     Claude Code saves on this Mac. It has expired. Needlbar updates
     automatically after Claude Code renews it."
   - No "Sign in", no "Log in again", and no instruction to run a command or
     send a prompt.
4. **Placement.**
   - When no source has a recent value, use the existing reason slot, as
     today.
   - When the main windows are recent through the status line, show the reason
     once on that surface, on the direct-only Fable detail line, which the
     reason currently suppresses.
   - The dashboard compact row keeps its existing rule.
   - The menu bar, widget, JSON export, and notifications are unchanged.
5. **Actions.** None new. The existing explicit "View Claude usage" link stays
   as it is.
6. **Recovery.** Unchanged. A later direct success clears the reason through
   the existing store path (`ProviderSnapshotStore.swift:71-77`). Cadence
   stays at 300 s and the popover threshold at 60 s
   (`RefreshCoordinator.swift:28`, `:218-228`, `:346-377`).
7. **Diagnostics.** The existing allowlisted OSLog events are unchanged.

**Specifications this would amend, once approved:**

- The reason table and placement in the 2026-09-15 passive-recovery design.
- The "presentation mapping stay unchanged" sentence in the 2026-09-16
  failure-origin design, for local-expiry origins only.

Nothing else is amended.

## 5. Acceptance criteria and tests

All tests use injected clocks, fake `QuotaRepository` and diagnostics
readers, synthetic origins, and secret-marker canaries. No test uses live
credentials, Keychain access, the network, or the `claude` CLI.

1. **Mapping table.** For each of the seven origins, crossed with the error
   codes `authenticationExpired`, `requiresAuthentication`,
   `permissionDenied`, `networkUnavailable`, and an unknown code, the stored
   reason matches the table in §4.1. Only the two local-expiry origins
   combined with `authenticationExpired` produce the new reason. A missing or
   undecodable origin falls back to the code mapping.
2. **Association.** The origin is rejected when the diagnostics
   `lastAttemptAt` predates the attempt start, when the result is from an old
   generation, and when the Claude result succeeded. The diagnostics read
   count is exactly one per completed Claude operation. The repository call
   count is unchanged.
3. **Transitions.** A sequence of expired, expired, then success clears the
   reason with no user action. A sequence of expired then HTTP 401 replaces it
   with "Quota access unavailable". A stop and restart does not carry a stale
   origin into the new generation.
4. **Presentation.** Covers the popover, dashboard, and Settings.
   - With no recent value, the new short text appears in the existing slot.
   - With recent status-line windows and a failing direct source, the
     main-window presentation is unchanged and the reason appears exactly once,
     on the Fable line.
   - The "Last checked" label shows the actual last direct success, never an
     attempt time.
   - No surface shows "Sign in", a Terminal action, or any new control.
   - Codex, Cursor, usage, and API billing presentation is unchanged.
5. **No side effects.**
   - Injected spies record zero process launches, zero automatic URL opens,
     zero login-coordinator calls, and no extra repository or bridge quota
     invocations.
   - The JSON export and widget projection are byte-identical to the pre-change
     fixtures.
6. **Privacy.** Canary payloads in fake diagnostics never appear in the store,
   presentation strings, logs, or exports. The reason is built only from the
   enum.
7. **Accessibility and localization.** The new strings are localizable keys,
   and the accessibility label of the reason element includes the full short
   text.
8. **Gates.** Run focused tests, then `make test` with
   `env PATH="$HOME/.cargo/bin:$PATH" MACOSX_DEPLOYMENT_TARGET=14.0`, then
   `git diff --check`. Passing source tests establishes mapping and
   presentation only. It does not establish native behaviour, renewal, or
   unattended recovery.

## 6. Non-goals

- Renewing, refreshing, or extending any Claude credential.
- Reading, parsing, holding, or sending a refresh token.
- Writing to, repairing, or changing the ACL of a Keychain item or credential
  file.
- Launching Claude Code, a terminal, or any CLI automatically or in the
  background, and any Terminal automation.
- Making a model request, or suggesting that the user send a prompt in order
  to renew access.
- A sign-in prompt, a login CTA, or reauthentication.
- Browser cookie access.
- Cancelling, bounding, or isolating a blocked synchronous Keychain call.
- Querying non-default `CLAUDE_CONFIG_DIR` Keychain entries.
- Changing the refresh cadence, recovery triggers, or status-line semantics.
- Deriving Fable from status-line data.
- New telemetry, network traffic, or provider endpoints.
- Merging usage, subscription quota/reset, and provider billing. They stay
  distinct.

## 7. Open questions for the user

1. **Q1.** Do you approve amending the 2026-09-15 passive-recovery reason
   table so that local credential expiry gets its own copy? This is required
   for option A.
2. **Q2.** Which wording do you want?
   - (a) The neutral "Waiting for Claude Code to renew access" (recommended).
   - (b) "Claude Code's saved access expired — it renews when you next use
     Claude Code".
   - (c) Your proposed "open Claude Code to refresh", which assumes H1 and
     invites a paid prompt.
3. **Q3.** Should there be any action?
   - (a) None (recommended).
   - (b) A fixed link to Claude Code's public authentication documentation.
   - (c) Open the Terminal application. This needs an explicit amendment and
     cannot respect your preferred terminal.
4. **Q4.** Which Claude Code host and credential source do you use day to day?
   For example: the terminal CLI with the default configuration, the desktop
   app, an IDE extension, another `CLAUDE_CONFIG_DIR`, or an environment
   token. Your existing `QuotaRefreshDiagnostic` events can answer this
   without credential inspection: were status-line receipts recent while
   direct attempts reported expiry? The answer decides between H1 and H2 and
   whether any "use Claude Code" hint would help.
5. **Q5.** Do you want option D as a later opt-in phase? If so, what N
   (proposed 60 minutes), and do you accept amending the 2026-08-31
   notifications design?
6. **Q6.** When the main windows are fresh from the status line, is the Fable
   line the right single place for the reason, or should it appear only in
   Settings?
7. **Q7.** Should the direct token-reading path itself be put through the
   separate provider-policy and compatibility review that the 2026-09-25
   design deferred, in light of the credential-use policy quoted in §3?
8. **Q8.** If Anthropic later documents a non-model renewal command, should
   option C be reconsidered as an explicit-click action only?

## 8. Decisions (2026-10-22)

The user approved the recommendation. Questions they did not answer
individually take the recommended default:

- **Q1:** Yes. Amend the 2026-09-15 passive-recovery reason table and the
  2026-09-16 failure-origin presentation sentence, for local-expiry origins
  only.
- **Q2:** (a) "Waiting for Claude Code to renew access", with the §4.3 detail
  line.
- **Q3:** (a) No action.
- **Q4:** Open. It does not block increment 1.
- **Q5:** Option D is deferred. No notification work is approved.
- **Q6:** The Fable detail line, as in §4.4.
- **Q7:** Open. It is a separate review, not part of increment 1.
- **Q8:** Deferred. Revisit only if Anthropic documents a non-model renewal
  command, and then only as an explicit-click action.

## References

Public documentation read on 2026-10-21:

- [Legal and compliance: authentication and credential use](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use):
  subscription OAuth is limited to Claude Code and native Anthropic
  applications, and third parties may not collect, store, or intermediate
  Claude.ai credentials or session tokens.
- [Authentication](https://code.claude.com/docs/en/authentication):
  - macOS Keychain storage, with a file fallback when the Keychain write is
    rejected;
  - `CLAUDE_CONFIG_DIR` keys a separate Keychain entry;
  - renewal of an expiring login and the `/status` login row;
  - authentication precedence, including `CLAUDE_CODE_OAUTH_TOKEN`.
- [CLI reference](https://code.claude.com/docs/en/cli-reference):
  descriptions of `claude auth status`, `claude auth login`, `claude doctor`,
  and `claude setup-token`. None is documented to renew a login without a
  model request.
- [Troubleshoot installation and login: not logged in or token expired](https://code.claude.com/docs/en/troubleshoot-install#not-logged-in-or-token-expired):
  - parallel sessions coordinate renewal so that one process refreshes;
  - before v2.1.211, a same-token double renewal after wake revoked the saved
    login;
  - token validation depends on clock accuracy.
- [Error reference](https://code.claude.com/docs/en/errors):
  - "Could not refresh your login" describes the shared refresh lock;
  - "Login expired" says Claude Code clears saved credentials when its stored
    refresh token is rejected.
- [Status line](https://code.claude.com/docs/en/statusline): `rate_limits`
  appears only for subscribers and only after the session's first API
  response, and it updates on session events or an optional timer.

Repository designs this proposal relies on, which remain authoritative unless
amended by an approved successor:

- `docs/superpowers/specs/2026-09-15-claude-passive-quota-recovery-design.md`
- `docs/superpowers/specs/2026-09-16-claude-quota-failure-origin-design.md`
- `docs/superpowers/specs/2026-09-25-claude-statusline-quota-bridge-design.md`
- `docs/superpowers/specs/2026-10-07-claude-refresh-reliability-design.md` and
  `docs/superpowers/plans/2026-10-07-claude-refresh-reliability.md`
- `docs/superpowers/specs/2026-08-31-needlbar-v0.2.1-widgets-notifications-design.md`
- `docs/superpowers/specs/2026-08-25-provider-managed-browser-login-design.md`
