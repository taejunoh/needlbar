# Automatic Claude Checks Opt-In Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Needlbar starts the user's installed `claude` to run `/usage` without a click only if the user turned that on. It is off by default, the user is told in three places, and automatic runs pause while Claude is hidden, as approved in the 2026-11-16 design.

**Architecture:** One gate, in one place. `ClaudeUsageProbeSchedule` gains `automaticRunsEnabled`, checked first in `automaticRunIsAllowed`, which every non-manual request and due check already passes through. `RefreshCoordinator` holds the flag, builds the schedule from it on `start()`, and exposes a setter that requests one `automaticResumed` run when it turns on. The app owns the reasons: a stored preference and the pure function `claudeIsShown`. It recomputes their conjunction on the main actor and sends it to the coordinator through one serial `AsyncStream`. `SettingsActions` carries the preference to Settings and the dashboard, so the acceptance build, which passes none, shows neither control. Part 2 adds a first-run window behind a presenter protocol and one new production lifecycle step.

**Tech Stack:** Swift 6 (SwiftPM, Swift Testing), SwiftUI and AppKit, Combine, macOS 14+ arm64. No Rust or C change.

## Global Constraints

Authoritative spec: `docs/superpowers/specs/2026-11-16-claude-automatic-checks-opt-in-design.md`. Copied from it verbatim:

- Status: "It authorizes an implementation plan only. Implementation, merge, installation, tag and release each still need the user's separate request."
- Default: "**Off by default,** for new installs and for people updating. A missing preference means off."
- Manual: "While off, `claude` starts only on a manual refresh (Check now). A manual run never turns the schedule on. Wake and connectivity recovery never start Claude, as today."
- Cadence: "**Cadence unchanged:** 15 minutes, 5-minute floor, backoff 5/10/20/30 minutes, 60-second limit."
- Gate: "**an automatic run may start only while automatic runs are allowed.**"
- Schedule: "`ClaudeUsageProbeSchedule` gains `automaticRunsEnabled`, default `false`." and "While off, a refused request does not set `pendingTrigger`, and `recordFailure` ignores non-manual triggers, so no backoff or retry can exist while off (an invariant, tested). Manual requests are unaffected."
- Coordinator: "`RefreshCoordinator` takes `claudeAutomaticRunsAllowed: Bool` at init, with no default, so every caller states it; existing tests pass `true`. It gains `setClaudeAutomaticRunsAllowed(_:)`. `start()` builds `ClaudeUsageProbeSchedule(automaticRunsEnabled:)` from the stored flag and requests only `startup`. The setter while stopped only stores the value. The 60-second tick keeps running; while off it starts nothing. A call that does not change the value does nothing."
- Turning off: "sets `pendingTrigger = nil`, `retryPending = false`, `backoffUntil = nil` and `consecutiveAutomaticFailures = 0`, and keeps `lastStartedAt`. A run in flight is not cancelled: it finishes within the 60-second limit and its reading is applied."
- Turning on: "requests one run at once, with the new trigger `automaticResumed`, through the automatic path, so the 5-minute floor still applies. If that request is refused (a run in flight, or one started less than 5 minutes ago), it is queued only when `lastStartedAt` is nil; otherwise nothing is queued and the periodic run follows 15 minutes after the last start."
- Trigger names, exactly: `startup`, `periodic`, `windowReset`, `backoffRetry`, `automaticResumed`, `manual`. "`QuotaRefreshTrigger` gains `automaticResumed`, logged like the others".
- Preference key: `needlbar.claude.automaticUsageChecks.enabled`, "absent means false, published state, `setEnabled`".
- App wiring: "`AppDelegate` passes the initial `preference && claudeIsShown` at init, and on a preference change or `ModuleConfiguration.didChangeNotification` recomputes it on the main actor and sends it through one serial channel (a single `AsyncStream` consumer), so values reach the coordinator in the order they were computed."
- Switch: "`NEEDLBAR_DISABLE_CLAUDE_USAGE_PROBE=1` still removes the repository, so neither automatic nor manual runs start."
- Shown: "`claudeIsShown(_: SystemMonitorConfiguration)`, true if either holds: the AI module is visible on the menu bar and Claude is visible in it; the AI section is visible on the dashboard and Claude is visible in it." and "The widget and notifications do not count".
- Dashboard copy: caption "Automatic checks are off." and a borderless "Turn on" button beside "Check now". "The acceptance build shows no prompt, so its fixtures do not depend on the developer's defaults."
- Settings copy: toggle "Check Claude quota automatically"; caption "Runs /usage in your Claude Code about every 15 minutes. Off: only when you click Check now."; while on and Claude is hidden, "Paused while Claude is hidden."
- "**Check now:** runs once; it does not turn the schedule on." and "**Menu bar and widget:** unchanged".
- First-run key: `needlbar.onboarding.claudeUsage.answeredVersion`; "The window shows while it is below the constant `1`"; "It is written when the user answers or closes the window, not when the window appears".
- First-run rule: "`shouldShow(answeredVersion:probeDisabled:claudeShown:)`". Already on: "the window is not shown and the answer is recorded."
- First-run copy. Title: "Check Claude quota automatically?" Body: "Needlbar can run /usage in the Claude Code you installed, under your own sign-in: when Needlbar starts, about every 15 minutes while it is running, when a limit resets, and sooner after a failed check. Needlbar does not read your Claude sign-in. If you leave this off, it runs only when you click Check now. You can change this in Settings." Buttons: "Turn on" and "Not now", "with "Not now" as the default button, because the window can appear at login and Return must not opt in. Closing the window counts as "Not now"."
- "The copy does not say whether a run uses quota or sends a model request; neither is verified."
- README paragraph: "Needlbar runs `claude` on a schedule only if you turn that on. It is off by default, including after an update, and Needlbar asks once. While it is off, Needlbar starts `claude` only when you click Check now. While it is on, it runs `/usage` when Needlbar starts, when you turn it on or show Claude again, about every 15 minutes, after a shown limit resets, and 5 to 30 minutes after a failed automatic run. Automatic runs pause while Claude is hidden from both the menu bar and the dashboard. Turning it off stops new automatic runs; one already started is stopped at 60 seconds at the latest."
- Delivery: "Two pull requests, each with its plan tasks: 1. The gate, the preference, the Settings toggle, the row prompt and off state, and the documentation. 2. The first-run window."

Repository constraints:

- Implementers never run `claude`; never read `~/.claude/.credentials.json`, `~/.claude.json`, Keychain items or cookies; never do anything that can change Claude Code's login state; never install an app or copy one into `/Applications`; never use `make run`; never push, merge, tag or start a release. The only app launch this plan allows is `make smoke` in the two verification tasks: it starts the packaged app from `dist/` with `NEEDLBAR_DISABLE_CLAUDE_USAGE_PROBE=1`, so no `claude` starts and no first-run window appears, and it stops the app itself.
- Tests never start the real `claude`. Coordinator tests use the fakes in `Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift` and a manual clock. App tests use isolated `UserDefaults` suites, never `.standard`.
- Bare `swift test` cannot link, because the tests need the bridge built with its test feature. Use `make swift-test SWIFT_TEST_FILTER=<name>` (`Makefile:9-53`). It builds that bridge, cleans the Swift build, runs the tests, then restores the normal bridge and cleans again, so each run takes about five minutes. Give it a timeout of at least ten minutes and let it finish; do not interrupt it. The filter is passed unquoted to the shell, so it holds no `|` or parentheses. It matches test type and function names, not a suite's display name.
- Never run `cargo fmt --all`: it reformats the vendored `vendor/tokscale-core` submodule. This plan changes no Rust file.
- CI builds with Xcode 16.2 and Swift 6.0, which is stricter than a newer local Swift in places. An implicit `switch` return is valid only as the sole expression of a body. Use the code in this plan as written and add no newer-only syntax.
- In `README.md`, `0.3.14` and `0.3.15` may appear only inside their versioned sections, and the section `### Claude quota from the Claude Code usage report (v0.3.15 prepared)` may gain no `### ` heading: the fixture at `scripts/tests/notarize-app-tests.sh:2238-2256` removes each section up to the next `### ` and aborts on any other occurrence. The README text in Task 8 adds neither string and no heading.
- New `docs/STATUS.md` text repeats no run ID, asset ID, release commit hash, `releases/tag/`, or `report 0.3.`, because the decoys at `scripts/tests/notarize-app-tests.sh:2207-2229` rewrite the first occurrence. Docs say prepared, not released.
- Stage only the files each commit step lists. Never `git add -A` or `git add .`: `.superpowers/brainstorm/` is untracked and stays out.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Commands run from the repository root after `export PATH="$HOME/.cargo/bin:$PATH" MACOSX_DEPLOYMENT_TARGET=14.0`. `rg` and the `make` targets that use it need `PATH` prefixed with `/Users/taejunoh/.codex/plugins/.plugin-appserver/codex-cli/codex-path` on the maintainer's Mac.
- Line numbers are from commit `946a389`. Once an earlier step shifts a file, find the place by the quoted text. Every quoted "replace" text occurs exactly once in its file at the time its step runs.
- Branches: Part 1 is committed on `claude/claude-auto-checks-gate`, created from the commit that holds the spec and this plan. Part 2 is committed on `claude/claude-auto-checks-first-run`, created from the tip of Part 1. Opening the two pull requests needs the user's request.

---

## Decisions Settled From The Code

### 1. Where the gate goes, and what today's code does

| Place | Today | Change |
|---|---|---|
| `ClaudeUsageProbeSchedule.automaticRunIsAllowed`, `ClaudeUsageProbeSchedule.swift:76-87` | The 5-minute floor and backoff | Checks `automaticRunsEnabled` first (Task 1) |
| `ClaudeUsageProbeSchedule.request`, `:25-32` | A refused non-manual request sets `pendingTrigger` | While off it sets nothing; a refused `automaticResumed` is queued only when `lastStartedAt` is nil (Task 1) |
| `ClaudeUsageProbeSchedule.recordFailure`, `:62-68` | Ignores manual failures | Also ignores every failure while off (Task 1) |
| `RefreshCoordinator.start()`, `RefreshCoordinator.swift:185,196` | Builds a fresh schedule and requests `.startup` | Builds it from the stored flag; still requests only `.startup` (Task 4) |
| `RefreshCoordinator.finishClaudeUsageProbe`, `:554-559` | Replays a pending request through `requestClaudeUsageProbe` | None: the replay goes through `request`, so the gate covers it |
| `RefreshCoordinator.evaluateClaudeUsageProbeTriggers`, `:503-515`, every 60 s | Starts `dueTrigger(...)` | None: `dueTrigger` returns nil while off, and the tick keeps running |
| `RefreshCoordinator.manualRefresh()`, `:255` | `requestClaudeUsageProbe(trigger: .manual)` | None |
| `RefreshCoordinator.backgroundRequestIsDue`, `:407` | An exhaustive `switch` over the triggers | Gains `.automaticResumed` (Task 1) |
| `AppDelegate.init`, `AppDelegate.swift:202-211` | Builds the coordinator | Passes the initial value (Task 4) and adds the relay (Task 5) |

The trigger's raw value reaches only the unified log (`QuotaRefreshDiagnosticsReporter`, `trigger=\(event.trigger.rawValue)`), so `automaticResumed` is "logged like the others" with no further change.

A refused resume with `lastStartedAt == nil` happens in one case: after `stop()` and `start()` the schedule is new while an older physical run is still in flight (`claudeUsageProbeTask` is kept until the call returns). Then the resume is queued and starts when that run ends, exactly as a refused `startup` does today.

Task 1 changes the two schedule constructions in `RefreshCoordinator` to `ClaudeUsageProbeSchedule(automaticRunsEnabled: true)`. That keeps the coordinator's behaviour identical until Task 4 replaces them with the stored flag, so every commit in Part 1 builds and passes.

### 2. How the app reaches the coordinator

`ClaudeAutomaticRunsRelay` (Task 5) observes the preference and `ModuleConfiguration.didChangeNotification`. Each observation hops to the main actor, reads the current preference and configuration, and yields the conjunction into one `AsyncStream`; a single task consumes it and awaits `setClaudeAutomaticRunsAllowed` for each value before reading the next. `@Published` reports a change before the value is stored, which is why the value is read on the next main-actor turn and not taken from the publisher. Because every value is computed from the state at the moment it is sent, the last value the coordinator applies is always the current one.

### 3. How the setting reaches Settings and the dashboard

`SettingsActions` is already the one object both `SettingsWindowController` and `MenuBarController` receive, and the acceptance build constructs it with no arguments. It gains an optional `ClaudeAutomaticChecksPreferences` and republishes it as `claudeAutomaticChecksEnabled: Bool?`. Nil hides the Settings toggle and the dashboard prompt. That gives the spec's "The acceptance build shows no prompt" without a build flag, and no existing `SettingsView`, `SettingsWindowController` or `MenuBarController` construction changes. The Settings toggle is therefore also absent in the acceptance build, which has no refresh coordinator for it to control; the spec names only the prompt.

### 4. Interpretations

1. **One line is both the reason and the prompt caption.** Spec §6 says, of a row with no reading while off, "the reason line says "Automatic checks are off." in the secondary colour, with no orange, no "Could not update", and no error state on the dashboard", and, of the prompt, "the caption "Automatic checks are off." and a borderless "Turn on" button beside "Check now"". Putting the sentence in the existing reason slot as well would show it twice in the standard layout and hide it inside "Quota details" in the compact one. The row therefore shows the sentence once, as the prompt's caption, in `caption2` and the secondary colour, in both layouts. Before any run the store reports no failure reason and the status `unavailable`, which the dashboard already draws without orange (`DashboardReadabilityPolicy.providerStatus`). Task 7 fixes that neutral state with a test, and a failure from a manual run keeps its own reason line beside the caption.
2. **The legacy switch.** Spec §4 says `claudeIsShown` does not read the `needlbar.menuBar.claude.enabled` flag. `claudeIsShown` never reads `ModuleConfiguration.claude`. The same key is still a last fallback inside `ModuleConfiguration.providerVisible` (`ModuleConfiguration.swift:210-216`) when no newer visibility key exists, and that fallback also decides what the menu bar and dashboard draw. `claudeIsShown` takes the resolved `SystemMonitorConfiguration`, so it always agrees with what is drawn. Task 2 tests that the flag alone cannot make Claude count as shown.
3. **Retry.** No built surface has a Retry that reaches `manualRefresh`: `MenuBarController.performRetryAction` has no caller outside tests, and the "Retry" button in `ProviderPopoverView` is used only by the private `LegacyMenuBarController`, which nothing constructs. The spec was corrected on 2026-11-16 to name Check now only, and every copy string here follows it.
4. **Already on.** The spec was amended on 2026-11-16: if the setting is already on at the first-run step, the controller records the answer and does not show it. `shouldShow` keeps its three parameters; the check is in `presentIfNeeded`, tested in Task 10.
5. **The window's title.** The spec's "Title" is the headline inside the window; the window's own title bar says "Needlbar".
6. **The window's content is AppKit.** A SwiftUI default button is not readable from a test; an `NSButton` with `keyEquivalent == "\r"` is. The window itself is an `NSWindow`, activated like `SettingsWindowController`.
7. **"Needlbar asks once" lands before the window.** The spec puts the README paragraph in the first pull request and the window in the second. Task 8 says in `docs/HANDOFF.md` and `docs/STATUS.md` that the window is not built yet, and Task 12 replaces that. Both parts must be merged before any release.
8. **Two documents outside spec §7.** `docs/releases/v0.3.15.md` still describes unconditional runs. It is the body of a release that was never published, the spec does not list it, and the spec requires a new release plan; Task 8 leaves it unchanged and records that in `docs/HANDOFF.md`. The inquiry to Anthropic is not in the repository, so "The inquiry to Anthropic is updated" becomes a recorded action for the user in `docs/HANDOFF.md` and `docs/STATUS.md`.

### 5. Test mechanics

- **What can fail first.** In Tasks 1 to 7, 10 and 11 the test step uses a type, a member or a parameter that does not exist yet, so its failing state is a build error and no test runs; the run step says which names the errors mention. Task 12's test compiles and fails at run time with one issue. Task 8 is documentation and has no failing phase, and says so.
- **Coordinator harness.** `Harness.startedAndIdle()` waits for one completed Claude run, which never comes while automatic runs are off. Task 4 adds `startedWithoutARun()`, which waits for the Codex and Cursor refresh instead. `advance(minutes:)` still waits for three sleeping loops, because the 60-second tick keeps running while off. `settle(watchingFor:)` is for negative checks only (`TestWaiting.swift`).
- **Timelines, checked against the schedule.** The tick fires at multiples of 60 s. Turning on at 420 s with no earlier start runs at 420 and then periodically at 1,320 and 2,220. A manual run at 0 followed by turning on at 60 queues nothing, and the periodic run starts at 900.
- **Hosted views.** `AccessibilityHostedView` reports buttons and the Settings switch (`AXCheckBox`) with their labels. It does not report a SwiftUI `Text` by label, so captions are asserted on the presentation and copy types, not through the hosted view.
- **Verified while writing this plan.** Every edit below was applied, in order and task by task, to a scratch copy of the repository at `946a389`, on local Swift 6.4 with a bridge built with its test feature. After each code task that task's filters were run there with `swift test --filter` and passed with the counts given. Task 12's failing run was executed and failed as described; the other failing runs are build errors by construction and were not executed. With everything applied, the whole Swift suite was run twice on the final tree and passed both times (52, 461, 379, 39 and 5 tests in its five test targets), the acceptance configuration ran `AcceptanceFixtureTests` (9 tests) and `AppDelegateLifecycle` (3 tests), and `scripts/tests/notarize-app-tests.sh` and `scripts/tests/widget-extension-search-guard-tests.sh` passed. Not done: `make test` as a whole, `make package`, the smoke scripts, CI's Xcode 16.2, and anything on screen. The window's layout in particular has only been measured (460 points wide), never seen. The repository itself was not changed.
- **One unrelated timing-sensitive test.** `cancelledWaiterDoesNotCancelSharedAnalyticsTask()` in `AnalyticsSnapshotStoreTests` failed once in an earlier full run of the suite made while writing this plan, passed in the three other full runs, and passed six times in a row when run alone. No file in this plan touches analytics. If it fails during verification, say so and rerun; do not change it as part of this work.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `Sources/NeedlbarCore/Refresh/ClaudeUsageProbeSchedule.swift` | When a run may start | `automaticRunsEnabled`, its setter, the gate, the refused-resume rule (Task 1) |
| `Sources/NeedlbarCore/Refresh/QuotaRefreshActivity.swift` | Trigger and attempt types | `automaticResumed` (Task 1) |
| `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift` | Starts and applies refreshes | Exhaustive switch and constructions (Task 1); the flag, the setter, `start()` (Task 4) |
| `Sources/NeedlbarCore/Configuration/ClaudeVisibility.swift` | `claudeIsShown` | Created (Task 2) |
| `Sources/Needlbar/App/ClaudeAutomaticChecksPreferences.swift` | The stored setting | Created (Task 3) |
| `Sources/Needlbar/App/AppDelegate.swift` | Composition root and lifecycle | Initial value (Task 4), relay (Task 5), actions (Task 6), first-run step (Task 12) |
| `Sources/Needlbar/App/ClaudeAutomaticRunsRelay.swift` | Preference and visibility to the coordinator, in order | Created (Task 5) |
| `Sources/Needlbar/App/ClaudeAutomaticChecksCopy.swift` | The approved in-app strings | Created (Task 6) |
| `Sources/Needlbar/Settings/SettingsActions.swift` | Actions shared by Settings and the dashboard | Carries the setting (Task 6) |
| `Sources/Needlbar/Settings/SettingsView.swift` | Settings panes | Toggle and caption in the Claude connection card (Task 6) |
| `Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift` | Dashboard presentation | `ClaudeAutomaticChecksPrompt`, `automaticChecksPrompt` (Task 7) |
| `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift` | Dashboard view | Caption and "Turn on" beside "Check now" (Task 7) |
| `Sources/Needlbar/MenuBar/MenuBarController.swift` | Owns the dashboard panel | Passes the state, observes it, handles "Turn on" (Task 7) |
| `Sources/Needlbar/App/ClaudeUsageOnboarding.swift` | First-run rule, copy and controller | Created (Task 10) |
| `Sources/Needlbar/App/ClaudeUsageOnboardingWindowController.swift` | The first-run window | Created (Task 11) |
| `Tests/NeedlbarCoreTests/ClaudeUsageProbeScheduleTests.swift` | Schedule behaviour | Existing constructions state `true`; new tests (Task 1) |
| `Tests/NeedlbarCoreTests/ClaudeVisibilityTests.swift` | `claudeIsShown` truth table | Created (Task 2) |
| `Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift` | Coordinator behaviour | Harness parameter and new tests (Task 4) |
| `Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift`, `Tests/NeedlbarCoreTests/UsageFileWatcherTests.swift`, `Tests/NeedlbarTests/ClaudeQuotaFreshnessPresentationTests.swift`, `Tests/NeedlbarTests/ClaudeStatusLineFallbackIntegrationTests.swift` | Existing coordinator constructions | Each passes `claudeAutomaticRunsAllowed: true` (Task 4) |
| `Tests/NeedlbarTests/ClaudeAutomaticChecksPreferencesTests.swift`, `ClaudeAutomaticRunsRelayTests.swift`, `ClaudeAutomaticChecksSettingsTests.swift`, `ClaudeAutomaticChecksDashboardTests.swift` | App-side tests | Created (Tasks 3, 5, 6, 7) |
| `Tests/NeedlbarTests/MenuBarControllerTests.swift` | Controller behaviour | Three tests and a helper (Task 7) |
| `Tests/NeedlbarTests/ClaudeUsageOnboardingTests.swift`, `ClaudeUsageOnboardingWindowTests.swift` | First-run tests | Created (Tasks 10, 11) |
| `Tests/NeedlbarTests/AppDelegateLifecycleTests.swift` | Lifecycle order | The new step (Task 12) |
| `README.md`, `docs/privacy.md`, `docs/providers/claude.md`, `docs/architecture.md`, `docs/HANDOFF.md`, `docs/STATUS.md`, the 2026-11-03 and 2026-11-12 specs | Current descriptions and records | Task 8; `HANDOFF`, `STATUS` and `providers/claude.md` again in Task 12 |

---

# Part 1 / PR 1: the gate, the setting, the controls and the documentation

Before Task 1:

```bash
git switch -c claude/claude-auto-checks-gate
```

### Task 1: The schedule gate and the `automaticResumed` trigger

