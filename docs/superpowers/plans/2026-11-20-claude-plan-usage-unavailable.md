# Claude Plan Usage Unavailable Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When Claude Code finishes `/usage` without plan usage, show a distinct "plan usage unavailable" state in the app and on the Overview widget, and stop retrying it under backoff, as approved in the 2026-11-20 design.

**Architecture:** The Rust parser recognises one exact output shape (a finished `usage` command with no `usage_report` key) as `ClaudeUsageReportOutcome::PlanUsageUnavailable`; the provider turns it into the existing `requiresAuthentication` code with a new diagnostics origin. Swift maps that code to a new `ClaudeQuotaFailureReason.planUsageUnavailable`, which the existing reason surfaces show, and `RefreshCoordinator` stops scheduling a backoff retry for it. The widget projection's Claude row gains one optional, leniently decoded `staleReason`, validated by one rule that the row, the projection and the app's mapper share; `WidgetPresentation` turns it into a dimmed column with a sign-in caption, a compact fallback and a spoken label. The schema version stays 1.

**Tech Stack:** Rust 2021 (`serde`, `serde_json`, `tokio` tests), Swift 6 and Swift Testing, SwiftUI and WidgetKit in a macOS 14+ arm64 app extension, Foundation `JSONEncoder`/`JSONDecoder`.

## Global Constraints

Authoritative spec: `docs/superpowers/specs/2026-11-20-claude-plan-usage-unavailable-design.md`. Every decision in it is final. Copied from it verbatim:

- Status: "It authorizes an implementation plan only. Implementation, merge, installation, tag and release each still need the user's separate request."
- Scope: "The probe, its arguments and limits, the cadence, the status-line source and the opt-in work in #55 and #56 are unchanged."
- New state: "**New state, "plan usage unavailable".** Distinct from a changed format." "**Shown on the widget too** (user's choice), with the last-checked time." "**No sign-in by Needlbar.** It never runs `claude auth` and offers no sign-in button; the copy names the Terminal command."
- Detection: "The parser (`claude_usage_report.rs`) returns the new outcome `PlanUsageUnavailable` only when all of these hold: 1. no assistant line has a non-null `usage_report`; 2. no assistant line has `error == "rate_limit"`; 3. at least one assistant line has a top-level `local_command_run` whose `command` is `"usage"` (decoded as an optional untyped JSON value, so a different shape never makes serde skip the line; compared, never kept); 4. no assistant line has a `usage_report` key at all, not even `null`."
- Order: "The order is: a report, then rate limited, then plan usage unavailable, then format changed. These stay `FormatChanged`: another command name, `usage_report: null`, a malformed report, no assistant lines." "Telling a missing key from `null` needs a field deserializer, because serde folds both into `None`. The parser still reads no text; the privacy note at the top of the file names the one extra field it now reads."
- Rust: "`ClaudeUsageReportOutcome::PlanUsageUnavailable` becomes a `QuotaError` with code `RequiresAuthentication` and the new origin `UsageReportPlanUsageUnavailable` (`"usageReportPlanUsageUnavailable"`), added to the origin enum and its serialization test."
- Bridge: "The code stays `"requiresAuthentication"`, which the bridge, diagnostics and Swift `DiagnosticsErrorCode` already know. No new code string."
- Swift: "New `ClaudeQuotaFailureReason.planUsageUnavailable`. `init(errorCode:)` maps `"requiresAuthentication"` to it; `"authenticationExpired"` stays `quotaAccessUnavailable`. The comment saying no Claude path sends that code is removed. The strict `ClaudeQuotaFailureOrigin` decoder gains the new origin."
- Status: "With no earlier success the store reports `DataStatus.requiresAuthentication`; after one, it reports `.error`, as it does for a changed format, and the widget stream is stale."
- Retry: "In `RefreshCoordinator.recordClaudeUsageOutcome`, `retries` becomes `code != "notInstalled" && code != "requiresAuthentication"`, on every path that carries a code, including a thrown bridge failure with that code. The backoff time is still recorded, as for "not installed", so repeated failures can push the periodic run out to 20 or 30 minutes. Check now is unaffected."
- Row reason: "Claude Code didn't report plan usage"
- Detail: "Claude Code usually shows plan usage only when it's signed in with a Claude plan. Run claude auth login in Terminal, then choose Check now in Needlbar. API keys and usage-billed accounts have no plan limits to show."
- Widget caption: "Sign in to Claude Code · <time>", where "`<time>` is the row's `lastSuccessfulAt` formatted by the same `lastCheckedTime` the "Last checked" caption uses".
- Compact caption: "`WidgetQuotaColumn` gains `compactDetail` ("Sign in to Claude Code"), and the widget wraps the caption in a `ViewThatFits`: the full caption at full size first, then the compact one with the existing 0.8 minimum scale."
- Widget VoiceOver: "Claude, <n> percent remaining, not updating, sign in to Claude Code, last checked <time>", "followed by the Fable part as today (", Fable <n> percent remaining"). The time is spoken even when the caption drops it."
- "No copy mentions a token, offers an automatic sign-in, or says "signed out"."
- Field: "`WidgetQuotaRow` gains `staleReason: WidgetQuotaStaleReason?` with one case, `planUsageUnavailable`. Schema version stays 1. Both decode paths (`RawQuotaRow` and `WidgetQuotaRow.init(from:)`) read it as `String?`: an absent key or `null` is `nil`, and an unknown string is `nil` instead of an error, so a later case cannot blank an older widget."
- Validation: "(in the row's initializers and in the projection's validation, as for Fable): only on the Claude row, the row has a last successful time and a headline, and its stream is not `fresh`. Anything else rejects the projection."
- Mapper: "Sets it only when those hold and the Claude failure reason captured from the store is `planUsageUnavailable`; otherwise leaves it out and never throws. `WidgetProviderCapture` gains the reason."
- Presentation: "In the Claude column it takes precedence over "Last checked" and "Awaiting fresh reading", and dims the figure and bar. The Fable text follows its own rules, unchanged."
- Status line: "The field is set even when a status-line reading is fresher, because the widget shows only `/usage` values and its figure is the stalled one."
- App: "`reasonSitsOnTheFableLine` (`ProviderPopoverView.swift`) gains `.planUsageUnavailable`". "The menu bar is unchanged."
- Tests: "New coordinator tests go in a new file to avoid conflicts with #55."
- Search guard: "The widget search guard rejects certain names in widget sources, comments included (for example the core module's name or the word for the other language). New widget code and comments avoid them." The guard pattern is `NeedlbarCore|CNeedlbar|Rust|Keychain|URLSession`, case-sensitive (`scripts/tests/widget-extension-tests.sh:25`); the widget source also may not contain `AcceptanceFixture` (`scripts/tests/acceptance-build-isolation-tests.sh:17`).

Repository constraints:

- Implementers never run `claude`; never read `~/.claude/.credentials.json`, `~/.claude.json`, Keychain items or cookies; never install any Needlbar app or widget, never copy anything into `/Applications`, and never push, merge, tag or start a release. The only app launch is `make smoke` in Task 10, whose script starts the packaged executable with `NEEDLBAR_DISABLE_CLAUDE_USAGE_PROBE=1` (`scripts/smoke-app.sh:199`), which `AppDelegate` reads before it creates the Claude repository (`Sources/Needlbar/App/AppDelegate.swift:141-146,205`), so no `claude` run starts.
- Commands run from the repository root after `export PATH="/Users/taejunoh/.codex/plugins/.plugin-appserver/codex-cli/codex-path:$HOME/.cargo/bin:$PATH" MACOSX_DEPLOYMENT_TARGET=14.0`. That PATH provides `rg`, which `make widget-extension-test` (and so `make test`) needs. On 2026-11-23 that directory was empty on the maintainer's Mac; if `bash -c 'command -v rg'` prints nothing, stop and ask the user for an `rg` before the steps that need it. Never type a bare `rg` in an interactive shell: in the maintainer's zsh profile `rg` is a function that executes the Claude Code binary. This plan's own searches use `/usr/bin/grep`.
- Never run `cargo fmt --all`. The Rust code in this plan is already formatted; check it with `cargo fmt -p needlbar-quota -p needlbar-bridge --check`.
- CI builds with Xcode 16.2 and Swift 6.0, stricter than the local Swift 6.4: an implicit `switch` return is valid only as the sole expression of a body. Use the code as written; every multi-statement `switch` in it uses explicit `return`.
- Bare `swift test` cannot link, because the tests need the bridge built with its test feature. Use `make swift-test SWIFT_TEST_FILTER=…` (`Makefile:9-53`). It builds that bridge, cleans the Swift build, runs the tests, restores the normal bridge and cleans again, so each run takes about five minutes; give it a timeout of at least ten minutes and do not interrupt it. The filter is pasted unquoted into the recipe, so a filter with `|` is passed with its own double quotes inside single quotes, `SWIFT_TEST_FILTER='"A|B"'`, which the recipe expands to `swift test --filter "A|B"` (checked with `make -n`). Filters match type and function names, not `@Suite` display names.
- In `README.md`, new text contains neither `0.3.14` nor `0.3.15` outside the versioned headings; `bash scripts/tests/notarize-app-tests.sh` aborts with `historical fixture: v0.3.14 text remains` otherwise. Say "prepared, not released" without a version.
- New `docs/STATUS.md` text repeats no run ID, asset ID, commit hash, `releases/tag/`, or `report 0.3.`, because the decoys in `scripts/tests/notarize-app-tests.sh` rewrite the first occurrence.
- Stage only the files each commit step lists. Never `git add -A` or `git add .`: `.superpowers/brainstorm/` is untracked and stays out.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Line numbers are from the state each task starts from (Task 1 starts at `e7c480c`). Every quoted "replace" text occurs exactly once in its file at that point.

---

## Decisions Settled From The Code

### 1. Where each piece goes

| Place | Today | Change |
|---|---|---|
| `StreamLine`, `crates/needlbar-quota/src/providers/claude_usage_report.rs:48-56` | `usage_report: Option<Value>` with `#[serde(default)]`, so a missing key and `null` are both `None` | `deserialize_with = "present"` keeps `null` as `Some(Value::Null)`; a new `local_command_run: Option<Value>` (Task 1) |
| `parse_usage_report_stream`, `:58-80` | report, then rate limited, then format changed | report, rate limited, plan usage unavailable, format changed (Task 1) |
| `ClaudeUsageReportProvider::run`, `claude_usage_provider.rs:112-147` | exhaustive `match` on the outcome | a new arm: format changed in Task 1, `RequiresAuthentication` with the new origin in Task 2 |
| `ClaudeQuotaFailureOrigin`, `crates/needlbar-quota/src/domain.rs:79-92`, and the bridge test `diagnostics_serializes_every_closed_claude_failure_origin_by_its_stable_name`, `crates/needlbar-bridge/src/lib.rs:810-854` | eight origins | `UsageReportPlanUsageUnavailable` (Task 2); no bridge source changes, because the bridge already maps `RequiresAuthentication` to `"requiresAuthentication"` (`crates/needlbar-bridge/src/quota.rs:186-188`) and serializes origins by name |
| `ClaudeQuotaFailureReason`, `Sources/NeedlbarCore/Models/ClaudeQuotaFailureReason.swift` | `requiresAuthentication` shares `quotaAccessUnavailable` | its own case, copy and mapping (Task 3) |
| `ClaudeQuotaFailureOrigin`, `Sources/NeedlbarCore/Diagnostics/DiagnosticsSnapshot.swift:106-118` | strict decoder | gains the origin (Task 3) |
| `recordClaudeUsageOutcome`, `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift:568-584` | reads a code only from a returned result | reads it from a returned result or a thrown `BridgeFailure.bridgeFailed`, and skips the retry for both codes (Task 4) |
| `ProviderPopoverPresentation`, `Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift:125-131` | only `.claudeCodeNotInstalled` sits on the Fable line | also `.planUsageUnavailable` (Task 5) |
| `WidgetQuotaRow`, `RawQuotaRow`, `WidgetProjection.validate`, `Sources/NeedlbarWidgetSupport/WidgetProjection.swift` | carries `fable` | also `staleReason`, read as `String?` on both paths (Task 6) |
| `WidgetProviderCapture`, `Sources/NeedlbarCore/Widget/WidgetUsageDayProvenance.swift:71-91`; `captureForWidget`, `Sources/NeedlbarCore/State/ProviderSnapshotStore.swift:203-218`; `WidgetProjectionMapper.mapQuota` | no failure reason | the Claude reason, copied by the store, turned into `staleReason` by the mapper (Task 7) |
| `WidgetQuotaStatus`, `quotaStatus`, `WidgetQuotaColumn`, `quotaColumn`, `Sources/NeedlbarWidgetSupport/WidgetPresentation.swift` | fresh, stale, awaiting, unavailable | a `planUsageUnavailable` status checked before the reset, `compactDetail` (Task 8) |
| `QuotaColumnView`, `WidgetExtension/NeedlbarOverviewWidget.swift:160-176` | one caption `Text` with a 0.8 minimum scale | a `ViewThatFits` when there is a compact caption (Task 8) |

- **The intermediate provider arm (Task 1).** The provider's `match` is exhaustive, so the new outcome cannot land without an arm. Task 1 maps it to exactly the error the provider returned for this output before (`SchemaChanged`, `UsageReportFormatChanged`), so Task 1 changes no observable behaviour and Task 2 is a reviewable one-arm change.
- **The copy lands with the reason (Task 3).** `localizedDisplayText` and `localizedDetailText` are exhaustive switches, so the reason case cannot compile without its copy. Task 3 therefore adds the reason with both texts and their core tests; Task 5 is the app presentation (the Fable line, popover, dashboard, Settings and Check now tests).
- **One rule for the widget field.** `WidgetQuotaStaleReason.isValid(for:stream:lastSuccessfulAt:headline:)` holds the spec's three conditions. The row initializer, `WidgetProjection.validate` and the mapper call it, as `WidgetFableReading.isValid` does for Fable, so the mapper never produces a row that the row or the projection refuses, and so it never throws for the field.
- **Lenient decoding.** Both decoders read `String?` and then `flatMap(WidgetQuotaStaleReason.init(rawValue:))`, so an unknown string becomes `nil` before validation and never rejects a file, even on a fresh row. A value of another JSON type (a number) still fails decoding and rejects the file, as a malformed `fable` does today; the spec says "read it as `String?`" and is silent on other types.
- **Encoding.** `WidgetQuotaRow.encode(to:)` is synthesized from `CodingKeys`, so `nil` writes no key and a projection without the reason encodes byte for byte as before; the existing `aProjectionWithoutFableEncodesExactlyAsBefore` pins those bytes and keeps passing.
- **Precedence on the widget.** `quotaStatus` returns `.planUsageUnavailable(headline, lastCheckedAt:)` after the freshness check and before the reset check, so it wins over "Awaiting fresh reading" and, because a row with the reason is never `fresh`, over "Last checked". The Fable text is computed after the figure guard exactly as today.
- **The caption view.** The first `ViewThatFits` child is the full caption with `lineLimit(1)` and no scale factor, so its ideal width is its full width at caption size; the second is the compact caption with the existing `minimumScaleFactor(0.8)`. Columns without a compact caption keep today's single `Text` with the same modifiers.

### 2. The retry rule, on both paths

`recordClaudeUsageOutcome` today takes the code only from a returned result; a thrown `BridgeFailure.bridgeFailed` always retries. The spec puts the rule "on every path that carries a code, including a thrown bridge failure with that code". A helper `claudeErrorCode(in:)` returns the Claude error's code from either path, and the one expression `code != "notInstalled" && code != "requiresAuthentication"` decides. As a consequence a thrown `notInstalled` also stops retrying under backoff; today it retries. The dedicated Claude path normalizes every error's provider to `claude` (`Sources/NeedlbarCore/Repositories/QuotaRepository.swift:126-145`), so `providerID == .claude` finds it. A run that returned neither a reading nor an error, and every thrown failure that is not `bridgeFailed`, still retries (`aRunWithNeitherReadingNorErrorRecordsExactlyOneRetryableFailure` keeps passing).

### 3. The recorded fixture

`Fixtures/quota/claude/usage-report-signed-out.jsonl` is built from the structure of the output recorded on 2026-11-20. Kept: the assistant line's `type`, `message.role`, `message.type`, `message.stop_reason`, `message.content` with the cost text, `parent_tool_use_id` and `local_command_run` (`{"command":"usage","args":""}`); the result line's `type`, `subtype` (`success`), `is_error`, `duration_ms`, `duration_api_ms`, `num_turns`, `result` (the same cost text), `stop_reason`, `total_cost_usd`, the four token counts of `usage`, `permission_denials` and `local_command`. Removed: the six hook and init lines, every `session_id`, `uuid` and `timestamp`, `message.id`, `message.model`, the message's own `usage` and other null fields, `local_command_source`, `modelUsage`, `model_usage_since_last_result`, `service_tier`, `speed`, `fast_mode_*`, `subagent_stats` and the other result counters. Every number is zero, and the wall-clock duration in the cost text reads `0s`. The file contains no path, account, model name or identifier.

### 4. Conflicts with open PRs #55 and #56

Every task's commits were merged in a scratch clone with `origin/claude/claude-auto-checks-gate` (#55) and `origin/claude/claude-auto-checks-first-run` (#56). Results:

