# Claude quota failure-origin diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record and locally emit the exact safe branch of the existing Claude quota operation, so an installed app can distinguish credential expiry from usage-endpoint rejection without making another request or exposing credential data.

**Architecture:** The quota operation carries an optional, closed Claude-only origin alongside its existing safe error result; it is deliberately skipped from the regular quota JSON envelope. The existing in-process diagnostics record consumes that operation result plus its start time, preserving last successful quota time independently. Swift reads the existing diagnostics C export after the matching serialized operation completes and logs only an allowlisted enum and RFC3339 attempt time.

**Tech Stack:** Rust (`needlbar-quota`, `needlbar-bridge`), Swift concurrency/Foundation/OSLog, Swift Testing, Rust integration tests, existing C ABI.

---

## Non-negotiable constraints

- Do not add an export, polling timer, retry, HTTP request, CLI invocation, login/logout, credential write, Keychain ACL change, or browser action.
- Keep `QuotaErrorCode`, bridge error `code`/`message`, quota JSON, provider presentation, credential precedence, and success semantics unchanged.
- Never serialize/log a token, refresh token, cookie, header, response body, local path, account identifier, raw Security error, raw bridge JSON, or arbitrary error description.
- Preserve the existing dirty Claude UI-consistency edits. Do not reset, checkout, or reformat unrelated files.

## File map

- Modify: `crates/needlbar-quota/src/domain.rs` — carry an internal safe Claude-origin value and an internal HTTP status discriminator on `QuotaError`; neither enters the regular quota envelope.
- Modify: `crates/needlbar-quota/src/http.rs` — retain only HTTP 401 vs. 403 until Claude maps it to its closed origin.
- Modify: `crates/needlbar-quota/src/providers/claude_credentials.rs` — distinguish file and Keychain expiry before error normalization.
- Modify: `crates/needlbar-quota/src/providers/claude.rs` — assign the closed origin at resolver/endpoint branches and leave existing safe error codes/messages intact.
- Modify: `crates/needlbar-bridge/src/quota.rs`, `crates/needlbar-bridge/src/diagnostics.rs`, `crates/needlbar-bridge/src/lib.rs` — preserve the origin inside the one collection result, timestamp existing quota calls at start, and expose only optional Claude diagnostics fields from the existing export.
- Modify: `Sources/NeedlbarCore/Diagnostics/DiagnosticsSnapshot.swift`, `Sources/NeedlbarCore/Bridge/RustBridge.swift`, `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift` — decode the optional fields, bind the already-declared diagnostics function, and call one completion observer before the current single-flight drains its next request.
- Create: `Sources/Needlbar/Diagnostics/ClaudeQuotaFailureDiagnosticsReporter.swift` — read diagnostics and emit a fixed OSLog event constructed only from typed data.
- Modify: `Sources/Needlbar/App/AppDelegate.swift` — construct/inject the reporter for production refreshes.
- Test: `crates/needlbar-quota/src/providers/claude.rs`, `crates/needlbar-quota/src/providers/claude_credentials.rs`, `crates/needlbar-quota/src/http.rs`, `crates/needlbar-bridge/src/diagnostics.rs`, `crates/needlbar-bridge/tests/redaction_contract.rs`.
- Test: `Tests/NeedlbarCoreTests/DiagnosticsTests.swift`, `Tests/NeedlbarCoreTests/BridgeDecodingTests.swift`, `Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift`, `Tests/NeedlbarTests/ClaudeQuotaFailureDiagnosticsReporterTests.swift` (new).

### Task 1: Implement the single safe origin vertical slice

**Files:** all files in the File map except `Sources/Needlbar/App/AppDelegate.swift`; modify that file only in Step 5.

