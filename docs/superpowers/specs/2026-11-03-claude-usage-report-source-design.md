# Claude usage report as the quota source

**Date:** 2026-11-03

**Status:** Approved by the user on 2026-11-03, including automatic background
execution. It authorizes writing an implementation plan only. Implementation, merge,
installation, tag, and release each still need the user's separate request.

**Amended 2026-11-03:** The user chose to add a periodic run, so readings stay current
during quiet periods and usage outside Claude Code appears within about 15 minutes. See
§6 for the trigger and the 20-minute freshness window, and §12 for its cost.

**Amended 2026-11-03 (whole-branch review):** a null usage report is a failed check, not a
signed-out signal (§7, §8). The `/usage` working directory is one fixed folder, emptied before
each run, not a new temporary folder per run (§6). The smoke script switches the probe off
(§6).

**Amended 2026-11-12:** a change in Claude Code's local usage records no longer starts a run,
and the run deadline is 60 seconds, up from 30. Each `/usage` run scans the last 7 days of
Claude Code transcripts, so runs slowed to a median of about 8 seconds and two were stopped at
the deadline, while usage-record changes started a run every 5 minutes during use. The design
is `docs/superpowers/specs/2026-11-12-claude-usage-probe-cadence-design.md`; §6, §9 and §12
below carry the dated changes.

**Scope:** Replace how Needlbar obtains Claude quota. Codex, Cursor, local usage,
and API billing are out of scope.

This design was prepared from repository code, specifications, logs, public
documentation, and strings in the installed Claude Code binary. The investigation
read no credential, Keychain item, cookie, token, or authentication file. The user
personally ran every `claude` command and answered every Keychain dialog cited
here. The investigation did not call the undocumented usage endpoint itself; only
the installed app did, during its normal refreshes.

## 1. Problem

Claude quota in Needlbar has failed repeatedly in different ways: expired
credentials, ambiguous credentials, Keychain denial, Keychain dialogs, and
unrecognized responses. Earlier fixes treated each as a separate defect. They
share one cause: Needlbar acts as an unofficial Claude client that relies on two
things it does not own.

1. **Claude Code's Keychain item.** Claude Code owns and rewrites it.
2. **An undocumented usage response.** It appears on no Anthropic documentation
   page searched for this design.

No change inside Needlbar can make either dependency stable.

## 2. Evidence

Times are UTC, 2026-11-03, on macOS 27 with candidate v0.3.15.

| Time | Event | Result |
|---|---|---|
| 17:07:34 | Button click, dialog dismissed without approval | `credentialAccessDenied`; securityd logged that the user did not approve |
| 17:08:10 to 17:17:00 | Button click, dialog left open, then closed with the same error code | One dialog; the scheduled cycle at 17:12:11 finished in 0.7 s without Claude's result |
| 17:20:25 | Always Allow | `keychainCredentialExpired`, so the read itself worked |
| Before 17:21:32 | User ran `claude -p "hi"` | Succeeded |
| 17:21:36, 17:22:11 | Next reads | `permissionDenied`, no dialog |
| 17:27:48 | Always Allow again | `usageResponseUnrecognized` / `schemaChanged` |
| 17:32:11 to at least 19:02 | Scheduled reads, no user dialog | Passed the Keychain without a prompt, then `schemaChanged` every time |

**Verified**

- Always Allow lets no-UI reads through while the grant holds.
- `schemaChanged` is reached only after a 2xx response. The parser requires
  `five_hour` and `seven_day` with non-null `utilization`; a null or missing
  window fails the whole read.
- `fiveHourReceipt=2026-10-07…` in diagnostics is a retained status-line receipt,
  not a direct success.
- The user's `claude -p "/usage"` run returned `weekly_all` at 74% and
  `weekly_scoped` for Fable at 0%, with zero tokens and zero cost. No Keychain
  prompt was logged after 17:32. It returned no `session` row, and the session's
  `get_usage` tool also lists weekly windows only.

**Inferred, not verified**

- Claude Code rewriting the item discards the grant. The binary rewrites with
  `security add-generic-password -U`; the access-list effect rests on the
  17:21 sequence and user reports.
- `schemaChanged` comes from a missing or null five-hour window. The response was
  not inspected and the log has no sub-reason.
- An earlier `claude -p` in the v0.3.13 period succeeded right after, which remains
  unexplained.

## 3. Policy

