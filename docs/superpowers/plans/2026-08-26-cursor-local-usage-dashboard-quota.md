# Cursor Local Usage and Dashboard Quota Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove Needlbar's unsupported Cursor session-token, remote hydration, and personal quota paths while preserving existing local-cache usage and adding a fixed Cursor Spending dashboard action.

**Architecture:** Rust keeps Cursor as a normalized provider but performs only local `tokscale-core` aggregation and returns a stable I/O-free quota-unavailable result. Swift removes forced Cursor refresh and token connection state, then owns a closed typed action that opens only the provider Spending URL. A one-shot bridge-private migration deletes only Needlbar's obsolete session file without reading it.

**Tech Stack:** Swift 6, SwiftUI, AppKit/`NSWorkspace`, Rust 2021, C ABI, `tokscale-core`, Swift Testing, Cargo tests.

**Spec:** `docs/superpowers/specs/2026-08-26-cursor-local-usage-dashboard-quota-design.md`

## Global Constraints

- macOS 14+ and Apple Silicon remain the v0.1 platform baseline.
- Supported providers remain exactly Claude Code, Codex, and Cursor.
- Do not change the pinned `tokscale-core` revision.
- Do not add a Cursor parser or read Cursor.app/browser credentials.
- Do not call Cursor authentication, usage-export, or personal-quota endpoints.
- Cursor usage may come only from an already-existing `~/.config/tokscale/cursor-cache/usage.csv` discovered by `tokscale-core`.
- Cursor quota must be provider-scoped `providerUnavailable` with no authentication action.
- The only Cursor external action opens `https://cursor.com/dashboard/spending` after an explicit click.
- Delete only Needlbar's obsolete `~/Library/Application Support/Needlbar/cursor-session.json`; never read its bytes and never delete the local usage cache.
- Usage and quota remain independently refreshable and independently fallible.
- Claude and Codex browser-login, Keychain, quota, and local usage behavior remain unchanged.
- Follow strict test-first RED → GREEN cycles and run `make test` before completion.

---

### Task 1: Replace Cursor Quota with an I/O-Free Unavailable Provider

**Files:**

- Modify: `crates/needlbar-quota/src/providers/cursor.rs`
- Modify: `crates/needlbar-quota/src/domain.rs`
- Modify: `crates/needlbar-quota/src/lib.rs`
- Modify: `crates/needlbar-quota/Cargo.toml`
- Modify: `crates/needlbar-quota/tests/cursor.rs`
- Delete: `Fixtures/quota/cursor/usage-summary-success.json`
- Delete: `Fixtures/quota/cursor/usage-summary-invalid.json`
- Modify: `crates/needlbar-bridge/src/quota.rs`
- Modify: `crates/needlbar-bridge/src/test_runtime.rs`
- Modify: `crates/needlbar-bridge/tests/quota_contract.rs`
- Modify: `crates/needlbar-bridge/tests/redaction_contract.rs`

**Interfaces:**

- Consumes: `ProviderId::Cursor`, `QuotaErrorCode::ProviderUnavailable`, and `QuotaProvider`.
- Produces: zero-sized `CursorQuotaProvider::new()` whose `fetch()` always returns a Cursor-scoped unavailable error with `action: None`.
- Removes: `CursorQuotaSource`, `QuotaAction`, `connectCursor`, Cursor session-store access, HTTP transport, response parsing, and Cursor quota fixtures.

- [ ] **Step 1: Write the failing Cursor provider test**

Replace the session/HTTP tests in `crates/needlbar-quota/tests/cursor.rs` with:

```rust
use needlbar_quota::{CursorQuotaProvider, ProviderId, QuotaErrorCode, QuotaProvider};

#[tokio::test]
async fn cursor_quota_is_unavailable_without_authentication_or_io() {
    let error = CursorQuotaProvider::new()
        .fetch()
        .await
        .expect_err("Cursor personal quota has no supported integration");
    assert_eq!(error.provider, Some(ProviderId::Cursor));
    assert_eq!(error.code, QuotaErrorCode::ProviderUnavailable);
    assert!(error.action.is_none());
}
```

