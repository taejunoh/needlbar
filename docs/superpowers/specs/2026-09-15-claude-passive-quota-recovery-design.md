# Claude passive quota recovery

**Date:** 2026-09-15

**Status:** Product direction approved; written specification awaiting review.

**Scope:** Reduce repeated user intervention for Claude quota failures.

## Decision

The user approved replacing repeated re-login guidance with last-known quota,
its last successful observation time, a safe failure explanation, and an optional
official usage-page link. They explicitly requested as little user action as
possible. This is graceful degradation, not a claim that unattended Claude
authentication renewal has been implemented or officially supported.

Alternatives considered:

1. **Passive recovery (selected):** retain existing successful readings, explain
   freshness, and recover when an existing scheduled refresh succeeds. No new
   login or credential-changing operation.
2. **Repeated browser login (rejected):** burdens the user and confuses a failed
   quota check with a requirement to reauthenticate.
3. **Needlbar-owned OAuth renewal (not selected):** changes credential ownership
   and risks concurrent token rotation; no supported integration has been
   established. Do not add it as a hidden fallback.

## Established facts and limits

- Needlbar reads access-token/expiry evidence on each Claude quota fetch. It
  does not cache the credential between fetches or use refresh tokens.
- An earlier one-shot diagnostic returned `authenticationExpired`; this can
  mean local expiry or an HTTP 401/403. It does not prove the cause of every
  subsequent failure or establish that the entire provider login is revoked.
- A later diagnostic produced no result before being terminated. Synchronous
  Security calls have no separate deadline, so no current error code was
  established by that attempt. Do not label a pending lookup as expired.
- Installed Claude Code 2.1.257 auth help lists login, logout, and status, not a
  standalone renewal command. Status is not a demonstrated renewal mechanism.
- This change does not certify the existing quota integration as a supported
  third-party provider API. Provider-supported integration remains a separate
  compatibility question.

## User experience

Apply this policy to Claude's dashboard row, provider popover, and Settings
connection presentation; leave Codex, Cursor, API billing, and local usage alone.

- Remove Claude's routine `Sign in with Claude` recovery CTA from these surfaces.
  Do not replace it with instructions to open a terminal, approve Keychain, or
  repeatedly press Retry. Do not launch the existing login flow from these rows.
- A valid fresh result continues to display normally.
- When a previous result exists but is stale or a refresh failed, keep the
  percentage and explicitly label it `Last known`. Show `Last checked` using
  the actual last successful quota timestamp in the user's locale/time zone.
  Do not substitute the last attempted refresh time.
- Without a previous successful result, show an em dash and `Quota unavailable`;
  never invent zero, a last-success timestamp, or a reset.
- Use one concise, safe provider-level reason: expired/rejected authentication
  becomes `Quota access unavailable`, permission denial becomes
  `Credential access unavailable`, network failure becomes `Connection unavailable`,
  rate limiting becomes `Temporarily limited`, and unclassified/schema/service
  failure becomes `Could not update quota`. Reasons must derive from typed,
  allowlisted errors, not raw error messages or inferred process timing.
- Fable shares Claude's freshness. Do not repeat the same error after both the
  main quota and Fable reset. Clearly mark the retained provider values as old;
  an old reset date must not imply a newly verified reset or a current 0% limit.
- Provide one optional `View Claude usage` action opening exactly
  `https://claude.ai/settings/usage` in the default browser on explicit click.
  Do not open it automatically or embed a login page. Browser authentication,
  if needed, remains provider-owned. This is subscription usage, not API billing.
- Failure to open the link produces a local safe message, not a login flow.
- Keep layout compact and accessible. No new modal, notification, badge count,
  or onboarding step is introduced.

## Recovery and architecture

Keep the existing scheduled quota refresh and its single-flight behavior; do not
increase frequency, add a login timer, trigger a model request to refresh auth,
or change credential lookup precedence. A later successful refresh replaces the
retained value and clears the stale/failure explanation automatically. This is
conditional on a fetch completing successfully, not a promise of automatic
credential renewal or a fix for the unbounded Keychain lookup.

Preserve a typed safe failure reason through NeedlbarCore where the current
normalization would otherwise collapse it, and expose only that enum and the
existing success timestamp to presentation. Keep raw provider messages, payloads,
credentials, and filesystem paths out of UI, exports, and logs. Retain current
schema compatibility and last-known-good semantics.

Do not parse or write refresh tokens, access browser cookies, create persistent
authentication stores, change Keychain ACLs, or run a live provider login during
implementation. An independently bounded Keychain helper/deadline is a separate
technical design, not silently bundled into this presentation change.

## Verification

Use deterministic injected data and actions, never live credentials:

- Fresh, stale, failed-with-cache, failed-without-cache, and pending states.
- Each allowlisted reason; unknown errors do not become authentication errors.
- Last-success timestamp differs from last-attempt timestamp and is displayed
  correctly; missing timestamps are not fabricated.
- Fable retains valid old data without duplicated error or misleading reset copy.
- A later successful snapshot clears the fallback with no user action.
- Claude surfaces invoke zero login actions, including failure and link-open error.
- The optional link uses only the fixed URL and only an explicit action.
- Codex/Cursor login, local usage, and API billing behavior remain unchanged.
- Focused tests, full `make test`, and `git diff --check` must pass before claiming
  implementation complete. Native visual acceptance and installation are separate;
  source changes must not be described as already running on the laptop.

## References checked on 2026-09-15

- [CLI reference](https://code.claude.com/docs/en/cli-reference): auth command list.
- [Authentication](https://code.claude.com/docs/en/authentication): provider credential
  ownership; setup-token is not an established quota-fetch solution.
- [Authentication and credential use](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use):
  restrictions relevant to adding a third-party authentication flow.
- [Claude usage](https://claude.ai/settings/usage): optional user-facing destination.

This specification amends only the Claude recovery presentation portions of the
2026-08-25 provider-managed login and 2026-09-12 preflight designs. It does not
authorize new authentication capabilities, installation, publication, or releases.
