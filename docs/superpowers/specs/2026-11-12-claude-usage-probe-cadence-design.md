# Claude usage probe cadence and deadline

**Date:** 2026-11-12

**Status:** Approved by the user in conversation on 2026-11-12: usage-record changes stop
starting runs, and the run deadline becomes 60 seconds. It authorizes an implementation plan
only. Implementation, merge, installation, tag, and release each still need the user's
separate request.

**Scope:** When Needlbar starts `claude -p /usage` and how long a run may take. It amends
`docs/superpowers/specs/2026-11-03-claude-usage-report-source-design.md` §6, §9 and §12. The
command, its arguments and environment, parsing, failure states, the status-line source, and
the 20-minute freshness window are unchanged.

## 1. Problem

Runs of `/usage` have been getting slower, and two timed out. Each row comes from Needlbar's
unified log (`QuotaRefreshDiagnostic`, `durationMs`), read on the date given.

| Logs covering | Read on | Build | Claude Code CLI | Runs | Median | Longest completed | Over 20 s |
|---|---|---|---|---|---|---|---|
| 17 h to 2026-11-05 | 2026-11-05 | local ad-hoc | 2.1.292 | 125 | 4.9 s | 19.3 s | 0 |
| 2026-11-08 12:42 to 11-09 07:18 | 2026-11-09 | Developer ID | 2.1.292 | 140 | 6.2 s | 22.5 s | 1 |
| 2026-11-11 23:31 to 11-12 17:12 | 2026-11-12 | Developer ID, `8cd964c` | 2.1.321 | 104 | 8.1 s | 23.1 s | 5 |

The CLI version per row follows from the install dates: 2.1.292 on 2026-10-07, 2.1.321 on
2026-11-09 at 17:09 local. Two runs on 2026-11-12 were stopped at the 30-second deadline
(`usageProbeTimedOut`); their real lengths are unknown. The first started at 16:26 local
(30.5 s with the stop grace), and the next two runs succeeded in 17.3 s and 10.8 s. The second
started at 17:52 local (30.6 s with the stop grace), after the window the table covers, which
ends at 17:12; it was seen in the log afterwards, and the next run succeeded in 11.1 s. Nine of
the ten slowest runs that day fell between 12:11 and 16:32, almost all started by usage-record
changes while the user was working in Claude Code. The second row is a session receipt and is
not in `docs/STATUS.md`.

## 2. Cause

**Observed:**

- Text extracted from the installed CLI 2.1.321 shows `/usage` in non-interactive mode
  scanning the transcripts under `~/.claude/projects` whose modification time is within a
  7-day constant (604,800,000 ms), to build its usage breakdown.
- No flag, environment variable or setting that turns this off was found.
- On 2026-11-12 the files in that window were 1,665 transcripts, about 4.93 GB (sizes only; no
  content was read).
- About 0.7 GB of transcripts last modified on 2026-11-05 at 06:42 left the 7-day window on
  2026-11-12 at 06:42. Quiet-time runs went from 7.56 s (06:36) to 6.0 s (06:51), after three
  hours at 7.6 to 7.7 s. This is one event: it shows that the volume in the window matters,
  not a rate per gigabyte.

**Inferred:**

- Each run reads those files in full, and no cache between runs was found.
- The second and third rows of §1 suggest 2.1.321 costs more per gigabyte than 2.1.292: the
  median rose while the window shrank. No run of both versions on the same data was made.
- The 15 to 30-second runs come from contention during heavy use. At the time of the
  investigation the Mac had about 15.9 GB of swap in use, a load average of 8 to 11, and
  `fseventsd` near 100 percent CPU after 41 days of uptime.

Needlbar's own share is small: it logs completion 20 to 30 ms after the child exits.

A run now takes about 8 seconds of wall time at the median. CPU was last measured on
2026-11-05, at 5.2 seconds for a 4.3-second run. The files in scope total about 4.93 GB; the
bytes actually read were not measured. The cost grows with the user's Claude Code use. While
Claude Code is in use, usage-record changes started a run every 5 minutes, up to 12 an hour.
On 2026-11-05 they were 90 of 125 runs.

## 3. Decision

1. **A change in Claude Code's local usage records no longer starts a run.** The periodic
   run keeps readings current every 15 minutes, during use and in quiet periods alike.
2. **The run deadline is 60 seconds**, up from 30.

The user chose a 15-minute delay during use over 10 minutes and over spacing based on the
last run's duration.

