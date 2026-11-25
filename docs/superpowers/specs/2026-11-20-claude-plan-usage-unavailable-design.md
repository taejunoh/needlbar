# Claude Code finishes `/usage` without plan usage

**Date:** 2026-11-20

**Status:** Approved by the user in conversation on 2026-11-20. It authorizes an implementation
plan only. Implementation, merge, installation, tag and release each still need the user's
separate request.

**Scope:** how Needlbar classifies and shows a `/usage` run that completes without a plan usage
report. It adds to `2026-11-03-claude-usage-report-source-design.md` (failure states) and
`2026-11-13-widget-fable-percent-design.md` (one more optional projection field). The probe, its
arguments and limits, the cadence, the status-line source and the opt-in work in #55 and #56 are
unchanged.

## 1. Problem

On 2026-11-19 the user's terminal `claude` became signed out (`claude auth status --json`:
`loggedIn: false`, `authMethod: "none"`; the cause is unknown). From then on every `/usage` run
exited 0 with only the session cost summary and no `usage_report`. Needlbar classified that as a
changed format ("Could not read Claude Code's usage report", no detail), retried under backoff,
and the widget kept showing the last value with "Last checked 11/19/26, 2:12 PM" for about a day.
The user kept working from that figure without noticing. After `claude auth login` the next
Check now succeeded.

This is also the release check "how a signed-out `claude` reports itself", now observed: exit 0,
`result` `subtype: "success"`, an assistant line with `local_command_run: {"command": "usage"}`,
and no `usage_report` key.

A static read of Claude Code 2.1.325 and 2.1.328 (the same in both) shows that `/usage` takes this
branch whenever Claude Code does not consider itself signed in with a Claude plan: signed out, an
API key, usage-based billing, or a token without the profile scope. The copy therefore describes
what Claude Code did, not a guessed cause.

## 2. Decisions