- [ ] **Step 1: Write the Rust RED tests for every origin at its owning branch.**

  Add a non-serialized `ClaudeQuotaFailureOrigin` with exactly these `serde(rename_all = "camelCase")` cases:

  ```rust
  pub enum ClaudeQuotaFailureOrigin {
      CredentialMissing,
      KeychainCredentialExpired,
      FileCredentialExpired,
      CredentialAccessDenied,
      UsageEndpointUnauthorized,
      UsageEndpointForbidden,
      OtherFailure,
  }
  ```

  Extend the existing Claude resolver and loopback HTTP fixtures to assert this exact matrix while asserting the old error code too:

  | fixture branch | existing `QuotaErrorCode` | origin |
  | --- | --- | --- |
  | no credential | `RequiresAuthentication` | `credentialMissing` |
  | Keychain expiry | `AuthenticationExpired` | `keychainCredentialExpired` |
  | fallback-file expiry | `AuthenticationExpired` | `fileCredentialExpired` |
  | no-UI/permission/cancelled credential access | `PermissionDenied` | `credentialAccessDenied` |
  | loopback HTTP 401 | `AuthenticationExpired` | `usageEndpointUnauthorized` |
  | loopback HTTP 403 | `AuthenticationExpired` | `usageEndpointForbidden` |
  | malformed credential, invalid response/schema, network/other unclassified Claude failure | existing code | `otherFailure` |

  Keep `parse_credential_payload`'s generic expiry test; the source-specific conversion belongs in the file and macOS Keychain resolver wrappers. Add a test that Codex's shared HTTP client still has its existing `AuthenticationExpired` result and never gains a Claude diagnostic field.

  Run:

  ```bash
  cargo test -p needlbar-quota providers::claude
  cargo test -p needlbar-quota http::tests
  ```

  Expected: the new origin assertions fail before production changes; existing tests remain green.

- [ ] **Step 2: Carry the typed value only with the quota operation, then record it in diagnostics.**

  In `QuotaError`, add `#[serde(skip)] pub(crate) claude_failure_origin: Option<ClaudeQuotaFailureOrigin>` and `#[serde(skip)] pub(crate) response_status: Option<u16>`, both initialized to `None` by `QuotaError::new`. Add crate-private builders and a read-only typed origin accessor for the bridge crate; these fields must never be copied to `BridgeError` or `QuotaPayload` JSON.

  `status_error` records only `401` or `403` in `response_status`; `ClaudeQuotaProvider::fetch_with_credential_access` converts those two values to endpoint origins after `for_provider(.Claude)`. Resolver errors map at `credential_error_to_quota_error`. Any Claude error arriving without an assigned origin is stored as `.OtherFailure`; no code infers origin from `AuthenticationExpired`.

  Add `claude_failure_origin: Option<ClaudeQuotaFailureOrigin>` to the in-memory `QuotaCollection`, and a `#[serde(skip)]` matching field on `QuotaPayload`. `envelope_from_collection` transfers it. This is the required result-local handoff: `needlbar_quota_snapshot_json` still emits the identical quota/error JSON shape.

  Capture `attempt_started_at` immediately before each existing `ffi_*quota_envelope()` call in `lib.rs`, then pass it with that same envelope to `record_quota`/`record_partial_quota`; do not timestamp in `needlbar_diagnostics_json`. Extend a Claude `StreamObservation` with:

  ```rust
  last_success_at: Option<String>,
  last_attempt_at: Option<String>,
  claude_failure_origin: Option<ClaudeQuotaFailureOrigin>,
  ```

  On a Claude attempt, always replace `last_attempt_at`; on success set `last_success_at` and clear the origin; on failure retain previous `last_success_at` and set the supplied origin. Serialize `lastAttemptAt` and `claudeQuotaFailureOrigin` only for the Claude diagnostic record and only when present. Codex/Cursor records must omit both fields.

  Add redaction-contract tests which pass every secret canary already defined in `redaction_contract.rs` through failures and assert that diagnostics contain only the seven enum strings and RFC3339 timestamps. Add a successful Claude fixture after a failing fixture and assert origin clears while `lastQuotaAt` stays the success time and differs from the failed attempt time.

  Run:

  ```bash
  cargo test -p needlbar-bridge diagnostics
  cargo test -p needlbar-bridge --test redaction_contract
  ```

  Expected: diagnostics JSON contains optional `claudeQuotaFailureOrigin`/`lastAttemptAt` only for Claude; it contains no canary or raw error text.

