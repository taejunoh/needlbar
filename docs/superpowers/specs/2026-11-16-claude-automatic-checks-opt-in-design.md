# Automatic Claude checks become opt-in

**Date:** 2026-11-16

**Status:** Approved by the user in conversation on 2026-11-16. It authorizes an implementation
plan only. Implementation, merge, installation, tag and release each still need the user's
separate request.

**Scope:** when Needlbar starts the user's installed `claude` to run `/usage` without a click.
It amends `2026-11-03-claude-usage-report-source-design.md` (§3 policy, §5 source order, §11
release) and `2026-11-12-claude-usage-probe-cadence-design.md` (the trigger table). The probe
itself, its limits, the parser, the 15-minute cadence, the status-line source, the widget
projection and the Claude logo are unchanged.

## 1. Problem

The prepared release runs `/usage` automatically: at app start, every 15 minutes, after a shown
limit resets, and on backoff retries. That is about 96 runs a day, usually all day, and the user
never chose it. A review of Anthropic's terms on 2026-11-16 found that Consumer Terms §3 restrict
access "through automated or non-human means" unless Anthropic explicitly permits it. A schedule
the user knowingly turned on is the strongest position Needlbar can take while it asks Anthropic,
and it is simple to describe truthfully in the README and the inquiry.

## 2. Decisions

- **Off by default,** for new installs and for people updating. A missing preference means off.
- **Check now stays.** While off, `claude` starts only on a manual refresh (Check now). *Corrected
  2026-11-16 while planning:* no built surface has a Retry that reaches the manual refresh (its only
  button belongs to a menu-bar controller that is no longer built), so the copy names Check now only. A manual run never turns the schedule on. Wake and
  connectivity recovery never start Claude, as today.
- **The user is told three ways:** a first-run window shown once, a prompt in the Claude row while
  off, and a Settings toggle.
- **Paused while Claude is hidden** (§4).
- **Cadence unchanged:** 15 minutes, 5-minute floor, backoff 5/10/20/30 minutes, 60-second limit.
- **Out of scope:** the Claude logo (kept; the inquiry asks for permission and it is replaced with
  the existing `sparkles` symbol only if Anthropic refuses), persisting the last reading across
  launches.

## 3. Gate

One rule, in one place: **an automatic run may start only while automatic runs are allowed.**

- **Schedule.** `ClaudeUsageProbeSchedule` gains `automaticRunsEnabled`, default `false`. It is
  checked first in `automaticRunIsAllowed`, which every non-manual `request` and `dueTrigger`
  already passes through, including the replay in `finishClaudeUsageProbe` and the 60-second tick.
  While off, a refused request does not set `pendingTrigger`, and `recordFailure` ignores
  non-manual triggers, so no backoff or retry can exist while off (an invariant, tested). Manual
  requests are unaffected.
- **Coordinator.** `RefreshCoordinator` takes `claudeAutomaticRunsAllowed: Bool` at init, with no
  default, so every caller states it; existing tests pass `true`. It gains
  `setClaudeAutomaticRunsAllowed(_:)`. `start()` builds `ClaudeUsageProbeSchedule(automaticRunsEnabled:)`
  from the stored flag and requests only `startup`. The setter while stopped only stores the value.
  The 60-second tick keeps running; while off it starts nothing. A call that does not change the
  value does nothing.
- **Turning off** sets `pendingTrigger = nil`, `retryPending = false`, `backoffUntil = nil` and
  `consecutiveAutomaticFailures = 0`, and keeps `lastStartedAt`. A run in flight is not cancelled: it finishes within the 60-second limit and its
  reading is applied. Cancelling would end `claude` while it may be renewing its own login.
- **Turning on** requests one run at once, with the new trigger `automaticResumed`, through the
  automatic path, so the 5-minute floor still applies. If that request is refused (a run in flight,
  or one started less than 5 minutes ago), it is queued only when `lastStartedAt` is nil; otherwise
  nothing is queued and the periodic run follows 15 minutes after the last start. So turning on
  right after Check now does not start a second run within the floor. Without this request nothing
  would start when no run has happened yet, because a periodic run needs a previous start.
- **Trigger.** `QuotaRefreshTrigger` gains `automaticResumed`, logged like the others, so the log
  does not show `startup` in the middle of a session.
