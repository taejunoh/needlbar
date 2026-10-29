# Claude quota failure-origin diagnostics

Date: 2026-09-16

Status: Approach and written specification approved on 2026-09-16.

> **Amendment — 2026-10-22:** The approved
> `docs/superpowers/specs/2026-10-22-claude-credential-renewal-design.md`
> (increment 1, decision Q1) amends the presentation sentence in "Data and
> ownership", for local-expiry origins only. The diagnostics record that the
> Swift consumer already reads after each completed Claude quota operation is
> now read once and shared by the OSLog reporter and the refresh coordinator.
> The coordinator uses `keychainCredentialExpired` or `fileCredentialExpired`
> to select a dedicated presentation reason only for the attempt that record
> describes. Error codes, messages, the bridge record, the C ABI, the JSON
> schema, and the OSLog event are unchanged.

> **Amendment — 2026-10-29:** Approved by the user to diagnose
> `otherFailure`. On the maintainer's Mac the installed v0.3.12 has failed
> every direct Claude quota attempt since at least 2026-10-28 with only
> `origin=otherFailure` logged, and that origin covers credential-format,
> usage-response and HTTP/transport failures alike. The OSLog event now also
> carries the allowlisted Claude quota error code, taken from the same bridge
> diagnostics record entry (`quotaErrorCode`) as the origin and attempt time,
> so the three always describe the same attempt:
>
> `claudeQuotaFailure origin=<origin> code=<code> attempt=<RFC 3339 second>`
>
> The code allowlist is closed: `notInstalled`, `requiresAuthentication`,
> `authenticationExpired`, `permissionDenied`, `rateLimited`,
> `networkUnavailable`, `providerUnavailable`, `schemaChanged`, and
> `unknown`. The first eight are the codes the bridge can record for a Claude
> quota error; the Rust `serviceUnavailable` code (HTTP 5xx) is folded into
> `providerUnavailable` before it reaches Swift. An absent code, or a record
> code that is not a quota code, logs `unknown`. A record whose code does not
> decode still fails closed and emits no event. No message, URL, header, body,
> token, path, HTTP status or payload enters the event; the line is one public
> string built only from the two closed values and the timestamp. No HTTP
> status class is logged, because the Swift-visible record has none and adding
> one would change the bridge schema. The quota layer, bridge record, C ABI,
> JSON schema, presentation, and the event's subsystem and category are
> unchanged.

## Objective

Identify the failing stage of the installed app's ordinary Claude quota refresh.
This diagnostic is not itself a quota recovery fix. Completion requires observing
a safe origin from the actual installed process, not merely passing fixtures.
Restoring actual quota values remains the subsequent objective once the cause
is established.

## Evidence

- The provider-owned CLI reports logged in. This does not prove usage-endpoint
  access or token validity for Needlbar.
- The shell and installed app have no custom CLAUDE_CONFIG_DIR.
- An existence-only Keychain query for Claude Code-credentials succeeded, with
  all attributes and output suppressed. No secret was printed or changed.
- The fallback credential file is expired, but Needlbar uses it only when the
  Keychain lookup returns NotFound. Its expiry does not prove the current cause.
- Local credential expiry and HTTP 401/403 currently normalize to the same error.
- Existing process-memory diagnostics do not preserve that distinction and have
  no Swift consumer. A new process cannot inspect the running process's history.

## Selected approach

Preserve a closed failure-origin value through the existing quota operation into
the existing bridge diagnostic record. Add a read-only Swift binding for the
diagnostics export and emit a strictly allowlisted local diagnostic event after
the existing quota operation completes. Do not perform a second quota request.

Alternatives rejected for this step: repeating login changes authentication
without identifying the failure; renewing tokens changes credential ownership;
inferring the cause from CLI logged-in state or an expired fallback file is not
sufficient evidence.

## Data and ownership

The quota layer assigns the origin at the actual failing branch, before generic
error normalization. Carry it with the operation result, not an unrelated global
last-error variable. Allowed origins are:

- credentialMissing
- keychainCredentialExpired
- fileCredentialExpired
- credentialAccessDenied
- usageEndpointUnauthorized (HTTP 401)
- usageEndpointForbidden (HTTP 403)
- otherFailure

Do not infer an origin from elapsed time, UI state, or generic authenticationExpired.
Unclassified errors remain otherFailure. Existing public error codes/messages
and presentation mapping stay unchanged, except *(amended 2026-10-22)* that an
`authenticationExpired` failure whose associated origin is
`keychainCredentialExpired` or `fileCredentialExpired` presents as
`Claude Code access on this Mac expired`. The origin is associated only when
the record's lastAttemptAt is not earlier than the attempt start truncated to
whole seconds, the attempt is in the current run generation, and its Claude
result failed. HTTP 401/403 and the other origins keep the existing mapping.

Bridge diagnostics add optional Claude-only origin and lastAttemptAt fields.
Capture lastAttemptAt when the existing operation begins, not when the diagnostic
record is read. Preserve the independent last-success timestamp. Success clears
the prior failure origin. A pending operation must not be labeled expired.
Existing JSON envelope and C ABI remain compatible; optional absent fields are
valid for older data. Do not add presentation logic to the bridge.

The Swift consumer reads the diagnostic snapshot after the matching existing
quota completion, frees the C string through the existing ownership convention,
and publishes one local OSLog diagnostic event with a fixed subsystem/category.
Only the allowlisted outcome/origin and attempt time may enter this event
*(amended 2026-10-29: plus the allowlisted Claude quota error code)*. Parse
failure must produce no raw payload output and must not affect quota refresh.
Tests must establish the completion/record association under current single-flight
behavior. No history file, telemetry, or UI setting is added.

## Security and scope boundaries

Never log credentials, refresh tokens, cookies, headers, response bodies, account
identifiers, file paths, raw Security errors, or raw diagnostic JSON. Never dump
Keychain data. All logging must construct output from the enum and timestamp;
string interpolation of arbitrary provider errors is forbidden.

No login, logout, token renewal, credential writes, ACL changes, cookie access,
model requests, new polling schedule, extra quota request, or provider source
change. Keep credential precedence, network behavior, timeouts, and success
semantics unchanged. Preserve the already tested uncommitted UI corrections.

## Verification and local observation

1. Inject each resolver/expiry/HTTP branch and assert distinct safe origin.
2. Assert other failures are not mislabeled as authentication failures.
3. Verify last-attempt versus last-success timestamps and clearing on success.
4. Use secret-marker fixtures to prove that diagnostics and emitted events cannot
   contain payloads, tokens, account details, paths, or raw error strings.
5. Test optional-field decoding, C-string freeing, and no extra quota invocation.
6. Run focused tests, full make test, diff checks, and independent review.
7. Package with the same local Developer ID identity and install with a recoverable
   previous-app backup, preserving settings and authentication data.
8. Observe the existing scheduled/startup refresh event from that installed app.
   Report its actual branch; a missing/pending event is not evidence of expiry.

No release, push, or public publication is included. If observation identifies a
need for new authentication capabilities, propose that separate change rather
than silently bundling it into diagnostics. Do not claim the user's quota is
restored until real values have been verified in the app.