This test catches any resumption of Cursor quota snapshots, authentication actions, or non-Cursor errors.

- [ ] **Step 2: Run the provider test and verify RED**

Run `cargo test -p needlbar-quota --test cursor`.

Expected: FAIL because the current provider reads a missing session and returns `RequiresAuthentication` with `ConnectCursor`.

- [ ] **Step 3: Add failing bridge-envelope assertions**

In `quota_contract.rs` and `redaction_contract.rs`, make the Cursor fixture result:

```rust
Err(QuotaError {
    provider: Some(ProviderId::Cursor),
    code: QuotaErrorCode::ProviderUnavailable,
    message: "Cursor personal quota is unavailable.",
    retry_after: None,
    action: None,
})
```

Assert `errors[2]` has provider `cursor`, code `providerUnavailable`, and no `action` field. Preserve deterministic provider order and all credential-canary assertions.

- [ ] **Step 4: Run bridge tests and verify RED**

```bash
cargo test -p needlbar-bridge --test quota_contract
cargo test -p needlbar-bridge --test redaction_contract --features bridge-test-runtime
```

Expected: FAIL because `connectCursor` still serializes.

- [ ] **Step 5: Implement the minimal provider**

Replace `providers/cursor.rs` with:

```rust
use async_trait::async_trait;
use crate::{ProviderId, ProviderQuotaSnapshot, QuotaError, QuotaErrorCode, QuotaProvider};

pub struct CursorQuotaProvider;

impl CursorQuotaProvider {
    pub fn new() -> Self { Self }
}

impl Default for CursorQuotaProvider {
    fn default() -> Self { Self::new() }
}

#[async_trait]
impl QuotaProvider for CursorQuotaProvider {
    async fn fetch(&self) -> Result<ProviderQuotaSnapshot, QuotaError> {
        Err(QuotaError::new(
            Some(ProviderId::Cursor),
            QuotaErrorCode::ProviderUnavailable,
            "Cursor personal quota is available in Cursor Spending.",
        ))
    }
}
```

Remove `QuotaAction`, `.with_action(...)`, its exports, and `action_name`. Remove the quota crate's source-sync dependency. Update `test_runtime.rs` to use Cursor `ProviderUnavailable` with `action: None`, while retaining Cursor provider-construction counting.

- [ ] **Step 6: Remove obsolete Cursor quota fixtures**

Delete only the two JSON fixtures under `Fixtures/quota/cursor`. Regenerate `Cargo.lock` through Cargo; do not edit it by hand.

- [ ] **Step 7: Verify GREEN and commit**

```bash
cargo fmt -p needlbar-quota -p needlbar-bridge -- --check
cargo test -p needlbar-quota
cargo test -p needlbar-bridge --test quota_contract
cargo test -p needlbar-bridge --test redaction_contract --features bridge-test-runtime
cargo clippy -p needlbar-quota -p needlbar-bridge --all-targets --all-features -- -D warnings
git add crates/needlbar-quota crates/needlbar-bridge/src/quota.rs crates/needlbar-bridge/src/test_runtime.rs crates/needlbar-bridge/tests/quota_contract.rs crates/needlbar-bridge/tests/redaction_contract.rs Fixtures/quota/cursor Cargo.lock
git commit -m "refactor: retire Cursor personal quota integration"
```

Expected: every verification command exits 0 before the commit.

---

### Task 2: Retire Remote Hydration and Session ABI

**Files:**

- Modify: `Cargo.toml`
- Modify: `Cargo.lock`
- Modify: `crates/needlbar-bridge/Cargo.toml`
- Modify: `crates/needlbar-bridge/src/lib.rs`
- Modify: `crates/needlbar-bridge/src/usage.rs`
- Create: `crates/needlbar-bridge/src/cursor_credential_cleanup.rs`
- Modify: `crates/needlbar-bridge/src/diagnostics.rs`
- Modify: `crates/needlbar-bridge/tests/cursor_usage_contract.rs`
- Create: `crates/needlbar-bridge/tests/cursor_credential_cleanup_contract.rs`
- Modify: `crates/needlbar-bridge/tests/ffi_contract.rs`
- Modify: `crates/needlbar-bridge/tests/redaction_contract.rs`
- Delete: `crates/needlbar-bridge/tests/cursor_import_contract.rs`
- Delete: `crates/needlbar-source-sync/`
- Modify: `Sources/CNeedlbar/include/needlbar.h`