- **Textual conflict, both PRs: `docs/STATUS.md` only.** Both add an entry at the top. Resolve by keeping both entries, newest date first.
- **No textual conflict** in `RefreshCoordinator.swift` (#55 does not touch `recordClaudeUsageOutcome`), `ClaudeUsageProbeCoordinatorTests.swift` (one line at about 523, away from #55's hunks at 136 and 596+), `RefreshCoordinatorTests.swift` (one line at 858, between #55's hunks at 840 and 879), `README.md`, `docs/privacy.md`, `docs/providers/claude.md` and `docs/HANDOFF.md`. This plan does not touch `ClaudeUsageProbeScheduleTests.swift`, `SettingsView.swift`, `SystemDashboardModel.swift` or `SystemDashboardPopoverView.swift`.
- **Semantic conflict: `Tests/NeedlbarCoreTests/ClaudePlanUsageUnavailableRetryTests.swift`.** #55 makes `claudeAutomaticRunsAllowed: Bool` a required `RefreshCoordinator` initializer argument, so after both land the new file fails with `missing argument for parameter 'claudeAutomaticRunsAllowed' in call`. Whichever branch merges second adds `claudeAutomaticRunsAllowed: true,` after `claudeUsageRepository: probe,` in `RetryHarness.init`. With that one line the merged scratch tree built and the new suite, `ClaudeUsageProbeCoordinatorTests`, `ClaudeUsageProbeScheduleTests`, `ClaudeUsageReportReasonTests` and `RefreshCoordinatorTests` passed (135 tests in 5 suites).
- **Wording left for the later merge.** To avoid conflicts, the docs append rather than rewrite: `docs/providers/claude.md` keeps its sentences that a signed-out run is unobserved and shows the no-readable-report state, and that signing out shows the no-usage state, and appends a dated section that supersedes them; `docs/HANDOFF.md` keeps its checkpoint line, its "Still open" sentence and the release gate's "the signed-out `claude` check", and adds a paragraph saying that check is answered. After both PRs land, a follow-up can fold these in.

### 5. Test mechanics

- **What fails first.** Every Rust and Swift task except Task 4 and Task 5 fails to compile first, because its tests name a type, case or member that does not exist yet. Task 4's new tests compile and two of them fail (9 issues); three pass before the implementation and are guards (another thrown code still retries, Check now runs, the status after a success). Task 5 fails one expectation. The Task 1 guards were checked by mutation: dropping `!report_key_seen`, dropping `usage_command_ran`, or removing the `present` deserializer each failed `anything_short_of_that_shape_stays_format_changed`.
- **`make widget-extension-test` never compiles Swift**, because its `xcrun` is a fake. Task 8 also runs `./scripts/build-widget-extension.sh`: a real `swiftc` build into the git-ignored `.build/widget-extension`, signed ad hoc, with nothing installed or launched.
- **Verified while writing this plan.** Every task was applied in order to a scratch clone at `e7c480c` and its steps run there. The Rust steps used the commands as written. The Swift steps used `swift build --build-tests` and `swift test --skip-build --filter …` against a bridge built once with `./scripts/build-rust.sh --features bridge-test-runtime`, which is what `make swift-test` wraps; the failure and pass lines below are from those runs. The widget build had no warning, and `make widget-extension-test` passed with a stand-in `rg` on PATH whose behaviour was not recorded (the PATH directory above was empty); real ripgrep has not scanned these sources on this Mac, and CI is the first real run. Every "replace" and "create" block in this file was extracted from the scratch commits by a script that checked each quoted text occurs exactly once. On the final scratch tree, with the same stand-in `rg`, `make test` exited 0 (Swift: 428, 369, 39, 5 and 61 tests, no `✘`; the cargo, vendor, bridge-archive, widget, package and notarize contracts passed), `make acceptance-test` passed 9 tests in `AcceptanceFixtureTests`, and `make package` exited 0. `make smoke` was not run while writing the plan, because it launches the packaged app on the maintainer's Mac. A one-off `make swift-test` with the quoted Task 3 filter confirmed the `'"A|B"'` form and its counts.

### 6. Where the spec is silent

1. **The provider message.** "Claude Code did not report plan usage." It never reaches the UI: the bridge replaces messages with `safe_quota_message(code)` (`crates/needlbar-bridge/src/quota.rs:205-217`).
2. **The localization keys.** `claudeQuota.reason.planUsageUnavailable` and `claudeQuota.reason.planUsageUnavailable.detail`, following the existing pattern.
3. **The fixture's name.** `usage-report-signed-out.jsonl`, beside the two existing fixtures.
4. **Forbidden words in the copy tests.** `noCopyOffersAnAutomaticSignIn` gains `"signed out"` and `"automatically"` alongside the existing words, and the widget gets a matching check over its caption and label.
5. **The widget's spoken label after a date.** It uses the same `lastCheckedTime` text as the caption, so it includes the date when the caption does.
6. **Docs placement.** The README text is one paragraph appended to the end of the "Claude quota from the Claude Code usage report" section; `docs/providers/claude.md` gets a table row and a dated section at the end of the file; `docs/privacy.md` names the extra field in the sentence that lists what is read (the one in-place edit, which merged cleanly with both PRs); `docs/HANDOFF.md` gets one paragraph after the Fable paragraph.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `Fixtures/quota/claude/usage-report-signed-out.jsonl` | Recorded signed-out output, identifiers removed | Create (Task 1) |
| `crates/needlbar-quota/src/providers/claude_usage_report.rs` | Pure `/usage` stream parser | New outcome, `present` deserializer, `local_command_run`, order (Task 1) |
| `crates/needlbar-quota/tests/claude_usage_report.rs` | Parser tests | Five tests, two helpers (Task 1) |
| `crates/needlbar-quota/src/providers/claude_usage_provider.rs` | Outcome to `QuotaError` | New arm (Tasks 1 and 2) |
| `crates/needlbar-quota/src/domain.rs` | Error codes and origins | `UsageReportPlanUsageUnavailable` (Task 2) |
| `crates/needlbar-quota/tests/claude_usage_provider.rs` | Provider tests with a fake `claude` script | One test (Task 2) |
| `crates/needlbar-bridge/src/lib.rs` | Bridge, with its unit tests | One entry in the origin name list (Task 2) |
| `Sources/NeedlbarCore/Models/ClaudeQuotaFailureReason.swift` | Safe Claude reasons and copy | `planUsageUnavailable` (Task 3) |
| `Sources/NeedlbarCore/Diagnostics/DiagnosticsSnapshot.swift` | Strict diagnostics decoding | New origin (Task 3) |
| `Tests/NeedlbarCoreTests/ClaudeUsageReportReasonTests.swift`, `ClaudeUsageProbeCoordinatorTests.swift`, `RefreshCoordinatorTests.swift`, `DiagnosticsTests.swift`, `BridgeDecodingTests.swift`, `Tests/NeedlbarTests/ClaudeQuotaFailureDiagnosticsReporterTests.swift` | Existing tables | One row or entry each, one new copy test (Task 3) |
| `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift` | Claude run scheduling | Retry rule and `claudeErrorCode(in:)` (Task 4) |
| `Tests/NeedlbarCoreTests/ClaudePlanUsageUnavailableRetryTests.swift` | Retry rule tests with their own harness | Create (Task 4) |
| `Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift` | Popover, dashboard and Settings presentation | `reasonSitsOnTheFableLine` (Task 5) |
| `Tests/NeedlbarTests/ClaudeUsageReportPresentationTests.swift`, `PopoverPresentationTests.swift`, `ClaudeCheckNowActionTests.swift` | App presentation tests | One test, three extended lists (Task 5) |
| `Sources/NeedlbarWidgetSupport/WidgetProjection.swift` | Projection, coding and validation | `WidgetQuotaStaleReason`, `staleReason` on both paths and both validators (Task 6) |
| `Tests/NeedlbarWidgetSupportTests/WidgetProjectionTests.swift` | Projection tests | Four tests, two helpers (Task 6) |
| `Sources/NeedlbarCore/Widget/WidgetUsageDayProvenance.swift`, `Sources/NeedlbarCore/State/ProviderSnapshotStore.swift`, `Sources/NeedlbarCore/Widget/WidgetProjectionMapper.swift` | Capture and mapping | The reason on the capture, `staleReason(...)` (Task 7) |
| `Tests/NeedlbarCoreTests/WidgetPlanUsageUnavailableMapperTests.swift` | Store-to-projection tests | Create (Task 7) |
| `Sources/NeedlbarWidgetSupport/WidgetPresentation.swift` | Widget presentation decisions | Status case, `compactDetail`, caption and label (Task 8) |
| `WidgetExtension/NeedlbarOverviewWidget.swift` | Layout | `ViewThatFits` caption (Task 8) |
| `Tests/NeedlbarWidgetSupportTests/WidgetOverviewPresentationTests.swift` | Presentation tests | Five tests, one helper parameter (Task 8) |
| `README.md`, `docs/providers/claude.md`, `docs/privacy.md`, `docs/HANDOFF.md`, `docs/STATUS.md` | Current descriptions and records | Appended text (Task 9) |

No script, `Package.swift`, extension Info.plist or entitlement, bridge source outside its test module, acceptance fixture or `docs/architecture.md` changes. The widget extension still compiles exactly `WidgetProjection.swift`, `WidgetPresentation.swift` and `NeedlbarOverviewWidget.swift`; no file is added to `Sources/NeedlbarWidgetSupport`.

---

### Task 1: The parser tells a run without plan usage from a changed format

**Files:**
- Create: `Fixtures/quota/claude/usage-report-signed-out.jsonl`
- Modify: `crates/needlbar-quota/src/providers/claude_usage_report.rs:1-9,41-44,50-57,59-62,67-70,74-80`
- Modify: `crates/needlbar-quota/src/providers/claude_usage_provider.rs:137-140`
- Test: `crates/needlbar-quota/tests/claude_usage_report.rs:7-12,203-205`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `ClaudeUsageReportOutcome::PlanUsageUnavailable` (a unit variant of `pub enum ClaudeUsageReportOutcome`, already re-exported from `needlbar_quota`)
  - `pub fn parse_usage_report_stream(bytes: &[u8]) -> ClaudeUsageReportOutcome` (signature unchanged, new result)
  - private `fn present<'de, D: Deserializer<'de>>(deserializer: D) -> Result<Option<Value>, D::Error>`
  - the fixture path `Fixtures/quota/claude/usage-report-signed-out.jsonl`, used again in Task 2

- [ ] **Step 1: Add the fixture and write the failing tests**

Create `Fixtures/quota/claude/usage-report-signed-out.jsonl` with exactly this content:

```json
{"type":"assistant","message":{"role":"assistant","type":"message","stop_reason":"end_turn","content":[{"type":"text","text":"Estimated cost:        $0.0000\nTotal duration (API):  0s\nTotal duration (wall): 0s\nTotal code changes:    0 lines added, 0 lines removed\nUsage:                 0 input, 0 output, 0 cache read, 0 cache write"}]},"parent_tool_use_id":null,"local_command_run":{"command":"usage","args":""}}
{"type":"result","subtype":"success","is_error":false,"duration_ms":0,"duration_api_ms":0,"num_turns":0,"result":"Estimated cost:        $0.0000\nTotal duration (API):  0s\nTotal duration (wall): 0s\nTotal code changes:    0 lines added, 0 lines removed\nUsage:                 0 input, 0 output, 0 cache read, 0 cache write","stop_reason":null,"total_cost_usd":0,"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"permission_denials":[],"local_command":"usage"}
```

The file has exactly two lines, each ending in a newline: the assistant line, then the result line (Decisions 3).

In `crates/needlbar-quota/tests/claude_usage_report.rs`, replace

```rust
const ALL_ROWS: &str = include_str!("../../../Fixtures/quota/claude/usage-report-all-rows.jsonl");
const WEEKLY_ONLY: &str =
    include_str!("../../../Fixtures/quota/claude/usage-report-weekly-only.jsonl");

fn stream(rate_limits: &str) -> Vec<u8> {
    format!(
```

with

```rust
const ALL_ROWS: &str = include_str!("../../../Fixtures/quota/claude/usage-report-all-rows.jsonl");
const WEEKLY_ONLY: &str =
    include_str!("../../../Fixtures/quota/claude/usage-report-weekly-only.jsonl");
/// Recorded from a signed-out `claude` on 2026-11-20, with every identifier removed.
const SIGNED_OUT: &str =
    include_str!("../../../Fixtures/quota/claude/usage-report-signed-out.jsonl");

fn stream(rate_limits: &str) -> Vec<u8> {
    format!(
```

Then, in the same file, replace

```rust
        assert!(!debug.contains(canary), "{canary}");
    }
}
```

with

```rust
        assert!(!debug.contains(canary), "{canary}");
    }
}

const USAGE_RUN: &str = r#""local_command_run":{"command":"usage","args":""}"#;

/// One assistant line with the given extra top-level fields.
fn assistant(fields: &str) -> Vec<u8> {
    format!("{{\"type\":\"assistant\",\"message\":{{\"content\":[]}},{fields}}}\n").into_bytes()
}

#[test]
fn a_finished_usage_command_without_a_report_key_is_plan_usage_unavailable() {
    assert_eq!(
        parse_usage_report_stream(SIGNED_OUT.as_bytes()),
        ClaudeUsageReportOutcome::PlanUsageUnavailable
    );
    assert_eq!(
        parse_usage_report_stream(&assistant(USAGE_RUN)),
        ClaudeUsageReportOutcome::PlanUsageUnavailable
    );
    // The command may be on any assistant line, and other lines may lack it.
    let mut two_lines = assistant(r#""local_command_run":null"#);
    two_lines.extend_from_slice(&assistant(USAGE_RUN));
    assert_eq!(
        parse_usage_report_stream(&two_lines),
        ClaudeUsageReportOutcome::PlanUsageUnavailable
    );
}

#[test]
fn anything_short_of_that_shape_stays_format_changed() {
    let mut null_report_elsewhere = assistant(USAGE_RUN);
    null_report_elsewhere.extend_from_slice(&assistant(r#""usage_report":null"#));
    let result_line_only = SIGNED_OUT
        .lines()
        .nth(1)
        .expect("result line")
        .as_bytes()
        .to_vec();
    for input in [
        assistant(r#""local_command_run":{"command":"cost","args":""}"#),
        assistant(r#""local_command_run":{"command":"Usage"}"#),
        assistant(r#""local_command_run":{"command":7}"#),
        assistant(r#""local_command_run":"usage""#),
        assistant(r#""local_command_run":["usage"]"#),
        assistant(&format!(r#"{USAGE_RUN},"usage_report":null"#)),
        null_report_elsewhere,
        assistant(&format!(r#"{USAGE_RUN},"usage_report":{{}}"#)),
        assistant(&format!(r#"{USAGE_RUN},"usage_report":7"#)),
        assistant(&format!(
            r#"{USAGE_RUN},"usage_report":{{"rate_limits":{{"limits":"none"}}}}"#
        )),
        br#"{"type":"user","local_command_run":{"command":"usage"}}"#.to_vec(),
        result_line_only,
    ] {
        assert!(
            matches!(
                parse_usage_report_stream(&input),
                ClaudeUsageReportOutcome::FormatChanged { .. }
            ),
            "{}",
            String::from_utf8_lossy(&input)
        );
    }
}

#[test]
fn a_report_and_a_rate_limit_still_come_first() {
    let with_report = stream(&format!("{{\"limits\":[{WEEKLY_ROW}]}}"))
        .into_iter()
        .chain(assistant(USAGE_RUN))
        .collect::<Vec<u8>>();
    assert!(matches!(
        parse_usage_report_stream(&with_report),
        ClaudeUsageReportOutcome::Windows { .. }
    ));
    assert_eq!(
        parse_usage_report_stream(&assistant(&format!(r#"{USAGE_RUN},"error":"rate_limit""#))),
        ClaudeUsageReportOutcome::RateLimited
    );
}

#[test]
fn a_strangely_shaped_local_command_run_never_hides_a_report() {
    let line = format!(
        "{{\"type\":\"assistant\",\"local_command_run\":[1,{{}}],\"usage_report\":{{\"rate_limits\":{{\"limits\":[{WEEKLY_ROW}]}}}}}}\n"
    );
    assert!(matches!(
        parse_usage_report_stream(line.as_bytes()),
        ClaudeUsageReportOutcome::Windows { .. }
    ));
}

#[test]
fn nothing_from_a_run_without_plan_usage_survives_parsing() {
    let input = br#"{"type":"assistant","message":{"content":[{"type":"text","text":"TEXT-CANARY"}]},"local_command_run":{"command":"usage","args":"ARGS-CANARY"}}"#;
    let debug = format!("{:?}", parse_usage_report_stream(input));
    assert_eq!(debug, "PlanUsageUnavailable");
}
```

What the tests cover from spec §3 and §8: the recorded fixture and a minimal line; the command on any assistant line; another command name, a differently cased name, a non-string command, a string or array `local_command_run`, `usage_report: null` on the same or another line, a malformed report (`{}`, `7`, a changed `limits`), a non-assistant line, the result line alone (no assistant lines); a report and a rate limit winning; a strange `local_command_run` never hiding a report; and no text surviving.

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
cargo test -p needlbar-quota --test claude_usage_report 2>&1 | grep -E '^error'
```

Expected: three lines `error[E0599]: no variant, associated function, or constant named `PlanUsageUnavailable` found for enum `ClaudeUsageReportOutcome` in the current scope`, then `error: could not compile `needlbar-quota` (test "claude_usage_report") due to 3 previous errors`.

- [ ] **Step 3: Write the implementation**

In `crates/needlbar-quota/src/providers/claude_usage_report.rs`, replace

```rust
//! Pure parser for `claude -p /usage --output-format stream-json`. It knows
//! nothing about processes. Everything except `usage_report`, and the closed
//! `error` value used when no report arrived, is discarded here: serde skips
//! other fields without building them, and no text is kept or logged.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;

```

with

```rust
//! Pure parser for `claude -p /usage --output-format stream-json`. It knows
//! nothing about processes. Everything except `usage_report`, the closed
//! `error` value used when no report arrived, and whether `local_command_run`
//! names the `usage` command is discarded here: serde skips other fields without
//! building them, `local_command_run` is compared and dropped, and no text is
//! kept or logged.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Deserializer, Serialize};
use serde_json::Value;

```

Then, in the same file, replace

```rust
    },
    RateLimited,
    FormatChanged {
        rows: ClaudeUsageRowSummary,
```

with

```rust
    },
    RateLimited,
    /// Claude Code ran `/usage` and finished without a `usage_report` key: it
    /// does not consider itself signed in with a Claude plan.
    PlanUsageUnavailable,
    FormatChanged {
        rows: ClaudeUsageRowSummary,
```

Then, in the same file, replace

```rust
    #[serde(default, rename = "type")]
    line_type: Option<Value>,
    #[serde(default)]
    usage_report: Option<Value>,
    #[serde(default)]
    error: Option<Value>,
}

```

with

```rust
    #[serde(default, rename = "type")]
    line_type: Option<Value>,
    /// `None` when the key is absent and `Some(Value::Null)` when it is `null`.
    #[serde(default, deserialize_with = "present")]
    usage_report: Option<Value>,
    #[serde(default)]
    error: Option<Value>,
    /// Untyped, so another shape never makes serde skip the line.
    #[serde(default)]
    local_command_run: Option<Value>,
}

/// Serde reads a present `null` as `None`; this keeps it as `Some(Value::Null)`.
fn present<'de, D: Deserializer<'de>>(deserializer: D) -> Result<Option<Value>, D::Error> {
    Value::deserialize(deserializer).map(Some)
}