**Files:**
- Modify: `Sources/NeedlbarCore/Refresh/ClaudeUsageProbeSchedule.swift:19,25-28,62-63,77`
- Modify: `Sources/NeedlbarCore/Refresh/QuotaRefreshActivity.swift:53`
- Modify: `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift:44,185,407`
- Test: `Tests/NeedlbarCoreTests/ClaudeUsageProbeScheduleTests.swift` (20 constructions, and new tests after line 189)

**Interfaces:**
- Consumes: nothing from another task.
- Produces, in `ClaudeUsageProbeSchedule`: `private(set) var automaticRunsEnabled: Bool`; `init(automaticRunsEnabled: Bool = false)`; `mutating func setAutomaticRunsEnabled(_ enabled: Bool)`. `request`, `dueTrigger`, `recordStart`, `recordSuccess` and `recordFailure` keep their signatures. In `QuotaRefreshTrigger`: `case automaticResumed`. `RefreshCoordinator` behaves as before.

- [ ] **Step 1: Make the existing schedule tests state the old behaviour, and write the failing tests**

Every existing test describes automatic runs that are on. Run:

```bash
perl -pi -e 's/ClaudeUsageProbeSchedule\(\)/ClaudeUsageProbeSchedule(automaticRunsEnabled: true)/g' Tests/NeedlbarCoreTests/ClaudeUsageProbeScheduleTests.swift
```

Then `grep -c "ClaudeUsageProbeSchedule(automaticRunsEnabled: true)" Tests/NeedlbarCoreTests/ClaudeUsageProbeScheduleTests.swift` prints `20`, and `grep -c "ClaudeUsageProbeSchedule()" Tests/NeedlbarCoreTests/ClaudeUsageProbeScheduleTests.swift` prints `0`.

In `Tests/NeedlbarCoreTests/ClaudeUsageProbeScheduleTests.swift`, replace

```swift
    }
}
```

with

```swift
    }

    // MARK: - Automatic runs off by default (spec 2026-11-16)

    @Test func automaticRunsAreOffByDefault() {
        #expect(!ClaudeUsageProbeSchedule().automaticRunsEnabled)
    }

    @Test func whileOffEveryAutomaticTriggerIsRefusedAndNothingIsLeftPending() {
        var schedule = ClaudeUsageProbeSchedule()
        for trigger in [QuotaRefreshTrigger.startup, .periodic, .windowReset, .backoffRetry, .automaticResumed] {
            #expect(schedule.request(trigger, now: start, inFlight: false) == .none, "\(trigger)")
            #expect(schedule.request(trigger, now: start, inFlight: true) == .none, "\(trigger)")
            #expect(schedule.pendingTrigger == nil, "\(trigger)")
        }
        // A manual run happened; a passed reset and a whole day still make nothing due.
        schedule.recordStart(at: start)
        #expect(schedule.dueTrigger(resetTimes: [at(60)], now: at(86_400), inFlight: false) == nil)
    }

    @Test func aManualRequestStartsWhileOffAndDoesNotTurnTheScheduleOn() {
        var schedule = ClaudeUsageProbeSchedule()
        #expect(schedule.request(.manual, now: start, inFlight: false) == .start)
        #expect(schedule.request(.manual, now: start, inFlight: true) == .none)
        #expect(!schedule.automaticRunsEnabled)
    }

    @Test func whileOffAFailureCreatesNoBackoffOrRetry() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.recordStart(at: start)
        schedule.recordFailure(trigger: .periodic, at: start, retriesWhenBackoffEnds: true)
        schedule.recordFailure(trigger: .manual, at: start, retriesWhenBackoffEnds: true)
        #expect(schedule.backoffUntil == nil)
        #expect(schedule.consecutiveAutomaticFailures == 0)
        schedule.setAutomaticRunsEnabled(true)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(300), inFlight: false) == nil, "no retry was left behind")
        #expect(schedule.dueTrigger(resetTimes: [], now: at(900), inFlight: false) == .periodic)
    }

    @Test func turningOffClearsPendingRetryAndBackoffAndKeepsTheLastStart() {
        var schedule = ClaudeUsageProbeSchedule(automaticRunsEnabled: true)
        schedule.recordStart(at: start)
        schedule.recordFailure(trigger: .startup, at: start, retriesWhenBackoffEnds: true)
        #expect(schedule.request(.startup, now: at(60), inFlight: false) == .none)
        #expect(schedule.pendingTrigger == .startup)
        #expect(schedule.backoffUntil == at(300))
        schedule.setAutomaticRunsEnabled(false)
        #expect(schedule.pendingTrigger == nil)
        #expect(schedule.backoffUntil == nil)
        #expect(schedule.consecutiveAutomaticFailures == 0)
        #expect(schedule.lastStartedAt == start)
        schedule.setAutomaticRunsEnabled(true)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(300), inFlight: false) == nil, "the retry was cleared")
        #expect(schedule.dueTrigger(resetTimes: [], now: at(900), inFlight: false) == .periodic)
    }

    @Test func turningOnLetsADueRunStart() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.setAutomaticRunsEnabled(true)
        #expect(schedule.request(.automaticResumed, now: start, inFlight: false) == .start)
        schedule.recordStart(at: start)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(900), inFlight: false) == .periodic)
    }

    @Test func aRefusedResumeIsQueuedOnlyWhenNoRunHasStarted() {
        // After a restart an older run can still be in flight with no start recorded.
        var fresh = ClaudeUsageProbeSchedule(automaticRunsEnabled: true)
        #expect(fresh.request(.automaticResumed, now: start, inFlight: true) == .none)
        #expect(fresh.pendingTrigger == .automaticResumed)

        // Turning on right after Check now: nothing is queued, the periodic run follows.
        var afterCheckNow = ClaudeUsageProbeSchedule()
        #expect(afterCheckNow.request(.manual, now: start, inFlight: false) == .start)
        afterCheckNow.recordStart(at: start)
        afterCheckNow.setAutomaticRunsEnabled(true)
        #expect(afterCheckNow.request(.automaticResumed, now: at(60), inFlight: true) == .none)
        #expect(afterCheckNow.request(.automaticResumed, now: at(60), inFlight: false) == .none)
        #expect(afterCheckNow.pendingTrigger == nil)
        #expect(afterCheckNow.dueTrigger(resetTimes: [], now: at(300), inFlight: false) == nil)
        #expect(afterCheckNow.dueTrigger(resetTimes: [], now: at(900), inFlight: false) == .periodic)
    }

    @Test func settingTheSameValueChangesNothing() {
        var schedule = ClaudeUsageProbeSchedule(automaticRunsEnabled: true)
        schedule.recordStart(at: start)
        schedule.recordFailure(trigger: .startup, at: start, retriesWhenBackoffEnds: true)
        let before = schedule
        schedule.setAutomaticRunsEnabled(true)
        #expect(schedule == before)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeUsageProbeSchedule`
Expected: FAIL at build time. `ClaudeUsageProbeScheduleTests.swift` does not compile: the errors name the `automaticRunsEnabled` argument and member, `setAutomaticRunsEnabled` and `automaticResumed`. No test runs, and make ends with `make: *** [swift-test] Error 1`.

- [ ] **Step 3: Add the trigger**

In `Sources/NeedlbarCore/Refresh/QuotaRefreshActivity.swift`, replace

```swift
    case windowReset, backoffRetry, periodic
}
```

with

```swift
    case windowReset, backoffRetry, periodic
    /// The one run requested when automatic Claude runs are turned on, or Claude is
    /// shown again, during a session. It keeps `startup` out of the middle of a log.
    case automaticResumed
}
```

- [ ] **Step 4: Add the gate to the schedule**

In `Sources/NeedlbarCore/Refresh/ClaudeUsageProbeSchedule.swift`, replace

```swift
    static let backoffSteps: [TimeInterval] = [5 * 60, 10 * 60, 20 * 60, 30 * 60]

    private(set) var lastStartedAt: Date?
```

with

```swift
    static let backoffSteps: [TimeInterval] = [5 * 60, 10 * 60, 20 * 60, 30 * 60]

    /// Off by default (spec 2026-11-16): while off, only a manual request starts a run.
    private(set) var automaticRunsEnabled: Bool
    private(set) var lastStartedAt: Date?
```

In `Sources/NeedlbarCore/Refresh/ClaudeUsageProbeSchedule.swift`, replace

```swift
    private var retryPending = false

    mutating func request(_ trigger: QuotaRefreshTrigger, now: Date, inFlight: Bool) -> Action {
        if trigger == .manual { return inFlight ? .none : .start }
        guard !inFlight, automaticRunIsAllowed(now: now) else {
            pendingTrigger = pendingTrigger ?? trigger
            return .none
```

with

```swift
    private var retryPending = false

    init(automaticRunsEnabled: Bool = false) {
        self.automaticRunsEnabled = automaticRunsEnabled
    }

    /// Turning off drops every queued or delayed automatic run and keeps
    /// `lastStartedAt`, so the five-minute floor still holds after turning on again.
    /// A call that does not change the value does nothing.
    mutating func setAutomaticRunsEnabled(_ enabled: Bool) {
        guard enabled != automaticRunsEnabled else { return }
        automaticRunsEnabled = enabled
        guard !enabled else { return }
        pendingTrigger = nil
        retryPending = false
        backoffUntil = nil
        consecutiveAutomaticFailures = 0
    }

    mutating func request(_ trigger: QuotaRefreshTrigger, now: Date, inFlight: Bool) -> Action {
        if trigger == .manual { return inFlight ? .none : .start }
        // While off a refused request leaves nothing pending.
        guard automaticRunsEnabled else { return .none }
        guard !inFlight, automaticRunIsAllowed(now: now) else {
            // A refused resume is queued only when no run has started yet. Otherwise
            // the periodic run follows 15 minutes after the last start, so turning on
            // right after Check now starts no second run inside the floor.
            if trigger != .automaticResumed || lastStartedAt == nil {
                pendingTrigger = pendingTrigger ?? trigger
            }
            return .none
```

In `Sources/NeedlbarCore/Refresh/ClaudeUsageProbeSchedule.swift`, replace

```swift
    /// automatic backoff, and it neither creates nor cancels an automatic retry.
    mutating func recordFailure(trigger: QuotaRefreshTrigger, at date: Date, retriesWhenBackoffEnds: Bool) {
        guard trigger != .manual else { return }
        retryPending = retriesWhenBackoffEnds
```

with

```swift
    /// automatic backoff, and it neither creates nor cancels an automatic retry.
    /// While automatic runs are off no failure does, so no backoff or retry can
    /// exist while off, even for an automatic run that was in flight at turn-off.
    mutating func recordFailure(trigger: QuotaRefreshTrigger, at date: Date, retriesWhenBackoffEnds: Bool) {
        guard trigger != .manual, automaticRunsEnabled else { return }
        retryPending = retriesWhenBackoffEnds
```

In `Sources/NeedlbarCore/Refresh/ClaudeUsageProbeSchedule.swift`, replace

```swift
    private func automaticRunIsAllowed(now: Date) -> Bool {
        if let lastStartedAt {
```

with

```swift
    private func automaticRunIsAllowed(now: Date) -> Bool {
        guard automaticRunsEnabled else { return false }
        if let lastStartedAt {
```

- [ ] **Step 5: Keep the coordinator compiling and unchanged**

The coordinator's exhaustive switch needs the new case. Its two schedule constructions state `true`, so its behaviour does not change until Task 4.

In `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`, replace

```swift
    private let claudeUsageAttemptLedger: QuotaAttemptLedger
    private var claudeUsageSchedule = ClaudeUsageProbeSchedule()
    /// Retained until the physical call returns, so runs never overlap across a restart.
```

with

```swift
    private let claudeUsageAttemptLedger: QuotaAttemptLedger
    private var claudeUsageSchedule = ClaudeUsageProbeSchedule(automaticRunsEnabled: true)
    /// Retained until the physical call returns, so runs never overlap across a restart.
```

In `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`, replace

```swift
        claudeUsageAttemptLedger.advance(to: runGeneration)
        claudeUsageSchedule = ClaudeUsageProbeSchedule()
        isRunning = true
```

with

```swift
        claudeUsageAttemptLedger.advance(to: runGeneration)
        claudeUsageSchedule = ClaudeUsageProbeSchedule(automaticRunsEnabled: true)
        isRunning = true
```

In `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`, replace

```swift
            return last < scheduledDueAt
        case .startup, .manual, .popover, .windowReset, .backoffRetry, .periodic:
            return true
```

with

```swift
            return last < scheduledDueAt
        case .startup, .manual, .popover, .windowReset, .backoffRetry, .periodic, .automaticResumed:
            return true
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeUsageProbe`
Expected: `Test run with 1 test in 1 suite passed` and `Test run with 55 tests in 2 suites passed`, and make exits 0. The second line covers the 26 schedule tests (18 existing, 8 new) and the unchanged coordinator tests.

- [ ] **Step 7: Commit**

```bash
git add Sources/NeedlbarCore/Refresh/ClaudeUsageProbeSchedule.swift \
  Sources/NeedlbarCore/Refresh/QuotaRefreshActivity.swift \
  Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift \
  Tests/NeedlbarCoreTests/ClaudeUsageProbeScheduleTests.swift
git commit -m "feat(claude): gate automatic /usage runs in the schedule" \
  -m "ClaudeUsageProbeSchedule gains automaticRunsEnabled, off by default. While off it refuses every non-manual trigger, queues nothing and records no backoff. The coordinator still builds it enabled, so nothing changes for the app yet." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `claudeIsShown`

**Files:**
- Create: `Sources/NeedlbarCore/Configuration/ClaudeVisibility.swift`
- Test: `Tests/NeedlbarCoreTests/ClaudeVisibilityTests.swift` (new)

**Interfaces:**
- Consumes: `SystemMonitorConfiguration.menuBarVisibleModules`, `.dashboardVisibleModules` and `.ai`, and `AIProviderDisplayPreference.menuBarVisible` and `.dashboardVisible` (`Sources/NeedlbarCore/SystemMetrics/SystemMetricModels.swift:41-66,216-253`).
- Produces: `public func claudeIsShown(_ configuration: SystemMonitorConfiguration) -> Bool`.

- [ ] **Step 1: Write the failing test**

Create `Tests/NeedlbarCoreTests/ClaudeVisibilityTests.swift`:

```swift
import Foundation
import Testing
@testable import NeedlbarCore