**Interfaces:**

- Consumes: `tokscale_core::generate_local_graph_report` and its existing Cursor cache discovery.
- Produces: only `needlbar_usage_snapshot_json` for local aggregation.
- Produces: bridge-private `schedule_obsolete_cursor_session_cleanup()` plus testable `cleanup_obsolete_cursor_session_in_home(home: &Path)`.
- Removes: source-sync workspace member, remote transport, session save/load, forced usage, Cursor import, and Cursor clear exports.

- [ ] **Step 1: Protect local-cache behavior and missing-cache behavior**

Keep the existing fixture-copy test in `cursor_usage_contract.rs`. Add:

```rust
#[test]
fn absent_local_cursor_cache_does_not_invent_cursor_usage() {
    let home = tempfile::tempdir().expect("temporary home");
    let snapshots = needlbar_bridge::usage::collect_usage_from_home(home.path())
        .expect("local report");
    assert!(!snapshots.iter().any(|snapshot| snapshot.provider == "cursor"));
}
```

- [ ] **Step 2: Write failing cleanup contracts**

Create `cursor_credential_cleanup_contract.rs` with four tests:

1. A regular synthetic session file is removed without returning its canary.
2. Repeated cleanup succeeds and does not create absent parent directories.
3. A symlink session leaf is rejected/preserved and its target bytes remain unchanged.
4. `~/.config/tokscale/cursor-cache/usage.csv` remains after session cleanup.

The tests may inspect only their synthetic fixtures. Production cleanup must never return file contents.

- [ ] **Step 3: Verify RED**

```bash
cargo test -p needlbar-bridge --test cursor_usage_contract
cargo test -p needlbar-bridge --test cursor_credential_cleanup_contract
```

Expected: the existing local-cache test remains GREEN and the cleanup test fails to compile because the module is absent. Record both outcomes.

- [ ] **Step 4: Remove source sync from usage collection**

Remove `sync_cursor_cache`, `UsageCollection`, `collect_usage_with_cursor_sync*`, sync helpers, and `cursorSyncFailed`. Keep:

```rust
pub fn collect_usage() -> Result<Vec<UsageProviderSnapshot>, BridgeError> {
    collect_usage_for_home(None, true)
}
```

Use a single `usage_envelope()` that calls `usage::collect_usage()`. Remove `needlbar_forced_usage_snapshot_json`.

- [ ] **Step 5: Implement no-read, no-follow credential cleanup**

Add `libc = "0.2"` to the bridge. Traverse only existing `Library/Application Support/Needlbar` parents using descriptor-relative `openat` with `O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC`. Before `unlinkat`, use `fstatat(..., AT_SYMLINK_NOFOLLOW)` and require a regular `cursor-session.json`. Treat `ENOENT` as success without creating directories. Reject symlink/non-directory parents and symlink/non-regular leaves. Never call `read`, `read_to_string`, or deserialize.

Use this one-shot production entry point:

```rust
static CLEANUP_ONCE: std::sync::Once = std::sync::Once::new();

pub fn schedule_obsolete_cursor_session_cleanup() {
    CLEANUP_ONCE.call_once(|| {
        let _ = std::thread::Builder::new()
            .name("needlbar-cursor-credential-cleanup".to_owned())
            .spawn(|| {
                if let Some(home) = std::env::var_os("HOME") {
                    let _ = cleanup_obsolete_cursor_session_in_home(Path::new(&home));
                }
            });
    });
}
```

Schedule it at each public snapshot entry; `Once` makes this non-blocking and idempotent. Expose no cleanup result in JSON or diagnostics.

- [ ] **Step 6: Remove session/source-sync contracts**