```

Then, in the same file, replace

```rust
    let mut report = None;
    let mut rate_limited = false;
    for line in bytes.split(|byte| *byte == b'\n') {
        let Ok(parsed) = serde_json::from_slice::<StreamLine>(line) else {
```

with

```rust
    let mut report = None;
    let mut rate_limited = false;
    let mut report_key_seen = false;
    let mut usage_command_ran = false;
    for line in bytes.split(|byte| *byte == b'\n') {
        let Ok(parsed) = serde_json::from_slice::<StreamLine>(line) else {
```

Then, in the same file, replace

```rust
        }
        rate_limited |= parsed.error.as_ref().and_then(Value::as_str) == Some("rate_limit");
        if let Some(candidate) = parsed.usage_report.filter(|value| !value.is_null()) {
            report = Some(candidate);
```

with

```rust
        }
        rate_limited |= parsed.error.as_ref().and_then(Value::as_str) == Some("rate_limit");
        usage_command_ran |= parsed
            .local_command_run
            .as_ref()
            .and_then(|run| run.get("command"))
            .and_then(Value::as_str)
            == Some("usage");
        report_key_seen |= parsed.usage_report.is_some();
        if let Some(candidate) = parsed.usage_report.filter(|value| !value.is_null()) {
            report = Some(candidate);
```

Then, in the same file, replace

```rust
        Some(report) => classify_report(&report),
        None if rate_limited => ClaudeUsageReportOutcome::RateLimited,
        None => ClaudeUsageReportOutcome::FormatChanged {
            rows: ClaudeUsageRowSummary::default(),
        },
    }
}
```

with

```rust
        Some(report) => classify_report(&report),
        None if rate_limited => ClaudeUsageReportOutcome::RateLimited,
        // A missing key alone is not enough: a renamed field would look the same.
        None if usage_command_ran && !report_key_seen => {
            ClaudeUsageReportOutcome::PlanUsageUnavailable
        }
        None => format_changed(),
    }
}
```

The provider's `match` must stay exhaustive. Until Task 2 the new outcome fails exactly as this output did before (Decisions 1):

In `crates/needlbar-quota/src/providers/claude_usage_provider.rs`, replace

```rust
                ClaudeUsageRowSummary::default(),
            ),
            ClaudeUsageReportOutcome::FormatChanged { rows } => (
                Err(failure(
```

with

```rust
                ClaudeUsageRowSummary::default(),
            ),
            // Mapped to its own code and origin in the next commit; until then it
            // fails exactly as it did before the parser told it apart.
            ClaudeUsageReportOutcome::PlanUsageUnavailable => (
                Err(failure(
                    QuotaErrorCode::SchemaChanged,
                    "Claude usage data was not in the expected format.",
                    ClaudeQuotaFailureOrigin::UsageReportFormatChanged,
                )),
                ClaudeUsageRowSummary::default(),
            ),
            ClaudeUsageReportOutcome::FormatChanged { rows } => (
                Err(failure(
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
cargo test -p needlbar-quota --test claude_usage_report --test claude_usage_provider 2>&1 | grep -E '^error|FAILED|test result'
cargo fmt -p needlbar-quota --check; echo "fmt exit $?"
```

Expected: `test result: ok. 10 passed; 0 failed` (the provider, unchanged) and `test result: ok. 18 passed; 0 failed` (the parser: 13 existing and 5 new), then `fmt exit 0`.

- [ ] **Step 5: Commit**

```bash
git add Fixtures/quota/claude/usage-report-signed-out.jsonl \
  crates/needlbar-quota/src/providers/claude_usage_report.rs \
  crates/needlbar-quota/src/providers/claude_usage_provider.rs \
  crates/needlbar-quota/tests/claude_usage_report.rs
git commit -m "feat(quota): tell a /usage run without plan usage from a changed format" \
  -m "The parser returns PlanUsageUnavailable only when an assistant line names the usage command, no line has a usage_report key, not even null, and nothing reported a rate limit. A field deserializer keeps a present null apart from a missing key. Until the provider maps it, it fails as before." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The provider reports it as requiresAuthentication with its own origin

**Files:**
- Modify: `crates/needlbar-quota/src/domain.rs:89-92`
- Modify: `crates/needlbar-quota/src/providers/claude_usage_provider.rs:137-147`
- Test: `crates/needlbar-quota/tests/claude_usage_provider.rs:19-22,153-156`
- Test: `crates/needlbar-bridge/src/lib.rs:822-825` (the `#[cfg(test)]` module)

**Interfaces:**
- Consumes, from Task 1: `ClaudeUsageReportOutcome::PlanUsageUnavailable`, the fixture.
- Produces:
  - `ClaudeQuotaFailureOrigin::UsageReportPlanUsageUnavailable`, serialized as `"usageReportPlanUsageUnavailable"` (`#[serde(rename_all = "camelCase")]`)
  - a run's `QuotaError` with `code == QuotaErrorCode::RequiresAuthentication`, `provider == Some(ProviderId::Claude)` and `claude_failure_origin() == Some(UsageReportPlanUsageUnavailable)`, which the bridge sends as code `"requiresAuthentication"` and origin `"usageReportPlanUsageUnavailable"`

- [ ] **Step 1: Write the failing tests**

In `crates/needlbar-quota/tests/claude_usage_provider.rs`, replace

```rust
const WEEKLY_ONLY: &str =
    include_str!("../../../Fixtures/quota/claude/usage-report-weekly-only.jsonl");
const PREWARM: &str = "--needlbar-prewarm";

```

with

```rust
const WEEKLY_ONLY: &str =
    include_str!("../../../Fixtures/quota/claude/usage-report-weekly-only.jsonl");
const SIGNED_OUT: &str =
    include_str!("../../../Fixtures/quota/claude/usage-report-signed-out.jsonl");
const PREWARM: &str = "--needlbar-prewarm";

```

Then, in the same file, replace

```rust
}

#[tokio::test]
async fn a_rate_limit_error_without_a_report_is_rate_limited() {
```

with

```rust
}

#[tokio::test]
async fn a_run_without_plan_usage_requires_authentication_with_its_own_origin() {
    let run = run_output(SIGNED_OUT).await;
    assert_failure(
        &run,
        QuotaErrorCode::RequiresAuthentication,
        ClaudeQuotaFailureOrigin::UsageReportPlanUsageUnavailable,
    );
    let summary = run.summary.expect("summary");
    assert!(summary.row_kinds.is_empty());
    assert_eq!(summary.unknown_row_count, 0);
    assert_eq!(summary.skipped_row_count, 0);
    let error = run.result.expect_err("plan usage unavailable");
    let surfaces = format!("{error:?}{}", serde_json::to_string(&error).unwrap());
    for text in ["Estimated cost", "local_command", "0.0000"] {
        assert!(!surfaces.contains(text), "{text}");
    }
}

#[tokio::test]
async fn a_rate_limit_error_without_a_report_is_rate_limited() {
```

In `crates/needlbar-bridge/src/lib.rs`, replace

```rust
            (Origin::UsageReportRateLimited, "usageReportRateLimited"),
            (Origin::UsageReportFormatChanged, "usageReportFormatChanged"),
            (Origin::OtherFailure, "otherFailure"),
        ] {
```

with

```rust
            (Origin::UsageReportRateLimited, "usageReportRateLimited"),
            (Origin::UsageReportFormatChanged, "usageReportFormatChanged"),
            (
                Origin::UsageReportPlanUsageUnavailable,
                "usageReportPlanUsageUnavailable",
            ),
            (Origin::OtherFailure, "otherFailure"),
        ] {
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
cargo test -p needlbar-quota --test claude_usage_provider 2>&1 | grep -E '^error'
cargo test -p needlbar-bridge --features bridge-test-runtime --lib diagnostics_serializes_every_closed_claude_failure_origin_by_its_stable_name 2>&1 | grep -E '^error'
```

Expected: each prints `error[E0599]: no variant, associated function, or constant named `UsageReportPlanUsageUnavailable` found for enum `ClaudeQuotaFailureOrigin` in the current scope` and a `could not compile` line.

- [ ] **Step 3: Write the implementation**

In `crates/needlbar-quota/src/domain.rs`, replace

```rust
    /// A run finished without a usable `usage_report`.
    UsageReportFormatChanged,
    OtherFailure,
}
```

with

```rust
    /// A run finished without a usable `usage_report`.
    UsageReportFormatChanged,
    /// `/usage` finished with no `usage_report` key: Claude Code does not
    /// consider itself signed in with a Claude plan.
    UsageReportPlanUsageUnavailable,
    OtherFailure,
}
```

In `crates/needlbar-quota/src/providers/claude_usage_provider.rs`, replace

```rust
                ClaudeUsageRowSummary::default(),
            ),
            // Mapped to its own code and origin in the next commit; until then it
            // fails exactly as it did before the parser told it apart.
            ClaudeUsageReportOutcome::PlanUsageUnavailable => (
                Err(failure(
                    QuotaErrorCode::SchemaChanged,
                    "Claude usage data was not in the expected format.",
                    ClaudeQuotaFailureOrigin::UsageReportFormatChanged,
                )),
                ClaudeUsageRowSummary::default(),
```

with

```rust
                ClaudeUsageRowSummary::default(),
            ),
            // Claude Code is not signed in with a Claude plan, as far as it can
            // tell. The app does not retry this under backoff: waiting does not
            // sign it in.
            ClaudeUsageReportOutcome::PlanUsageUnavailable => (
                Err(failure(
                    QuotaErrorCode::RequiresAuthentication,
                    "Claude Code did not report plan usage.",
                    ClaudeQuotaFailureOrigin::UsageReportPlanUsageUnavailable,
                )),
                ClaudeUsageRowSummary::default(),
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
cargo test -p needlbar-quota --test claude_usage_provider --test claude_usage_report 2>&1 | grep -E '^error|FAILED|test result'
cargo test -p needlbar-bridge --features bridge-test-runtime --lib diagnostics_serializes_every_closed_claude_failure_origin_by_its_stable_name 2>&1 | grep 'test result'
cargo test --workspace --features bridge-test-runtime 2>&1 | grep -E 'FAILED|panicked' ; echo "grep exit $?"
cargo fmt -p needlbar-quota -p needlbar-bridge --check; echo "fmt exit $?"
```

Expected: `test result: ok. 11 passed` (provider) and `test result: ok. 18 passed` (parser); `test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 18 filtered out`; `grep exit 1` (no failing workspace test; the scratch run passed 169 tests in 24 binaries); `fmt exit 0`.

- [ ] **Step 5: Commit**

```bash
git add crates/needlbar-quota/src/domain.rs \
  crates/needlbar-quota/src/providers/claude_usage_provider.rs \
  crates/needlbar-quota/tests/claude_usage_provider.rs \
  crates/needlbar-bridge/src/lib.rs
git commit -m "feat(quota): report plan usage unavailable as requiresAuthentication" \
  -m "A /usage run without plan usage becomes a QuotaError with the existing RequiresAuthentication code and the new origin usageReportPlanUsageUnavailable, so the bridge, diagnostics and Swift need no new code string." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Swift maps requiresAuthentication to the new reason and decodes the origin

**Files:**
- Modify: `Sources/NeedlbarCore/Models/ClaudeQuotaFailureReason.swift:14-17,47-50,66-69,76-82`
- Modify: `Sources/NeedlbarCore/Diagnostics/DiagnosticsSnapshot.swift:115-118`
- Test: `Tests/NeedlbarCoreTests/ClaudeUsageReportReasonTests.swift:9-16,34-37,45-48,53-56`
- Test: `Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift:521-525` (spec §10 "about line 523")
- Test: `Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift:856-860` (spec §10 "about line 858")
- Test: `Tests/NeedlbarCoreTests/DiagnosticsTests.swift:66-70,128-131`
- Test: `Tests/NeedlbarCoreTests/BridgeDecodingTests.swift:139-142`
- Test: `Tests/NeedlbarTests/ClaudeQuotaFailureDiagnosticsReporterTests.swift:53-56,362-366`

**Interfaces:**
- Consumes, from Task 2: the code `"requiresAuthentication"` and the origin `"usageReportPlanUsageUnavailable"` in bridge envelopes.
- Produces:
  - `case planUsageUnavailable` on `public enum ClaudeQuotaFailureReason: String, Sendable, Equatable`, with `displayText == "Claude Code didn't report plan usage"` and `detailText` equal to the spec's detail
  - `ClaudeQuotaFailureReason(errorCode: "requiresAuthentication") == .planUsageUnavailable`; `"authenticationExpired"` stays `.quotaAccessUnavailable`
  - `case usageReportPlanUsageUnavailable` on `public enum ClaudeQuotaFailureOrigin: String, Decodable, Sendable, Equatable`

The diagnostics reporter needs no source change: it already logs any decoded origin and allowlists `requiresAuthentication` (`Sources/Needlbar/Diagnostics/ClaudeQuotaFailureDiagnosticsReporter.swift:10-36`).

- [ ] **Step 1: Update the three tables and write the failing tests**

In `Tests/NeedlbarCoreTests/ClaudeUsageReportReasonTests.swift`, replace

```swift
    @Test(arguments: [
        ("notInstalled", ClaudeQuotaFailureReason.claudeCodeNotInstalled),
        // No Claude path reports this any more, because a null usage report is
        // a failed check rather than proof of a signed-out user. The generic
        // mapping is the same as for an expired sign-in.
        ("requiresAuthentication", .quotaAccessUnavailable),
        ("authenticationExpired", .quotaAccessUnavailable),
        ("providerUnavailable", .claudeCodeCheckFailed),
```

with

```swift
    @Test(arguments: [
        ("notInstalled", ClaudeQuotaFailureReason.claudeCodeNotInstalled),
        // Only a `/usage` run that finished without plan usage sends this.
        ("requiresAuthentication", .planUsageUnavailable),
        ("authenticationExpired", .quotaAccessUnavailable),
        ("providerUnavailable", .claudeCodeCheckFailed),
```

Then, in the same file, replace

```swift
    }

    @Test func theNewCopyComesFromLocalizableKeys() throws {
        let directory = FileManager.default.temporaryDirectory
```

with

```swift
    }

    @Test func planUsageUnavailableNamesWhatClaudeCodeDidAndTheTerminalCommand() {
        #expect(ClaudeQuotaFailureReason.planUsageUnavailable.displayText == "Claude Code didn't report plan usage")
        #expect(ClaudeQuotaFailureReason.planUsageUnavailable.detailText
            == "Claude Code usually shows plan usage only when it's signed in with a Claude plan. Run claude auth login in Terminal, then choose Check now in Needlbar. API keys and usage-billed accounts have no plan limits to show.")
        #expect(ClaudeQuotaFailureReason.planUsageUnavailable.rawValue == "planUsageUnavailable")
    }

    @Test func theNewCopyComesFromLocalizableKeys() throws {
        let directory = FileManager.default.temporaryDirectory
```

Then, in the same file, replace

```swift
        "claudeQuota.reason.claudeCodeCheckFailed.detail" = "D";
        "claudeQuota.reason.usageReportFormatChanged" = "F";
        """
        try Data(table.utf8).write(to: directory.appendingPathComponent("Localizable.strings"))
```

with

```swift
        "claudeQuota.reason.claudeCodeCheckFailed.detail" = "D";
        "claudeQuota.reason.usageReportFormatChanged" = "F";
        "claudeQuota.reason.planUsageUnavailable" = "G";
        "claudeQuota.reason.planUsageUnavailable.detail" = "H";
        """
        try Data(table.utf8).write(to: directory.appendingPathComponent("Localizable.strings"))
```

Then, in the same file, replace

```swift
        #expect(ClaudeQuotaFailureReason.claudeCodeCheckFailed.localizedDetailText(bundle: bundle) == "D")
        #expect(ClaudeQuotaFailureReason.usageReportFormatChanged.localizedDisplayText(bundle: bundle) == "F")
    }

```

with

```swift
        #expect(ClaudeQuotaFailureReason.claudeCodeCheckFailed.localizedDetailText(bundle: bundle) == "D")
        #expect(ClaudeQuotaFailureReason.usageReportFormatChanged.localizedDisplayText(bundle: bundle) == "F")
        #expect(ClaudeQuotaFailureReason.planUsageUnavailable.localizedDisplayText(bundle: bundle) == "G")
        #expect(ClaudeQuotaFailureReason.planUsageUnavailable.localizedDetailText(bundle: bundle) == "H")
    }

```

In `Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift`, replace

```swift

    @Test(arguments: [
        ("requiresAuthentication", ClaudeQuotaFailureReason.quotaAccessUnavailable),
        ("notInstalled", .claudeCodeNotInstalled),
        ("providerUnavailable", .claudeCodeCheckFailed),
```

with

```swift

    @Test(arguments: [
        ("requiresAuthentication", ClaudeQuotaFailureReason.planUsageUnavailable),
        ("notInstalled", .claudeCodeNotInstalled),
        ("providerUnavailable", .claudeCodeCheckFailed),
```

In `Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift`, replace

```swift
    @Test func returnedClaudeQuotaErrorsMapOnlyAllowlistedCodesToSafeReasons() async throws {
        let cases: [(String, ClaudeQuotaFailureReason)] = [
            ("requiresAuthentication", .quotaAccessUnavailable),
            ("authenticationExpired", .quotaAccessUnavailable),
            ("permissionDenied", .couldNotUpdateQuota),
```

with

```swift
    @Test func returnedClaudeQuotaErrorsMapOnlyAllowlistedCodesToSafeReasons() async throws {
        let cases: [(String, ClaudeQuotaFailureReason)] = [
            ("requiresAuthentication", .planUsageUnavailable),
            ("authenticationExpired", .quotaAccessUnavailable),
            ("permissionDenied", .couldNotUpdateQuota),
```

In `Tests/NeedlbarCoreTests/DiagnosticsTests.swift`, replace

```swift
    let origins: [ClaudeQuotaFailureOrigin] = [
        .claudeCliNotFound, .usageReportNoUsage, .usageProbeTimedOut, .usageProbeOutputTooLarge,
        .usageProbeFailed, .usageReportRateLimited, .usageReportFormatChanged, .otherFailure,
    ]
    for origin in origins {
```

with

```swift
    let origins: [ClaudeQuotaFailureOrigin] = [
        .claudeCliNotFound, .usageReportNoUsage, .usageProbeTimedOut, .usageProbeOutputTooLarge,
        .usageProbeFailed, .usageReportRateLimited, .usageReportFormatChanged,
        .usageReportPlanUsageUnavailable, .otherFailure,
    ]
    for origin in origins {
```

Then, in the same file, replace

```swift
        "claudeCliNotFound", "usageReportNoUsage", "usageProbeTimedOut", "usageProbeOutputTooLarge",
        "usageProbeFailed", "usageReportRateLimited", "usageReportFormatChanged",
    ] {
        let payload = """
```

with

```swift
        "claudeCliNotFound", "usageReportNoUsage", "usageProbeTimedOut", "usageProbeOutputTooLarge",
        "usageProbeFailed", "usageReportRateLimited", "usageReportFormatChanged",
        "usageReportPlanUsageUnavailable",
    ] {
        let payload = """
```

In `Tests/NeedlbarCoreTests/BridgeDecodingTests.swift`, replace

```swift
        "claudeCliNotFound", "usageReportNoUsage", "usageProbeTimedOut", "usageProbeOutputTooLarge",
        "usageProbeFailed", "usageReportRateLimited", "usageReportFormatChanged",
    ] {
        let frees = FreeRecorder()
```

with

```swift
        "claudeCliNotFound", "usageReportNoUsage", "usageProbeTimedOut", "usageProbeOutputTooLarge",
        "usageProbeFailed", "usageReportRateLimited", "usageReportFormatChanged",
        "usageReportPlanUsageUnavailable",
    ] {
        let frees = FreeRecorder()
```

In `Tests/NeedlbarTests/ClaudeQuotaFailureDiagnosticsReporterTests.swift`, replace

```swift
        ("usageReportRateLimited", "rateLimited"),
        ("usageReportFormatChanged", "schemaChanged"),
    ]
    for (origin, code) in cases {
```

with

```swift
        ("usageReportRateLimited", "rateLimited"),
        ("usageReportFormatChanged", "schemaChanged"),
        ("usageReportPlanUsageUnavailable", "requiresAuthentication"),
    ]
    for (origin, code) in cases {
```

Then, in the same file, replace

```swift
    static let allCasesForTest: [Self] = [
        .claudeCliNotFound, .usageReportNoUsage, .usageProbeTimedOut, .usageProbeOutputTooLarge,
        .usageProbeFailed, .usageReportRateLimited, .usageReportFormatChanged, .otherFailure,
    ]
}
```

with

```swift
    static let allCasesForTest: [Self] = [
        .claudeCliNotFound, .usageReportNoUsage, .usageProbeTimedOut, .usageProbeOutputTooLarge,
        .usageProbeFailed, .usageReportRateLimited, .usageReportFormatChanged,
        .usageReportPlanUsageUnavailable, .otherFailure,
    ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make swift-test SWIFT_TEST_FILTER='"ClaudeUsageReportReasonTests|ClaudeUsageProbeCoordinatorTests|RefreshCoordinatorTests|diagnosticsDecoderAccepts|rustBridgeDiagnosticsEnvelopeDecodesEachSplit|reporter"'`

Expected: the build fails with `error: type 'ClaudeQuotaFailureOrigin' has no member 'usageReportPlanUsageUnavailable'` (first in `DiagnosticsTests.swift`) and `type 'ClaudeQuotaFailureReason' has no member 'planUsageUnavailable'`, and make ends with `make: *** [swift-test] Error 1`.

- [ ] **Step 3: Write the implementation**

In `Sources/NeedlbarCore/Models/ClaudeQuotaFailureReason.swift`, replace

```swift
    /// A run finished without a usable usage report.
    case usageReportFormatChanged

    public var displayText: String { localizedDisplayText(bundle: .main) }
```

with

```swift
    /// A run finished without a usable usage report.
    case usageReportFormatChanged
    /// `/usage` finished without plan usage, which Claude Code does when it does
    /// not consider itself signed in with a Claude plan.
    case planUsageUnavailable

    public var displayText: String { localizedDisplayText(bundle: .main) }
```

Then, in the same file, replace

```swift
                comment: "Claude quota reason: Claude Code finished but gave no usage report Needlbar can read."
            )
        }
    }
```

with

```swift
                comment: "Claude quota reason: Claude Code finished but gave no usage report Needlbar can read."
            )
        case .planUsageUnavailable:
            String(
                localized: "claudeQuota.reason.planUsageUnavailable",
                defaultValue: "Claude Code didn't report plan usage",
                bundle: bundle,
                comment: "Claude quota reason: Claude Code ran its usage command and finished without plan usage, which it does when it is not signed in with a Claude plan. Describes what Claude Code did, not a cause."
            )
        }
    }
```

Then, in the same file, replace

```swift
                comment: "Second line for the check-failed reason, shown in the provider popover and Settings. Keep 'claude' as the command name. Needlbar offers no button for this."
            )
        case .quotaAccessUnavailable, .connectionUnavailable,
             .temporarilyLimited, .couldNotUpdateQuota, .usageReportFormatChanged:
```

with

```swift
                comment: "Second line for the check-failed reason, shown in the provider popover and Settings. Keep 'claude' as the command name. Needlbar offers no button for this."
            )
        case .planUsageUnavailable:
            String(
                localized: "claudeQuota.reason.planUsageUnavailable.detail",
                defaultValue: "Claude Code usually shows plan usage only when it's signed in with a Claude plan. Run claude auth login in Terminal, then choose Check now in Needlbar. API keys and usage-billed accounts have no plan limits to show.",
                bundle: bundle,
                comment: "Second line for the plan-usage-unavailable reason, shown in the provider popover and Settings. Keep 'claude auth login' as the command and 'Check now' as the button name. Needlbar never runs the command and offers no sign-in button."
            )
        case .quotaAccessUnavailable, .connectionUnavailable,
             .temporarilyLimited, .couldNotUpdateQuota, .usageReportFormatChanged:
```

Then, in the same file, replace

```swift
        switch errorCode {
        case "notInstalled": self = .claudeCodeNotInstalled
        // No Claude path reports "requiresAuthentication" any more, so it shares
        // the generic reason with an expired sign-in.
        case "requiresAuthentication", "authenticationExpired": self = .quotaAccessUnavailable
        case "networkUnavailable": self = .connectionUnavailable
        case "rateLimited": self = .temporarilyLimited
```

with

```swift
        switch errorCode {
        case "notInstalled": self = .claudeCodeNotInstalled
        case "requiresAuthentication": self = .planUsageUnavailable
        case "authenticationExpired": self = .quotaAccessUnavailable
        case "networkUnavailable": self = .connectionUnavailable
        case "rateLimited": self = .temporarilyLimited
```

In `Sources/NeedlbarCore/Diagnostics/DiagnosticsSnapshot.swift`, replace

```swift
    /// A run finished without a usable `usage_report`.
    case usageReportFormatChanged
    case otherFailure
}
```

with

```swift
    /// A run finished without a usable `usage_report`.
    case usageReportFormatChanged
    /// `/usage` finished with no `usage_report` key: Claude Code does not
    /// consider itself signed in with a Claude plan.
    case usageReportPlanUsageUnavailable
    case otherFailure
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the same command as Step 2.

Expected: `Test run with 100 tests in 3 suites passed` (core: the three suites plus the matching free diagnostics and bridge decoding tests) and `Test run with 11 tests in 0 suites passed` (app: the reporter tests), and make exits 0.

- [ ] **Step 5: Commit**

```bash
git add Sources/NeedlbarCore/Models/ClaudeQuotaFailureReason.swift \
  Sources/NeedlbarCore/Diagnostics/DiagnosticsSnapshot.swift \
  Tests/NeedlbarCoreTests/ClaudeUsageReportReasonTests.swift \
  Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift \
  Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift \
  Tests/NeedlbarCoreTests/DiagnosticsTests.swift \
  Tests/NeedlbarCoreTests/BridgeDecodingTests.swift \
  Tests/NeedlbarTests/ClaudeQuotaFailureDiagnosticsReporterTests.swift
git commit -m "feat(claude): map requiresAuthentication to a plan usage unavailable reason" \
  -m "ClaudeQuotaFailureReason gains planUsageUnavailable with its row text and detail; authenticationExpired keeps the generic reason. The strict origin decoder accepts usageReportPlanUsageUnavailable, and the three tables that expected the generic reason are updated." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: No backoff retry for plan usage unavailable

**Files:**
- Modify: `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift:569-587`
- Create: `Tests/NeedlbarCoreTests/ClaudePlanUsageUnavailableRetryTests.swift`

**Interfaces:**
- Consumes, from Task 3: `ClaudeQuotaFailureReason.planUsageUnavailable`. Existing: `ClaudeUsageProbeSchedule.recordFailure(trigger:at:retriesWhenBackoffEnds:)`, `BridgeFailure.bridgeFailed([BridgeError])`, `BridgeError.providerID`, `ConditionWaiters` and `settle(watchingFor:)` (`Tests/NeedlbarCoreTests/TestWaiting.swift`), the internal `QuotaAttemptEvent` and `QuotaRefreshTrigger`.
- Produces: `private static func claudeErrorCode(in result: Result<QuotaRefreshResult, Error>) -> String?` on `RefreshCoordinator`. The test file's doubles are `private` and prefixed `Retry`, so they never collide with the private doubles of `ClaudeUsageProbeCoordinatorTests.swift`.

- [ ] **Step 1: Write the tests**

Create `Tests/NeedlbarCoreTests/ClaudePlanUsageUnavailableRetryTests.swift` with exactly this content:

```swift
import Foundation
import Testing
@testable import NeedlbarCore

// The retry rule for a `/usage` run that finished without plan usage (spec
// 2026-11-20 §4). Kept apart from ClaudeUsageProbeCoordinatorTests so the two
// files change independently. Everything is synthetic: fake repositories and a
// manual clock. Nothing here touches a process, the network or credentials.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ClaudePlanUsageUnavailableRetryTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func planUsageUnavailableWaitsForThePeriodicRunAndKeepsItsBackoff() async throws {
        let harness = RetryHarness()
        for _ in 0 ..< 3 { harness.probe.script(.result(claudeFailure("requiresAuthentication"))) }
        await harness.startedAndIdle()
        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == .planUsageUnavailable)
        #expect(await harness.store.snapshot(for: .claude).quotaStatus == .requiresAuthentication,
                "with no earlier success")

        // The five-minute backoff ends at 300 s and nothing retries by itself.
        await harness.advance(minutes: 14)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1, "no backoff retry")
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)

        // The second failure backs off ten minutes, which ends before the next periodic run.
        await harness.advance(minutes: 14)
        await settle(watchingFor: { harness.probe.callCount > 2 })
        #expect(harness.probe.callCount == 2)
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(3)
        await harness.waitUntilCompletedRuns(3)

        // The third failure backs off twenty minutes, which holds the periodic run
        // due at 2,700 s until 3,000 s.
        await harness.advance(minutes: 19)
        await settle(watchingFor: { harness.probe.callCount > 3 })
        #expect(harness.probe.callCount == 3, "the periodic run waits for backoff")
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(4)
        await harness.waitUntilCompletedRuns(4)
        #expect(harness.probe.startTimes.map { $0.timeIntervalSince(Self.start) } == [0, 900, 1_800, 3_000])
        #expect(harness.probe.triggersSeen(in: harness.events) == [.startup, .periodic, .periodic, .periodic])
        await harness.coordinator.stop()
    }

    @Test(arguments: ["requiresAuthentication", "notInstalled"])
    func aThrownBridgeFailureWithTheCodeAlsoWaitsForThePeriodicRun(code: String) async throws {
        let harness = RetryHarness()
        harness.probe.script(.failure(BridgeFailure.bridgeFailed([
            BridgeError(provider: "claude", code: code, message: "fixture", action: nil),
        ])))
        await harness.startedAndIdle()
        await harness.advance(minutes: 14)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1, "\(code) does not retry when backoff ends")
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)
        #expect(harness.probe.triggersSeen(in: harness.events) == [.startup, .periodic])
        await harness.coordinator.stop()
    }

    @Test func aThrownBridgeFailureWithAnotherCodeStillRetriesUnderBackoff() async throws {
        let harness = RetryHarness()
        harness.probe.script(.failure(BridgeFailure.bridgeFailed([
            BridgeError(provider: "claude", code: "schemaChanged", message: "fixture", action: nil),
        ])))
        await harness.startedAndIdle()
        await harness.advance(minutes: 5)
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)
        #expect(harness.probe.triggersSeen(in: harness.events) == [.startup, .backoffRetry])
        await harness.coordinator.stop()
    }

    @Test func checkNowStillRunsAndTheSameReasonReturns() async throws {
        let harness = RetryHarness()
        harness.probe.script(.result(claudeFailure("requiresAuthentication")))
        harness.probe.script(.result(claudeFailure("requiresAuthentication")))
        await harness.startedAndIdle()
        await harness.coordinator.manualRefresh()
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)
        #expect(harness.probe.startTimes == [Self.start, Self.start])
        #expect(harness.probe.triggersSeen(in: harness.events) == [.startup, .manual])
        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == .planUsageUnavailable)
        await harness.coordinator.stop()
    }

    @Test func afterAnEarlierSuccessTheStatusIsAnErrorAndTheReadingIsKept() async throws {
        let harness = RetryHarness()
        harness.probe.script(.result(try weeklyReading()))
        harness.probe.script(.result(claudeFailure("requiresAuthentication")))
        await harness.startedAndIdle()
        await harness.advance(minutes: 15)
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)
        let snapshot = await harness.store.snapshot(for: .claude)
        #expect(snapshot.claudeQuotaFailureReason == .planUsageUnavailable)
        #expect(snapshot.quotaStatus == .error(message: "Authentication is required.", lastSuccessfulAt: Self.start))
        #expect(snapshot.quota != nil)
        #expect(snapshot.quotaLastSuccessfulAt == Self.start)
        await harness.coordinator.stop()
    }
}