@Suite("ClaudeIsShown")
struct ClaudeVisibilityTests {
    @Test func claudeIsShownWhenEitherSurfaceShowsItsAISectionAndClaudeInIt() {
        for aiOnMenuBar in [false, true] {
            for claudeOnMenuBar in [false, true] {
                for aiOnDashboard in [false, true] {
                    for claudeOnDashboard in [false, true] {
                        var configuration = SystemMonitorConfiguration(
                            visibleModules: aiOnMenuBar ? [.cpu, .ai] : [.cpu],
                            dashboardVisibleModules: aiOnDashboard ? [.memory, .ai] : [.memory])
                        configuration.ai[.claude] = AIProviderDisplayPreference(
                            isVisible: claudeOnMenuBar, dashboardVisible: claudeOnDashboard)
                        let expected = (aiOnMenuBar && claudeOnMenuBar) || (aiOnDashboard && claudeOnDashboard)
                        #expect(
                            claudeIsShown(configuration) == expected,
                            "menu bar \(aiOnMenuBar)/\(claudeOnMenuBar), dashboard \(aiOnDashboard)/\(claudeOnDashboard)")
                    }
                }
            }
        }
    }

    @Test func otherProvidersDoNotCount() {
        var configuration = SystemMonitorConfiguration(visibleModules: [.ai])
        configuration.ai[.claude] = AIProviderDisplayPreference(isVisible: false)
        configuration.ai[.codex] = AIProviderDisplayPreference(isVisible: true)
        configuration.ai[.cursor] = AIProviderDisplayPreference(isVisible: true)
        #expect(!claudeIsShown(configuration))
    }

    @Test func aMissingClaudePreferenceCountsAsVisibleLikeTheRenderers() {
        var configuration = SystemMonitorConfiguration(visibleModules: [.ai])
        configuration.ai[.claude] = nil
        #expect(claudeIsShown(configuration))
    }

    @Test func theDefaultConfigurationShowsClaude() {
        #expect(claudeIsShown(SystemMonitorConfiguration()))
    }

    @Test func theLegacyMenuBarSwitchCannotOverrideTheNewerKeys() throws {
        let name = "ClaudeIsShown.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "needlbar.systemMonitor.ai.claude.menuBar.visible")
        defaults.set(false, forKey: "needlbar.systemMonitor.ai.claude.dashboard.visible")
        defaults.set(true, forKey: "needlbar.menuBar.claude.enabled")
        let configuration = ModuleConfiguration(defaults: defaults)
        #expect(configuration.claude.isEnabled)
        #expect(!claudeIsShown(configuration.systemMonitor))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeVisibility`
Expected: FAIL at build time: `ClaudeVisibilityTests.swift` cannot find `claudeIsShown` in scope. make ends with `make: *** [swift-test] Error 1`.

- [ ] **Step 3: Write the function**

A missing Claude preference counts as visible, as it does in `MenuBarDashboardRenderer` and `SystemDashboardPresentation`.

Create `Sources/NeedlbarCore/Configuration/ClaudeVisibility.swift`:

```swift
import Foundation

/// Whether Claude is shown anywhere the user can see it in the app: in the AI
/// module on the menu bar, or in the AI section of the dashboard. Automatic
/// `/usage` runs pause while this is false. The widget and notifications do not
/// count. The legacy `needlbar.menuBar.claude.enabled` flag matters only as
/// `ModuleConfiguration`'s last fallback when no newer visibility key exists.
public func claudeIsShown(_ configuration: SystemMonitorConfiguration) -> Bool {
    let claude = configuration.ai[.claude] ?? AIProviderDisplayPreference()
    let onMenuBar = configuration.menuBarVisibleModules.contains(.ai) && claude.menuBarVisible
    let onDashboard = configuration.dashboardVisibleModules.contains(.ai) && claude.dashboardVisible
    return onMenuBar || onDashboard
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeVisibility`
Expected: `Test run with 5 tests in 1 suite passed`, and make exits 0.

- [ ] **Step 5: Commit**

```bash
git add Sources/NeedlbarCore/Configuration/ClaudeVisibility.swift \
  Tests/NeedlbarCoreTests/ClaudeVisibilityTests.swift
git commit -m "feat(claude): add claudeIsShown for the menu bar and the dashboard" \
  -m "True when the AI module and Claude are visible on the menu bar, or the AI section and Claude are visible on the dashboard. The widget and notifications do not count." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The stored setting

**Files:**
- Create: `Sources/Needlbar/App/ClaudeAutomaticChecksPreferences.swift`
- Test: `Tests/NeedlbarTests/ClaudeAutomaticChecksPreferencesTests.swift` (new)

**Interfaces:**
- Consumes: nothing from another task. It follows `QuotaNotificationPreferences` (`Sources/Needlbar/Notifications/QuotaNotificationPreferences.swift`).
- Produces: `@MainActor public final class ClaudeAutomaticChecksPreferences: ObservableObject` with `static let key = "needlbar.claude.automaticUsageChecks.enabled"`, `@Published public private(set) var isEnabled: Bool`, `public init(defaults: UserDefaults = .standard)` and `func setEnabled(_ enabled: Bool)`.

- [ ] **Step 1: Write the failing test**

Create `Tests/NeedlbarTests/ClaudeAutomaticChecksPreferencesTests.swift`:

```swift
import Foundation
import Testing
@testable import NeedlbarApp

@Suite("ClaudeAutomaticChecksPreferences")
@MainActor
struct ClaudeAutomaticChecksPreferencesTests {
    private static func makeDefaults() throws -> (UserDefaults, String) {
        let name = "ClaudeAutomaticChecks.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    @Test func aMissingValueMeansOff() throws {
        let (defaults, name) = try Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(defaults.object(forKey: "needlbar.claude.automaticUsageChecks.enabled") == nil)
        #expect(!ClaudeAutomaticChecksPreferences(defaults: defaults).isEnabled)
    }

    @Test func theChoicePersistsUnderTheSpecifiedKey() throws {
        let (defaults, name) = try Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = ClaudeAutomaticChecksPreferences(defaults: defaults)
        preferences.setEnabled(true)
        #expect(preferences.isEnabled)
        #expect(defaults.object(forKey: "needlbar.claude.automaticUsageChecks.enabled") as? Bool == true)
        #expect(ClaudeAutomaticChecksPreferences(defaults: defaults).isEnabled)
        preferences.setEnabled(false)
        #expect(!preferences.isEnabled)
        #expect(!ClaudeAutomaticChecksPreferences(defaults: defaults).isEnabled)
    }

    @Test func aChangeIsPublished() throws {
        let (defaults, name) = try Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = ClaudeAutomaticChecksPreferences(defaults: defaults)
        var seen: [Bool] = []
        let observation = preferences.$isEnabled.sink { seen.append($0) }
        preferences.setEnabled(true)
        preferences.setEnabled(false)
        observation.cancel()
        #expect(seen == [false, true, false])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeAutomaticChecksPreferences`
Expected: FAIL at build time: the test file cannot find `ClaudeAutomaticChecksPreferences` in scope. make ends with `make: *** [swift-test] Error 1`.

- [ ] **Step 3: Write the preference**

Create `Sources/Needlbar/App/ClaudeAutomaticChecksPreferences.swift`:

```swift
import Combine
import Foundation

/// Whether Needlbar may start `claude` to run `/usage` without a click. Off by
/// default, for new installs and for people updating: a missing value means off.
@MainActor
public final class ClaudeAutomaticChecksPreferences: ObservableObject {
    static let key = "needlbar.claude.automaticUsageChecks.enabled"

    @Published public private(set) var isEnabled: Bool

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.key)
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.key)
        isEnabled = enabled
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeAutomaticChecksPreferences`
Expected: `Test run with 3 tests in 1 suite passed`, and make exits 0.

- [ ] **Step 5: Commit**

```bash
git add Sources/Needlbar/App/ClaudeAutomaticChecksPreferences.swift \
  Tests/NeedlbarTests/ClaudeAutomaticChecksPreferencesTests.swift
git commit -m "feat(claude): store the automatic checks setting, off by default" \
  -m "The key is needlbar.claude.automaticUsageChecks.enabled. A missing value means off, so the setting is off for new installs and after an update." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The coordinator flag

**Files:**
- Modify: `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift:44,97,111,131,159,185,242`
- Modify: `Sources/Needlbar/App/AppDelegate.swift:156,184,206`
- Test: `Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift:136,599,617,627`
- Test: `Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift` (41 constructions), `Tests/NeedlbarCoreTests/UsageFileWatcherTests.swift:107`, `Tests/NeedlbarTests/ClaudeQuotaFreshnessPresentationTests.swift:245`, `Tests/NeedlbarTests/ClaudeStatusLineFallbackIntegrationTests.swift:34`

**Interfaces:**
- Consumes: from Task 1, `ClaudeUsageProbeSchedule(automaticRunsEnabled:)`, `setAutomaticRunsEnabled(_:)` and `QuotaRefreshTrigger.automaticResumed`. From Task 2, `claudeIsShown(_:)`. From Task 3, `ClaudeAutomaticChecksPreferences.isEnabled`.
- Produces: both `RefreshCoordinator` initializers take `claudeAutomaticRunsAllowed: Bool`, with no default, between `claudeUsageRepository:` and `store:`. `public func setClaudeAutomaticRunsAllowed(_ allowed: Bool)` on the actor. `AppDelegate` holds `private let claudeAutomaticChecks: ClaudeAutomaticChecksPreferences` and passes the initial value. Later changes of the setting do not reach the coordinator until Task 5.

- [ ] **Step 1: State the flag in every existing test construction**

`store:` follows `claudeUsageRepository:` or `quotaRepository:` in every call and appears once per call, so the new argument goes directly before it. Run:

```bash
perl -0pi -e 's/(RefreshCoordinator\((?:(?!\bstore:).)*?)(\bstore:)/$1claudeAutomaticRunsAllowed: true, $2/gs' Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift Tests/NeedlbarCoreTests/UsageFileWatcherTests.swift Tests/NeedlbarTests/ClaudeQuotaFreshnessPresentationTests.swift Tests/NeedlbarTests/ClaudeStatusLineFallbackIntegrationTests.swift
```

Then `grep -o "claudeAutomaticRunsAllowed: true, store:" <file> | wc -l` prints `41` for `RefreshCoordinatorTests.swift` and `1` for each of the other three files, which equals `grep -c "RefreshCoordinator(" <file>` for each of them.

The harness of the Claude coordinator tests takes the value as a parameter, default on, and gains a start that does not wait for a Claude run. The new tests go before `// MARK: - Manual`.

In `Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift`, replace

```swift
        #expect(harness.probe.startTimes.last == reset.addingTimeInterval(900))
        #expect(harness.events.values.last?.trigger == .periodic)
        await harness.coordinator.stop()
    }
```

with

```swift
        #expect(harness.probe.startTimes.last == reset.addingTimeInterval(900))
        #expect(harness.events.values.last?.trigger == .periodic)
        await harness.coordinator.stop()
    }

    // MARK: - Automatic runs are opt-in (spec 2026-11-16)

    @Test func withAutomaticRunsOffNothingRunsOverManyTicks() async throws {
        let harness = Harness(automaticRuns: false)
        await harness.startedWithoutARun()
        await harness.advance(minutes: 45)
        await settle(watchingFor: { harness.probe.callCount > 0 })
        #expect(harness.probe.callCount == 0)
        #expect(harness.events.values.isEmpty)
        await harness.coordinator.stop()
    }

    @Test func aFailedManualRunWhileOffGivesNoLaterRun() async throws {
        let harness = Harness(automaticRuns: false)
        harness.probe.script(.result(providerUnavailable()))
        await harness.startedWithoutARun()
        await harness.coordinator.manualRefresh()
        await harness.waitUntilCompletedRuns(1)
        // Long enough for every backoff step and the periodic interval.
        await harness.advance(minutes: 45)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1, "no backoff or retry exists while off")
        #expect(harness.probe.triggersSeen(in: harness.events) == [.manual])
        await harness.coordinator.stop()
    }

    @Test func anAutomaticRunThatFailsAfterTurningOffLeavesNoRetry() async throws {
        let harness = Harness()
        harness.probe.holdNext()
        harness.probe.script(.result(providerUnavailable()))
        await harness.coordinator.start()
        await harness.probe.waitUntilHeld()
        await harness.coordinator.setClaudeAutomaticRunsAllowed(false)
        harness.probe.release()
        await harness.waitUntilCompletedRuns(1)
        await harness.other.waitUntilCallCount(1)
        await harness.advance(minutes: 45)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1)
        await harness.coordinator.stop()
    }

    @Test func turningOnRightAfterCheckNowStartsNoSecondRunInsideTheFloor() async throws {
        let harness = Harness(automaticRuns: false)
        await harness.startedWithoutARun()
        await harness.coordinator.manualRefresh()
        await harness.waitUntilCompletedRuns(1)
        await harness.advance(minutes: 1)
        await harness.coordinator.setClaudeAutomaticRunsAllowed(true)
        await harness.advance(minutes: 13)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1, "nothing is queued; the periodic run follows the manual one")
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)
        #expect(harness.probe.startTimes.map { $0.timeIntervalSince(Self.start) } == [0, 900])
        #expect(harness.probe.triggersSeen(in: harness.events) == [.manual, .periodic])
        await harness.coordinator.stop()
    }

    @Test func onOffOnWithinFiveMinutesStartsNoExtraRun() async throws {
        let harness = Harness()
        await harness.startedAndIdle()
        await harness.advance(minutes: 1)
        await harness.coordinator.setClaudeAutomaticRunsAllowed(false)
        await harness.advance(minutes: 1)
        await harness.coordinator.setClaudeAutomaticRunsAllowed(true)
        await harness.advance(minutes: 12)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1)
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)
        #expect(harness.probe.startTimes.map { $0.timeIntervalSince(Self.start) } == [0, 900])
        #expect(harness.probe.triggersSeen(in: harness.events) == [.startup, .periodic])
        await harness.coordinator.stop()
    }

    @Test func startWithAutomaticRunsOnGivesOneStartupRunAndNoResume() async throws {
        let harness = Harness()
        await harness.startedAndIdle()
        // The value does not change, so this does nothing.
        await harness.coordinator.setClaudeAutomaticRunsAllowed(true)
        await harness.advance(minutes: 6)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1)
        #expect(harness.probe.triggersSeen(in: harness.events) == [.startup])
        await harness.coordinator.stop()
    }

    @Test func turningOnStartsOneResumedRunThenPeriodicRuns() async throws {
        let harness = Harness(automaticRuns: false)
        await harness.startedWithoutARun()
        await harness.advance(minutes: 7)
        await harness.coordinator.setClaudeAutomaticRunsAllowed(true)
        await harness.probe.waitUntilCallCount(1)
        await harness.waitUntilCompletedRuns(1)
        await harness.coordinator.setClaudeAutomaticRunsAllowed(true)
        await harness.advance(minutes: 14)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1, "exactly one resumed run")
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)
        await harness.advance(minutes: 15)
        await harness.probe.waitUntilCallCount(3)
        await harness.waitUntilCompletedRuns(3)
        #expect(harness.probe.startTimes.map { $0.timeIntervalSince(Self.start) } == [420, 1_320, 2_220])
        #expect(harness.probe.triggersSeen(in: harness.events) == [.automaticResumed, .periodic, .periodic])
        await harness.coordinator.stop()
    }

    @Test func turningOffWithARunInFlightLetsItFinishAndAppliesItsReading() async throws {
        let harness = Harness()
        harness.probe.holdNext()
        await harness.coordinator.start()
        await harness.probe.waitUntilHeld()
        await harness.coordinator.setClaudeAutomaticRunsAllowed(false)
        harness.probe.release()
        await harness.waitUntilCompletedRuns(1)
        #expect(await harness.store.snapshot(for: .claude).quota != nil, "the reading is applied")
        #expect(harness.probe.cancelledThrough.isEmpty, "turning off never cancels")
        await harness.other.waitUntilCallCount(1)
        await harness.advance(minutes: 30)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1)
        await harness.coordinator.stop()
    }

    @Test func theFlagIsOnlyStoredWhileStoppedAndSurvivesStopAndStart() async throws {
        let harness = Harness(automaticRuns: false)
        await harness.coordinator.setClaudeAutomaticRunsAllowed(true)
        await settle(watchingFor: { harness.probe.callCount > 0 })
        #expect(harness.probe.callCount == 0, "while stopped the setter only stores the value")
        await harness.coordinator.start()
        await harness.waitUntilCompletedRuns(1)
        #expect(harness.probe.triggersSeen(in: harness.events) == [.startup])

        await harness.coordinator.setClaudeAutomaticRunsAllowed(false)
        await harness.coordinator.stop()
        await harness.coordinator.start()
        await harness.other.waitUntilCallCount(2)
        await harness.advance(minutes: 20)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1, "off survives a restart")
        await harness.coordinator.stop()
    }
```

In `Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift`, replace

```swift
    let coordinator: RefreshCoordinator

    init(claudeRepository: Bool = true, claudeTotal: UInt64 = 0) {
        let clock = ManualClock(now: ClaudeUsageProbeCoordinatorTests.start)
```

with

```swift
    let coordinator: RefreshCoordinator

    init(claudeRepository: Bool = true, claudeTotal: UInt64 = 0, automaticRuns: Bool = true) {
        let clock = ManualClock(now: ClaudeUsageProbeCoordinatorTests.start)
```

In `Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift`, replace

```swift
            claudeUsageRepository: claudeRepository ? probe : nil,
            store: store,
```

with

```swift
            claudeUsageRepository: claudeRepository ? probe : nil,
            claudeAutomaticRunsAllowed: automaticRuns,
            store: store,
```

In `Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift`, replace

```swift
        await waitUntilCompletedRuns(1)
        await other.waitUntilCallCount(1)
```

with

```swift
        await waitUntilCompletedRuns(1)
        await other.waitUntilCallCount(1)
    }

    /// For a coordinator whose automatic runs are off: start, and wait for the
    /// Codex and Cursor refresh instead of a Claude run that must not come.
    func startedWithoutARun() async {
        await coordinator.start()
        await other.waitUntilCallCount(1)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeUsageProbe`
Expected: FAIL at build time. The test files do not compile: the errors name the extra argument `claudeAutomaticRunsAllowed` in the `RefreshCoordinator` calls and the missing member `setClaudeAutomaticRunsAllowed`. No test runs, and make ends with `make: *** [swift-test] Error 1`.

- [ ] **Step 3: Add the flag, the setter and the gated start to the coordinator**

In `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`, replace

```swift
    private let claudeUsageAttemptLedger: QuotaAttemptLedger
    private var claudeUsageSchedule = ClaudeUsageProbeSchedule(automaticRunsEnabled: true)
    /// Retained until the physical call returns, so runs never overlap across a restart.
```

with

```swift
    private let claudeUsageAttemptLedger: QuotaAttemptLedger
    /// Whether an automatic Claude run may start: the user's setting and Claude
    /// being shown, computed by the app. It survives `stop()` and `start()`.
    private var claudeAutomaticRunsAllowed: Bool
    private var claudeUsageSchedule: ClaudeUsageProbeSchedule
    /// Retained until the physical call returns, so runs never overlap across a restart.
```

In `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`, replace

```swift
    public init(
        usageRepository: any UsageRepository,
        quotaRepository: any QuotaRepository,
        claudeUsageRepository: (any QuotaRepository)? = nil,
        store: ProviderSnapshotStore,
        clock: any ClockLike = SystemClock(),
        lastQuotaSuccessfulAt: Date? = nil,
        usageFileWatcher: (any UsageFileWatching)? = nil,
```

with

```swift
    public init(
        usageRepository: any UsageRepository,
        quotaRepository: any QuotaRepository,
        claudeUsageRepository: (any QuotaRepository)? = nil,
        claudeAutomaticRunsAllowed: Bool,
        store: ProviderSnapshotStore,
        clock: any ClockLike = SystemClock(),
        lastQuotaSuccessfulAt: Date? = nil,
        usageFileWatcher: (any UsageFileWatching)? = nil,
```

In `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`, replace

```swift
            claudeUsageRepository: claudeUsageRepository,
            store: store,
```

with

```swift
            claudeUsageRepository: claudeUsageRepository,
            claudeAutomaticRunsAllowed: claudeAutomaticRunsAllowed,
            store: store,
```

In `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`, replace

```swift
        claudeUsageRepository: (any QuotaRepository)? = nil,
        store: ProviderSnapshotStore,
```

with

```swift
        claudeUsageRepository: (any QuotaRepository)? = nil,
        claudeAutomaticRunsAllowed: Bool,
        store: ProviderSnapshotStore,
```

In `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`, replace

```swift
        self.claudeUsageRepository = claudeUsageRepository
        self.backgroundQuotaOperationCompleted = backgroundQuotaOperationCompleted
```

with

```swift
        self.claudeUsageRepository = claudeUsageRepository
        self.claudeAutomaticRunsAllowed = claudeAutomaticRunsAllowed
        self.claudeUsageSchedule = ClaudeUsageProbeSchedule(automaticRunsEnabled: claudeAutomaticRunsAllowed)
        self.backgroundQuotaOperationCompleted = backgroundQuotaOperationCompleted
```

In `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`, replace

```swift
        claudeUsageAttemptLedger.advance(to: runGeneration)
        claudeUsageSchedule = ClaudeUsageProbeSchedule(automaticRunsEnabled: true)
        isRunning = true
```

with

```swift
        claudeUsageAttemptLedger.advance(to: runGeneration)
        claudeUsageSchedule = ClaudeUsageProbeSchedule(automaticRunsEnabled: claudeAutomaticRunsAllowed)
        isRunning = true
```

In `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`, replace

```swift
        requestQuotaRefresh(trigger: .popover)
    }
```

with

```swift
        requestQuotaRefresh(trigger: .popover)
    }

    /// Turns automatic Claude runs on or off. Manual runs are never affected.
    /// While stopped it only stores the value, which `start()` then uses. Turning
    /// off drops queued and delayed runs and leaves a run in flight alone: it ends
    /// within its own limit and its reading is applied. Turning on requests one
    /// `automaticResumed` run through the automatic path, so the five-minute floor
    /// still applies. A call that does not change the value does nothing.
    public func setClaudeAutomaticRunsAllowed(_ allowed: Bool) {
        guard allowed != claudeAutomaticRunsAllowed else { return }
        claudeAutomaticRunsAllowed = allowed
        guard isRunning else { return }
        claudeUsageSchedule.setAutomaticRunsEnabled(allowed)
        if allowed { requestClaudeUsageProbe(trigger: .automaticResumed) }
    }
```

- [ ] **Step 4: Pass the initial value from the app**

The app target does not build until its one construction states the flag. It passes the stored setting and Claude being shown, so from this commit on the app starts no automatic run unless the setting is on.

In `Sources/Needlbar/App/AppDelegate.swift`, replace

```swift
    private let notificationService: QuotaNotificationService
    private let widgetPublisher: WidgetProjectionPublisher?
```

with

```swift
    private let notificationService: QuotaNotificationService
    private let claudeAutomaticChecks: ClaudeAutomaticChecksPreferences
    private let widgetPublisher: WidgetProjectionPublisher?
```

In `Sources/Needlbar/App/AppDelegate.swift`, replace

```swift
        let notificationPreferences = QuotaNotificationPreferences()
        self.snapshotStore = snapshotStore
```

with

```swift
        let notificationPreferences = QuotaNotificationPreferences()
        let claudeAutomaticChecks = ClaudeAutomaticChecksPreferences()
        self.claudeAutomaticChecks = claudeAutomaticChecks
        self.snapshotStore = snapshotStore
```

In `Sources/Needlbar/App/AppDelegate.swift`, replace

```swift
                claudeUsageRepository: ClaudeUsageProbeSwitch.isDisabled() ? nil : RustQuotaRepository(bridge: bridge),
                store: snapshotStore,
```

with

```swift
                claudeUsageRepository: ClaudeUsageProbeSwitch.isDisabled() ? nil : RustQuotaRepository(bridge: bridge),
                // Off unless the user turned automatic checks on, and paused while
                // Claude is hidden.
                claudeAutomaticRunsAllowed: claudeAutomaticChecks.isEnabled
                    && claudeIsShown(moduleConfiguration.systemMonitor),
                store: snapshotStore,
```

- [ ] **Step 5: Confirm no construction is left without the flag**

Run: `grep -rn "claudeAutomaticRunsAllowed: " Tests Sources/Needlbar | wc -l`
Expected: `46`: 41, 1, 1 and 1 in the four files of Step 1, the harness, and `AppDelegate.swift`. That equals the number of `RefreshCoordinator(` constructions outside `RefreshCoordinator.swift`.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeUsageProbe`
Expected: `Test run with 1 test in 1 suite passed` and `Test run with 64 tests in 2 suites passed`, and make exits 0. The second line includes the nine new coordinator tests.

Run: `make swift-test SWIFT_TEST_FILTER=RefreshCoordinator`
Expected: `Test run with 53 tests in 1 suite passed`, and make exits 0.

- [ ] **Step 7: Commit**

```bash
git add Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift \
  Sources/Needlbar/App/AppDelegate.swift \
  Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift \
  Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift \
  Tests/NeedlbarCoreTests/UsageFileWatcherTests.swift \
  Tests/NeedlbarTests/ClaudeQuotaFreshnessPresentationTests.swift \
  Tests/NeedlbarTests/ClaudeStatusLineFallbackIntegrationTests.swift
git commit -m "feat(claude): make automatic /usage runs opt-in in the coordinator" \
  -m "RefreshCoordinator takes claudeAutomaticRunsAllowed with no default and builds the schedule from it. The setter requests one automaticResumed run when it turns on, clears queued runs and backoff when it turns off, and never cancels a run in flight. The app passes the stored setting and Claude being shown, so automatic runs are off by default." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Send changes to the coordinator in order

**Files:**
- Create: `Sources/Needlbar/App/ClaudeAutomaticRunsRelay.swift`
- Modify: `Sources/Needlbar/App/AppDelegate.swift:157,240`
- Test: `Tests/NeedlbarTests/ClaudeAutomaticRunsRelayTests.swift` (new)

**Interfaces:**
- Consumes: `ClaudeAutomaticChecksPreferences` (Task 3), `claudeIsShown(_:)` (Task 2), `RefreshCoordinator.setClaudeAutomaticRunsAllowed(_:)` (Task 4), and `ModuleConfiguration.didChangeNotification` and `.systemMonitor` (`Sources/NeedlbarCore/Configuration/ModuleConfiguration.swift:41,70`).
- Produces: `@MainActor final class ClaudeAutomaticRunsRelay` with `init(preferences: ClaudeAutomaticChecksPreferences, configuration: ModuleConfiguration, apply: @escaping @Sendable (Bool) async -> Void)`, `var allowed: Bool`, `func push()` and `func stop()`.

- [ ] **Step 1: Write the failing test**

The ordering test makes the first value the slowest to apply. A consumer that applied values concurrently would deliver `true` last and leave the coordinator on after the setting was turned off.

Create `Tests/NeedlbarTests/ClaudeAutomaticRunsRelayTests.swift`:

```swift
import Foundation
import NeedlbarCore
import Testing
@testable import NeedlbarApp

@Suite("ClaudeAutomaticRunsRelay", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct ClaudeAutomaticRunsRelayTests {
    @Test func theValueIsThePreferenceAndClaudeBeingShown() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        #expect(!fixture.relay.allowed, "off by default")
        fixture.preferences.setEnabled(true)
        #expect(fixture.relay.allowed)
        fixture.hideClaude()
        #expect(!fixture.relay.allowed, "paused while Claude is hidden")
        fixture.preferences.setEnabled(false)
        #expect(!fixture.relay.allowed)
    }

    @Test func valuesReachTheCoordinatorInTheOrderTheyWereComputed() async throws {
        // The first value is the slowest to apply. A consumer that applied values
        // concurrently would deliver it last and leave the coordinator on.
        let fixture = try Fixture(applyDelay: { $0 ? .milliseconds(30) : .zero })
        defer { fixture.tearDown() }
        fixture.preferences.setEnabled(true)
        fixture.relay.push()
        fixture.preferences.setEnabled(false)
        fixture.relay.push()
        // Two direct pushes, then one from each observed change, both computed
        // after the second change.
        await fixture.applied.waitForCount(4)
        #expect(fixture.applied.values == [true, false, false, false])
    }

    @Test func aPreferenceChangeIsPushedWithoutACall() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.preferences.setEnabled(true)
        await fixture.applied.waitForCount(1)
        #expect(fixture.applied.values == [true])
    }

    @Test func hidingAndShowingClaudeIsPushed() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.preferences.setEnabled(true)
        await fixture.applied.waitForCount(1)
        fixture.hideClaude()
        await fixture.applied.waitUntilLast(is: false)
        fixture.showClaude()
        await fixture.applied.waitUntilLast(is: true)
        #expect(fixture.applied.values.first == true)
    }
}

private final class AppliedValues: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Bool] = []

    var values: [Bool] { lock.withLock { recorded } }
    func record(_ value: Bool) { lock.withLock { recorded.append(value) } }

    func waitForCount(_ count: Int) async {
        while !Task.isCancelled, values.count < count {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    func waitUntilLast(is value: Bool) async {
        while !Task.isCancelled, values.last != value {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}

@MainActor
private final class Fixture {
    let preferences: ClaudeAutomaticChecksPreferences
    let configuration: ModuleConfiguration
    let applied = AppliedValues()
    let relay: ClaudeAutomaticRunsRelay
    private let defaults: UserDefaults
    private let name: String

    init(applyDelay: @escaping @Sendable (Bool) -> Duration = { _ in .zero }) throws {
        name = "ClaudeAutomaticRunsRelay.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: name))
        preferences = ClaudeAutomaticChecksPreferences(defaults: defaults)
        configuration = ModuleConfiguration(defaults: defaults)
        let applied = self.applied
        relay = ClaudeAutomaticRunsRelay(preferences: preferences, configuration: configuration) { value in
            try? await Task.sleep(for: applyDelay(value))
            applied.record(value)
        }
    }

    func hideClaude() { setClaudeVisible(false) }
    func showClaude() { setClaudeVisible(true) }

    private func setClaudeVisible(_ visible: Bool) {
        var monitor = configuration.systemMonitor
        monitor.ai[.claude]?.isVisible = visible
        configuration.setSystemMonitor(monitor)
    }

    func tearDown() {
        relay.stop()
        defaults.removePersistentDomain(forName: name)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeAutomaticRunsRelay`
Expected: FAIL at build time: the test file cannot find `ClaudeAutomaticRunsRelay` in scope. make ends with `make: *** [swift-test] Error 1`.

- [ ] **Step 3: Write the relay**

Create `Sources/Needlbar/App/ClaudeAutomaticRunsRelay.swift`:

```swift
import Combine
import Foundation
import NeedlbarCore

/// Tells the refresh coordinator whether automatic Claude runs are allowed: the
/// user's setting and Claude being shown. Each value is computed on the main
/// actor from the current state and sent through one serial channel, so values
/// reach the coordinator in the order they were computed and the last one it
/// applies is the current one.
@MainActor
final class ClaudeAutomaticRunsRelay {
    private let preferences: ClaudeAutomaticChecksPreferences
    private let configuration: ModuleConfiguration
    private let continuation: AsyncStream<Bool>.Continuation
    private var preferenceObservation: AnyCancellable?
    private var configurationObserver: NSObjectProtocol?

    init(
        preferences: ClaudeAutomaticChecksPreferences,
        configuration: ModuleConfiguration,
        apply: @escaping @Sendable (Bool) async -> Void
    ) {
        self.preferences = preferences
        self.configuration = configuration
        let (stream, continuation) = AsyncStream.makeStream(of: Bool.self)
        self.continuation = continuation
        // The single consumer: one value is applied before the next is read.
        Task {
            for await allowed in stream {
                await apply(allowed)
            }
        }
        // `@Published` reports a change before it is stored, so the value is
        // read again on the next main-actor turn rather than taken from here.
        preferenceObservation = preferences.$isEnabled.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.push() }
        }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: ModuleConfiguration.didChangeNotification,
            object: configuration,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.push() }
        }
    }

    /// The value the coordinator should hold now.
    var allowed: Bool {
        preferences.isEnabled && claudeIsShown(configuration.systemMonitor)
    }

    func push() {
        continuation.yield(allowed)
    }

    func stop() {
        preferenceObservation = nil
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        continuation.finish()
    }
}
```

- [ ] **Step 4: Create it in the app**

The relay is created in the same synchronous initializer that computed the initial value, so no change can fall between the two.

In `Sources/Needlbar/App/AppDelegate.swift`, replace

```swift
    private let claudeAutomaticChecks: ClaudeAutomaticChecksPreferences
    private let widgetPublisher: WidgetProjectionPublisher?
```

with

```swift
    private let claudeAutomaticChecks: ClaudeAutomaticChecksPreferences
    private var claudeAutomaticRunsRelay: ClaudeAutomaticRunsRelay?
    private let widgetPublisher: WidgetProjectionPublisher?
```

In `Sources/Needlbar/App/AppDelegate.swift`, replace

```swift
                claudeCheckNow: { Task { await refreshCoordinator.manualRefresh() } }
            )
```

with

```swift
                claudeCheckNow: { Task { await refreshCoordinator.manualRefresh() } }
            )
            // Sends every later change of that value, in order.
            self.claudeAutomaticRunsRelay = ClaudeAutomaticRunsRelay(
                preferences: claudeAutomaticChecks,
                configuration: moduleConfiguration,
                apply: { await refreshCoordinator.setClaudeAutomaticRunsAllowed($0) }
            )
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeAutomaticRunsRelay`
Expected: `Test run with 4 tests in 1 suite passed`, and make exits 0.

- [ ] **Step 6: Commit**

```bash
git add Sources/Needlbar/App/ClaudeAutomaticRunsRelay.swift \
  Sources/Needlbar/App/AppDelegate.swift \
  Tests/NeedlbarTests/ClaudeAutomaticRunsRelayTests.swift
git commit -m "feat(claude): send the automatic checks state to the coordinator in order" \
  -m "A change of the setting or of the module configuration recomputes setting-and-shown on the main actor and sends it through one AsyncStream with a single consumer, so the coordinator applies values in the order they were computed." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The Settings toggle and its captions

**Files:**
- Create: `Sources/Needlbar/App/ClaudeAutomaticChecksCopy.swift`
- Modify: `Sources/Needlbar/Settings/SettingsActions.swift:9-18,25,43-48,71`
- Modify: `Sources/Needlbar/Settings/SettingsView.swift:243,333`
- Modify: `Sources/Needlbar/App/AppDelegate.swift:240`
- Test: `Tests/NeedlbarTests/ClaudeAutomaticChecksSettingsTests.swift` (new)

**Interfaces:**
- Consumes: `ClaudeAutomaticChecksPreferences` (Task 3) and `claudeIsShown(_:)` (Task 2).
- Produces: `enum ClaudeAutomaticChecksCopy` with `static let offCaption`, `turnOn`, `settingsToggle`, `settingsCaption`, `settingsPausedCaption` and `static func settingsCaption(enabled: Bool, claudeShown: Bool) -> String`. In `SettingsActions`: `@Published public private(set) var claudeAutomaticChecksEnabled: Bool?`, `public func setClaudeAutomaticChecksEnabled(_ enabled: Bool)`, and both initializers gain `claudeAutomaticChecks: ClaudeAutomaticChecksPreferences? = nil` as their last parameter. In `SettingsView`: `@ViewBuilder var claudeAutomaticChecksRows: some View` and `func claudeAutomaticChecksCaption(enabled: Bool) -> String`. Task 7 uses the copy and the two `SettingsActions` members.

- [ ] **Step 1: Write the failing test**

Create `Tests/NeedlbarTests/ClaudeAutomaticChecksSettingsTests.swift`:

```swift
import Foundation
import NeedlbarCore
import SwiftUI
import Testing
@testable import NeedlbarApp

// The Settings toggle for automatic Claude checks. Everything is synthetic:
// isolated defaults, no refresh coordinator, and nothing here runs `claude`.
@Suite("ClaudeAutomaticChecksSettings", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct ClaudeAutomaticChecksSettingsTests {
    @Test func theCopyIsTheApprovedText() {
        #expect(ClaudeAutomaticChecksCopy.offCaption == "Automatic checks are off.")
        #expect(ClaudeAutomaticChecksCopy.turnOn == "Turn on")
        #expect(ClaudeAutomaticChecksCopy.settingsToggle == "Check Claude quota automatically")
        #expect(ClaudeAutomaticChecksCopy.settingsCaption(enabled: false, claudeShown: true)
            == "Runs /usage in your Claude Code about every 15 minutes. Off: only when you click Check now.")
        #expect(ClaudeAutomaticChecksCopy.settingsCaption(enabled: true, claudeShown: true)
            == ClaudeAutomaticChecksCopy.settingsCaption(enabled: false, claudeShown: true))
        #expect(ClaudeAutomaticChecksCopy.settingsCaption(enabled: false, claudeShown: false)
            == ClaudeAutomaticChecksCopy.settingsCaption(enabled: false, claudeShown: true),
            "off and hidden still explains the setting")
        #expect(ClaudeAutomaticChecksCopy.settingsCaption(enabled: true, claudeShown: false)
            == "Paused while Claude is hidden.")
    }

    @Test func actionsWithoutAPreferenceCarryNoSettingAndIgnoreARequest() {
        let actions = SettingsActions()
        #expect(actions.claudeAutomaticChecksEnabled == nil)
        actions.setClaudeAutomaticChecksEnabled(true)
        #expect(actions.claudeAutomaticChecksEnabled == nil)
    }

    @Test func actionsShowAndSetThePreferenceAndRunNoCheck() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        var checks = 0
        let actions = SettingsActions(claudeCheckNow: { checks += 1 }, claudeAutomaticChecks: fixture.preferences)
        #expect(actions.claudeAutomaticChecksEnabled == false)
        actions.setClaudeAutomaticChecksEnabled(true)
        #expect(actions.claudeAutomaticChecksEnabled == true)
        #expect(fixture.preferences.isEnabled)
        actions.setClaudeAutomaticChecksEnabled(false)
        #expect(actions.claudeAutomaticChecksEnabled == false)
        #expect(!fixture.preferences.isEnabled)
        #expect(checks == 0, "the toggle is not Check now")
    }

    @Test func actionsFollowAChangeMadeElsewhere() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let actions = SettingsActions(claudeAutomaticChecks: fixture.preferences)
        fixture.preferences.setEnabled(true)
        while !Task.isCancelled, actions.claudeAutomaticChecksEnabled != true {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(actions.claudeAutomaticChecksEnabled == true)
    }

    @Test func theCaptionSaysPausedOnlyWhileOnAndClaudeIsHidden() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let view = fixture.settingsView(actions: SettingsActions(claudeAutomaticChecks: fixture.preferences))
        #expect(view.claudeAutomaticChecksCaption(enabled: false) == ClaudeAutomaticChecksCopy.settingsCaption)
        #expect(view.claudeAutomaticChecksCaption(enabled: true) == ClaudeAutomaticChecksCopy.settingsCaption)
        fixture.defaults.set(false, forKey: "needlbar.systemMonitor.ai.claude.menuBar.visible")
        fixture.defaults.set(false, forKey: "needlbar.systemMonitor.ai.claude.dashboard.visible")
        #expect(view.claudeAutomaticChecksCaption(enabled: true) == "Paused while Claude is hidden.")
        #expect(view.claudeAutomaticChecksCaption(enabled: false) == ClaudeAutomaticChecksCopy.settingsCaption)
    }

    @Test func theRowsRenderOnlyWhenTheActionsCarryAPreference() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let with = fixture.settingsView(actions: SettingsActions(claudeAutomaticChecks: fixture.preferences))
        try AccessibilityHostedView(VStack { with.claudeAutomaticChecksRows }, width: 640) { hosted in
            #expect(hosted.items.filter { $0.role == "AXCheckBox" }.map(\.label) == ["Check Claude quota automatically"],
                    "\(hosted.items)")
        }
        let without = fixture.settingsView(actions: SettingsActions())
        try AccessibilityHostedView(VStack { without.claudeAutomaticChecksRows }, width: 640) { hosted in
            #expect(!hosted.items.contains { $0.label == "Check Claude quota automatically" }, "\(hosted.items)")
        }
    }
}

