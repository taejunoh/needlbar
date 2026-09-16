# Claude quota failure-origin diagnostics

Date: 2026-09-16

Status: Approach approved in conversation; written specification awaiting review.

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
and presentation mapping stay unchanged.

Bridge diagnostics add optional Claude-only origin and lastAttemptAt fields.
Capture lastAttemptAt when the existing operation begins, not when the diagnostic
record is read. Preserve the independent last-success timestamp. Success clears
the prior failure origin. A pending operation must not be labeled expired.
Existing JSON envelope and C ABI remain compatible; optional absent fields are
valid for older data. Do not add presentation logic to the bridge.

The Swift consumer reads the diagnostic snapshot after the matching existing
quota completion, frees the C string through the existing ownership convention,
and publishes one local OSLog diagnostic event with a fixed subsystem/category.
Only the allowlisted outcome/origin and attempt time may enter this event. Parse
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