**Options not taken:**

- Allowing a usage-record change to start a run only 15 minutes after the last start. The
  periodic run is due at that moment anyway, so it differs by at most one once-a-minute check,
  and it needs a per-trigger interval plus care with the pending request, which today is
  released after 5 minutes.
- Raising the 5-minute minimum interval for every automatic run to 15 minutes. It saves
  nothing more and delays the run after a passed reset and the retry after a failure.
- Pointing `CLAUDE_CONFIG_DIR` at a smaller folder. It is expected to change where Claude Code
  finds its login; this was not tested, because testing it would risk the login state.

## 4. Triggers after this change

| Trigger | Behaviour |
|---|---|
| App start | Unchanged: a run starts at once. |
| **Check now** | Unchanged: starts at once, or joins the run in flight. |
| Passing a displayed window's `resets_at` | Unchanged: due on the next once-a-minute check once 5 minutes have passed since the last start. |
| Retry after an automatic failure | Unchanged: backoff of 5, 10, 20, then 30 minutes. A failure because Claude Code is not installed still does not retry when backoff ends; it waits for the next trigger, which is now the periodic run, a reset, **Check now** or app start. |
| 15 minutes since the last start (periodic) | Unchanged. |
| Change in Claude Code's local usage records | **Removed.** |

The 5-minute minimum interval, single flight, the once-a-minute trigger check, and the rule
that opening the dashboard, waking the Mac or regaining a connection starts no run all stay.
In practice automatic runs are now 15 minutes apart; the 5-minute minimum matters only after a
reset or a failure.

The pending-request path in `ClaudeUsageProbeSchedule` stays on purpose. After this change only
an app start refused because an older run is still in flight uses it.

Needlbar still reads Claude Code's local usage records for token totals and costs; only the
link from a change in them to a `/usage` run is removed.

## 5. What the user sees

- **Age of a reading:** at most about 17 minutes before the next one lands: 15 minutes, plus
  up to one 60-second check, plus a run of up to 60 seconds and the stop grace (1,021 seconds).
  That is under the 20-minute freshness window by 2 minutes 59 seconds, by design. During
  continuous use the age was typically about 6 to 7 minutes before.
- **Late check under load:** the margin is the same as for quiet periods today, but it now
  applies during use too, when the Mac is busiest. A check that runs late can briefly flip the
  label to **Last known** before the reading lands.
- **After a failed run:** the reading shows **Last known** at once, as today. The retry comes
  5 minutes later, so the next reading is about 21 to 24 minutes old, and about 32 to 36
  minutes after two failures in a row.
- **Status line:** it does not fill the gap for this user. Its only Claude values are the
  five-hour and seven-day windows, and status-line commands run only in interactive terminal
  sessions. On the maintainer's Mac its `quota.json` was last written on 2026-10-07 (file date
  checked on 2026-11-12), because the maintainer uses the desktop app's Code tab
  (`docs/HANDOFF.md`). For terminal users it still supplies those two windows between runs, as
  before.
- **Alerts:** the five-hour and seven-day alerts come only from the usage report, never from
  the status line, and Fable has none. They can arrive up to about 17 minutes after the change.
  On this account only the seven-day alert applies, because the report has no five-hour row.
- **Check now** remains the way to get a current value at once. While a run is in flight it
  joins that run, so the longest wait grows from about 30 to about 60 seconds.

## 6. Deadline

60 seconds is twice the old deadline. The longest completed run was 23.1 seconds, and the two
runs that were stopped at 30 seconds would have taken longer by an unknown amount. A run that
times out has already paid its full cost and returns nothing, then is retried 5 minutes later, so a
deadline close to the observed lengths wastes more than it saves. 45 seconds was rejected
because the cost grows with transcript volume.

A timeout stays an automatic failure with backoff. The 1 MiB output cap, the 0.5-second stop
grace, the process-group kill after any exit, and stopping a run when the app quits are
unchanged. The deadline and the freshness window are independent of the widget's reload
schedule.

## 7. Code

- `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`: remove the usage-record change
  detection that requests a run: `noteClaudeUsageRecords` with its doc comment,
  `lastClaudeUsageTotalTokens` and its reset in `start()`, and the call in
  `finishUsageRefresh` with the comment and generation guard that exist only for it. Update
  the comment that mentions a deferred usage change, and the exhaustive trigger `switch`.