Delete Cursor import/disconnect payloads, pointer parsing, verifier thread, test runtime, and associated unit/integration tests. Remove these declarations from `needlbar.h`:

```c
needlbar_forced_usage_snapshot_json
needlbar_cursor_import_session_json
needlbar_cursor_clear_session_json
```

Remove source-sync from the root workspace and bridge dependency, delete its directory, and regenerate `Cargo.lock`.

- [ ] **Step 7: Update diagnostics and FFI tests**

Set Cursor to `UsageSource::Local` and new `QuotaSource::Unavailable`. Remove `CursorExport`, `Session`, and `CursorSyncFailed`. Exercise/free only remaining exports in `ffi_contract.rs`. Keep redaction canaries and assert output contains neither `connectCursor` nor `cursorSyncFailed`.

- [ ] **Step 8: Verify GREEN and commit**

```bash
cargo fmt -p needlbar-bridge -- --check
cargo test -p needlbar-bridge --test cursor_usage_contract
cargo test -p needlbar-bridge --test cursor_credential_cleanup_contract
cargo test -p needlbar-bridge --test ffi_contract
cargo test -p needlbar-bridge --test redaction_contract --features bridge-test-runtime
cargo test --workspace --all-features
cargo clippy --workspace --all-targets --all-features -- -D warnings
git add Cargo.toml Cargo.lock crates/needlbar-bridge crates/needlbar-source-sync Sources/CNeedlbar/include/needlbar.h
git commit -m "refactor: make Cursor usage local-cache only"
```

Expected: every verification command exits 0 before the commit.

---

### Task 3: Simplify NeedlbarCore to One Usage Refresh Path

**Files:**

- Modify: `Sources/NeedlbarCore/Bridge/RustBridge.swift`
- Modify: `Sources/NeedlbarCore/Bridge/BridgeEnvelope.swift`
- Modify: `Sources/NeedlbarCore/Repositories/UsageRepository.swift`
- Modify: `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`
- Modify: `Sources/NeedlbarCore/Diagnostics/DiagnosticsSnapshot.swift`
- Modify: `Tests/NeedlbarCoreTests/BridgeDecodingTests.swift`
- Modify: `Tests/NeedlbarCoreTests/BridgeIntegrationSmokeTests.swift`
- Modify: `Tests/NeedlbarCoreTests/DiagnosticsTests.swift`
- Modify: `Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift`
- Modify: `Tests/NeedlbarCoreTests/HeadlineQuotaSelectorTests.swift`

**Interfaces:**

- Produces: `UsageRepository.refresh()` and `RustBridge.usageEnvelope()` without force parameters.
- Removes: `BridgeAction.connectCursor`, forced usage-call injection, and forced-cycle queue state.
- Preserves: quota intent/coalescing and local usage/last-known-good behavior.

- [ ] **Step 1: Replace forced-cycle tests**

Update fake usage repositories to count plain `refresh()` calls. Assert `manualRefresh()` arriving during an in-flight usage cycle does not create a special forced cycle; it may join the current cycle or use the already-queued normal follow-up. Preserve stop/generation assertions.

- [ ] **Step 2: Add failing bridge/diagnostic expectations**

Remove `forcedUsageCall` from test bridge construction and `connectCursor` action decoding. Decode Cursor diagnostics as:

```json
{
  "provider": "cursor",
  "usageStatus": "available",
  "quotaStatus": "unavailable",
  "usageSource": "local",
  "quotaSource": "unavailable",
  "lastUsageAt": null,
  "lastQuotaAt": null,
  "quotaErrorCode": "providerUnavailable"
}
```

- [ ] **Step 3: Verify RED**

```bash
swift test --filter RefreshCoordinatorTests
swift test --filter BridgeDecodingTests
swift test --filter DiagnosticsTests
```

Expected: compile/assertion failures because forced-refresh and old diagnostics types remain.

- [ ] **Step 4: Remove forced bridge/repository API**

Implement:

```swift
public func usageEnvelope() throws -> BridgeEnvelope<BridgeUsagePayload> {
    try decodeCString(usageCall, decode: decoder.decodeUsageEnvelope)
}

public protocol UsageRepository: Sendable {
    func refresh() throws -> UsageRefreshResult
}
```