@MainActor
private final class Fixture {
    let defaults: UserDefaults
    let preferences: ClaudeAutomaticChecksPreferences
    private let name: String

    init() throws {
        name = "ClaudeAutomaticChecksSettings.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: name))
        preferences = ClaudeAutomaticChecksPreferences(defaults: defaults)
    }

    func settingsView(actions: SettingsActions) -> SettingsView {
        let notificationPreferences = QuotaNotificationPreferences(defaults: defaults)
        return SettingsView(
            configuration: ModuleConfiguration(defaults: defaults),
            actions: actions,
            notificationPreferences: notificationPreferences,
            notificationService: QuotaNotificationService(
                store: ProviderSnapshotStore(), preferences: notificationPreferences),
            openCursorSpending: {},
            openClaudeUsage: { true }
        )
    }

    func tearDown() { defaults.removePersistentDomain(forName: name) }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeAutomaticChecksSettings`
Expected: FAIL at build time: the test file cannot find `ClaudeAutomaticChecksCopy`, and `SettingsActions` and `SettingsView` have no `claudeAutomaticChecks` members. make ends with `make: *** [swift-test] Error 1`.

- [ ] **Step 3: Add the copy**

All in-app strings of spec §6 are here, including the two the dashboard uses in Task 7.

Create `Sources/Needlbar/App/ClaudeAutomaticChecksCopy.swift`:

```swift
import Foundation

/// The in-app copy for automatic Claude checks (spec 2026-11-16 §6). It does not
/// say whether a run uses quota or sends a model request; neither is verified.
enum ClaudeAutomaticChecksCopy {
    static let offCaption = "Automatic checks are off."
    static let turnOn = "Turn on"
    static let settingsToggle = "Check Claude quota automatically"
    static let settingsCaption =
        "Runs /usage in your Claude Code about every 15 minutes. Off: only when you click Check now."
    static let settingsPausedCaption = "Paused while Claude is hidden."

    /// The one caption line under the Settings toggle.
    static func settingsCaption(enabled: Bool, claudeShown: Bool) -> String {
        enabled && !claudeShown ? settingsPausedCaption : settingsCaption
    }
}
```

- [ ] **Step 4: Carry the setting in `SettingsActions`**

In `Sources/Needlbar/Settings/SettingsActions.swift`, replace

```swift
    @Published public private(set) var exportState: SnapshotExportState

    private let loginCoordinator: ProviderLoginCoordinator?
    private let snapshotExportController: SnapshotExportController?
    private let claudeCheckNow: (@MainActor () -> Void)?
    private var cancellables: Set<AnyCancellable> = []

    public init(
        loginCoordinator: ProviderLoginCoordinator,
        snapshotExportController: SnapshotExportController,
        claudeCheckNow: (@MainActor () -> Void)? = nil
    ) {
```

with

```swift
    @Published public private(set) var exportState: SnapshotExportState
    /// The automatic Claude checks setting, or nil when these actions carry no
    /// preference (the acceptance build and tests), which hides its controls.
    @Published public private(set) var claudeAutomaticChecksEnabled: Bool?

    private let loginCoordinator: ProviderLoginCoordinator?
    private let snapshotExportController: SnapshotExportController?
    private let claudeCheckNow: (@MainActor () -> Void)?
    private let claudeAutomaticChecks: ClaudeAutomaticChecksPreferences?
    private var cancellables: Set<AnyCancellable> = []

    public init(
        loginCoordinator: ProviderLoginCoordinator,
        snapshotExportController: SnapshotExportController,
        claudeCheckNow: (@MainActor () -> Void)? = nil,
        claudeAutomaticChecks: ClaudeAutomaticChecksPreferences? = nil
    ) {
```

In `Sources/Needlbar/Settings/SettingsActions.swift`, replace

```swift
        self.snapshotExportController = snapshotExportController
        self.claudeCheckNow = claudeCheckNow

        loginCoordinator.objectWillChange
```

with

```swift
        self.snapshotExportController = snapshotExportController
        self.claudeCheckNow = claudeCheckNow
        self.claudeAutomaticChecks = claudeAutomaticChecks
        claudeAutomaticChecksEnabled = claudeAutomaticChecks?.isEnabled
        observeClaudeAutomaticChecks()

        loginCoordinator.objectWillChange
```

In `Sources/Needlbar/Settings/SettingsActions.swift`, replace

```swift
    }

    public init(claudeCheckNow: (@MainActor () -> Void)? = nil) {
        loginStates = [:]
        exportState = .idle
        loginCoordinator = nil
        snapshotExportController = nil
        self.claudeCheckNow = claudeCheckNow
    }
```

with

```swift
    }

