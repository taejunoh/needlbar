# Provider-Managed Browser Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add explicit provider-managed browser login for Claude and Codex, including user-approved Claude Keychain quota verification, while preserving Cursor's validated session-token connection and Needlbar's local-first privacy boundary.

**Architecture:** AppKit launches fixed provider CLI commands and owns child-process lifecycle. `NeedlbarCore` distinguishes ordinary quota refresh from a user-initiated post-authentication refresh. Rust keeps the raw Claude credential inside `needlbar-quota`, using interaction-forbidden Keychain access in the background and a dedicated Claude-only C export that may permit Keychain UI only after the explicit user action.

**Tech Stack:** Swift 6, AppKit, SwiftUI, Combine `ObservableObject`, Foundation `Process`, Rust 2021, macOS Security.framework, JSON-over-C ABI, Swift Testing, Cargo tests

**Spec:** `docs/superpowers/specs/2026-08-25-provider-managed-browser-login-design.md`

## Global Constraints

- Deployment target remains macOS 14+ and Apple Silicon first.
- Supported providers remain exactly Claude Code, Codex, and Cursor.
- Claude login command is exactly `claude auth login --claudeai`; Codex login command is exactly `codex login`.
- Cursor retains the existing explicit session-token Connect/Reconnect/Disconnect flow.
- Provider CLIs own browser navigation, OAuth callbacks, refresh, and credential storage.
- Login and Keychain UI begin only from an explicit user action; background refresh never displays authentication UI.
- Background Claude Keychain access uses interaction-forbidden Security.framework options.
- User-initiated Claude verification queries only the exact `Claude Code-credentials` generic-password service; no Keychain enumeration, account guessing, `security` subprocess, or browser crawling.
- Raw Claude credentials remain in a redacting/zeroizing Rust secret type and never cross the C ABI or enter Swift, diagnostics, logs, preferences, or bridge errors. Real credentials never enter tests; synthetic canaries are permitted only to prove containment and redaction.
- Never invoke a shell, interpolate user input into a command, or retain provider child stdout/stderr.
- Usage and quota remain independently refreshable and independently fallible; failed verification preserves last-known-good quota.
- Work one numbered task at a time, use tests first, run narrow tests while developing, and run `make test` before completion.
- Do not tag, release, notarize, or perform a real provider login without separate user-authorized acceptance.

---

### Task 1: Add Claude Credential Access Modes and the macOS Keychain Resolver

**Files:**
- Modify: `Cargo.toml`
- Modify: `crates/needlbar-quota/Cargo.toml`
- Modify: `crates/needlbar-quota/src/domain.rs`
- Modify: `crates/needlbar-quota/src/lib.rs`
- Create: `crates/needlbar-quota/src/providers/claude_credentials.rs`
- Modify: `crates/needlbar-quota/src/providers/claude.rs`
- Modify: `crates/needlbar-quota/src/providers/codex.rs`
- Modify: `crates/needlbar-quota/src/providers/mod.rs`
- Modify: `crates/needlbar-quota/tests/claude.rs`

**Interfaces:**
- Produces `ClaudeCredentialAccess::{BackgroundNoUI, UserInitiatedAllowUI}`.
- Produces `ClaudeCredentialResolver::resolve(access) -> Result<ClaudeOAuthSecret, ClaudeCredentialError>`.
- Produces `ClaudeQuotaProvider::fetch_with_credential_access(access)`; the existing `QuotaProvider::fetch()` is fixed to `BackgroundNoUI`.
- Adds `QuotaErrorCode::PermissionDenied` with provider-safe static copy.
- Keeps the existing file credential parser for non-macOS and legacy fixtures.

- [ ] **Step 1: Add failing resolver/access-policy tests**

Add fakes that record the access mode and return a credential canary without printing it:

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClaudeCredentialAccess {
    BackgroundNoUI,
    UserInitiatedAllowUI,
}

