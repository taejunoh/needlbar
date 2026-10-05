# Claude Connection Card Padding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Give the Claude Settings connection card the approved 20pt vertical and total 24pt horizontal clearance, with a readable explanation-to-quota gap.

**Architecture:** Presentation-only SwiftUI change. If required for real layout tests, extract the existing row verbatim into a small internal production view consumed by SettingsView; retain state ownership and the same action. SettingsStudioSection retains its existing 16pt horizontal inset and all other cards remain unchanged.

**Tech Stack:** SwiftUI, AppKit NSHostingView, Swift Testing, existing synthetic provider presentations.

---

### Task 1: Implement and verify Claude card spacing

**Files:**
- Modify: `Sources/Needlbar/Settings/SettingsView.swift`.
- Create only if necessary: `Sources/Needlbar/Settings/ClaudeUsageConnectionRow.swift`.
- Create: `Tests/NeedlbarTests/ClaudeUsageConnectionRowLayoutTests.swift`.
- Update: `docs/STATUS.md`.

- [x] Run the unchanged baseline using `PATH=/Users/taejunoh/.cargo/bin:$PATH make test`; record the pre-existing ready-file fixture race and passing focused rerun in STATUS rather than claiming a green initial baseline.
- [x] Build a real NSHostingView regression for the production connection row wrapped in SettingsStudioSection. Use synthetic complete and unavailable/last-known presentations, including Fable and failure/timestamp lines; never read live credentials. Inspect measured content bounds or rendered pixels, not source text or padding constants.
- [x] Demonstrate a failing assertion against the unpadded row. An internal content/row split preserves existing layout and state ownership, so this red run identifies missing clearance rather than a compile error.
- [x] Apply the approved insets to the Claude row only:

```swift
.frame(minHeight: 54)
.padding(.horizontal, 8)
.padding(.vertical, 20)
```

  Add `.padding(.bottom, 6)` to the explanatory caption only. Keep existing 2pt spacing among individual quota metadata lines.
- [x] Run `PATH=/Users/taejunoh/.cargo/bin:$PATH make swift-test SWIFT_TEST_FILTER=ClaudeUsageConnectionRowLayoutTests`; this wrapper installs the fixture-only Rust bridge required by the existing test targets and restores the production archive afterward. Require actual green layout assertions at regular and narrow widths, with no missing or clipped metadata. Retain the RED/GREEN evidence logs.
- [x] Render synthetic light/dark card images and inspect them. Do not alter the installed app or user preferences for review. The fixture-only rendering helper remains in the test file.
- [x] Run `PATH=/Users/taejunoh/.cargo/bin:$PATH make test` and `git diff --check`, independently review scope and code quality, and correct any substantive findings.
- [x] Record results and delivery limits in STATUS. Commit the focused change after a final diff check; do not push, merge, release, replace the app, or modify authentication.