// MARK: - Fixtures

private func claudeFailure(_ code: String) -> QuotaRefreshResult {
    .init(snapshots: [:], errors: [.claude: .init(provider: "claude", code: code, message: "fixture", action: nil)])
}

private func weeklyReading() throws -> QuotaRefreshResult {
    .init(snapshots: [.claude: QuotaSnapshot(windows: [
        try QuotaWindow(id: "claude.weekly", title: "Weekly", usedPercent: 74, resetsAt: nil),
    ])], errors: [:])
}

// MARK: - Test doubles

private struct RetryHarness {
    let store: ProviderSnapshotStore
    let probe: RetryProbeRepository
    let other: RetryBackgroundRepository
    let clock: RetryManualClock
    let events = RetryAttemptEvents()
    let coordinator: RefreshCoordinator

    init() {
        let clock = RetryManualClock(now: ClaudePlanUsageUnavailableRetryTests.start)
        let events = self.events
        let probe = RetryProbeRepository(clock: clock)
        let other = RetryBackgroundRepository()
        let store = ProviderSnapshotStore(now: { clock.now })
        self.store = store
        self.probe = probe
        self.other = other
        self.clock = clock
        coordinator = RefreshCoordinator(
            usageRepository: RetryUsageRepository(),
            quotaRepository: other,
            claudeUsageRepository: probe,
            store: store,
            clock: clock,
            quotaAttemptObserver: { events.record($0) }
        )
    }

    func startedAndIdle() async {
        await coordinator.start()
        await waitUntilCompletedRuns(1)
        await other.waitUntilCallCount(1)
    }

    /// `QuotaAttemptLedger.complete` is the last thing a run does before it
    /// frees its slot, with no suspension between them.
    func waitUntilCompletedRuns(_ expected: Int) async {
        await events.changes.wait { events.values.filter { $0.phase == .completed }.count >= expected }
    }

    /// Moves time a minute at a time, each minute only after every loop sleeps.
    func advance(minutes: Int) async {
        for _ in 0 ..< minutes {
            await clock.waitUntilSleeperCount(3)
            clock.advance(by: 60)
            await clock.waitUntilSleeperCount(3)
        }
    }
}

private final class RetryAttemptEvents: @unchecked Sendable {
    private let lock = NSLock()
    let changes = ConditionWaiters()
    private var recorded: [QuotaAttemptEvent] = []
    var values: [QuotaAttemptEvent] { lock.withLock { recorded } }
    func record(_ event: QuotaAttemptEvent) {
        lock.withLock { recorded.append(event) }
        changes.signal()
    }
}

private final class RetryProbeRepository: QuotaRepository, @unchecked Sendable {
    enum Outcome {
        case result(QuotaRefreshResult)
        case failure(any Error)
    }

    private let clock: RetryManualClock
    private let lock = NSLock()
    private let changes = ConditionWaiters()
    private var outcomes: [Outcome] = []
    private var recordedStarts: [Date] = []

    init(clock: RetryManualClock) { self.clock = clock }

    var callCount: Int { lock.withLock { recordedStarts.count } }
    var startTimes: [Date] { lock.withLock { recordedStarts } }

    func script(_ outcome: Outcome) { lock.withLock { outcomes.append(outcome) } }
    func waitUntilCallCount(_ expected: Int) async { await changes.wait { self.callCount >= expected } }

    func triggersSeen(in events: RetryAttemptEvents) -> [QuotaRefreshTrigger] {
        events.values.filter { $0.phase == .started }.map(\.trigger)
    }

    func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult {
        guard case .claudeUsageReport = intent else { throw BridgeFailure.nullPointer }
        let scripted = lock.withLock { () -> Outcome? in
            recordedStarts.append(clock.now)
            return outcomes.isEmpty ? nil : outcomes.removeFirst()
        }
        changes.signal()
        // With nothing scripted a run succeeds.
        switch scripted {
        case .result(let result)?: return result
        case .failure(let error)?: throw error
        case nil: return try weeklyReading()
        }
    }

    func cancelClaudeUsageReport(through runID: UInt64) {}
}

/// The Codex and Cursor refresh.
private final class RetryBackgroundRepository: QuotaRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let changes = ConditionWaiters()
    private var calls = 0

    var callCount: Int { lock.withLock { calls } }
    func waitUntilCallCount(_ expected: Int) async { await changes.wait { self.callCount >= expected } }

    func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult {
        guard intent == .backgroundAll else { throw BridgeFailure.nullPointer }
        lock.withLock { calls += 1 }
        changes.signal()
        return .init(snapshots: [.codex: QuotaSnapshot(windows: [
            try QuotaWindow(id: "codex.primary", title: "Primary", usedPercent: 10, resetsAt: nil),
        ])], errors: [:])
    }
}

private final class RetryUsageRepository: UsageRepository, @unchecked Sendable {
    func refresh() throws -> UsageRefreshResult {
        .init(snapshots: [:], errors: [:])
    }
}

private final class RetryManualClock: ClockLike, @unchecked Sendable {
    private struct Sleeper {
        let deadline: Date
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private let changes = ConditionWaiters()
    private var date: Date
    private var sleepers: [UUID: Sleeper] = [:]

    init(now: Date) { date = now }

    var now: Date { lock.withLock { date } }
    var sleeperCount: Int { lock.withLock { sleepers.count } }

    func waitUntilSleeperCount(_ expected: Int) async {
        await changes.wait { self.sleeperCount >= expected }
    }

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        let id = UUID()
        let seconds = TimeInterval(duration.components.seconds)
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let cancelled = lock.withLock { () -> Bool in
                    if Task.isCancelled { return true }
                    sleepers[id] = .init(deadline: date.addingTimeInterval(seconds), continuation: continuation)
                    return false
                }
                if cancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    changes.signal()
                }
            }
        }, onCancel: {
            let sleeper = self.lock.withLock { self.sleepers.removeValue(forKey: id) }
            sleeper?.continuation.resume(throwing: CancellationError())
        })
    }

    func advance(by interval: TimeInterval) {
        let due = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            date = date.addingTimeInterval(interval)
            let ready = sleepers.filter { $0.value.deadline <= date }
            ready.keys.forEach { sleepers.removeValue(forKey: $0) }
            return ready.values.map(\.continuation)
        }
        due.forEach { $0.resume() }
    }
}
```

What the tests cover from spec §4 and §7: no backoff retry, the periodic run still runs, the recorded backoff still holds the periodic run at 20 minutes, a thrown bridge failure with either code, another thrown code still retrying, Check now running once with the same reason back, and the status with and without an earlier success.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudePlanUsageUnavailableRetryTests`

Expected: `✘ Test run with 5 tests in 1 suite failed … with 9 issues`: `planUsageUnavailableWaitsForThePeriodicRunAndKeepsItsBackoff()` fails at `harness.probe.callCount == 1` (a backoff retry ran), and both cases of `aThrownBridgeFailureWithTheCodeAlsoWaitsForThePeriodicRun(code:)` fail the same way. `aThrownBridgeFailureWithAnotherCodeStillRetriesUnderBackoff()`, `checkNowStillRunsAndTheSameReasonReturns()` and `afterAnEarlierSuccessTheStatusIsAnErrorAndTheReadingIsKept()` pass; they are guards. make ends with `make: *** [swift-test] Error 1`.

- [ ] **Step 3: Write the implementation**

In `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`, replace

```swift
        _ result: Result<QuotaRefreshResult, Error>, trigger: QuotaRefreshTrigger, at date: Date
    ) {
        var retries = true
        if case .success(let refresh) = result {
            if refresh.errors[.claude] == nil, refresh.snapshots[.claude] != nil {
                claudeUsageSchedule.recordSuccess()
                return
            }
            // Not installed waits for the next trigger, which includes the periodic
            // run (spec §8). Every other failure, including a null usage report,
            // retries under backoff.
            let code = refresh.errors[.claude]?.code
            retries = code != "notInstalled"
        }
        claudeUsageSchedule.recordFailure(trigger: trigger, at: date, retriesWhenBackoffEnds: retries)
    }

    private func requestStatusLineRead() {
        guard let repository = statusLineRepository else { return }
```

with

```swift
        _ result: Result<QuotaRefreshResult, Error>, trigger: QuotaRefreshTrigger, at date: Date
    ) {
        if case .success(let refresh) = result, refresh.errors[.claude] == nil, refresh.snapshots[.claude] != nil {
            claudeUsageSchedule.recordSuccess()
            return
        }
        // Not installed and plan usage unavailable wait for the next trigger, which
        // includes the periodic run (spec §8; 2026-11-20 spec §4): waiting neither
        // installs Claude Code nor signs it in. Every other failure, including a
        // null usage report, retries under backoff. Both still record the backoff.
        let code = Self.claudeErrorCode(in: result)
        let retries = code != "notInstalled" && code != "requiresAuthentication"
        claudeUsageSchedule.recordFailure(trigger: trigger, at: date, retriesWhenBackoffEnds: retries)
    }

    /// The Claude error code a run returned or threw, if it carried one.
    private static func claudeErrorCode(in result: Result<QuotaRefreshResult, Error>) -> String? {
        switch result {
        case .success(let refresh):
            return refresh.errors[.claude]?.code
        case .failure(let error):
            guard case .bridgeFailed(let errors)? = error as? BridgeFailure else { return nil }
            return errors.first { $0.providerID == .claude }?.code
        }
    }

    private func requestStatusLineRead() {
        guard let repository = statusLineRepository else { return }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make swift-test SWIFT_TEST_FILTER='"ClaudePlanUsageUnavailableRetryTests|ClaudeUsageProbeCoordinatorTests|ClaudeUsageProbeScheduleTests"'`

Expected: `Test run with 52 tests in 3 suites passed`, and make exits 0. In the scratch run the new suite passed 15 times out of 15 in a row.

- [ ] **Step 5: Commit**

```bash
git add Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift \
  Tests/NeedlbarCoreTests/ClaudePlanUsageUnavailableRetryTests.swift
git commit -m "feat(claude): do not retry plan usage unavailable under backoff" \
  -m "recordClaudeUsageOutcome reads the Claude error code from a returned result or a thrown bridge failure and skips the backoff retry for notInstalled and requiresAuthentication. The backoff time is still recorded, and the periodic run and Check now still run. The tests are in a new file to keep clear of the open automatic-checks work." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The app shows the reason, including on the Fable line

**Files:**
- Modify: `Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift:126-131`
- Test: `Tests/NeedlbarTests/ClaudeUsageReportPresentationTests.swift:96-100,107-116`
- Test: `Tests/NeedlbarTests/PopoverPresentationTests.swift:79-82`
- Test: `Tests/NeedlbarTests/ClaudeCheckNowActionTests.swift:19-22`

**Interfaces:**
- Consumes, from Task 3: `ClaudeQuotaFailureReason.planUsageUnavailable`, its `displayText` and `detailText`. Existing: `ProviderPopoverPresentation(snapshot:now:)` with `quotaFailureReasonText`, `quotaFailureDetailText`, `fableFailureReasonText`, `authenticationAction`, `requiresProviderSignIn`; the dashboard row's `quotaFailureReasonText` and `checkNowAction`. Settings shows the same presentation (`Sources/Needlbar/Settings/SettingsView.swift:297-316`), so it needs no change.
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing tests**

In `Tests/NeedlbarTests/ClaudeUsageReportPresentationTests.swift`, replace

```swift
            fiveHour: StatusLineWindowObservation(usedPercent: 25, resetsAt: nil, receivedAt: now.addingTimeInterval(-30)),
            sevenDay: StatusLineWindowObservation(usedPercent: 35, resetsAt: nil, receivedAt: now.addingTimeInterval(-30)))
        for reason in [ClaudeQuotaFailureReason.claudeCodeNotInstalled] {
            let popover = ProviderPopoverPresentation(
                snapshot: claude(windows: [try fable()], reason: reason, age: 3_600, statusLine: record), now: now)
```

with

```swift
            fiveHour: StatusLineWindowObservation(usedPercent: 25, resetsAt: nil, receivedAt: now.addingTimeInterval(-30)),
            sevenDay: StatusLineWindowObservation(usedPercent: 35, resetsAt: nil, receivedAt: now.addingTimeInterval(-30)))
        for reason in [ClaudeQuotaFailureReason.claudeCodeNotInstalled, .planUsageUnavailable] {
            let popover = ProviderPopoverPresentation(
                snapshot: claude(windows: [try fable()], reason: reason, age: 3_600, statusLine: record), now: now)
```

Then, in the same file, replace

```swift
    @Test func noCopyOffersAnAutomaticSignIn() {
        for reason in [ClaudeQuotaFailureReason.claudeCodeNotInstalled,
                       .claudeCodeCheckFailed, .usageReportFormatChanged] {
            let text = "\(reason.displayText) \(reason.detailText ?? "")"
            for forbidden in ["Keychain", "credential", "Always Allow", "token"] {
                #expect(!text.localizedCaseInsensitiveContains(forbidden), "\(reason) \(forbidden)")
            }
        }
    }
}
```

with

```swift
    @Test func noCopyOffersAnAutomaticSignIn() {
        for reason in [ClaudeQuotaFailureReason.claudeCodeNotInstalled,
                       .claudeCodeCheckFailed, .usageReportFormatChanged, .planUsageUnavailable] {
            let text = "\(reason.displayText) \(reason.detailText ?? "")"
            for forbidden in ["Keychain", "credential", "Always Allow", "token", "signed out", "automatically"] {
                #expect(!text.localizedCaseInsensitiveContains(forbidden), "\(reason) \(forbidden)")
            }
        }
    }

    @Test func planUsageUnavailableShowsItsReasonAndDetailAndKeepsTheUsageLink() throws {
        let reason = ClaudeQuotaFailureReason.planUsageUnavailable
        // With no earlier success the store reports the authentication status.
        let neverChecked = ProviderSnapshot(
            provider: .claude, usage: nil, quota: nil, usageStatus: .fresh,
            quotaStatus: .requiresAuthentication, updatedAt: now, claudeQuotaFailureReason: reason)
        // After one it reports an error and keeps the last value.
        let checkedBefore = claude(windows: [try weekly()], reason: reason, age: 7_200)
        for snapshot in [neverChecked, checkedBefore] {
            let popover = ProviderPopoverPresentation(snapshot: snapshot, now: now)
            #expect(popover.quotaFailureReasonText == "Claude Code didn't report plan usage")
            #expect(popover.quotaFailureDetailText == reason.detailText)
            #expect(popover.authenticationAction == .openClaudeUsage(title: "View Claude usage"))
            #expect(!popover.requiresProviderSignIn)
            #expect(dashboardRow(snapshot).quotaFailureReasonText == reason.displayText)
        }
        let lastKnown = ProviderPopoverPresentation(snapshot: checkedBefore, now: now)
        #expect(lastKnown.quotaIsLastKnown)
        #expect(lastKnown.lastKnownQuotaRemaining == "26%")
    }
}
```

In `Tests/NeedlbarTests/PopoverPresentationTests.swift`, replace

```swift
        (.claudeCodeCheckFailed, "Could not check Claude Code"),
        (.usageReportFormatChanged, "Could not read Claude Code's usage report"),
    ]

```

with

```swift
        (.claudeCodeCheckFailed, "Could not check Claude Code"),
        (.usageReportFormatChanged, "Could not read Claude Code's usage report"),
        (.planUsageUnavailable, "Claude Code didn't report plan usage"),
    ]

```

In `Tests/NeedlbarTests/ClaudeCheckNowActionTests.swift`, replace

```swift
        .quotaAccessUnavailable, .connectionUnavailable, .temporarilyLimited, .couldNotUpdateQuota,
        .claudeCodeNotInstalled, .claudeCodeCheckFailed, .usageReportFormatChanged,
    ]

```

with

```swift
        .quotaAccessUnavailable, .connectionUnavailable, .temporarilyLimited, .couldNotUpdateQuota,
        .claudeCodeNotInstalled, .claudeCodeCheckFailed, .usageReportFormatChanged,
        .planUsageUnavailable,
    ]

```

The extended `allReasons` list makes the existing hosted dashboard and Settings tests press **Check now** in this state too.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make swift-test SWIFT_TEST_FILTER='"ClaudeUsageReportPresentation|everySafeClaudeQuotaReasonRendersItsExactAllowlistedText|ClaudeCheckNowActionTests"'`

Expected: `✘ Test withRecentStatusLineValuesTheGuidanceMovesToTheFableLine() recorded an issue at ClaudeUsageReportPresentationTests.swift:103:13: Expectation failed: popover.fableFailureReasonText == reason.displayText`, then `✘ Test run with 20 tests in 2 suites failed … with 1 issue`, and make ends with `make: *** [swift-test] Error 1`.

- [ ] **Step 3: Write the implementation**

In `Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift`, replace

```swift
            quotaFailureReasonText = hasRecentClaudeQuota ? nil : reason?.displayText
            // While status-line windows are recent, a reason the user can act on is
            // shown once, on the Fable line it keeps from updating.
            let reasonSitsOnTheFableLine = reason == .claudeCodeNotInstalled
            fableFailureReasonText = hasRecentClaudeQuota && reasonSitsOnTheFableLine ? reason?.displayText : nil
            quotaFailureDetailText = reason?.detailText
```

with

```swift
            quotaFailureReasonText = hasRecentClaudeQuota ? nil : reason?.displayText
            // While status-line windows are recent, a reason the user can act on is
            // shown once, on the Fable line it keeps from updating. Only `/usage`
            // fills that line.
            let reasonSitsOnTheFableLine = reason == .claudeCodeNotInstalled || reason == .planUsageUnavailable
            fableFailureReasonText = hasRecentClaudeQuota && reasonSitsOnTheFableLine ? reason?.displayText : nil
            quotaFailureDetailText = reason?.detailText
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the same command as Step 2.

Expected: `Test run with 20 tests in 2 suites passed`, and make exits 0.

- [ ] **Step 5: Commit**

```bash
git add Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift \
  Tests/NeedlbarTests/ClaudeUsageReportPresentationTests.swift \
  Tests/NeedlbarTests/PopoverPresentationTests.swift \
  Tests/NeedlbarTests/ClaudeCheckNowActionTests.swift
git commit -m "feat(claude): show plan usage unavailable wherever reasons appear" \
  -m "While status-line windows are recent the reason sits once on the Fable line, which only /usage fills, as not installed already does. The popover, dashboard and Settings show its text and detail, Claude keeps View Claude usage and no sign-in button, and Check now stays available." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: An optional stale reason in the widget projection

**Files:**
- Modify: `Sources/NeedlbarWidgetSupport/WidgetProjection.swift:68-71,75-78,81-89,93-96,101-104,115-119,346-349,384-388,422-426`
- Test: `Tests/NeedlbarWidgetSupportTests/WidgetProjectionTests.swift:376-379,405-408,415-418`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `public enum WidgetQuotaStaleReason: String, Codable, Sendable, Equatable { case planUsageUnavailable }`
  - `public func isValid(for provider: WidgetProvider, stream: WidgetStreamState, lastSuccessfulAt: Date?, headline: WidgetQuotaHeadline?) -> Bool` on it
  - `public let staleReason: WidgetQuotaStaleReason?` on `WidgetQuotaRow`
  - `WidgetQuotaRow.init(provider:stream:lastSuccessfulAt:headline:fable:staleReason:) throws`, where `fable` and `staleReason` default to `nil`, so every existing call compiles unchanged
  - the JSON key `staleReason` on a quota row, a string; unknown strings decode as `nil`

- [ ] **Step 1: Write the failing tests**

In `Tests/NeedlbarWidgetSupportTests/WidgetProjectionTests.swift`, replace

```swift
        #expect(WidgetFableReading(remainingPercent: 100, resetsAt: nil).isValid(for: .claude, lastSuccessfulAt: referenceDate))
    }
}

```

with

```swift
        #expect(WidgetFableReading(remainingPercent: 100, resetsAt: nil).isValid(for: .claude, lastSuccessfulAt: referenceDate))
    }

    // MARK: Stale reason

    @Test
    func aStaleReasonRoundTripsThroughBothDecodePaths() throws {
        let projection = try fableProjection(claude: staleClaudeRow(staleReason: .planUsageUnavailable))
        let decoded = try WidgetProjection.decode(WidgetProjection.encode(projection), referenceDate: referenceDate)
        #expect(decoded == projection)
        #expect(decoded.quotaRows[0].staleReason == .planUsageUnavailable)
        #expect(decoded.quotaRows[1].staleReason == nil)
        #expect(String(decoding: try WidgetProjection.encode(projection), as: UTF8.self)
            .contains(#""staleReason":"planUsageUnavailable""#))

        // The row's own coding, which the projection decoder does not use.
        let row = try JSONDecoder().decode(WidgetQuotaRow.self, from: JSONEncoder().encode(projection.quotaRows[0]))
        #expect(row.staleReason == .planUsageUnavailable)

        let without = try fableProjection(claude: staleClaudeRow(staleReason: nil))
        let encoded = String(decoding: try WidgetProjection.encode(without), as: UTF8.self)
        #expect(!encoded.contains("staleReason"))
        #expect(try WidgetProjection.decode(Data(encoded.utf8), referenceDate: referenceDate) == without)
    }

    @Test
    func anAbsentNullOrUnknownStaleReasonDecodesAsNoReason() throws {
        let cases = [
            staleClaudeRowJSON,
            staleClaudeRowJSON + #","staleReason":null"#,
            staleClaudeRowJSON + #","staleReason":"signInExpired""#,
            // An unknown value is dropped before validation, so it cannot reject a fresh row.
            claudeRowJSON + #","staleReason":"signInExpired""#,
        ]
        let rowDecoder = JSONDecoder()
        rowDecoder.dateDecodingStrategy = .iso8601
        for members in cases {
            let decoded = try WidgetProjection.decode(document(claude: members), referenceDate: referenceDate)
            #expect(decoded.quotaRows[0].staleReason == nil, "\(members)")
            #expect(decoded.quotaRows[0].headline?.remainingPercent == 77)

            let row = try rowDecoder.decode(WidgetQuotaRow.self, from: Data(("{" + members + "}").utf8))
            #expect(row.staleReason == nil, "\(members)")
        }
        let known = try WidgetProjection.decode(
            document(claude: staleClaudeRowJSON + #","staleReason":"planUsageUnavailable""#), referenceDate: referenceDate)
        #expect(known.quotaRows[0].staleReason == .planUsageUnavailable)
    }

    @Test
    func aStaleReasonIsRejectedOffAStoppedClaudeRow() {
        let reason = WidgetQuotaStaleReason.planUsageUnavailable
        let headline = WidgetQuotaHeadline(id: .claudeWeekly, remainingPercent: 77, resetsAt: nil)
        // Codex, no last successful time, no headline, a fresh stream.
        #expect(throws: WidgetProjectionError.invalidQuotaRow) {
            try WidgetQuotaRow(provider: .codex, stream: .stale, lastSuccessfulAt: referenceDate,
                               headline: WidgetQuotaHeadline(id: .codexPrimary, remainingPercent: 85, resetsAt: nil),
                               staleReason: reason)
        }
        #expect(throws: WidgetProjectionError.invalidQuotaRow) {
            try WidgetQuotaRow(provider: .claude, stream: .unavailable, lastSuccessfulAt: nil, headline: nil, staleReason: reason)
        }
        #expect(throws: WidgetProjectionError.invalidQuotaRow) {
            try WidgetQuotaRow(provider: .claude, stream: .stale, lastSuccessfulAt: referenceDate, headline: nil, staleReason: reason)
        }
        #expect(throws: WidgetProjectionError.invalidQuotaRow) {
            try WidgetQuotaRow(provider: .claude, stream: .fresh, lastSuccessfulAt: referenceDate, headline: headline, staleReason: reason)
        }
        #expect(reason.isValid(for: .claude, stream: .stale, lastSuccessfulAt: referenceDate, headline: headline))
        #expect(reason.isValid(for: .claude, stream: .unavailable, lastSuccessfulAt: referenceDate, headline: headline))
    }

    @Test
    func aFileWithAStaleReasonOnAnInvalidRowIsRejected() {
        let reason = #","staleReason":"planUsageUnavailable""#
        let onCodex = document(codex: #""provider":"codex","stream":"stale","lastSuccessfulAt":"2027-01-15T08:00:00Z","headline":{"id":"codex.primary","remainingPercent":85,"resetsAt":null}"# + reason)
        let onFresh = document(claude: claudeRowJSON + reason)
        let withoutHeadline = document(
            claude: #""provider":"claude","stream":"stale","lastSuccessfulAt":"2027-01-15T08:00:00Z","headline":null"# + reason)
        let withoutLastSuccess = document(
            claude: #""provider":"claude","stream":"unavailable","lastSuccessfulAt":null,"headline":null"# + reason)
        for bytes in [onCodex, onFresh, withoutHeadline, withoutLastSuccess] {
            #expect(throws: WidgetProjectionError.invalidQuotaRow) {
                try WidgetProjection.decode(bytes, referenceDate: referenceDate)
            }
        }
    }
}

```

Then, in the same file, replace

```swift
}

private func fableProjection(claude: WidgetQuotaRow) throws -> WidgetProjection {
    try WidgetProjection(
```

with