pub trait ClaudeCredentialResolver: Send + Sync {
    fn resolve(
        &self,
        access: ClaudeCredentialAccess,
    ) -> Result<ClaudeOAuthSecret, ClaudeCredentialError>;
}
```

Tests must prove:

- `QuotaProvider::fetch()` requests `BackgroundNoUI` only.
- `fetch_with_credential_access(UserInitiatedAllowUI)` forwards that exact mode.
- item-not-found maps to `RequiresAuthentication`.
- interaction-forbidden, locked Keychain, and user cancellation map to `PermissionDenied`.
- expired OAuth maps to `AuthenticationExpired`.
- malformed Keychain JSON maps to `SchemaChanged`.
- the literal `CLAUDE-KEYCHAIN-CANARY` is absent from `Debug`, every `QuotaError`, and serialized safe errors.
- valid legacy file fixtures still parse on the injected file resolver.

- [ ] **Step 2: Run the Claude suite and verify RED**

```bash
cargo test -p needlbar-quota --test claude
```

Expected: compilation fails because the access enum, resolver, secret wrapper, and permission error do not exist.

- [ ] **Step 3: Add direct macOS security dependencies and secret zeroization**

Declare workspace dependencies and use target-specific quota dependencies:

```toml
[workspace.dependencies]
security-framework = "3.7.0"
security-framework-sys = "2.17.0"
zeroize = "1.8"

[target.'cfg(target_os = "macos")'.dependencies]
security-framework.workspace = true
security-framework-sys.workspace = true

[dependencies]
zeroize.workspace = true
```

Do not rely on the current transitive TLS copy of `security-framework`; the quota crate must declare the API it uses.

- [ ] **Step 4: Implement the secret and resolver domain**

Define a non-`Debug`, non-`Serialize`, non-`Clone` wrapper:

```rust
pub struct ClaudeOAuthSecret {
    access_token: zeroize::Zeroizing<String>,
    expires_at: Option<chrono::DateTime<chrono::Utc>>,
}
```

Expose only crate-private accessors required to attach the bearer header. Implement `ClaudeCredentialError` as a closed enum without source strings, payloads, paths, account names, or tokens:

```rust
pub enum ClaudeCredentialError {
    NotFound,
    InteractionNotAllowed,
    PermissionDenied,
    Cancelled,
    Expired,
    Malformed,
}
```

Add `QuotaErrorCode::PermissionDenied` and map each credential error to a static provider-safe `QuotaError`. Update every exhaustive `QuotaErrorCode` match in `needlbar-quota`, including Codex's safe-message helper, with a static `PermissionDenied` branch even though Codex does not currently emit it.

Wrap the Security.framework result immediately in `Zeroizing<Vec<u8>>`. Deserialize through a typed projection that declares only `claudeAiOauth.accessToken` and the expiry fields, so an ignored `refreshToken` is never materialized. Move the parsed access-token `String` exactly once into `Zeroizing<String>` and promptly drop parser intermediates. The zeroization guarantee applies to buffers owned by Needlbar; HTTP-client request internals must be dropped promptly but are not claimed to be zeroized.

- [ ] **Step 5: Implement the exact macOS Keychain query**

In `claude_credentials.rs`, build a Security.framework query with:

- class `kSecClassGenericPassword`,
- service exactly `Claude Code-credentials`,
- match limit sufficient to reject zero or multiple exact-service matches,
- return data enabled,
- authentication UI set to fail for `BackgroundNoUI`,
- authentication UI allowed for `UserInitiatedAllowUI`.

Do not add account/email predicates unless the provider contract is verified and documented. Reject multiple matches rather than selecting heuristically. Do not invoke `/usr/bin/security` and do not enumerate unrelated Keychain items.

Parse only the expected `claudeAiOauth.accessToken` and expiry fields into `ClaudeOAuthSecret`. On macOS, the exact-service Keychain resolver is primary; item absence may fall back to the existing legacy file resolver, while denied/locked/malformed Keychain results fail closed. On non-macOS, compile only the file resolver.

Use synthetic canaries to cover the Keychain payload buffer, typed parser, HTTP request seam, `Debug`, safe errors, and bridge serialization. Assert `CLAUDE-KEYCHAIN-CANARY` is absent from every observable surface after both success and failure paths.

- [ ] **Step 6: Refactor `ClaudeQuotaProvider` around injected credentials**

Store `Arc<dyn ClaudeCredentialResolver>` in the provider. Keep `new()` for production and extend the existing test constructor with an injected resolver constructor. Implement:

```rust
pub async fn fetch_with_credential_access(
    &self,
    access: ClaudeCredentialAccess,
) -> Result<ProviderQuotaSnapshot, QuotaError>;