Anthropic's [legal and compliance page](https://code.claude.com/docs/en/legal-and-compliance)
says developers "may not collect, store, or intermediate Claude.ai credentials or
session tokens" and that Anthropic does not permit third-party developers to offer
Claude.ai login in their own applications. Whether a transient read falls under
this is arguable; the direct path has no clear support, and this design closes the
2026-10-22 review item Q7 by retiring it.

The same page says "preinstalling or running Claude Code in your products or
services" requires the Commercial Terms, with examples about hosted sandboxes and
agent infrastructure. It does not clearly address a local app starting the user's
own installed CLI. This is an open **release gate** (§11).

## 4. Options

| Option | Outcome | Reason |
|---|---|---|
| Keep Keychain and endpoint, relax the parser | Rejected | Repeated approvals and policy exposure remain |
| Spawn `/usr/bin/security` to read the item | Rejected | Sidesteps the per-app decision macOS gives the user |
| Needlbar's own sign-in | Rejected | Prohibited by §3 |
| Partition list, helper, or own token cache | Rejected | Needs authority over Claude Code's item; a cache stores tokens |
| Status line only | Rejected as primary | Needs an active terminal session; the last receipt here is Oct 7; carries no Fable field |
| Click-only `/usage` | Rejected by the user | Values go stale until a click |
| Automatic `/usage`, status line, last known | **Chosen** | Removes both private dependencies |

## 5. Architecture

Source order for Claude quota:

1. **`usage_report`** from `/usage` run by the user's installed `claude`.
2. **Status-line data** the existing bridge already receives.
3. **Last known** values, labelled with the time they were checked.