```swift
}

private func staleClaudeRow(staleReason: WidgetQuotaStaleReason?) throws -> WidgetQuotaRow {
    try WidgetQuotaRow(
        provider: .claude,
        stream: .stale,
        lastSuccessfulAt: referenceDate,
        headline: WidgetQuotaHeadline(id: .claudeWeekly, remainingPercent: 77, resetsAt: nil),
        staleReason: staleReason
    )
}

private func fableProjection(claude: WidgetQuotaRow) throws -> WidgetProjection {
    try WidgetProjection(
```

Then, in the same file, replace

```swift
// `referenceDate` is 2027-01-15T08:00:00Z.
private let claudeRowJSON = #""provider":"claude","stream":"fresh","lastSuccessfulAt":"2027-01-15T08:00:00Z","headline":{"id":"claude.weekly","remainingPercent":77,"resetsAt":null}"#
private let codexRowJSON = #""provider":"codex","stream":"fresh","lastSuccessfulAt":"2027-01-15T08:00:00Z","headline":{"id":"codex.primary","remainingPercent":85,"resetsAt":null}"#
private let fableJSON = #","fable":{"remainingPercent":71,"resetsAt":"2027-01-15T09:00:00Z"}"#
```

with

```swift
// `referenceDate` is 2027-01-15T08:00:00Z.
private let claudeRowJSON = #""provider":"claude","stream":"fresh","lastSuccessfulAt":"2027-01-15T08:00:00Z","headline":{"id":"claude.weekly","remainingPercent":77,"resetsAt":null}"#
private let staleClaudeRowJSON = #""provider":"claude","stream":"stale","lastSuccessfulAt":"2027-01-15T08:00:00Z","headline":{"id":"claude.weekly","remainingPercent":77,"resetsAt":null}"#
private let codexRowJSON = #""provider":"codex","stream":"fresh","lastSuccessfulAt":"2027-01-15T08:00:00Z","headline":{"id":"codex.primary","remainingPercent":85,"resetsAt":null}"#
private let fableJSON = #","fable":{"remainingPercent":71,"resetsAt":"2027-01-15T09:00:00Z"}"#
```

What the tests cover from spec §6 and §8: a round trip with and without the field on both decode paths, an old file without the key, `null`, an unknown value (also on a fresh row), no key when there is no reason, and each invalid combination through the initializer and through a file. `aProjectionWithoutFableEncodesExactlyAsBefore` already pins the bytes of a projection without the field.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make swift-test SWIFT_TEST_FILTER=NeedlbarWidgetSupportTests`

Expected: the build fails with `error: cannot find type 'WidgetQuotaStaleReason' in scope`, and make ends with `make: *** [swift-test] Error 1`.

- [ ] **Step 3: Write the implementation**

In `Sources/NeedlbarWidgetSupport/WidgetProjection.swift`, replace

```swift
}

public struct WidgetQuotaRow: Codable, Sendable, Equatable {
    public let provider: WidgetProvider
```

with

```swift
}

/// Why the Claude reading stopped updating, when the widget can say so. Both decoders
/// read it as a string and drop a value they do not know, so a later case cannot
/// blank an older widget.
public enum WidgetQuotaStaleReason: String, Codable, Sendable, Equatable {
    /// Claude Code finished its usage check without plan usage.
    case planUsageUnavailable

    /// Whether a quota row with these values may carry the reason: only the Claude row,
    /// with a last successful time and a headline, while its stream is not fresh. The
    /// row, the projection and the app's mapper all use this one rule.
    public func isValid(
        for provider: WidgetProvider,
        stream: WidgetStreamState,
        lastSuccessfulAt: Date?,
        headline: WidgetQuotaHeadline?
    ) -> Bool {
        provider == .claude && lastSuccessfulAt != nil && headline != nil && stream != .fresh
    }
}

public struct WidgetQuotaRow: Codable, Sendable, Equatable {
    public let provider: WidgetProvider
```

Then, in the same file, replace

```swift
    /// Only on the Claude row. `nil` encodes as no key, as before the field existed.
    public let fable: WidgetFableReading?

    public init(
```

with

```swift
    /// Only on the Claude row. `nil` encodes as no key, as before the field existed.
    public let fable: WidgetFableReading?
    /// Only on a stopped Claude row. `nil` encodes as no key, as before the field existed.
    public let staleReason: WidgetQuotaStaleReason?

    public init(
```

Then, in the same file, replace

```swift
        lastSuccessfulAt: Date?,
        headline: WidgetQuotaHeadline?,
        fable: WidgetFableReading? = nil
    ) throws {
        guard provider != .cursor,
              headline.map({ $0.id.provider == provider }) ?? true,
              fable.map({ $0.isValid(for: provider, lastSuccessfulAt: lastSuccessfulAt) }) ?? true else {
            throw WidgetProjectionError.invalidQuotaRow
        }
```

with

```swift
        lastSuccessfulAt: Date?,
        headline: WidgetQuotaHeadline?,
        fable: WidgetFableReading? = nil,
        staleReason: WidgetQuotaStaleReason? = nil
    ) throws {
        guard provider != .cursor,
              headline.map({ $0.id.provider == provider }) ?? true,
              fable.map({ $0.isValid(for: provider, lastSuccessfulAt: lastSuccessfulAt) }) ?? true,
              staleReason.map({
                  $0.isValid(for: provider, stream: stream, lastSuccessfulAt: lastSuccessfulAt, headline: headline)
              }) ?? true else {
            throw WidgetProjectionError.invalidQuotaRow
        }
```

Then, in the same file, replace

```swift
        self.headline = headline
        self.fable = fable
    }

```

with

```swift
        self.headline = headline
        self.fable = fable
        self.staleReason = staleReason
    }

```

Then, in the same file, replace

```swift
        case headline
        case fable
    }

```

with

```swift
        case headline
        case fable
        case staleReason
    }

```

Then, in the same file, replace

```swift
            lastSuccessfulAt: try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulAt),
            headline: headline,
            fable: try container.decodeIfPresent(WidgetFableReading.self, forKey: .fable)
        )
    }
```

with

```swift
            lastSuccessfulAt: try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulAt),
            headline: headline,
            fable: try container.decodeIfPresent(WidgetFableReading.self, forKey: .fable),
            staleReason: try container.decodeIfPresent(String.self, forKey: .staleReason)
                .flatMap(WidgetQuotaStaleReason.init(rawValue:))
        )
    }
```

Then, in the same file, replace

```swift
        let headline: RawQuotaHeadline?
        let fable: WidgetFableReading?
    }

```

with

```swift
        let headline: RawQuotaHeadline?
        let fable: WidgetFableReading?
        let staleReason: String?
    }

```

Then, in the same file, replace

```swift
                lastSuccessfulAt: row.lastSuccessfulAt,
                headline: headline,
                fable: row.fable
            )
        }
```

with

```swift
                lastSuccessfulAt: row.lastSuccessfulAt,
                headline: headline,
                fable: row.fable,
                staleReason: row.staleReason.flatMap(WidgetQuotaStaleReason.init(rawValue:))
            )
        }
```

Then, in the same file, replace

```swift
                  }) ?? true,
                  row.headline == nil || row.lastSuccessfulAt != nil,
                  row.fable.map({ $0.isValid(for: row.provider, lastSuccessfulAt: row.lastSuccessfulAt) }) ?? true else {
                throw WidgetProjectionError.invalidQuotaRow
            }
```

with

```swift
                  }) ?? true,
                  row.headline == nil || row.lastSuccessfulAt != nil,
                  row.fable.map({ $0.isValid(for: row.provider, lastSuccessfulAt: row.lastSuccessfulAt) }) ?? true,
                  row.staleReason.map({
                      $0.isValid(for: row.provider, stream: row.stream, lastSuccessfulAt: row.lastSuccessfulAt, headline: row.headline)
                  }) ?? true else {
                throw WidgetProjectionError.invalidQuotaRow
            }
```

`WidgetProjection.schemaVersion` stays `1`. The comments contain none of the guarded words.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make swift-test SWIFT_TEST_FILTER=NeedlbarWidgetSupportTests`

Expected: `Test run with 56 tests in 2 suites passed` (52 existing and 4 new), and make exits 0.

- [ ] **Step 5: Commit**

```bash
git add Sources/NeedlbarWidgetSupport/WidgetProjection.swift Tests/NeedlbarWidgetSupportTests/WidgetProjectionTests.swift
git commit -m "feat(widget): carry an optional stale reason on the Claude quota row" \
  -m "WidgetQuotaRow gains staleReason with one case, planUsageUnavailable, allowed only on a Claude row with a last successful time and a headline whose stream is not fresh. Both decoders read it as a string and drop unknown values, and the schema version stays 1." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: The mapper sets the stale reason from the captured Claude reason

**Files:**
- Modify: `Sources/NeedlbarCore/Widget/WidgetUsageDayProvenance.swift:78-83,88-91`
- Modify: `Sources/NeedlbarCore/State/ProviderSnapshotStore.swift:213-217`
- Modify: `Sources/NeedlbarCore/Widget/WidgetProjectionMapper.swift:49-56`
- Create: `Tests/NeedlbarCoreTests/WidgetPlanUsageUnavailableMapperTests.swift`

**Interfaces:**
- Consumes, from Task 6: `WidgetQuotaStaleReason`, its `isValid(for:stream:lastSuccessfulAt:headline:)`, `WidgetQuotaRow.init(...staleReason:)`, `WidgetQuotaRow.staleReason`. From Task 3: `ClaudeQuotaFailureReason.planUsageUnavailable`. Existing: `ProviderSnapshotStore.applyQuota(_:for:at:)` (clears the stored reason), `markQuotaFailure(for:status:claudeFailureReason:at:)` (replaces it), `applyClaudeStatusLineQuota(_:)`, `captureForWidget(exportedAt:)`.
- Produces:
  - `public let claudeQuotaFailureReason: ClaudeQuotaFailureReason?` on `WidgetProviderCapture`, and an initializer parameter of that name defaulting to `nil`, so the existing caller in `Tests/NeedlbarCoreTests/WidgetProjectionTests.swift:106` compiles unchanged
  - private `staleReason(_:provider:stream:headline:) -> WidgetQuotaStaleReason?` on `WidgetProjectionMapper`

- [ ] **Step 1: Write the failing tests**

Create `Tests/NeedlbarCoreTests/WidgetPlanUsageUnavailableMapperTests.swift` with exactly this content:

```swift
import Foundation
import NeedlbarClaudeStatusLineSupport
import NeedlbarWidgetSupport
import Testing
@testable import NeedlbarCore

// The widget's stale reason, from the store's captured Claude failure reason to the
// projection row (spec 2026-11-20 §6). Everything is synthetic.
@Suite("WidgetPlanUsageUnavailableMapper")
struct WidgetPlanUsageUnavailableMapperTests {
    private let checkedAt = Date(timeIntervalSince1970: 1_800_000_000)
    private var now: Date { checkedAt.addingTimeInterval(3_600) }

    private func weekly() throws -> QuotaSnapshot {
        QuotaSnapshot(windows: [
            try QuotaWindow(id: "claude.weekly", title: "Weekly", usedPercent: 74, resetsAt: nil),
        ])
    }

    private func projection(_ store: ProviderSnapshotStore) async throws -> WidgetProjection {
        try WidgetProjectionMapper(now: now).map(await store.captureForWidget(exportedAt: now))
    }

    private func markPlanUsageUnavailable(_ store: ProviderSnapshotStore) async {
        await store.markQuotaFailure(
            for: .claude, status: .requiresAuthentication, claudeFailureReason: .planUsageUnavailable, at: now)
    }

    @Test func theCaptureCarriesOnlyTheClaudeReason() async throws {
        let store = ProviderSnapshotStore(now: { self.now })
        await store.applyQuota(try weekly(), for: .claude, at: checkedAt)
        await markPlanUsageUnavailable(store)
        await store.markQuotaFailure(for: .codex, status: .requiresAuthentication, at: now)
        let capture = await store.captureForWidget(exportedAt: now)
        #expect(capture.providers.map(\.claudeQuotaFailureReason) == [.planUsageUnavailable, nil, nil])
    }

    @Test func aPlanUsageFailureAfterASuccessMarksTheStaleClaudeRow() async throws {
        let store = ProviderSnapshotStore(now: { self.now })
        await store.applyQuota(try weekly(), for: .claude, at: checkedAt)
        await markPlanUsageUnavailable(store)
        let rows = try await projection(store).quotaRows
        #expect(rows[0].stream == .stale)
        #expect(rows[0].lastSuccessfulAt == checkedAt)
        #expect(rows[0].headline?.id == .claudeWeekly)
        #expect(rows[0].staleReason == .planUsageUnavailable)
        #expect(rows[1].staleReason == nil)
    }

    @Test func aSuccessClearsTheReasonAndADifferentFailureReplacesIt() async throws {
        let store = ProviderSnapshotStore(now: { self.now })
        await store.applyQuota(try weekly(), for: .claude, at: checkedAt)
        await markPlanUsageUnavailable(store)
        #expect(try await projection(store).quotaRows[0].staleReason == .planUsageUnavailable)

        await store.applyQuota(try weekly(), for: .claude, at: now)
        let cleared = try await projection(store).quotaRows[0]
        #expect(cleared.stream == .fresh)
        #expect(cleared.staleReason == nil)

        await markPlanUsageUnavailable(store)
        await store.markQuotaFailure(
            for: .claude, status: .error(message: "fixture", lastSuccessfulAt: nil),
            claudeFailureReason: .usageReportFormatChanged, at: now)
        let replaced = try await projection(store).quotaRows[0]
        #expect(replaced.stream == .stale)
        #expect(replaced.staleReason == nil)
    }

    @Test func otherReasonsNeverSetIt() async throws {
        for reason in [ClaudeQuotaFailureReason.quotaAccessUnavailable, .connectionUnavailable, .temporarilyLimited,
                       .couldNotUpdateQuota, .claudeCodeNotInstalled, .claudeCodeCheckFailed, .usageReportFormatChanged] {
            let store = ProviderSnapshotStore(now: { self.now })
            await store.applyQuota(try weekly(), for: .claude, at: checkedAt)
            await store.markQuotaFailure(
                for: .claude, status: .error(message: "fixture", lastSuccessfulAt: nil), claudeFailureReason: reason, at: now)
            #expect(try await projection(store).quotaRows[0].staleReason == nil, "\(reason)")
        }
    }

    @Test func theReasonIsLeftOutWithoutThrowingWhenTheRowCannotCarryIt() async throws {
        // No earlier success: no last successful time and no headline.
        let neverChecked = ProviderSnapshotStore(now: { self.now })
        await markPlanUsageUnavailable(neverChecked)
        let undated = try await projection(neverChecked).quotaRows[0]
        #expect(undated.lastSuccessfulAt == nil)
        #expect(undated.staleReason == nil)

        // A reading with Fable only has no headline.
        let fableOnly = ProviderSnapshotStore(now: { self.now })
        await fableOnly.applyQuota(QuotaSnapshot(windows: [
            try QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "Fable weekly", usedPercent: 3, resetsAt: nil),
        ]), for: .claude, at: checkedAt)
        await markPlanUsageUnavailable(fableOnly)
        let withoutHeadline = try await projection(fableOnly).quotaRows[0]
        #expect(withoutHeadline.headline == nil)
        #expect(withoutHeadline.staleReason == nil)
    }

    @Test func aFresherStatusLineReadingDoesNotClearIt() async throws {
        let store = ProviderSnapshotStore(now: { self.now })
        await store.applyQuota(try weekly(), for: .claude, at: checkedAt)
        await markPlanUsageUnavailable(store)
        await store.applyClaudeStatusLineQuota(StatusLineQuotaRecord(
            schemaVersion: StatusLineQuotaRecord.currentSchemaVersion, generation: UUID(),
            fiveHour: StatusLineWindowObservation(usedPercent: 10, resetsAt: nil, receivedAt: now),
            sevenDay: StatusLineWindowObservation(usedPercent: 20, resetsAt: nil, receivedAt: now)))
        let row = try await projection(store).quotaRows[0]
        #expect(row.headline?.remainingPercent == 26, "the widget shows only the stalled /usage value")
        #expect(row.staleReason == .planUsageUnavailable)
    }
}
```

What the tests cover from spec §6 and §8: the capture carries only Claude's reason; the field is set after a success; a success clears it and a different failure replaces it; other reasons never set it; it is left out without throwing with no earlier success or no headline; and a newer status-line reading does not clear it.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make swift-test SWIFT_TEST_FILTER='"WidgetPlanUsageUnavailableMapperTests|WidgetProjection"'`

Expected: the build fails with `error: value of type 'WidgetProviderCapture' has no member 'claudeQuotaFailureReason'`, and make ends with `make: *** [swift-test] Error 1`.

- [ ] **Step 3: Write the implementation**

In `Sources/NeedlbarCore/Widget/WidgetUsageDayProvenance.swift`, replace

```swift
    public let quotaLastSuccessfulAt: Date?
    public let usageDayProvenance: WidgetUsageDayProvenance?

    public init(provider: ProviderID, usage: UsageSnapshot?, quota: QuotaSnapshot?, usageStatus: DataStatus, quotaStatus: DataStatus, usageLastSuccessfulAt: Date?, quotaLastSuccessfulAt: Date?, usageDayProvenance: WidgetUsageDayProvenance?) {
        self.provider = provider
        self.usage = usage
```

with

```swift
    public let quotaLastSuccessfulAt: Date?
    public let usageDayProvenance: WidgetUsageDayProvenance?
    /// The store's safe Claude failure reason; `nil` for other providers.
    public let claudeQuotaFailureReason: ClaudeQuotaFailureReason?

    public init(provider: ProviderID, usage: UsageSnapshot?, quota: QuotaSnapshot?, usageStatus: DataStatus, quotaStatus: DataStatus, usageLastSuccessfulAt: Date?, quotaLastSuccessfulAt: Date?, usageDayProvenance: WidgetUsageDayProvenance?, claudeQuotaFailureReason: ClaudeQuotaFailureReason? = nil) {
        self.provider = provider
        self.usage = usage
```

Then, in the same file, replace

```swift
        self.quotaLastSuccessfulAt = quotaLastSuccessfulAt
        self.usageDayProvenance = usageDayProvenance
    }
}
```

with

```swift
        self.quotaLastSuccessfulAt = quotaLastSuccessfulAt
        self.usageDayProvenance = usageDayProvenance
        self.claudeQuotaFailureReason = claudeQuotaFailureReason
    }
}
```

In `Sources/NeedlbarCore/State/ProviderSnapshotStore.swift`, replace

```swift
                usageLastSuccessfulAt: state.usage.lastSuccessfulAt,
                quotaLastSuccessfulAt: state.quota.lastSuccessfulAt,
                usageDayProvenance: state.usage.usageDayProvenance
            )
        })
```

with

```swift
                usageLastSuccessfulAt: state.usage.lastSuccessfulAt,
                quotaLastSuccessfulAt: state.quota.lastSuccessfulAt,
                usageDayProvenance: state.usage.usageDayProvenance,
                claudeQuotaFailureReason: provider == .claude ? state.claudeQuotaFailureReason : nil
            )
        })
```