#[async_trait]
impl QuotaProvider for ClaudeQuotaProvider {
    async fn fetch(&self) -> Result<ProviderQuotaSnapshot, QuotaError> {
        self.fetch_with_credential_access(ClaudeCredentialAccess::BackgroundNoUI).await
    }
}
```

The HTTP layer receives a borrowed secret token, never a formatted error or cloned diagnostic value.

- [ ] **Step 7: Run formatting, tests, and lint**

```bash
cargo fmt -p needlbar-quota -- --check
cargo test -p needlbar-quota --test claude
cargo test -p needlbar-quota
cargo clippy -p needlbar-quota --all-targets -- -D warnings
```

Expected: all Claude access-mode, error mapping, canary-redaction, legacy-file, parser, and HTTP tests pass; Clippy is clean; no real Keychain UI appears.

- [ ] **Step 8: Commit the credential boundary**

```bash
git add Cargo.toml Cargo.lock crates/needlbar-quota
git commit -m "feat: add prompt-safe Claude credential resolution"
```

---

### Task 2: Expose Dedicated Provider Verification ABIs

**Files:**
- Modify: `Sources/CNeedlbar/include/needlbar.h`
- Modify: `crates/needlbar-bridge/src/quota.rs`
- Modify: `crates/needlbar-bridge/src/lib.rs`
- Modify: `crates/needlbar-bridge/tests/ffi_contract.rs`
- Modify: `crates/needlbar-bridge/tests/quota_contract.rs`
- Modify: `crates/needlbar-bridge/tests/redaction_contract.rs`

**Interfaces:**
- Produces `const char *needlbar_claude_user_initiated_quota_snapshot_json(void)`.
- Produces `const char *needlbar_codex_quota_snapshot_json(void)`.
- Returns the existing `needlbar.v1` envelope with only the requested provider's data/errors.
- Guarantees `UserInitiatedAllowUI` for the Claude export and `BackgroundNoUI` for `needlbar_quota_snapshot_json()`.
- Preserves Rust-owned string allocation/free, null-safe free, and panic containment.

- [ ] **Step 1: Add RED ABI and intent-isolation tests**

Add a header/FFI contract assertion for:

```c
const char *needlbar_claude_user_initiated_quota_snapshot_json(void);
const char *needlbar_codex_quota_snapshot_json(void);
```

With injected fake providers, assert:

- ordinary all-provider collection calls Claude with `BackgroundNoUI`,
- the new collection calls only Claude with `UserInitiatedAllowUI`,
- the Codex collection calls only Codex and creates no Claude/Cursor provider,
- success serializes one provider with id `claude`,
- Codex success serializes one provider with id `codex`,
- permission denial serializes `provider: "claude"`, `code: "permissionDenied"`, safe message, and no data token,
- `CLAUDE-KEYCHAIN-CANARY` is absent from the returned bytes and diagnostics,
- each returned pointer is freed exactly once and both exports catch panics.

Extend the existing `bridge-test-runtime` fixture hook so the new exports resolve injected fakes rather than production credentials. Add explicit seams such as:

```rust
pub async fn collect_claude_user_initiated_with_source(
    source: Arc<dyn ClaudeUserInitiatedQuotaSource>,
) -> QuotaCollection;

pub async fn collect_codex_with_provider(
    provider: Arc<dyn QuotaProvider>,
) -> QuotaCollection;
```

The public production collectors construct their real provider and delegate to these seams. Contract tests must prove access-mode isolation without touching a real Keychain or network.

- [ ] **Step 2: Run bridge tests and verify RED**

```bash
cargo test -p needlbar-bridge --test ffi_contract
cargo test -p needlbar-bridge --test quota_contract
```

Expected: missing export/collector and missing `permissionDenied` bridge mapping failures.

- [ ] **Step 3: Implement provider-only collection and safe error mapping**

Add:

```rust
pub async fn collect_claude_user_initiated() -> QuotaCollection {
    let result = ClaudeQuotaProvider::new()
        .fetch_with_credential_access(ClaudeCredentialAccess::UserInitiatedAllowUI)
        .await;
    collection_from_results([result])
}

