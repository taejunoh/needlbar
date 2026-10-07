# Claude quota refresh reliability

**Date:** 2026-10-07

**Status:** Written specification approved by the user on 2026-10-07.

**Scope:** Make Claude quota freshness source-aware and improve recovery/liveness
after lifecycle or connectivity changes, without changing authentication
ownership or the provider refresh cadence.

## Context and evidence

On October 7, two Needlbar hosts emitted the allowlisted
`keychainCredentialExpired` quota-failure origin five minutes apart, matching
the normal refresh cadence. Scheduled attempts ran and failed; this does not
prove scheduler failure. Later, canonical Settings showed direct Claude usage
at 12% and a Claude Code status-line observation after the user initiated a terminal
prompt. These facts do not establish authentication rotation or a causal link
between the prompt and direct quota recovery. Claude Code's `loggedIn` report
does not prove Needlbar's credential is valid.

This increment improves source selection, lifecycle recovery, and safe local
liveness evidence. It does not repair Keychain access, renew credentials, or
guarantee a provider request completes. The approved 2026-09-15 passive-recovery
and 2026-09-25 status-line bridge designs remain authoritative for credential
boundaries, cache validation, and status-line semantics.

## Decision and alternatives

1. **Source-aware freshness and lifecycle recovery (selected):** keep direct
   and status-line observations independent; use one timed policy on all Claude
   quota surfaces; read the local bridge cache on launch, wake, and
   offline-to-online recovery. Direct catch-up is eligible only after five
   minutes since the actual prior attempt. Preserve the normal cadence.
2. **File watcher (deferred):** could reduce display latency but adds lifecycle
   and race complexity; the existing five-minute local read is sufficient now.
3. **Helper-process Keychain isolation (deferred):** could eventually bound a
   blocked Security call but adds process, cancellation, and credential-access
   risk; it requires a separate design and is not implied here.

## Source-aware value and freshness

For each Claude quota window, evaluate the direct observation and the
status-line observation independently against the injected current time. A
direct observation is current only when all of the following are true:

- The direct quota stream's current status is valid and fresh.
- Its actual last-success timestamp exists, is finite, is not in the future,
  and is less than 15 minutes old (`now >= timestamp` and
  `now - timestamp < 15 minutes`). Missing and future timestamps are not fresh.
- If a reset timestamp exists, it is later than now; a reset at or before now makes the
  observation last-known. Without one, the remaining value may be fresh while
  its reset label says `Reset unavailable`.

Keep the actual last-success timestamp when refresh fails; never replace it
with the attempt time. Apply the same age, future-time, and passed-reset checks
to direct Fable using its own timestamp and reset. Fable remains independently
fresh, stale, or unavailable; status-line data cannot refresh or timestamp it.

Preserve bridge semantics: only a valid active-generation record is eligible;
identical observations do not extend recency; its 15-minute recency and reset
rules remain unchanged. Receipt time is local, not proof of a provider fetch
or server observation.

Select a value for each window in this order:

1. A current direct observation.
2. A current status-line observation.
3. The most recently observed valid last-known observation from either source.

For equal observation times, prefer direct quota. A valid retained value without
a usable timestamp remains displayable as last-known but ranks behind values
with finite timestamps not later than now. Missing, non-finite, and future times
are unusable for both freshness and ranking. If both retained values lack usable
times, prefer direct quota without inventing or displaying an unusable time.
If neither source has a valid value, show unavailable without a percentage,
zero, timestamp, or reset.

Use this policy in the dashboard, provider popover, and Settings. Re-evaluate
age/reset boundaries while a surface remains open without a provider request.
For a later UI increment, retain the approved direction: show one named,
most-constrained window with remaining semantics and put other windows and
provenance in disclosure. This document does not implement that UI change.

## Bounded recovery behavior

On app start, system wake, and offline-to-online transition, read the local
status-line cache and apply it only if schema, active generation, and window
values validate. This neither launches Claude Code nor makes a provider
request. Wake and connectivity recovery may request one direct quota catch-up
only after five minutes since the actual prior background quota attempt.
Startup retains the existing initial-refresh policy; recovery events must not
duplicate it before any prior attempt exists. Preserve the normal five-minute
cadence and existing quota refresh boundary, without a separate Claude-only
request pipeline.

Coalesce wake/connectivity/popover triggers to one in-flight direct request and
at most one pending catch-up. Clear or reconcile pending work on stop; restart
begins a new generation. Recheck recovery eligibility when pending work drains:
a newer attempt can make queued recovery unnecessary. Coincident periodic and
recovery requests must share one attempt instead of running back-to-back.
Preserve physical single-flight across stop/restart; fencing a result does not
prove its synchronous call was cancelled. Remove lifecycle observers on stop
and register them at most once on start. Ignore results and bridge reads from
old run or connection generations. Add no faster retry, sign-in prompt, model request, or
Claude authentication/configuration write.

