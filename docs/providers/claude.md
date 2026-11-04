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
  if the app already has it; 30 seconds, then the process group is terminated; 1 MiB of standard
  output, then the same; standard error discarded; cancelled when the app stops. After any exit,
  including a normal one, the process group also receives SIGKILL. That covers the group Needlbar
  started; a process that moved to its own session or group is not covered.
- **Switch:** launching the app with `NEEDLBAR_DISABLE_CLAUDE_USAGE_PROBE=1` starts no run. The smoke
  script sets it, so a smoke launch never starts a real `claude` that could renew the login and outlive
  the killed app.
- **When:** at app start, on manual refresh, when Claude Code's local usage records change, when a
  displayed window's reset passes, and after 15 minutes without a run. Automatic runs happen at most
  once every 5 minutes and only one at a time. Manual refresh skips the interval and backoff but joins
  a run in flight. Opening the dashboard, waking the Mac and regaining a connection do not
  themselves start a run, but a periodic run that fell due during sleep starts within about a minute
  of waking, when the once-a-minute check finds it overdue. If Codex is failing, each dashboard open retries Codex; that starts no Claude run and no dialog.
- **After failures:** automatic runs wait 5, 10, 20, then 30 minutes. Any success resets this.
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

The run after 15 minutes counts as a trigger, so the first state is tried again about every
15 minutes, further apart under backoff. A null `rate_limits` or null or empty `limits` is also what
Claude Code's schema reports while its own usage fetch is failing (offline, 429, 5xx), so it is not
treated as signed out. How a signed-out `claude` reports itself in this mode has not been observed,
and Needlbar does not guess it; until it is, a non-zero exit counts as a process failure. API-key, usage-billed and `claude setup-token` sessions produce no `usage_report`,
so they show the no-readable-report state. Usage outside Claude Code, such as on the web, appears
within about 15 minutes while the app is running and the Mac is awake. That means about 96 runs a day from the periodic run alone, and up to 288 a day with other triggers, because runs are at least 5 minutes apart,
whose memory and CPU cost has not been measured.

Diagnostics record the failure reason, the run duration and the row kinds seen, never tokens, output
text or emails. The `ClaudeQuotaFailureDiagnostic` and `QuotaRefreshDiagnostic` log categories stay
on this Mac.

**View Claude usage** opens only `https://claude.ai/settings/usage` after an explicit click.

Needlbar does not own Claude credentials and therefore does not provide a Claude Disconnect button. Sign out or revoke the provider session through Claude's supported controls; Needlbar will then show the no-usage state on the next run.