pub async fn collect_codex_only() -> QuotaCollection {
    collect_codex_with_provider(Arc::new(CodexQuotaProvider::new())).await
}
```

Factor common result-to-collection logic without changing stable provider order in the existing all-provider path. Implement the injection seams above and route the `bridge-test-runtime` fixture through them. Map `QuotaErrorCode::PermissionDenied` to wire code `permissionDenied` and static copy `Provider credential access was denied.` Update both bridge-side exhaustive mappings in `quota.rs` and `lib.rs`.

- [ ] **Step 4: Add the panic-contained C export**

Follow the existing snapshot pattern:

```rust
#[no_mangle]
pub unsafe extern "C" fn needlbar_claude_user_initiated_quota_snapshot_json() -> *const c_char {
    snapshot_json(|| quota::claude_user_initiated_envelope())
}

#[no_mangle]
pub unsafe extern "C" fn needlbar_codex_quota_snapshot_json() -> *const c_char {
    snapshot_json(|| quota::codex_envelope())
}
```

Match the workspace's existing Rust 2021 C ABI style exactly: `#[no_mangle] pub unsafe extern "C" fn`. Do not migrate editions. Neither export accepts a provider string or boolean; the physical API boundary prevents accidental interactive Claude access and accidental all-provider verification from provider-specific call sites.

- [ ] **Step 5: Run bridge verification**

```bash
cargo fmt -p needlbar-bridge -p needlbar-quota -- --check
cargo test -p needlbar-bridge --test ffi_contract
cargo test -p needlbar-bridge --test quota_contract
cargo test -p needlbar-bridge --test redaction_contract --features bridge-test-runtime
cargo test -p needlbar-bridge
```

Expected: ABI, envelope, permission, redaction, panic, and lifetime tests pass without accessing a real Keychain.

- [ ] **Step 6: Commit the provider verification exports**

```bash
git add Sources/CNeedlbar/include/needlbar.h crates/needlbar-bridge
git commit -m "feat: expose provider-specific quota verification"
```

---

### Task 3: Add Typed Post-Authentication Refresh in Swift Core

**Files:**
- Modify: `Sources/NeedlbarCore/Bridge/RustBridge.swift`
- Modify: `Sources/NeedlbarCore/Repositories/QuotaRepository.swift`
- Modify: `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`
- Modify: `Tests/NeedlbarCoreTests/BridgeDecodingTests.swift`
- Modify: `Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift`

**Interfaces:**
- Produces Swift `QuotaRefreshIntent` cases `.backgroundAll` and `.userInitiated(provider:)`.
- Changes `QuotaRepository` to `refresh(intent:) throws -> QuotaRefreshResult` with a convenience `refresh()` fixed to `.backgroundAll`.
- Produces `RefreshCoordinator.refreshQuota(afterUserAuthenticationFor:) async -> Bool`.
- Maps Claude and Codex user intents to their dedicated provider-only C exports.

- [ ] **Step 1: Add RED bridge/repository intent tests**

Inject separate JSON calls into `RustBridge` and assert exact routing:

```swift
public enum QuotaRefreshIntent: Equatable, Sendable {
    case backgroundAll
    case userInitiated(provider: ProviderID)
}
```

- `.backgroundAll` invokes only `needlbar_quota_snapshot_json`.
- `.userInitiated(.claude)` invokes only `needlbar_claude_user_initiated_quota_snapshot_json` and frees its pointer once.
- `.userInitiated(.codex)` invokes only `needlbar_codex_quota_snapshot_json` and frees its pointer once.
- `.userInitiated(.cursor)` fails closed as unsupported because Cursor uses its own connection controller.

- [ ] **Step 2: Add RED coordinator coalescing tests**

Extend the serialized coordinator suite with a blocking intent-aware quota repository. Prove:

