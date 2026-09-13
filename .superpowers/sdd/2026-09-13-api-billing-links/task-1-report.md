# Task 1 report: Persist the strict opt-in

## Result

Implemented and committed the Core persistence contract for per-provider API
billing-link visibility. Claude and Codex read and persist strict Booleans;
Cursor is always false. Codable missing or malformed values fall back to false,
and the setter posts the existing configuration notifications.

## Verification

All commands were run from the isolated worktree
`/Users/taejunoh/Developer/LFG/needlbar/.worktrees/api-billing-links` with
`PATH=/Users/taejunoh/.cargo/bin:$PATH`.

### RED

Command:

```text
PATH=/Users/taejunoh/.cargo/bin:$PATH make swift-test SWIFT_TEST_FILTER='apiBillingPreferencesAreStrictAndIndependent'
```

Result: exit 2, as expected. Compilation failed because
`AIProviderDisplayPreference.apiBillingLinkVisible` and
`ModuleConfiguration.setAPIBillingLinkVisible(_:for:)` did not yet exist.

### GREEN (focused)

Command:

```text
PATH=/Users/taejunoh/.cargo/bin:$PATH make swift-test SWIFT_TEST_FILTER='ModuleConfiguration\|apiBilling'
```

Result: exit 0. All 8 matching Core tests passed, including
`apiBillingPreferencesAreStrictAndIndependent`.

### GREEN (project gate)

Command:

```text
PATH=/Users/taejunoh/.cargo/bin:$PATH make test
```

Result: exit 0. Swift ran 474 tests in 19 suites; Rust workspace, pinned
vendor, bridge archive, provider-brand-assets, widget-extension, package-app,
and notarize-app gates passed.

`git diff --check` also exited 0 before commit.

## Review notes

`UserDefaults` preserves an existing numeric `NSNumber` type when a malformed
numeric value is overwritten with a Boolean. The supported-provider writes
therefore remove the canonical key before setting the Boolean, ensuring strict
reads remain strict after repair. Reads do not write defaults or refresh data.

Commit: `3beb611da00613f21ba0eb5e2534c0a3110a330b`
