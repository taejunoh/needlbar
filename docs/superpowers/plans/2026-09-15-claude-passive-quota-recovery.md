# Claude passive quota recovery implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Tech Stack:** Swift, SwiftUI/AppKit, Swift Testing; existing Rust bridge unchanged.

## Global Constraints

No live credentials, login, token writes, automatic browser actions, new refresh
timers, installation, push, or release. Codex/Cursor and API billing behavior
stay unchanged. Last-success timestamps must not become last-attempt timestamps.
Only typed allowlisted failure reasons enter the new presentation. The approved
specification is authoritative. Implementation uses TDD before production edits.

> **For the implementer:** Work in the dedicated `claude-passive-quota-recovery`
> worktree. This plan implements only the approved
> `2026-09-15-claude-passive-quota-recovery-design.md`; it does not change
> credential ownership, quota refresh scheduling, or provider login.

**Goal:** Make a failed Claude quota refresh degrade to a safe, last-known
presentation with one optional official usage-page link, rather than prompting
the user to sign in again.

**Architecture:** Preserve an allowlisted Claude quota-failure classification
alongside the existing last-known quota state in `NeedlbarCore`. The bridge's
already-safe error *code* is classified at the refresh boundary; raw bridge
messages never become presentation data. Existing snapshots continue to carry
their value/status and their last successful observation time. Presentation
derives a compact Claude-only fallback from those safe fields, while Codex and
Cursor retain their current login/action behavior. A small app-owned URL action
opens the fixed public URL only when explicitly pressed and reports only a
fixed local failure message.

## Task 1: Implement the typed Claude fallback end-to-end

**Files:**

- Create: `Sources/NeedlbarCore/Models/ClaudeQuotaFailureReason.swift`
- Modify: `Sources/NeedlbarCore/Models/ProviderSnapshot.swift`
- Modify: `Sources/NeedlbarCore/State/ProviderSnapshotStore.swift`
- Modify: `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`
- Create: `Sources/Needlbar/Claude/ClaudeUsageAction.swift`
- Modify: `Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift`
- Modify: `Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift`
- Modify: `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift`
- Modify: `Sources/Needlbar/MenuBar/MenuBarController.swift`
- Modify: `Sources/Needlbar/Settings/SettingsView.swift`
- Modify: `Sources/Needlbar/Settings/SettingsWindowController.swift`
- Test: `Tests/NeedlbarCoreTests/ProviderSnapshotStoreTests.swift`
- Test: `Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift`
- Test: `Tests/NeedlbarCoreTests/SnapshotExporterTests.swift`
- Test: `Tests/NeedlbarTests/PopoverPresentationTests.swift`
- Test: `Tests/NeedlbarTests/SystemDashboardPopoverTests.swift`
- Test: `Tests/NeedlbarTests/MenuBarControllerTests.swift`
- Test: `Tests/NeedlbarTests/SettingsStudioTests.swift`
- Test: `Tests/NeedlbarTests/ProviderBrandSurfaceContractTests.swift` (only if
  its source/action contract assertions need the new fixed action)

- [ ] **Step 1:** Define the Core-only safe classification, then make it survive a failed
   Claude refresh without exposing a raw error.

   Add `ClaudeQuotaFailureReason: String, Sendable, Equatable` with exactly
   these cases and display strings:

   | bridge error code | reason case | displayed text |
   | --- | --- | --- |
   | `requiresAuthentication`, `authenticationExpired` | `quotaAccessUnavailable` | `Quota access unavailable` |
   | `permissionDenied` | `credentialAccessUnavailable` | `Credential access unavailable` |
   | `networkUnavailable` | `connectionUnavailable` | `Connection unavailable` |
   | `rateLimited` | `temporarilyLimited` | `Temporarily limited` |
   | `notInstalled`, `providerUnavailable`, `schemaChanged`, `internalError`, malformed/unknown code, or an untyped quota operation failure | `couldNotUpdateQuota` | `Could not update quota` |

   Put the mapping in `RefreshCoordinator`, keyed only by `BridgeError.code`.
   Do not inspect `BridgeError.message`, error descriptions, timestamps,
   Keychain state, HTTP payloads, or process state. Apply a reason only to
   Claude quota failures; leave `quotaStatus(for:)`, Codex login, and Cursor
   provider-unavailable handling semantically unchanged. Cover both success
   result `refresh.errors` and `BridgeFailure.bridgeFailed` paths, and map the
   generic non-`BridgeFailure` path for Claude to `couldNotUpdateQuota`.

   Extend `ProviderSnapshot` with optional safe Claude quota recovery metadata:
   `claudeQuotaFailureReason` and `quotaLastSuccessfulAt`. Give new initializer
   parameters defaults so unrelated fixtures remain source-compatible. Keep
   this metadata out of `ExportCapture`, `WidgetStoreCapture`, diagnostics, and
   logs; the existing export status/last-success fields remain schema-compatible.
   In `ProviderSnapshotStore`, store the reason with the quota stream,
   preserve it when retaining a last-known quota on failure, set it only via a
   dedicated optional argument to `markQuotaFailure`, and clear it in
   `applyQuota`. The timestamp must be assigned only by `applyQuota`, never by
   `markQuotaFailure`; a failed first fetch therefore has neither quota value
   nor last-success time.