    public init(
        claudeCheckNow: (@MainActor () -> Void)? = nil,
        claudeAutomaticChecks: ClaudeAutomaticChecksPreferences? = nil
    ) {
        loginStates = [:]
        exportState = .idle
        loginCoordinator = nil
        snapshotExportController = nil
        self.claudeCheckNow = claudeCheckNow
        self.claudeAutomaticChecks = claudeAutomaticChecks
        claudeAutomaticChecksEnabled = claudeAutomaticChecks?.isEnabled
        observeClaudeAutomaticChecks()
    }
```

In `Sources/Needlbar/Settings/SettingsActions.swift`, replace

```swift
    }

    public func exportSnapshot() {
```

with

```swift
    }

    /// Sets the automatic Claude checks preference. It starts no run itself: the
    /// app observes the preference and tells the refresh coordinator.
    public func setClaudeAutomaticChecksEnabled(_ enabled: Bool) {
        guard let claudeAutomaticChecks else { return }
        claudeAutomaticChecks.setEnabled(enabled)
        claudeAutomaticChecksEnabled = enabled
    }

    /// Follows a change made elsewhere: the dashboard row or the first-run window.
    private func observeClaudeAutomaticChecks() {
        guard let claudeAutomaticChecks else { return }
        claudeAutomaticChecks.$isEnabled.dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.claudeAutomaticChecksEnabled = self.claudeAutomaticChecks?.isEnabled
                }
            }
            .store(in: &cancellables)
    }

    public func exportSnapshot() {
```

- [ ] **Step 5: Show the toggle in the Claude connection card**

It sits under the Claude row that already holds **Check now**, in the same card, so no new section title is needed. The Check now button and its visibility rule are untouched.

In `Sources/Needlbar/Settings/SettingsView.swift`, replace

```swift
            switch provider {
            case .claude: claudeUsageRow
            case .codex: providerLoginRow(provider: .codex, title: "Codex", actionTitle: "Sign in with ChatGPT")
```

with

```swift
            switch provider {
            case .claude:
                claudeUsageRow
                claudeAutomaticChecksRows
            case .codex: providerLoginRow(provider: .codex, title: "Codex", actionTitle: "Sign in with ChatGPT")
```

In `Sources/Needlbar/Settings/SettingsView.swift`, replace

```swift
        .frame(minHeight: 54)
    }
```

with

```swift
        .frame(minHeight: 54)
    }

    /// The opt-in for automatic `/usage` runs, under the Claude connection row.
    /// Absent when the actions carry no preference, as in the acceptance build.
    @ViewBuilder var claudeAutomaticChecksRows: some View {
        if let enabled = actions.claudeAutomaticChecksEnabled {
            Divider().padding(.top, 12)
            SettingsStudioToggle(title: ClaudeAutomaticChecksCopy.settingsToggle, value: Binding(
                get: { actions.claudeAutomaticChecksEnabled ?? false },
                set: { actions.setClaudeAutomaticChecksEnabled($0) }))
            Text(claudeAutomaticChecksCaption(enabled: enabled))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Reads the stored configuration, like `claudeCheckNowAction`, so it is
    /// current whenever the pane is drawn again after a visibility change.
    func claudeAutomaticChecksCaption(enabled: Bool) -> String {
        ClaudeAutomaticChecksCopy.settingsCaption(
            enabled: enabled, claudeShown: claudeIsShown(configuration.systemMonitor))
    }
```

- [ ] **Step 6: Give the production actions the preference**

In `Sources/Needlbar/App/AppDelegate.swift`, replace

```swift
                snapshotExportController: snapshotExportController,
                claudeCheckNow: { Task { await refreshCoordinator.manualRefresh() } }
            )
```

with

```swift
                snapshotExportController: snapshotExportController,
                claudeCheckNow: { Task { await refreshCoordinator.manualRefresh() } },
                claudeAutomaticChecks: claudeAutomaticChecks
            )
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeAutomaticChecks`
Expected: `Test run with 9 tests in 2 suites passed`, and make exits 0.

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeCheckNow`
Expected: `Test run with 11 tests in 1 suite passed`, and make exits 0: the Settings row and its **Check now** button are unchanged.

- [ ] **Step 8: Commit**

```bash
git add Sources/Needlbar/App/ClaudeAutomaticChecksCopy.swift \
  Sources/Needlbar/Settings/SettingsActions.swift \
  Sources/Needlbar/Settings/SettingsView.swift \
  Sources/Needlbar/App/AppDelegate.swift \
  Tests/NeedlbarTests/ClaudeAutomaticChecksSettingsTests.swift
git commit -m "feat(settings): add the Check Claude quota automatically toggle" \
  -m "The Claude pane gets the toggle and one caption line, which reads Paused while Claude is hidden while the setting is on and Claude is on neither surface. SettingsActions carries the setting, so builds that pass none, such as the acceptance build, show no control." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: The dashboard row prompt and the neutral off state

**Files:**
- Modify: `Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift:76,149,171,247,426-445`
- Modify: `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift:85,98,113,127,142,164,351-357,409,564`
- Modify: `Sources/Needlbar/MenuBar/MenuBarController.swift:2,470,488,525,624,649,676-678,739,778,867`
- Test: `Tests/NeedlbarTests/ClaudeAutomaticChecksDashboardTests.swift` (new)
- Test: `Tests/NeedlbarTests/MenuBarControllerTests.swift:1000,1031`

**Interfaces:**
- Consumes: `ClaudeAutomaticChecksCopy.offCaption` and `.turnOn`, and `SettingsActions.claudeAutomaticChecksEnabled` and `.setClaudeAutomaticChecksEnabled(_:)` (Task 6). The test fixtures `ClaudeCheckNowActionTests.combined`, `.claude(reason:statusLine:)`, `.dashboardConfiguration(metric:)` and `.now` (`Tests/NeedlbarTests/ClaudeCheckNowActionTests.swift:171-208`).
- Produces: `public struct ClaudeAutomaticChecksPrompt: Equatable, Sendable` with `caption`, `actionTitle` and `static let turnOn`. `SystemDashboardPresentation.AIProvider.automaticChecksPrompt: ClaudeAutomaticChecksPrompt?`. `SystemDashboardPresentation.init(snapshot:configuration:claudeAutomaticChecksOff:now:)`, `SystemDashboardModel.init(snapshot:configuration:claudeAutomaticChecksOff:)` and `.update(snapshot:configuration:claudeAutomaticChecksOff:)`, each with `claudeAutomaticChecksOff: Bool = false`. `SystemDashboardPopoverView` initializers gain `onClaudeAutomaticChecksTurnOn: @escaping () -> Void = {}` after `onClaudeCheckNow`. In `MenuBarController`: `func performClaudeAutomaticChecksTurnOnAction()` and `var dashboardShowsClaudeAutomaticChecksPrompt: Bool`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/NeedlbarTests/ClaudeAutomaticChecksDashboardTests.swift`:

```swift
import Foundation
import SwiftUI
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

// The dashboard Claude row while automatic checks are off: a neutral caption and
// a "Turn on" button beside "Check now". Everything is synthetic; the closures
// count calls and stop there.
@Suite("ClaudeAutomaticChecksDashboard", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct ClaudeAutomaticChecksDashboardTests {
    nonisolated static let now = ClaudeCheckNowActionTests.now

    // MARK: - Presentation

    @Test func thePromptIsOnTheClaudeRowOnlyAndOnlyWhileOff() throws {
        let snapshot = ClaudeCheckNowActionTests.combined(try ClaudeCheckNowActionTests.claude(reason: nil, statusLine: nil))
        let off = Self.presentation(snapshot, off: true)
        #expect(off.ai.filter { $0.automaticChecksPrompt != nil }.map(\.provider) == [.claude])
        #expect(Self.claudeRow(off)?.automaticChecksPrompt == .turnOn)
        #expect(ClaudeAutomaticChecksPrompt.turnOn.caption == "Automatic checks are off.")
        #expect(ClaudeAutomaticChecksPrompt.turnOn.actionTitle == "Turn on")

        let on = Self.presentation(snapshot, off: false)
        #expect(on.ai.allSatisfy { $0.automaticChecksPrompt == nil })
        let unstated = SystemDashboardPresentation(
            snapshot: snapshot, configuration: ClaudeCheckNowActionTests.dashboardConfiguration(), now: Self.now)
        #expect(unstated.ai.allSatisfy { $0.automaticChecksPrompt == nil }, "no prompt unless the caller says off")
    }

    @Test func offWithNoReadingAndNoRunTriedIsNeutral() throws {
        for metric in [AIProviderDisplayMetric.remaining, .usage] {
            let row = try #require(Self.claudeRow(Self.presentation(
                ClaudeCheckNowActionTests.combined(Self.neverChecked()), off: true, metric: metric)))
            #expect(row.automaticChecksPrompt?.caption == "Automatic checks are off.")
            #expect(row.statusText == nil, "no orange status")
            #expect(row.quotaFailureReasonText == nil, "no Could not update")
            #expect(row.quotaStatus == .unavailable, "no error state")
            #expect(row.compactQuotaValue == "—")
        }
    }

    @Test func aFailureFromAManualRunStillShowsAsToday() throws {
        let failed = ProviderSnapshot(
            provider: .claude, usage: nil, quota: nil, usageStatus: .fresh,
            quotaStatus: .error(message: "failed", lastSuccessfulAt: nil), updatedAt: Self.now,
            claudeQuotaFailureReason: .claudeCodeNotInstalled)
        let off = try #require(Self.claudeRow(Self.presentation(ClaudeCheckNowActionTests.combined(failed), off: true)))
        let on = try #require(Self.claudeRow(Self.presentation(ClaudeCheckNowActionTests.combined(failed), off: false)))
        #expect(off.quotaFailureReasonText == "Install Claude Code to see quota")
        #expect(off.quotaFailureReasonText == on.quotaFailureReasonText)
        #expect(off.statusText == on.statusText)
        #expect(off.automaticChecksPrompt == .turnOn, "the prompt stays beside the failure")
    }

    @Test func aRowWithAReadingIsUnchangedApartFromThePrompt() throws {
        let snapshot = ClaudeCheckNowActionTests.combined(try ClaudeCheckNowActionTests.claude(reason: nil, statusLine: nil))
        let off = try #require(Self.claudeRow(Self.presentation(snapshot, off: true)))
        let on = try #require(Self.claudeRow(Self.presentation(snapshot, off: false)))
        #expect(off.value == on.value)
        #expect(off.compactQuotaValue == on.compactQuotaValue)
        #expect(off.compactQuotaLabel == on.compactQuotaLabel)
        #expect(off.statusText == on.statusText)
        #expect(off.quotaIsLastKnown == on.quotaIsLastKnown)
        #expect(off.checkNowAction == .checkNow)
    }

    @Test func theModelKeepsTheStateAcrossUpdatesAndReprojection() throws {
        let snapshot = ClaudeCheckNowActionTests.combined(Self.neverChecked())
        let configuration = ClaudeCheckNowActionTests.dashboardConfiguration()
        let model = SystemDashboardModel(snapshot: snapshot, configuration: configuration, claudeAutomaticChecksOff: true)
        #expect(Self.claudeRow(model.presentation)?.automaticChecksPrompt == .turnOn)
        model.reproject(at: Self.now.addingTimeInterval(60))
        #expect(Self.claudeRow(model.presentation)?.automaticChecksPrompt == .turnOn)
        model.update(snapshot: snapshot, configuration: configuration, claudeAutomaticChecksOff: false)
        model.reproject(at: Self.now.addingTimeInterval(120))
        #expect(Self.claudeRow(model.presentation)?.automaticChecksPrompt == nil)
    }

    // MARK: - View

    @Test func bothLayoutsShowOneTurnOnButtonBesideCheckNowOnlyWhileOff() throws {
        for metric in [AIProviderDisplayMetric.remaining, .usage] {
            try Self.hostedDashboard(off: true, metric: metric) { hosted, _ in
                #expect(hosted.buttons.filter { $0 == "Turn on" }.count == 1, "\(metric) \(hosted.buttons)")
                #expect(hosted.buttons.filter { $0 == "Check now" }.count == 1, "\(metric) \(hosted.buttons)")
            }
            try Self.hostedDashboard(off: false, metric: metric) { hosted, _ in
                #expect(!hosted.buttons.contains("Turn on"), "\(metric) \(hosted.buttons)")
                #expect(hosted.buttons.filter { $0 == "Check now" }.count == 1)
            }
        }
    }

    @Test func turnOnReachesItsClosureOnceAndNothingElse() throws {
        for metric in [AIProviderDisplayMetric.remaining, .usage] {
            try Self.hostedDashboard(off: true, metric: metric) { hosted, counts in
                #expect(counts.turnOns == 0, "rendering must not turn anything on")
                try hosted.press("Turn on")
                #expect(counts.turnOns == 1, "\(metric)")
                #expect(counts.checks == 0, "Turn on is not Check now")
                #expect(counts.others == 0)
                try hosted.press("Check now")
                #expect(counts.checks == 1)
                #expect(counts.turnOns == 1, "Check now does not turn the schedule on")
            }
        }
    }
}

@MainActor
private final class Counts {
    var turnOns = 0
    var checks = 0
    var others = 0
}

extension ClaudeAutomaticChecksDashboardTests {
    /// Claude as the store reports it before any run: no quota, no failure reason.
    static func neverChecked() -> ProviderSnapshot {
        ProviderSnapshot(
            provider: .claude, usage: nil, quota: nil, usageStatus: .fresh,
            quotaStatus: .unavailable, updatedAt: now)
    }

    static func presentation(
        _ snapshot: CombinedUsageSnapshot, off: Bool, metric: AIProviderDisplayMetric = .remaining
    ) -> SystemDashboardPresentation {
        SystemDashboardPresentation(
            snapshot: snapshot, configuration: ClaudeCheckNowActionTests.dashboardConfiguration(metric: metric),
            claudeAutomaticChecksOff: off, now: now)
    }

    static func claudeRow(_ presentation: SystemDashboardPresentation) -> SystemDashboardPresentation.AIProvider? {
        presentation.ai.first { $0.provider == .claude }
    }

    fileprivate static func hostedDashboard(
        off: Bool,
        metric: AIProviderDisplayMetric,
        body: (AccessibilityHostedView, Counts) throws -> Void
    ) throws {
        let counts = Counts()
        let layout = SystemDashboardPopoverLayout(height: 900)
        let model = SystemDashboardModel(
            snapshot: ClaudeCheckNowActionTests.combined(neverChecked()),
            configuration: ClaudeCheckNowActionTests.dashboardConfiguration(metric: metric),
            claudeAutomaticChecksOff: off)
        let view = SystemDashboardPopoverView(
            model: model,
            layout: layout,
            onShowSettings: { counts.others += 1 },
            onShowAnalytics: { counts.others += 1 },
            onProviderAction: { _ in counts.others += 1 },
            onAPIBillingAction: { _ in counts.others += 1; return false },
            onClaudeUsageAction: { counts.others += 1; return true },
            onClaudeCheckNow: { counts.checks += 1 },
            onClaudeAutomaticChecksTurnOn: { counts.turnOns += 1 })
        try AccessibilityHostedView(view, body: { try body($0, counts) })
    }
}
```

The controller tests use a second helper that builds the controller from explicit actions.

In `Tests/NeedlbarTests/MenuBarControllerTests.swift`, replace

```swift
    }

    @Test func stopObservingDismissesShownPanelAndCancelsMonitoringOnlyOnce() {
```

with

```swift
    }

    @Test func theDashboardTurnOnButtonSetsThePreferenceRunsNothingAndLeavesThePanelShown() throws {
        let defaults = freshMenuBarDefaults()
        let preferences = ClaudeAutomaticChecksPreferences(defaults: defaults)
        var checks = 0
        var refreshes = 0
        let presenter = FakeMenuPanelPresenter()
        let controller = makeMenuBarController(
            defaults: defaults,
            actions: SettingsActions(claudeCheckNow: { checks += 1 }, claudeAutomaticChecks: preferences),
            panelPresenter: presenter,
            onRetryRequested: { refreshes += 1 }
        )

        controller.openOverview()
        let shown = try #require(presenter.presentedContentViewControllers.last)
        try AccessibilityHostedView(view: shown.view, width: 360) { hosted in
            #expect(hosted.buttons.filter { $0 == "Turn on" }.count == 1, "\(hosted.buttons)")
            try hosted.press("Turn on")
        }

        #expect(preferences.isEnabled)
        #expect(checks == 0)
        #expect(refreshes == 0, "turning on is not a manual refresh")
        #expect(presenter.isShown)
        #expect(presenter.dismissCount == 0)
    }

    @Test func theDashboardPromptFollowsThePreferenceWhileObserving() async {
        let defaults = freshMenuBarDefaults()
        let preferences = ClaudeAutomaticChecksPreferences(defaults: defaults)
        let controller = makeMenuBarController(
            defaults: defaults,
            actions: SettingsActions(claudeAutomaticChecks: preferences)
        )
        await controller.startObserving()
        #expect(controller.dashboardShowsClaudeAutomaticChecksPrompt, "off by default")

        preferences.setEnabled(true)
        #expect(await eventually { !controller.dashboardShowsClaudeAutomaticChecksPrompt })
        preferences.setEnabled(false)
        #expect(await eventually { controller.dashboardShowsClaudeAutomaticChecksPrompt })
        controller.stopObserving()
    }

    @Test func withoutAPreferenceTheDashboardShowsNoPrompt() async throws {
        let presenter = FakeMenuPanelPresenter()
        let controller = makeMenuBarController(
            defaults: freshMenuBarDefaults(), actions: SettingsActions(), panelPresenter: presenter)
        controller.openOverview()
        #expect(!controller.dashboardShowsClaudeAutomaticChecksPrompt)
        let shown = try #require(presenter.presentedContentViewControllers.last)
        try AccessibilityHostedView(view: shown.view, width: 360) { hosted in
            #expect(!hosted.buttons.contains("Turn on"), "\(hosted.buttons)")
        }
    }

    @Test func stopObservingDismissesShownPanelAndCancelsMonitoringOnlyOnce() {
```

In `Tests/NeedlbarTests/MenuBarControllerTests.swift`, replace

```swift
    ProviderLoginCoordinator(refreshQuota: { _ in false })
}
```

with

```swift
    ProviderLoginCoordinator(refreshQuota: { _ in false })
}

/// A controller built from explicit actions, for the automatic checks prompt.
@MainActor
private func makeMenuBarController(
    defaults: UserDefaults,
    actions: SettingsActions,
    panelPresenter: any MenuPanelPresenting = FakeMenuPanelPresenter(),
    onRetryRequested: @escaping @MainActor () -> Void = {}
) -> MenuBarController {
    let snapshotStore = ProviderSnapshotStore()
    let notificationPreferences = QuotaNotificationPreferences(defaults: defaults)
    return MenuBarController(
        configuration: ModuleConfiguration(defaults: defaults),
        snapshotStore: snapshotStore,
        actions: actions,
        notificationPreferences: notificationPreferences,
        notificationService: QuotaNotificationService(store: snapshotStore, preferences: notificationPreferences),
        statusItemFactory: FakeStatusItemFactory(),
        globalMouseDownMonitor: FakeGlobalMouseDownMonitor(),
        panelPresenter: panelPresenter,
        onRetryRequested: onRetryRequested
    )
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeAutomaticChecksDashboard`
Expected: FAIL at build time: the test files cannot find `ClaudeAutomaticChecksPrompt`, the `claudeAutomaticChecksOff` and `onClaudeAutomaticChecksTurnOn` arguments, `performClaudeAutomaticChecksTurnOnAction` or `dashboardShowsClaudeAutomaticChecksPrompt`. make ends with `make: *** [swift-test] Error 1`.

- [ ] **Step 3: Add the prompt to the presentation and the model**

The prompt changes no other field of the row. With no reading and no run tried, the row keeps the status `unavailable`, no status text and no failure reason, which is the neutral state the tests fix.

In `Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift`, replace

```swift
}

public struct SystemDashboardPresentation: Equatable, Sendable {
```

with

```swift
}

/// The dashboard's prompt in the Claude row while automatic checks are off: one
/// caption line, which is also the row's reason for having no reading, and a
/// button that turns them on.
public struct ClaudeAutomaticChecksPrompt: Equatable, Sendable {
    public let caption: String
    public let actionTitle: String

    public static let turnOn = ClaudeAutomaticChecksPrompt(
        caption: ClaudeAutomaticChecksCopy.offCaption,
        actionTitle: ClaudeAutomaticChecksCopy.turnOn
    )
}

public struct SystemDashboardPresentation: Equatable, Sendable {
```

In `Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift`, replace

```swift
        public let checkNowAction: ClaudeCheckNowAction?
        public let apiBillingAction: ProviderAPIBillingAction?
```

with

```swift
        public let checkNowAction: ClaudeCheckNowAction?
        /// Claude only, while automatic checks are off. Its caption is neutral:
        /// secondary colour, and it changes no status, so a row that has no reading
        /// because nothing has run shows no error. A failure from a manual run
        /// keeps its own reason beside it.
        public let automaticChecksPrompt: ClaudeAutomaticChecksPrompt?
        public let apiBillingAction: ProviderAPIBillingAction?
```

In `Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift`, replace

```swift
    public let ai: [AIProvider]

    public init(snapshot: CombinedUsageSnapshot, configuration: SystemMonitorConfiguration, now: Date = .now) {
        let system = snapshot.system
```

with

```swift
    public let ai: [AIProvider]

    public init(
        snapshot: CombinedUsageSnapshot,
        configuration: SystemMonitorConfiguration,
        claudeAutomaticChecksOff: Bool = false,
        now: Date = .now
    ) {
        let system = snapshot.system
```

In `Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift`, replace

```swift
                checkNowAction: provider == .claude ? .checkNow : nil,
                apiBillingAction: preference.apiBillingLinkVisible ? ProviderAPIBillingAction(provider: provider) : nil,
```

with

```swift
                checkNowAction: provider == .claude ? .checkNow : nil,
                automaticChecksPrompt: provider == .claude && claudeAutomaticChecksOff ? .turnOn : nil,
                apiBillingAction: preference.apiBillingLinkVisible ? ProviderAPIBillingAction(provider: provider) : nil,
```

In `Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift`, replace

```swift
    private var latestConfiguration: SystemMonitorConfiguration

    public init(snapshot: CombinedUsageSnapshot, configuration: SystemMonitorConfiguration) {
        latestSnapshot = snapshot
        latestConfiguration = configuration
        presentation = SystemDashboardPresentation(snapshot: snapshot, configuration: configuration)
        var initialHistory = SystemDashboardHistory()
        initialHistory.append(snapshot.system)
        history = initialHistory
    }

    public func update(snapshot: CombinedUsageSnapshot, configuration: SystemMonitorConfiguration) {
        latestSnapshot = snapshot
        latestConfiguration = configuration
        presentation = SystemDashboardPresentation(snapshot: snapshot, configuration: configuration)
        history.append(snapshot.system)
    }

    public func reproject(at now: Date) {
        presentation = SystemDashboardPresentation(
            snapshot: latestSnapshot, configuration: latestConfiguration, now: now)
    }
```

with

```swift
    private var latestConfiguration: SystemMonitorConfiguration
    private var latestClaudeAutomaticChecksOff: Bool

    public init(
        snapshot: CombinedUsageSnapshot,
        configuration: SystemMonitorConfiguration,
        claudeAutomaticChecksOff: Bool = false
    ) {
        latestSnapshot = snapshot
        latestConfiguration = configuration
        latestClaudeAutomaticChecksOff = claudeAutomaticChecksOff
        presentation = SystemDashboardPresentation(
            snapshot: snapshot, configuration: configuration, claudeAutomaticChecksOff: claudeAutomaticChecksOff)
        var initialHistory = SystemDashboardHistory()
        initialHistory.append(snapshot.system)
        history = initialHistory
    }

    public func update(
        snapshot: CombinedUsageSnapshot,
        configuration: SystemMonitorConfiguration,
        claudeAutomaticChecksOff: Bool = false
    ) {
        latestSnapshot = snapshot
        latestConfiguration = configuration
        latestClaudeAutomaticChecksOff = claudeAutomaticChecksOff
        presentation = SystemDashboardPresentation(
            snapshot: snapshot, configuration: configuration, claudeAutomaticChecksOff: claudeAutomaticChecksOff)
        history.append(snapshot.system)
    }

    public func reproject(at now: Date) {
        presentation = SystemDashboardPresentation(
            snapshot: latestSnapshot, configuration: latestConfiguration,
            claudeAutomaticChecksOff: latestClaudeAutomaticChecksOff, now: now)
    }
```

- [ ] **Step 4: Draw the caption and the button**

The function is renamed because it now draws more than one button. A row without the prompt draws the same single button as before.

In `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift`, replace

```swift
    private let onClaudeCheckNow: () -> Void
    private let onQuotaDetailsExpansionChanged: () -> Void
```

with

```swift
    private let onClaudeCheckNow: () -> Void
    private let onClaudeAutomaticChecksTurnOn: () -> Void
    private let onQuotaDetailsExpansionChanged: () -> Void
```

In `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift`, replace

```swift
        onAPIBillingStateChanged: @escaping (DashboardAPIBillingLinkState) -> Void = { _ in },
        onClaudeUsageAction: @escaping () -> Bool = { false },
        onClaudeUsageStateChanged: @escaping (DashboardClaudeUsageLinkState) -> Void = { _ in },
        onClaudeCheckNow: @escaping () -> Void = {},
        onQuotaDetailsExpansionChanged: @escaping () -> Void = {}
    ) {
        _model = ObservedObject(wrappedValue: model)
        _layout = ObservedObject(wrappedValue: SystemDashboardPopoverLayout(height: height))
```

with

```swift
        onAPIBillingStateChanged: @escaping (DashboardAPIBillingLinkState) -> Void = { _ in },
        onClaudeUsageAction: @escaping () -> Bool = { false },
        onClaudeUsageStateChanged: @escaping (DashboardClaudeUsageLinkState) -> Void = { _ in },
        onClaudeCheckNow: @escaping () -> Void = {},
        onClaudeAutomaticChecksTurnOn: @escaping () -> Void = {},
        onQuotaDetailsExpansionChanged: @escaping () -> Void = {}
    ) {
        _model = ObservedObject(wrappedValue: model)
        _layout = ObservedObject(wrappedValue: SystemDashboardPopoverLayout(height: height))
```

In `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift`, replace

```swift
        self.onAPIBillingAction = onAPIBillingAction
        self.onAPIBillingStateChanged = onAPIBillingStateChanged
        self.onClaudeUsageAction = onClaudeUsageAction
        self.onClaudeUsageStateChanged = onClaudeUsageStateChanged
        self.onClaudeCheckNow = onClaudeCheckNow
        self.onQuotaDetailsExpansionChanged = onQuotaDetailsExpansionChanged
    }

    init(
        model: SystemDashboardModel,
```

with

```swift
        self.onAPIBillingAction = onAPIBillingAction
        self.onAPIBillingStateChanged = onAPIBillingStateChanged
        self.onClaudeUsageAction = onClaudeUsageAction
        self.onClaudeUsageStateChanged = onClaudeUsageStateChanged
        self.onClaudeCheckNow = onClaudeCheckNow
        self.onClaudeAutomaticChecksTurnOn = onClaudeAutomaticChecksTurnOn
        self.onQuotaDetailsExpansionChanged = onQuotaDetailsExpansionChanged
    }

    init(
        model: SystemDashboardModel,
```

In `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift`, replace

```swift
        onClaudeCheckNow: @escaping () -> Void = {},
        onQuotaDetailsExpansionChanged: @escaping () -> Void = {}
```

with

```swift
        onClaudeCheckNow: @escaping () -> Void = {},
        onClaudeAutomaticChecksTurnOn: @escaping () -> Void = {},
        onQuotaDetailsExpansionChanged: @escaping () -> Void = {}
```

In `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift`, replace

```swift
        self.onClaudeCheckNow = onClaudeCheckNow
        self.onQuotaDetailsExpansionChanged = onQuotaDetailsExpansionChanged
```

with

```swift
        self.onClaudeCheckNow = onClaudeCheckNow
        self.onClaudeAutomaticChecksTurnOn = onClaudeAutomaticChecksTurnOn
        self.onQuotaDetailsExpansionChanged = onQuotaDetailsExpansionChanged
```

In `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift`, replace

```swift
        onClaudeCheckNow = {}
        onQuotaDetailsExpansionChanged = {}
```

with

```swift
        onClaudeCheckNow = {}
        onClaudeAutomaticChecksTurnOn = {}
        onQuotaDetailsExpansionChanged = {}
```

In `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift`, replace

```swift
    /// On its own line, so "View Claude usage" keeps its place and its width.
    @ViewBuilder
    private func claudeCheckNowButton(_ provider: SystemDashboardPresentation.AIProvider) -> some View {
        if let action = provider.checkNowAction {
            Button(action.title) { onClaudeCheckNow() }
                .buttonStyle(.borderless)
                .font(.caption)
                .accessibilityLabel(action.title)
        }
```

with

```swift
    /// On its own line, so "View Claude usage" keeps its place and its width.
    /// While automatic checks are off, a neutral caption sits above it and
    /// "Turn on" beside it.
    @ViewBuilder
    private func claudeCheckControls(_ provider: SystemDashboardPresentation.AIProvider) -> some View {
        if let prompt = provider.automaticChecksPrompt {
            Text(prompt.caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        if let action = provider.checkNowAction {
            HStack(spacing: 12) {
                Button(action.title) { onClaudeCheckNow() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .accessibilityLabel(action.title)
                if let prompt = provider.automaticChecksPrompt {
                    Button(prompt.actionTitle) { onClaudeAutomaticChecksTurnOn() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .accessibilityLabel(prompt.actionTitle)
                }
            }
        }
```

In `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift`, replace

```swift
            }

            claudeCheckNowButton(provider)

            if let fable = provider.fable {
```

with

```swift
            }

            claudeCheckControls(provider)

            if let fable = provider.fable {
```

In `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift`, replace

```swift
            }
            claudeCheckNowButton(provider)
            if let action = provider.apiBillingAction {
```

with

```swift
            }
            claudeCheckControls(provider)
            if let action = provider.apiBillingAction {
```

- [ ] **Step 5: Wire the controller**

The controller keeps the actions it already receives, redraws the dashboard when the setting changes while it is observing, and sets the preference for "Turn on". It starts no run itself.

In `Sources/Needlbar/MenuBar/MenuBarController.swift`, replace

```swift
import AppKit
import NeedlbarCore
```

with

```swift
import AppKit
import Combine
import NeedlbarCore
```

In `Sources/Needlbar/MenuBar/MenuBarController.swift`, replace

```swift
    private let settingsWindowController: SettingsWindowController
    private var statusItem: (any StatusItemHandle)?
```

with

```swift
    private let settingsWindowController: SettingsWindowController
    private let actions: SettingsActions
    private var claudeAutomaticChecksObservation: AnyCancellable?
    private var statusItem: (any StatusItemHandle)?
```

In `Sources/Needlbar/MenuBar/MenuBarController.swift`, replace

```swift
    var settingsPreviewResult: MenuBarDashboardRenderResult { settingsWindowController.previewResult }

    public init(
```

with

```swift
    var settingsPreviewResult: MenuBarDashboardRenderResult { settingsWindowController.previewResult }
    /// Whether the dashboard model currently carries the automatic checks prompt.
    var dashboardShowsClaudeAutomaticChecksPrompt: Bool {
        dashboardModel?.presentation.ai.contains { $0.automaticChecksPrompt != nil } ?? false
    }

    public init(
```

In `Sources/Needlbar/MenuBar/MenuBarController.swift`, replace

```swift
        self.openAPIBilling = openAPIBilling
        self.settingsWindowController = SettingsWindowController(
```

with

```swift
        self.openAPIBilling = openAPIBilling
        self.actions = actions
        self.settingsWindowController = SettingsWindowController(
```

In `Sources/Needlbar/MenuBar/MenuBarController.swift`, replace

```swift
        }
        if let providerUpdates {
```

with

```swift
        }
        // The Claude row's prompt follows the automatic checks setting.
        claudeAutomaticChecksObservation = actions.$claudeAutomaticChecksEnabled.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.observationGeneration == generation else { return }
                self.reconcile(using: self.cachedCombinedSnapshot)
            }
        }
        if let providerUpdates {
```

In `Sources/Needlbar/MenuBar/MenuBarController.swift`, replace

```swift
        combinedObservationTask = nil
        if let configurationObserver {
```

with

```swift
        combinedObservationTask = nil
        claudeAutomaticChecksObservation = nil
        if let configurationObserver {
```

In `Sources/Needlbar/MenuBar/MenuBarController.swift`, replace

```swift
        if let dashboardModel {
            dashboardModel.update(snapshot: snapshot, configuration: monitorConfiguration)
        } else {
            dashboardModel = SystemDashboardModel(snapshot: snapshot, configuration: monitorConfiguration)
        }
```

with

```swift
        if let dashboardModel {
            dashboardModel.update(
                snapshot: snapshot, configuration: monitorConfiguration,
                claudeAutomaticChecksOff: claudeAutomaticChecksOff)
        } else {
            dashboardModel = SystemDashboardModel(
                snapshot: snapshot, configuration: monitorConfiguration,
                claudeAutomaticChecksOff: claudeAutomaticChecksOff)
        }
```

In `Sources/Needlbar/MenuBar/MenuBarController.swift`, replace

```swift
        } else {
            model = SystemDashboardModel(snapshot: snapshot, configuration: monitorConfiguration)
            dashboardModel = model
```

with

```swift
        } else {
            model = SystemDashboardModel(
                snapshot: snapshot, configuration: monitorConfiguration,
                claudeAutomaticChecksOff: claudeAutomaticChecksOff)
            dashboardModel = model
```

In `Sources/Needlbar/MenuBar/MenuBarController.swift`, replace

```swift
                self?.performClaudeCheckNowAction()
            },
```

with

```swift
                self?.performClaudeCheckNowAction()
            },
            onClaudeAutomaticChecksTurnOn: { [weak self] in
                self?.performClaudeAutomaticChecksTurnOnAction()
            },
```

In `Sources/Needlbar/MenuBar/MenuBarController.swift`, replace

```swift
    func performClaudeCheckNowAction() {
        onRetryRequested()
    }

    func performAPIBillingAction(_ action: ProviderAPIBillingAction) -> Bool {
```

with

```swift
    func performClaudeCheckNowAction() {
        onRetryRequested()
    }

    /// Only an explicit false shows the prompt: nil means these actions carry no
    /// preference, as in the acceptance build, whose fixtures must not depend on
    /// the developer's defaults.
    private var claudeAutomaticChecksOff: Bool {
        actions.claudeAutomaticChecksEnabled == false
    }

    /// "Turn on" sets the preference and leaves the panel shown. It starts no run
    /// here: the app observes the preference and tells the refresh coordinator.
    func performClaudeAutomaticChecksTurnOnAction() {
        actions.setClaudeAutomaticChecksEnabled(true)
    }

    func performAPIBillingAction(_ action: ProviderAPIBillingAction) -> Bool {
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeAutomaticChecksDashboard`
Expected: `Test run with 7 tests in 1 suite passed`, and make exits 0.

Run: `make swift-test SWIFT_TEST_FILTER=MenuBarController`
Expected: `Test run with 41 tests in 1 suite passed`, and make exits 0.

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeCheckNow`
Expected: `Test run with 11 tests in 1 suite passed`, and make exits 0: every existing row still shows exactly one **Check now** button.

- [ ] **Step 7: Commit**

```bash
git add Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift \
  Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift \
  Sources/Needlbar/MenuBar/MenuBarController.swift \
  Tests/NeedlbarTests/ClaudeAutomaticChecksDashboardTests.swift \
  Tests/NeedlbarTests/MenuBarControllerTests.swift
git commit -m "feat(dashboard): prompt to turn on automatic Claude checks" \
  -m "While the setting is off, the Claude row says Automatic checks are off. in the secondary colour and shows a borderless Turn on button beside Check now, in the compact and the standard layout. The caption changes no status, so a row with no reading because nothing has run shows no error. Turn on sets the preference and leaves the panel open." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Documentation and records

**Files:**
- Modify: `README.md:204-214,222,499`
- Modify: `docs/privacy.md:110-112`
- Modify: `docs/providers/claude.md:47-48,57,81-86`
- Modify: `docs/architecture.md:180-182`
- Modify: `docs/HANDOFF.md:3,161,178-179,210-211,325`
- Modify: `docs/STATUS.md:2`
- Modify: `docs/superpowers/specs/2026-11-03-claude-usage-report-source-design.md:24,100,123,335`
- Modify: `docs/superpowers/specs/2026-11-12-claude-usage-probe-cadence-design.md:98`
- Test: `scripts/tests/notarize-app-tests.sh` (the README and STATUS contract; not changed)

**Interfaces:**
- Consumes: the names and behaviour of Tasks 1 to 7: the key `needlbar.claude.automaticUsageChecks.enabled`, the trigger `automaticResumed`, `claudeIsShown`, `ClaudeAutomaticRunsRelay`, `RefreshCoordinator.setClaudeAutomaticRunsAllowed`, and the in-app copy.
- Produces: documents only. Task 12 edits three of them again.

This task has no failing phase: the contract test passes before and after, and its job here is to prove the new README and STATUS text breaks none of its rules.

- [ ] **Step 1: README, "Claude Code and Anthropic's terms" and the prepared section**

The first edit adds the spec's paragraph word for word. That section had no sentence saying runs are scheduled unconditionally, so nothing is removed. The other three make the trigger list, "retries under backoff", the runs-per-day figure and "appears within about 15 minutes" conditional on the setting. No heading and no version string is added.

In `README.md`, replace

```markdown
never through a shell) and reads the documented `usage_report` field, which is
marked experimental. Runs happen at app start, on manual refresh (**Check now**, in the dashboard and in Settings),
when a displayed window's reset passes, and
after 15 minutes without a run. Automatic runs are in practice 15 minutes apart; the
5-minute minimum between them matters only after a reset or a failed run. Since
2026-11-12 a change in Claude Code's local usage records no longer starts a run: each
run makes `claude` scan its session transcripts from the last 7 days, and during use
those changes started a run every 5 minutes. Opening the dashboard
alone starts none. A reading stays current for 20 minutes. Usage, in Claude Code or
outside it, appears within about 15 minutes while the app is running and the Mac is
awake, or about 17 when a run is slow; **Check now** reads it at once.
That means about 96 runs a day, plus runs after resets and retries after failures; it was up to 288 a day. A run is
limited to 60 seconds (30 before 2026-11-12, when two runs were stopped at that limit) and 1 MiB of output, works in one fixed folder in the temporary directory that is emptied before each run,
```

with

```markdown
never through a shell) and reads the documented `usage_report` field, which is
marked experimental. Since 2026-11-16 automatic runs are opt-in and off by default. A run happens
on manual refresh (**Check now**, in the dashboard and in Settings) and, only with automatic checks
turned on and Claude shown, at app start, when automatic checks are turned on or Claude is shown
again, when a displayed window's reset passes, and
after 15 minutes without a run. Automatic runs are then in practice 15 minutes apart; the
5-minute minimum between them matters only after a reset or a failed run. Since
2026-11-12 a change in Claude Code's local usage records no longer starts a run: each
run makes `claude` scan its session transcripts from the last 7 days, and during use
those changes started a run every 5 minutes. Opening the dashboard
alone starts none. A reading stays current for 20 minutes. With automatic checks on, usage, in Claude Code or
outside it, appears within about 15 minutes while the app is running and the Mac is
awake, or about 17 when a run is slow; **Check now** reads it at once. With automatic checks off,
it appears only after **Check now**.
With automatic checks on, that means about 96 runs a day, plus runs after resets and retries after failures; it was up to 288 a day. With them off, no run starts without a click. A run is
limited to 60 seconds (30 before 2026-11-12, when two runs were stopped at that limit) and 1 MiB of output, works in one fixed folder in the temporary directory that is emptied before each run,
```

In `README.md`, replace

```markdown
Claude Code, suggests running `claude` in Terminal to check its sign-in if that continues,
and retries under backoff. It offers no button. Needlbar never runs `claude auth`
and writes no Claude configuration, though Claude Code may renew its own login
```

with

```markdown
Claude Code, suggests running `claude` in Terminal to check its sign-in if that continues,
and, with automatic checks on, retries under backoff. It offers no button. Needlbar never runs `claude auth`
and writes no Claude configuration, though Claude Code may renew its own login
```

In `README.md`, replace

```markdown
not pay for, resell or route anyone's Claude usage.

Anthropic's [legal and compliance page](https://code.claude.com/docs/en/legal-and-compliance)
```

with

```markdown
not pay for, resell or route anyone's Claude usage.

Needlbar runs `claude` on a schedule only if you turn that on. It is off by default, including
after an update, and Needlbar asks once. While it is off, Needlbar starts `claude` only when you
click Check now. While it is on, it runs `/usage` when Needlbar starts, when you turn it
on or show Claude again, about every 15 minutes, after a shown limit resets, and 5 to 30 minutes
after a failed automatic run. Automatic runs pause while Claude is hidden from both the menu bar
and the dashboard. Turning it off stops new automatic runs; one already started is stopped at 60
seconds at the latest.

Anthropic's [legal and compliance page](https://code.claude.com/docs/en/legal-and-compliance)
```

- [ ] **Step 2: Privacy, provider and architecture documents**

In `docs/privacy.md`, replace

```markdown
- Prepared for the next release, not in v0.3.14: Needlbar makes no Claude network request. It starts
  the user's installed `claude` automatically, without a click: at app start, after a displayed
  window resets, on backoff retries and every 15 minutes, as
  well as on manual refresh. Since 2026-11-12 a change in Claude Code's local usage records no
  longer starts it, because each run makes `claude` scan its own session transcripts from the last
```

with

```markdown
- Prepared for the next release, not in v0.3.14: Needlbar makes no Claude network request. It starts
  the user's installed `claude` without a click only if the user turned automatic checks on. That
  setting is off by default, including after an update. While it is on, runs start at app start,
  when it is turned on or Claude is shown again, after a displayed window resets, on backoff
  retries and every 15 minutes, and they pause while Claude is hidden from both the menu bar and
  the dashboard. While it is off, `claude` starts only on manual refresh (**Check now**),
  which is always available. Since 2026-11-12 a change in Claude Code's local usage records no
  longer starts it, because each run makes `claude` scan its own session transcripts from the last
```

In `docs/providers/claude.md`, replace

```markdown
  the killed app.
- **When:** at app start, on manual refresh (**Check now**, on the dashboard's Claude row and in Settings beside **View Claude usage**), when a
  displayed window's reset passes, and after 15 minutes without a run. Automatic runs are in
  practice 15 minutes apart: the minimum of 5 minutes between them matters only after a reset or a
```

with

```markdown
  the killed app.
- **When:** on manual refresh (**Check now**, on the dashboard's Claude row and in Settings beside **View Claude usage**) at any time.
  Automatic runs are opt-in since 2026-11-16 and off by default, including after an update: Settings
  has the toggle **Check Claude quota automatically**, and while it is off the dashboard's Claude row
  says "Automatic checks are off." with **Turn on** beside **Check now**. Only with that on, and while
  Claude is shown on the menu bar or the dashboard, a run also starts at app start, when automatic
  checks are turned on or Claude is shown again (at once if 5 minutes have passed since the last
  start, otherwise with the next periodic run), when a
  displayed window's reset passes, and after 15 minutes without a run. The widget and notifications
  do not count as shown. Turning automatic checks off drops queued runs and backoff and does not
  stop a run already started. Automatic runs are in
  practice 15 minutes apart: the minimum of 5 minutes between them matters only after a reset or a
```

In `docs/providers/claude.md`, replace

```markdown
- **After failures:** automatic runs wait 5, 10, 20, then 30 minutes. Any success resets this.
- **Freshness:** a reading is current for 20 minutes, then **Last known**. A failed run shows **Last
```

with

```markdown
- **After failures:** automatic runs wait 5, 10, 20, then 30 minutes. Any success resets this.
  Turning automatic checks off clears it, and while they are off no failure starts a wait or a retry.
- **Freshness:** a reading is current for 20 minutes, then **Last known**. A failed run shows **Last
```

In `docs/providers/claude.md`, replace

```markdown
| No readable report | **Could not read Claude Code's usage report** and the last checked time | Last known | Backoff |

The run after 15 minutes counts as a trigger, so the first state is tried again about every
15 minutes, further apart under backoff. A null `rate_limits` or null or empty `limits` is also what
Claude Code's schema reports while its own usage fetch is failing (offline, 429, 5xx), so it is not
treated as signed out. How a signed-out `claude` reports itself in this mode has not been observed,
and Needlbar does not guess it; until it is, a non-zero exit counts as a process failure. API-key, usage-billed and `claude setup-token` sessions produce no `usage_report`,
so they show the no-readable-report state. Usage, in Claude Code or outside it such as on the web,
appears within about 15 minutes while the app is running and the Mac is awake, or about 17 when a
```

with

```markdown
| No readable report | **Could not read Claude Code's usage report** and the last checked time | Last known | Backoff |

With automatic checks on, the run after 15 minutes counts as a trigger, so the first state is tried
again about every 15 minutes, further apart under backoff. With automatic checks off, the next
attempt in every row is the next **Check now**. A null `rate_limits` or null or empty `limits` is also what
Claude Code's schema reports while its own usage fetch is failing (offline, 429, 5xx), so it is not
treated as signed out. How a signed-out `claude` reports itself in this mode has not been observed,
and Needlbar does not guess it; until it is, a non-zero exit counts as a process failure. API-key, usage-billed and `claude setup-token` sessions produce no `usage_report`,
so they show the no-readable-report state. With automatic checks on, usage, in Claude Code or outside it such as on the web,
appears within about 15 minutes while the app is running and the Mac is awake, or about 17 when a
```

In `docs/architecture.md`, replace

```markdown
Prepared for the next release, not in v0.3.14: Claude has no login path. `RefreshCoordinator` runs
Claude on its own slot, off the cooperative pool, under `ClaudeUsageProbeSchedule`: at app start, on
manual refresh, when a displayed reset passes,
and after 15 minutes without a run, at most once every 5 minutes with backoff. Since 2026-11-12 a
changed Claude total in the usage refresh no longer starts a run, because each run scans the last 7
```

with

```markdown
Prepared for the next release, not in v0.3.14: Claude has no login path. `RefreshCoordinator` runs
Claude on its own slot, off the cooperative pool, under `ClaudeUsageProbeSchedule`: on manual
refresh at any time and, only while automatic runs are allowed, at app start, on being allowed again
(`automaticResumed`), when a displayed reset passes,
and after 15 minutes without a run, at most once every 5 minutes with backoff. Automatic runs are
allowed while the user's setting (`needlbar.claude.automaticUsageChecks.enabled`, off by default
since 2026-11-16) is on and `claudeIsShown` holds for the menu bar or the dashboard. The app computes
that on the main actor and `ClaudeAutomaticRunsRelay` sends it through one serial channel to
`RefreshCoordinator.setClaudeAutomaticRunsAllowed`. While not allowed, the schedule refuses every
non-manual trigger, queues nothing and records no backoff; turning off does not cancel a run in
flight. Since 2026-11-12 a
changed Claude total in the usage refresh no longer starts a run, because each run scans the last 7
```

- [ ] **Step 3: Handoff and status**

The handoff says what is built, what is not (the first-run window, until Task 12), that `docs/releases/v0.3.15.md` is left for the new release plan, and that the inquiry draft, which is outside the repository, must be updated by the user.

In `docs/HANDOFF.md`, replace

```markdown
# Claude continuation handoff

**Checkpoint:** 2026-11-13, updated for the Fable percent on the Overview widget, now beside the big Claude figure, which is
not released and was seen installed on 2026-11-13 (`fef7cf7`, Developer ID, light and dark); before that 2026-11-12, for the
```

with

```markdown
# Claude continuation handoff

**Checkpoint:** 2026-11-16, updated for opt-in automatic Claude checks, which are prepared and not
released and not yet run on a real machine; before that 2026-11-13, for the Fable percent on the Overview widget, now beside the big Claude figure, which is
not released and was seen installed on 2026-11-13 (`fef7cf7`, Developer ID, light and dark); before that 2026-11-12, for the
```

In `docs/HANDOFF.md`, replace

```markdown
The probe sends SIGKILL to its process group after any exit. That covers the group it
started; a process that moved to its own session or group is not covered. Claude runs only on app start, manual refresh, a
passed reset, a backoff retry and every 15 minutes; a dashboard open, waking or
```

with

```markdown
The probe sends SIGKILL to its process group after any exit. That covers the group it
started; a process that moved to its own session or group is not covered. Claude runs on manual refresh and, only with
automatic checks on (see below), on app start, a
passed reset, a backoff retry and every 15 minutes; a dashboard open, waking or
```

In `docs/HANDOFF.md`, replace

```markdown
installation the unified log should show only the triggers `startup`, `manual`, `windowReset`,
`backoffRetry` and `periodic`, automatic starts at least 15 minutes apart except after a reset or a
failure, and no `usageProbeTimedOut` with `durationMs` under 60,000.

**Fable on the widget (2026-11-13, prepared, not released).** Design:
```

with

```markdown
installation the unified log should show only the triggers `startup`, `manual`, `windowReset`,
`backoffRetry`, `periodic` and, since 2026-11-16, `automaticResumed`, automatic starts at least 15 minutes apart except after a reset or a
failure, and no `usageProbeTimedOut` with `durationMs` under 60,000.

**Automatic checks are opt-in (2026-11-16, prepared, not released).** Design:
`docs/superpowers/specs/2026-11-16-claude-automatic-checks-opt-in-design.md`. Plan:
`docs/superpowers/plans/2026-11-16-claude-automatic-checks-opt-in.md`. Needlbar starts `claude`
without a click only if the user turned that on. The setting is
`needlbar.claude.automaticUsageChecks.enabled`; a missing value means off, so it is off for new
installs and after an update. While off, only a manual refresh starts a run, and the schedule keeps
no pending run, retry or backoff. While on, automatic runs still pause while Claude is hidden from
both the menu bar and the dashboard (`claudeIsShown`); the widget and notifications do not count.
Turning on, or showing Claude again, requests one run with the new trigger `automaticResumed`, which
respects the 5-minute minimum; turning off never cancels a run in flight. Settings has the toggle
**Check Claude quota automatically** in the Claude pane, and while off the dashboard's Claude row
shows "Automatic checks are off." with **Turn on** beside **Check now**. The acceptance build shows
neither. The first-run window that asks once is the plan's second part and is not built yet, so the
README sentence "Needlbar asks once" is ahead of the code until then. With automatic checks off,
each launch starts with no Claude value until **Check now**, and Claude quota alerts fire only from
manual readings. `docs/releases/v0.3.15.md` still describes unconditional runs; the new release plan
rewrites it. Not yet checked on a real machine: with the setting off the unified log shows no
automatic trigger, and after turning on it shows `automaticResumed` and then `periodic`.

**Fable on the widget (2026-11-13, prepared, not released).** Design:
```

In `docs/HANDOFF.md`, replace

```markdown
Code and Anthropic's terms". The inquiry is drafted and the user sends it. If Anthropic objects, the
§11 fallback applies. A public release still needs a weekday log check, the signed-out `claude`
check, a new release plan and the user's separate request. No tag or release is authorized, and the
v0.3.15 release plan of 2026-11-02 is superseded.
```

with

```markdown
Code and Anthropic's terms". The inquiry is drafted and the user sends it. If Anthropic objects, the
§11 fallback applies. The inquiry draft is not in this repository; before it is sent it must say
that automatic runs are off until the user turns them on (spec 2026-11-16 §7). A public release
still needs a weekday log check, the signed-out `claude`
check, the inquiry sent, a new release plan and the user's separate request. No tag or release is authorized, and the
v0.3.15 release plan of 2026-11-02 is superseded.
```

In `docs/HANDOFF.md`, replace

```markdown
- `Sources/NeedlbarCore/Refresh/ClaudeUsageProbeSchedule.swift`
- `Sources/NeedlbarCore/Widget/WidgetProjectionMapper.swift`
```

with

```markdown
- `Sources/NeedlbarCore/Refresh/ClaudeUsageProbeSchedule.swift`
- `Sources/NeedlbarCore/Configuration/ClaudeVisibility.swift`
- `Sources/Needlbar/App/ClaudeAutomaticChecksPreferences.swift`
- `Sources/Needlbar/App/ClaudeAutomaticRunsRelay.swift`
- `Sources/NeedlbarCore/Widget/WidgetProjectionMapper.swift`
```

In `docs/STATUS.md`, replace

```markdown
# Needlbar Development Status

## 2026-11-15 Terms question decided: stated reading plus inquiry (prepared, not released)
```

with

```markdown
# Needlbar Development Status

## 2026-11-16 Automatic Claude checks become opt-in (prepared, not released)

- **Change.** Needlbar starts `claude` without a click only if the user turned automatic checks on.
  It is off by default, for new installs and after an update. Design:
  `docs/superpowers/specs/2026-11-16-claude-automatic-checks-opt-in-design.md`; plan:
  `docs/superpowers/plans/2026-11-16-claude-automatic-checks-opt-in.md`.
- **Why.** The prepared build ran `/usage` about 96 times a day without the user choosing it, and
  Anthropic's Consumer Terms §3 restrict access "through automated or non-human means" unless
  Anthropic explicitly permits it. A schedule the user turned on is the position Needlbar takes
  while it asks Anthropic.
- **Built.** The gate in `ClaudeUsageProbeSchedule` and `RefreshCoordinator`, the `automaticResumed`
  trigger, the pause while Claude is hidden from both the menu bar and the dashboard, the stored
  setting, the Settings toggle, and the dashboard row prompt with its neutral off state. The
  cadence, the limits and the parser are unchanged.
- **First-run window.** Not built yet; it is the plan's second part.
- **Verification.** Automated tests only. Nothing was installed and no real `claude` was run. Not
  yet seen on a real machine: the log with the setting off, `automaticResumed` then `periodic` after
  turning on, and the toggle and the row prompt in light and dark.
- **Still open before release.** A weekday log check, the signed-out `claude` check, the inquiry
  sent (its draft is not in this repository and must say automatic runs are off until the user
  turns them on), a new release plan and the user's separate request.

## 2026-11-15 Terms question decided: stated reading plus inquiry (prepared, not released)
```

- [ ] **Step 4: Dated amendments to the two earlier specs**

In `docs/superpowers/specs/2026-11-03-claude-usage-report-source-design.md`, replace

```markdown
below carry the dated changes.

**Scope:** Replace how Needlbar obtains Claude quota. Codex, Cursor, local usage,
```

with

```markdown
below carry the dated changes.

**Amended 2026-11-16:** automatic runs are opt-in and off by default. Without the user's choice
only a manual refresh starts `claude`; the automatic triggers apply only while the setting is on
and Claude is shown on the menu bar or the dashboard. The design is
`docs/superpowers/specs/2026-11-16-claude-automatic-checks-opt-in-design.md`; §3, §5 and §11 below
carry the dated changes.

**Scope:** Replace how Needlbar obtains Claude quota. Codex, Cursor, local usage,
```

In `docs/superpowers/specs/2026-11-03-claude-usage-report-source-design.md`, replace

```markdown
own installed CLI. This is an open **release gate** (§11).

## 4. Options
```

with

```markdown
own installed CLI. This is an open **release gate** (§11).

*Amended 2026-11-16:* a review of Anthropic's terms on this date found that Consumer Terms §3
restrict access "through automated or non-human means" unless Anthropic explicitly permits it.
Automatic runs are therefore off until the user turns them on, which is the position Needlbar takes
while it asks Anthropic.

## 4. Options
```

In `docs/superpowers/specs/2026-11-03-claude-usage-report-source-design.md`, replace

```markdown
source may invent a value.

**Removed:**
```

with

```markdown
source may invent a value.

*Amended 2026-11-16:* the order is unchanged, but the first source is read without a click only
while automatic checks are on and Claude is shown on the menu bar or the dashboard. While they are
off it is read only on a manual refresh, so after a launch the status line or nothing is shown
until **Check now**.

**Removed:**
```

In `docs/superpowers/specs/2026-11-03-claude-usage-report-source-design.md`, replace

```markdown
- If Anthropic objects, the fallback is status line, last known, and the usage link.

## 12. Known limits
```

with

```markdown
- If Anthropic objects, the fallback is status line, last known, and the usage link.
- *Amended 2026-11-16:* automatic runs ship off by default, and the inquiry says so. The release
  still needs a weekday log check, the signed-out `claude` check, the inquiry sent, a new release
  plan and the user's separate request.

## 12. Known limits
```

In `docs/superpowers/specs/2026-11-12-claude-usage-probe-cadence-design.md`, replace

```markdown
| Change in Claude Code's local usage records | **Removed.** |

The 5-minute minimum interval, single flight, the once-a-minute trigger check, and the rule
```

with

```markdown
| Change in Claude Code's local usage records | **Removed.** |

*Amended 2026-11-16:* every trigger in this table except **Check now** applies only while automatic
checks are on and Claude is shown on the menu bar or the dashboard, and automatic checks are off by
default. Turning them on, or showing Claude again, adds one trigger, `automaticResumed`: it starts
a run at once when 5 minutes have passed since the last start, and otherwise the periodic run
follows 15 minutes after that start. The design is
`docs/superpowers/specs/2026-11-16-claude-automatic-checks-opt-in-design.md`.

The 5-minute minimum interval, single flight, the once-a-minute trigger check, and the rule
```

- [ ] **Step 5: Run the documentation contract**

Run: `bash scripts/tests/notarize-app-tests.sh; echo "exit $?"`
Expected: the last two lines are `notarize-app shell contracts passed` and `exit 0`.

Run: `awk '/^### Claude Code and Anthropic.s terms/,/^## Development/' README.md | grep -c "0\.3\.1[45]"; awk '/^### Claude quota from the Claude Code usage report/,/^### Usage and quota monitoring/' README.md | grep -c "^### "`
Expected: `0`, then `2` (the section's own heading and the next one).

- [ ] **Step 6: Commit**

```bash
git add README.md docs/privacy.md docs/providers/claude.md docs/architecture.md \
  docs/HANDOFF.md docs/STATUS.md \
  docs/superpowers/specs/2026-11-03-claude-usage-report-source-design.md \
  docs/superpowers/specs/2026-11-12-claude-usage-probe-cadence-design.md
git commit -m "docs: describe opt-in automatic Claude checks" \
  -m "The README, privacy, provider and architecture documents say that Needlbar starts claude on a schedule only if the user turned that on, and that runs pause while Claude is hidden. The handoff and status record the change as prepared, not released, and the two earlier specs carry dated amendments." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Verify Part 1

**Files:** none changed.

**Interfaces:**
- Consumes: the commits of Tasks 1 to 8.
- Produces: the evidence for the first pull request.

- [ ] **Step 1: Run the project gate**

Run: `make test`
Expected: exit 0. The Swift part prints five `Test run with` lines, all `passed`. The gate includes `make widget-extension-test` (the widget search guard and the widget script) and `make notarize-test`. If the only failure is `cancelledWaiterDoesNotCancelSharedAnalyticsTask()`, see "One unrelated timing-sensitive test" under Test mechanics: run `make swift-test SWIFT_TEST_FILTER=AnalyticsSnapshotStore`, then `make test` again, and report both results.

- [ ] **Step 2: Compile the acceptance configuration and run its fixtures**

Run: `make acceptance-test`
Expected: exit 0. The acceptance build constructs `SettingsActions()` with no preference, so it compiles without the toggle or the prompt, and its fixtures do not read the developer's defaults.

- [ ] **Step 3: Package and smoke**

Run: `make package && ./scripts/tests/smoke-app-tests.sh && make smoke`
Expected: exit 0, with `smoke-app cleanup regressions passed` and the smoke script's own success line. The smoke script launches the packaged app with `NEEDLBAR_DISABLE_CLAUDE_USAGE_PROBE=1`; no `claude` process starts.

- [ ] **Step 4: Confirm the gate is the only path**

Run: `grep -rn "ClaudeUsageProbeSchedule(" Sources; grep -rn "claudeAutomaticRunsAllowed: true" Sources; echo "grep exit $?"`
Expected: two lines, both in `RefreshCoordinator.swift` and both `ClaudeUsageProbeSchedule(automaticRunsEnabled: claudeAutomaticRunsAllowed)`; then no line and `grep exit 1`: no source constructs an enabled schedule or a coordinator that is on unconditionally.

- [ ] **Step 5: Confirm the tree and stop**

Run: `git status --short; git log --oneline -8`
Expected: only `?? .superpowers/brainstorm/` is listed, and the eight commits of Tasks 1 to 8 are on `claude/claude-auto-checks-gate`. Report the results. Do not push or open the pull request without the user's request. Not checked by this plan, and left for the user on an installed build: the toggle and the row prompt in light and dark, turning on from Settings and from the row, and the log showing `automaticResumed` and then `periodic`.

---

# Part 2 / PR 2: the first-run window

Before Task 10:

```bash
git switch -c claude/claude-auto-checks-first-run
```

### Task 10: The first-run rule and its controller

**Files:**
- Create: `Sources/Needlbar/App/ClaudeUsageOnboarding.swift`
- Test: `Tests/NeedlbarTests/ClaudeUsageOnboardingTests.swift` (new)

**Interfaces:**
- Consumes: `ClaudeAutomaticChecksPreferences` (Task 3).
- Produces: `enum ClaudeUsageOnboarding` with `static let answeredVersionKey = "needlbar.onboarding.claudeUsage.answeredVersion"`, `static let currentVersion = 1` and `static func shouldShow(answeredVersion: Int, probeDisabled: Bool, claudeShown: Bool) -> Bool`. `enum ClaudeUsageOnboardingCopy` with `title`, `body`, `turnOn`, `notNow`. `enum ClaudeUsageOnboardingAnswer { case turnOn, notNow }`. `@MainActor protocol ClaudeUsageOnboardingPresenting: AnyObject` with `func present(onAnswer: @escaping @MainActor (ClaudeUsageOnboardingAnswer) -> Void)` and `func close()`. `@MainActor final class ClaudeUsageOnboardingController` with `init(defaults: UserDefaults, preferences: ClaudeAutomaticChecksPreferences, presenter: any ClaudeUsageOnboardingPresenting, probeDisabled: @escaping @MainActor () -> Bool, claudeShown: @escaping @MainActor () -> Bool)`, `var answeredVersion: Int` and `func presentIfNeeded()`.

- [ ] **Step 1: Write the failing test**

The fake presenter stands for the window: it reports a button, and it reports the user closing the window as "Not now", which is what the real window does in Task 11.

Create `Tests/NeedlbarTests/ClaudeUsageOnboardingTests.swift`:

```swift
import Foundation
import Testing
@testable import NeedlbarApp

// The first-run question about automatic Claude checks: the rule, the copy and
// the controller, driven through a fake presenter. No window is built here.
@Suite("ClaudeUsageOnboarding", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct ClaudeUsageOnboardingTests {
    // MARK: - The rule

    @Test func theWindowShowsOnlyWhenUnansweredWithTheProbeEnabledAndClaudeShown() {
        #expect(ClaudeUsageOnboarding.currentVersion == 1)
        #expect(ClaudeUsageOnboarding.answeredVersionKey == "needlbar.onboarding.claudeUsage.answeredVersion")
        for answeredVersion in [0, 1, 2] {
            for probeDisabled in [false, true] {
                for claudeShown in [false, true] {
                    let expected = answeredVersion < 1 && !probeDisabled && claudeShown
                    #expect(
                        ClaudeUsageOnboarding.shouldShow(
                            answeredVersion: answeredVersion, probeDisabled: probeDisabled, claudeShown: claudeShown
                        ) == expected,
                        "version \(answeredVersion), probe disabled \(probeDisabled), shown \(claudeShown)")
                }
            }
        }
    }

    @Test func theCopyIsTheApprovedText() {
        #expect(ClaudeUsageOnboardingCopy.title == "Check Claude quota automatically?")
        #expect(ClaudeUsageOnboardingCopy.body == "Needlbar can run /usage in the Claude Code you installed, under your own sign-in: when Needlbar starts, about every 15 minutes while it is running, when a limit resets, and sooner after a failed check. Needlbar does not read your Claude sign-in. If you leave this off, it runs only when you click Check now. You can change this in Settings.")
        #expect(ClaudeUsageOnboardingCopy.turnOn == "Turn on")
        #expect(ClaudeUsageOnboardingCopy.notNow == "Not now")
    }

    // MARK: - The controller

    @Test func itIsNotShownAndIsRecordedWhenTheSettingIsAlreadyOn() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.preferences.setEnabled(true)
        fixture.controller.presentIfNeeded()
        #expect(fixture.presenter.presentCount == 0)
        #expect(fixture.controller.answeredVersion == 1)
    }

    @Test func itIsShownOnceAndNothingIsRecordedUntilItIsAnswered() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.controller.presentIfNeeded()
        fixture.controller.presentIfNeeded()
        #expect(fixture.presenter.presentCount == 1)
        #expect(fixture.controller.answeredVersion == 0, "appearing records nothing")
        #expect(fixture.defaults.object(forKey: "needlbar.onboarding.claudeUsage.answeredVersion") == nil)

        // A quit before answering: the next launch shows it again.
        let nextLaunch = try Fixture(sharing: fixture)
        nextLaunch.controller.presentIfNeeded()
        #expect(nextLaunch.presenter.presentCount == 1)
    }

    @Test func turnOnSetsThePreferenceAndRecordsTheAnswer() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.controller.presentIfNeeded()
        fixture.presenter.answer(.turnOn)
        #expect(fixture.preferences.isEnabled)
        #expect(fixture.defaults.integer(forKey: "needlbar.onboarding.claudeUsage.answeredVersion") == 1)

        fixture.controller.presentIfNeeded()
        let nextLaunch = try Fixture(sharing: fixture)
        nextLaunch.controller.presentIfNeeded()
        #expect(fixture.presenter.presentCount == 1)
        #expect(nextLaunch.presenter.presentCount == 0, "answered: never shown again")
    }

    @Test func notNowAndClosingTheWindowLeaveItOffAndRecordTheAnswer() throws {
        // The presenter reports the user closing the window as "Not now".
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.controller.presentIfNeeded()
        fixture.presenter.answer(.notNow)
        #expect(!fixture.preferences.isEnabled)
        #expect(fixture.controller.answeredVersion == 1)
        fixture.controller.presentIfNeeded()
        #expect(fixture.presenter.presentCount == 1)
        #expect(fixture.presenter.closeCount == 0, "the presenter closed itself")
    }

    @Test func turningOnElsewhereClosesTheWindowAndRecordsTheAnswer() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.controller.presentIfNeeded()
        // From Settings or the Claude row.
        fixture.preferences.setEnabled(true)
        while !Task.isCancelled, fixture.presenter.closeCount == 0 {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(fixture.presenter.closeCount == 1)
        #expect(fixture.controller.answeredVersion == 1)
        #expect(fixture.preferences.isEnabled)
        // A late answer from the closed window changes nothing.
        fixture.presenter.answer(.notNow)
        #expect(fixture.preferences.isEnabled)
        #expect(fixture.controller.answeredVersion == 1)
    }

    @Test func itIsNotShownWithTheSmokeVariableAndNothingIsRecorded() throws {
        let fixture = try Fixture(probeDisabled: true)
        defer { fixture.tearDown() }
        fixture.controller.presentIfNeeded()
        #expect(fixture.presenter.presentCount == 0)
        #expect(fixture.controller.answeredVersion == 0)
    }

    @Test func whileClaudeIsHiddenItWaitsForALaterLaunch() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.claudeShown = false
        fixture.controller.presentIfNeeded()
        #expect(fixture.presenter.presentCount == 0)
        #expect(fixture.controller.answeredVersion == 0)
        fixture.claudeShown = true
        fixture.controller.presentIfNeeded()
        #expect(fixture.presenter.presentCount == 1)
    }
}

