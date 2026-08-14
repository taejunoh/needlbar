# Needlbar Development Status

**Updated:** 2026-08-14
**Branch:** `main`
**Current phase:** Task 1 bootstrap verification
**Next implementation task:** Task 2 — Rust JSON envelope and memory-safe C ABI

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
- Minimal Swift and Rust bootstrap sources/tests.
- GitHub Actions CI on `macos-14` running `make test`.

Latest known bootstrap commit before this status document: `6c4e7a5bc35cdb8f1b079aae5354522c7de43dd4` (`ci: add bootstrap verification workflow`).

## Current CI State

GitHub Actions CI run #1 (`31805524416`) completed with **failure**.

The failure is in the Swift portion of `make test`: the package manifest declares Swift tools 6.0, while the selected `macos-14` runner currently invokes Swift 5.10.

Known manifest line:

```swift
// swift-tools-version: 6.0
```

Known error:

```text
package 'needlbar' is using Swift tools version 6.0.0
but the installed version is 5.10.0
```

Rust compilation/tests completed before that Swift failure; the current blocker is the Swift toolchain mismatch, not a known Rust test failure.

## Required Next Action

Do not begin Task 2 until Task 1 has a green project-wide verification.

Resolve the mismatch deliberately. Two conceptual options are:

1. Configure CI to use a Swift 6-capable toolchain while preserving the implementation plan's Swift 6 baseline.
2. Lower `swift-tools-version` only if Swift 5.10 compatibility is intentionally accepted; document this as a baseline deviation here.

Whichever path is chosen, verify with:

```bash
make test
```

Then push and confirm the GitHub Actions run is green.

## Task 2 Continuation Point

Once Task 1 is green, resume exactly at:

> **Task 2: Define the Rust JSON Envelope and Memory-Safe C ABI**

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