- [ ] **Step 3: Add safe Swift decoding and the existing-export binding before adding logging.**

  In `DiagnosticsSnapshot.swift`, add:

  ```swift
  public enum ClaudeQuotaFailureOrigin: String, Decodable, Sendable, Equatable {
      case credentialMissing, keychainCredentialExpired, fileCredentialExpired
      case credentialAccessDenied, usageEndpointUnauthorized, usageEndpointForbidden, otherFailure
  }
  ```

  Add optional `lastAttemptAt: Date?` and `claudeQuotaFailureOrigin: ClaudeQuotaFailureOrigin?` to `ProviderDiagnostics` and decode both with `decodeIfPresent`. Do not add them to `BridgeError` or quota snapshot models.

  Add `diagnosticsCall` to `RustBridge.init`, defaulting to `needlbar_diagnostics_json()`, and:

  ```swift
  public func diagnosticsEnvelope() throws -> BridgeEnvelope<DiagnosticsSnapshot> {
      try decodeCString(diagnosticsCall, decode: decoder.decodeDiagnosticsEnvelope)
  }
  ```

  Write `DiagnosticsTests` fixtures for absent optional fields (compatibility), all seven valid origins, unknown origin rejection, and malformed `lastAttemptAt` rejection. In `BridgeDecodingTests`, inject a diagnostics C string and a freeing recorder; assert one diagnostics call and exactly one free. Include secret-marker JSON with a decoding failure and assert the error is returned rather than logged by this layer.

  Run:

  ```bash
  swift test --filter DiagnosticsTests
  swift test --filter BridgeDecodingTests
  ```

  Expected: optional old diagnostics decode; malformed/unrecognized diagnostics fail closed; all returned C strings are freed once.

- [ ] **Step 4: Report after the matching current single-flight operation, without starting another one.**

  Add an optional `claudeQuotaOperationCompleted: (@Sendable () async -> Void)?` parameter to the testable `RefreshCoordinator` initializer with the public visibility needed by the app target and a nil default. In `finishQuotaRefresh`, after the existing generation/apply guard and before its `defer` clears `quotaTask`/drains queued work, invoke it exactly once only for `.backgroundAll`, `.claudePreflight`, or `.userInitiated(provider: .claude)`. Do not invoke it for Codex-only work, cancellation, stale generation, or an operation that never completed.

  Create `ClaudeQuotaFailureDiagnosticsReporter` with an injected `RustBridge` and an injected typed event sink. Its only public operation reads `bridge.diagnosticsEnvelope()`, selects the Claude record, and emits an event only when both allowlisted origin and `lastAttemptAt` are present. It catches every bridge/decoding failure and emits nothing. The production sink uses exactly:

  ```swift
  Logger(subsystem: "com.taejunoh.needlbar", category: "ClaudeQuotaFailureDiagnostic")
      .notice("claudeQuotaFailure origin=\(event.origin.rawValue, privacy: .public) attempt=\(event.attemptRFC3339, privacy: .public)")
  ```

  `ClaudeQuotaDiagnosticEvent` must build `attemptRFC3339` with a fixed RFC3339 formatter from `Date`, never interpolate diagnostic JSON, bridge error message, or `Error.localizedDescription`.

  Add a blocked single-flight test to `RefreshCoordinatorTests`: complete one Claude background result, make the observer wait, request another refresh, assert repository call count remains one until observer release, then assert exactly one queued normal operation begins. Add reporter tests for every origin, success/no-origin, malformed bridge JSON, absent fields, and canary-bearing ignored fields; the captured event must be only enum plus timestamp. Add an assertion that reporter invocation does not call a quota repository or any quota bridge closure.

  Run:

  ```bash
  swift test --filter RefreshCoordinatorTests
  swift test --filter ClaudeQuotaFailureDiagnosticsReporterTests
  ```

  Expected: one diagnostic read is associated with one completed Claude operation, parsing failure is inert, and no second quota operation occurs.

