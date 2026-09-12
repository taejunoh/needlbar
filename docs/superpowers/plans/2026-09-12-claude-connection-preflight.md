# Claude Connection Preflight

**Approved direction:** User approved reducing redundant login and permission requests on 2026-09-12. Execute in the existing isolated worktree.

**Execution status:** Implemented and independently reviewed on 2026-09-12. Final
`make test` passed (Swift 473 tests / 19 suites plus Rust and shell contracts).
Locally rebuilt, signed, and installed after follow-up approval; runtime hash and
recoverable backup are recorded in STATUS. No live authentication check, push,
notarization, or release performed.

## Design and global constraints

An explicit Claude connection click first performs a Claude-only quota check that forbids Keychain interaction. Fresh quota connects immediately. Missing or expired authentication starts the existing fixed Claude CLI login. Permission denial during the silent check proceeds to one existing interactive verification without launching the CLI. Other failures stop safely without login. CLI success still requires fresh quota verification.

This amends the 2026-08-25 provider-managed login design only to allow explicit-click preflight and permission-only verification without a preceding CLI process. The first macOS grant cannot be bypassed or guaranteed unnecessary. Background work never prompts. No credential duplication, new OAuth client, Keychain enumeration, query/schema changes, secrets in Swift/logs, live credential inspection, or actual login in automated tests. Codex and Cursor behavior stays unchanged. Quota remains serialized, provider-specific, generation-safe, independent from usage, and preserves last-known-good data.

## Task 1: Implement and test the end-to-end Claude preflight

**Ownership:** One implementation agent owns the following production files and their focused tests. Root owns this plan and STATUS; no concurrent implementation edits.

- `crates/needlbar-bridge/src/quota.rs`: Claude-only BackgroundNoUI collector using the existing provider fetch path.
- `crates/needlbar-bridge/src/lib.rs`, `Sources/CNeedlbar/include/needlbar.h`: dedicated `needlbar_claude_preflight_quota_snapshot_json` export, normal envelope/free/panic/redaction contracts.
- `Sources/NeedlbarCore/Bridge/RustBridge.swift`: injected dedicated preflight bridge entry.
- `Sources/NeedlbarCore/Repositories/QuotaRepository.swift`: dedicated `.claudePreflight` intent, normalize only Claude.
- `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`: typed `ClaudeLoginPreflightOutcome` and `preflightClaudeLogin()`, integrated into the existing one-task scheduler. Outcomes: verified, requiresAuthentication, keychainPermissionRequired, verificationFailed. Classify current result errors before DataStatus collapse; requiresAuthentication/authenticationExpired mean login, permissionDenied means permission verification. A prior cached fresh snapshot must never turn a failed current check into success. Stop/restart completes waiters once with failure and prevents late publication. Dedicated checks must not mark all-provider refresh fresh.
- `Sources/Needlbar/Authentication/ProviderLoginCoordinator.swift`: injected preflight closure, Claude-only branching before executable lookup; preserve admission, cancellation, shutdown/generation protections. Fresh preflight skips locator/runner. Permission branch uses one interactive verifier and skips locator/runner even on denial. Non-auth faults fail safely. Existing Codex path unchanged. Any default injection must fail closed rather than invent a successful check.
- `Sources/Needlbar/App/AppDelegate.swift`: production wiring to coordinator preflight.
- `Sources/Needlbar/Settings/SettingsView.swift`: concise upfront explanation that existing sign-in is checked first and macOS may request access. Update other exhaustive UI consumers only if needed; do not redesign views.
- `docs/providers/claude.md`: accurate new flow and unavoidable first permission explanation.
- Focused tests in `Tests/NeedlbarTests/ProviderLoginCoordinatorTests.swift`, `Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift`, bridge/repository test files as discovered, and Rust bridge contract tests. No unrelated test repairs.

### Steps

1. Read current interfaces and identify exact existing test suites. Run focused baseline tests. Read TDD guidance and write failing behavioral tests first; record RED command/output before implementing each layer.
2. Add the dedicated no-UI Rust/ABI/repository path, reusing existing security and normalization boundaries. Test provider isolation and access mode through injected resolvers/collectors only.
3. Add typed serialized preflight results and deterministic coalescing/stop tests. Test fresh, absent/expired auth, permission, network/schema, failed current check with cached good quota, queued background work, and generation changes.
4. Add login branching and wiring. Verify locator/runner zero calls for fresh and permission branches; auth-required runs the fixed CLI then exactly one verifier; denial does not retry; repeated clicks are single-flight; stopping preflight cannot start CLI or interactive verification later. Codex regression tests pass.
5. Update focused copy/docs. Self-review against the constraints. Run focused Swift/Rust tests, `git diff --check`, and one full `make test`. Preserve full logs outside tracked code. Report the known unrelated Analytics cancellation admission flake separately if it recurs; do not change that test here.
6. Write report with RED/GREEN evidence, exact commands/results and changed files. Do not commit, push, install, release, touch live credentials, or dispatch subagents. Root will review and decide integration.

## Review and handoff

Independent review checks spec and quality, particularly no-UI isolation, error classification, serialized waiter lifecycle, and zero redundant login. Root verifies final test evidence and updates STATUS. Native user acceptance remains separate from synthetic tests; do not claim installed behavior changed until an updated build is installed.

## Preflight conflict table

| Task | Files shared with other active writers | Ruling |
| --- | --- | --- |
| 1 | None; root only edits plan and STATUS | Single implementation agent; reviewer read-only |
