# Analytics Summary-First Design

**Status:** A layout and detailed scope approved in conversation; written spec awaiting user review.

## Purpose and scope

Improve the native Analytics window so repository-attributed estimates, unlinked
usage, missing evidence and diagnostic limitations cannot be mistaken for one
another. Investigate the observed zero-repository result using local aggregate-only
diagnostics. This supplements the approved 2026-09-01 v0.2.2 analytics contract;
its privacy, bounded processing, pricing, correlation and manual-refresh rules
remain authoritative.

No menu-bar, Settings, quota, authentication, widget or export changes. No new
providers, arbitrary folder discovery, network calls, database or automatic scans.
The public v0.3.0 tag and release assets remain immutable. This work does not
implicitly authorize a new release, push or installation.

## Selected presentation: A, summary first

Use a native adaptive window, respecting system light/dark appearance and existing
app typography. The browser mockup selects structure, not its decorative gradients
or exact CSS. Maintain readable primary text, secondary labels, aligned numerical
values and restrained warning color. No invented charts or sample repositories in
production empty states.

1. A compact header contains Analytics, the fixed last-30-days range, capture time
   and Refresh. Preserve the single retained window and existing serialized refresh.
2. Three summary cards show repository-attributed estimated cost, repository
   linkage and observed active AI-session time.
3. Repository rows appear in existing descending cost order. Each expands to
   provider/model and local commit details with all existing safety caveats.
4. An independent Unattributed section presents retained unlinked usage and cost.
5. A collapsed diagnostic disclosure explains limitations and safe next actions.
   An additional concise estimate-definition disclosure replaces the long always-
   visible explanatory block.

At wide sizes the summary cards share a row; at the minimum supported size they
reflow without horizontal clipping. Keep the header visible and place the content
in a vertical scroll view. Long model labels and diagnostic descriptions wrap;
numerical amounts remain legible. All content, including the final disclosure,
must be reachable with scrolling and keyboard navigation. Disclosure controls
have accessible labels and explicit expanded state; color is not the sole signal.

## Truthful display rules

- The summary cost is explicitly **Repository-attributed estimate**, not total
  spend. With no eligible repository evidence show `—` and `No linked repositories`
  instead of a prominent `$0.00`. A genuinely measured zero remains zero. Preserve
  underlying aggregates and known-subtotal semantics when pricing is partial.
- Linkage shows the repository count and a separately labelled unlinked-fragment
  count. Repository counts and fragment counts are not one fraction. If a coverage
  percentage is displayed, use the existing attributed/eligible-fragment definition
  and state its denominator; an empty denominator is unavailable, not 0%.
- Active time is **Observed AI activity**, with its timestamp-gap definition
  available in help. No attributable evidence means `—`, not `0s`. A valid isolated
  timestamped event can legitimately yield zero observed time. Missing response
  duration is distinct from absent active-time evidence and does not alone make
  active time unavailable.
- Keep Unattributed estimated cost separate from repository totals. When timestamp
  coverage is incomplete, state that the amount is not a verified 30-day total.
  Never label either amount as an invoice or subscription charge.
- A repository-empty result explains that no usable local repository association
  was established, rather than claiming the user has no repositories or AI usage.
  Offer the diagnostic disclosure and existing manual Refresh; do not introduce a
  folder picker or imply Refresh will repair missing source metadata.
- Diagnostic counts retain their units: fragments, observations or inspection
  failures. Counts for different units must not be added together. Explain timing
  truncation independently from Git output/record limits; do not claim lost cost
  merely because timing observations were bounded.
- Initial loading, refreshing with existing data, stale last-good, unavailable,
  partial and complete states remain distinct. Disable Refresh while in flight.
  A failed refresh preserves the last successful content with a stale notice.

## Investigation findings and limits

Read-only tracing used the v0.3.0 pinned vendor revision `ecfb694`; the main
checkout has unrelated vendor modifications and must not be repaired or reset.

Confirmed code behavior:

- AnalyticsView sums repository rows only for summary cost; Unattributed is separate.
- In the supplied snapshot, 430 unlinked fragments match 418 missing-timestamp
  and 12 discovery-unavailable outcomes. No retained fragment produced a repository
  row. This is not evidence of a SwiftUI row-visibility problem.
- The vendor caps retained positive timestamp observations at 8,192 while retaining
  cost/token aggregation. The analytics adapter currently maps timing overflow to
  both missing-duration and record-limit reasons, conflating diagnostic meanings.
- The local Git executable works. Discovery-unavailable can also represent workspace
  canonicalization, spawning or cleanup failure; a missing executable is not the
  established cause.

Unresolved: which sources produced the missing-timestamp fragments and which
specific discovery stage failed. Stale or inaccessible workspaces are a hypothesis,
not a confirmed cause. The matching 158,033 counters strongly suggest timing-only
overflow but must not substitute for stage-level evidence.

## Safe diagnostic work and correction boundary

Before proposing attribution changes, add fixture-tested, one-shot local diagnostic
instrumentation outside the public analytics ABI. It may emit only fixed provider
identifiers and aggregate counts for timestamp absent/invalid, canonicalization
failure, discovery spawn/cleanup failure, non-repository, mapped results and the
separate timing/fragment/model caps. File errors may be classified by fixed error
kind to distinguish absent paths from inaccessible or malformed paths.

No raw paths, source messages, prompts, responses, credentials, session identifiers,
Git output, per-record token values or costs may enter the report. No new persisted
analytics cache, background task, source traversal or network access is allowed.
The probe uses the existing bounded source pipeline only when explicitly invoked.
Do not log raw errors as part of implementing the counters. Remove the temporary
probe from packaged production artifacts and preserve sanitized fixture coverage.

After evidence identifies a cause, specify the smallest correction and regression
fixture before changing aggregation. Do not increase caps, weaken validation,
invent timestamps, reassign unknown records or replace the vendor pin by assumption.
A source parser/vendor or public schema change requires a separately reviewed
technical amendment and the existing provider fixture-parity checks. Presentation
changes may proceed without claiming that the attribution cause has been fixed.

## Ownership and implementation sequencing

- Rust source engine retains parsing/dedup/pricing ownership; project analytics
  retains repository resolution, bounded correlation and sanitized result ownership.
- NeedlbarCore derives UI-free presentation semantics from validated snapshot data.
- Native Analytics views own layout, disclosures and interactions. Keep these
  changes isolated from repository fetching and provider refreshes.
- Plan one numbered task at a time: safe evidence probe; presentation semantics
  tests; A-layout implementation; native acceptance and documentation. Add an
  evidence-based attribution correction task only after its technical scope is known.

## Verification and acceptance

Use test-first steps in the implementation plan. Cover all-unlinked, no data,
valid zero-cost/zero-active-time, mixed attribution, missing pricing/timing,
overflow reasons, multiple repositories, large values and long labels. Privacy
canaries must prove no raw diagnostic data reaches the ABI or normal logs.

Run focused Rust and Swift tests during development, then `make test`, package
and smoke serially from an isolated worktree using the pinned vendor. Do not use
direct Swift tests against an incorrectly configured bridge runtime.

Visually inspect actual native light/dark windows at default and minimum sizes:
summary, populated/empty repository list, expanded provider/commit rows, diagnostic
disclosures, scroll reachability and loading/partial/stale/unavailable states.
Check keyboard and accessibility labels. Browser mockups alone are not acceptance.
Record command exits and distinguish fixture verification from live-source findings.
Update docs/STATUS.md with the evidence, remaining uncertainty and next task.