- **App.** `ClaudeAutomaticChecksPreferences` follows `QuotaNotificationPreferences`: UserDefaults
  key `needlbar.claude.automaticUsageChecks.enabled`, absent means false, published state,
  `setEnabled`. `AppDelegate` passes the initial `preference && claudeIsShown` at init, and on a
  preference change or `ModuleConfiguration.didChangeNotification` recomputes it on the main actor
  and sends it through one serial channel (a single `AsyncStream` consumer), so values reach the
  coordinator in the order they were computed.
- `NEEDLBAR_DISABLE_CLAUDE_USAGE_PROBE=1` still removes the repository, so neither automatic nor
  manual runs start.

| Trigger | Off | On, Claude shown | On, Claude hidden |
|---|---|---|---|
| `startup`, `periodic`, `windowReset`, `backoffRetry`, `automaticResumed` | no run | runs | no run |
| `manual` (Check now) | runs | runs | runs |
| popover or Settings opened | no run | no run | no run |

## 4. Hidden

A pure function in NeedlbarCore, `claudeIsShown(_: SystemMonitorConfiguration)`, true if either
holds:

- the AI module is visible on the menu bar and Claude is visible in it;
- the AI section is visible on the dashboard and Claude is visible in it.

The widget and notifications do not count: a placed widget does not keep automatic runs going, and
its Claude column keeps the last value written. Becoming shown again while the preference is on
resumes like turning on. The README states it as "paused while Claude is hidden from both the menu
bar and the dashboard". `claudeIsShown` does not read the `needlbar.menuBar.claude.enabled` flag,
which belongs to a menu-bar controller that is no longer built. `ModuleConfiguration` still uses it
as the last fallback for provider visibility when no newer key exists, and `claudeIsShown` takes
the resolved configuration, so it always agrees with what is drawn.

## 5. First-run window

- **What.** A small non-modal window, shown once, built like `SettingsWindowController`
  (`NSWindow`, the app activated for it), after the menu bar has started. Not `NSAlert.runModal`,
  which would block the main run loop at launch.
- **Once.** One integer, `needlbar.onboarding.claudeUsage.answeredVersion`. The window shows while
  it is below the constant `1`, which covers a new install and an update alike. It is written when
  the user answers or closes the window, not when the window appears, so a crash or a quit before
  answering shows it again next launch.
- **Where.** It is presented from a new `ProductionLifecycleServing` step after
  `startProductionMenu`; the acceptance lifecycle has no such step, so acceptance runs never show it.
