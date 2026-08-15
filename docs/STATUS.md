# Needlbar Development Status

**Updated:** 2026-08-14
**Branch:** `main`
**Current phase:** Task 15 packaging and final v0.1 implementation gate complete
**Next action:** Perform credentialed/manual release acceptance, then create a user-authorized v0.1 tag/release

## Source of Truth

The v0.1 work is governed by:

- `docs/superpowers/specs/2026-08-13-needlbar-v0.1-design.md` — approved architecture and product scope.
- `docs/superpowers/plans/2026-08-13-needlbar-v0.1.md` — ordered implementation plan.
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
- Developer ID signing, notarization, stapling, and publication were not run because the required secrets were not provided; the release workflow refuses to publish an ad-hoc stable artifact when they are absent.
- Live real-account Claude, Codex, or Cursor credential smoke and interactive menu-item/Settings click-through were not performed in the noninteractive session. These remain credentialed/manual release follow-ups, not silently accepted criteria.

## Final v0.1 Continuation

The implementation plan and hosted CI/artifact verification are complete. The only remaining work is credentialed/manual release acceptance on a supported macOS 14 arm64 machine, followed by a user-authorized v0.1 tag/release; this is not a Task 16 implementation task.

## Required Next Action

Perform credentialed/manual release acceptance, then create a user-authorized v0.1 tag/release. Do not begin a Task 16 implementation.

## v0.1 Constraints to Preserve

- macOS 14+.
- Apple Silicon first.
- Exactly Claude Code, Codex, and Cursor.
- Swift/AppKit owns the shell and presentation.
- `NeedlbarCore` owns normalized state, refresh scheduling, and last-known-good behavior.
- `tokscale-core` owns usage discovery/parsing/deduplication/aggregation/pricing.
- `needlbar-source-sync` hydrates Cursor usage data only.
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
