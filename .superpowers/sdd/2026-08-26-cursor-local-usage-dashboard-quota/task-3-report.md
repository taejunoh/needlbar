# Task 3 report: simplify NeedlbarCore to one usage refresh path

## TDD evidence

After the Task 3 test updates, the required RED command sequence exposed the
removed `needlbar_forced_usage_snapshot_json` ABI from
`RustBridge.swift`. Each focused Swift command failed to compile until the
forced bridge/repository/coordinator path was removed.

The integration smoke test then failed as intended because the feature-gated
integration runtime still returned a `cursor.plan` quota snapshot. The test
expected local Cursor usage with unavailable quota. The narrow fixture change
made that runtime return the existing provider-scoped `providerUnavailable`
result instead.

## Implementation

- `RustBridge.usageEnvelope()` and `UsageRepository.refresh()` now expose one
  normal usage path only.
- `RefreshCoordinator` has no forced-cycle state. A manual refresh that sees
  an in-flight usage cycle requests the same generation-bound normal follow-up;
  repeated callers coalesce to at most one queued follow-up. Stop and
  generation guards remain unchanged. Quota intents/coalescing are unchanged.
- Retired Cursor bridge action decoding, diagnostics sources/error codes, and
  forced refresh test doubles were removed. Cursor diagnostics decode local
  usage with `unavailable` quota source and `providerUnavailable` error.
- Integration fixtures retain local Cursor usage while returning unavailable
  Cursor quota; headline selection now considers only eligible Claude/Codex
  windows.

## Authorized transitional cleanup

Task 2 had already deleted the Cursor session C ABI, which blocked compilation
of all Swift test targets. Per the controller ruling, this task also removed
the obsolete Settings session controller, bridge, state, token controls, and
their three controller-only tests. Settings retains only the approved
non-interactive copy:

> Usage is read from an existing local cache. Quota is available in Cursor Spending.

No Spending action, button, URL opener, popover route, or authentication-action
policy was added; Task 4 owns those.

The only Rust cross-layer fixture change is
`crates/needlbar-bridge/src/test_runtime.rs` in `FixtureMode::Integration`:
Cursor's former successful `cursor.plan` fixture was replaced by the existing
action-free `providerUnavailable` outcome. Production quota collection and all
other fixture modes are untouched.

## GREEN verification

All commands exited 0:

```text
PATH=/Users/taejunoh/.cargo/bin:$PATH cargo test -p needlbar-bridge --features bridge-test-runtime
PATH=/Users/taejunoh/.cargo/bin:$PATH cargo test -p needlbar-bridge --features bridge-test-runtime --test usage_contract
swift test --filter RefreshCoordinatorTests
swift test --filter BridgeDecodingTests
swift test --filter BridgeIntegrationSmokeTests
swift test --filter DiagnosticsTests
swift test --filter HeadlineQuotaSelectorTests
PATH=/Users/taejunoh/.cargo/bin:$PATH make test
git diff --check
```

The final project gate reported Rust workspace success, Swift 127 tests passed,
and the package-app relink regression passed.

## Self-review

- No forced usage-call injection or forced coordinator state remains in
  `NeedlbarCore`.
- Manual in-flight semantics are deliberately a single normal queued follow-up,
  not a force mode.
- The non-interactive Settings transition contains no token field, session
  controller/bridge, connection status, or navigation action.
- The diagnostic and integration fixture contracts preserve Cursor local usage
  independently of unavailable quota.

## Commit

`refactor: remove forced Cursor refresh state`