@MainActor
private final class FakePresenter: ClaudeUsageOnboardingPresenting {
    private(set) var presentCount = 0
    private(set) var closeCount = 0
    private var onAnswer: (@MainActor (ClaudeUsageOnboardingAnswer) -> Void)?

    func present(onAnswer: @escaping @MainActor (ClaudeUsageOnboardingAnswer) -> Void) {
        presentCount += 1
        self.onAnswer = onAnswer
    }

    func close() { closeCount += 1 }

    /// A button, or the user closing the window (which is "Not now").
    func answer(_ answer: ClaudeUsageOnboardingAnswer) { onAnswer?(answer) }
}

@MainActor
private final class Fixture {
    let defaults: UserDefaults
    let preferences: ClaudeAutomaticChecksPreferences
    let presenter = FakePresenter()
    var claudeShown = true
    private(set) var controller: ClaudeUsageOnboardingController!
    private let name: String

    /// `sharing` models the next launch: the same stored defaults, new objects.
    init(probeDisabled: Bool = false, sharing other: Fixture? = nil) throws {
        if let other {
            name = other.name
            defaults = other.defaults
        } else {
            name = "ClaudeUsageOnboarding.\(UUID().uuidString)"
            defaults = try #require(UserDefaults(suiteName: name))
        }
        preferences = ClaudeAutomaticChecksPreferences(defaults: defaults)
        controller = ClaudeUsageOnboardingController(
            defaults: defaults,
            preferences: preferences,
            presenter: presenter,
            probeDisabled: { probeDisabled },
            claudeShown: { [unowned self] in self.claudeShown }
        )
    }