- **New state, "plan usage unavailable".** Distinct from a changed format.
- **Shown on the widget too** (user's choice), with the last-checked time.
- **No backoff retry** (user's choice), like "not installed": it is checked again on the periodic
  run and on Check now. Waiting does not fix a sign-in.
- **No sign-in by Needlbar.** It never runs `claude auth` and offers no sign-in button; the copy
  names the Terminal command.

## 3. Detection

The parser (`claude_usage_report.rs`) returns the new outcome `PlanUsageUnavailable` only when all
of these hold:

1. no assistant line has a non-null `usage_report`;
2. no assistant line has `error == "rate_limit"`;
3. at least one assistant line has a top-level `local_command_run` whose `command` is `"usage"`
   (decoded as an optional untyped JSON value, so a different shape never makes serde skip the
   line; compared, never kept);
4. no assistant line has a `usage_report` key at all, not even `null`.

The order is: a report, then rate limited, then plan usage unavailable, then format changed. These
stay `FormatChanged`: another command name, `usage_report: null`, a malformed report, no assistant
lines. Telling a missing key from `null` needs a field deserializer, because serde folds both into
`None`. The parser still reads no text; the privacy note at the top of the file names the one extra
field it now reads.

Not taken: a missing `usage_report` alone (every future format change would read as a sign-in
problem); matching the "Estimated cost" text (brittle, possibly localized); running
`claude auth status` (Needlbar never runs `claude auth`).

## 4. Plumbing

- **Rust.** `ClaudeUsageReportOutcome::PlanUsageUnavailable` becomes a `QuotaError` with code
  `RequiresAuthentication` and the new origin `UsageReportPlanUsageUnavailable`
  (`"usageReportPlanUsageUnavailable"`), added to the origin enum and its serialization test.
- **Bridge.** The code stays `"requiresAuthentication"`, which the bridge, diagnostics and Swift
  `DiagnosticsErrorCode` already know. No new code string.
- **Swift.** New `ClaudeQuotaFailureReason.planUsageUnavailable`. `init(errorCode:)` maps
  `"requiresAuthentication"` to it; `"authenticationExpired"` stays `quotaAccessUnavailable`. The
  comment saying no Claude path sends that code is removed. The strict `ClaudeQuotaFailureOrigin`
  decoder gains the new origin.
- **Status.** With no earlier success the store reports `DataStatus.requiresAuthentication`;
  after one, it reports `.error`, as it does for a changed format, and the widget stream is stale.
  Claude has no sign-in button (`requiresProviderSignIn` leaves Claude out), and the menu-bar
  "Sign in" word comes from usage status, not quota status, so neither appears. With no earlier
  success the Overview popover says "Authentication required" where a changed format said
  "Refresh failed", and the export state is `requiresAuthentication` instead of `error`; both are
  accepted as accurate.
- **Retry.** In `RefreshCoordinator.recordClaudeUsageOutcome`, `retries` becomes
  `code != "notInstalled" && code != "requiresAuthentication"`, on every path that carries a code,
  including a thrown bridge failure with that code. The backoff time is still recorded,
  as for "not installed", so repeated failures can push the periodic run out to 20 or 30 minutes.
  Check now is unaffected.

## 5. Copy

- **Row reason:** "Claude Code didn't report plan usage"
- **Detail:** "Claude Code usually shows plan usage only when it's signed in with a Claude plan.
  Run claude auth login in Terminal, then choose Check now in Needlbar. API keys and usage-billed
  accounts have no plan limits to show."
- **Widget caption:** "Sign in to Claude Code · <time>", where `<time>` is the row's
  `lastSuccessfulAt` formatted by the same `lastCheckedTime` the "Last checked" caption uses (so it
  includes the date when that caption would). `WidgetQuotaColumn` gains `compactDetail`
  ("Sign in to Claude Code"), and the widget wraps the caption in a `ViewThatFits`: the full
  caption at full size first, then the compact one with the existing 0.8 minimum scale. With a date
  the full caption probably never fits a medium column; the on-device check settles it. The widget
  field only exists after an earlier success, so signing in is the likely fix.
- **Widget VoiceOver:** "Claude, <n> percent remaining, not updating, sign in to Claude Code, last
  checked <time>", followed by the Fable part as today (", Fable <n> percent remaining"). The time
  is spoken even when the caption drops it.
- No copy mentions a token, offers an automatic sign-in, or says "signed out".

## 6. Widget

- **Field.** `WidgetQuotaRow` gains `staleReason: WidgetQuotaStaleReason?` with one case,
  `planUsageUnavailable`. Schema version stays 1. Both decode paths (`RawQuotaRow` and
  `WidgetQuotaRow.init(from:)`) read it as `String?`: an absent key or `null` is `nil`, and an
  unknown string is `nil` instead of an error, so a later case cannot blank an older widget.
- **Validation** (in the row's initializers and in the projection's validation, as for Fable):
  only on the Claude row, the row has a last successful time and a headline, and its stream is not
  `fresh`. Anything else rejects the projection.
- **Mapper.** Sets it only when those hold and the Claude failure reason captured from the store
  is `planUsageUnavailable`; otherwise leaves it out and never throws. `WidgetProviderCapture`
  gains the reason. It clears by itself: a success clears the stored reason, and a different
  failure replaces it.
- **Presentation.** In the Claude column it takes precedence over "Last checked" and "Awaiting
  fresh reading", and dims the figure and bar. The Fable text follows its own rules, unchanged.
- **Status line.** The field is set even when a status-line reading is fresher, because the widget
  shows only `/usage` values and its figure is the stalled one.

## 7. App

- The dashboard Claude row, the provider popover and Settings show the new reason and detail
  wherever they show reasons today.
- When a recent status-line reading covers Session and Weekly, other reasons are hidden today;
  `reasonSitsOnTheFableLine` (`ProviderPopoverView.swift`) gains `.planUsageUnavailable`, so this
  reason shows on the Fable line, which only `/usage` fills, as "not installed" already does.
- Check now in this state runs once, the same reason returns, and nothing else changes. That is
  accepted.
- The menu bar is unchanged.

## 8. Testing

- **Rust parser:** a signed-out fixture recorded from the 2026-11-20 output with identifiers
  removed (new file under `Fixtures/quota/claude/`); another command name; `usage_report: null`;
  a malformed report; a rate limit together with `local_command_run`; no assistant lines.
- **Rust provider:** the code and origin. **Bridge:** the origin name list.
- **Swift:** the code-to-reason mapping, the origin decoding, the diagnostics reporter pairs, the
  copy (including `noCopyOffersAnAutomaticSignIn`, and that Claude's authentication action stays
  "View Claude usage"), and the retry rule: no backoff retry, the periodic run and Check now still
  run. New coordinator tests go in a new file to avoid conflicts with #55.
- **Widget:** round trip with and without the field; an old file without the key; `null`; an
  unknown value; each invalid combination rejected; the mapper setting and clearing it; the caption
  with time, the fallback without time, dimming, and VoiceOver.
- **Not automated, checked by the user on an installed build:** the widget caption in light and
  dark and its fallback when narrow.

## 9. Documentation

`README.md` (the Claude usage report section's failure states), `docs/providers/claude.md` (the
state table and the note that a signed-out run was not yet observed), `docs/privacy.md` (the extra
field read), `docs/HANDOFF.md` and a `docs/STATUS.md` entry marked prepared, not released. New text
is appended where #55 also edits, to keep conflicts small.

## 10. Risks

- If Claude Code renames `usage_report`, runs would show this state instead of a changed format.
  The copy is hedged and the distinct origin keeps it diagnosable in the log.
- The app row can look current from the status line while the widget asks to sign in; that is
  intended (§6).
- A widget process from before installation ignores the new key until it restarts.
- Remapping `requiresAuthentication` for Claude changes three Swift tables that expect
  `quotaAccessUnavailable`: `ClaudeUsageProbeCoordinatorTests.swift` (about line 523),
  `ClaudeUsageReportReasonTests.swift` (about line 14) and `RefreshCoordinatorTests.swift` (about
  line 858). They are updated.
- With no `/usage` success since launch (the store is in memory only), the widget shows "Quota
  unavailable" with no reason, even after a relaunch while signed out; the app row shows the reason.
- The widget search guard rejects certain names in widget sources, comments included (for example
  the core module's name or the word for the other language). New widget code and comments avoid
  them.
- Not observed: the output for an API-key or usage-billed account; the static read says it takes
  the same branch.
