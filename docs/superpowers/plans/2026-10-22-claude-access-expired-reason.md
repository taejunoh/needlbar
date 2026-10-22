# Claude access-expired reason Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement increment 1 of
`docs/superpowers/specs/2026-10-22-claude-credential-renewal-design.md`. When
a direct Claude quota attempt fails with `authenticationExpired` because the
access Claude Code saved on this Mac has passed its expiry time, say so
plainly instead of the generic "Quota access unavailable". Renewal is not
implemented and is not part of this plan.

**Architecture:** Presentation change in `NeedlbarCore` and the app target.
After each completed Claude quota operation the coordinator reads the existing
bridge diagnostics record once, through an injected reader, before it stores
the failure reason. It accepts the record's closed failure origin only for the
attempt it is completing, and hands the same read to the existing OSLog
reporter, which keeps its event rules. A new `ClaudeQuotaFailureReason` case is
stored only for `authenticationExpired` plus a local-expiry origin; every other
combination keeps the code-based mapping. Presentation puts the short text in
the existing reason slot, or on the Fable line when the main windows are
recent through the status line, with a detail line in the popover and
Settings only. No Rust, C ABI, JSON schema, export, widget, menu bar, or
notification change.

**Tech Stack:** Swift concurrency, SwiftUI/AppKit hosting with the
accessibility tree, Swift Testing.

---

## Decisions

- **Case name:** `ClaudeQuotaFailureReason.claudeCodeAccessExpired`. It names
  the cause the origin establishes (Claude Code's saved access expired on this
  Mac), not the copy, and it is the design's working name.
- **Copy (§8 Q2(a)):**
  - Short, key `claudeQuota.reason.claudeCodeAccessExpired`:
    "Waiting for Claude Code to renew access".
  - Detail, key `claudeQuota.reason.claudeCodeAccessExpired.detail`, popover and
    Settings only: "Needlbar reads the access Claude Code saves on this Mac. It
    has expired. Needlbar updates automatically after Claude Code renews it."
  - No action, link, sign-in, or command text (§8 Q3(a)).
- **Association (§4.2):** the origin is used only when all hold:
  - the read succeeded and the Claude record carries an origin and is not
    `available`;
  - its `lastAttemptAt` is not earlier than the attempt start truncated to
    whole seconds (the bridge writes whole seconds);
  - the attempt's generation is the current run generation, re-checked after
    the read;
  - the attempt's Claude result is a failure.
  Otherwise the code-based reason is kept. A failed read or an undecodable
  origin is the same as no origin.
- **One read:** the coordinator calls the reader once per completed Claude
  operation (background, Claude user-initiated, Claude preflight) and passes
  the same value to the reporter. Production wiring no longer installs the
  zero-argument completion callback that used to read again.
- **Placement (§4.4, §8 Q6):**
  - no recent value: the existing reason slot on every surface, as today;
  - main windows recent through the status line: once, on the Fable line —
    popover Fable section, Settings Fable line, dashboard Fable status (the
    status the reason used to suppress);
  - the dashboard compact headline, label, and provider status keep their
    existing rules; the dashboard gets no detail line.

## File map

- Modify `Sources/NeedlbarCore/Models/ClaudeQuotaFailureReason.swift`: the case,
  localized copy, and the code-plus-origin mapping.
- Create `Sources/NeedlbarCore/Diagnostics/ClaudeQuotaCompletionDiagnostics.swift`:
  the shared read type, the injected read/report pair, and the association
  guard.
- Modify `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`: read once,
  associate, map, then report.
- Modify `Sources/Needlbar/Diagnostics/ClaudeQuotaFailureDiagnosticsReporter.swift`:
  report from a supplied read; event rules unchanged.
- Modify `Sources/Needlbar/App/AppDelegate.swift`: production wiring.
- Modify `Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift`,
  `Sources/Needlbar/Settings/SettingsView.swift`,
  `Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift`,
  `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift`:
  placement, detail line, and accessibility labels.
- Create `Tests/NeedlbarCoreTests/ClaudeAccessExpiredReasonTests.swift` and
  `Tests/NeedlbarTests/ClaudeAccessExpiredPresentationTests.swift`.
- Amend the 2026-09-15 and 2026-09-16 specifications; update `docs/STATUS.md`
  and `docs/HANDOFF.md`.

### Task 1: Tests first

- [ ] Write the §5 tests 1–7 with a manual clock, scripted fake quota
  repository, fake diagnostics reader with read counter and gate, canary
  payloads, and spy closures for every action. View-level checks host the real
  SwiftUI views and read their accessibility tree.
- [ ] Add only compile scaffolding (the case and copy, an ignored coordinator
  parameter, `nil` presentation fields) so the run fails on assertions, not on
  compilation. Record the RED run.
- [ ] Export and widget fixtures are the bytes the pre-change code produced
  for the same scripted failure at `df5c77e`.

### Task 2: Implement §4.1–4.7

- [ ] Mapping, association, single read, reporter hand-off, production wiring.
- [ ] Presentation fields and views. Leave the menu bar, widget, export,
  notifications, cadence, recovery triggers, and actions unchanged.
- [ ] Focused tests GREEN.

### Task 3: Documents and gates

- [ ] Dated amendment notes in the two specifications, a dated STATUS entry
  (no release run IDs, asset IDs, or hashes repeated), and the HANDOFF
  credential item.
- [ ] Gates: focused tests; `make test` with
  `env PATH="$HOME/.cargo/bin:$PATH" MACOSX_DEPLOYMENT_TARGET=14.0`;
  `env -u LANG -u LC_ALL -u LC_CTYPE bash scripts/tests/notarize-app-tests.sh`;
  `git diff --check`; grep of the added lines for sign-in, log-in, Terminal, or
  command text.

Passing source tests establishes mapping and presentation only. It does not
establish native behaviour, renewal, or unattended recovery.
