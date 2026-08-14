# Needlbar Development Status

**Updated:** 2026-08-14
**Branch:** `main`
**Current phase:** Task 1 bootstrap verified
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
- Tracked `Cargo.lock` for deterministic Rust dependency resolution.
- Minimal Swift and Rust bootstrap sources/tests.
- GitHub Actions CI on `macos-14` running `make test`.

Task 1 continuation commits on `main`:

- `dea34b2` — select Xcode 16.2 for Swift tests on CI.
- `a7ca67a` — track `Cargo.lock`.

## Current CI State

Task 1 is verified green.

- Local `make test` passed on Swift 6.3.3 and Rust 1.97.1.
- `Cargo.lock` is tracked for deterministic Rust dependency resolution.
- GitHub Actions run [31837456920](https://github.com/openai/needlbar/actions/runs/31837456920) succeeded in 3m49s.
- CI retains `runs-on: macos-14` and deliberately selects `/Applications/Xcode_16.2.app` before running tests.
- `Package.swift` remains on Swift tools version 6.0 with a macOS 14 deployment target.
- No approved-baseline deviation was made.

## Required Next Action

Task 1 verification is complete. Begin Task 2 exactly at the Rust JSON envelope and memory-safe C ABI work described below; preserve the approved Swift 6.0 baseline and macOS 14 deployment target.

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