`RustUsageRepository.refresh()` calls this single envelope path.

- [ ] **Step 5: Simplify coordinator state**

Remove `forceCursorSyncRequestedWhileInFlight`, `usageTaskIsForced`, force parameters, and force branches. `beginUsageRefresh()` always calls `repository.refresh()`. `finishUsageRefresh` queues one normal follow-up only when requested for the current generation. `manualRefresh()` joins/requests normal usage plus quota work while leaving quota intents unchanged.

- [ ] **Step 6: Update Swift models and integration fixtures**

Remove `.connectCursor`, `.cursorExport`, `.session`, and `.cursorSyncFailed`; add `QuotaDiagnosticsSource.unavailable`. Make integration fixtures allow Cursor local usage alongside provider-unavailable Cursor quota. Remove Cursor quota windows from headline-selection expectations while keeping Claude/Codex eligibility.

- [ ] **Step 7: Verify GREEN and commit**

```bash
swift test --filter RefreshCoordinatorTests
swift test --filter BridgeDecodingTests
swift test --filter BridgeIntegrationSmokeTests
swift test --filter DiagnosticsTests
swift test --filter HeadlineQuotaSelectorTests
git add Sources/NeedlbarCore Tests/NeedlbarCoreTests
git commit -m "refactor: remove forced Cursor refresh state"
```

Expected: every test command exits 0 before the commit.

---

### Task 4: Replace Cursor Connection UI with a Typed Spending Action

**Files:**

- Create: `Sources/Needlbar/Cursor/CursorSpendingAction.swift`
- Modify: `Sources/Needlbar/Settings/SettingsView.swift`
- Modify: `Sources/Needlbar/Settings/SettingsWindowController.swift`
- Modify: `Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift`
- Modify: `Sources/Needlbar/MenuBar/MenuBarController.swift`
- Modify: `Sources/Needlbar/App/AppDelegate.swift`
- Modify: `Tests/NeedlbarTests/PopoverPresentationTests.swift`
- Modify: `Tests/NeedlbarTests/MenuBarControllerTests.swift`
- Modify: `Tests/NeedlbarTests/AppDelegateLifecycleTests.swift`

**Interfaces:**

- Produces: closed `CursorSpendingAction` and `ProviderAuthenticationAction.openCursorSpending(title:)`.
- Removes: token state, `CursorSessionConnectionController`, `CursorSessionBridge`, and connection UI/tests.
- Preserves: Claude/Codex `.browserLogin`.

- [ ] **Step 1: Write failing presentation test**

```swift
#expect(ProviderPopoverPresentation(snapshot: snapshot(
    provider: .cursor,
    usage: usage(totalTokens: 900),
    quota: nil,
    usageStatus: .fresh,
    quotaStatus: .unavailable
)).authenticationAction == .openCursorSpending(title: "Open Cursor Spending"))
```

Keep Claude/Codex authentication-required assertions. Remove suspended importer/clearer tests only after this new RED test exists.

- [ ] **Step 2: Write failing routing test**

Inject an opener in `MenuBarControllerTests.swift` and assert Cursor opens exactly once with:

```swift
URL(string: "https://cursor.com/dashboard/spending")!
```

Also assert no provider-login or Settings callback occurs.

- [ ] **Step 3: Verify RED**

```bash
swift test --filter PopoverPresentationTests
swift test --filter MenuBarControllerTests
```

Expected: compile failures because the Spending action does not exist and Cursor routes to Settings.

- [ ] **Step 4: Implement the fixed action**

Create:

```swift
import AppKit
import Foundation

enum CursorSpendingAction {
    static let dashboardURL = URL(string: "https://cursor.com/dashboard/spending")!

    static func open(using opener: (URL) -> Bool = NSWorkspace.shared.open) -> Bool {
        opener(dashboardURL)
    }
}
```

Inject the opener at the controller/app boundary. UI requests the typed action and cannot provide an arbitrary URL string.

- [ ] **Step 5: Replace Settings controls**