- **When not shown:** when `NEEDLBAR_DISABLE_CLAUDE_USAGE_PROBE=1` (the smoke
  script sets it, so smoke runs neither flash the window nor use up the developer's answer); and
  while Claude is hidden, in which case nothing is recorded and it waits for a later launch. These
  rules are one pure function, `shouldShow(answeredVersion:probeDisabled:claudeShown:)`.
- **Already on.** If the preference is already on at the first-run step (turned on in
  Settings during a launch when the window waited), the window is not shown and the answer is
  recorded.
- **Answered elsewhere.** If the preference is turned on from Settings or the Claude row while the
  window is open, the window closes and the answer is recorded.
- **Claude Code not installed:** shown anyway. Needlbar does not look for the CLI from Swift; turning
  on leads to the existing "not installed" guidance.
- **Copy:**
  - Title: "Check Claude quota automatically?"
  - Body: "Needlbar can run /usage in the Claude Code you installed, under your own sign-in: when
    Needlbar starts, about every 15 minutes while it is running, when a limit resets, and sooner
    after a failed check. Needlbar does not read your Claude sign-in. If you leave this off, it runs
    only when you click Check now. You can change this in Settings."
  - Buttons: "Turn on" and "Not now", with "Not now" as the default button, because the window can
    appear at login and Return must not opt in. Closing the window counts as "Not now".
  - The copy does not say whether a run uses quota or sends a model request; neither is verified.
- **Single purpose.** It does not offer the status-line connection.

## 6. Off state

- **Claude row with a reading:** unchanged. It is current for 20 minutes, then "Last known".
- **Claude row with no reading while off:** when no run has been tried, the reason line says
  "Automatic checks are off." in the secondary colour, with no orange, no "Could not update", and
  no error state on the dashboard. A failure from a manual run, such as "not installed", still
  shows as today.
- **Prompt:** in the dashboard Claude row, compact and standard layouts, while off: the caption
  "Automatic checks are off." and a borderless "Turn on" button beside "Check now". "Turn on" sets
  the preference. The acceptance build shows no prompt, so its fixtures do not depend on the
  developer's defaults.
- **Settings:** in the Claude pane, a toggle "Check Claude quota automatically" with one caption
  line: "Runs /usage in your Claude Code about every 15 minutes. Off: only when you click Check now." While on and Claude is hidden, the caption reads "Paused while Claude is hidden." The
  Settings Check now button and its visibility rule are unchanged.
- **Check now:** runs once; it does not turn the schedule on.
- **Menu bar and widget:** unchanged, "—" or the last value. The projection is unchanged.

## 7. Documentation

- **README**, "Claude Code and Anthropic's terms": add, replacing any sentence that says runs are
  scheduled unconditionally: "Needlbar runs `claude` on a schedule only if you turn that on. It is
  off by default, including after an update, and Needlbar asks once. While it is off, Needlbar
  starts `claude` only when you click Check now. While it is on, it runs `/usage` when
  Needlbar starts, when you turn it on or show Claude again, about every 15 minutes, after a shown
  limit resets, and 5 to 30 minutes after a failed automatic run. Automatic runs pause while Claude
  is hidden from both the menu bar and the dashboard. Turning it off stops new automatic runs; one
  already started is stopped at 60 seconds at the latest." In the prepared v0.3.15 section, the
  trigger list, "retries under backoff", the runs-per-day figure and "appears within about 15
  minutes" become conditional on the setting being on.
- `docs/privacy.md` (the automatic-run list), `docs/providers/claude.md` (when runs start),
  `docs/architecture.md` (Claude triggers), `docs/HANDOFF.md`, and a `docs/STATUS.md` entry marked
  prepared, not released.
- Dated amendments to the two specs named in Scope.
- The inquiry to Anthropic is updated to say automatic runs are off until the user turns them on.

## 8. Risks

- **A Retry wired later.** If a future change connects a Retry button to the manual refresh, it will
  also run `claude`, and the copy must name it.
- **No value after launch.** Readings live in memory, so with automatic runs off each launch starts
  with no Claude value until Check now. Persisting the last reading is a separate change.
- **Fewer alerts.** While off, Claude quota alerts fire only from manual readings.
- **Login launch.** People who start Needlbar at login see the window then.
- **Window on a developer Mac.** A local build without the smoke variable shows the window once and
  stores the answer, like any install.

## 9. Testing

- **Schedule (pure):** off refuses every non-manual trigger and sets nothing pending; manual starts
  while off; turning off clears pending, retry and backoff; turning on lets a due run start.
- **Coordinator:**
  - default off gives zero runs over many ticks, and no backoff or retry exists while off;
  - turning on right after Check now, or on, off, on within 5 minutes, gives no extra run within
    the floor;
  - `start()` with the flag on gives one `startup` run and no `automaticResumed`;
  - a failed manual run while off gives no later run;
  - turning on gives exactly one `automaticResumed` run, then periodic runs;
  - turning off with a held run lets it finish, applies its reading and never cancels;
  - the flag survives `stop()` and `start()`;
  - existing tests pass `claudeAutomaticRunsAllowed: true` and build the schedule with
    `automaticRunsEnabled: true`.
- **App:**
  - the preference defaults to off and persists;
  - a `claudeIsShown` truth table;
  - a `shouldShow` truth table;
  - pushes reach the coordinator in order (off after on stays off);
  - a fake presenter in the lifecycle tests: shown once, recorded on answer and on close, not shown
    and recorded when already on, closed and
    recorded when turned on elsewhere, not shown with the smoke variable;
  - presentation: the neutral off state and the prompt.
- The smoke and acceptance scripts still pass and show no window.
- **Not automated, checked by the user on an installed build:** the window and the row prompt in
  light and dark, turning on from each of the three places, and the log showing `automaticResumed`
  and then `periodic`.

## 10. Delivery

Two pull requests, each with its plan tasks:

1. The gate, the preference, the Settings toggle, the row prompt and off state, and the
   documentation.
2. The first-run window.

The release still needs a weekday log check, the signed-out `claude` check, the inquiry sent, a new
release plan and the user's separate request.