- [ ] **Step 5: Wire production and perform the focused integration gate.**

  In `AppDelegate.swift`'s `.production` setup, construct one reporter backed by `RustBridge()` and pass its async operation as `claudeQuotaOperationCompleted` when constructing `RefreshCoordinator`. Keep it local to production construction; do not add UI state, settings, persistence, telemetry, or an API. Ensure the callback exists before `startProductionRefresh` calls `RefreshCoordinator.start()`.

  Run:

  ```bash
  cargo test -p needlbar-quota
  cargo test -p needlbar-bridge
  swift test --filter DiagnosticsTests
  swift test --filter BridgeDecodingTests
  swift test --filter RefreshCoordinatorTests
  swift test --filter ClaudeQuotaFailureDiagnosticsReporterTests
  make test
  git diff --check
  ```

  Expected: all tests pass. Inspect the diff and reject it if any regular quota envelope adds an origin field, if `BridgeError` changes, if any error string/raw JSON reaches `Logger`, or if a refresh/request/timer was added.

### Task 2: Build, install, and observe one ordinary refresh

**Files:** no source changes required. Update `docs/STATUS.md` only after the observed safe event is recorded.

- [ ] **Step 1: Re-run the final source gate from the exact implementation commit.**

  ```bash
  PATH=/Users/taejunoh/.cargo/bin:$PATH make test
  git diff --check
  git status --short
  ```

  Expected: tests and whitespace check pass. Record pre-existing UI edits separately; do not include unrelated files in the diagnostic commit.

- [ ] **Step 2: Produce and locally install the approved diagnostic build.**

  ```bash
  PATH=/Users/taejunoh/.cargo/bin:$PATH make package
  ```

  Verify the package with the repository's existing signing/package checks, move the prior canonical app at `/Users/taejunoh/Developer/LFG/needlbar-runtime/latest/Needlbar.app` to a timestamped directory under `/Users/taejunoh/Developer/LFG/needlbar-runtime/backups/`, then install the newly packaged app at that exact canonical path. Preserve the existing settings and Keychain items; do not run any Claude command, credential command, or login action.

- [ ] **Step 3: Observe the startup/scheduled refresh already performed by the app.**

  Launch only the installed canonical app once and inspect its local unified log for the fixed category/event:

  ```bash
  log show --style compact --predicate 'subsystem == "com.taejunoh.needlbar" AND category == "ClaudeQuotaFailureDiagnostic"' --last 10m
  ```

  Report only one of the seven enum origins and its attempt timestamp, or `no Claude failure diagnostic event observed`. Absence of an event does not prove that a refresh never completed: a successful refresh also has no failure origin. It is not evidence of expiration. Do not force refresh, alter auth, send another quota request, or inspect credential contents.

- [ ] **Step 4: Record the factual result and scope the follow-up.**

  In `docs/STATUS.md`, state the installed build identity, whether an event was observed, the allowlisted origin if present, and that quota restoration remains unproven. If origin is `keychainCredentialExpired`, `fileCredentialExpired`, `credentialMissing`, `credentialAccessDenied`, `usageEndpointUnauthorized`, `usageEndpointForbidden`, or `otherFailure`, propose the recovery only as a separate approved design; do not bundle any recovery into this diagnostic change.

## Self-review

- Spec coverage: Task 1 covers all seven closed origins, result-local carriage, optional diagnostics, operation-start attempt time, preserved success time, existing C binding, one safe OSLog event, redaction, and single-flight association. Task 2 covers the required installed ordinary-refresh evidence and explicitly separates recovery.
- Compatibility: no new C export, no bridge error/code/message change, and optional diagnostics fields remain absent for old/non-Claude data.
- Security: no task reads or writes secrets. Every logged value originates from a closed enum or formatter-created timestamp.
- Scope: no presentation, provider-source, cadence, credential-precedence, or authentication-flow change is planned.