In `Sources/NeedlbarCore/Widget/WidgetProjectionMapper.swift`, replace

```swift
            lastSuccessfulAt: capture.quotaLastSuccessfulAt,
            headline: candidates.first,
            fable: fableReading(capture, provider: provider)
        )
    }

    /// Fable is secondary text, so anything wrong with it drops it and never throws: the
    /// publisher maps with `try?`, and a thrown error would stop every widget update.
```

with

```swift
            lastSuccessfulAt: capture.quotaLastSuccessfulAt,
            headline: candidates.first,
            fable: fableReading(capture, provider: provider),
            staleReason: staleReason(capture, provider: provider, stream: stream, headline: candidates.first)
        )
    }

    /// Like Fable, the reason is secondary: when the row cannot carry it, it is left out and
    /// nothing throws. It is set even while a status-line reading is newer, because the
    /// widget shows only `/usage` values and its figure is the one that stopped.
    private func staleReason(
        _ capture: WidgetProviderCapture,
        provider: WidgetProvider,
        stream: WidgetStreamState,
        headline: WidgetQuotaHeadline?
    ) -> WidgetQuotaStaleReason? {
        guard capture.claudeQuotaFailureReason == .planUsageUnavailable else { return nil }
        let reason = WidgetQuotaStaleReason.planUsageUnavailable
        let carried = reason.isValid(
            for: provider, stream: stream, lastSuccessfulAt: capture.quotaLastSuccessfulAt, headline: headline)
        return carried ? reason : nil
    }

    /// Fable is secondary text, so anything wrong with it drops it and never throws: the
    /// publisher maps with `try?`, and a thrown error would stop every widget update.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the same command as Step 2.

Expected: `Test run with 26 tests in 1 suite passed` (the support target's `WidgetProjectionTests`) and `Test run with 23 tests in 2 suites passed` (the core target's `WidgetProjectionTests`, 17, and the new suite, 6), and make exits 0.

- [ ] **Step 5: Commit**

```bash
git add Sources/NeedlbarCore/Widget/WidgetUsageDayProvenance.swift \
  Sources/NeedlbarCore/State/ProviderSnapshotStore.swift \
  Sources/NeedlbarCore/Widget/WidgetProjectionMapper.swift \
  Tests/NeedlbarCoreTests/WidgetPlanUsageUnavailableMapperTests.swift
git commit -m "feat(widget): set the stale reason from the captured Claude failure reason" \
  -m "The store's widget capture carries Claude's safe failure reason, and the mapper sets staleReason only when it is planUsageUnavailable and the row can carry it. It never throws for the field, clears on a success and is replaced by a different failure." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: The widget asks to sign in to Claude Code

**Files:**
- Modify: `Sources/NeedlbarWidgetSupport/WidgetPresentation.swift:44-47,67-70,78-81,87-90,215-218,233-236,252-255,272-275`
- Modify: `WidgetExtension/NeedlbarOverviewWidget.swift:158-161,165-173`
- Test: `Tests/NeedlbarWidgetSupportTests/WidgetOverviewPresentationTests.swift:400-403,432-436,439-443`

**Interfaces:**
- Consumes, from Task 6: `WidgetQuotaRow.staleReason`, `WidgetQuotaStaleReason.planUsageUnavailable`, `WidgetQuotaRow.init(...staleReason:)`. Existing: `lastCheckedTime(_:now:calendar:locale:)`, `fableReadout(_:now:)`, the test helpers `overview(claude:codex:usage:today:)`, `column(_:_:)`, `shortText(_:includingDate:)`, `weekly(_:resetIn:)`, `fable(_:resetIn:)`.
- Produces:
  - `case planUsageUnavailable(WidgetQuotaHeadline, lastCheckedAt: Date)` on `public enum WidgetQuotaStatus`
  - `public let compactDetail: String?` on `WidgetQuotaColumn`, and an initializer parameter of that name after `detail`, defaulting to `nil`, so every existing column comparison compiles unchanged and now also asserts `nil`
  - in the view, `captionText(_:)` and `caption`

- [ ] **Step 1: Write the failing tests**

In `Tests/NeedlbarWidgetSupportTests/WidgetOverviewPresentationTests.swift`, replace

```swift
        #expect(nextReload(onTheHour) == referenceDate.addingTimeInterval(minute))
    }
}

```

with

```swift
        #expect(nextReload(onTheHour) == referenceDate.addingTimeInterval(minute))
    }

    // MARK: Plan usage unavailable

    @Test
    func planUsageUnavailableAsksToSignInWithTheLastCheckedTimeAndDims() throws {
        let age = 30 * minute
        let projection = try overview(claude: quota(
            .claude, age: age, stream: .stale, headline: weekly(77, resetIn: day), staleReason: .planUsageUnavailable
        ))
        let time = shortText(referenceDate.addingTimeInterval(-age), includingDate: false)
        #expect(column(.claude, projection) == WidgetQuotaColumn(
            title: "Claude",
            figure: "77%",
            fraction: 0.77,
            level: .normal,
            isDimmed: true,
            detail: "Sign in to Claude Code · \(time)",
            compactDetail: "Sign in to Claude Code",
            accessibilityLabel: "Claude, 77 percent remaining, not updating, sign in to Claude Code, last checked \(time)"
        ))
        #expect(WidgetPresentation.quotaStatus(projection.quotaRows[0], now: referenceDate)
            == .planUsageUnavailable(weekly(77, resetIn: day), lastCheckedAt: referenceDate.addingTimeInterval(-age)))
        #expect(column(.codex, projection).compactDetail == nil)
    }

    @Test
    func theSignInCaptionCarriesTheDateLikeLastChecked() throws {
        let checkedAt = referenceDate.addingTimeInterval(-9 * hour)
        let projection = try overview(claude: quota(
            .claude, age: 9 * hour, stream: .stale, headline: weekly(77, resetIn: day), staleReason: .planUsageUnavailable
        ))
        let expected = shortText(checkedAt, includingDate: true)
        #expect(expected != shortText(checkedAt, includingDate: false))
        let value = column(.claude, projection)
        #expect(value.detail == "Sign in to Claude Code · \(expected)")
        #expect(value.compactDetail == "Sign in to Claude Code")
        // The time is spoken even when the shown caption drops it.
        #expect(value.accessibilityLabel.hasSuffix("last checked \(expected)"))
    }

    @Test
    func theSignInCaptionTakesPrecedenceOverAPassedReset() throws {
        let projection = try overview(claude: quota(
            .claude, age: hour, stream: .stale, headline: weekly(77, resetIn: -1), staleReason: .planUsageUnavailable
        ))
        let value = column(.claude, projection)
        #expect(value.isDimmed)
        #expect(value.detail.hasPrefix("Sign in to Claude Code · "))
        #expect(value.compactDetail == "Sign in to Claude Code")
    }

    @Test
    func theFableTextKeepsItsOwnRulesBesideTheSignInCaption() throws {
        let age = 30 * minute
        let time = shortText(referenceDate.addingTimeInterval(-age), includingDate: false)
        let projection = try overview(claude: quota(
            .claude, age: age, stream: .stale, headline: weekly(77, resetIn: day),
            fable: fable(71, resetIn: day), staleReason: .planUsageUnavailable
        ))
        let value = column(.claude, projection)
        #expect(value.fable == WidgetFableText(text: "Fable 71%", level: .normal))
        #expect(value.accessibilityLabel
            == "Claude, 77 percent remaining, not updating, sign in to Claude Code, last checked \(time), Fable 71 percent remaining")
        let passed = try overview(claude: quota(
            .claude, age: age, stream: .stale, headline: weekly(77, resetIn: day),
            fable: fable(71, resetIn: -minute), staleReason: .planUsageUnavailable
        ))
        #expect(column(.claude, passed).fable == WidgetFableText(text: "Fable —", level: nil))
    }

    @Test
    func noOtherColumnHasACompactCaptionAndTheCopyStaysFactual() throws {
        let fresh = try overview(claude: quota(.claude, age: minute, headline: weekly(77, resetIn: day)))
        let stale = try overview(claude: quota(.claude, age: hour, stream: .stale, headline: weekly(77, resetIn: day)))
        let awaitingReset = try overview(claude: quota(.claude, age: minute, headline: weekly(77, resetIn: -1)))
        for projection in [fresh, stale, awaitingReset] {
            #expect(column(.claude, projection).compactDetail == nil)
        }
        #expect(column(.claude, nil).compactDetail == nil)

        let signIn = column(.claude, try overview(claude: quota(
            .claude, age: hour, stream: .stale, headline: weekly(77, resetIn: day), staleReason: .planUsageUnavailable
        )))
        let text = "\(signIn.detail) \(signIn.compactDetail ?? "") \(signIn.accessibilityLabel)"
        for forbidden in ["token", "signed out", "automatically"] {
            #expect(!text.localizedCaseInsensitiveContains(forbidden), "\(forbidden)")
        }
    }
}

```

Then, in the same file, replace

```swift
    stream: WidgetStreamState = .fresh,
    headline: WidgetQuotaHeadline?,
    fable: WidgetFableReading? = nil
) throws -> WidgetQuotaRow {
    try WidgetQuotaRow(
```

with

```swift
    stream: WidgetStreamState = .fresh,
    headline: WidgetQuotaHeadline?,
    fable: WidgetFableReading? = nil,
    staleReason: WidgetQuotaStaleReason? = nil
) throws -> WidgetQuotaRow {
    try WidgetQuotaRow(
```

Then, in the same file, replace

```swift
        lastSuccessfulAt: referenceDate.addingTimeInterval(-age),
        headline: headline,
        fable: fable
    )
}
```

with

```swift
        lastSuccessfulAt: referenceDate.addingTimeInterval(-age),
        headline: headline,
        fable: fable,
        staleReason: staleReason
    )
}
```

What the tests cover from spec §5, §6 and §8: the caption with the time, the compact fallback, dimming, the date on an earlier day, precedence over a passed reset, the Fable text and its spoken suffix beside it, no compact caption anywhere else, and no forbidden word.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make swift-test SWIFT_TEST_FILTER=NeedlbarWidgetSupportTests`

Expected: the build fails with `error: extra argument 'compactDetail' in call`, `type 'WidgetQuotaStatus' has no member 'planUsageUnavailable'` and `value of type 'WidgetQuotaColumn' has no member 'compactDetail'`, and make ends with `make: *** [swift-test] Error 1`.

- [ ] **Step 3: Write the presentation**

In `Sources/NeedlbarWidgetSupport/WidgetPresentation.swift`, replace

```swift
    case fresh(WidgetQuotaHeadline)
    case stale(WidgetQuotaHeadline, lastCheckedAt: Date)
    case awaitingFreshReading(WidgetQuotaHeadline)
    case unavailable
```

with

```swift
    case fresh(WidgetQuotaHeadline)
    case stale(WidgetQuotaHeadline, lastCheckedAt: Date)
    /// Claude Code stopped reporting plan usage after this reading.
    case planUsageUnavailable(WidgetQuotaHeadline, lastCheckedAt: Date)
    case awaitingFreshReading(WidgetQuotaHeadline)
    case unavailable
```

Then, in the same file, replace

```swift
    public let isDimmed: Bool
    public let detail: String
    /// `nil` hides the text: no Fable value, or the column shows no figure.
    public let fable: WidgetFableText?
```

with

```swift
    public let isDimmed: Bool
    public let detail: String
    /// A shorter caption for when `detail` does not fit at full size. `nil` when the
    /// caption has no shorter form.
    public let compactDetail: String?
    /// `nil` hides the text: no Fable value, or the column shows no figure.
    public let fable: WidgetFableText?
```

Then, in the same file, replace

```swift
        isDimmed: Bool,
        detail: String,
        fable: WidgetFableText? = nil,
        accessibilityLabel: String
```

with

```swift
        isDimmed: Bool,
        detail: String,
        compactDetail: String? = nil,
        fable: WidgetFableText? = nil,
        accessibilityLabel: String
```

Then, in the same file, replace

```swift
        self.isDimmed = isDimmed
        self.detail = detail
        self.fable = fable
        self.accessibilityLabel = accessibilityLabel
```

with

```swift
        self.isDimmed = isDimmed
        self.detail = detail
        self.compactDetail = compactDetail
        self.fable = fable
        self.accessibilityLabel = accessibilityLabel