- authentication completion performs no usage call and no forced Cursor sync,
- Claude verification returns `true` only after a fresh Claude result,
- permission denial returns `false` while preserving last-known-good quota,
- a user intent arriving during background refresh is not merged away,
- three concurrent Claude requests queue one Claude follow-up,
- simultaneous Claude and Codex requests each receive the result of their own provider verification in stable provider order,
- each provider-specific completion resumes only that provider's waiters exactly once,
- stop/restart generation changes resume every outstanding waiter exactly once with `false` and do not apply late data,
- a successful Claude-only verification does not advance background-all quota freshness,
- after Claude-only success with stale Codex/Cursor data, opening a popover still triggers a background-all refresh.

- [ ] **Step 3: Run narrow tests and verify RED**

```bash
swift test --filter BridgeDecodingTests
swift test --filter RefreshCoordinatorTests
```

Expected: missing intent, bridge call, repository routing, and coordinator API failures.

- [ ] **Step 4: Implement Rust bridge and repository routing**

Add `claudeUserInitiatedQuotaCall` and `codexQuotaCall` `BridgeJSONCall` values to `RustBridge`, with their dedicated C exports as defaults. Reuse `decodeCString` so UTF-8 validation and exact-once free remain identical.

In `RustQuotaRepository`, parse every dedicated envelope through one helper. Reject an unexpected provider id rather than filtering an aggregate result. Never expose a credential or Keychain result beyond the existing safe `BridgeError`.

- [ ] **Step 5: Implement intent-aware coordinator queuing**

Replace the single quota queued boolean with explicit state:

```swift
private var activeQuotaIntent: QuotaRefreshIntent?
private var queuedBackgroundQuotaRefresh = false
private var queuedUserInitiatedProviders: Set<ProviderID> = []
private var userQuotaWaiters: [ProviderID: [CheckedContinuation<Bool, Never>]] = [:]
```

`beginQuotaRefresh(intent:)` passes the intent to the repository. Existing timer/popover/manual paths request `.backgroundAll`. Rename `lastQuotaSuccessfulAt` to `lastBackgroundQuotaSuccessfulAt`; update it only after a successful `.backgroundAll` result, never after provider-specific verification.

`refreshQuota(afterUserAuthenticationFor:)` registers a continuation in the provider's current generation. Same-provider callers coalesce behind one fetch. If another intent is active, insert the provider into the queue; otherwise begin it immediately. On completion, calculate freshness for exactly that provider, remove and resume only that provider's captured waiters exactly once, then drain queued user providers in `ProviderID.allCases` order before a queued background refresh. `stop()` and generation restart must remove and resume all outstanding waiters with `false` before discarding late tasks. Preserve the existing generation and last-known-good application logic.

- [ ] **Step 6: Run Swift Core tests and full Swift suite**

```bash
swift test --filter BridgeDecodingTests
swift test --filter RefreshCoordinatorTests
swift test
```

Expected: intent routing, concurrent coalescing, no-usage side effects, safe errors, and all existing Swift tests pass.

- [ ] **Step 7: Commit the Core authentication refresh seam**

```bash
git add Sources/NeedlbarCore Tests/NeedlbarCoreTests
git commit -m "feat: add typed post-authentication quota refresh"
```

---

### Task 4: Build the Provider Login Process Coordinator

**Files:**
- Create: `Sources/Needlbar/Authentication/ProviderLoginCoordinator.swift`
- Create: `Tests/NeedlbarTests/ProviderLoginCoordinatorTests.swift`

**Interfaces:**
- Produces `ProviderLoginState`, `ProviderLoginFailure`, `ProviderLoginCommand`, resolver/runner protocols, and `ProviderLoginCoordinator`.
- Produces `connect(_:) -> Bool`, `state(for:)`, and `stop() async`.
- Injects `refreshQuota: @Sendable (ProviderID) async -> Bool`.

- [ ] **Step 1: Add RED fixed-command and environment tests**

Assert exact commands through the resolver result:

```swift
#expect(try resolver.command(for: .claude).arguments == ["auth", "login", "--claudeai"])
#expect(try resolver.command(for: .codex).arguments == ["login"])
```

Test executable discovery through inherited `PATH`, `~/.local/bin`, `~/.volta/bin`, `~/.bun/bin`, `~/.asdf/shims`, `/opt/homebrew/bin`, `/usr/local/bin`, and `~/.nvm/versions/node/*/bin`. The selected executable must pass an injected executable predicate.

