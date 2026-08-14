# Needlbar Agent Guide

This repository is being implemented from an approved v0.1 design and implementation plan. Continue the existing plan; do not redesign the product unless the user explicitly asks for a design change.

## Start Here

Read these files in order before changing code:

1. `docs/STATUS.md` — current implementation state, blockers, and exact continuation point.
2. `docs/superpowers/specs/2026-08-13-needlbar-v0.1-design.md` — approved v0.1 product and architecture contract.
3. `docs/superpowers/plans/2026-08-13-needlbar-v0.1.md` — task-by-task implementation plan.

When the plan is silent, the approved design spec is authoritative.

## Current Continuation Point

The bootstrap from Task 1 is present on `main`. The first GitHub Actions run completed with a failure in the Swift portion of `make test` because `Package.swift` declares `// swift-tools-version: 6.0` while the selected `macos-14` runner invokes Swift 5.10.

Before starting Task 2:

1. Resolve the Swift toolchain mismatch with the smallest deliberate change.
2. Keep the macOS 14 deployment target unless the approved design changes.
3. Run `make test` and require a clean exit.
4. Push the fix and confirm CI is green.
5. Update `docs/STATUS.md` to mark Task 1 verified.

The implementation plan names Swift 6 as the baseline. If you change the package tools version instead of selecting/configuring a Swift 6-capable CI toolchain, record that deviation in `docs/STATUS.md` rather than silently changing the baseline.

After Task 1 is green, continue with **Task 2: Define the Rust JSON Envelope and Memory-Safe C ABI** from the implementation plan.

Task 2's public contract includes:

- `const char *needlbar_usage_snapshot_json(void)`
- `const char *needlbar_quota_snapshot_json(void)`
- `const char *needlbar_diagnostics_json(void)`
- `void needlbar_free_string(const char *ptr)`
- JSON envelope fields `schemaVersion`, `ok`, `generatedAt`, `data`, and `errors`
- `BridgeError { provider: Option<String>, code: String, message: String }`

Follow the exact Task 2 checklist in the implementation plan rather than re-deriving the bridge design.

## Working Contract

- Work one numbered implementation-plan task at a time.
- Use tests first where the plan specifies test-first steps.
- Run the narrow test while developing, then run `make test` before considering a task complete.
- Keep Swift/AppKit presentation, `NeedlbarCore` state, Rust usage aggregation, Cursor source hydration, quota retrieval, and the C bridge in their assigned layers.
- Usage and quota must remain independently refreshable and independently fallible.
- Do not add providers or v0.1-excluded features opportunistically.
- Do not move token-history parsing into `needlbar-quota`.
- Do not move subscription quota computation into `needlbar-source-sync`.
- Do not add presentation logic to `needlbar-bridge`.
- Do not change the pinned `tokscale-core` revision without the fixture cross-check required by the design.
- Prefer focused commits and avoid unrelated refactors.
- Update `docs/STATUS.md` whenever a task is completed, a blocker changes, or the next continuation point moves.

## Verification Entry Point

From a fresh checkout:

```bash
git submodule update --init --recursive
make test
```

`make test` is the project-wide verification command.