    func tearDown() { defaults.removePersistentDomain(forName: name) }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeUsageOnboarding`
Expected: FAIL at build time: the test file cannot find `ClaudeUsageOnboarding`, `ClaudeUsageOnboardingCopy`, `ClaudeUsageOnboardingController` or `ClaudeUsageOnboardingPresenting` in scope. make ends with `make: *** [swift-test] Error 1`.

- [ ] **Step 3: Write the rule, the copy and the controller**

Create `Sources/Needlbar/App/ClaudeUsageOnboarding.swift`:

```swift
import Combine
import Foundation

/// The first-run question about automatic Claude checks (spec 2026-11-16 §5).
enum ClaudeUsageOnboarding {
    static let answeredVersionKey = "needlbar.onboarding.claudeUsage.answeredVersion"
    /// The window shows while the stored version is below this, which covers a
    /// new install and an update alike.
    static let currentVersion = 1

    /// Not shown on a smoke run, which sets the probe switch, so it neither
    /// flashes the window nor uses up the developer's answer. Not shown while
    /// Claude is hidden either: nothing is recorded and it waits for a later launch.
    static func shouldShow(answeredVersion: Int, probeDisabled: Bool, claudeShown: Bool) -> Bool {
        !probeDisabled && claudeShown && answeredVersion < currentVersion
    }
}

/// The window's copy. It does not say whether a run uses quota or sends a model
/// request; neither is verified.
enum ClaudeUsageOnboardingCopy {
    static let title = "Check Claude quota automatically?"
    static let body = "Needlbar can run /usage in the Claude Code you installed, under your own sign-in: "
        + "when Needlbar starts, about every 15 minutes while it is running, when a limit resets, and sooner "
        + "after a failed check. Needlbar does not read your Claude sign-in. If you leave this off, it runs "
        + "only when you click Check now. You can change this in Settings."
    static let turnOn = "Turn on"
    static let notNow = "Not now"
}

enum ClaudeUsageOnboardingAnswer: Equatable, Sendable {
    case turnOn
    case notNow
}

@MainActor
protocol ClaudeUsageOnboardingPresenting: AnyObject {
    /// Shows the window. `onAnswer` is called at most once: for a button, or for
    /// the user closing the window, which counts as "Not now".
    func present(onAnswer: @escaping @MainActor (ClaudeUsageOnboardingAnswer) -> Void)
    /// Closes the window without calling `onAnswer`.
    func close()
}

/// Shows the question once and records that it was answered. The answer is
/// recorded when the user answers or closes the window, not when the window
/// appears, so a crash or a quit before answering shows it again next launch.
@MainActor
final class ClaudeUsageOnboardingController {
    private let defaults: UserDefaults
    private let preferences: ClaudeAutomaticChecksPreferences
    private let presenter: any ClaudeUsageOnboardingPresenting
    private let probeDisabled: @MainActor () -> Bool
    private let claudeShown: @MainActor () -> Bool
    private var isPresented = false
    private var preferenceObservation: AnyCancellable?

    init(
        defaults: UserDefaults,
        preferences: ClaudeAutomaticChecksPreferences,
        presenter: any ClaudeUsageOnboardingPresenting,
        probeDisabled: @escaping @MainActor () -> Bool,
        claudeShown: @escaping @MainActor () -> Bool
    ) {
        self.defaults = defaults
        self.preferences = preferences
        self.presenter = presenter
        self.probeDisabled = probeDisabled
        self.claudeShown = claudeShown
    }

    /// A missing value reads as 0.
    var answeredVersion: Int {
        defaults.integer(forKey: ClaudeUsageOnboarding.answeredVersionKey)
    }