Assert the child environment contains only the documented allowlist, prepends the executable parent to `PATH`, includes only the matching `CLAUDE_CONFIG_DIR` or `CODEX_HOME`, and excludes `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, `OPENAI_API_KEY`, and fixture secrets.

- [ ] **Step 2: Add RED state, concurrency, and cleanup tests**

With suspended fake runners, prove:

- same-provider duplicate clicks are rejected,
- Claude and Codex can run independently,
- the main actor stays responsive,
- zero exit calls provider verification exactly once,
- verification `true` becomes `.connected`; `false` becomes `.failed(.verificationFailed)`,
- CLI missing, launch failure, nonzero exit, timeout, and cancellation map to fixed safe failures,
- Cursor never launches,
- `stop()` cancels/reaps both children and late completion cannot refresh or mutate state,
- no child output field exists in the result/state model,
- a never-finishing child receives `SIGTERM`, then `SIGKILL` after the bounded grace period, and is reaped,
- cleanup targets only the exact spawned child PID and never a provider-opened browser.

- [ ] **Step 3: Run the new suite and verify RED**

```bash
swift test --filter ProviderLoginCoordinatorTests
```

Expected: missing coordinator types and behavior.

- [ ] **Step 4: Implement state and command contracts**

```swift
public enum ProviderLoginState: Equatable, Sendable {
    case idle, launching, awaitingBrowser, refreshingQuota, connected
    case failed(ProviderLoginFailure)
}

public enum ProviderLoginFailure: Error, Equatable, Sendable {
    case unsupportedProvider, cliNotInstalled, launchFailed
    case cancelled, timedOut, providerRejected, verificationFailed
}

