# Claude provider

Needlbar treats Claude usage and Claude quota as separate sources.

## Usage source

The pinned `tokscale-core` engine reads the documented Claude local roots:

- `~/.claude/projects`
- `~/.claude/transcripts`

Needlbar delegates discovery, parsing, deduplication, aggregation, and cost estimation to that engine. It does not copy Claude transcript parsing into the application or display transcript content.

## Quota source

Prepared for the next release, not in v0.3.14. The public v0.3.14 still reads Claude Code's
Keychain item or credentials file and calls the usage endpoint; everything below replaces that.

Quota comes from `/usage` run by the user's installed `claude`. Needlbar reads the
[documented](https://code.claude.com/docs/en/agent-sdk/typescript) `usage_report` field of the
assistant message, which is marked experimental. It reads no Claude Keychain item and no
credential file, and it calls no Anthropic endpoint itself.

Source order for each window: the usage report, then Claude Code status-line data the optional
bridge received, then last-known values labelled with the time they were checked. A newer valid
reading wins regardless of source, and no source invents a value.

### Running `/usage`

- **Location:** the first executable regular file, after resolving symlinks, among
  `~/.local/bin/claude`, `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`. No shell and no
  `PATH` search, so shell functions and aliases never apply.
- **Command:** `claude -p /usage --no-session-persistence --strict-mcp-config --settings
  {"disableAllHooks":true} --output-format stream-json --verbose`, with no user-derived text.
- **Limits:** one fixed working directory, `<TMPDIR>/needlbar-claude-usage`, created with mode 0700,
  refused if it is a symlink or not a directory, and emptied before each run (the CLI keeps records
  per working directory, so a new folder per run could accumulate); no standard input; an
  environment of only `HOME`, `USER`, `LOGNAME`, `TMPDIR`, a fixed `PATH`, and `CLAUDE_CONFIG_DIR`
  if the app already has it; 60 seconds (30 before 2026-11-12, when two runs were stopped at that
  limit), then the process group is terminated; 1 MiB of standard
  output, then the same; standard error discarded; cancelled when the app stops. After any exit,
  including a normal one, the process group also receives SIGKILL. That covers the group Needlbar
  started; a process that moved to its own session or group is not covered.
- **Switch:** launching the app with `NEEDLBAR_DISABLE_CLAUDE_USAGE_PROBE=1` starts no run. The smoke
  script sets it, so a smoke launch never starts a real `claude` that could renew the login and outlive
  the killed app.
- **When:** on manual refresh (**Check now**, on the dashboard's Claude row and in Settings beside **View Claude usage**) at any time.
  Automatic runs are opt-in since 2026-11-16 and off by default, including after an update: a
  first-run window asks once, Settings
  has the toggle **Check Claude quota automatically**, and while it is off the dashboard's Claude row
  says "Automatic checks are off." with **Turn on** beside **Check now**. Only with that on, and while
  Claude is shown on the menu bar or the dashboard, a run also starts at app start, when automatic
  checks are turned on or Claude is shown again (at once if 5 minutes have passed since the last
  start, otherwise with the next periodic run), when a
  displayed window's reset passes, and after 15 minutes without a run. The widget and notifications
  do not count as shown. Turning automatic checks off drops queued runs and backoff and does not
  stop a run already started. Automatic runs are in
  practice 15 minutes apart: the minimum of 5 minutes between them matters only after a reset or a
  failed run. Only one runs at a time. Since 2026-11-12 a change in Claude Code's local usage
  records no longer starts a run, because each run makes `claude` scan its session transcripts from
  the last 7 days and those changes started a run every 5 minutes during use. Manual refresh skips the interval and backoff but joins
  a run in flight. Opening the dashboard, waking the Mac and regaining a connection do not
  themselves start a run, but a periodic run that fell due during sleep starts within about a minute
  of waking, when the once-a-minute check finds it overdue. If Codex is failing, each dashboard open retries Codex; that starts no Claude run and no dialog.
- **After failures:** automatic runs wait 5, 10, 20, then 30 minutes. Any success resets this.
  Turning automatic checks off clears it, and while they are off no failure starts a wait or a retry.
- **Freshness:** a reading is current for 20 minutes, then **Last known**. A failed run shows **Last
  known** at once. Status-line readings keep their own 15-minute recency and 24-hour maximum age.

Needlbar never runs `claude auth`, never opens a login flow and never writes Claude configuration.
Claude Code may renew its own login during a run, and `claude` itself may show a Keychain prompt.

### Reading the report

`session` is the five-hour window, `weekly_all` the seven-day window, and `weekly_scoped` is Fable
when `scope.model.display_name` equals `Fable`, ignoring case. That label is a known weak point,
because no documented identifier exists. Every row is optional: a missing row hides that field
only, an unknown kind is ignored, and a malformed row is skipped. `percent` is a used share,
clamped to 0-100. Everything else in the output is discarded without being logged or stored.

### What the user sees

| State | Shown | Values | Next attempt |
| --- | --- | --- | --- |
| Claude Code not found | **Install Claude Code to see quota** and the usage link | Last known or none | Next trigger, with backoff |
| No usage available | **Could not check Claude Code**, and "If this continues, run claude in Terminal to check its sign-in."; no launch button | Last known or none | Backoff |
| Timed out, too much output, or the process failed | **Could not check Claude Code** and the last checked time | Last known | Backoff |
| Rate limited | **Temporarily limited** and the last checked time | Last known | Backoff |
| No readable report | **Could not read Claude Code's usage report** and the last checked time | Last known | Backoff |
| Plan usage not reported (since 2026-11-20) | **Claude Code didn't report plan usage**, and "Claude Code usually shows plan usage only when it's signed in with a Claude plan. Run claude auth login in Terminal, then choose Check now in Needlbar. API keys and usage-billed accounts have no plan limits to show."; no sign-in button. The widget says "Sign in to Claude Code" with the last checked time | Last known or none | The next periodic run when automatic checks are on (no backoff retry; the backoff time still delays it), or Check now |

With automatic checks on, the run after 15 minutes counts as a trigger, so the first state is tried
again about every 15 minutes, further apart under backoff. With automatic checks off, the next
attempt in every row is the next **Check now**. A null `rate_limits` or null or empty `limits` is also what
Claude Code's schema reports while its own usage fetch is failing (offline, 429, 5xx), so it is not
treated as signed out. *Superseded 2026-11-20:* a signed-out run is now recognised from its own output and shows plan usage unavailable (see below); a null `rate_limits` or null or empty `limits` is still not treated as signed out. How a signed-out `claude` reports itself in this mode has not been observed,
and Needlbar does not guess it; until it is, a non-zero exit counts as a process failure. *Superseded 2026-11-20:* it has been observed, and it exits 0 with no `usage_report`, so this is no longer a process failure; a non-zero exit still is. API-key, usage-billed and `claude setup-token` sessions produce no `usage_report`,
so they show the no-readable-report state. *Superseded 2026-11-20:* by a static read of Claude Code (not observed), they take the same branch as a signed-out run and show plan usage unavailable. With automatic checks on, usage, in Claude Code or outside it such as on the web,
appears within about 15 minutes while the app is running and the Mac is awake, or about 17 when a
run is slow. That means about 96 runs a day, plus runs after resets and retries after failures
(amended 2026-11-12: it was up to 288 a day while usage-record changes started runs). A run costs
more as the recent transcripts grow: on one Mac the median run took about 4.9 s on 2026-11-05 and
about 8.1 s on 2026-11-12, and one run on 2026-11-05 took about 5.2 s of CPU and 454 MB of peak
memory. CPU and memory were not measured again.

Diagnostics record the failure reason, the run duration and the row kinds seen, never tokens, output
text or emails. The `ClaudeQuotaFailureDiagnostic` and `QuotaRefreshDiagnostic` log categories stay
on this Mac.

**View Claude usage** opens only `https://claude.ai/settings/usage` after an explicit click.

Needlbar does not own Claude credentials and therefore does not provide a Claude Disconnect button. Sign out or revoke the provider session through Claude's supported controls; Needlbar will then show the no-usage state on the next run. *Superseded 2026-11-20:* it now shows plan usage unavailable on the next run.

### Plan usage not reported (2026-11-20, prepared, not released)

A signed-out `claude` was observed on 2026-11-19: `/usage` exited 0 with `result` `subtype:
"success"`, an assistant line with `local_command_run: {"command": "usage"}`, the session cost text
and no `usage_report` key. A static read of Claude Code 2.1.325 and 2.1.328 shows the same branch
whenever Claude Code does not consider itself signed in with a Claude plan: signed out, an API key,
usage-based billing, or a token without the profile scope. This replaces three statements above:
a signed-out run is no longer unobserved, such runs no longer show the no-readable-report state,
and signing out now shows plan usage unavailable rather than the no-usage state.

Needlbar shows this state only when no assistant line has a non-null `usage_report`, none reports a
rate limit, at least one has a `local_command_run` whose `command` is `usage`, and none has a
`usage_report` key at all, not even `null`. Another command name, a `null` report, a malformed
report or no assistant line still reads as a changed format. The bridge code is
`requiresAuthentication` and the diagnostics origin `usageReportPlanUsageUnavailable`. With no
earlier reading the quota status is authentication required; after one it is an error with the
last-known values, as for a changed format. Claude still has no sign-in button, and the menu bar is
unchanged. While status-line windows are recent, the reason sits once on the Fable line, which only
`/usage` fills. There is no backoff retry, and the backoff time is still recorded, so repeated
failures can push the periodic run, when automatic checks are on, out to 20 or 30 minutes. **Check now** runs once and the same
reason returns.

The Overview widget's Claude row carries `staleReason: "planUsageUnavailable"` only after an earlier
reading, while the row is not fresh; the schema version stays 1, and an older widget ignores the key.
The column dims the figure and bar and says "Sign in to Claude Code · <time>", falling back to "Sign
in to Claude Code" when the full caption does not fit, and VoiceOver always speaks the time. It is set
even when a status-line reading is newer, because the widget shows only `/usage` values. With no
`/usage` success since launch the widget shows "Quota unavailable" with no reason. If Claude Code
renames `usage_report`, runs would show this state instead of a changed format; the distinct origin
keeps that visible in the log. The output of an API-key or usage-billed account has not been
observed.