Remove every Cursor session property/controller/bridge/control. Add:

```swift
HStack {
    VStack(alignment: .leading, spacing: 2) {
        Text("Cursor")
        Text("Usage is read from an existing local cache. Quota is available in Cursor Spending.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    Spacer()
    Button("Open Cursor Spending", action: openCursorSpending)
}
```

Thread the same action through `SettingsWindowController`, `MenuBarController`, and `AppDelegate`.

- [ ] **Step 6: Update popover policy**

Add `.openCursorSpending(title:)`. Cursor selects it when quota has no windows and is not fresh, independent of `requiresAuthentication`. Claude/Codex remain authentication-gated. Route the new case to the fixed action and remove `.openSettings` if unused.

- [ ] **Step 7: Verify GREEN, package, and commit**

```bash
swift test --filter PopoverPresentationTests
swift test --filter MenuBarControllerTests
swift test --filter AppDelegateLifecycleTests
make package
make smoke
git add Sources/Needlbar Tests/NeedlbarTests
git commit -m "feat: link Cursor quota to Spending dashboard"
```

Expected: every command exits 0 before the commit.

---

### Task 5: Documentation, Status, Full Acceptance, and Push

**Files:**

- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/privacy.md`
- Modify: `docs/providers/cursor.md`
- Modify: `docs/STATUS.md`
- Modify: `docs/superpowers/specs/2026-08-25-provider-managed-browser-login-design.md`
- Modify: `docs/superpowers/plans/2026-08-25-provider-managed-browser-login.md`
- Modify: `docs/superpowers/specs/2026-08-26-cursor-paste-command-design.md`
- Modify: `docs/superpowers/plans/2026-08-26-cursor-paste-command.md`

**Interfaces:**

- Consumes: verified Task 1-4 behavior and commit IDs.
- Produces: active docs with no token/cookie/private-endpoint instructions and an exact continuation point.

- [ ] **Step 1: Mark historical Cursor requirements superseded**

Add a prominent note to the prior browser-login and Cursor-paste specs/plans pointing to the approved 2026-08-26 amendment. Preserve historical task records while making their Cursor session requirements inactive.

- [ ] **Step 2: Update active documentation**

State that Cursor usage reads only an existing local compatible cache, Needlbar does not create/refresh it, quota opens the Spending dashboard, no Cursor credential/private endpoint is used, and the migration deletes only Needlbar's obsolete session file while preserving usage cache. Remove live Connect/Reconnect/Disconnect and token-extraction instructions.

- [ ] **Step 3: Update `docs/STATUS.md`**

Record Task 1-4 commits, RED/GREEN evidence, complete verification, packaging/UI acceptance, and the next continuation point. Record only whether an obsolete file existed and whether it was removed; never record contents or credential-derived metadata.

- [ ] **Step 4: Scan active sources and docs**

```bash
rg -n "WorkosCursorSessionToken|api/usage-summary|export-usage-events-csv|Cursor session token|Connect/Reconnect/Disconnect|connectCursor" README.md docs Sources crates Tests
```

Expected: matches appear only in explicitly superseded history or the approved amendment's removed-contract list; no active instruction or production source match remains.

- [ ] **Step 5: Run complete fresh verification**

```bash
cargo fmt --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
make test
make package
make smoke
git diff --check
```

Expected: every command exits 0. Read and record the full output before claiming completion.

- [ ] **Step 6: Perform packaged-app visual acceptance**

Launch the packaged app and verify:

1. Claude and Codex login rows remain.
2. Cursor shows the local-cache explanation and one Spending button.
3. No Cursor credential or connection control is visible.
4. Settings and the Cursor popover open the exact Spending dashboard.
5. No browser cookie, clipboard, or credential file is inspected.

- [ ] **Step 7: Commit, push, and verify exact-head CI**

```bash
git add README.md docs
git commit -m "docs: finalize Cursor local-only behavior"
git push
```

Wait for the exact-head GitHub Actions run and require every job to pass. Record the run URL/head in `docs/STATUS.md`; if that creates a new commit, push it and verify the replacement exact-head run before reporting completion.