struct ProviderLoginCommand: Equatable, Sendable {
    let provider: ProviderID
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]
}
```

The resolver builds candidates from fixed locations only. It never launches a shell or reads shell startup files.

- [ ] **Step 5: Implement the bounded direct `Process` runner**

Use `Process` with an executable URL and argument array. Standardize candidate URLs, require the injected executable check, and permit ordinary wrappers/symlinks only after they resolve through the fixed candidate search. Set the minimal environment, close standard input, and direct stdout/stderr to `FileHandle.nullDevice`. Bridge the termination handler asynchronously and race completion against `.seconds(300)`.

On timeout, cancellation, or app stop, send `SIGTERM` to the exact still-running child PID, wait a short bounded grace period, then call `Darwin.kill(pid, SIGKILL)` if that same child remains alive; finally await and reap it. Never target a process group, application name, provider browser, or descendant discovered by scanning. Store active processes inside an actor so `Process` never crosses its isolation boundary.

- [ ] **Step 6: Implement the observable coordinator**

Use `@MainActor public final class ProviderLoginCoordinator: ObservableObject`. Keep provider-scoped tasks and generation counters. A successful process sets `.refreshingQuota`, awaits `refreshQuota(provider)`, and sets `.connected` only for `true` on the current generation. Login progress remains ephemeral and is never written to UserDefaults or diagnostics.

- [ ] **Step 7: Run the non-TTY provider compatibility gate**

Before Task 4 is accepted, use the same direct `Process` configuration—exact arguments, closed stdin, null stdout/stderr, no shell or Terminal—to confirm that installed `claude auth login --claudeai` and `codex login` can open their provider-owned browser from a non-TTY child. This is a user-authorized manual compatibility check because it may start a login flow; cancel before entering credentials unless separately authorized.

Do not parse output and do not add a shell, Terminal, AppleScript, PTY, or fallback command. If either installed CLI cannot initiate browser login under this contract, mark that provider feature blocked in `docs/STATUS.md` and stop before Task 5 rather than weakening the boundary.

- [ ] **Step 8: Run verification and commit**

```bash
swift test --filter ProviderLoginCoordinatorTests
git add Sources/Needlbar/Authentication Tests/NeedlbarTests/ProviderLoginCoordinatorTests.swift
git commit -m "feat: add provider-managed login coordinator"
```

---

### Task 5: Wire Settings, Popovers, and App Termination

**Files:**
- Modify: `Sources/Needlbar/App/AppDelegate.swift`
- Modify: `Sources/Needlbar/MenuBar/MenuBarController.swift`
- Modify: `Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift`
- Modify: `Sources/Needlbar/Settings/SettingsView.swift`
- Modify: `Sources/Needlbar/Settings/SettingsWindowController.swift`
- Modify: `Tests/NeedlbarTests/AppDelegateLifecycleTests.swift`
- Modify: `Tests/NeedlbarTests/MenuBarControllerTests.swift`
- Modify: `Tests/NeedlbarTests/PopoverPresentationTests.swift`

**Interfaces:**
- Consumes the application-lifetime login coordinator and `refreshQuota(afterUserAuthenticationFor:)`.
- Produces Claude/Codex browser-login rows, provider-popover CTAs, and exactly-once child cleanup on termination.
- Preserves the existing Cursor transient-token clearing and serialized Connect/Reconnect/Disconnect controller.

- [ ] **Step 1: Add RED presentation and routing tests**

Add a pure action model:

```swift
enum ProviderAuthenticationAction: Equatable, Sendable {
    case browserLogin(title: String)
    case openSettings(title: String)
}
```

Assert auth-required Claude selects `Sign in with Claude`, Codex selects `Sign in with ChatGPT`, and Cursor selects `Open Settings`. Fresh, stale, unavailable, rate-limited, network, and schema states must not invent a login CTA.

In `MenuBarControllerTests`, assert Claude/Codex call `onProviderLoginRequested(provider)` once; Cursor opens Settings and never invokes the login coordinator.

- [ ] **Step 2: Add RED termination tests**

Extend `AccessoryTerminationController` tests with suspended login and refresh shutdown gates. The AppKit reply must remain pending until both finish, repeated requests must not duplicate cleanup, and the reply count must be exactly one.

- [ ] **Step 3: Run UI/lifecycle suites and verify RED**

```bash
swift test --filter PopoverPresentationTests
swift test --filter MenuBarControllerTests
swift test --filter AppDelegateLifecycleTests
```

Expected: missing CTA, callback, injected Settings coordinator, and login shutdown hook failures.

- [ ] **Step 4: Implement Settings connection rows**

Inject the shared coordinator into `SettingsView` with `@ObservedObject`. Render independent Claude and Codex buttons and fixed safe status copy. During Claude `.refreshingQuota`, state that macOS may request access to Claude Code credentials; never mention a Keychain account, item payload, path, or token.

Use these generic terminal messages: CLI not found, login could not start, login cancelled, login timed out, login incomplete, or sign-in completed but quota could not be verified. Leave every Cursor secret-handling line intact.

- [ ] **Step 5: Wire popovers and shared ownership**

Pass the coordinator into `SettingsWindowController` and `MenuBarController`. Provider popovers close before launching or opening Settings. `AppDelegate` constructs one coordinator after `RefreshCoordinator`:

```swift
let loginCoordinator = ProviderLoginCoordinator(
    refreshQuota: { provider in
        await refreshCoordinator.refreshQuota(afterUserAuthenticationFor: provider)
    }
)
```

No login begins in app launch, refresh start, file watcher, popover open, or Settings construction.

- [ ] **Step 6: Stop login children before termination reply**

Extend the termination task to await `loginCoordinator.stop()` and `refreshCoordinator.stop()` before replying. Preserve synchronous cancellation/observer cleanup and exactly-once semantics.

- [ ] **Step 7: Run UI/lifecycle verification and commit**

```bash
swift test --filter PopoverPresentationTests
swift test --filter MenuBarControllerTests
swift test --filter AppDelegateLifecycleTests
swift test --filter ProviderLoginCoordinatorTests
git add Sources/Needlbar Tests/NeedlbarTests
git commit -m "feat: expose Claude and Codex browser login"
```

---

### Task 6: Update Public Contracts and Run Final Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/privacy.md`
- Modify: `docs/providers/claude.md`
- Modify: `docs/providers/codex.md`
- Modify: `docs/providers/cursor.md`
- Modify: `docs/STATUS.md`

**Interfaces:**
- Produces accurate public connection, privacy, Keychain permission, recovery, compatibility, and continuation documentation.
- Preserves unreleased status, no release tag, and no notarization claim.

- [ ] **Step 1: Update provider and privacy documentation**

Document:

