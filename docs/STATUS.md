# Needlbar Development Status

**Updated:** 2026-08-30
**Branch:** `main` (PR #3 merge commit `181e41d07d9c2dfe41edb37d9257e697dd5840d7`; v0.2.0 final feature commit `6f39ec6917db92a6566b545aab0eef80cfd4540f`)
**Current phase:** The approved v0.1 implementation and credentialed tagless release validation are complete; no tag or public GitHub Release exists. All five v0.2.0 local JSON export plan tasks are complete and integrated into `main`. The final feature commit `6f39ec6917db92a6566b545aab0eef80cfd4540f` fixes cross-Xcode JSON key ordering with an internal UTF-8 lexical canonical writer. Final whole-branch review and scoped fix re-review are clean (`Ready to merge: Yes`); main CI is green.
**Next action:** Begin the v0.2.1 widgets/notifications design and implementation only when the user authorizes that scope. The v0.1 tag/public-release gate remains separate: until explicit authorization is given, no tag or release action is authorized.

## Source of Truth

The active Needlbar work is governed by:

- `docs/superpowers/specs/2026-08-13-needlbar-v0.1-design.md` — approved architecture and product scope.
- `docs/superpowers/plans/2026-08-13-needlbar-v0.1.md` — ordered implementation plan.
- `docs/superpowers/specs/2026-08-25-provider-managed-browser-login-design.md` — approved authentication UX amendment.
- `docs/superpowers/plans/2026-08-25-provider-managed-browser-login.md` — ordered follow-up implementation plan.
- `docs/superpowers/specs/2026-08-29-needlbar-v0.2.0-local-json-export-design.md` — approved v0.2.0 local JSON export contract; implementation and acceptance are recorded below.
- `docs/superpowers/plans/2026-08-29-needlbar-v0.2.0-local-json-export.md` — approved v0.2.0 local JSON export implementation plan; all tasks are implemented and documented below.
- `AGENTS.md` — continuation rules for Codex/agentic workers.

## What Is Already Implemented

Task 1 bootstrap files exist on `main`, including:

- SwiftPM package with `Needlbar`, `NeedlbarApp`, `NeedlbarCore`, and `CNeedlbar` targets.
- Rust workspace with `needlbar-bridge`, `needlbar-source-sync`, and `needlbar-quota` crates.
- Pinned `vendor/tokscale-core` submodule.
- Root `Makefile` and `scripts/build-rust.sh`.
- Tracked `Cargo.lock` for deterministic Rust dependency resolution.
- Minimal Swift and Rust bootstrap sources/tests.
- GitHub Actions CI on `macos-14` running `make test`.

Task 1 continuation commits on `main`:

- `dea34b2` — select Xcode 16.2 for Swift tests on CI.
- `a7ca67a` — track `Cargo.lock`.

Task 2 implementation commits on `main`:

- `29a0b71` — add the versioned Rust/Swift bridge contract.
- `c46c4f8` — format the bridge ABI contract with scoped `rustfmt`.

Task 3 implementation commit on `main`:

- `37846c3` — aggregate Claude and Codex usage with `tokscale-core`.

Task 4 implementation commits on `main`:

- `066e985` — hydrate Cursor usage before aggregation.
- `96e49e7` — harden Cursor cache synchronization and validate exports.
- `e8f0953` — close Cursor cache path races and support v1 CSV compatibility.
- `1cef31c` — separate mechanical source-sync Clippy hygiene.

Task 5 implementation commits on `main`:

- `cf25a5f` — add the shared quota domain and Claude adapter.
- `7526171` — harden Claude quota/auth/HTTP boundaries.

Task 6 implementation commits on `main`:

- `c77ed8d` — add the Codex quota adapter with RPC fallback.
- `86f374f` — harden Codex RPC fallback transport and cleanup.
- `37b8aaf` — validate Codex RPC request and response contracts.

Task 7 implementation commits on `main`:

- `ecf6d32` — add Cursor quota and explicit connection flow.
- `20e02b6` — harden Cursor session import and source sync.

Task 8 implementation commit on `main`:

- `8fd1e21` — expose partial quota results through the bridge.

Task 9 implementation commit on `main`:

- `f078ff7` — add Swift bridge models and stale state.

## Current CI State

Task 1 is verified green.

- Local `make test` passed on Swift 6.3.3 and Rust 1.97.1.
- `Cargo.lock` is tracked for deterministic Rust dependency resolution.
- GitHub Actions run [31837456920](https://github.com/taejunoh/needlbar/actions/runs/31837456920) succeeded in 3m49s.
- CI retains `runs-on: macos-14` and deliberately selects `/Applications/Xcode_16.2.app` before running tests.
- `Package.swift` remains on Swift tools version 6.0 with a macOS 14 deployment target.
- No approved-baseline deviation was made.

## v0.2.0 Local JSON Export — Task 5 Acceptance and Completion

The v0.2.0 implementation plan was completed only after the acceptance evidence for all five numbered tasks was recorded. The pre-integration implementation head `2eafbdb` (`fix: expose pending snapshot cleanup safely`) included sanitized `cleanupPending` and the `requiresAuthentication` regression. Task 5 adds the public documentation and acceptance record without changing implementation code. The v0.1 release authorization gate remains separate and unchanged.

Final focused and full acceptance on pre-integration head `2eafbdb` passed:

- `swift test --filter SnapshotFileWriterTests` — exit 0.
- `swift test --filter SnapshotExporterTests` — exit 0.
- `source /Users/taejunoh/.cargo/env && make test` — exit 0; the Rust workspace, pinned `tokscale-core` suite, Swift tests, package relink regression, and notarization shell contracts passed.

Release-like checks run at pre-integration head `2eafbdb` also passed:

- `swift build -c release` — exit 0.
- `make package` — exit 0; the local arm64/macOS 14 bundle was produced.
- `make smoke` — exit 0; bundle metadata, signature, executable identity, launch, and bounded cleanup passed.

The bounded live Settings/save-panel export and cancellation acceptance is explicitly evidence from the initial implementation head `718748e`; it remains the recorded live UI run and was not rerun on `2eafbdb` or the final feature commit. No Foundation `JSONSerialization` re-encode byte-equality claim is made; the exact sorted-key/golden behavior remains covered by `SnapshotExporter` automation.

Bounded live UI acceptance completed through the accessibility fallback: the exact packaged app from this worktree was running, Settings opened from its status-item popover, and the Data Export button opened the production save panel. The panel default was `Needlbar-Snapshot-20260829T233601572Z`; selecting the harmless LFG destination produced `/Users/taejunoh/Developer/LFG/Needlbar-Snapshot-20260829T233601572Z.json` (with the OS-appended `.json` extension). `stat` reported mode `600` and size `3055`; `file` reported JSON data; the final byte was `0a`. Parsed data reported `schemaVersion: 1`, provider order `claude,codex,cursor`, `cursor.quota.data == null`, and an empty forbidden-key intersection for `title`, `message`, `path`, `accountId`, `prompt`, `response`, `sourceCode`, `cookie`, and `credential`. Object keys followed the `SnapshotExporter`/`JSONEncoder` sorted-key contract; exact full golden behavior remains covered by automation. No Foundation `JSONSerialization` re-encode byte-equality claim is made because its numeric-key ordering differs for `last7Days` and `last30Days`. A second export click opened the panel again; Cancel returned to Settings and the only matching file remained the first saved file, proving cancellation created nothing. No credentials, account identifiers, prompts, responses, cookies, or source content were inspected.

No Rust/C/provider/auth/network changes, extra export entry points, raw error/title fields, tag, or release action were introduced. No tag or public GitHub Release was created; until explicit authorization is given, no tag or release action is authorized.

Final whole-branch review and the scoped fix re-review were clean with `Ready to merge: Yes`; PR #3 integration and green main CI are recorded below.

## v0.2.0 Integration Completion — 2026-08-30

Pull request [#3](https://github.com/taejunoh/needlbar/pull/3) merged at `2026-08-30T00:42:48Z` via merge commit `181e41d07d9c2dfe41edb37d9257e697dd5840d7`. The local `main` worktree was fast-forwarded to that merge commit before this documentation update. The final feature commit `6f39ec6917db92a6566b545aab0eef80cfd4540f` (`fix: canonicalize snapshot JSON key order`) replaced the cross-Xcode-sensitive encoder ordering with an internal UTF-8 lexical canonical writer after PR CI run [33282531973](https://github.com/taejunoh/needlbar/actions/runs/33282531973) failed on the Xcode 16.2 golden-byte test.

Corrected PR CI run [33283518126](https://github.com/taejunoh/needlbar/actions/runs/33283518126) passed. Main CI run [33283963156](https://github.com/taejunoh/needlbar/actions/runs/33283963156) passed all Rust, vendored, lint, `make test`, package, smoke, and artifact steps. The prior release build/package/smoke evidence and the live Settings save/cancel evidence remain recorded above with their exact head boundaries; the live UI run was on initial head `718748e`, not rerun after `6f39ec6`.

V0.2.0 is complete. The next continuation point is the separately scoped v0.2.1 widgets/notifications design and implementation, only after explicit user authorization. No tag or public GitHub Release was created; until explicit authorization is given, no tag or release action is authorized.

## Task 2 Verification

Task 2 is complete. The bridge now provides:

- `needlbar_usage_snapshot_json`, `needlbar_quota_snapshot_json`, and `needlbar_diagnostics_json` C exports.
- `needlbar_free_string` with null acceptance and Rust-owned `CString` exact-once release semantics.
- Versioned JSON envelopes with `schemaVersion`, `ok`, `generatedAt`, `data`, and `errors` fields.
- The typed `BridgeError { provider: Option<String>, code: String, message: String }` contract.
- Panic containment at every exported snapshot/free boundary, returning a versioned `internalError` envelope when needed.

Verification evidence:

- RED: `source /Users/taejunoh/.cargo/env && cargo test -p needlbar-bridge --test ffi_contract` exited 101 with the expected missing `needlbar_diagnostics_json` and `needlbar_free_string` symbols.
- GREEN: `cargo test -p needlbar-bridge` passed with 3 tests and `make test` exited 0; Rust passed including `tokscale-core` (1372 passed, 0 failed, 1 ignored) and Swift passed 2 tests.
- Scoped formatting: `cargo fmt -p needlbar-bridge -- --check` exited 0 after formatting only Task 2-owned Rust files.
- No approved-baseline deviation was made.

## Task 2 Contract (Complete)

The completed Task 2 bridge contract is:

Primary files from the approved plan:

- `Sources/CNeedlbar/include/needlbar.h`
- `crates/needlbar-bridge/src/envelope.rs`
- `crates/needlbar-bridge/src/lib.rs`
- Task 2 bridge contract tests described in the implementation plan

Required exported C ABI:

```c
const char *needlbar_usage_snapshot_json(void);
const char *needlbar_quota_snapshot_json(void);
const char *needlbar_diagnostics_json(void);
void needlbar_free_string(const char *ptr);
```

Required JSON envelope fields:

- `schemaVersion`
- `ok`
- `generatedAt`
- `data`
- `errors`

The bridge must contain panic boundaries and clear Rust-owned string lifetime/freeing semantics. Do not add presentation logic to the bridge.

## Task 3 Verification

Task 3 is complete. The usage adapter owns only the bridge-facing aggregation and delegates discovery/parsing to the pinned `tokscale-core` public graph-report API:

- Builds `tokscale_core::ReportOptions` and calls `tokscale_core::generate_local_graph_report` through a short-lived Tokio runtime.
- Consumes `GraphResult.contributions[] -> DailyContribution.clients[]`; no Claude/Codex parser copies were added to Needlbar.
- Aggregates the exact upstream client IDs `claude` and `codex` into all-time, today, rolling 7-day, and rolling 30-day periods.
- Rejects negative/corrupt signed counters and invalid costs before converting to normalized unsigned bridge values.

Fixture totals are deterministic and sanitized:

| Provider | Input | Output | Cache read | Cache write | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Claude | 1000 | 250 | 400 | 100 | 1750 |
| Codex | 800 | 200 | 300 | 0 | 1300 |

Partial provider behavior is explicit: when one provider has no usage source, usable provider data remains in `data`, the envelope remains `ok: true`, and a provider-scoped `noUsageData` error is appended. When no providers have data, the envelope is `ok: false` with `noUsageData` errors.

Verification evidence:

- RED: `source /Users/taejunoh/.cargo/env && cargo test -p needlbar-bridge --test usage_contract` exited 101 before the adapter existed with the expected missing `usage::collect_usage_from_home` symbol (the partial-envelope test also intentionally exited 101 before extraction).
- GREEN: `cargo fmt -p needlbar-bridge -- --check`, `cargo test -p needlbar-bridge --test usage_contract`, `cargo test -p needlbar-bridge`, and `cargo test --manifest-path vendor/tokscale-core/Cargo.toml` all exited 0; the pinned engine reported 1372 passed, 0 failed, 1 ignored.
- GREEN project verification: `source /Users/taejunoh/.cargo/env && make test` exited 0; Rust passed including the pinned engine and Swift passed 2 tests.
- Task 2 CI run [31838440815](https://github.com/taejunoh/needlbar/actions/runs/31838440815) is green.
- No approved-baseline deviation was made; no vendor revision was changed.

## Task 4 Verification

Task 4 is complete. Needlbar now hydrates the pinned Tokscale-compatible Cursor usage cache before usage aggregation without adding a Cursor transcript/parser source or changing the pinned core revision.

Implementation and contract evidence:

- Credentials are resolved only from `~/Library/Application Support/Needlbar/cursor-session.json`, with private `0700` session directory and `0600` session/cache/marker/temp files on Unix. The session token is never logged or copied into bridge errors.
- The fixed request target is Cursor's proven Tokscale export endpoint, `https://cursor.com/api/dashboard/export-usage-events-csv?strategy=tokens`, with a bounded 15-second HTTP timeout and the `WorkosCursorSessionToken` cookie only.
- The five-minute freshness gate skips transport calls for fresh cache/attempt markers; `force=true` bypasses it. Every attempt touches `usage.last-sync-attempt`.
- Cache writes are same-directory temporary-file `write_all`/`sync_all` followed by rename and parent-directory `sync_all`, preserving the previous cache on transport, malformed-response, or durability failure.
- CSV validation accepts the pinned parser's v1, v2, and v3 layouts, requires parser-valid rows, and rejects malformed or unsupported responses before replacement.
- Unix path handling is descriptor-relative and no-follow: intermediate directories use `openat`/`mkdirat` with `O_DIRECTORY | O_NOFOLLOW`, leaves reject symlinks/non-regular files, and rename/cleanup/fsync remain descriptor-relative.
- The bridge places `usage.csv` at `<fixture-home>/.config/tokscale/cursor-cache/usage.csv` and relies on the pinned core's normal `ReportOptions.home_dir` discovery; no custom cache-root fork was added.
- Production refresh calls `sync_cursor_cache(false)` before scanning Claude, Codex, and Cursor. A sync failure becomes a provider-scoped `cursorSyncFailed` warning while valid prior Cursor cache data remains usable.

Verification evidence:

- Original RED: `source /Users/taejunoh/.cargo/env && cargo test -p needlbar-source-sync --test cursor_sync` and `cargo test -p needlbar-bridge --test cursor_usage_contract` exited 101 with the expected missing source-sync API/imports and missing Cursor snapshot assertion.
- Original GREEN: `cargo fmt -p needlbar-source-sync -p needlbar-bridge -- --check`, `cargo test -p needlbar-source-sync`, `cargo test -p needlbar-bridge --test cursor_usage_contract`, `cargo test -p needlbar-bridge`, `cargo test --manifest-path vendor/tokscale-core/Cargo.toml`, and `source /Users/taejunoh/.cargo/env && make test` exited 0; the pinned engine reported 1372 passed, 0 failed, 1 ignored, and Swift passed 2 tests.
- Hardening GREEN: source-sync tests passed 4 tests after malformed-response/no-follow validation and 5 tests after descriptor-relative traversal/v1 compatibility; bridge cursor contract passed 1 test; scoped rustfmt and `make test` passed with the pinned engine at 1372 passed, 0 failed, 1 ignored and Swift at 2 passed.
- Task 3 CI run [31839252018](https://github.com/taejunoh/needlbar/actions/runs/31839252018) is green.
- No approved-baseline deviation was made and the `tokscale-core` vendor revision was not changed.

## Task 5 Verification

Task 5 is complete and review-approved. The shared quota domain and Claude adapter are implemented without Codex/Cursor quota code, browser scraping, Keychain access, login prompts, token-history parsing, bridge changes, or presentation changes.

Implementation and contract evidence:

- The quota domain provides `ProviderId`, checked `QuotaWindow`, `ProviderQuotaSnapshot`, `QuotaErrorCode`, `QuotaError`, and the async `QuotaProvider` trait. Percentages are finite and normalized to `0...100`; invalid values return `schemaChanged` without clamping.
- Claude credential precedence is exact: `CLAUDE_CONFIG_DIR/.credentials.json` when configured, otherwise `~/.claude/.credentials.json`. Background refresh uses existing file OAuth only, never Keychain/browser scraping; missing or unusable credentials return `requiresAuthentication`, and known expired evidence returns `authenticationExpired`.
- The bounded/redacting HTTP client uses the Anthropic OAuth usage endpoint with a 15-second timeout, validates the allowed HTTPS host before attaching bearer authorization, does not follow redirects, limits response bodies to 64 KiB, bounds `Retry-After`, and never exposes fixture tokens or response bodies in errors.
- Sanitized Claude fixtures produce stable `claude.session` and `claude.weekly` windows; malformed, missing-reset, and out-of-range payloads fail safely as `schemaChanged`.

Verification evidence:

- Claude integration suite: `cargo test -p needlbar-quota --test claude` — 11 passed, 0 failed.
- Quota package: `cargo test -p needlbar-quota` — 7 unit tests and 11 Claude integration tests passed.
- Scoped lint: `cargo clippy -p needlbar-quota --all-targets -- -D warnings` passed after preserving the separate Task 4 hygiene commit `1cef31c`.
- Full project gate: `PATH="$HOME/.cargo/bin:$PATH" make test` passed; Rust workspace including pinned `tokscale-core` had 1372 passed, 0 failed, 1 ignored, and Swift had 2 passed.
- Formatting and `git diff --check` passed.
- Task 5/documented head `e0d3da0` is pushed and green in [run 31841873719](https://github.com/taejunoh/needlbar/actions/runs/31841873719).
- No approved-design deviation was made; the pinned `tokscale-core` revision and all prior v0.1 constraints are unchanged.

## Task 6 Verification

Task 6 is complete, review-approved, and has no open findings. Codex quota uses the authenticated primary source first and a bounded exact app-server fallback without launching an interactive TUI or login flow.

Implementation and contract evidence:

- Primary auth resolves `$CODEX_HOME/auth.json`, falling back to `~/.codex/auth.json`; OAuth evidence remains Rust-only and never enters presentation data or debug output.
- The primary source calls the allowlisted `https://chatgpt.com/backend-api/wham/usage` endpoint through the bounded redacting HTTP client. The fallback runs `codex -s read-only -a untrusted app-server` with a 20-second deadline, capped stdout/stderr, request-ID correlation, `kill_on_drop`, explicit kill/wait/reap, and stderr-task cleanup.
- The JSON-RPC transcript is exact: initialize → initialized → `account/read` with `params: {}` → `account/rateLimits/read` without params; matched responses require JSON-RPC 2.0 and tolerate notifications/mismatched IDs safely.
- Primary and secondary windows plus reset fields accept absent/null provider values; available windows are preserved, both missing windows produce a valid empty snapshot, and malformed present values or contradictory percentages fail closed as `schemaChanged`.
- Stable window IDs remain `codex.primary` and `codex.secondary`; executable-missing, authentication, deadline, and malformed-RPC cases map to the documented safe error categories.

Verification evidence:

- Transport unit tests: `cargo test -p needlbar-quota --lib providers::codex::tests` — 6 passed.
- Codex integration tests: `cargo test -p needlbar-quota --test codex` — 6 passed.
- Quota package: `cargo test -p needlbar-quota` — 30 passed.
- `cargo check -p needlbar-quota` and `cargo clippy -p needlbar-quota --all-targets -- -D warnings` passed.
- Full project gate: `make test` passed; Rust workspace including pinned `tokscale-core` had 1372 passed, 0 failed, 1 ignored, and Swift tests passed.
- Task 6/documented head `7aada1a` is pushed and green in [run 31843385394](https://github.com/taejunoh/needlbar/actions/runs/31843385394).
- No approved-design deviation was made; all prior v0.1 constraints and the pinned `tokscale-core` revision remain unchanged.

## Task 7 Verification

Task 7 is complete and review-approved. The review has no open findings; the only deferred minor is logger-capture coverage, which is non-blocking because the bridge has no logging path.

Implementation and contract evidence:

- `CursorSessionStore` is shared by source sync and quota, remains Rust-owned, preserves descriptor-relative no-follow handling, and performs atomic durable saves with private `0600` permissions and safe clear/load behavior.
- Cursor quota uses the bounded `https://cursor.com/api/usage-summary` request with HTTPS/host validation, redirects disabled, a 15-second timeout, the session cookie only, and the existing 64 KiB response cap. Usage-source transport is likewise bounded and preserves the last valid cache on failure.
- Cursor windows are stable `cursor.plan` and `cursor.onDemand`; absent billing-cycle end remains `resetsAt: null`, while malformed/contradictory values fail closed as `schemaChanged`.
- Missing/invalid sessions and 401/403 errors carry structured serialized `action: "connectCursor"`; `BridgeError { provider, code, message }` remains unchanged.
- `needlbar_cursor_import_session_json` validates null/UTF-8/empty/whitespace/control input, verifies before saving, contains panics, returns only `{ "connected": true }`, and the ABI/redaction tests prove the token is absent from JSON/debug/captured-log surfaces.

Verification evidence:

- Source-sync suite: `cargo test -p needlbar-source-sync` — 12 tests passed (2 unit + 10 integration).
- Cursor quota suite: `cargo test -p needlbar-quota --test cursor` — 7 passed.
- Bridge suite: `cargo test -p needlbar-bridge` — 9 passed across unit and integration targets.
- Affected strict lint: `cargo clippy -p needlbar-source-sync -p needlbar-quota -p needlbar-bridge --all-targets -- -D warnings` passed; formatting checks passed.
- Full project gate: `make test` passed; Rust workspace including pinned `tokscale-core` had 1372 passed, 0 failed, 1 ignored, and Swift tests passed.
- `vendor/tokscale-core` is clean and remains pinned at `53f9eefffd3278fd430076531548f7b1f5861f9a`.
- Task 7/documented head `fcc5d22` is pushed and green in [run 31845316146](https://github.com/taejunoh/needlbar/actions/runs/31845316146).
- No approved-design deviation was made; all prior v0.1 constraints remain unchanged.

## Task 8 Verification

Task 8 is complete and review-approved with no Critical or Important findings. One minor delayed-provider test remains deferred and is non-blocking.

Implementation and contract evidence:

- `quota::collect_quota()` runs Claude, Codex, and Cursor adapters concurrently with bounded provider-owned timeouts while preserving deterministic provider/error order: Claude, Codex, Cursor.
- Partial and all-provider failures preserve usable `data.providers` and provider-scoped errors with `ok: true`; only bridge-wide runtime, panic, or serialization failures return `ok: false`.
- Synchronous quota C ABI calls execute collection on a dedicated Rust thread with a short-lived Tokio runtime, preventing nested-runtime panics when the embedding process already runs Tokio.
- The additive structured `BridgeError.action` field propagates Cursor's `connectCursor` action without changing the required `provider`, `code`, and `message` fields. Usage and diagnostics ABI behavior remains compatible.

Verification evidence:

- Focused bridge contract: `cargo test -p needlbar-bridge --test quota_contract` — 2 passed.
- Full bridge suite: `cargo test -p needlbar-bridge` — 11 passed.
- `cargo fmt -p needlbar-bridge -- --check`, `cargo check -p needlbar-bridge`, and `cargo clippy -p needlbar-bridge --all-targets -- -D warnings` passed.
- Full project gate: `make test` passed; Rust workspace including pinned `tokscale-core` had 1372 passed, 0 failed, 1 ignored, and Swift tests passed.
- Task 8/documented head `dc9f6d1` is pushed and green in [run 31846072025](https://github.com/taejunoh/needlbar/actions/runs/31846072025).
- No approved-design deviation was made; all prior v0.1 constraints and the pinned `tokscale-core` revision remain unchanged.

## Task 9 Verification

Task 9 is complete and review-approved with no Critical or Important findings. Three test-only minors are deferred: successful/null-pointer bridge coverage, successful quota live-shape coverage, and generic pre-success/partial routing coverage.

Implementation and contract evidence:

- Added normalized Swift provider, usage, quota, status, and merged snapshot models with additive/live wire decoding that tolerates unknown fields, providers, and actions without installing unknown providers.
- Decimal costs decode exactly from decimal strings and the existing Rust numeric representation, without a `Double` round-trip.
- The Rust bridge wrapper copies C bytes into Swift-owned data and frees every non-null Rust string exactly once on all decode paths, including decoding errors.
- Usage and quota repositories retain partial successes and provider-scoped errors independently. The actor-isolated snapshot store keeps independent usage/quota values and last-success timestamps, preserving prior values on refresh failures and applying authentication status only before any valid value exists.

Verification evidence:

- Focused Swift verification: `swift test --filter NeedlbarCoreTests` — 7 independently focused tests passed after the final decoding-error free-path regression.
- Full project gate: `source /Users/taejunoh/.cargo/env && make test` exited 0; Swift reported 8 tests passed, Rust workspace including pinned `tokscale-core` had 1372 passed, 0 failed, 1 ignored.
- `source /Users/taejunoh/.cargo/env && make rust` exited 0.
- Remote CI remains green through Task 8 at [run 31846072025](https://github.com/taejunoh/needlbar/actions/runs/31846072025); Task 9 commit `f078ff7` is local and its CI push is pending.
- No approved-design deviation was made; all prior v0.1 constraints and the pinned `tokscale-core` revision remain unchanged.

## Task 10 Verification

Task 10 is complete and final concurrency/spec review-approved with no findings. Refresh coordination, file-system triggers, and the production forced Cursor synchronization path are implemented across the assigned Swift, Rust, and C bridge layers.

Implementation and contract evidence:

- Manual and scheduled refreshes coordinate bounded usage and quota work independently. Usage keeps the approved five-minute cadence, file changes debounce for one second, and popover-triggered retries use the approved 60-second retry window.
- The forced usage ABI reaches production `sync_cursor_cache(true)` through the Rust bridge and Swift `UsageRepository`, so a manual refresh actually bypasses the Cursor freshness gate while preserving the existing repository path and pinned `tokscale-core` discovery layout.
- Refresh effects are guarded by run generation, manual bursts coalesce, watcher startup/stop ownership is lifecycle-safe, and descriptor/file-descriptor leases remain safe across asynchronous callbacks and cancellation.
- Usage and quota remain independently refreshable and independently fallible; one side's failure does not erase the other's valid last-known-good state.

Task 10 implementation commits on `main`:

- `cba429c` — coordinate bounded usage and quota refresh.
- `4675a40` — force Cursor sync through the production refresh bridge.
- `06aff57` — guard refresh effects by run generation.
- `8a873e4` — coalesce forced refresh requests.
- `f37eb2a` — close refresh lifecycle races.
- `ae2d70b` — isolate stale watcher startup.
- `916a29d` — await quota refresh completion in the synchronization regression test.
- `7e345d5` — serialize semaphore-based refresh race suites to prevent CI executor starvation.

Verification evidence:

- `cargo fmt -p needlbar-bridge -- --check` and `cargo clippy -p needlbar-bridge --all-targets -- -D warnings` passed.
- `swift test --filter RefreshCoordinatorTests` — 8 tests passed.
- `swift test --filter UsageFileWatcherTests` — 5 tests passed.
- `source /Users/taejunoh/.cargo/env && make test` passed: Swift 21 tests, Rust including pinned `tokscale-core` 1372 passed, 0 failed, 1 ignored.
- `git diff --check` passed and `git -C vendor/tokscale-core status --short` was clean.
- Final independent review approved with no Critical, Important, or Minor findings. A test-only synchronization defect was diagnosed as a wait-condition issue; production behavior was verified correct, and `916a29d` now waits for the first quota refresh to finish before issuing the retry.
- The first Task 10 CI run [31852585168](https://github.com/taejunoh/needlbar/actions/runs/31852585168) was cancelled after more than 16 minutes in the Test workspace. Its log ended after Swift Build completed with an orphan `swiftpm-testing` process, matching the diagnosed test-only cooperative-executor starvation from three concurrent semaphore-based race tests rather than a production defect. Commit `7e345d5` adds `@Suite(.serialized)` to preserve the assertions and contracts; the reviewer approved the correction with no findings.
- Root verification passed: `RefreshCoordinatorTests` ran 10 times with `--parallel --num-workers 2`; `make test` passed with Swift 21 tests and pinned `tokscale-core` 1372 passed, 0 failed, 1 ignored; `git diff --check` and the vendor status check were clean.
- No approved-design deviation was made; the pinned `tokscale-core` revision and all v0.1 constraints remain unchanged.

- Remote verification is complete: Task 10 CI run [31853771074](https://github.com/taejunoh/needlbar/actions/runs/31853771074) passed in 7m1s at head `6b7b969`. This confirms the Task 10 retry containing `7e345d5`; Task 11 remains the next implementation task.

## Task 11 Verification

Task 11 is complete and rereview-approved with no findings. Module configuration and menu-bar title rendering now follow the approved v0.1 defaults and presentation boundary.

Implementation and contract evidence:

- The approved defaults are Overview enabled, all providers disabled, and `quotaRemaining` as the quota headline mode.
- Only non-secret UI preferences are stored in injected `UserDefaults`; credentials and provider session data remain outside the configuration layer.
- The enabled-provider quota headline selects the most constrained available Overview quota, while Overview token and cost totals aggregate every available usage snapshot.
- The pure menu-bar renderer uses a neutral unavailable state, deterministic number/cost formatting, deterministic reset formatting including `nil`, and checked `UInt64` aggregation without overflow wrapping.

Task 11 implementation commits on `main`:

- `5a00c3c` — implement module configuration and menu-bar title logic.
- `6dbd4a9` — resolve review findings and harden configuration/rendering behavior.

Verification evidence:

- Review round 1 found 2 Important and 1 Minor findings; all were resolved in `6dbd4a9`, and rereview approved with no findings.
- Root fresh verification passed: `ModuleConfigurationTests` — 2; `HeadlineQuotaSelectorTests` — 4; `MenuBarTitleRendererTests` — 5.
- `source /Users/taejunoh/.cargo/env && make test` passed with Swift 32 tests and pinned `tokscale-core` 1372 passed, 0 failed, 1 ignored.
- `git diff --check` passed and `git -C vendor/tokscale-core status --short` was clean.
- No approved-design deviation was made; the pinned `tokscale-core` revision and all v0.1 constraints remain unchanged.
- Remote verification is complete: Task 11 CI run [31854765005](https://github.com/taejunoh/needlbar/actions/runs/31854765005) passed in 4m40s at head `84a1d7c`. Task 12 remains the next implementation task.

## Task 12 Verification

Task 12 is complete and rereview-approved with no findings. The native accessory runner and hybrid status-item shell now own lifecycle coordination while keeping normalized state and presentation logic in their assigned layers.

Implementation and contract evidence:

- The thin AppKit runner/accessory shell is wired to the existing `LSUIElement` application configuration; `Info.plist` already had `LSUIElement`, so no manifest churn was needed.
- `AppDelegate` owns one long-lived snapshot store, module configuration, refresh coordinator, Rust-backed repositories, watcher, and menu-bar controller for the application lifetime.
- Menu-bar handles reconcile incrementally. Snapshot and configuration observations are installed with explicit cleanup, avoiding duplicate observers and stale handles.
- Titles remain neutral when data is unavailable. `terminateLater` performs exactly-once awaited shutdown of the owned lifecycle resources.

Task 12 implementation commits on `main`:

- `b3cb0ca` — build the native accessory app and hybrid status items.
- `b491f32` — resolve lifecycle/shutdown review findings.

Verification evidence:

- Review round 1 found 1 Important shutdown finding; it was resolved in `b491f32`, and rereview approved with no findings.
- Root fresh verification passed: `MenuBarControllerTests` — 7; `AppDelegateLifecycleTests` — 1.
- `source /Users/taejunoh/.cargo/env && make test` passed with Swift 40 tests and pinned `tokscale-core` 1372 passed, 0 failed, 1 ignored.
- `git diff --check` passed and `git -C vendor/tokscale-core status --short` was clean.
- Smoke verification initially hit the expected local-PATH-only failure when `make run` was invoked without the Cargo environment. After `source /Users/taejunoh/.cargo/env`, `make run` built and launched Needlbar; the foreground process group was interrupted and `pgrep` confirmed no Needlbar process remained.
- No approved-design deviation was made; the pinned `tokscale-core` revision, existing `LSUIElement` setting, and all v0.1 constraints remain unchanged.
- Remote verification is complete: Task 12 CI run [31855885744](https://github.com/taejunoh/needlbar/actions/runs/31855885744) passed in 4m39s at head `4988d10230c30c347d5ab2d92af1155a9aec684d`. Task 13 remains the next implementation task.

## Task 13 Verification

Task 13 is complete and the final reviewer approved it after three rounds. Overview, provider popovers, and Settings now cover partial data, provider connections, and the approved UI preferences without moving secrets into Swift persistence.

Implementation and contract evidence:

- `Overview`, provider popovers, and Settings use shared presentation models for partial usage/quota states, neutral unavailable rendering, provider rows, quota windows, resets, stale/error indicators, and the Settings action.
- The existing aggregate bridge/Core contract now has the additive `last7DaysDaily` field: exactly seven chronological dated `{date,totalTokens}` points, including legitimate zero days, with checked token aggregation. Swift treats an absent additive field as `[]` for compatibility.
- The Cursor Settings path adds the safe, idempotent `needlbar_cursor_clear_session_json` ABI backed by Rust-owned session clearing. It returns only the disconnect result, releases its response, and preserves token redaction.
- Cursor input remains transient `@State`; import/clear run off-main, clear the input before work completes, and serialize connect/reconnect/disconnect operations so rejected actions retain no token and cannot race an accepted action.

Task 13 implementation commits on `main`:

- `e10cad3` — add AI usage popovers and Settings.
- `0a9cda1` — harden enabled-provider quota selection and off-main secret handling.
- `7720c81` — serialize Cursor connection actions.

Verification evidence:

- TDD RED coverage first caught the missing presentation models, additive `last7DaysDaily` bridge/Core field, and missing `needlbar_cursor_clear_session_json`; subsequent RED regressions covered enabled-provider headline selection, transient-input clearing, and serialized slow Cursor actions.
- Final review completed three rounds and approved with no findings.
- Root fresh verification passed: `cargo test -p needlbar-bridge` — 8 unit plus 7 integration/contract tests (15 total); `swift test --filter PopoverPresentationTests` — 10 tests.
- `source /Users/taejunoh/.cargo/env && make test` passed with Swift 51 tests and pinned `tokscale-core` 1372 passed, 0 failed, 1 ignored.
- `git diff --check` passed and `git -C vendor/tokscale-core status --short` was clean at pinned revision `53f9eefffd3278fd430076531548f7b1f5861f9a`.
- Bounded `make run` built and launched Needlbar; Ctrl-C stopped the foreground process group and a follow-up process check found no lingering Needlbar process.
- Live interactive menu-bar clicks and a real Cursor-session smoke were not performed in the noninteractive environment; automated seams cover secret clearing and connection ordering.
- The daily series and Cursor disconnect are deliberate additive bridge-contract extensions required by the Task 13 plan, not a product redesign or scope deviation. No other approved-design deviation was made.
- Remote verification is complete: Task 13 CI run [31857311990](https://github.com/taejunoh/needlbar/actions/runs/31857311990) passed in 4m49s at tested head `0d73338aa9d79f40de42192d5715a60a824c15a6`. Task 14 remains the next implementation task.

## Task 14 Verification

Task 14 is complete and the final reviewer approved the implementation in review round 2. Diagnostics, privacy guardrails, public documentation, and the full feature-only integration seam now enforce the approved v0.1 boundaries.

Implementation and contract evidence:

- Rust diagnostics use safe DTOs with fixed provider, subsystem-status, source, and error-code enums. Swift uses a strict diagnostics decoder. The bounded observation store records only actual usage/quota ABI statuses, timestamps, and safe codes; it performs no extra source, credential, or provider-response scans.
- Redaction coverage exercises the real exported C usage, quota, diagnostics, and free functions plus safe `BridgeError` serialization. `CLAUDE-CANARY-SECRET`, `CODEX-CANARY-SECRET`, and `CURSOR-CANARY-SECRET`, a raw path, and an email are absent while safe provider/code/action fields remain available.
- The feature-only fixture runtime drives the real C ABI through `RustBridge`, the usage/quota repositories, and `ProviderSnapshotStore` end to end. It covers usage and quota for all three providers, deterministic constrained Cursor selection, and partial Codex failure isolation without erasing other providers.
- Eight public documents lock the architecture, privacy, provider boundaries, security, contribution, and project usage contracts. Diagnostics and privacy surfaces exclude tokens, cookies, emails, raw paths, prompts, responses, and source code.
- The integration work discovered and fixed the `estimatedCostUsd` versus approved `estimatedCostUSD` wire mismatch with an explicit Rust serialization rename.
- The test harness feature is absent from the production C header and default bridge archive. `make swift-test` uses an exit/signal trap to restore the production bridge and clean SwiftPM artifacts, including after interrupted or failed test runs; archive/header checks found no `needlbar_test_*` markers.

Task 14 implementation commits on `main`:

- `5c0e339` — add diagnostics, privacy guardrails, public documentation, and feature-only integration coverage.
- `9e56abc` — harden ABI redaction, wire compatibility, and test artifact hygiene.

Verification evidence:

- TDD RED coverage first caught the absent diagnostics module/decoder and outcome mapper; follow-up RED coverage caught the real ABI `estimatedCostUSD` mismatch and stale SwiftPM static-library reuse.
- Root fresh `make test` exited 0 with Swift 54 tests and pinned `tokscale-core` 1372 passed, 0 failed, 1 ignored.
- `cargo clippy --workspace --all-targets --all-features -- -D warnings` passed.
- `swift build -c release` exited 0. It emitted pre-existing, non-blocking macOS object-version/Apple linker warnings; the release build succeeded.
- `git diff --check` passed and `git -C vendor/tokscale-core status --short` was clean at pinned revision `53f9eefffd3278fd430076531548f7b1f5861f9a`.
- Strings checks over the release archive and production header found no `needlbar_test` markers.
- The feature-only test harness is a deliberate test-only integration seam required by the Task 14 plan, not a production feature or design deviation. No other approved-design deviation was made.
- The first Task 14 CI run [31859272045](https://github.com/taejunoh/needlbar/actions/runs/31859272045) failed only after the builds because the Makefile symbol audit invoked unavailable `rg`; no test or build failed. Systematic diagnosis produced follow-up commits `c27b3b5` (portable `strings`/`grep` audit), `bd8b439` (trap-before-`mktemp` and signal cleanup), and `8e24654` (restoration-failure priority). Reviewers approved the fixes, and restricted-PATH local `make test` passed with Swift 54 and pinned core 1372 passed/1 ignored.
- Remote verification is complete: Task 14 CI run [31859898712](https://github.com/taejunoh/needlbar/actions/runs/31859898712) passed in 4m52s at tested head `8e246543ef89bc789582e646d81c2cc7a6807492`. Task 15 remains the next implementation task.

## Task 15 Verification

Task 15 completes the approved v0.1 implementation plan. The final independent reviewer approved the packaging, smoke, cleanup, and release-workflow implementation after the review rounds.

Implementation and artifact evidence:

- The production build is an arm64 macOS 14 Rust/Swift accessory app with no test-only runtime feature. Packaging produces `dist/Needlbar.app` and `dist/Needlbar-macos-arm64.zip`; the app bundle contains `Contents/Info.plist`, the arm64 `Contents/MacOS/Needlbar` executable, and `Contents/Resources/ThirdPartyNotices.txt`. The zip has `Needlbar.app` at its archive root.
- `make package` applies an ad-hoc signature accepted by strict `codesign` verification. `scripts/smoke-app.sh` validates plist, signature, and arm64 executable identity, launches the exact bundle executable, and performs bounded cleanup.
- Smoke cleanup captures the launched PID, parent PID, exact executable command, and `ps lstart` identity before signaling. PID reuse/identity mismatch, deferred `INT`/`TERM`, bounded mismatch return, fixture-directory cleanup, and exact-PID regressions are covered; cleanup never signals an unverified process.
- CI gates run workspace Cargo tests/strict Clippy, `make test`, package, packaged-app smoke, and arm64 artifact upload. The tag release workflow hard-gates stable publication on Developer ID certificate/keychain setup, Apple ID/team/app-specific-password secrets, then signs, notarizes, staples, re-verifies, and publishes the zip.
- README install/privacy requirements, MIT licensing, Tokscale attribution, and third-party notices are included. `MACOSX_DEPLOYMENT_TARGET=14.0` preserves the approved macOS 14 floor and removes the locally observed Rust object-version linker warning.

Task 15 implementation commits on `main`:

- `d120264` — package and verify the Needlbar macOS release.
- `6d1c240` — harden PID identity and deferred-signal cleanup.
- `fecb08c` — bound identity-mismatch cleanup without synchronous waiting.
- `5adaa7f` — close the fixture cleanup window around temporary directories and signals.
- `a8e82fc` — harden fixture child identity capture and exact cleanup.

Final acceptance evidence:

- From the initialized submodule checkout, the pinned revision check, `cargo test --workspace`, `cargo clippy --workspace --all-targets --all-features -- -D warnings`, `make test`, `make package`, `./scripts/smoke-app.sh`, and `git diff --check` all passed.
- Root final gate reported Swift 54 tests, pinned `tokscale-core` 1372 passed with 1 ignored, strict workspace Clippy success, clean vendor state at `53f9eefffd3278fd430076531548f7b1f5861f9a`, and clean plist/codesign/file/unzip/artifact checks. Focused smoke cleanup regressions passed repeatedly with no lingering Needlbar process or fixture directories.
- The first production `make run`/packaged-app smoke launched and terminated cleanly; the exact PID was cleaned and no Needlbar process remained.
- No implementation or approved-design deviation was made. The macOS 14 deployment-target setting is an explicit build correction that preserves the approved platform floor.

- Hosted Task 15 verification is complete: CI run [31861693135](https://github.com/taejunoh/needlbar/actions/runs/31861693135) passed in 8m33s at tested head `98203636d5c8a5d5dd99cc2e575f18fb2ae7cea7`. Rust workspace tests, strict Clippy, `make test`, package, cleanup regression, packaged smoke, and arm64 artifact upload all passed.
- Uploaded artifact `Needlbar-macos-arm64` has API id `9240875960`, size `5,139,200` bytes, was created `2026-08-15T03:32:10Z`, is not expired, and expires `2026-11-13T03:23:36Z`. Its downloaded `Needlbar-macos-arm64.zip` is 5,151,078 bytes with SHA-256 `1358d46f0c0ec29474e43d458a6b0c3751931df6ca9236d56a75a218ab7dccbe`; unzip integrity passed with `Needlbar.app` at the root, correct `Contents`, and no `dist` prefix, `__MACOSX`, or AppleDouble files.

Release acceptance intentionally not claimed:

- No git tag or GitHub Release was created.
- Local Developer ID signing, strict verification, and hardened-runtime checks passed. Notarization, stapling, and publication were not run because the required secrets were not provided; the release workflow refuses to publish an ad-hoc stable artifact when they are absent.
- Manual Accessibility click-through and partial live smoke were performed on 2026-08-15; the full provider matrix remains incomplete for Claude quota/auth fallback, Cursor usage/quota with an explicit session, and the Codex CLI fallback.

## Credentialed/Manual Release Acceptance — 2026-08-15

- On a supported Mac, the packaged app launched as an accessory/menu-bar app with Overview as the only initial item. macOS Accessibility click-through opened the Overview popover, Settings window, and Codex provider popover. Enabling Codex added a second menu item; disabling it restored the single Overview item. An immediately-read `AXValue` can be stale after a press, but defaults, menu state, and rendered state agreed; no product bug was found.
- A one-process ABI run returned usage successfully for Claude and Codex, with seven daily points each; Cursor returned `noUsageData`. Quota returned one successful Codex window; Claude observed `authenticationExpired` followed by `rateLimited`; Cursor returned `requiresAuthentication`/`connectCursor` because no session was available. Diagnostics reflected these statuses safely. The Codex CLI fallback was not forced because its primary source succeeded.
- A standalone usage scan completed in approximately 89 seconds on the large local history during the second controlled run. The UI stayed responsive and displayed last-known-good data; this is a non-blocking performance observation unless the approved specification changes.
- Gatekeeper rejected an unstapled/unnotarized copy as expected after the local Developer ID sign/strict-verification/hardened-runtime check. The GitHub repository secret list is empty, so the stable notarization workflow cannot run. No Cursor session was available.

Remaining release acceptance: retry Cursor explicit-session connection once with a fresh current session token obtained through the documented supported route, without broadening to browser crawling; then configure the required GitHub notarization/release secrets and run the notarize/staple/Gatekeeper gate. The Codex CLI fallback remains unforced. Only after those gates may the user authorize a v0.1 tag/release.

## Final v0.1 Continuation

The original fifteen-task implementation plan and hosted CI/artifact verification are complete. Release acceptance is now paused by the approved authentication amendment below; complete its separate follow-up plan and verification before returning to credentialed/manual release acceptance and a user-authorized v0.1 tag/release.

## Approved Authentication Amendment — 2026-08-25

> The provider-managed browser-login and Cursor-paste records below are historical records
> from before the approved 2026-08-26 Cursor local-usage/dashboard amendment. Their Claude
> and Codex requirements remain active; every Cursor session-token, private-endpoint, and
> connection requirement is superseded by the amendment and is not an active instruction.

The user approved a deliberate post-plan design change before release acceptance:

- Claude gains `Sign in with Claude`, launching `claude auth login --claudeai` as an explicit user action.
- Codex gains `Sign in with ChatGPT`, launching `codex login` as an explicit user action.
- The provider CLIs continue to own browser navigation, OAuth callbacks, token refresh, and credential storage.
- Needlbar does not add an OAuth client, persist or expose Claude/Codex tokens, read browser profiles, or retain child-process output.
- The user explicitly approved access to Claude Code's exact provider-owned macOS Keychain item after clicking Connect. Raw credentials remain ephemeral inside Rust quota code and never cross the C ABI; background refresh uses interaction-forbidden access and never displays Keychain UI.
- Cursor retains the current explicit validated session-token Connect/Reconnect/Disconnect path. Cursor's documented CLI browser login does not expose the personal usage/quota handoff required by Needlbar.
- AppKit owns login-process lifecycle; `NeedlbarCore` gains typed background/user-initiated quota intents; Rust adds dedicated Claude-only and Codex-only post-authentication quota exports but no login/OAuth callback API.

The approved delta spec is `docs/superpowers/specs/2026-08-25-provider-managed-browser-login-design.md`. The test-first execution plan is `docs/superpowers/plans/2026-08-25-provider-managed-browser-login.md`.

### Task 1 Follow-Up Verification

Task 1 of the provider-managed browser-login follow-up is complete and review-approved. The implementation was delivered in focused commits:

- `6611ac0` — add prompt-safe Claude credential resolution.
- `35cecf0` — cover Claude bearer canary redaction.
- `57331fa` — confine the Claude test endpoint seam.

TDD RED was observed for the missing credential-access API and the follow-up test seams before implementation. Final verification passed: Claude integration — 16 tests; full `needlbar-quota` — 46 tests; formatting check; Clippy with `-D warnings`; default Cargo check; and `git diff --check`.

No real Keychain access, UI interaction, or external provider call was performed. The spec-compliance review passed, and the code-quality review passed with no issues. The pre-existing Task 15 verification remains valid for the current code, but release acceptance remains paused; the full authentication amendment is not complete.

### Task 2 Follow-Up Verification

Task 2 of the provider-managed browser-login follow-up is complete and review-approved. The implementation was delivered in focused commits:

- `fc76d64` — map `PermissionDenied` through the bridge integration path, restoring the full workspace green after Task 1.
- `ca80091` — add provider-specific Claude/Codex quota ABI exports.
- `8b6fd5c` — resolve diagnostics/runtime review fixes.
- `09112dc` — scope fixture sessions and remove production fallback behavior.
- `7adc458` — harden zero-session handling.

The provider-specific exports are `needlbar_claude_user_initiated_quota_snapshot_json` and `needlbar_codex_quota_snapshot_json`. Claude's explicit login path uses `UserInitiatedAllowUI`; the all-provider path remains `BackgroundNoUI`; and the Codex-only path does not invoke unrelated providers.

Verification evidence:

- FFI contract — 3 tests; quota contract — 6 tests; redaction contract — 6 tests; full bridge suite passed.
- Clippy with `-D warnings` passed; full `make test` exited 0 with Swift 55 tests and pinned `tokscale-core` 1372 passed, 0 failed, 1 ignored.
- No real Keychain, network, or UI interaction was performed; only pre-existing linker warnings remain.
- Final spec-compliance and code-quality reviews approved with no Critical, Important, or Minor findings.

Release acceptance remains paused, and the full authentication amendment is not complete.

### Task 3 Follow-Up Verification

Task 3 of the provider-managed browser-login follow-up is complete and review-approved. Typed quota refresh intents, dedicated provider calls, and generation-scoped coordinator fairness are implemented without browser, Keychain, or network interaction.

Implementation and contract evidence:

- Typed background and user-initiated quota intents are carried through the bridge/repository/coordinator path; Claude and Codex use dedicated provider calls, while Cursor is explicitly unsupported for typed provider refresh.
- Rust-owned C strings are freed exactly once by exact pointer, and generation-scoped waiters complete exactly once. Requested-provider failures remain scoped to the requested provider.
- Background freshness gates and ticket fairness preserve the approved refresh behavior, and quota refresh has no usage side effects.

Task 3 implementation commits:

- `843d588` — initial typed quota refresh implementation.
- `0095163` — fix waiter generation and protocol behavior.
- `f910e9a` — add dedicated validation and fairness coverage.

Verification evidence:

- Final Bridge suite: 15 tests passed.
- Final coordinator suite: 23 tests passed.
- Final Swift suite: 80 tests passed.
- `make swift-test` and `make test` exited 0.
- The implementation is spec-compliant; the quality review found no Critical, Important, or Minor findings.
- No browser, Keychain, or network interaction was performed, and no provider login command was launched.

Release acceptance remains paused. Task 4's non-TTY manual gate is complete; continue with Task 5 before returning to the remaining release-acceptance checks.

### Task 4 Automated Verification

Task 4's automated implementation is complete and final spec-compliance and code-quality reviews passed with no open Critical or Important findings. The separate user-authorized non-TTY provider compatibility gate also passed, so Task 4 is accepted as complete.

Implementation commits through the current head `3364c3c` include the provider login coordinator, direct POSIX runner, bounded termination/reaping hardening, deterministic syscall seams, admission lifetime fixes, and the documented gate result. No provider credentials, account identifiers, or login URLs are recorded here.

Verification evidence:

- `make swift-test` passed in five consecutive runs, with 113 Swift tests each run.
- `make test` passed cleanly after the final Task 4 implementation and test hardening.
- `git diff --check` passed and the working tree is clean.
- The final automated review evidence covers process lifecycle, signal/reap races, exact executable/argv/env/fd/CLOEXEC contract, cancellation/timeout/stop coalescing, descendant isolation, and failure-path bounds.

### Task 4 Non-TTY Provider Compatibility Gate

The user-authorized non-TTY compatibility gate passed on 2026-08-25 using the implementation runner's exact contract: direct `posix_spawn`, exact executable path and fixed argv, stdin from `/dev/null`, stdout/stderr from `/dev/null`, allowlisted environment, and no shell, PTY, output parsing, or credential capture.

- Claude Code 2.1.238: the resolver selected `/Users/taejunoh/.local/bin/claude`; `auth login --claudeai` opened the provider-owned browser and exited with status 0 after 207.856 seconds. The sanitized status was `loggedIn: true`, `authMethod: claude.ai`.
- Codex CLI 0.142.5: the resolver selected `/opt/homebrew/bin/codex`; `login` opened the provider-owned browser and exited with status 0 after 17.626 seconds. The sanitized status was `Logged in` / `ChatGPT`.

No provider login child remained after either run. The production Rust archive was restored without test symbols, the temporary manual test was removed, and the worktree remained clean. No account identifiers, URLs, credentials, or provider CLI output were persisted in project files.

### Task 4 approved implementation deviation — direct POSIX spawn

The approved Task 4 implementation keeps AppKit as the application/lifecycle owner but replaces the planned Foundation transport with direct macOS `posix_spawn` and parent-owned nonblocking `waitpid`. Foundation Process was rejected because it can reap asynchronously and exposes only a numeric PID; direct spawn/waitpid preserves PID identity until Needlbar itself reaps the child.

The single session actor is the sole waitpid owner. The runner resolves an exact executable URL/path (never `posix_spawnp`), validates NUL-free executable/argv/envp values, passes the executable path as `argv[0]` followed by fixed arguments, builds an allowlisted `envp`, connects stdin to `/dev/null` read and stdout/stderr to `/dev/null` write through spawn file actions, and sets `POSIX_SPAWN_CLOEXEC_DEFAULT`. It polls `waitpid(WNOHANG)`, retries `EINTR`, treats `ECHILD` as an invariant violation with no further signal, switches to reap confirmation after `ESRCH`, and bounds other signal failures. Timeout, cancellation, and app stop coalesce into TERM, bounded grace, KILL, and final reap of the direct PID only; descendants are never targeted.

Task 4 verification included harmless real-child normal and TERM-only exits, TERM-to-KILL, cancellation, timeout, cancel-plus-stop coalescing, pre/post-spawn cancellation, syscall-seam `WNOHANG`/exit/`EINTR`/`ECHILD`/`ESRCH`/KILL-failure cases, exact argv/env/fd/CLOEXEC assertions, descendant isolation, and the user-authorized non-TTY provider command compatibility gate.

### Task 5 Verification

Task 5 is complete and final spec-compliance and code-quality reviews passed with no open findings. Settings and provider popovers expose the approved Claude/Codex browser-login actions, and app termination now preserves the required direct-child cleanup and retry semantics.

Implementation commits:

- `6f0a5fc` — expose Claude and Codex browser login.
- `fd5935c` — document the approved degraded termination behavior.
- `12cacf8` — report bounded login cleanup state.
- `a308b29` — keep the app alive while a login child is reaped.
- `675a713` — revalidate login process ownership.
- `c14cc39` — close login admission during termination.
- `3fdff59` — reopen login admission after a negative termination reply.
- `4eca8b5` — avoid nested task polling in the login runner.

Behavior and contract evidence:

- Login cleanup reports either `allChildrenReaped` or `backgroundReaping`. A persistent signal or `waitpid` failure sends exactly one negative AppKit reply, does not stop refresh, keeps the app/coordinator and affected provider admission alive while the actor reaps the exact child, and permits a later termination request to retry cleanup.
- Successful termination remains conditional on all login children being reaped before refresh shutdown. Concurrent termination requests coalesce, and admission closes during cleanup so no new login can race termination.
- The coordinator retains exact PID ownership through background reaping and resumes admission only after a denied termination decision; no credentials, account identifiers, or provider output are persisted.

Verification evidence:

- Repeated `make swift-test` runs were green, and the latest agent-reported `make test` completed successfully; final root verification remains the next verification step.
- Final Task 5 spec-compliance and code-quality reviews passed with no Critical, Important, or Minor findings.
- The Task 4 non-TTY compatibility gate remains accepted for Claude Code and Codex; no additional provider login was run during Task 5 implementation.

### Task 6 Final Verification and Claude Credentialed Acceptance — 2026-08-26

Task 6 implementation and Claude credentialed acceptance are complete for the exercised path. The following focused fixes were applied and reviewed:

- `3202474` — split the Claude Keychain lookup into reference and data phases while retaining the exact `Claude Code-credentials` service.
- `fe88442` — select the single accepted macOS Keychain item from the returned item list.
- `61e2d5f` — force the Swift release executable to relink during packaging without clearing SwiftPM caches.
- `226bda5` — accept explicit `null` Claude reset timestamps.
- `7d43804` — run the packaging relink regression through the default `make test` path.

Credentialed acceptance evidence:

- With Claude Code 2.1.238, the user-authorized `/Users/taejunoh/.local/bin/claude auth login --claudeai` flow completed successfully through the provider-owned browser.
- The exact Keychain service returned exactly one parseable item. No Keychain UI prompt appeared because access was already allowed; a prompt is not required when exact-item access succeeds.
- The live packaged app produced fresh Claude quota and fresh Codex quota. Claude Settings showed `Connected.` directly. The first Codex button attempt showed `Login incomplete.` because a new provider-auth tab was left incomplete and an already-successful tab was mistakenly treated as the current flow; this was an acceptance procedure error, not a product change.
- The exact `/opt/homebrew/bin/codex login` non-TTY revalidation completed the current provider flow for the account/workspace and exited 0. The Needlbar Codex button was then run again through a newly completed provider flow; Settings showed Codex `Connected.` and fresh Codex quota. Login-child completion was observed.
- Raw credentials and account data were never printed, persisted, or copied.

Fresh verification evidence:

- Claude integration: 17 tests passed; FFI contract: 3 passed; quota contract: 6 passed; redaction contract: 6 passed.
- Strict workspace Clippy passed. `make test` passed with the pinned `tokscale-core` suite at 1372 passed, 0 failed, 1 ignored, and Swift at 124 passed.
- The packaging regression passed through `make test`; codesign verification, zip creation, and packaged-app smoke passed. `vendor/tokscale-core` remained clean at the approved pinned revision.
- Specification and code-quality reviews were approved after the `package-test` CI linkage was added.
- Open PR #1 ([github.com/taejunoh/needlbar/pull/1](https://github.com/taejunoh/needlbar/pull/1)) remains open, unmerged, and currently `MERGEABLE`.
- The provider implementation/status head validated by hosted CI is `b3d116071d0ed3200b4ea431e2d65657329987ab`; run [32987657091](https://github.com/taejunoh/needlbar/actions/runs/32987657091) for that exact head completed `SUCCESS` at `2026-08-26T16:26:20Z`; the `test` job passed.
- The following status update is docs-only and changes no product code.
- Historical outage evidence: hosted CI run [32984248738](https://github.com/taejunoh/needlbar/actions/runs/32984248738) was queued with zero jobs while GitHub's official Actions status reported `major_outage` at `2026-08-26T15:11:58Z`.

### Cursor Explicit-Session Acceptance — 2026-08-26

- Packaged-app Settings showed Claude and Codex `Connected`; the Cursor session store was absent before the attempt.
- After the user's approved Connect action, the secure field was not read or exposed. The UI returned exactly the safe generic message `Cursor could not be connected.`, and the Cursor session store remained absent.
- This result does not establish a product bug or prove remote verification failure: input validation, network/provider verification, ABI/runtime, and post-verification save failures converge to the same safe generic UI, and success is returned only after save.
- The Settings secure field initially accepted typed input but not `Command-V` because the programmatic accessory app did not install a native Edit/Paste command. `ApplicationMenuInstaller` now installs or repairs `NSText.paste(_:)` with a `nil` target and the Command-`V` key equivalent so AppKit routes paste through the current first responder. Repeated installation does not create app-owned duplicates, and pre-existing external menu content is not deleted.
- TDD covered the missing installer, native selector/target/key contract, normal-path idempotence, malformed Paste repair, and preservation of pre-existing same-title menu content. The focused suite passed 3 tests; specification and code-quality reviews approved the final contract and implementation.
- Fresh root verification passed: `swift test --filter ApplicationMenuInstallerTests` ran 3 tests with 0 failures; `make test` exited 0 with the pinned `tokscale-core` suite at 1372 passed, 0 failed, 1 ignored and Swift at 127 passed; the package-app relink regression passed; `make package` produced the packaged app successfully.
- A packaged-app manual smoke copied only the harmless fixture `NEEDLBAR-PASTE-SMOKE`, focused the Cursor secure field, and pressed `Command-V`. Masked input appeared. The field and clipboard were immediately cleared, and Connect was not pressed. No provider token or clipboard contents were printed, logged, persisted, or exposed.
- Hosted CI run [32996703404](https://github.com/taejunoh/needlbar/actions/runs/32996703404) passed at Cursor paste implementation head `6c6f494d1fc66c0772dbae2ea4905dc245291bc8`: Rust tests and strict lint, complete project tests, arm64 packaging, cleanup regression, packaged-app smoke, and artifact upload all completed successfully.
- Blocker/next action: the user must paste a fresh current Cursor session token obtained through the documented supported route, without whitespace or newlines, and retry Connect once. Do not broaden the flow to browser crawling, and do not record or request the token in project documentation or chat.

Release remains unreleased: no tag or GitHub Release was created, and notarization/stapling/publication were not run.

## Required Next Action

Cursor amendment Tasks 1–5 are complete, the final whole-branch review is clean, and PR #1
remains open and `MERGEABLE`. The next external gate is the notarization/release-secrets
gate. Preserve the unreleased and unmerged status; no merge, tag, or release action is
authorized here, and never request or record a Cursor session token.

## Cursor Local Usage and Dashboard Amendment — 2026-08-26

The approved amendment replaces Cursor session-token authentication, remote usage hydration,
and personal quota retrieval with local-cache usage and a fixed Spending dashboard action.
The implementation is complete through Task 4; this section records the Task 5 acceptance
state and deliberately supersedes the older Cursor records above.

### Task 1–4 implementation commits

- `ec18fcd` — retire Cursor personal quota integration.
- `ebc6175` — make Cursor usage local-cache only and add the no-read cleanup migration.
- `b6251f5` — remove forced Cursor refresh state.
- `4b38fc7` — exclude retained Cursor quota windows from headlines.
- `5c79f49` — link Cursor quota-unavailable actions to the Spending dashboard.

### Task 1–4 verification summary

- Task 1 RED: the Cursor provider returned `RequiresAuthentication` with the old session
  path; GREEN: the provider and bridge contracts returned Cursor-scoped
  `providerUnavailable` with no action, and strict quota/bridge tests passed.
- Task 2 RED: the cleanup module was absent; GREEN: local-cache usage, no-read descriptor-
  relative cleanup, ABI removal, diagnostics, redaction, workspace Clippy, and bridge
  contracts passed.
- Task 3 RED: Swift still referenced the removed forced usage export and integration still
  expected a Cursor quota window; GREEN: one normal usage path, local Cursor usage, and
  unavailable Cursor quota passed the focused Core/presentation and full project gates.
- Task 4 RED: the typed Spending action and opener seam were absent; GREEN: popover,
  Settings, routing, packaging, smoke, and full project tests passed.

### Task 5 acceptance state

- Active documentation states that Cursor usage reads only an existing compatible
  `~/.config/tokscale/cursor-cache/usage.csv`; Needlbar does not create, refresh, or claim
  freshness for it.
- Cursor quota is unavailable inside Needlbar. Settings and the Cursor popover expose one
  typed `Open Cursor Spending` action to exactly `https://cursor.com/dashboard/spending`.
- Needlbar does not use Cursor credentials, browser cookies, private endpoints, or remote
  usage hydration. The one-shot migration removes only the obsolete Needlbar-owned
  `cursor-session.json` file without reading it and preserves the local usage cache.
- Safe existence-only preflight found no obsolete session file and no local cache in the
  acceptance home (`legacy_session_exists=false`, `cursor_cache_exists=false`). No file
  contents, clipboard, cookies, browser storage, or credential material were inspected.
- Fresh `cargo clippy --workspace --all-targets --all-features -- -D warnings`, `make test`,
  `make package`, `make smoke`, and `git diff --check` exited 0. `make test` reported 1372
  pinned-core tests passed with 1 ignored, 128 Swift tests passed, and package-test passed.
- The initial Task 5 run, before `dc7e29a`, recorded the required exact `cargo fmt --check`
  exiting 1 solely on pre-existing formatting differences throughout the non-owned
  `vendor/tokscale-core` submodule. The owned packages passed
  `cargo fmt -p needlbar-bridge -p needlbar-quota -- --check`; the submodule was not changed
  or reverted.
- Packaged-app launch was confirmed. In this GUI session, the LSUIElement status item had no
  Orca-accessible window and the status-bar surface is unavailable to the computer-use
  provider, so a live Settings/popover click-through could not be completed. Structural
  Swift tests passed for Claude/Codex login rows, the Cursor local-cache explanation, the
  single Spending action, no credential controls, both routes, and the exact URL.
- Existence-only post-launch checks remained `legacy_session_exists=false` and
  `cursor_cache_exists=false`; no file contents, clipboard, cookies, browser storage, or
  credential material were inspected. The packaged process was only inspected by exact path
  and was terminated after the smoke attempt.

Task 5's fix round replaces a stale positive `connectCursor` decoding fixture with a generic
future-action unknown-value assertion, so the retired action appears only in approved
historical or redaction-negative records. The workspace formatting boundary now excludes
the vendored path dependency, so literal stable `cargo fmt --check` covers the owned
workspace and passes; tokscale-core remains a pinned transitive dependency and is explicitly
tested and linted through its manifest in Makefile/CI, with no vendor source or revision
change. The live packaged UI was then verified on display 2: Settings showed Claude and Codex rows,
the Cursor local-cache explanation, one Spending button, and no Cursor credential controls;
the Settings action and Cursor popover action each opened the exact
`https://cursor.com/dashboard/spending` URL. Evidence is retained only as the
local-only cropped/redacted `local-only/task5-settings-connections.png` and
`local-only/task5-cursor-popover.png` under the Task 5 SDD directory. Fix-round commit
`dc7e29a44b521fa417b0ca20e5036e9afc2df7e`
passed exact-head CI run [33018740992](https://github.com/taejunoh/needlbar/actions/runs/33018740992),
including owned workspace tests, explicit vendored tokscale-core test and clippy, full
Swift/package verification, and packaged-app smoke checks. The follow-up cleanup restores the
existing CI workspace test's original feature scope while retaining bridge-test runtime
coverage in Makefile and the explicit vendor checks. The live-acceptance commit
`4ec1081ae982e3b03759230ace6ccc38d7e32934` passed exact-head CI run
[33019798610](https://github.com/taejunoh/needlbar/actions/runs/33019798610), with every step
successful, including the packaged visual-acceptance build path. This status-only update
records that completed run/head; any exact-head CI generated for this status-only commit will
be recorded only in the untracked Task 5 report, not through another STATUS commit, with no
tag or release action authorized here.

The follow-up nested-worktree review fix `893309a` excludes the `.worktrees` prefix
from Cargo workspace discovery and verifies the pinned vendor through a portable
detached-worktree helper; no vendor source or revision changed.

### Final whole-branch review and closeout

The final review is clean. Fix `bed1037` makes Cursor `providerUnavailable` render as
unavailable in NeedlbarCore and the bridge, and removes the stale controller copy. Exact-head
CI run [33025188508](https://github.com/taejunoh/needlbar/actions/runs/33025188508) completed
successfully. Independent verification also passed: `cargo fmt --check`, workspace Clippy,
`make test`, `make package`, `make smoke`, and `git diff --check`; the pinned
`tokscale-core` revision remains `53f9eefffd3278fd430076531548f7b1f5861f9a`. A direct
pre-merge vendor-Clippy invocation from this nested worktree can discover the outer Cargo
workspace; fresh-checkout CI vendor Clippy passed, and the portable detached-worktree helper
preserves local verification without changing the vendor.

## Release Validation Continuation — 2026-08-27

Task 5 of tagless release validation is documented and contract-checked. The reusable
fake-tested `scripts/notarize-app.sh` and split `.github/workflows/release.yml`
validate/publish workflow are implemented. Manual dispatch is tagless and produces only an
Actions artifact; `validate` is read-only, while `publish` is write-enabled only for future
`v*` push tags. This implementation did not configure or read a protected GitHub Environment
secret. No real notarization, stapling, Gatekeeper acceptance, merge to `main`, tag, public
GitHub Release, or distribution is claimed here.

The next gate is merge to `main`, authorized protected Environment setup outside chat, then
tagless manual validation. No tag or release action is authorized here. The older credentialed
release and Cursor-session records above remain historical; the active Cursor contract is
local-cache-only and never requests or records a Cursor session token.

## Credentialed Tagless Release Validation — 2026-08-29

This section supersedes the preceding continuation point while preserving it as historical
record. Credentialed tagless release validation is complete against remote `main` head
`eec51a57f9acd23ab238f1d02d546e2e6d568966` (merge commit `eec51a5`, PR #2).

- GitHub Actions Release run [33272883313](https://github.com/taejunoh/needlbar/actions/runs/33272883313)
  was dispatched with `workflow_dispatch` on `main`; it completed successfully, created at
  `2026-08-29T20:12:49Z`, and updated at `2026-08-29T20:24:01Z`.
- The `validate` job succeeded through Swift 6 toolchain selection, complete project
  verification, arm64 packaging, packaged-app smoke, Developer ID signing, Apple
  notarization, stapling, validation/Gatekeeper checks, and artifact upload. The `publish`
  job was skipped as required for tagless dispatch.
- At post-run API verification, artifact `Needlbar-macos-arm64-notarized` was present at
  5,180,723 bytes, was not expired, and was set to expire `2026-11-27T20:12:50Z`. API
  verification after the run reported zero GitHub releases and zero tags.
- Protected GitHub Environment `release` was configured with the six required secret names
  (`DEVELOPER_ID_APPLICATION`, `DEVELOPER_ID_APPLICATION_CERTIFICATE`,
  `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, and
  `APPLE_APP_SPECIFIC_PASSWORD`), without recording values. Required reviewer is `taejunoh`;
  `prevent_self_review` is false, admin bypass is disabled, and deployment policies are
  `main` and `v*`.
- The temporary exported local P12 was deleted after secret setup; the macOS Keychain source
  certificate was retained. No password, certificate bytes, Apple ID, or secret value is
  recorded. No Cursor credential was requested, inspected, or recorded.
- Before this documentation edit, the isolated-worktree baseline
  `source /Users/taejunoh/.cargo/env && cargo build && make test` exited 0: Needlbar Rust
  suites passed, pinned `tokscale-core` reported 1372 passed/0 failed/1 ignored, Swift
  reported 129 passed, and the package relink regression and notarize shell contracts passed.

No tag or public GitHub Release was created. Await explicit user authorization for any
version tag/public GitHub Release; until then do not create/push a tag or publish a release.

## v0.1 Constraints to Preserve

- macOS 14+.
- Apple Silicon first.
- Exactly Claude Code, Codex, and Cursor.
- Swift/AppKit owns the shell and presentation.
- `NeedlbarCore` owns normalized state, refresh scheduling, and last-known-good behavior.
- `tokscale-core` owns usage discovery/parsing/deduplication/aggregation/pricing.
- Cursor usage has no Needlbar-owned hydration layer; the pinned engine reads an existing
  local compatible cache only.
- `needlbar-quota` owns quota/auth/reset logic only.
- Usage and quota failures must not erase each other's valid last-known-good values.
- No backend/account system/telemetry or prompt/response/source-code upload.
- No extra v0.1 providers or opportunistic feature expansion.

## Status Update Rule

Whenever work moves forward, update this file with:

- completed task/step,
- verification commands and result,
- current CI state,
- any deliberate deviation from the approved plan,
- exact next continuation point.
