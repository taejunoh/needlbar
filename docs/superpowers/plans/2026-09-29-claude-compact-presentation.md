# Claude Compact Presentation Implementation Plan

> For agentic workers: use subagent-driven-development for scoped implementation and review.

**Goal:** Reduce the overview dashboard's verbose Claude quota block without hiding stale-value warnings or losing diagnostic information.

**Architecture:** Presentation-only change. Retain the normalized quota selection and refresh behavior. Claude and Fable each get a compact visible value row; detailed provenance, failures, observation timestamps, and unverified reset information move into a default-collapsed disclosure. Other providers retain their current presentation.

**Tech Stack:** SwiftUI/AppKit, Swift Testing.

## Task 1: Compact Claude dashboard presentation

- Own `SystemDashboardPopoverView.swift` and focused tests in `SystemDashboardPopoverTests.swift`; add a small presentation helper in `SystemDashboardModel.swift` only if it supports meaningful behavior tests.
- Show Claude's current value, or its explicitly labelled last-known value when current quota is unavailable. Never imply a retained value is fresh.
- Show Fable's value and its independent last-known/status indication on a separate concise row.
- Keep active actionable status and action failures visible. Keep the configured API billing action available.
- Put duplicate caption/source/reason/time/reset metadata inside a default-collapsed `Quota details` disclosure, preserving separate local-receipt and direct-fetch labels and Fable timestamps.
- Preserve independent Fable freshness and unknown/unverified resets. Do not change credentials, refresh logic, or Core quota selectors.
- Test stale, missing, fresh local primary plus stale Fable, and layout height/disclosure expansion. Run focused tests, then `make test` and `git diff --check`.
- Update `docs/STATUS.md` with verified scope and remaining native acceptance/integration state.

## Task 2: Review and handoff

- Review compliance with the compact-display and provenance requirements, then review implementation quality.
- Verify a hosted/rendered compact and expanded example if the existing local harness permits it; never present fixture data as live account data.
- Provide a reviewable completed change. Publishing a new release is outside this layout-only task.