- Claude/Codex buttons launch provider-owned browser flows.
- Claude Code stores current macOS OAuth in Keychain; Needlbar may request exact-item access only after the explicit click.
- background access is interaction-forbidden and never prompts.
- the raw credential stays Rust-internal, ephemeral, redacted, and unpersisted by Needlbar.
- Codex keeps its existing auth/app-server quota path.
- Cursor remains explicit session-token based because no compatible personal quota credential handoff is documented.
- missing CLI, denied Keychain permission, and re-authentication recovery steps.

- [ ] **Step 2: Update README connection guidance**

Use concise provider rows and mention the possible Claude macOS Keychain permission. Keep build/test/package/privacy claims accurate and do not document credential values or private payloads.

- [ ] **Step 3: Run narrow and full automated gates**

```bash
cargo fmt --workspace -- --check
cargo test -p needlbar-quota --test claude
cargo test -p needlbar-bridge --test ffi_contract
cargo test -p needlbar-bridge --test quota_contract
cargo test -p needlbar-bridge --test redaction_contract --features bridge-test-runtime
cargo clippy --workspace --all-targets --all-features -- -D warnings
swift test --filter RefreshCoordinatorTests
swift test --filter ProviderLoginCoordinatorTests
swift test --filter PopoverPresentationTests
swift test --filter MenuBarControllerTests
swift test --filter AppDelegateLifecycleTests
source /Users/taejunoh/.cargo/env
make test
git diff --check
git -C vendor/tokscale-core status --short
```

Expected: all commands exit 0; no real browser or Keychain UI appears; the pinned vendor tree is clean.

- [ ] **Step 4: Run a bounded non-credentialed UI smoke**

Launch with `make run`, verify three connection rows and independently enabled Claude/Codex buttons, and confirm no login or Keychain prompt occurs before a click. Stop the process and confirm no Needlbar or provider-login child remains. Do not click a real login button in this automated smoke.

- [ ] **Step 5: Perform the user-authorized Claude compatibility acceptance**

In a separate credentialed manual gate, record only:

- installed Claude Code version,
- whether `claude auth login --claudeai` completed,
- whether the exact `Claude Code-credentials` query returned one parseable item after macOS permission,
- whether Claude quota became fresh,
- whether diagnostics/preferences/log searches contained no credential canary or account identifier.

Never print, persist, hash, or copy the credential value. If the exact service/payload contract fails, stop and record the release blocker; do not broaden the Keychain query.

- [ ] **Step 6: Perform Codex credentialed acceptance**

Run the explicit Codex button flow, verify provider-owned browser completion and fresh Codex quota, and confirm the currently observed broken npm wrapper is reported safely until the local Codex installation is repaired. Do not alter the user's Codex installation without separate authorization.

- [ ] **Step 7: Update status and commit public docs**

Record implementation commits, test counts, CI state, non-credentialed smoke, credentialed acceptance results or blockers, Cursor's unchanged path, and the exact next action. Then commit:

```bash
git add README.md docs/architecture.md docs/privacy.md docs/providers/claude.md docs/providers/codex.md docs/providers/cursor.md docs/STATUS.md
git commit -m "docs: document provider-managed browser login"
```

---

## Plan Self-Review Checklist

- [x] Every feature-spec acceptance criterion maps to a numbered task.
- [x] Background quota cannot call an interaction-allowed Keychain path.
- [x] Only the dedicated Claude post-auth export can permit Keychain UI.
- [x] The exact Keychain service query has no enumeration or heuristic fallback.
- [x] Raw credentials cannot cross Rust quota, C ABI, Swift, diagnostics, or logs; real credentials never enter tests and synthetic canaries stay contained.
- [x] Claude and Codex post-auth verification each use a dedicated provider-only ABI.
- [x] Provider-specific success cannot advance the all-provider background freshness timestamp.
- [x] Every provider waiter is resumed exactly once, including stop/restart paths.
- [x] Claude/Codex command names, arguments, labels, and Core APIs are consistent.
- [x] Cursor remains on the existing explicit session-token path.
- [x] Same-provider duplicate and cross-provider concurrency behavior is tested.
- [x] App termination and late-completion generation protection are tested.
- [x] The final task includes `make test`, strict Clippy, redaction tests, UI smoke, and both provider compatibility gates.