```

Then, in the same file, replace

```swift
        let state = freshness(row, now: now)
        guard state != .unavailable else { return .unavailable }
        if let reset = headline.resetsAt, reset <= now {
            return .awaitingFreshReading(headline)
```

with

```swift
        let state = freshness(row, now: now)
        guard state != .unavailable else { return .unavailable }
        // Before the reset check: after a passed reset this reading still cannot update.
        if row.staleReason == .planUsageUnavailable {
            return .planUsageUnavailable(headline, lastCheckedAt: checkedAt)
        }
        if let reset = headline.resetsAt, reset <= now {
            return .awaitingFreshReading(headline)
```

Then, in the same file, replace

```swift
        let detail: String
        let spokenDetail: String
        var isDimmed = false
        switch quotaStatus(row, now: now) {
```

with

```swift
        let detail: String
        let spokenDetail: String
        var compactDetail: String?
        var isDimmed = false
        switch quotaStatus(row, now: now) {
```

Then, in the same file, replace

```swift
            detail = "Last checked \(time)"
            spokenDetail = "last checked \(time)"
        case .awaitingFreshReading(let value):
            headline = value
```

with

```swift
            detail = "Last checked \(time)"
            spokenDetail = "last checked \(time)"
        case .planUsageUnavailable(let value, let checkedAt):
            headline = value
            isDimmed = true
            let time = lastCheckedTime(checkedAt, now: now, calendar: calendar, locale: locale)
            detail = "Sign in to Claude Code · \(time)"
            compactDetail = "Sign in to Claude Code"
            spokenDetail = "not updating, sign in to Claude Code, last checked \(time)"
        case .awaitingFreshReading(let value):
            headline = value
```

Then, in the same file, replace

```swift
            isDimmed: isDimmed,
            detail: detail,
            fable: fable?.text,
            accessibilityLabel: "\(title), \(percent) percent remaining, \(spokenDetail)"
```

with

```swift
            isDimmed: isDimmed,
            detail: detail,
            compactDetail: compactDetail,
            fable: fable?.text,
            accessibilityLabel: "\(title), \(percent) percent remaining, \(spokenDetail)"
```

`nextDeadline` is unchanged: its countdown steps come only from `.fresh` columns, and a row with the reason is never fresh.

- [ ] **Step 4: Lay the caption out**

In `WidgetExtension/NeedlbarOverviewWidget.swift`, replace

```swift
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
```

with

```swift
    }

    private func captionText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    // The full caption at full size when it fits, otherwise the shorter one, which may
    // scale down like any other caption. The spoken label always keeps the full form.
    @ViewBuilder
    private var caption: some View {
        if let compact = column.compactDetail {
            ViewThatFits(in: .horizontal) {
                captionText(column.detail)
                captionText(compact)
                    .minimumScaleFactor(0.8)
            }
        } else {
            captionText(column.detail)
                .minimumScaleFactor(0.8)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
```

Then, in the same file, replace

```swift
            QuotaBar(fraction: column.fraction, fill: warning ?? accent)
                .opacity(column.isDimmed ? 0.45 : 1)
            Text(column.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
```

with

```swift
            QuotaBar(fraction: column.fraction, fill: warning ?? accent)
                .opacity(column.isDimmed ? 0.45 : 1)
            caption
        }
        .frame(maxWidth: .infinity, alignment: .leading)
```

The column stays one accessibility element, so VoiceOver reads `accessibilityLabel`, which always carries the time.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `make swift-test SWIFT_TEST_FILTER=NeedlbarWidgetSupportTests`

Expected: `Test run with 61 tests in 2 suites passed` (56 after Task 6 and 5 new), and make exits 0.

- [ ] **Step 6: Compile the widget for real and run the guard**

Run:

```bash
mkdir -p .build
./scripts/build-widget-extension.sh > .build/widget-build.log 2>&1; echo "build exit $?"
/usr/bin/grep -ci warning .build/widget-build.log
tail -1 .build/widget-build.log
/usr/bin/grep -rnE 'NeedlbarCore|CNeedlbar|Rust|Keychain|URLSession|AcceptanceFixture' Sources/NeedlbarWidgetSupport WidgetExtension/NeedlbarOverviewWidget.swift; echo "grep exit $?"
bash -c 'command -v rg' || { echo "no rg on PATH: the search guard cannot run; stop and ask"; exit 1; }
make widget-extension-test
```

Expected: `build exit 0`, `0`, `widget extension built with synthetic App Group identity`; no matches and `grep exit 1`; then `widget-extension search-guard regression passed` and `widget-extension build/metadata contract passed`, and make exits 0. Without `rg` the target prints `search-guard regression passed` and then fails; that line tests the guard with fake `rg` and is not the scan. In that case report: guard not run locally, `/usr/bin/grep` scan clean, CI runs the guard. `.build/` is git-ignored, and nothing is installed or launched.

- [ ] **Step 7: Commit**

```bash
git add Sources/NeedlbarWidgetSupport/WidgetPresentation.swift \
  WidgetExtension/NeedlbarOverviewWidget.swift \
  Tests/NeedlbarWidgetSupportTests/WidgetOverviewPresentationTests.swift
git commit -m "feat(widget): ask to sign in to Claude Code when plan usage stops" \
  -m "A Claude row with the stale reason dims its figure and bar and says Sign in to Claude Code with the last checked time, ahead of Last checked and Awaiting fresh reading. A ViewThatFits falls back to the short caption, and VoiceOver always speaks the time. The Fable text keeps its own rules." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Documentation and records

**Files:**
- Modify: `README.md:238-241` (appended to the end of the "Claude quota from the Claude Code usage report" section)
- Modify: `docs/providers/claude.md:78-81,99-100` (a table row and a dated section at the end)
- Modify: `docs/privacy.md:115-120`
- Modify: `docs/HANDOFF.md:195-198` (a paragraph after the Fable paragraph)
- Modify: `docs/STATUS.md:1-4` (a new entry at the top)

**Interfaces:**
- Consumes: the behaviour as built in Tasks 1 to 8.
- Produces: documents only.

- [ ] **Step 1: Update `README.md`**

In `README.md`, replace

```markdown
[Claude Code and Anthropic's terms](#claude-code-and-anthropics-terms).

### Usage and quota monitoring

```

with

```markdown
[Claude Code and Anthropic's terms](#claude-code-and-anthropics-terms).

When `/usage` finishes without plan usage, which Claude Code does when it does not consider itself
signed in with a Claude plan (signed out, an API key, usage-based billing), the app shows **Claude
Code didn't report plan usage** with "Claude Code usually shows plan usage only when it's signed in
with a Claude plan. Run claude auth login in Terminal, then choose Check now in Needlbar. API keys
and usage-billed accounts have no plan limits to show." (prepared 2026-11-20, not released). Until
then such a run read as a changed format and was retried under backoff, while the widget kept the
last value with only its last checked time. Needlbar tells the two apart only when the run named
the `usage` command and returned no `usage_report` key at all; any other missing report still reads
as a changed format. This state is not retried under backoff, like a missing Claude Code: the next
automatic run or **Check now** tries again. After an earlier reading, the Overview widget dims the
Claude figure and says "Sign in to Claude Code" with the last checked time. Needlbar still never
runs `claude auth` and offers no sign-in button.

### Usage and quota monitoring

```

- [ ] **Step 2: Update `docs/providers/claude.md`**

In `docs/providers/claude.md`, replace

```markdown
| Rate limited | **Temporarily limited** and the last checked time | Last known | Backoff |
| No readable report | **Could not read Claude Code's usage report** and the last checked time | Last known | Backoff |

The run after 15 minutes counts as a trigger, so the first state is tried again about every
```

with

```markdown
| Rate limited | **Temporarily limited** and the last checked time | Last known | Backoff |
| No readable report | **Could not read Claude Code's usage report** and the last checked time | Last known | Backoff |
| Plan usage not reported (since 2026-11-20) | **Claude Code didn't report plan usage**, and "Claude Code usually shows plan usage only when it's signed in with a Claude plan. Run claude auth login in Terminal, then choose Check now in Needlbar. API keys and usage-billed accounts have no plan limits to show."; no sign-in button. The widget says "Sign in to Claude Code" with the last checked time | Last known or none | Next trigger, with backoff, as for Claude Code not found |

The run after 15 minutes counts as a trigger, so the first state is tried again about every
```

Then, in the same file, replace

```markdown

Needlbar does not own Claude credentials and therefore does not provide a Claude Disconnect button. Sign out or revoke the provider session through Claude's supported controls; Needlbar will then show the no-usage state on the next run.
```

with

```markdown

Needlbar does not own Claude credentials and therefore does not provide a Claude Disconnect button. Sign out or revoke the provider session through Claude's supported controls; Needlbar will then show the no-usage state on the next run.

### Plan usage not reported (2026-11-20, prepared, not released)

A signed-out `claude` was observed on 2026-11-19: `/usage` exited 0 with `result` `subtype:
"success"`, an assistant line with `local_command_run: {"command": "usage"}`, the session cost text
and no `usage_report` key. A static read of Claude Code 2.1.325 and 2.1.328 shows the same branch
whenever Claude Code does not consider itself signed in with a Claude plan: signed out, an API key,
usage-based billing, or a token without the profile scope. This replaces three statements above:
a signed-out run is no longer unobserved, such runs no longer show the no-readable-report state,
and signing out now shows this state rather than the no-usage state.

Needlbar shows this state only when no assistant line has a non-null `usage_report`, none reports a
rate limit, at least one has a `local_command_run` whose `command` is `usage`, and none has a
`usage_report` key at all, not even `null`. Another command name, a `null` report, a malformed
report or no assistant line still reads as a changed format. The bridge code is
`requiresAuthentication` and the diagnostics origin `usageReportPlanUsageUnavailable`. With no
earlier reading the quota status is authentication required; after one it is an error with the
last-known values, as for a changed format. Claude still has no sign-in button, and the menu bar is
unchanged. While status-line windows are recent, the reason sits once on the Fable line, which only
`/usage` fills. There is no backoff retry, and the backoff time is still recorded, so repeated
failures can push the periodic run out to 20 or 30 minutes. **Check now** runs once and the same
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
```

- [ ] **Step 3: Update `docs/privacy.md`**

In `docs/privacy.md`, replace

```markdown
  `/usage` through the user's installed `claude`, with a fixed command, no shell, one fixed working
  folder in the temporary directory that is emptied before each run, a minimal environment and a 60-second limit (30 seconds before 2026-11-12). Any network use, login renewal, Keychain
  prompt or transcript reading during that run belongs to `claude`. Needlbar reads only the `usage_report` field and an
  error label, and discards the rest without logging or storing it. It reads no Claude Keychain item
  or credential file. v0.3.14 still uses the Anthropic usage endpoint with existing local evidence.
  Needlbar does not bundle or modify Claude Code and has no Claude sign-in; how this relates to
```

with

```markdown
  `/usage` through the user's installed `claude`, with a fixed command, no shell, one fixed working
  folder in the temporary directory that is emptied before each run, a minimal environment and a 60-second limit (30 seconds before 2026-11-12). Any network use, login renewal, Keychain
  prompt or transcript reading during that run belongs to `claude`. Needlbar reads only the `usage_report` field, an
  error label and, since 2026-11-20, whether `local_command_run` names the `usage` command, which
  tells a run without plan usage from a changed format and is compared, never kept. It discards the rest without logging or storing it. It reads no Claude Keychain item
  or credential file. v0.3.14 still uses the Anthropic usage endpoint with existing local evidence.
  Needlbar does not bundle or modify Claude Code and has no Claude sign-in; how this relates to
```

- [ ] **Step 4: Update `docs/HANDOFF.md`**

In `docs/HANDOFF.md`, replace

```markdown
rename removes the text without notice.

A local ad-hoc build ran for about 38 hours on the maintainer's Mac (STATUS, 2026-11-05): every
logged run succeeded, no Keychain prompt appeared, and runs took about 5 s (maximum about 19.3 s).
```

with

```markdown
rename removes the text without notice.

**Plan usage unavailable (2026-11-20, prepared, not released).** Design:
`docs/superpowers/specs/2026-11-20-claude-plan-usage-unavailable-design.md`. Plan:
`docs/superpowers/plans/2026-11-20-claude-plan-usage-unavailable.md`. This answers the open check of
how a signed-out `claude` reports itself (STATUS, 2026-11-20): `/usage` exits 0 with
`local_command_run` naming `usage` and no `usage_report` key. The parser returns
`PlanUsageUnavailable` for exactly that shape; the provider sends `requiresAuthentication` with the
origin `usageReportPlanUsageUnavailable`; Swift maps the code to
`ClaudeQuotaFailureReason.planUsageUnavailable` (`authenticationExpired` stays
`quotaAccessUnavailable`). The app shows "Claude Code didn't report plan usage" and its detail, on
the Fable line while status-line windows are recent. `RefreshCoordinator` does not retry it under
backoff, as for `notInstalled`; a thrown bridge failure with either code now also waits (no
production path throws one). The widget row carries
`staleReason` only after an earlier reading and only while not fresh, and the column says "Sign in to
Claude Code · <time>" with a shorter fallback. Not yet seen on an installed widget: the caption in
light and dark and its fallback when narrow; after installing, restart the old widget process, which
ignores the new key.

A local ad-hoc build ran for about 38 hours on the maintainer's Mac (STATUS, 2026-11-05): every
logged run succeeded, no Keychain prompt appeared, and runs took about 5 s (maximum about 19.3 s).
```

- [ ] **Step 5: Add the STATUS entry**

In `docs/STATUS.md`, replace

```markdown
# Needlbar Development Status

## 2026-11-15 Terms question decided: stated reading plus inquiry (prepared, not released)

```

with

```markdown
# Needlbar Development Status

## 2026-11-20 Claude plan usage unavailable state (prepared, not released)

- **Observed.** On 2026-11-19 the terminal `claude` on the maintainer's Mac became signed out.
  Every `/usage` run then exited 0 with the session cost summary and no `usage_report`; Needlbar
  showed a changed format, retried under backoff, and the widget kept the last value with only its
  last checked time for about a day. After `claude auth login` the next **Check now** succeeded.
- **Change.** A run that names the `usage` command and returns no `usage_report` key is its own
  state: "Claude Code didn't report plan usage", with a line naming `claude auth login` in Terminal
  and **Check now**. Bridge code `requiresAuthentication`, origin `usageReportPlanUsageUnavailable`.
  No backoff retry; the periodic run and **Check now** try again. The widget's Claude column dims and
  says "Sign in to Claude Code" with the last checked time. Design:
  `docs/superpowers/specs/2026-11-20-claude-plan-usage-unavailable-design.md`; plan:
  `docs/superpowers/plans/2026-11-20-claude-plan-usage-unavailable.md`.
- **Fixture.** `Fixtures/quota/claude/usage-report-signed-out.jsonl` keeps only the assistant line
  and the result line of the 2026-11-20 output, with every identifier removed and numbers zeroed.
- **Not checked.** The widget caption on an installed build in light and dark and its fallback when
  narrow; the output of an API-key or usage-billed account. Nothing was tagged or released.

## 2026-11-15 Terms question decided: stated reading plus inquiry (prepared, not released)

```

- [ ] **Step 6: Check the documentation contracts**

Run:

```bash
git diff -U0 -- README.md | /usr/bin/grep '^+' | /usr/bin/grep -c -e '0\.3\.14' -e '0\.3\.15'
git diff -- docs/STATUS.md | /usr/bin/grep '^+' | /usr/bin/grep -c -e 'releases/tag/' -e 'report 0\.3\.'
bash scripts/tests/notarize-app-tests.sh 2>&1 | tail -n 1
```

Expected: `0`, `0`, then `notarize-app shell contracts passed`.

- [ ] **Step 7: Commit**

```bash
git add README.md docs/providers/claude.md docs/privacy.md docs/HANDOFF.md docs/STATUS.md
git commit -m "docs: record the plan usage unavailable state" \
  -m "README, the Claude provider doc, privacy, HANDOFF and a STATUS entry describe the state as prepared, not released. New text is appended where the open automatic-checks work also edits." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Verification

**Files:** none changed.

**Interfaces:** consumes the branch after Task 9; produces logs only.

Steps 1 to 3 except `make smoke` were run on the scratch tree while writing this plan (Decisions 5).

- [ ] **Step 1: Run the full project gate**

Run:

```bash
bash -c 'command -v rg' || { echo "no rg on PATH: the search guard cannot run; stop and ask"; exit 1; }
make test > "${TMPDIR:-/tmp}/needlbar-make-test.log" 2>&1; echo "make exit $?"
tail -n 1 "${TMPDIR:-/tmp}/needlbar-make-test.log"
/usr/bin/grep -c '✘' "${TMPDIR:-/tmp}/needlbar-make-test.log"
```

Expected: a path to `rg`; `make exit 0`; the last line `notarize-app shell contracts passed`; a count of `0`. The run takes well over ten minutes; give it a timeout of at least thirty. It includes `cargo test --workspace --features bridge-test-runtime`, the vendored-crate test, the bridge archive check, the whole Swift suite, `widget-extension-test`, `package-test` and `notarize-test`.

- [ ] **Step 2: Run the acceptance build's tests**

Run:

```bash
make acceptance-test > "${TMPDIR:-/tmp}/needlbar-acceptance.log" 2>&1; echo "acceptance exit $?"
/usr/bin/grep -E 'Test run with' "${TMPDIR:-/tmp}/needlbar-acceptance.log"
```

Expected: `acceptance exit 0` and a passing `Test run with … tests` line for `AcceptanceFixtureTests`. This plan changes no acceptance fixture; the run shows the new optional fields did not break the acceptance build.

- [ ] **Step 3: Package and smoke**

Run:

```bash
make package > "${TMPDIR:-/tmp}/needlbar-package.log" 2>&1; echo "package exit $?"
/usr/bin/grep -n 'NEEDLBAR_DISABLE_CLAUDE_USAGE_PROBE=1' scripts/smoke-app.sh
make smoke > "${TMPDIR:-/tmp}/needlbar-smoke.log" 2>&1; echo "smoke exit $?"
pgrep -f -- '-p /usage --no-session-persistence'; echo "pgrep exit $?"
```

Expected: `package exit 0` (an ad-hoc signed `dist/Needlbar.app` and its zip); the `grep` prints line 199, which starts the packaged executable with the probe disabled, so no `claude` run starts; `smoke exit 0`; `pgrep exit 1` (no `/usage` run exists). Do not open `dist/Needlbar.app` any other way, and do not copy it anywhere.

- [ ] **Step 4: Confirm the tree**

Run: `git status --short`

Expected: only `?? .superpowers/brainstorm/` (and `dist/` only if it is not ignored; it is listed in `.gitignore`).

### Where the plan stops

After Task 10 the branch `claude/claude-plan-usage-unavailable` holds nine new local commits on top of the spec commit and is ready for review. Implementers stop here. Pushing and opening a pull request is the main session's step, at the user's request; see Decisions 4 for the one-line follow-up after #55 merges. Merge, a tagless Developer ID build, installation, tag and release each need the user's separate request.

### Manual check (USER-RUN, after a build and an installation, not for implementers)

Spec §8 lists what only the installed widget can show. It applies once the user has separately asked for a build and its installation.

- [ ] After installing, stop the old `NeedlbarWidgetExtension` process by its process ID and confirm the new one maps the installed executable; an old process ignores `staleReason` (spec §10).
- [ ] With `claude` signed out and an earlier reading since launch, the Claude column shows the dimmed figure and "Sign in to Claude Code · <time>" in light and in dark appearance.
- [ ] When the full caption does not fit (for example with a date), the column shows "Sign in to Claude Code" without truncation.
- [ ] VoiceOver reads the Claude column as one element with "not updating, sign in to Claude Code, last checked <time>".
- [ ] After `claude auth login` in Terminal and **Check now**, the reason and the caption clear.

---

## Self-Review

**1. Spec coverage**

| Spec | Requirement | Where |
|---|---|---|
| §2 | New state, distinct from a changed format | Tasks 1 to 3 |
| §2 | Shown on the widget with the last-checked time | Tasks 6 to 8 |
| §2 | No backoff retry; periodic run and Check now | Task 4 |
| §2 | No sign-in by Needlbar; copy names the Terminal command | Task 3 copy; Task 5 (`authenticationAction`, `requiresProviderSignIn`); no task adds a button or runs `claude auth` |
| §3 | The four conditions and the order | Task 1 Step 3; Step 1 tests; mutation check in Decisions 5 |
| §3 | Stays `FormatChanged`: another command, `null`, malformed, no assistant lines | Task 1 `anything_short_of_that_shape_stays_format_changed` |
| §3 | Field deserializer; untyped `local_command_run`; compared, never kept | Task 1 (`present`, `Option<Value>`, the canary test) |
| §3 | Privacy note at the top of the parser | Task 1 Step 3, first block |
| §4 Rust | `RequiresAuthentication`, origin, serialization test | Task 2 |
| §4 Bridge | No new code string | Decisions 1; no bridge source change |
| §4 Swift | Reason, mapping, `authenticationExpired` unchanged, comment removed, origin decoder | Task 3 |
| §4 Status | `requiresAuthentication` without, `.error` after an earlier success | Task 4 (`planUsageUnavailableWaits…`, `afterAnEarlierSuccess…`); Task 7 (stale stream) |
| §4 Retry | The expression, every path, backoff still recorded, Check now | Task 4; Decisions 2 |
| §5 | Row reason and detail | Task 3 copy and test; Task 5 surfaces |
| §5 | Widget caption with `lastCheckedTime`, date included | Task 8 (`…WithTheLastCheckedTimeAndDims`, `…CarriesTheDateLikeLastChecked`) |
| §5 | `compactDetail` and `ViewThatFits` with 0.8 | Task 8 Steps 3 and 4 |
| §5 | VoiceOver with the time and the Fable part | Task 8 (`…AndDims`, `theFableTextKeepsItsOwnRules…`) |
| §5 | No token, no automatic sign-in, no "signed out" | Task 5 `noCopyOffersAnAutomaticSignIn`; Task 8 `noOtherColumn…AndTheCopyStaysFactual` |
| §6 Field | `staleReason`, one case, schema 1, both decoders as `String?`, unknown is `nil` | Task 6 |
| §6 Validation | Claude only, last successful time, headline, not fresh, in initializers and validation | Task 6 (`isValid`, both rejection tests) |
| §6 Mapper | Only for `planUsageUnavailable`, never throws, capture gains the reason, clears and replaces | Task 7 |
| §6 Presentation | Precedence, dimming, Fable unchanged | Task 8 |
| §6 Status line | Set even when a status-line reading is fresher | Task 7 `aFresherStatusLineReadingDoesNotClearIt` |
| §7 | Dashboard row, popover, Settings | Task 5 |
| §7 | `reasonSitsOnTheFableLine` gains the reason | Task 5 Step 3 |
| §7 | Check now runs once, same reason; menu bar unchanged | Task 4 `checkNowStillRuns…`; Task 5 (`allReasons`); no menu bar file changes |
| §8 Rust | Fixture and the five other shapes; provider code and origin; bridge list | Tasks 1 and 2 |
| §8 Swift | Mapping, origin decoding, reporter pairs, copy, auth action, retry in a new file | Tasks 3, 4 and 5 |
| §8 Widget | Round trip, old file, `null`, unknown, invalid combinations, mapper set and clear, caption, fallback, dimming, VoiceOver | Tasks 6, 7 and 8 |
| §8 | Not automated, checked by the user | Manual check (USER-RUN) |
| §9 | README, Claude provider doc, privacy, HANDOFF, STATUS marked prepared, appended where #55 edits | Task 9; Decisions 4 |
| §10 | Three tables updated | Task 3 Step 1 |
| §10 | Widget process restart; search guard; no reason without a success since launch | Manual check; Task 8 Step 6; Task 7 `theReasonIsLeftOut…`; Task 9 claude.md section |

No gap found. Decisions 6 lists where the spec is silent and what the plan does there.

**2. Placeholder scan:** every code and document step shows the full text to replace and to add, extracted from the scratch commits; every command has its expected result. No step says "TBD", "similar to" or "add tests for".

**3. Name consistency:** `ClaudeUsageReportOutcome::PlanUsageUnavailable` (Task 1) is matched in Task 2. `ClaudeQuotaFailureOrigin::UsageReportPlanUsageUnavailable` (Rust, Task 2) serializes as `usageReportPlanUsageUnavailable`, the Swift case of the same name (Task 3). `ClaudeQuotaFailureReason.planUsageUnavailable` (Task 3) is used in Tasks 4, 5 and 7. `WidgetQuotaStaleReason.planUsageUnavailable`, `isValid(for:stream:lastSuccessfulAt:headline:)` and `WidgetQuotaRow.staleReason` (Task 6) are used in Tasks 7 and 8. `WidgetProviderCapture.claudeQuotaFailureReason` (Task 7) is set only by `captureForWidget`. `WidgetQuotaStatus.planUsageUnavailable(_:lastCheckedAt:)` and `WidgetQuotaColumn.compactDetail` (Task 8) are used by the view in the same task. The test doubles in Task 4 are all prefixed `Retry`. Test counts: Rust parser 13 to 18 (Task 1), provider 10 to 11 (Task 2); support target 52 to 56 (Task 6) to 61 (Task 8); core `WidgetProjectionTests` 17 unchanged plus 6 new (Task 7); the retry suite 5 (Task 4).