Freshness is not a request timeout. Synchronous Keychain access has no
established deadline. Do not claim to bound HTTP/Keychain duration, fix a hung
Security call, or guarantee unattended renewal. Deadline-bounded credential
lookup requires a separate design, including credential and process-isolation
implications.

## Safe local liveness evidence

Make in-progress quota attempts inspectable in local diagnostics. Emit an
attempt-start immediately before the repository call, with an allowlisted
trigger (`startup`, `scheduled`, `wake`, `connectivity`, `popover`, `manual`)
and local attempt timestamp. Emit completion only after applying a result from
the current generation; a stopped/superseded generation cannot report success.

Keep attempt start, direct-success time, failure-attempt time, and status-line
receipt time distinct. Completion reports only safe outcome and source; it
does not imply browser authentication. Log no raw errors, tokens, paths,
payloads, commands, or account identifiers. Diagnostics are local, not network
telemetry.

If synchronous Keychain lookup never returns, keep the local in-progress state
visible until stop or supersession. Do not fabricate a timeout or completion.

## Component boundaries

- `NeedlbarCore` owns per-window source selection/freshness and distinct direct
  success and status-line receipt timestamps.
- `RefreshCoordinator` owns coalescing, actual-attempt timing, single-flight
  execution, and run-generation fencing; periodic scheduling keeps the cadence.
- App lifecycle/connectivity signals start, wake, and offline-to-online events.
  Local cache reads remain separate from provider requests.
- Host-local diagnostics expose only allowlisted liveness fields and safe
  outcomes, without extending the Rust C-ABI/JSON diagnostics schema. UI uses
  shared Claude presentation policy, not separate source selection.
- No presentation logic moves to Rust; no provider or authentication component
  is added.

## Deterministic acceptance

Use an injected clock, synthetic observations, and fake repositories. Cover:

- Direct freshness just before, at, and after 15 minutes; timestamp equal to
  now; missing, non-finite, future timestamps; fresh versus failed/stale
  status; reset before/at/after its boundary; and missing reset display.
- Direct-current precedence; current status-line fallback after direct failure;
  most-recent dated last-known fallback; direct tie-break; timestamp-less
  retained value ranked last; and no invented value if neither source is valid.
- Fable freshness/timestamp independent of main quota, including stale Fable
  with fresh main window and unavailable Fable without fabricated reset.
- Identical status-line data not extending age; old-generation rejection; and
  dashboard/popover/Settings agreement as an open view crosses age/reset
  boundaries without a repository call.
- Start/wake/connectivity cache reads; catch-up just below/at five minutes;
  unchanged cadence; one in-flight plus one pending under overlap; stop/restart
  fencing and physical single-flight; rechecking pending recovery eligibility;
  coincident periodic/recovery requests sharing one attempt; observer cleanup;
  stale completion ignored.
- Typed expiry remains distinct from scheduler failure; failed attempt does
  not replace success; later direct success restores current state; diagnostics
  expose in-progress/start/completion without unsafe fields.
- No authentication flow, model request, Claude configuration write, or
  fabricated numeric zero in any recovery path.

Implementation must run focused tests, `make test`, and `git diff --check`.
Native installation, overnight freshness/reset observation, and long-term
recovery claims require separate evidence. This spec authorizes no installation,
authentication change, release, or publication.

## Accepted later roadmap

**Phase 2 — compact quota summary:** one named most-constrained window with
explicit remaining semantics; other windows, source, reset verification,
failure reason, and successful observation time in disclosure. Settings and
popover use consistent freshness labels. Requires a separate specification and
implementation plan after the reliability increment.

**Phase 3 — AI cost/quota workflow:** distinguish subscription remaining/reset,
today's local estimated usage cost, and the provider-owned API billing page.
Reuse existing surfaces; add no fabricated balance, provider, or analytics.

## References and relationship to approved designs

- [Claude Code status-line documentation](https://code.claude.com/docs/en/statusline)
  defines the status-line data and event-driven update context used by the
  existing bridge.
- [Anthropic authentication and credential-use policy](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use)
  is the boundary referenced by the approved designs; this specification adds
  no new claim about authorization or provider support.
- [Claude usage page](https://claude.ai/settings/usage) remains the explicit,
  provider-owned usage destination from the passive-recovery design.
- `docs/superpowers/specs/2026-09-15-claude-passive-quota-recovery-design.md`
  remains authoritative for passive recovery, safe failure reasons, and
  credential ownership.
- `docs/superpowers/specs/2026-09-25-claude-statusline-quota-bridge-design.md`
  remains authoritative for bridge installation, cache, source, generation,
  and status-line receipt semantics.

This specification covers the next bounded reliability increment only. It
does not establish the direct quota path as a provider-supported third-party
API and does not certify credential rotation, continuous status-line emission,
or long-term unattended success.
