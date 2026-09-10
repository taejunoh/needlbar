# Analytics observed-time bounds technical amendment

Status: Technical amendment reviewed PASS; synthetic RED reproduced and correction
implemented in local vendor commit `3c427e0`. Focused, direct vendor, parent Rust
and final `make test` verification passed (exit 0). No release or runtime
installation is claimed.

## Evidence and scope

The September 10 aggregate-only probe reported 501 normalized timestamp-unavailable
fragments, 180115 overflowed timing observations, and 566 overflowed fragment
observations. Twelve workspace canonicalizations reported absent paths. The
missing-path problem is independent and is not repaired by this amendment.

At pinned vendor `ecfb69497307b3bfbb5d9c25fc7d2fcc5c6dfefc`, the workspace report
uses a global 8192-element timing-observation budget. A detailed fragment first
seen after that budget retains usage but no timing samples; finalization currently
derives first/last timestamps from that empty sample and emits zero. A previously
sampled fragment can likewise retain an outdated end time after later accepted
events are omitted from the timing sample. Code tracing establishes these paths;
the live aggregates alone do not establish how many user fragments took them.

## Correction contract

For each of the existing at-most-512 detailed workspace/session fragments, retain
two scalar observed timestamp bounds independently of the timing sample vector.
Update minimum and maximum for every accepted positive timestamp, including events
whose timing samples cannot be retained. Emit these actual bounds as first_seen_ms
and last_seen_ms. A fragment with no observed positive timestamp still emits zero.

Calculate active time exclusively from the existing bounded sample vector. Do not
calculate duration from the scalar bounds. Preserve timing_coverage_partial and
all overflow counters. The anonymous overflow bucket retains no workspace,
identity or timestamp bounds and must remain unattributed.

The corrected end bound deliberately changes the four-hour commit association
where the previous sampled end preceded the actual final event. No timestamp is
invented, and no missing workspace is reassigned. Existing exact-range filtering,
deduplication, costs, token totals, scanning order, cache policy, limits, source
traversal, networking and manual-refresh behavior remain unchanged.

## Ownership and file boundary

- Vendor `src/lib.rs`: WorkspaceSessionAccumulator scalar bounds and its tests.
- Vendor workspace report integration tests: range/dedup and cap regression.
- Needlbar analytics tests: positive bounded-end report maps through fake Git;
  genuinely missing timestamps and anonymous overflow remain unattributed.
- Parent vendor gitlink: update only after required fixture-parity checks.
- No analytics ABI, Core DTO, Swift UI, Git runner, permissions or signing change.

Do not modify the unrelated dirty vendor checkout on main. Work only in the
existing isolated analytics worktree. No push, release or local reinstall is
implied by this amendment.

## Regression and verification gates

1. Feed 8192 valid events for detailed session A, then a positive event for B.
   B must retain its actual bounds and unchanged usage, with timing partial and
   one timing overflow; no detail overflow. Verify failure before implementation.
2. Feed a later positive A event after the budget. Its end bound must advance to
   that actual time; sampled activity must not increase from the scalar bounds.
3. Nonpositive source timestamps remain zero; out-of-order positive events yield
   actual min/max; exact instant range filtering and dedup remain unchanged.
4. The 513th detail key stays in the anonymous zero-bound overflow bucket.
5. Analytics regression verifies repository eligibility and commit selection use
   the actual end, while missing-source-time controls remain unattributed.
6. Run pinned-provider usage fixture parity for Claude, Codex and Cursor, the
   vendor suite, focused analytics/privacy tests, and full `make test` before any
   production-completion claim or pin update. Record actual command exits.

A successful synthetic regression does not prove all live repository linkage is
repaired: absent paths, true missing metadata and detail-cap pressure remain.