`usage_report` is [documented](https://code.claude.com/docs/en/agent-sdk/typescript)
and marked experimental. A newer valid reading wins regardless of source, and no
source may invent a value.

**Removed:**

- Claude's Keychain read and `.credentials.json` read
- the direct usage endpoint call
- the **Allow Keychain access** button, its copy and tests
- `requestClaudeKeychainAccess` and the keychain sequencing that serves it
- the login-path leftovers that only served the direct path

**Unit boundaries:**

- **CLI locator:** finds the executable. Returns a path or `notInstalled`.
- **Usage probe:** runs the command under §6 limits. Returns bytes or a typed failure.
- **Report parser:** pure function from bytes to rows. Knows nothing about processes.
- **Probe scheduler:** decides when to run, inside the existing refresh coordinator.

The implementation plan decides whether each unit sits in `crates/needlbar-quota`
or `NeedlbarCore`, following existing structure.

## 6. Execution

**Triggers:**

- app start
- manual refresh
- passing the `resets_at` of a displayed window
- 15 minutes since the last run started (periodic; user decision, 2026-11-03)

Automatic runs happen at most once every 5 minutes. Only one runs at a time.
Manual refresh skips the interval and backoff, but joins a run in flight. Opening
the dashboard alone does not start a run, and neither does waking the Mac or regaining
a connection.

*Amended 2026-11-04:* the manual refresh control is **Check now**, on the dashboard's Claude row and in Settings beside **View Claude usage**.

*Amended 2026-11-12:* a change in Claude Code's local usage records was a trigger until this
date and is removed. Each run scans the last 7 days of transcripts, and during use those
changes started a run every 5 minutes. The periodic run now keeps readings current during use
and in quiet periods alike, so automatic runs are in practice 15 minutes apart. The 5-minute
minimum stays and matters only after a passed reset or a failed run.

The periodic run is a trigger like any other, last in priority, under the same interval,
backoff, and single-run rules. It is checked about once a minute. A clock set backwards
does not make it due. Time asleep counts, so a run that fell due during sleep can start
within about a minute of waking.

**Freshness:** a usage report reading is current for 20 minutes, then **Last known**. A
refresh that is due at 15 minutes can finish about two minutes later (amended 2026-11-12, from
about a minute and a half: with the 60-second deadline the slowest refresh ends 17:01 after
the last start), so a shorter
window would flip the label just before each refresh. A failed run shows **Last known** at
once. This applies wherever a Claude reading is labelled, including the widget's Claude
quota row. The status line keeps its 15-minute recency and its 24-hour maximum age.

**Backoff:** after consecutive automatic failures, wait 5, 10, 20, then 30 minutes.
Any success resets it.

**Locating the CLI:** check `~/.local/bin/claude`, `/opt/homebrew/bin/claude`, and
`/usr/local/bin/claude` in that order and take the first executable regular file
after resolving symlinks. Use no shell and no `PATH` search, so user shell functions
and aliases never apply.

**Command:** fixed argv only, with no user-derived text:

```text
claude -p /usage --no-session-persistence --strict-mcp-config
  --settings {"disableAllHooks":true} --output-format stream-json --verbose
```

**Limits:**

- one fixed working directory, `<TMPDIR>/needlbar-claude-usage`, created with mode 0700 if
  absent, checked with `symlink_metadata` to be a real directory and not a symlink (a launch
  failure otherwise, and nothing runs), and emptied before each run. Only one run happens at
  a time. *Amended 2026-11-03 (whole-branch review):* this replaces a new temporary directory
  per run. The CLI keeps records per working directory, and up to 288 new directories a day
  could grow the user's Claude Code folders without limit. That growth is unverified, and one
  fixed folder rules it out cheaply.
- `stdin` closed
- *Amended 2026-11-03 (whole-branch review):* the app starts no run when it is launched with
  `NEEDLBAR_DISABLE_CLAUDE_USAGE_PROBE=1`. `scripts/smoke-app.sh` sets it, because a smoke launch
  on a Mac with `claude` would otherwise start a real `/usage`, which can renew the login, and
  that child would outlive the killed app.
- a minimal environment: `HOME`, `USER`, `LOGNAME`, `TMPDIR`, a fixed `PATH`, and
  `CLAUDE_CONFIG_DIR` only if the app already has it
- a 60-second deadline, then terminate the process group (amended 2026-11-12: it was 30
  seconds)
- 1 MiB of stdout, then terminate; stderr is drained and discarded
- cancelled on app stop; results from an older generation are ignored

Acceptance measures the real duration. If it does not fit, the deadline changes in
this specification before release. *Amended 2026-11-12:* this clause was used. Runs reached
23.1 seconds and two were stopped at 30 seconds, so the deadline is now 60 seconds.

Needlbar never runs `claude auth`, never opens a login flow, and never writes Claude
configuration. Claude Code may renew its own login during a run. This is a deliberate
change to the earlier boundary and is recorded in §10.

## 7. Parsing

Read only the `usage_report` field. Discard everything else in the stream without
logging or storing it.

- Classify on `kind`, as the documentation requires.
- `session` maps to the five-hour window and `weekly_all` to the seven-day window.
- `weekly_scoped` maps to Fable when `scope.model.display_name` equals `Fable`,
  ignoring case. No documented identifier is available, so this is a known weak point.
- Every row is optional. A missing row hides that field only.
- Unknown kinds are ignored. A malformed row is skipped; the other rows still count.
- `percent` is a used share. Clamp finite values to 0–100. Skip non-finite ones.
- A null or missing `resets_at` shows no reset time.
- `rate_limits: null`, or `limits` null or empty, is **no usage available**, not a
  schema failure. It is a failed check, not a signed-out signal (see the note in §8).
- A run with no `usage_report` at all is **format changed**.

Readings are held in memory, except what existing last-known storage already keeps.
No new credential or raw output storage is added.

## 8. Failure states

| State | Dashboard and Settings | Values | Next attempt |
|---|---|---|---|
| CLI not found | Install guidance and the usage page link | Last known or none | Next trigger with backoff |
| No usage available | **Could not check Claude Code**, with a second line telling the user to run `claude` in Terminal to check its sign-in if this continues; no launch button | Last known or none | Backoff |
| Timed out, output too large, or process failure | Last checked time | Last known | Backoff |
| Rate limited | Last checked time | Last known | Backoff |
| Format changed | Last checked time | Last known | Backoff |

The periodic run counts as a trigger, so the first state is tried again about every
15 minutes, further apart under backoff. The others retry when backoff ends.

**Amended 2026-11-03 (whole-branch review):** `rate_limits: null` or null or empty
`limits` no longer means signed out. The CLI's own schema also leaves `limits` null while
its usage fetch is failing, including offline, 429 and 5xx, so a signed-in user could be
told to sign in and then not be retried for about 15 minutes. These shapes now map to
`ProviderUnavailable` with the origin `usageReportNoUsage` kept, so the user sees
**Could not check Claude Code** and a backoff retry follows. The second line, "If this
continues, run claude in Terminal to check its sign-in.", is the only sign-in hint. The
separate sign-in-required reason and its copy are removed because nothing reaches
them. Needlbar does not guess a signed-out state: how a signed-out `claude` reports
itself in this mode has not been observed, and the plan captures it in a user-run
check before any such state is added. Until then, a non-zero exit counts as a process
failure.

The UI never shows a made-up zero. Diagnostics record the failure reason, the
duration, and the row kinds seen. They never record tokens, output text, or emails.

## 9. Testing

**Automated, with a fake `claude` executable and fixtures:**

- all rows present; `session` missing; only Fable present
- `percent` above 100; malformed row; unknown kind
- `rate_limits` null; no `usage_report`
- timeout; oversized output; non-zero exit; CLI missing
- interval, backoff, single run, and manual join
- periodic run: due at 15 minutes, last in priority, behind the interval and backoff, never
  from a negative age; opening the dashboard, waking, and regaining a connection start none
- the not-installed state retried on the periodic run, under backoff; the no-usage state
  retried under backoff
- the 20-minute freshness boundary, a label that stays current across a periodic refresh,
  and **Last known** after a failed run
- no shell use, and exact argv and environment
- source order and last-known labelling
- no secret or raw output in logs
- a source-level check that the Claude path contains no Keychain or endpoint call

**Real-machine acceptance, user-run where credentials are involved:**

- Run for at least 24 hours, across a login renewal by Claude Code.
- Needlbar causes no `SecurityAgent` dialog.
- Quota keeps updating after renewal with no user action.
- Record run duration, peak memory, and CPU.
- Record the cost of about 96 runs a day, plus runs after resets and retries, and whether the
  label stays current across them (amended 2026-11-12: it was up to 288 runs a day while
  usage-record changes started runs).
- Confirm a `claude` prompt, if any, is noticed and recorded honestly.

## 10. Specification changes

If this design is approved, these are amended with dated notes rather than rewritten:

- `2026-10-07-claude-refresh-reliability-design.md`: "no Claude
  authentication/configuration write" no longer covers a renewal performed by
  Claude Code during a spawned `/usage`. Needlbar itself still performs no
  authentication or configuration write.
- `2026-10-22-claude-credential-renewal-design.md`: Q7 closes; option C's click-only
  condition is superseded for `/usage`; the objection that retirement loses Fable is
  answered by `weekly_scoped` rows.
- `2026-09-15-claude-passive-quota-recovery-design.md`: the ban on Terminal
  instructions gains an exception for the not-installed state and for the second line
  under **Could not check Claude Code** (amended 2026-11-03: it was first written for
  a signed-out state that Needlbar no longer guesses).
- `2026-09-25-claude-statusline-quota-bridge-design.md`: the status line becomes the
  secondary source.
- `docs/providers/claude.md` and `docs/privacy.md`: describe the new source, and remove
  Keychain, credential file, and endpoint statements for Claude.
- `docs/HANDOFF.md`, `docs/STATUS.md`, README, and the v0.3.15 plan and notes.

## 11. Release

- The current v0.3.15 candidate at `99f13bc` is not tagged. The number was never
  published, so the new design is proposed to ship as v0.3.15 under a new plan and
  new notes.
- **Release gate:** before any public build, the user decides how to resolve the §3
  question: ask Anthropic, or ship on a stated reading of the terms. Until then the
  build runs on this Mac only.
- If Anthropic objects, the fallback is status line, last known, and the usage link.

## 12. Known limits

This ends the Keychain approval loop in Needlbar. It does not promise that quota can
never fail.

- Usage outside Claude Code, such as on the web, appears within about 15 minutes while
  the app is running and awake. This means about 96 runs a day from the periodic run, plus runs
  after resets and retries after failures. *Amended 2026-11-12:* it was up to 288 a day while
  usage-record changes started runs, and its cost is no longer unmeasured (see the amended
  item on duration below).
- `usage_report` is experimental and can change; Needlbar then shows last known values.
- Fable matching depends on a display label.
- `claude` itself may show a Keychain prompt while running. None was logged in the one
  observed run, and an upstream report describes this happening.
- Users without the CLI get status-line data and the usage link only.
- *Amended 2026-11-12:* this item said that duration, memory, and CPU under repeated runs had
  not been measured. Duration has been, and it grows with the user's Claude Code use: a median
  of 4.9 s on 2026-11-05 and 8.1 s on 2026-11-12, with two runs stopped at 30 seconds. One run
  on 2026-11-05 took about 5.2 s of CPU and 454 MB of peak memory; CPU and memory were not
  measured again. `docs/STATUS.md` has the details under 2026-11-05 and 2026-11-12.
- Whether `/usage` has its own rate limit has not been measured. The periodic run makes
  this more likely to matter. If a limit shows up as `rate_limits: null`, the app shows
  **Could not check Claude Code** and retries under backoff (amended 2026-11-03).