- [ ] **Step 2:** Derive the approved Claude presentation from the safe Core fields; do not
   use the existing generic authentication CTA as a recovery path.

   In `ProviderPopoverPresentation`, add explicit Claude quota fallback fields
   (reason text, whether a retained result is `Last known`, and optional
   `Last checked` timestamp) derived from `quota`,
   `claudeQuotaFailureReason`, and `quotaLastSuccessfulAt`. For a failed or
   stale cached Claude value, retain and label the percentage/windows as `Last
   known` and format `Last checked` with a user-locale `DateFormatter`; do not
   use `updatedAt`/attempt time. For a Claude fallback without a value, render
   `—` and `Quota unavailable`, with no timestamp, reset, or zero. Show the
   one allowlisted reason once at the Claude quota level. Fable must inherit
   the parent Claude freshness and mark an old reset as old, but must not echo
   the reason beneath its own row. A fresh successful result removes all
   fallback copy naturally when the store clears its reason.

   Add `.openClaudeUsage(title: "View Claude usage")` to
   `ProviderAuthenticationAction`, but select it only for a Claude snapshot
   with `claudeQuotaFailureReason`; never return `.browserLogin` for Claude.
   Keep Codex's existing browser-login action and Cursor Spending action.
   Do not show the generic Retry control for Claude fallback states. Thread the
   same presentation fields through `SystemDashboardPresentation.AIProvider`
   and `SystemDashboardPopoverView` so its Claude row has identical last-known,
   last-checked, unavailable, and one-reason behavior. The dashboard must not
   display the provider/Fable error twice.

- [ ] **Step 3:** Add the explicit public usage action and wire failure feedback locally.

   Model `ClaudeUsageAction` after `CursorSpendingAction`: its only destination
   is `https://claude.ai/settings/usage`, and `open(using:) -> Bool` delegates
   to the supplied/default `NSWorkspace` opener. Thread an injectable
   `() -> Bool` closure through `MenuBarController`, `SettingsWindowController`,
   `SettingsView`, and dashboard/provider-popover action dispatch. Do not
   dismiss into or invoke `ProviderLoginCoordinator` for this action.

   Reuse the existing dashboard billing-link-state pattern (or an equivalently
   small Claude-usage link state) to retain a local boolean open failure and
   resize the displayed dashboard if its safe message becomes visible. On a
   false opener result, keep the active surface and show one fixed accessible
   message such as `Couldn't open Claude usage. Try again.`; on success clear
   it. In Settings, replace only the Claude connection login row with concise
   provider-owned usage copy plus `View Claude usage` and the same local-safe
   failure feedback. Do not change the Codex connection row, Cursor row, API
   billing settings, refresh cadence/single-flight, credential reads, or
   browser-login implementation.

- [ ] **Step 4:** Write deterministic tests before each seam; no live auth, Keychain,
   browser, or network access.

   - `ProviderSnapshotStoreTests`: cached Claude quota + failure retains value,
     exact original `quotaLastSuccessfulAt`, and safe reason; an initial failed
     quota has no value/timestamp; `applyQuota` clears the reason; a failure
     attempt date different from the successful date is not substituted.
   - `RefreshCoordinatorTests`: inject every table code above through both
     returned-error and bridge-failure paths; assert only the matching typed
     Claude reason. Assert unknown/untyped errors become `couldNotUpdateQuota`,
     not authentication, and Codex/Cursor keep current statuses/actions.
   - `SnapshotExporterTests`: assert the existing snapshot JSON schema and
     safe `lastSuccessfulAt` behavior are unchanged and neither enum/display
     text nor a raw bridge message is exported.
   - `PopoverPresentationTests`: fresh Claude remains normal; stale and
     failure-with-cache show `Last known` and locale-formatted successful time;
     failure-without-cache is `—`/`Quota unavailable` without time/reset; all
     five reasons render exactly once; Fable marks old data without duplicating
     the reason; recovery after `applyQuota` clears fallback; Claude exposes
     only `View Claude usage`, while Codex/Cursor preserve their actions.
   - `SystemDashboardPopoverTests`: assert equivalent dashboard copy/action,
     no duplicated Fable reason, fixed action title/accessibility label, and
     local link-open failure/retry feedback and sizing state.
   - `MenuBarControllerTests` and `SettingsStudioTests`: inject a false then
     true URL opener, assert the exact fixed URL/action is used only after an
     explicit click, safe failure clears on success, and no Claude login
     coordinator callback fires. Preserve existing API-billing and Cursor
     assertions.

- [ ] **Step 5:** Verify the focused test targets during development, then run the repository
   gate from the recovery worktree:

   ```bash
   swift test --filter ProviderSnapshotStoreTests
   swift test --filter RefreshCoordinatorTests
   swift test --filter PopoverPresentationTests
   swift test --filter SystemDashboardPopoverTests
   swift test --filter MenuBarControllerTests
   swift test --filter SettingsStudioTests
   swift test --filter SnapshotExporterTests
   make test
   git diff --check
   ```

   Before handoff, inspect the diff for forbidden additions: refresh-token
   parsing/writes, credential-store access changes, automatic CLI/browser
   calls, new timers/retries, raw `BridgeError.message` presentation/export,
   and any Codex/Cursor or API-billing behavior change. Do not claim the
   installed app changed until a separately authorized build/install step.