    func presentIfNeeded() {
        // Already turned on in Settings during a launch when the window waited:
        // nothing to ask, so the answer is recorded without showing it.
        if !isPresented, preferences.isEnabled, !probeDisabled(),
           answeredVersion < ClaudeUsageOnboarding.currentVersion {
            defaults.set(ClaudeUsageOnboarding.currentVersion, forKey: ClaudeUsageOnboarding.answeredVersionKey)
            return
        }
        guard !isPresented, ClaudeUsageOnboarding.shouldShow(
            answeredVersion: answeredVersion, probeDisabled: probeDisabled(), claudeShown: claudeShown()
        ) else { return }
        isPresented = true
        // Answered elsewhere: turned on from Settings or the Claude row while the
        // window is open. `@Published` reports a change before it is stored, so
        // the value is read on the next main-actor turn.
        preferenceObservation = preferences.$isEnabled.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.preferenceDidChange() }
        }
        presenter.present { [weak self] answer in self?.answered(answer) }
    }

    private func answered(_ answer: ClaudeUsageOnboardingAnswer) {
        guard isPresented else { return }
        recordAnswered()
        if answer == .turnOn { preferences.setEnabled(true) }
    }

    private func preferenceDidChange() {
        guard isPresented, preferences.isEnabled else { return }
        recordAnswered()
        presenter.close()
    }

    private func recordAnswered() {
        isPresented = false
        preferenceObservation = nil
        defaults.set(ClaudeUsageOnboarding.currentVersion, forKey: ClaudeUsageOnboarding.answeredVersionKey)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeUsageOnboarding`
Expected: `Test run with 9 tests in 1 suite passed`, and make exits 0.

- [ ] **Step 5: Commit**

```bash
git add Sources/Needlbar/App/ClaudeUsageOnboarding.swift \
  Tests/NeedlbarTests/ClaudeUsageOnboardingTests.swift
git commit -m "feat(claude): decide when to ask about automatic checks, once" \
  -m "The question shows while needlbar.onboarding.claudeUsage.answeredVersion is below 1, not on a smoke run and not while Claude is hidden. The answer is recorded when the user answers or closes the window, not when it appears, and the window closes when the setting is turned on elsewhere." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: The first-run window

**Files:**
- Create: `Sources/Needlbar/App/ClaudeUsageOnboardingWindowController.swift`
- Test: `Tests/NeedlbarTests/ClaudeUsageOnboardingWindowTests.swift` (new)

**Interfaces:**
- Consumes: `ClaudeUsageOnboardingPresenting`, `ClaudeUsageOnboardingAnswer` and `ClaudeUsageOnboardingCopy` (Task 10).
- Produces: `@MainActor final class ClaudeUsageOnboardingWindowController: NSObject, ClaudeUsageOnboardingPresenting, NSWindowDelegate` with `init(show: @escaping @MainActor (NSWindow) -> Void = <center, order front, activate the app>)` and `private(set) var window: NSWindow?`.

- [ ] **Step 1: Write the failing test**

The tests replace the `show` step, so no window is ordered front and the app is not activated.

Create `Tests/NeedlbarTests/ClaudeUsageOnboardingWindowTests.swift`:

```swift
import AppKit
import Foundation
import Testing
@testable import NeedlbarApp

// The first-run window itself. It is built but never put on screen: the
// controller's `show` step is replaced, so nothing is ordered front or activated.
@Suite("ClaudeUsageOnboardingWindow", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct ClaudeUsageOnboardingWindowTests {
    @Test func theWindowOffersTurnOnAndNotNowWithNotNowAsTheDefaultButton() throws {
        _ = NSApplication.shared
        var answers: [ClaudeUsageOnboardingAnswer] = []
        let windows = ClaudeUsageOnboardingWindowController(show: { _ in })
        windows.present { answers.append($0) }
        let window = try #require(windows.window)
        let content = try #require(window.contentView)
        let buttons = Self.buttons(in: content)
        #expect(buttons.map(\.title) == ["Turn on", "Not now"])
        #expect(buttons.filter { $0.keyEquivalent == "\r" }.map(\.title) == ["Not now"], "Return must not opt in")
        #expect(Self.labels(in: content) == [ClaudeUsageOnboardingCopy.title, ClaudeUsageOnboardingCopy.body])
        #expect(content.fittingSize.width == 460)

        try #require(buttons.first { $0.title == "Turn on" }).performClick(nil)
        #expect(answers == [.turnOn])
        #expect(windows.window == nil, "a button closes the window")

        windows.present { answers.append($0) }
        let again = try #require(windows.window?.contentView)
        try #require(Self.buttons(in: again).first { $0.title == "Not now" }).performClick(nil)
        #expect(answers == [.turnOn, .notNow])
    }

    @Test func theWindowReportsAButtonOnceAndAUserCloseAsNotNow() throws {
        _ = NSApplication.shared
        var answers: [ClaudeUsageOnboardingAnswer] = []
        var shown = 0
        let windows = ClaudeUsageOnboardingWindowController(show: { _ in shown += 1 })
        windows.present { answers.append($0) }
        windows.present { answers.append($0) }
        #expect(shown == 1)
        let window = try #require(windows.window)
        #expect(window.styleMask.contains(.closable))
        #expect(!window.isReleasedWhenClosed)

        // The user closes the window.
        window.close()
        #expect(answers == [.notNow])
        #expect(windows.window == nil)

        // Closed by the app after an answer elsewhere: no answer is reported.
        windows.present { answers.append($0) }
        windows.close()
        #expect(answers == [.notNow])
        #expect(windows.window == nil)
        #expect(shown == 2)
    }

    private static func buttons(in view: NSView) -> [NSButton] {
        if let button = view as? NSButton { return [button] }
        return view.subviews.flatMap { buttons(in: $0) }
    }

    private static func labels(in view: NSView) -> [String] {
        if let field = view as? NSTextField { return [field.stringValue] }
        return view.subviews.flatMap { labels(in: $0) }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeUsageOnboardingWindow`
Expected: FAIL at build time: the test file cannot find `ClaudeUsageOnboardingWindowController` in scope. make ends with `make: *** [swift-test] Error 1`.

- [ ] **Step 3: Write the window controller**

It is non-modal. A close the controller starts removes the delegate first, so `windowWillClose` only ever means the user closed the window.

Create `Sources/Needlbar/App/ClaudeUsageOnboardingWindowController.swift`:

```swift
import AppKit

/// A small non-modal window, built like `SettingsWindowController`: an
/// `NSWindow`, with the app activated for it. Not `NSAlert.runModal`, which
/// would block the main run loop at launch. The content is plain AppKit so the
/// default button is a property a test can read.
@MainActor
final class ClaudeUsageOnboardingWindowController: NSObject, ClaudeUsageOnboardingPresenting, NSWindowDelegate {
    private static let textWidth: CGFloat = 420

    private let show: @MainActor (NSWindow) -> Void
    private(set) var window: NSWindow?
    private var onAnswer: (@MainActor (ClaudeUsageOnboardingAnswer) -> Void)?

    init(show: @escaping @MainActor (NSWindow) -> Void = { window in
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }) {
        self.show = show
    }

    func present(onAnswer: @escaping @MainActor (ClaudeUsageOnboardingAnswer) -> Void) {
        guard window == nil else { return }
        self.onAnswer = onAnswer
        let content = makeContent()
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: content.fittingSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Needlbar"
        window.contentView = content
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        show(window)
    }

    func close() {
        onAnswer = nil
        closeWindow()
    }

    private func makeContent() -> NSView {
        let title = NSTextField(labelWithString: ClaudeUsageOnboardingCopy.title)
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let body = NSTextField(wrappingLabelWithString: ClaudeUsageOnboardingCopy.body)
        body.preferredMaxLayoutWidth = Self.textWidth

        let turnOn = NSButton(title: ClaudeUsageOnboardingCopy.turnOn, target: self, action: #selector(turnOnClicked))
        let notNow = NSButton(title: ClaudeUsageOnboardingCopy.notNow, target: self, action: #selector(notNowClicked))
        // The default button: the window can appear at login, and Return must not opt in.
        notNow.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, turnOn, notNow])
        buttons.orientation = .horizontal

        let stack = NSStackView(views: [title, body, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        NSLayoutConstraint.activate([
            body.widthAnchor.constraint(equalToConstant: Self.textWidth),
            buttons.widthAnchor.constraint(equalTo: body.widthAnchor),
        ])
        return stack
    }

    @objc private func turnOnClicked() { answer(.turnOn) }
    @objc private func notNowClicked() { answer(.notNow) }

    private func answer(_ answer: ClaudeUsageOnboardingAnswer) {
        let onAnswer = self.onAnswer
        self.onAnswer = nil
        closeWindow()
        onAnswer?(answer)
    }

    private func closeWindow() {
        guard let window else { return }
        self.window = nil
        window.delegate = nil
        window.close()
    }

    /// The close button. A close this controller started has already removed
    /// the delegate, so this is the user closing the window: "Not now".
    func windowWillClose(_ notification: Notification) {
        window = nil
        let onAnswer = self.onAnswer
        self.onAnswer = nil
        onAnswer?(.notNow)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeUsageOnboardingWindow`
Expected: `Test run with 2 tests in 1 suite passed`, and make exits 0.

- [ ] **Step 5: Commit**

```bash
git add Sources/Needlbar/App/ClaudeUsageOnboardingWindowController.swift \
  Tests/NeedlbarTests/ClaudeUsageOnboardingWindowTests.swift
git commit -m "feat(claude): add the first-run window for automatic checks" \
  -m "A small non-modal window with the approved title, body and two buttons. Not now is the default button, so Return at login does not opt in, and closing the window counts as Not now." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Present it from the production lifecycle

**Files:**
- Modify: `Sources/Needlbar/App/AppDelegate.swift:8,63,158,248,417`
- Modify: `docs/HANDOFF.md:195-196,351`
- Modify: `docs/STATUS.md:17`
- Modify: `docs/providers/claude.md:48`
- Test: `Tests/NeedlbarTests/AppDelegateLifecycleTests.swift:20,277`

**Interfaces:**
- Consumes: `ClaudeUsageOnboardingController` (Task 10), `ClaudeUsageOnboardingWindowController` (Task 11), `ClaudeUsageProbeSwitch.isDisabled()` (`AppDelegate.swift`), `claudeIsShown(_:)` (Task 2) and the `claudeAutomaticChecks` property (Task 4).
- Produces: `ProductionLifecycleServing` gains `func presentProductionOnboarding() async`, called by `ProductionLifecycleController.start()` directly after `startProductionMenu()`. `AcceptanceLifecycleServing` is unchanged.

- [ ] **Step 1: Write the failing test**

The order test expects the new step after the menu, and the recording double implements it.

In `Tests/NeedlbarTests/AppDelegateLifecycleTests.swift`, replace

```swift
    #expect(await services.events == [
        "menu.start", "system.start", "notifications.start", "publisher.start", "refresh.start", "recovery.start",
        "recovery.stop", "refresh.stop", "publisher.stop", "notifications.stop", "system.stop", "menu.stop",
```

with

```swift
    #expect(await services.events == [
        "menu.start", "onboarding.present", "system.start", "notifications.start", "publisher.start",
        "refresh.start", "recovery.start",
        "recovery.stop", "refresh.stop", "publisher.stop", "notifications.stop", "system.stop", "menu.stop",
```

In `Tests/NeedlbarTests/AppDelegateLifecycleTests.swift`, replace

```swift
    func startProductionMenu() async { events.append("menu.start") }
    func startProductionSystem() async { events.append("system.start") }
```

with

```swift
    func startProductionMenu() async { events.append("menu.start") }
    func presentProductionOnboarding() async { events.append("onboarding.present") }
    func startProductionSystem() async { events.append("system.start") }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `make swift-test SWIFT_TEST_FILTER=AppDelegateLifecycle`
Expected: FAIL in `productionLifecycleStartsAndStopsSystemMetricsBeforeMenuTeardown()` with one issue: the recorded events have no `"onboarding.present"`, because the lifecycle does not call the step yet. The run ends with `failed` and `with 1 issue`, and make ends with `make: *** [swift-test] Error 1`.

- [ ] **Step 3: Add the step and wire the controller**

The step runs after the menu bar has started and before the refresh starts. If the user answers "Turn on" before the coordinator starts, the setter only stores the value and `start()` then makes its `startup` run. The acceptance lifecycle has no such step.

In `Sources/Needlbar/App/AppDelegate.swift`, replace

```swift
    func startProductionMenu() async
    func startProductionSystem() async
```

with

```swift
    func startProductionMenu() async
    /// The first-run question about automatic Claude checks. The acceptance
    /// lifecycle has no such step, so acceptance runs never show it.
    func presentProductionOnboarding() async
    func startProductionSystem() async
```

In `Sources/Needlbar/App/AppDelegate.swift`, replace

```swift
        await services.startProductionMenu()
        guard running, generation == self.generation else { return }
```

with

```swift
        await services.startProductionMenu()
        guard running, generation == self.generation else { return }
        await services.presentProductionOnboarding()
        guard running, generation == self.generation else { return }
```

In `Sources/Needlbar/App/AppDelegate.swift`, replace

```swift
    private var claudeAutomaticRunsRelay: ClaudeAutomaticRunsRelay?
    private let widgetPublisher: WidgetProjectionPublisher?
```

with

```swift
    private var claudeAutomaticRunsRelay: ClaudeAutomaticRunsRelay?
    private var claudeUsageOnboarding: ClaudeUsageOnboardingController?
    private let widgetPublisher: WidgetProjectionPublisher?
```

In `Sources/Needlbar/App/AppDelegate.swift`, replace

```swift
                apply: { await refreshCoordinator.setClaudeAutomaticRunsAllowed($0) }
            )
```

with

```swift
                apply: { await refreshCoordinator.setClaudeAutomaticRunsAllowed($0) }
            )
            self.claudeUsageOnboarding = ClaudeUsageOnboardingController(
                defaults: .standard,
                preferences: claudeAutomaticChecks,
                presenter: ClaudeUsageOnboardingWindowController(),
                probeDisabled: { ClaudeUsageProbeSwitch.isDisabled() },
                claudeShown: { claudeIsShown(moduleConfiguration.systemMonitor) }
            )
```

In `Sources/Needlbar/App/AppDelegate.swift`, replace

```swift
        _ = try? ClaudeStatusLineConnectionManager().refreshEnabledHelper()
        await menuBarController.startObserving()
    }

    func startProductionSystem() async {
```

with

```swift
        _ = try? ClaudeStatusLineConnectionManager().refreshEnabledHelper()
        await menuBarController.startObserving()
    }

    func presentProductionOnboarding() async {
        claudeUsageOnboarding?.presentIfNeeded()
    }

    func startProductionSystem() async {
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make swift-test SWIFT_TEST_FILTER=AppDelegateLifecycle`
Expected: `Test run with 5 tests in 1 suite passed`, and make exits 0.

- [ ] **Step 5: Record that the window is built**

In `docs/HANDOFF.md`, replace

```markdown
shows "Automatic checks are off." with **Turn on** beside **Check now**. The acceptance build shows
neither. The first-run window that asks once is the plan's second part and is not built yet, so the
README sentence "Needlbar asks once" is ahead of the code until then. With automatic checks off,
each launch starts with no Claude value until **Check now**, and Claude quota alerts fire only from
```

with

```markdown
shows "Automatic checks are off." with **Turn on** beside **Check now**. The acceptance build shows
neither. A first-run window asks once, "Check Claude quota automatically?", after the menu bar has
started: it is non-modal, **Not now** is its default button, and closing it counts as **Not now**.
The answer is stored as `needlbar.onboarding.claudeUsage.answeredVersion` when the user answers or
closes the window, not when it appears. It is not shown with
`NEEDLBAR_DISABLE_CLAUDE_USAGE_PROBE=1`, in the acceptance build, or while Claude is hidden. If the setting is already on it is not shown and the answer is recorded, and it
closes when the setting is turned on elsewhere. Its layout has not been seen on a real machine. With automatic checks off,
each launch starts with no Claude value until **Check now**, and Claude quota alerts fire only from
```

In `docs/HANDOFF.md`, replace

```markdown
- `Sources/Needlbar/App/ClaudeAutomaticRunsRelay.swift`
- `Sources/NeedlbarCore/Widget/WidgetProjectionMapper.swift`
```

with

```markdown
- `Sources/Needlbar/App/ClaudeAutomaticRunsRelay.swift`
- `Sources/Needlbar/App/ClaudeUsageOnboarding.swift`
- `Sources/Needlbar/App/ClaudeUsageOnboardingWindowController.swift`
- `Sources/NeedlbarCore/Widget/WidgetProjectionMapper.swift`
```

In `docs/STATUS.md`, replace

```markdown
  cadence, the limits and the parser are unchanged.
- **First-run window.** Not built yet; it is the plan's second part.
- **Verification.** Automated tests only. Nothing was installed and no real `claude` was run. Not
```

with

```markdown
  cadence, the limits and the parser are unchanged.
- **First-run window.** Built in the plan's second part: a non-modal window shown once after the
  menu bar has started, with **Not now** as the default button. The answer is recorded when the
  user answers or closes the window. It is not shown on smoke or acceptance runs or while Claude is
  hidden. Its layout, in light and dark, has not been seen on a real machine.
- **Verification.** Automated tests only. Nothing was installed and no real `claude` was run. Not
```

In `docs/providers/claude.md`, replace

```markdown
- **When:** on manual refresh (**Check now**, on the dashboard's Claude row and in Settings beside **View Claude usage**) at any time.
  Automatic runs are opt-in since 2026-11-16 and off by default, including after an update: Settings
  has the toggle **Check Claude quota automatically**, and while it is off the dashboard's Claude row
```

with

```markdown
- **When:** on manual refresh (**Check now**, on the dashboard's Claude row and in Settings beside **View Claude usage**) at any time.
  Automatic runs are opt-in since 2026-11-16 and off by default, including after an update: a
  first-run window asks once, Settings
  has the toggle **Check Claude quota automatically**, and while it is off the dashboard's Claude row
```

- [ ] **Step 6: Run the documentation contract**

Run: `bash scripts/tests/notarize-app-tests.sh; echo "exit $?"`
Expected: the last two lines are `notarize-app shell contracts passed` and `exit 0`.

- [ ] **Step 7: Commit**

```bash
git add Sources/Needlbar/App/AppDelegate.swift \
  Tests/NeedlbarTests/AppDelegateLifecycleTests.swift \
  docs/HANDOFF.md docs/STATUS.md docs/providers/claude.md
git commit -m "feat(claude): ask once about automatic checks after the menu bar starts" \
  -m "The production lifecycle gains a step after the menu start that shows the first-run window when the rule allows it. The acceptance lifecycle has no such step, and a smoke run sets the probe switch, so neither shows the window." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Verify Part 2

**Files:** none changed.

**Interfaces:**
- Consumes: the commits of Tasks 10 to 12 on top of Part 1.
- Produces: the evidence for the second pull request.

- [ ] **Step 1: Run the project gate**

Run: `make test`
Expected: exit 0, with five `Test run with` lines, all `passed`. The note on `cancelledWaiterDoesNotCancelSharedAnalyticsTask()` in Task 9 Step 1 applies here too.

- [ ] **Step 2: Run the acceptance fixtures**

Run: `make acceptance-test`
Expected: exit 0.

Run: `make acceptance-test ACCEPTANCE_TEST_FILTER=AppDelegateLifecycle`
Expected: exit 0, including `acceptanceLifecycleStartsAndStopsOnlyAcceptanceSurfacesInOrder()`, whose expected order is unchanged: the acceptance lifecycle has no onboarding step.

- [ ] **Step 3: Package and smoke, and confirm no window**

Run: `make package && ./scripts/tests/smoke-app-tests.sh && make smoke`
Expected: exit 0. During `make smoke` no "Check Claude quota automatically?" window appears, because the script sets `NEEDLBAR_DISABLE_CLAUDE_USAGE_PROBE=1`. That the rule then shows nothing and records nothing is covered by `itIsNotShownWithTheSmokeVariableAndNothingIsRecorded()`.

- [ ] **Step 4: Confirm the tree and stop**

Run: `git status --short; git log --oneline -3`
Expected: only `?? .superpowers/brainstorm/` is listed, and the three commits of Tasks 10 to 12 are on `claude/claude-auto-checks-first-run`. Report the results. Do not push or open the pull request without the user's request, and do not start the app outside `make smoke`: a local build started without the smoke variable shows the window once and stores the answer in the developer's defaults (spec §8). Left for the user on an installed build: the window in light and dark, turning on from each of the three places, and the log showing `automaticResumed` and then `periodic`.

---

## Self-Review

**Spec coverage, section by section.**

| Spec | Where |
|---|---|
| §2 off by default; a missing preference means off | Task 3 (`aMissingValueMeansOff`), Task 1 (`automaticRunsAreOffByDefault`), Task 4 (`AppDelegate` initial value) |
| §2 Check now stays; a manual run never turns the schedule on | Task 1 (`aManualRequestStartsWhileOffAndDoesNotTurnTheScheduleOn`), Task 4 (`aFailedManualRunWhileOffGivesNoLaterRun`), Task 7 (`turnOnReachesItsClosureOnceAndNothingElse`) |
| §2 wake and connectivity never start Claude | Unchanged code; the existing `wakeAndConnectivityNeverStartARunEvenWithOneOverdue` still passes with the flag on |
| §2 told three ways | Task 6 (Settings), Task 7 (row), Tasks 10 to 12 (window) |
| §2 cadence unchanged | No constant changes; the existing cadence tests pass unchanged in Tasks 1 and 4 |
| §3 schedule | Task 1 |
| §3 coordinator, turning off, turning on | Task 4 |
| §3 trigger | Task 1 |
| §3 app: preference | Task 3 |
| §3 app: initial value and serial channel | Tasks 4 and 5 |
| §3 `NEEDLBAR_DISABLE_CLAUDE_USAGE_PROBE=1` | Unchanged line in `AppDelegate`; Task 9 Step 3 |
| §3 table | Task 1 (off row), Task 4 (on, shown), Tasks 2 and 5 (on, hidden); popover and Settings opening start no run in unchanged code |
| §4 hidden; resume when shown again | Task 2, Task 5 (`hidingAndShowingClaudeIsPushed`), Task 4 (resume is the setter turning on) |
| §4 README wording "paused while Claude is hidden from both the menu bar and the dashboard" | Task 8 |
| §5 what, once, where, when not shown, already on, answered elsewhere, copy, single purpose | Tasks 10, 11 and 12 |
| §5 Claude Code not installed: shown anyway | Task 10: the rule has no such input |
| §6 row with a reading unchanged | Task 7 (`aRowWithAReadingIsUnchangedApartFromThePrompt`) |
| §6 row with no reading while off | Task 7 (`offWithNoReadingAndNoRunTriedIsNeutral`, `aFailureFromAManualRunStillShowsAsToday`); interpretation 1 |
| §6 prompt, both layouts, acceptance shows none | Task 7 |
| §6 Settings toggle and captions; Check now unchanged | Task 6 |
| §6 menu bar and widget unchanged | No change to the renderer or the projection |
| §7 documentation | Task 8, and Task 12 for the window; the inquiry and the release notes are interpretation 8 |
| §8 risks | Recorded in `docs/HANDOFF.md` (Task 8); the developer-Mac risk is the stop rule in Task 13 |
| §9 schedule tests | Task 1 |
| §9 coordinator tests | Task 4: every listed case, plus an automatic run that fails after turning off |
| §9 app tests | Task 3, Task 2, Task 10, Task 5, Tasks 10 to 12, Tasks 6 and 7 |
| §9 smoke and acceptance show no window | Tasks 9 and 13 |
| §9 not automated | Named as left for the user in Tasks 9 and 13 |
| §10 two pull requests | Part 1 and Part 2 |

**Placeholder scan.** No step says "TBD", "similar to", or "add tests for the above". Every code step shows the code. The two `perl` commands replace repetitive single-argument insertions and each has a count check.

**Type and name consistency.** `automaticRunsEnabled` is the schedule's property and initializer label; `claudeAutomaticRunsAllowed` is the coordinator's initializer label and stored flag; `setAutomaticRunsEnabled(_:)` is the schedule's setter and `setClaudeAutomaticRunsAllowed(_:)` the coordinator's. `ClaudeAutomaticChecksPreferences.isEnabled` and `setEnabled(_:)` are used by the relay, `SettingsActions`, and the first-run controller. `SettingsActions.claudeAutomaticChecksEnabled` and `setClaudeAutomaticChecksEnabled(_:)` are used by `SettingsView` and `MenuBarController`. `claudeAutomaticChecksOff` is the one parameter name on `SystemDashboardPresentation`, `SystemDashboardModel.init` and `.update`. `ClaudeAutomaticChecksPrompt.turnOn` reads its two strings from `ClaudeAutomaticChecksCopy`. `ClaudeUsageOnboarding.shouldShow(answeredVersion:probeDisabled:claudeShown:)` matches the spec's signature. The trigger is `automaticResumed` everywhere. The keys are `needlbar.claude.automaticUsageChecks.enabled` and `needlbar.onboarding.claudeUsage.answeredVersion` in code, tests and documents.

**Found and fixed while reviewing.** A view test first asserted the caption through the hosted accessibility tree, which does not report a SwiftUI `Text` by label; the caption is now asserted on the presentation. The first-run window was first drawn in SwiftUI, where the default button could not be read by a test; it is AppKit now. The copy strings first lived beside the preference, which made two tasks edit one file; they have their own file, created in Task 6.