- `Sources/NeedlbarCore/Refresh/QuotaRefreshActivity.swift`: remove the
  `usageRecordsChanged` trigger, which no longer has a caller. Nothing parses its log name, it
  is not stored, and it does not cross the Rust bridge. Removing it makes the absence of a
  usage-record run a compile-time fact.
- `Sources/NeedlbarCore/Refresh/ClaudeUsageProbeSchedule.swift`: unchanged in behaviour; its
  comment on the refused request no longer names a usage change.
- `crates/needlbar-quota/src/providers/claude_usage_probe.rs`: the default deadline becomes
  60 seconds.
- Comments that state the 30-second deadline or the 16:31 bound
  (`RefreshCoordinator.swift`, `ClaudeQuotaPresentationSelector.swift`,
  `crates/needlbar-bridge/src/quota.rs`) become 60 seconds and 17:01.

## 8. Testing

- **New:** a change in Claude usage totals starts no `/usage` run. The test changes the total
  once within 5 minutes of the startup run and once after 5 minutes, then expects only
  `[.startup, .periodic]`, with the second run starting 900 seconds after the first.
- **Schedule tests** (`ClaudeUsageProbeScheduleTests.swift`) that used the removed trigger use
  `.startup` where they go through `request()`, and `.periodic` where they record a failure.
- **Coordinator tests** (`ClaudeUsageProbeCoordinatorTests.swift`):
  - tests that expected a run after a usage-record change are removed or rewritten to the
    periodic timing;
  - the freshness bound of 991 seconds (900 + 60 + 31) becomes 1,021 (900 + 60 + 61), and the
    "a 30-second run" message is updated;
  - the not-installed test uses periodic runs: failures at 0, 900 and 1,800 seconds, then the
    20-minute backoff holds the periodic run due at 2,700 seconds until 3,000.
- **Freshness guard** (`ClaudeUsageFreshnessTests`): uses 60 + 1 seconds and still holds,
  1,021 under 1,200.
- **Rust:** a test fixes the default deadline at 60 seconds.
- Existing backoff, manual and single-flight tests still pass.
- **Not automated, checked on a real machine after installation:** the unified log shows only
  the triggers `startup`, `manual`, `windowReset`, `backoffRetry` and `periodic`; automatic
  starts are at least 15 minutes apart except after a reset or a failure; and no
  `usageProbeTimedOut` appears with `durationMs` under 60,000.

## 9. Documentation

Dated notes or edits, each saying what changed and why:

- **the 2026-11-03 spec:** an "Amended 2026-11-12" note in its header, as for its earlier
  amendments; §6 triggers and the 5-minute wording; the freshness margin ("about a minute and
  a half" becomes about two minutes); the deadline in the limits, and the clause saying the
  deadline changes in that specification if it does not fit, which this amendment exercises;
  the "288 a day" figures in §9 and §12; and the §12 sentence saying cost has not been
  measured.
- **the 2026-11-03 plan** (`docs/superpowers/plans/2026-11-03-claude-usage-report-source.md`):
  an amendment note at the top, covering its decisions, its usage-change detection section and
  its acceptance checklist (5-minute spacing, `trigger=usageRecordsChanged`, 288 runs).
- **`README.md`:** the trigger list; "at most once every 5 minutes" reworded to say runs are
  in practice 15 minutes apart; "up to 288 a day" replaced by about 96 plus resets and
  retries; the 30-second limit; the earlier cost observation; and the sentence saying a full
  day on a Developer ID build has not been observed.
- `docs/providers/claude.md`, `docs/privacy.md`, `docs/architecture.md`, `docs/HANDOFF.md`,
  `docs/releases/v0.3.15.md`.
- **`docs/STATUS.md`:** a new entry with the measurements in §1 and §2 and this decision.

No in-app text mentions the cadence or the deadline.

## 10. Not in scope, and when to revisit

- **The idle cost:** the periodic run still makes about 96 runs a day, each scanning up to the
  whole 7-day window. Lengthening it collides with the 20-minute freshness window and the
  2026-11-03 decision to keep the periodic run, so it is a separate decision.
- **Upstream:** a way to skip the transcript scan in `-p /usage`, or a cache, would remove the
  cost at its source. Asking Anthropic is the user's call.
- **Revisit** if runs approach 60 seconds, rather than raising the deadline again, or if a
  later CLI version changes the cost.
- The cause in §2 is specific to CLI 2.1.321 and to this machine's data and load.
