# Analytics Producer–Consumer Contract Correction

> **For agentic workers:** Use subagent-driven-development for the bounded correction and independent review. User approved proceeding after the same-byte live diagnosis.

**Goal:** Make populated production analytics output conform to the existing Swift contract and prevent the demonstrated integration-testing gap.

**Architecture:** Preserve strict Core decoding and the approved `needlbar.analytics.v1` schema. Correct producer serialization; exercise the real RustBridge and decoder using the existing nonshipping bridge-test-runtime fixture path.

**Tech Stack:** Rust serde, C ABI, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-01-needlbar-v0.2.2-local-repository-cost-analytics-design.md`, sections 5–7. This is a corrective amendment to the prior presentation-only plan, authorized by the subsequent diagnosis/approval.

## Constraints

- `repositoryID` and `commitID` are the approved exact field names.
- Capture time remains fixed; no emitted commit may be after that time.
- No public C/header, schema-version, parser/vendor, UI, permission, authentication, network, or refresh-scheduling changes.
- Fixture controls remain under `bridge-test-runtime` and absent from normal artifacts.
- Preserve source privacy, stale last-good behavior, all existing byte/record bounds, and unrelated worktree changes.
- No merge, push, or public release. Native installation is gated on corrected-source review/tests and one safe live boundary verification.

## Task 1: Actual serialized populated payload regression and ID correction

Files: `crates/needlbar-project-analytics/src/model.rs`, `crates/needlbar-bridge/src/test_runtime.rs`, and a focused `Tests/NeedlbarCoreTests` bridge test.

- [ ] Add test-only fixture install/clear controls reusing the existing deterministic analytics redaction fixture; no public header.
- [ ] In Swift, install fixture, defer cleanup, call `RustBridge().analyticsEnvelope()`, decode with exact `AnalyticsBridgeDecoder`, and assert nonempty repository and commit with independently known valid IDs. Serialize tests that share global fixture state.
- [ ] Run focused `make swift-test` and observe field-set rejection before any production correction.
- [ ] Add `#[serde(rename = "repositoryID")]` to `repository_id`. Verify remaining `commitId` still fails the same cross-language test.
- [ ] Add `#[serde(rename = "commitID")]` to `commit_id`; rerun focused tests and require success. Retain strict Swift validation.
- [ ] Review diff for real serialization coverage, cleanup, and normal-artifact isolation.

## Task 2: Fixed capture boundary for correlated commits

Files: `crates/needlbar-project-analytics/src/correlation.rs` and `crates/needlbar-project-analytics/tests/correlation.rs`.

- [ ] Regression: capture T, fragment end T−60s, commit T+60s. Expect no commit row, assigned=0, unassigned=1, pendingCommitWindow=1, and retained repository usage. Control: commit exactly T remains eligible.
- [ ] Run focused Rust test and observe future commit wrongly assigned.
- [ ] Add `commit.committed_at <= state.generated_at` to the existing inclusive correlation predicate. Do not clamp dates or change the four-hour window.
- [ ] Rerun focused tests and the correlation suite; independently review the diff.

## Task 3: Final gates and truthful handoff

- [ ] Run full `make test` serially; retain logs outside the worktree and verify exit/counts.
- [ ] Verify normal archive has no test-only controls using the existing public-bridge-surface gate.
- [ ] Recompile the prior scratch harness against the corrected normal archive/Core objects; run at most one bounded live collection, identical bytes into exact decoder, fixed categories/counts only, no raw payload persistence.
- [ ] Record actual success/failure separately from native UI acceptance in `docs/STATUS.md`.

## Deferred, explicit decisions

The >256 distinct provider/model rows mismatch is real but not observed in the live failure. Folding/truncation policy affects data semantics; retain it as a separate bounded-output design task, not a silent cap relaxation. Safe production failure categorization likewise remains a separate bounded follow-up rather than adding arbitrary logging or changing the screen during this repair. The scratch verification supplies exact boundary evidence for this correction.
