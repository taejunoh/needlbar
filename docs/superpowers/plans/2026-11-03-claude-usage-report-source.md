# Claude Usage Report Quota Source Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Needlbar's Claude Keychain read, credential-file read and direct usage endpoint with `/usage` run by the user's installed `claude`, keeping the status line and last-known values as fallbacks.

**Architecture:** Three new units in `crates/needlbar-quota` (CLI locator, usage probe, report parser) compose into a provider exposed through two new C exports; a pure schedule value inside `RefreshCoordinator` decides when a run starts, on its own slot beside the Codex and Cursor refresh. Claude leaves the all-provider refresh only after the new source works, and every old Claude path is removed after that, so each task leaves the build and tests green.

**Tech Stack:** Rust 2021 (tokio process, serde_json, tempfile, libc), Swift 6 / Swift Testing, C ABI through `Sources/CNeedlbar`, macOS 14+ arm64.

> **Amendment — 2026-11-03 (whole-branch review):** a null `rate_limits` or null or empty
> `limits` maps to `ProviderUnavailable` with the origin `usageReportNoUsage` and retries under
> backoff, not to `RequiresAuthentication`. The `.claudeCodeSignInRequired` reason, its copy and
> its code blocks in Tasks 3, 6 and 8 below are superseded: `.claudeCodeCheckFailed` carries the
> detail "If this continues, run claude in Terminal to check its sign-in." The decision table in
> Decisions 6 and Task 14 Step 5 are updated; other code blocks are kept as the record of what
> was first written.
>
> **Amendment — 2026-11-03 (whole-branch review):** the probe's working directory is one fixed
> folder, `<TMPDIR>/needlbar-claude-usage`, not a `tempfile` directory per run, because the CLI keeps
> records per working directory. Task 2's `tempfile::Builder` block and its "fresh directory it
> deletes" test are superseded: the folder is created with mode 0700, refused if a symlink or not a
> directory, and emptied before each run, and tests assert the same directory and an empty start.
> `tempfile` stays a dev-dependency only.

## Global Constraints

Authoritative spec: `docs/superpowers/specs/2026-11-03-claude-usage-report-source-design.md`. These apply to every task.

- Approval covers this plan only. Implementation, merge, installation, tag and release each need the user's separate request.
- Implementers never read, list or delete Keychain items; never read browser cookies or credential files; never run `claude`, `claude auth`, or anything that can change login state; never launch, kill or reinstall the app; never run `make smoke`, which launches the app; never push, merge, tag or start a release. Steps that need real credentials are marked **USER-RUN** and implementers do not run them.
- Tests never spawn the real `claude`. Rust tests inject a fake executable through `ClaudeCliLocator::with_candidates`. Never call `needlbar_claude_usage_report_quota_snapshot_json` from a test built without `bridge-test-runtime`, because CI also runs `cargo test --workspace` (`.github/workflows/ci.yml:46`).
- CLI locations, in order: `~/.local/bin/claude`, `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`. First executable regular file after resolving symlinks. No shell and no `PATH` search.
- Fixed argv, no user-derived text: `-p /usage --no-session-persistence --strict-mcp-config --settings {"disableAllHooks":true} --output-format stream-json --verbose`.
- Process limits: one fixed working directory `<TMPDIR>/needlbar-claude-usage` (amended 2026-11-03: was a new temporary directory per run), created with mode 0700, refused if a symlink or not a directory, emptied before each run; `stdin` closed (`Stdio::null()`, immediate EOF); environment exactly `HOME`, `USER`, `LOGNAME`, `TMPDIR`, a fixed `PATH`, and `CLAUDE_CONFIG_DIR` only if the app already has it; 30-second deadline, then terminate the process group; 1 MiB of stdout, then terminate; stderr drained and discarded; cancelled on app stop; results from an older generation ignored.
- Triggers: app start, manual refresh, a change in Claude Code's local usage records, passing the `resets_at` of a displayed window, and 15 minutes since the last run started (`.periodic`, last in priority; user decision, 2026-11-03). Automatic runs at most once every 5 minutes, one at a time. Manual skips the interval and backoff but joins a run in flight. Opening the dashboard alone does not start a run, and neither does waking the Mac or regaining a connection.
- Freshness: a usage report reading is current for 20 minutes (`recentDirectInterval`, and the widget's Claude quota row), so the label does not flip before each periodic refresh. A failed run shows Last known at once. `recentStatusLineInterval` and `maximumStatusLineAge` do not change.
- Backoff after consecutive automatic failures: 5, 10, 20, then 30 minutes. Any success resets it.
- Parsing: read only `usage_report` (see Spec Deviation 1). Classify on `kind`. `session` is the five-hour window, `weekly_all` the seven-day window, `weekly_scoped` is Fable when `scope.model.display_name` equals `Fable` ignoring case. Every row is optional. Unknown kinds ignored, malformed rows skipped. `percent` is a used share; clamp finite values to 0-100, skip others. Null or missing `resets_at` shows no reset time. `rate_limits: null`, or `limits` null or empty, is no usage available. No `usage_report` at all is format changed.
- Window IDs and titles stay `claude.session`/`Session`, `claude.weekly`/`Weekly`, `claude.fable.weekly`/`Fable weekly`, so export, widget and alert contracts are unchanged.
- The UI never shows a made-up zero. No new credential or raw-output storage. Diagnostics record failure reason, duration and row kinds only; never tokens, output text or emails.
- Needlbar never runs `claude auth`, never opens a login flow and never writes Claude configuration. The signed-out state has no launch button.
- Codex, Cursor, local usage and API billing behave exactly as before.
- Keep macOS 14+, the pinned toolchain and `tokscale-core`. Do not add presentation logic to `needlbar-bridge`.
- Symbol names must not contain `diagnostic_probe` or `needlbar_test_` in shipped code: `scripts/verify-public-bridge-surface.sh:16` rejects any archive containing them.
- Docs say **prepared, not released**. Public availability stays v0.3.14. Mention `0.3.15` in `README.md` only inside the prepared section, because the historical fixtures at `scripts/tests/notarize-app-tests.sh:2253-2255` abort on any other occurrence. New `docs/STATUS.md` text repeats no run ID, asset ID, commit hash, `releases/tag/`, or `report 0.3.`, because the decoys at `scripts/tests/notarize-app-tests.sh:2209-2229` rewrite the first occurrence.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Commands assume the repository root and `export PATH="$HOME/.cargo/bin:$PATH" MACOSX_DEPLOYMENT_TARGET=14.0`.
- Line numbers in this plan are from commit `cb59f86`. Once earlier tasks shift a file, find the place by the quoted text.

---

## Decisions Settled From The Code

### 1. Where each unit goes

| Unit | Location | Why |
|---|---|---|
| CLI locator | `crates/needlbar-quota/src/providers/claude_cli.rs` | `AGENTS.md:50` assigns quota retrieval to Rust; `crates/needlbar-quota/src/lib.rs:1-2` keeps provider responses on the Rust side of the bridge |
| Usage probe | `crates/needlbar-quota/src/providers/claude_usage_probe.rs` | Direct precedent: Codex spawns its CLI for quota with `tokio::process` at `crates/needlbar-quota/src/providers/codex.rs:158-179`; the bridge thread's runtime already has `enable_all` (`crates/needlbar-bridge/src/lib.rs:561-563`) |
| Report parser | `crates/needlbar-quota/src/providers/claude_usage_report.rs` | Raw `claude` output then never crosses the C ABI, which the redaction contract (`crates/needlbar-bridge/tests/redaction_contract.rs:504`) can assert |
| Provider | `crates/needlbar-quota/src/providers/claude_usage_provider.rs` | Composes the three and maps to the closed `QuotaError` (`crates/needlbar-quota/src/domain.rs:106-120`) |
| Probe scheduler | `Sources/NeedlbarCore/Refresh/ClaudeUsageProbeSchedule.swift` plus `RefreshCoordinator` | The spec places it inside the coordinator; the decision logic is a pure value so it can be tested without a clock or process |

Today Claude travels `ClaudeQuotaProvider.fetch` (`crates/needlbar-quota/src/providers/claude.rs:152`), `collect_quota` (`crates/needlbar-bridge/src/quota.rs:53`), `needlbar_quota_snapshot_json` (`crates/needlbar-bridge/src/lib.rs:329`), `RustQuotaRepository.refreshAggregate` (`QuotaRepository.swift:62`), then `applyQuotaResult` and `store.applyQuota` (`RefreshCoordinator.swift:677,725`). Fable is a window with ID `claude.fable.weekly`, found by label at `claude.rs:187-219` and shown only from that source (`ClaudeQuotaPresentationSelector.swift:46,50`), because the status line has no Fable field. The new path keeps the same window, the same `ProviderQuotaSnapshot` JSON and the same store call, and changes only how the snapshot is produced and when.

Claude gets its own slot, not the quota slot. `tokio::join!` in `collect_quota_with_providers` (`crates/needlbar-bridge/src/quota.rs:144`) would hold Codex and Cursor for up to 30 s, and STATUS 2026-11-02 records that as a real stall. The synchronous `repository.refresh` at `RefreshCoordinator.swift:524` would also pin a cooperative thread, which `requestClaudeKeychainAccess` already avoided with a dispatch thread (`RefreshCoordinator.swift:316-320`); the new run reuses that shape.

**Sandbox, hardened runtime and spawn, verified:**

- `Resources/NeedlbarHostWidget.entitlements` holds only `com.apple.security.application-groups`, and `scripts/tests/package-app-tests.sh:175` fails the build if `com.apple.security.app-sandbox` appears. The host is not sandboxed, so a spawned `claude` inherits no sandbox and can reach `~/.claude`.
- Release signing applies `--options runtime` (`scripts/notarize-app.sh:134-136`). Hardened runtime restricts the signed process itself (library validation, unsigned memory, `DYLD_*`), not `posix_spawn` of another binary. No entitlement is needed. The child's own signature governs it.
- Precedents in the shipping binary: `crates/needlbar-quota/src/providers/codex.rs:158` and `Sources/Needlbar/Authentication/ProviderLoginCoordinator.swift:221-266`.
- Keychain identity: a prompt raised by the child is attributed to the child or the `security` tool it runs, not to Needlbar, which matches spec §12. This cannot be verified from code, so Task 14 records it in the user-run observation.
- Traps handled in this plan: `UsageFileWatcher.swift:175` opens directories without `O_CLOEXEC`, and Rust's `Command` does not set `POSIX_SPAWN_CLOEXEC_DEFAULT`, so `claude` would inherit those descriptors (Task 9 fixes this). A descendant holding the stdout pipe after `claude` exits must not stall the run (Task 2 stops reading after a grace period). TCC attributes the child to the responsible process, so a Files-and-Folders prompt would name Needlbar; the empty working directory makes one unlikely and Task 14 watches for it.

### 2. Detecting a change in Claude Code's local usage records

**Signal: the Claude total in the existing usage refresh**, compared in `RefreshCoordinator.finishUsageRefresh` (`RefreshCoordinator.swift:571-610`) as `refresh.snapshots[.claude]?.totalTokens`. No new watcher and no metadata read.

`requestUsageRefresh` (`RefreshCoordinator.swift:198`) and `UsageFileWatcher` cannot serve directly: the watcher's token (`UsageFileWatcher.swift:14-24`) carries no provider, it also fires for Codex and Cursor roots (`UsageFileWatcher.swift:121-127`), and `DirectoryFileEventSource` watches only the root directory descriptor (`UsageFileWatcher.swift:175-190`), so appending to `~/.claude/projects/<project>/<session>.jsonl` fires nothing. The usage refresh runs at least every 5 minutes (`RefreshCoordinator.swift:391-403`) and rescans everything, and `totalTokens` is Claude-only and ignores day rollover, unlike `today` or `last7Days`. Detection latency is therefore at most 5 minutes, which equals the automatic-run cap. The first observation after start only sets the baseline. `--no-session-persistence` means a run should not change the total; if it ever did, the cap bounds the effect, and Task 14 checks it.

### 3. How scheduled, wake and popover triggers change

| Path | Code | `.backgroundAll` (Codex, Cursor) | Claude run |
|---|---|---|---|
| Popover or dashboard open | `popoverOpened`, `RefreshCoordinator.swift:229-239`; `AppDelegate.swift:245-247` | Unchanged | **None** |
| 5-minute timer | `requestScheduledQuotaRefresh`, `:427-431` | Unchanged | **None by itself** |
| Wake, connectivity | `recoverQuota`, `:222-227`; `QuotaRecoveryMonitor.swift` | Unchanged | **None** |
| App start | `start`, `:175-196` | Unchanged | Starts a run |
| Manual refresh | `manualRefresh`, `:241-259` | Unchanged | Starts or joins |
| Usage total changed | `finishUsageRefresh`, `:588-602` | n/a | Automatic request, deferred while capped |
| A displayed `resets_at` passed | new 60-second tick | n/a | Automatic, evaluated by the tick |
| Retryable failure, backoff elapsed | new 60-second tick | n/a | Automatic, evaluated by the tick |
| 15 minutes since the last run started | new 60-second tick | n/a | Automatic, `.periodic`, last in priority, behind the interval and backoff |

Because Claude leaves `.backgroundAll`, popover and wake lose Claude without changing their code. The tick reads only actor state, does no I/O, and exists only when a Claude repository is injected, so existing clock-sleeper tests are unaffected.

**Sleep:** `Task.sleep` counts time asleep, so the first tick after a wake can find a periodic run overdue and start it within about a minute. That run is the tick's, logged `trigger=periodic`, not the wake handler's. The wake and popover tests hold the clock still with a run overdue, to prove their handlers start nothing, then let the tick start it.

**Clock set back:** a negative age never makes the periodic run due, so it waits until the clock catches up or another trigger starts a run, which re-anchors it. A manual refresh always does.

`QuotaRefreshTrigger` has one exhaustive `switch` in Sources or Tests: `backgroundRequestIsDue` at `RefreshCoordinator.swift:434-442`, updated in Task 6. `QuotaRecoveryRequestToken.submit` (`QuotaRefreshActivity.swift:59`) and `requestQuotaRefresh` (`RefreshCoordinator.swift:462-463`) compare with `==` and need no change.

Tests that assume otherwise: `Tests/NeedlbarCoreTests/ClaudeKeychainAccessTests.swift:258-301` (popover, wake and timer reach Claude through `.backgroundAll`), `ClaudeAccessExpiredReasonTests.swift` (drives Claude through `popoverOpened`), and `RefreshCoordinatorTests.swift:94-144` (`expiryPreservesDirectSuccess…`, second attempt through `popoverOpened`). `timerPopoverAndManualQuotaPathsAlwaysUseBackgroundAllIntent` stays as is, and it now asserts the new rule. Task 7 ports or deletes these by name.

### 3a. Freshness with a periodic run

A periodic refresh falls due 15:00 after the last start, waits up to 60 s for the tick, and can take the 30-second deadline plus 1 s of termination, so the slowest refresh finishes 16:31 after the last start. Anything that labels a reading after 15 minutes would flip just before each refresh.

| Place | Today | Change |
|---|---|---|
| `recentDirectInterval`, `ClaudeQuotaPresentationSelector.swift:33,88` | 15 minutes | 20 minutes (Task 8). Leaves 3:29 of margin |
| `WidgetPresentation.freshnessHorizon`, `WidgetPresentation.swift:10,20,50`; `NeedlbarOverviewWidget.swift:61-69,130` | 15 minutes for every row | Claude quota row 20 minutes (Task 8). Codex and usage rows keep 15, because they refresh every 5 minutes and must not change |
| `recentStatusLineInterval`, `maximumStatusLineAge`, `ClaudeQuotaPresentationSelector.swift:32,37` | 15 minutes, 24 hours | None |
| Alerts, `QuotaNotificationService.swift:357`, `QuotaAlertPolicy.swift:175` | Admit a reading under 15 minutes old | None. They are evaluated when `applyQuota` publishes a new reading (`ProviderSnapshotStore.swift:71-82`), when its age is about zero |
| Store status, `ProviderSnapshotStore.swift:301-304` | Does not age | None |

### 4. Removal inventory

| Item | Location | Removed in |
|---|---|---|
| Keychain resolver, file resolver, `ClaudeCredentialAccess`, `ClaudeOAuthSecret`, keychain lock and sequencing | `crates/needlbar-quota/src/providers/claude_credentials.rs` (whole file, 2176 lines) | Task 12 |
| Direct endpoint, OAuth beta header, `parse_usage_payload`, credential error mapping | `crates/needlbar-quota/src/providers/claude.rs` (whole file) | Task 12 |
| Credential re-exports and modules | `crates/needlbar-quota/src/lib.rs:13-17`, `providers/mod.rs:5-6` | Task 12 |
| `api.anthropic.com` host, `RedactingHttpClient::new`, `Default`, endpoint-status tagging | `crates/needlbar-quota/src/http.rs:5,8,28-30,165-169,188-197,210` | Task 12 |
| `ClaudeUsageEndpointStatus`, `claude_credential_busy`, old origins | `crates/needlbar-quota/src/domain.rs:79-102,116-119,139-154,174-187` | Task 12 |
| `security-framework`, `security-framework-sys`, `core-foundation`, `core-foundation-sys`, `zeroize` | `crates/needlbar-quota/Cargo.toml:15,17-21`, `Cargo.toml:24-28` (no other crate uses them directly; verified by search) | Task 12 |
| `needlbar_claude_user_initiated_…`, `needlbar_claude_preflight_…` exports | `crates/needlbar-bridge/src/lib.rs:335-364,392-398,529-541`; `Sources/CNeedlbar/include/needlbar.h:13-17`; `crates/needlbar-bridge/src/quota.rs:29-48,71-118` | Task 11 |
| Claude in the aggregate | `crates/needlbar-bridge/src/quota.rs:53-69,139-146` | Task 9 |
| `Allow Keychain access` button, copy, tests | `ClaudeQuotaFailureReason.swift:18-24,58-86`; `ProviderPopoverView.swift:8,61-66,124-125,150-151,286-297,388`; `SystemDashboardModel.swift:146-147,245-246`; `SystemDashboardPopoverView.swift:84,97,112,126,141,163,350-366,417,559,672,685`; `SettingsView.swift:318-330`; `MenuBarController.swift:96,128,142,185,205,448-450,472,512,530,576,600,789-791,928-930`; `AppDelegate.swift:223-225,254-256`; `SettingsActions.swift:9,13,19,25,44,49,66-76`; `Tests/NeedlbarTests/ClaudeKeychainAccessPresentationTests.swift`; `MenuBarControllerTests.swift:922-950,1017,1048`; `PopoverPresentationTests.swift:75` | Task 10 |
| `requestClaudeKeychainAccess`, in-flight flag, epoch, `excludingClaude` | `RefreshCoordinator.swift:96-101,264,301-328,511,519-527,665-672,684,688-692,712,741,753,779` | Task 10 |
| `credentialAccessUnavailable`, `claudeCodeAccessExpired` reasons, origin association | `ClaudeQuotaFailureReason.swift`; `ClaudeQuotaCompletionDiagnostics.swift:26-49` | Tasks 10, 11 |
| Login-path leftovers: `claude auth login`, preflight, `.claudePreflight`, `.userInitiated(.claude)`, `ClaudeLoginPreflightOutcome`, Settings Claude login copy | `ProviderLoginCoordinator.swift:49-54,78-79,101,132,717,733,741,753-760,781-832`; `RefreshCoordinator.swift:19-24,51-54,84,94-95,262,330-355,374,382,641-644,653-658,712-714,741-743,834-838,889-933`; `AppDelegate.swift:204-206`; `QuotaRepository.swift:13,20,51-54`; `RustBridge.swift:12-13,23-24,33-34,49-55`; `SettingsView.swift:486-488,494-496`; `SettingsStudioReviewFixtures.swift:88` | Task 11 |
| Old-path copy in docs | Task 13 list | Task 13 |

**Codex keeps working:** `codex.rs` uses `RedactingHttpClient::for_codex_usage`, `get_bearer`, `send`, `read_limited_body`, `with_retry_after` and `for_provider`, all kept. It imports nothing from `claude*`. Its only dependence on the removed text is the 401/403 message, which `codex_http_error` (`codex.rs:493-508`) already rewrites. `crates/needlbar-quota/tests/codex.rs` and `tests/cursor.rs` are untouched and run in every gate.

### 5. Presentation when the five-hour window is absent

| Place | Behaviour without `session` | Change |
|---|---|---|
| `ClaudeQuotaPresentationSelector.swift:44-50` | `fiveHour` nil unless a recent status line has it | Source order only (Task 8) |
| `ProviderPopoverView.swift:82,250` | Row hidden | None |
| `ProviderPopoverView.swift:114` | `quotaUnavailable` true when only Fable exists, wrongly | Fix (Task 8) |
| `HeadlineQuotaSelector.swift:10-18`, menu bar (`MenuBarTitleRenderer.swift:39,70`, `MenuBarDashboardRenderer.swift:356`) | Uses what exists; Fable never headlines, so only-Fable shows `—` | None, test added |
| Dashboard `SystemDashboardModel.swift:258-264,316-345` | Compact row uses what exists | None |
| Widget `WidgetProjectionMapper.swift:42-46`, `WidgetProjection.swift:53-60` | Picks the most constrained allowed ID; a nil headline is valid | None, test added |
| Alerts `QuotaNotificationService.swift:353-385`, `QuotaAlertPolicy.swift:25` | Filters to allowed IDs; absent window gives no observation; a stale ledger record is harmless | None, test added |
| Export `SnapshotExporter.swift:122,233-237` | Validates only present windows, filters Fable | None, test added |
| Attempt diagnostics `RefreshCoordinator.swift:805-809` | `observationSource(nil)` is `.unavailable` | None |

**Cached data:** direct values were only ever in memory (`docs/HANDOFF.md:89-91`). The persisted items are the status-line record, whose `fiveHour` and `sevenDay` are already optional and which ages out at 24 hours (`ClaudeQuotaPresentationSelector.swift:37,108`); the widget projection, whose IDs are unchanged; and the alert ledger, whose keys are unchanged. No migration is needed.

### 6. Failure states and diagnostics

| Spec state | `QuotaErrorCode` | Origin (serialized) | Reason | Short copy | Auto-retry after backoff |
|---|---|---|---|---|---|
| CLI not found | `NotInstalled` | `claudeCliNotFound` | `.claudeCodeNotInstalled` | Install Claude Code to see quota | No, next trigger (the periodic run counts) |
| No usage (amended 2026-11-03: was "Signed out or no usage" / `RequiresAuthentication` / `.claudeCodeSignInRequired`) | `ProviderUnavailable` | `usageReportNoUsage` | `.claudeCodeCheckFailed` | Could not check Claude Code, plus detail "If this continues, run claude in Terminal to check its sign-in." | Yes |
| Timed out | `ProviderUnavailable` | `usageProbeTimedOut` | `.claudeCodeCheckFailed` | Could not check Claude Code | Yes |
| Output too large | `ProviderUnavailable` | `usageProbeOutputTooLarge` | `.claudeCodeCheckFailed` | same | Yes |
| Process failure | `ProviderUnavailable` | `usageProbeFailed` | `.claudeCodeCheckFailed` | same | Yes |
| Rate limited | `RateLimited` | `usageReportRateLimited` | `.temporarilyLimited` (existing) | Temporarily limited | Yes |
| Format changed | `SchemaChanged` | `usageReportFormatChanged` | `.usageReportFormatChanged` | Could not read Claude Code's usage report | Yes |

`ClaudeQuotaFailureDiagnostic` keeps its line and appends `durationMs= rows= unknownRows= skippedRows=` when a run summary exists. `QuotaRefreshDiagnostic` becomes the record of Claude runs only: it adds the same fields, new triggers `usageRecordsChanged`, `windowReset`, `backoffRetry`, `periodic`, and relabels `direct` as `usageReport` in the log. Row kinds are a closed enum, so a server-sent `kind` string never reaches a log; unknown kinds are only counted. The summary reaches Swift through `claudeUsageProbe` on the existing diagnostics record, which the coordinator already reads once per Claude operation (`RefreshCoordinator.swift:693-700`).

### 7. Test mechanics

- Rust narrow: `cargo test -p needlbar-quota <filter>`; `cargo test -p needlbar-bridge --features bridge-test-runtime --test quota_contract`.
- Swift narrow: `make swift-test SWIFT_TEST_FILTER=<SuiteOrFunction>`. It rebuilds the bridge with `bridge-test-runtime` and restores it (`Makefile:9-53`). Do not use bare `swift test`, which would link the production bridge.
- Project gate: `make test`.
- Fake `claude`: a `#!/bin/sh` script generated in a `TempDir`, prewarmed once outside the timed path, because macOS can hold the first exec of a new file for about 3 s (`crates/needlbar-quota/src/providers/codex.rs:735-760`). The environment is cleared, so the script hard-codes absolute record paths.
- Contract scripts: `scripts/tests/notarize-app-tests.sh:2239` names the README's prepared section and must follow the new heading (Task 13). `scripts/smoke-app.sh` and `scripts/tests/smoke-app-tests.sh` assert nothing about Claude quota and need no change. `scripts/tests/package-app-tests.sh:175` already forbids sandbox and keychain entitlements and stays. `scripts/verify-public-bridge-surface.sh` checks markers, not an export list, and needs no change. `crates/needlbar-bridge/tests/ffi_contract.rs:12-13,21-31` lists exports and changes in Tasks 4 and 11.

### 8. Spec deviations and gaps

1. **Rate-limited state.** Spec §7 reads only `usage_report`, but `SDKUsageReport` has no rate-limit signal, so §8's Rate limited row could never fire. This plan reads one more closed, documented field on the same assistant line, `error == "rate_limit"` (`SDKAssistantMessageError`), compares it, and discards it. It is consulted only when no `usage_report` was found. Reported to the user; the user-run check in Task 14 shows whether it ever fires for `/usage`.
2. **Sessions with no `usage_report` by design.** The public documentation says API-key sessions, usage-based billing and `claude setup-token` sessions deliver text without the field and suggests falling back to the text. Spec §7 forbids reading it and calls this format changed. This plan follows the spec, so those accounts see "Could not read Claude Code's usage report". Reported to the user.
3. **Non-empty `limits` with no usable row** is not in the spec. This plan treats it as format changed. It invents nothing and keeps last known values.
4. **Two rows mapping to one field** is not in the spec. This plan hides that field only, keeping the fail-closed rule at `crates/needlbar-quota/src/providers/claude.rs:213-215`.
5. **Quiet periods (user decision, 2026-11-03).** A periodic run every 15 minutes keeps readings current, and the spec now says so in §6 and §12. `recentDirectInterval` becomes 20 minutes so the label does not flip before each refresh (Decisions 3a). A reading turns **Last known** at once when a run fails, or once it is 20 minutes old with no newer success, for example after sleep. Up to 288 runs a day is an unmeasured cost, observed in Task 14.
6. **Fable line text.** `Fable weekly · Unavailable` stays for a missing Fable row. It shows no value, so "a missing row hides that field only" holds in substance.
7. **Widget freshness.** The decision named the selector, but `WidgetPresentation.freshnessHorizon` has the same 15-minute trap for the Claude quota row, so this plan gives that row 20 minutes too. Spec §6 states this. Reported to the user, because it goes beyond the named constant.

---

## File Structure

**Create**
- `crates/needlbar-quota/src/providers/claude_usage_report.rs`: pure parser, bytes to outcome.
- `crates/needlbar-quota/src/providers/claude_cli.rs`: CLI locator.
- `crates/needlbar-quota/src/providers/claude_usage_probe.rs`: bounded process run, cancellation control.
- `crates/needlbar-quota/src/providers/claude_usage_provider.rs`: composition, closed errors, run summary.
- `crates/needlbar-quota/tests/claude_usage_report.rs`, `claude_usage_probe.rs`, `claude_usage_provider.rs`, `claude_source_contract.rs`.
- `Fixtures/quota/claude/usage-report-all-rows.jsonl`, `usage-report-weekly-only.jsonl`.
- `Sources/NeedlbarCore/Refresh/ClaudeUsageProbeSchedule.swift`: pure run decisions.
- `Tests/NeedlbarCoreTests/ClaudeUsageProbeScheduleTests.swift`, `ClaudeUsageProbeCoordinatorTests.swift`, `ClaudeUsageReportReasonTests.swift`, `ClaudeUsageReportSourceContractTests.swift`.
- `Tests/NeedlbarTests/ClaudeUsageReportPresentationTests.swift`.

**Delete** (each in the task named above)
- `crates/needlbar-quota/src/providers/claude.rs`, `claude_credentials.rs`, `crates/needlbar-quota/tests/claude.rs`, `Fixtures/quota/claude/usage-success.json`, `usage-fable-success.json`, `usage-malformed.json`.
- `Tests/NeedlbarCoreTests/ClaudeKeychainAccessTests.swift`, `ClaudeAccessExpiredReasonTests.swift`, `Tests/NeedlbarTests/ClaudeKeychainAccessPresentationTests.swift`, `ClaudeAccessExpiredPresentationTests.swift`.

**Modify**: the files named per task.

---

## Task 1: Report parser

**Files:**
- Create: `crates/needlbar-quota/src/providers/claude_usage_report.rs`
- Create: `Fixtures/quota/claude/usage-report-all-rows.jsonl`, `Fixtures/quota/claude/usage-report-weekly-only.jsonl`
- Modify: `crates/needlbar-quota/src/providers/mod.rs:5-8`, `crates/needlbar-quota/src/lib.rs:8-20`
- Test: `crates/needlbar-quota/tests/claude_usage_report.rs`

**Interfaces:**
- Consumes: `QuotaWindow::new` (`crates/needlbar-quota/src/domain.rs:24-36`).
- Produces: `pub fn parse_usage_report_stream(bytes: &[u8]) -> ClaudeUsageReportOutcome`; `pub enum ClaudeUsageReportOutcome { Windows { windows: Vec<QuotaWindow>, rows: ClaudeUsageRowSummary }, NoUsageAvailable { rows: ClaudeUsageRowSummary }, RateLimited, FormatChanged { rows: ClaudeUsageRowSummary } }`; `pub struct ClaudeUsageRowSummary { pub row_kinds: Vec<ClaudeUsageRowKind>, pub unknown_row_count: u32, pub skipped_row_count: u32 }`; `pub enum ClaudeUsageRowKind { Session, WeeklyAll, WeeklyScoped }`, serialized `session`, `weeklyAll`, `weeklyScoped`. All re-exported from the crate root.

- [ ] **Step 1: Write the fixtures**

`Fixtures/quota/claude/usage-report-all-rows.jsonl` (three lines, every canary must never surface):

```text
{"type":"system","subtype":"init","session_id":"SESSION-CANARY","cwd":"/Users/alice/PATH-CANARY","model":"claude-test"}
{"type":"assistant","uuid":"00000000-0000-4000-8000-000000000001","session_id":"SESSION-CANARY","parent_tool_use_id":null,"message":{"role":"assistant","content":[{"type":"text","text":"TEXT-CANARY alice@example.com"}]},"usage_report":{"session":{"total_cost_usd":12.5,"total_api_duration_ms":0,"total_duration_ms":0,"total_lines_added":0,"total_lines_removed":0,"model_usage":{}},"rate_limits":{"limits":[{"kind":"session","group":"session","percent":42.5,"resets_at":"2030-02-02T05:00:00Z","scope":null,"severity":"normal","is_active":true},{"kind":"weekly_all","group":"weekly","percent":74,"resets_at":"2030-02-09T01:00:00Z","scope":null,"severity":"normal","is_active":false},{"kind":"weekly_scoped","group":"weekly","percent":25,"resets_at":"2030-02-09T01:00:00Z","scope":{"model":{"display_name":"Fable"},"surface":null},"severity":"normal","is_active":false}],"extra_usage":null}}}
{"type":"result","subtype":"success","is_error":false,"result":"RESULT-CANARY","total_cost_usd":0,"session_id":"SESSION-CANARY"}
```

`Fixtures/quota/claude/usage-report-weekly-only.jsonl` (the shape seen on this account: no `session` row):

```text
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"TEXT-CANARY"}]},"usage_report":{"session":{"total_cost_usd":0,"model_usage":{}},"rate_limits":{"limits":[{"kind":"weekly_all","group":"weekly","percent":74,"resets_at":"2030-02-09T01:00:00Z","severity":"normal","is_active":true},{"kind":"weekly_scoped","group":"weekly","percent":0,"resets_at":null,"scope":{"model":{"display_name":"Fable"}},"severity":"normal","is_active":false}]}}}
```

- [ ] **Step 2: Write the failing test**

`crates/needlbar-quota/tests/claude_usage_report.rs`:

```rust
use chrono::{TimeZone, Utc};
use needlbar_quota::{
    parse_usage_report_stream, ClaudeUsageReportOutcome, ClaudeUsageRowKind, ClaudeUsageRowSummary,
    QuotaWindow,
};

const ALL_ROWS: &str = include_str!("../../../Fixtures/quota/claude/usage-report-all-rows.jsonl");
const WEEKLY_ONLY: &str =
    include_str!("../../../Fixtures/quota/claude/usage-report-weekly-only.jsonl");

fn stream(rate_limits: &str) -> Vec<u8> {
    format!(
        "{{\"type\":\"assistant\",\"message\":{{\"content\":[]}},\"usage_report\":{{\"session\":{{\"total_cost_usd\":1}},\"rate_limits\":{rate_limits}}}}}\n"
    )
    .into_bytes()
}

fn rows(rows: &str) -> Vec<u8> {
    stream(&format!("{{\"limits\":[{rows}]}}"))
}

const WEEKLY_ROW: &str =
    r#"{"kind":"weekly_all","group":"weekly","percent":74,"resets_at":"2030-02-09T01:00:00Z"}"#;

fn windows(outcome: ClaudeUsageReportOutcome) -> (Vec<QuotaWindow>, ClaudeUsageRowSummary) {
    match outcome {
        ClaudeUsageReportOutcome::Windows { windows, rows } => (windows, rows),
        other => panic!("expected windows, got {other:?}"),
    }
}

#[test]
fn all_rows_map_to_the_existing_window_ids_in_order() {
    let (windows, rows) = windows(parse_usage_report_stream(ALL_ROWS.as_bytes()));
    let ids: Vec<_> = windows.iter().map(QuotaWindow::id).collect();
    assert_eq!(ids, ["claude.session", "claude.weekly", "claude.fable.weekly"]);
    let titles: Vec<_> = windows.iter().map(QuotaWindow::title).collect();
    assert_eq!(titles, ["Session", "Weekly", "Fable weekly"]);
    assert_eq!(windows[0].used_percent(), 42.5);
    assert_eq!(windows[1].used_percent(), 74.0);
    assert_eq!(windows[2].used_percent(), 25.0);
    assert_eq!(
        windows[0].resets_at(),
        Some(Utc.with_ymd_and_hms(2030, 2, 2, 5, 0, 0).unwrap())
    );
    assert_eq!(
        rows.row_kinds,
        [
            ClaudeUsageRowKind::Session,
            ClaudeUsageRowKind::WeeklyAll,
            ClaudeUsageRowKind::WeeklyScoped
        ]
    );
}

#[test]
fn a_missing_session_row_hides_only_that_field() {
    let (windows, _) = windows(parse_usage_report_stream(WEEKLY_ONLY.as_bytes()));
    let ids: Vec<_> = windows.iter().map(QuotaWindow::id).collect();
    assert_eq!(ids, ["claude.weekly", "claude.fable.weekly"]);
    assert_eq!(windows[1].used_percent(), 0.0);
    assert_eq!(windows[1].resets_at(), None);
}

#[test]
fn the_report_level_session_totals_are_not_the_session_row() {
    let (windows, _) = windows(parse_usage_report_stream(&rows(WEEKLY_ROW)));
    assert!(windows.iter().all(|window| window.id() != "claude.session"));
}

#[test]
fn only_fable_present_is_a_valid_reading() {
    let only_fable = r#"{"kind":"weekly_scoped","percent":3,"scope":{"model":{"display_name":"FABLE"}}}"#;
    let (windows, _) = windows(parse_usage_report_stream(&rows(only_fable)));
    assert_eq!(windows.len(), 1);
    assert_eq!(windows[0].id(), "claude.fable.weekly");
}

#[test]
fn percent_is_clamped_and_non_numbers_are_skipped() {
    let input = rows(
        r#"{"kind":"session","percent":140},{"kind":"weekly_all","percent":-5},{"kind":"weekly_scoped","percent":"NaN","scope":{"model":{"display_name":"Fable"}}}"#,
    );
    let (windows, rows) = windows(parse_usage_report_stream(&input));
    assert_eq!(windows.len(), 2);
    assert_eq!(windows[0].used_percent(), 100.0);
    assert_eq!(windows[1].used_percent(), 0.0);
    assert_eq!(rows.skipped_row_count, 1);
}

#[test]
fn a_malformed_row_is_skipped_and_the_others_still_count() {
    let input = rows(&format!(
        r#"{{"percent":10}},{{"kind":"session","resets_at":"2030-02-02T05:00:00Z"}},{{"kind":"session","percent":10,"resets_at":"not-a-date"}},17,{WEEKLY_ROW}"#
    ));
    let (windows, rows) = windows(parse_usage_report_stream(&input));
    assert_eq!(windows.len(), 1);
    assert_eq!(windows[0].id(), "claude.weekly");
    assert_eq!(rows.skipped_row_count, 4);
}

#[test]
fn unknown_kinds_and_other_models_are_ignored() {
    let input = rows(&format!(
        r#"{{"kind":"daily_future","percent":10}},{{"kind":"weekly_scoped","percent":9,"scope":{{"model":{{"display_name":"Other"}}}}}},{WEEKLY_ROW}"#
    ));
    let (windows, rows) = windows(parse_usage_report_stream(&input));
    assert_eq!(windows.len(), 1);
    assert_eq!(rows.unknown_row_count, 1);
    assert!(rows.row_kinds.contains(&ClaudeUsageRowKind::WeeklyScoped));
}

#[test]
fn missing_or_null_reset_shows_no_reset_time() {
    let input = rows(r#"{"kind":"session","percent":1},{"kind":"weekly_all","percent":2,"resets_at":null}"#);
    let (windows, _) = windows(parse_usage_report_stream(&input));
    assert!(windows.iter().all(|window| window.resets_at().is_none()));
}

#[test]
fn two_rows_for_one_field_hide_only_that_field() {
    let input = rows(&format!(
        r#"{{"kind":"session","percent":1}},{{"kind":"session","percent":2}},{WEEKLY_ROW}"#
    ));
    let (windows, rows) = windows(parse_usage_report_stream(&input));
    assert_eq!(windows.len(), 1);
    assert_eq!(windows[0].id(), "claude.weekly");
    assert_eq!(rows.skipped_row_count, 2);
}

#[test]
fn null_rate_limits_and_null_or_empty_limits_are_no_usage() {
    for input in [stream("null"), stream(r#"{"limits":null}"#), stream(r#"{"limits":[]}"#)] {
        assert!(matches!(
            parse_usage_report_stream(&input),
            ClaudeUsageReportOutcome::NoUsageAvailable { .. }
        ));
    }
}

#[test]
fn no_report_and_changed_shapes_are_format_changed() {
    for input in [
        b"".to_vec(),
        b"not json\n".to_vec(),
        br#"{"type":"assistant","message":{"content":[]}}"#.to_vec(),
        br#"{"type":"assistant","usage_report":null}"#.to_vec(),
        br#"{"type":"result","usage_report":{"rate_limits":null}}"#.to_vec(),
        br#"{"type":"assistant","usage_report":{}}"#.to_vec(),
        stream("7"),
        stream(r#"{"limits":"none"}"#),
        stream(r#"{}"#),
        rows(r#"{"kind":"daily_future","percent":10}"#),
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
fn a_rate_limit_error_is_used_only_when_there_is_no_report() {
    let limited = br#"{"type":"assistant","error":"rate_limit","message":{"content":[]}}"#;
    assert_eq!(
        parse_usage_report_stream(limited),
        ClaudeUsageReportOutcome::RateLimited
    );
    let mut with_report = limited.to_vec();
    with_report.push(b'\n');
    with_report.extend_from_slice(&rows(WEEKLY_ROW));
    assert!(matches!(
        parse_usage_report_stream(&with_report),
        ClaudeUsageReportOutcome::Windows { .. }
    ));
}

#[test]
fn nothing_but_closed_values_survives_parsing() {
    let outcome = parse_usage_report_stream(ALL_ROWS.as_bytes());
    let debug = format!("{outcome:?}");
    for canary in [
        "SESSION-CANARY",
        "PATH-CANARY",
        "TEXT-CANARY",
        "RESULT-CANARY",
        "alice@example.com",
    ] {
        assert!(!debug.contains(canary), "{canary}");
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cargo test -p needlbar-quota --test claude_usage_report`
Expected: FAIL to compile with `unresolved import` for `parse_usage_report_stream`.

- [ ] **Step 4: Write the parser**

`crates/needlbar-quota/src/providers/claude_usage_report.rs`:

```rust
//! Pure parser for `claude -p /usage --output-format stream-json`. It knows
//! nothing about processes. Everything except `usage_report`, and the closed
//! `error` value used when no report arrived, is discarded here: serde skips
//! other fields without building them, and no text is kept or logged.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::QuotaWindow;

const SESSION_ID: &str = "claude.session";
const WEEKLY_ID: &str = "claude.weekly";
const FABLE_ID: &str = "claude.fable.weekly";

/// A closed label for diagnostics, so a server-sent `kind` never reaches a log.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ClaudeUsageRowKind {
    Session,
    WeeklyAll,
    WeeklyScoped,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClaudeUsageRowSummary {
    pub row_kinds: Vec<ClaudeUsageRowKind>,
    pub unknown_row_count: u32,
    pub skipped_row_count: u32,
}

#[derive(Debug, Clone, PartialEq)]
pub enum ClaudeUsageReportOutcome {
    Windows {
        windows: Vec<QuotaWindow>,
        rows: ClaudeUsageRowSummary,
    },
    NoUsageAvailable {
        rows: ClaudeUsageRowSummary,
    },
    RateLimited,
    FormatChanged {
        rows: ClaudeUsageRowSummary,
    },
}

#[derive(Deserialize)]
struct StreamLine {
    #[serde(default, rename = "type")]
    line_type: Option<Value>,
    #[serde(default)]
    usage_report: Option<Value>,
    #[serde(default)]
    error: Option<Value>,
}

pub fn parse_usage_report_stream(bytes: &[u8]) -> ClaudeUsageReportOutcome {
    let mut report = None;
    let mut rate_limited = false;
    for line in bytes.split(|byte| *byte == b'\n') {
        let Ok(parsed) = serde_json::from_slice::<StreamLine>(line) else {
            continue;
        };
        if parsed.line_type.as_ref().and_then(Value::as_str) != Some("assistant") {
            continue;
        }
        rate_limited |= parsed.error.as_ref().and_then(Value::as_str) == Some("rate_limit");
        if let Some(candidate) = parsed.usage_report.filter(|value| !value.is_null()) {
            report = Some(candidate);
        }
    }
    match report {
        Some(report) => classify_report(&report),
        None if rate_limited => ClaudeUsageReportOutcome::RateLimited,
        None => ClaudeUsageReportOutcome::FormatChanged {
            rows: ClaudeUsageRowSummary::default(),
        },
    }
}

fn format_changed() -> ClaudeUsageReportOutcome {
    ClaudeUsageReportOutcome::FormatChanged {
        rows: ClaudeUsageRowSummary::default(),
    }
}

fn no_usage() -> ClaudeUsageReportOutcome {
    ClaudeUsageReportOutcome::NoUsageAvailable {
        rows: ClaudeUsageRowSummary::default(),
    }
}

fn classify_report(report: &Value) -> ClaudeUsageReportOutcome {
    let Some(rate_limits) = report.as_object().and_then(|object| object.get("rate_limits")) else {
        return format_changed();
    };
    if rate_limits.is_null() {
        return no_usage();
    }
    let Some(limits) = rate_limits.as_object().and_then(|object| object.get("limits")) else {
        return format_changed();
    };
    if limits.is_null() {
        return no_usage();
    }
    let Some(rows) = limits.as_array() else {
        return format_changed();
    };
    if rows.is_empty() {
        return no_usage();
    }
    classify_rows(rows)
}

#[derive(Default)]
struct Field {
    readings: Vec<(f64, Option<DateTime<Utc>>)>,
}

impl Field {
    fn window(self, id: &str, title: &str, summary: &mut ClaudeUsageRowSummary) -> Option<QuotaWindow> {
        match self.readings.as_slice() {
            [] => None,
            [(percent, resets_at)] => QuotaWindow::new(id, title, *percent, *resets_at).ok(),
            // Two rows for one field cannot be told apart, so show neither.
            several => {
                summary.skipped_row_count += several.len() as u32;
                None
            }
        }
    }
}

fn classify_rows(rows: &[Value]) -> ClaudeUsageReportOutcome {
    let mut summary = ClaudeUsageRowSummary::default();
    let (mut session, mut weekly, mut fable) =
        (Field::default(), Field::default(), Field::default());
    for row in rows {
        let Some(kind) = row.get("kind").and_then(Value::as_str) else {
            summary.skipped_row_count += 1;
            continue;
        };
        let (row_kind, field) = match kind {
            "session" => (ClaudeUsageRowKind::Session, Some(&mut session)),
            "weekly_all" => (ClaudeUsageRowKind::WeeklyAll, Some(&mut weekly)),
            "weekly_scoped" => (
                ClaudeUsageRowKind::WeeklyScoped,
                is_fable(row).then_some(&mut fable),
            ),
            _ => {
                summary.unknown_row_count += 1;
                continue;
            }
        };
        if !summary.row_kinds.contains(&row_kind) {
            summary.row_kinds.push(row_kind);
        }
        let Some(field) = field else { continue };
        match parse_reading(row) {
            Some(reading) => field.readings.push(reading),
            None => summary.skipped_row_count += 1,
        }
    }
    let windows: Vec<QuotaWindow> = [
        session.window(SESSION_ID, "Session", &mut summary),
        weekly.window(WEEKLY_ID, "Weekly", &mut summary),
        fable.window(FABLE_ID, "Fable weekly", &mut summary),
    ]
    .into_iter()
    .flatten()
    .collect();
    if windows.is_empty() {
        return ClaudeUsageReportOutcome::FormatChanged { rows: summary };
    }
    ClaudeUsageReportOutcome::Windows {
        windows,
        rows: summary,
    }
}

/// No documented identifier exists for a model scope, so this label is a known
/// weak point (spec §7).
fn is_fable(row: &Value) -> bool {
    row.pointer("/scope/model/display_name")
        .and_then(Value::as_str)
        .is_some_and(|name| name.eq_ignore_ascii_case("Fable"))
}

fn parse_reading(row: &Value) -> Option<(f64, Option<DateTime<Utc>>)> {
    let percent = row.get("percent")?.as_f64().filter(|value| value.is_finite())?;
    let resets_at = match row.get("resets_at") {
        None | Some(Value::Null) => None,
        Some(Value::String(text)) => Some(
            DateTime::parse_from_rfc3339(text)
                .ok()?
                .with_timezone(&Utc),
        ),
        Some(_) => return None,
    };
    Some((percent.clamp(0.0, 100.0), resets_at))
}
```

In `crates/needlbar-quota/src/providers/mod.rs` add `pub mod claude_usage_report;` after `pub mod claude_credentials;`. In `crates/needlbar-quota/src/lib.rs` add after line 17:

```rust
pub use providers::claude_usage_report::{
    parse_usage_report_stream, ClaudeUsageReportOutcome, ClaudeUsageRowKind, ClaudeUsageRowSummary,
};
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cargo test -p needlbar-quota --test claude_usage_report`
Expected: PASS, 13 tests.

- [ ] **Step 6: Commit**

```bash
git add crates/needlbar-quota/src/providers/claude_usage_report.rs crates/needlbar-quota/src/providers/mod.rs crates/needlbar-quota/src/lib.rs crates/needlbar-quota/tests/claude_usage_report.rs Fixtures/quota/claude/usage-report-all-rows.jsonl Fixtures/quota/claude/usage-report-weekly-only.jsonl
git commit -m "feat(quota): parse the Claude usage report stream

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 2: CLI locator and usage probe

**Files:**
- Create: `crates/needlbar-quota/src/providers/claude_cli.rs`, `crates/needlbar-quota/src/providers/claude_usage_probe.rs`
- Modify: `Cargo.toml:22` (tokio features), `crates/needlbar-quota/Cargo.toml`, `crates/needlbar-quota/src/providers/mod.rs`, `crates/needlbar-quota/src/lib.rs`
- Test: `crates/needlbar-quota/tests/claude_usage_probe.rs`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `ClaudeCliLocator::{for_home(&Path), with_candidates(Vec<PathBuf>), candidates() -> &[PathBuf], locate() -> Option<PathBuf>}`; `USAGE_PROBE_ARGUMENTS: [&str; 9]`; `UsageProbeEnvironment::{from_lookup(impl Fn(&str) -> Option<OsString>), from_process(), pairs() -> &[(&'static str, OsString)]}`; `UsageProbeLimits { deadline: Duration, max_stdout_bytes: usize }` with `Default` of 30 s and 1 MiB; `UsageProbeFailure { LaunchFailed, ExitedUnsuccessfully, TimedOut, OutputTooLarge, Cancelled }`; `UsageProbeControl::{new(), shared() -> Arc<Self>, cancel_through(u64), is_cancelled(u64) -> bool}`; `async fn run_usage_probe(executable: &Path, environment: &UsageProbeEnvironment, limits: UsageProbeLimits, control: &UsageProbeControl, run_id: u64) -> Result<Vec<u8>, UsageProbeFailure>`. Run IDs start at 1.

- [ ] **Step 1: Write the failing test**

`crates/needlbar-quota/tests/claude_usage_probe.rs`:

```rust
use std::{
    ffi::OsString,
    fs,
    os::unix::fs::{symlink, PermissionsExt},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::Arc,
    time::{Duration, Instant},
};

use needlbar_quota::{
    run_usage_probe, ClaudeCliLocator, UsageProbeControl, UsageProbeEnvironment, UsageProbeFailure,
    UsageProbeLimits, USAGE_PROBE_ARGUMENTS,
};
use tempfile::TempDir;

const PREWARM: &str = "--needlbar-prewarm";

/// Writes an executable fake `claude`. macOS can hold the first exec of a new
/// file for about 3 s, so it runs once here, outside the timed path.
fn fake_claude(directory: &Path, body: &str) -> PathBuf {
    let path = directory.join("claude");
    fs::write(
        &path,
        format!("#!/bin/sh\nif [ \"${{1:-}}\" = '{PREWARM}' ]; then exit 0; fi\n{body}\n"),
    )
    .unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o700)).unwrap();
    assert!(Command::new(&path)
        .arg(PREWARM)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .unwrap()
        .success());
    path
}

fn environment() -> UsageProbeEnvironment {
    UsageProbeEnvironment::from_lookup(|name| match name {
        "HOME" => Some(OsString::from("/tmp/needlbar-fake-home")),
        "USER" => Some(OsString::from("fake-user")),
        "LOGNAME" => Some(OsString::from("fake-login")),
        "TMPDIR" => Some(OsString::from("/tmp")),
        "ANTHROPIC_API_KEY" | "CLAUDE_CODE_OAUTH_TOKEN" | "OTHER" => Some(OsString::from("LEAK")),
        _ => None,
    })
}

fn limits(deadline_ms: u64) -> UsageProbeLimits {
    UsageProbeLimits {
        deadline: Duration::from_millis(deadline_ms),
        ..UsageProbeLimits::default()
    }
}

async fn assert_pid_gone(pid_file: &Path) {
    let text = fs::read_to_string(pid_file).unwrap();
    let pid = text.trim();
    assert!(!pid.is_empty() && pid.bytes().all(|byte| byte.is_ascii_digit()), "{text:?}");
    let deadline = Instant::now() + Duration::from_secs(5);
    while Instant::now() < deadline {
        let alive = Command::new("kill")
            .args(["-0", pid])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .unwrap()
            .success();
        if !alive {
            return;
        }
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
    panic!("process {pid} was still running");
}

#[test]
fn locator_takes_the_first_executable_regular_file_in_order() {
    let temp = TempDir::new().unwrap();
    let first = temp.path().join("first");
    let second = temp.path().join("second");
    let third = temp.path().join("third");
    fs::write(&first, "not executable").unwrap();
    fs::set_permissions(&first, fs::Permissions::from_mode(0o600)).unwrap();
    fs::write(&second, "#!/bin/sh\n").unwrap();
    fs::set_permissions(&second, fs::Permissions::from_mode(0o700)).unwrap();
    fs::write(&third, "#!/bin/sh\n").unwrap();
    fs::set_permissions(&third, fs::Permissions::from_mode(0o700)).unwrap();
    let locator = ClaudeCliLocator::with_candidates(vec![
        temp.path().join("missing"),
        first,
        second.clone(),
        third,
    ]);
    assert_eq!(locator.locate(), Some(fs::canonicalize(second).unwrap()));
}

#[test]
fn locator_resolves_symlinks_and_rejects_directories_and_dangling_links() {
    let temp = TempDir::new().unwrap();
    let target = temp.path().join("versions/1.0/claude");
    fs::create_dir_all(target.parent().unwrap()).unwrap();
    fs::write(&target, "#!/bin/sh\n").unwrap();
    fs::set_permissions(&target, fs::Permissions::from_mode(0o700)).unwrap();
    let link = temp.path().join("claude");
    symlink(&target, &link).unwrap();
    let dangling = temp.path().join("dangling");
    symlink(temp.path().join("nowhere"), &dangling).unwrap();
    let directory = temp.path().join("directory");
    fs::create_dir(&directory).unwrap();

    assert_eq!(
        ClaudeCliLocator::with_candidates(vec![dangling.clone(), directory.clone(), link]).locate(),
        Some(fs::canonicalize(&target).unwrap())
    );
    assert_eq!(
        ClaudeCliLocator::with_candidates(vec![dangling, directory]).locate(),
        None
    );
}

#[test]
fn locator_checks_the_fixed_locations_in_the_specified_order() {
    let candidates = ClaudeCliLocator::for_home(Path::new("/Users/fake")).candidates().to_vec();
    assert_eq!(
        candidates,
        [
            PathBuf::from("/Users/fake/.local/bin/claude"),
            PathBuf::from("/opt/homebrew/bin/claude"),
            PathBuf::from("/usr/local/bin/claude"),
        ]
    );
}

#[test]
fn environment_is_an_allowlist_with_a_fixed_path() {
    let names: Vec<_> = environment().pairs().iter().map(|(name, _)| *name).collect();
    assert_eq!(names, ["HOME", "USER", "LOGNAME", "TMPDIR", "PATH"]);
    let with_config = UsageProbeEnvironment::from_lookup(|name| {
        (name == "CLAUDE_CONFIG_DIR").then(|| OsString::from("/tmp/config"))
    });
    assert!(with_config
        .pairs()
        .iter()
        .any(|(name, value)| *name == "CLAUDE_CONFIG_DIR" && value == "/tmp/config"));
    let empty_config = UsageProbeEnvironment::from_lookup(|name| {
        (name == "CLAUDE_CONFIG_DIR").then(OsString::new)
    });
    assert!(empty_config.pairs().iter().all(|(name, _)| *name != "CLAUDE_CONFIG_DIR"));
}

#[tokio::test]
async fn runs_with_the_exact_argv_environment_stdin_and_a_fresh_directory_it_deletes() {
    let temp = TempDir::new().unwrap();
    let record = temp.path().join("record");
    fs::create_dir(&record).unwrap();
    let record_text = record.display();
    let script = fake_claude(
        temp.path(),
        &format!(
            r#"for argument in "$@"; do printf '%s\n' "$argument"; done > '{record_text}/argv'
/usr/bin/env > '{record_text}/env'
pwd > '{record_text}/cwd'
/bin/ls -A > '{record_text}/entries'
/bin/cat > '{record_text}/stdin'
printf 'report-bytes'"#
        ),
    );

    let output = run_usage_probe(
        &script,
        &environment(),
        limits(10_000),
        &UsageProbeControl::new(),
        1,
    )
    .await
    .unwrap();

    assert_eq!(output, b"report-bytes");
    let argv = fs::read_to_string(record.join("argv")).unwrap();
    assert_eq!(argv.lines().collect::<Vec<_>>(), USAGE_PROBE_ARGUMENTS);
    assert_eq!(
        USAGE_PROBE_ARGUMENTS,
        [
            "-p",
            "/usage",
            "--no-session-persistence",
            "--strict-mcp-config",
            "--settings",
            r#"{"disableAllHooks":true}"#,
            "--output-format",
            "stream-json",
            "--verbose",
        ]
    );
    let env = fs::read_to_string(record.join("env")).unwrap();
    let names: Vec<_> = env.lines().filter_map(|line| line.split('=').next()).collect();
    for name in names {
        // /bin/sh and macOS add the last five; the rest must come from the allowlist.
        assert!(
            [
                "HOME",
                "USER",
                "LOGNAME",
                "TMPDIR",
                "PATH",
                "PWD",
                "OLDPWD",
                "SHLVL",
                "_",
                "__CF_USER_TEXT_ENCODING",
            ]
            .contains(&name),
            "unexpected variable {name}"
        );
    }
    assert!(!env.contains("LEAK"));
    assert!(env.contains("PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin\n"));
    assert_eq!(fs::read_to_string(record.join("entries")).unwrap(), "");
    assert_eq!(fs::read_to_string(record.join("stdin")).unwrap(), "");
    let cwd = fs::read_to_string(record.join("cwd")).unwrap();
    assert!(!Path::new(cwd.trim()).exists(), "working directory was not deleted");
}

#[tokio::test]
async fn non_zero_exit_is_a_process_failure_even_with_valid_output() {
    let temp = TempDir::new().unwrap();
    let script = fake_claude(temp.path(), "printf 'report'\nexit 3");
    let result = run_usage_probe(&script, &environment(), limits(10_000), &UsageProbeControl::new(), 1).await;
    assert_eq!(result, Err(UsageProbeFailure::ExitedUnsuccessfully));
}

#[tokio::test]
async fn a_missing_executable_is_a_launch_failure() {
    let temp = TempDir::new().unwrap();
    let result = run_usage_probe(
        &temp.path().join("absent"),
        &environment(),
        limits(1_000),
        &UsageProbeControl::new(),
        1,
    )
    .await;
    assert_eq!(result, Err(UsageProbeFailure::LaunchFailed));
}

#[tokio::test]
async fn the_deadline_terminates_the_whole_process_group() {
    let temp = TempDir::new().unwrap();
    let parent = temp.path().join("parent.pid");
    let child = temp.path().join("child.pid");
    let script = fake_claude(
        temp.path(),
        &format!(
            "printf '%s\\n' \"$$\" > '{}'\n/bin/sleep 30 &\nprintf '%s\\n' \"$!\" > '{}'\nwait",
            parent.display(),
            child.display()
        ),
    );
    let started = Instant::now();
    let result = run_usage_probe(&script, &environment(), limits(3_000), &UsageProbeControl::new(), 1).await;
    assert_eq!(result, Err(UsageProbeFailure::TimedOut));
    assert!(started.elapsed() < Duration::from_secs(10));
    assert_pid_gone(&parent).await;
    assert_pid_gone(&child).await;
}

#[tokio::test]
async fn oversized_stdout_terminates_the_run() {
    let temp = TempDir::new().unwrap();
    let script = fake_claude(temp.path(), "/usr/bin/yes report");
    let result = run_usage_probe(
        &script,
        &environment(),
        UsageProbeLimits {
            deadline: Duration::from_secs(20),
            max_stdout_bytes: 64 * 1024,
        },
        &UsageProbeControl::new(),
        1,
    )
    .await;
    assert_eq!(result, Err(UsageProbeFailure::OutputTooLarge));
}

#[tokio::test]
async fn stderr_is_drained_without_counting_or_blocking() {
    let temp = TempDir::new().unwrap();
    let script = fake_claude(
        temp.path(),
        "/usr/bin/head -c 2097152 /dev/zero >&2\nprintf 'report'",
    );
    let output = run_usage_probe(&script, &environment(), limits(20_000), &UsageProbeControl::new(), 1)
        .await
        .unwrap();
    assert_eq!(output, b"report");
}

#[tokio::test]
async fn a_descendant_holding_stdout_after_exit_cannot_stall_the_run() {
    let temp = TempDir::new().unwrap();
    let held = temp.path().join("held.pid");
    let script = fake_claude(
        temp.path(),
        &format!("printf 'report'\n/bin/sleep 30 &\nprintf '%s\\n' \"$!\" > '{}'", held.display()),
    );
    let started = Instant::now();
    let output = run_usage_probe(&script, &environment(), limits(20_000), &UsageProbeControl::new(), 1)
        .await
        .unwrap();
    assert_eq!(output, b"report");
    assert!(started.elapsed() < Duration::from_secs(10));
    let pid = fs::read_to_string(&held).unwrap();
    let _ = Command::new("kill").arg(pid.trim()).status();
}

#[tokio::test]
async fn cancelling_stops_the_process_and_an_already_cancelled_run_never_spawns() {
    let temp = TempDir::new().unwrap();
    let started_marker = temp.path().join("started");
    let pid_file = temp.path().join("run.pid");
    let script = fake_claude(
        temp.path(),
        &format!(
            "printf '%s\\n' \"$$\" > '{}'\n: > '{}'\n/bin/sleep 30",
            pid_file.display(),
            started_marker.display()
        ),
    );
    let control = Arc::new(UsageProbeControl::new());
    let run = {
        let (script, control) = (script.clone(), Arc::clone(&control));
        tokio::spawn(async move {
            run_usage_probe(&script, &environment(), limits(25_000), &control, 5).await
        })
    };
    while !started_marker.exists() {
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    control.cancel_through(5);
    assert_eq!(run.await.unwrap(), Err(UsageProbeFailure::Cancelled));
    assert_pid_gone(&pid_file).await;

    fs::remove_file(&started_marker).unwrap();
    let older = run_usage_probe(&script, &environment(), limits(25_000), &control, 4).await;
    assert_eq!(older, Err(UsageProbeFailure::Cancelled));
    assert!(!started_marker.exists(), "a cancelled run must not spawn");
    assert!(!control.is_cancelled(6), "a later run is not cancelled");
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test -p needlbar-quota --test claude_usage_probe`
Expected: FAIL to compile with `unresolved import` for `run_usage_probe`.

- [ ] **Step 3: Update manifests**

In `Cargo.toml:22` change the tokio line to:

```toml
tokio = { version = "1", features = ["rt-multi-thread", "macros", "time", "process", "fs", "io-util", "sync"] }
```

`codex.rs` already uses `io-util` through feature unification; naming it and `sync` makes the dependency explicit.

In `crates/needlbar-quota/Cargo.toml` add to `[dependencies]`, and delete the `libc.workspace = true` line under `[target.'cfg(target_os = "macos")'.dependencies]`:

```toml
libc.workspace = true
tempfile.workspace = true
```

Keep `tempfile.workspace = true` under `[dev-dependencies]` as well.

- [ ] **Step 4: Write the locator**

`crates/needlbar-quota/src/providers/claude_cli.rs`:

```rust
//! Finds the user's installed `claude`. No shell and no `PATH` search, so shell
//! functions and aliases never apply.

use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
};

pub struct ClaudeCliLocator {
    candidates: Vec<PathBuf>,
}

impl ClaudeCliLocator {
    pub fn for_home(home: &Path) -> Self {
        Self::with_candidates(vec![
            home.join(".local/bin/claude"),
            PathBuf::from("/opt/homebrew/bin/claude"),
            PathBuf::from("/usr/local/bin/claude"),
        ])
    }

    pub fn with_candidates(candidates: Vec<PathBuf>) -> Self {
        Self { candidates }
    }

    pub fn candidates(&self) -> &[PathBuf] {
        &self.candidates
    }

    /// The first candidate that resolves to an executable regular file.
    pub fn locate(&self) -> Option<PathBuf> {
        self.candidates
            .iter()
            .find_map(|candidate| executable_regular_file(candidate))
    }
}

fn executable_regular_file(path: &Path) -> Option<PathBuf> {
    let resolved = fs::canonicalize(path).ok()?;
    let metadata = fs::metadata(&resolved).ok()?;
    (metadata.is_file() && metadata.permissions().mode() & 0o111 != 0).then_some(resolved)
}
```

- [ ] **Step 5: Write the probe**

`crates/needlbar-quota/src/providers/claude_usage_probe.rs`:

```rust
//! Runs `/usage` under fixed limits and returns its stdout bytes or a typed
//! failure. It knows nothing about the report format.

use std::{
    ffi::OsString,
    path::Path,
    process::{ExitStatus, Stdio},
    sync::{Arc, LazyLock, Mutex},
    time::Duration,
};

use tokio::{
    io::AsyncReadExt,
    process::{Child, ChildStdout, Command},
    sync::Notify,
    time::{sleep, sleep_until, timeout, Instant},
};

pub const USAGE_PROBE_ARGUMENTS: [&str; 9] = [
    "-p",
    "/usage",
    "--no-session-persistence",
    "--strict-mcp-config",
    "--settings",
    r#"{"disableAllHooks":true}"#,
    "--output-format",
    "stream-json",
    "--verbose",
];

const USAGE_PROBE_PATH: &str = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
const TERMINATION_GRACE: Duration = Duration::from_millis(500);
/// A descendant can keep the stdout pipe open after `claude` itself exits.
const PIPE_DRAIN_GRACE: Duration = Duration::from_millis(250);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct UsageProbeLimits {
    pub deadline: Duration,
    pub max_stdout_bytes: usize,
}

impl Default for UsageProbeLimits {
    fn default() -> Self {
        Self {
            deadline: Duration::from_secs(30),
            max_stdout_bytes: 1024 * 1024,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UsageProbeFailure {
    LaunchFailed,
    ExitedUnsuccessfully,
    TimedOut,
    OutputTooLarge,
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UsageProbeEnvironment {
    values: Vec<(&'static str, OsString)>,
}

impl UsageProbeEnvironment {
    pub fn from_lookup(lookup: impl Fn(&str) -> Option<OsString>) -> Self {
        let mut values = Vec::new();
        for name in ["HOME", "USER", "LOGNAME", "TMPDIR"] {
            if let Some(value) = lookup(name) {
                values.push((name, value));
            }
        }
        values.push(("PATH", OsString::from(USAGE_PROBE_PATH)));
        if let Some(value) = lookup("CLAUDE_CONFIG_DIR").filter(|value| !value.is_empty()) {
            values.push(("CLAUDE_CONFIG_DIR", value));
        }
        Self { values }
    }

    pub fn from_process() -> Self {
        Self::from_lookup(|name| std::env::var_os(name))
    }

    pub fn pairs(&self) -> &[(&'static str, OsString)] {
        &self.values
    }
}

#[derive(Default)]
struct ControlState {
    cancelled_through: u64,
    active: Option<(u64, i32)>,
}

/// Cancels runs by ID. A cancel that arrives before a run registers still
/// applies, because the run checks the same state, and later runs have larger
/// IDs and are unaffected. `cancel_through` signals synchronously, so a run does
/// not outlive an app that exits right after asking.
#[derive(Default)]
pub struct UsageProbeControl {
    state: Mutex<ControlState>,
    changed: Notify,
}

static SHARED_CONTROL: LazyLock<Arc<UsageProbeControl>> =
    LazyLock::new(|| Arc::new(UsageProbeControl::new()));

impl UsageProbeControl {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn shared() -> Arc<Self> {
        Arc::clone(&SHARED_CONTROL)
    }

    pub fn cancel_through(&self, run_id: u64) {
        {
            let mut state = self.lock();
            state.cancelled_through = state.cancelled_through.max(run_id);
            if let Some((active_run, process_group)) = state.active {
                if active_run <= run_id {
                    signal_group(process_group, libc::SIGTERM);
                }
            }
        }
        self.changed.notify_waiters();
    }

    pub fn is_cancelled(&self, run_id: u64) -> bool {
        self.lock().cancelled_through >= run_id
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, ControlState> {
        self.state
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn register(&self, run_id: u64, process_group: i32) -> bool {
        let mut state = self.lock();
        if state.cancelled_through >= run_id {
            return false;
        }
        state.active = Some((run_id, process_group));
        true
    }

    fn unregister(&self) {
        self.lock().active = None;
    }

    async fn cancelled(&self, run_id: u64) {
        loop {
            // A `Notified` receives `notify_waiters` from the moment it exists.
            let notified = self.changed.notified();
            if self.is_cancelled(run_id) {
                return;
            }
            notified.await;
        }
    }
}

fn signal_group(process_group: i32, signal: i32) {
    // SAFETY: `kill` takes no pointers; a negative ID addresses the group this
    // module created with `process_group(0)`.
    unsafe {
        libc::kill(-process_group, signal);
    }
}

enum Stop {
    Exited(ExitStatus),
    WaitFailed,
    TimedOut,
    OutputTooLarge,
    Cancelled,
}

pub async fn run_usage_probe(
    executable: &Path,
    environment: &UsageProbeEnvironment,
    limits: UsageProbeLimits,
    control: &UsageProbeControl,
    run_id: u64,
) -> Result<Vec<u8>, UsageProbeFailure> {
    if control.is_cancelled(run_id) {
        return Err(UsageProbeFailure::Cancelled);
    }
    // Deleted when this function returns, on every path.
    let working_directory = tempfile::Builder::new()
        .prefix("needlbar-claude-usage-")
        .tempdir()
        .map_err(|_| UsageProbeFailure::LaunchFailed)?;
    let deadline = Instant::now() + limits.deadline;
    let mut command = Command::new(executable);
    command
        .args(USAGE_PROBE_ARGUMENTS)
        .current_dir(working_directory.path())
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .env_clear()
        .envs(environment.pairs().iter().map(|(name, value)| (*name, value)))
        .process_group(0)
        .kill_on_drop(true);
    let mut child = command
        .spawn()
        .map_err(|_| UsageProbeFailure::LaunchFailed)?;
    let process_group = child
        .id()
        .and_then(|id| i32::try_from(id).ok())
        .ok_or(UsageProbeFailure::LaunchFailed)?;
    let stdout = child.stdout.take().ok_or(UsageProbeFailure::LaunchFailed)?;
    let mut stderr = child.stderr.take().ok_or(UsageProbeFailure::LaunchFailed)?;
    if !control.register(run_id, process_group) {
        terminate_group(&mut child, process_group).await;
        return Err(UsageProbeFailure::Cancelled);
    }
    let stderr_drain = tokio::spawn(async move {
        let _ = tokio::io::copy(&mut stderr, &mut tokio::io::sink()).await;
    });

    let mut output = Vec::new();
    let stop = tokio::select! {
        biased;
        () = control.cancelled(run_id) => Stop::Cancelled,
        () = sleep_until(deadline) => Stop::TimedOut,
        stop = read_until_exit(&mut child, stdout, limits.max_stdout_bytes, &mut output) => stop,
    };
    if !matches!(stop, Stop::Exited(_)) {
        terminate_group(&mut child, process_group).await;
    }
    control.unregister();
    stderr_drain.abort();
    let _ = stderr_drain.await;

    match stop {
        Stop::Exited(status) if status.success() => Ok(output),
        Stop::Exited(_) | Stop::WaitFailed => Err(UsageProbeFailure::ExitedUnsuccessfully),
        Stop::TimedOut => Err(UsageProbeFailure::TimedOut),
        Stop::OutputTooLarge => Err(UsageProbeFailure::OutputTooLarge),
        Stop::Cancelled => Err(UsageProbeFailure::Cancelled),
    }
}

async fn read_until_exit(
    child: &mut Child,
    mut stdout: ChildStdout,
    limit: usize,
    output: &mut Vec<u8>,
) -> Stop {
    let mut buffer = [0_u8; 8192];
    let mut stdout_open = true;
    let mut status = None;
    loop {
        tokio::select! {
            read = stdout.read(&mut buffer), if stdout_open => match read {
                Ok(0) | Err(_) => stdout_open = false,
                Ok(count) => {
                    if output.len().saturating_add(count) > limit {
                        return Stop::OutputTooLarge;
                    }
                    output.extend_from_slice(&buffer[..count]);
                }
            },
            exited = child.wait(), if status.is_none() => match exited {
                Ok(exit_status) => status = Some(exit_status),
                Err(_) => return Stop::WaitFailed,
            },
            () = sleep(PIPE_DRAIN_GRACE), if status.is_some() && stdout_open => stdout_open = false,
        }
        if let (Some(exit_status), false) = (status, stdout_open) {
            return Stop::Exited(exit_status);
        }
    }
}

async fn terminate_group(child: &mut Child, process_group: i32) {
    signal_group(process_group, libc::SIGTERM);
    let _ = timeout(TERMINATION_GRACE, child.wait()).await;
    // Also reaches a descendant that ignored SIGTERM after its parent exited.
    signal_group(process_group, libc::SIGKILL);
    let _ = timeout(TERMINATION_GRACE, child.wait()).await;
}
```

In `crates/needlbar-quota/src/providers/mod.rs` add `pub mod claude_cli;` and `pub mod claude_usage_probe;`. In `crates/needlbar-quota/src/lib.rs` add:

```rust
pub use providers::claude_cli::ClaudeCliLocator;
pub use providers::claude_usage_probe::{
    run_usage_probe, UsageProbeControl, UsageProbeEnvironment, UsageProbeFailure, UsageProbeLimits,
    USAGE_PROBE_ARGUMENTS,
};
```

- [ ] **Step 6: Run test to verify it passes**

Run: `cargo test -p needlbar-quota --test claude_usage_probe`
Expected: PASS, 13 tests. Also run `cargo test -p needlbar-quota` to confirm `claude_credentials.rs` still builds with `libc` moved; expected PASS.

- [ ] **Step 7: Commit**

```bash
git add Cargo.toml Cargo.lock crates/needlbar-quota/Cargo.toml crates/needlbar-quota/src/providers/claude_cli.rs crates/needlbar-quota/src/providers/claude_usage_probe.rs crates/needlbar-quota/src/providers/mod.rs crates/needlbar-quota/src/lib.rs crates/needlbar-quota/tests/claude_usage_probe.rs
git commit -m "feat(quota): locate claude and run /usage under fixed limits

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

</content>
---

## Task 3: Provider, failure origins and run summary

**Files:**
- Create: `crates/needlbar-quota/src/providers/claude_usage_provider.rs`
- Modify: `crates/needlbar-quota/src/domain.rs:77-95,106-154`, `crates/needlbar-quota/src/providers/mod.rs`, `crates/needlbar-quota/src/lib.rs`
- Test: `crates/needlbar-quota/tests/claude_usage_provider.rs`

**Interfaces:**
- Consumes: `parse_usage_report_stream`, `ClaudeUsageReportOutcome`, `ClaudeUsageRowKind`, `ClaudeUsageRowSummary` (Task 1); `ClaudeCliLocator`, `run_usage_probe`, `UsageProbeEnvironment`, `UsageProbeLimits`, `UsageProbeFailure`, `UsageProbeControl` (Task 2).
- Produces: new `ClaudeQuotaFailureOrigin` cases `ClaudeCliNotFound`, `UsageReportNoUsage`, `UsageProbeTimedOut`, `UsageProbeOutputTooLarge`, `UsageProbeFailed`, `UsageReportRateLimited`, `UsageReportFormatChanged`; `QuotaError::claude_usage_report_cancelled()` and `is_claude_usage_report_cancelled()`; `pub struct ClaudeUsageProbeSummary { pub duration_ms: u64, pub row_kinds: Vec<ClaudeUsageRowKind>, pub unknown_row_count: u32, pub skipped_row_count: u32 }` (`Serialize`, camelCase); `pub struct ClaudeUsageReportRun { pub result: Result<ProviderQuotaSnapshot, QuotaError>, pub summary: Option<ClaudeUsageProbeSummary> }`; `ClaudeUsageReportProvider::{new(run_id: u64), with_parts(locator, environment, limits, control, run_id), run(&self) -> ClaudeUsageReportRun (async)}`.

- [ ] **Step 1: Write the failing test**

`crates/needlbar-quota/tests/claude_usage_provider.rs`:

```rust
use std::{
    ffi::OsString,
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::Arc,
    time::Duration,
};

use needlbar_quota::{
    ClaudeCliLocator, ClaudeQuotaFailureOrigin, ClaudeUsageReportProvider, ClaudeUsageReportRun,
    ClaudeUsageRowKind, ProviderId, QuotaErrorCode, UsageProbeControl, UsageProbeEnvironment,
    UsageProbeLimits,
};
use tempfile::TempDir;

const ALL_ROWS: &str = include_str!("../../../Fixtures/quota/claude/usage-report-all-rows.jsonl");
const WEEKLY_ONLY: &str =
    include_str!("../../../Fixtures/quota/claude/usage-report-weekly-only.jsonl");
const PREWARM: &str = "--needlbar-prewarm";

fn fake(directory: &Path, body: &str) -> PathBuf {
    let path = directory.join("claude");
    fs::write(
        &path,
        format!("#!/bin/sh\nif [ \"${{1:-}}\" = '{PREWARM}' ]; then exit 0; fi\n{body}\n"),
    )
    .unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o700)).unwrap();
    assert!(Command::new(&path)
        .arg(PREWARM)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .unwrap()
        .success());
    path
}

fn provider(candidates: Vec<PathBuf>, limits: UsageProbeLimits) -> ClaudeUsageReportProvider {
    ClaudeUsageReportProvider::with_parts(
        ClaudeCliLocator::with_candidates(candidates),
        UsageProbeEnvironment::from_lookup(|_| None::<OsString>),
        limits,
        Arc::new(UsageProbeControl::new()),
        1,
    )
}

async fn run_script(body: &str) -> ClaudeUsageReportRun {
    let temp = TempDir::new().unwrap();
    let script = fake(temp.path(), body);
    provider(vec![script], UsageProbeLimits::default()).run().await
}

async fn run_output(output: &str) -> ClaudeUsageReportRun {
    let temp = TempDir::new().unwrap();
    let source = temp.path().join("output.jsonl");
    fs::write(&source, output).unwrap();
    let script = fake(temp.path(), &format!("/bin/cat '{}'", source.display()));
    provider(vec![script], UsageProbeLimits::default()).run().await
}

fn assert_failure(run: &ClaudeUsageReportRun, code: QuotaErrorCode, origin: ClaudeQuotaFailureOrigin) {
    let error = run.result.as_ref().expect_err("expected a failure");
    assert_eq!(error.code, code);
    assert_eq!(error.provider, Some(ProviderId::Claude));
    assert_eq!(error.claude_failure_origin(), Some(origin));
}

#[tokio::test]
async fn a_full_report_becomes_a_claude_snapshot_with_a_summary() {
    let run = run_output(ALL_ROWS).await;
    let snapshot = run.result.expect("snapshot");
    assert_eq!(snapshot.provider, ProviderId::Claude);
    assert_eq!(snapshot.windows.len(), 3);
    let summary = run.summary.expect("summary");
    assert_eq!(
        summary.row_kinds,
        [
            ClaudeUsageRowKind::Session,
            ClaudeUsageRowKind::WeeklyAll,
            ClaudeUsageRowKind::WeeklyScoped
        ]
    );
    assert_eq!(summary.unknown_row_count, 0);
}

#[tokio::test]
async fn weekly_only_report_has_no_session_window() {
    let snapshot = run_output(WEEKLY_ONLY).await.result.expect("snapshot");
    assert!(snapshot.windows.iter().all(|window| window.id() != "claude.session"));
    assert_eq!(snapshot.windows.len(), 2);
}

#[tokio::test]
async fn a_missing_cli_is_not_installed() {
    let temp = TempDir::new().unwrap();
    let run = provider(vec![temp.path().join("absent")], UsageProbeLimits::default())
        .run()
        .await;
    assert_failure(&run, QuotaErrorCode::NotInstalled, ClaudeQuotaFailureOrigin::ClaudeCliNotFound);
    assert!(run.summary.is_some());
}

#[tokio::test]
async fn null_rate_limits_is_no_usage_not_a_schema_failure() {
    let run = run_output(r#"{"type":"assistant","usage_report":{"rate_limits":null}}"#).await;
    assert_failure(
        &run,
        QuotaErrorCode::RequiresAuthentication,
        ClaudeQuotaFailureOrigin::UsageReportNoUsage,
    );
}

#[tokio::test]
async fn no_report_is_format_changed() {
    let run = run_output(r#"{"type":"result","subtype":"success","result":"text"}"#).await;
    assert_failure(
        &run,
        QuotaErrorCode::SchemaChanged,
        ClaudeQuotaFailureOrigin::UsageReportFormatChanged,
    );
}

#[tokio::test]
async fn a_rate_limit_error_without_a_report_is_rate_limited() {
    let run = run_output(r#"{"type":"assistant","error":"rate_limit"}"#).await;
    assert_failure(
        &run,
        QuotaErrorCode::RateLimited,
        ClaudeQuotaFailureOrigin::UsageReportRateLimited,
    );
}

#[tokio::test]
async fn non_zero_exit_is_a_process_failure_even_with_a_report_in_its_output() {
    let run = run_script("printf '%s\\n' '{\"type\":\"assistant\",\"usage_report\":{\"rate_limits\":null}}'\nexit 1").await;
    assert_failure(
        &run,
        QuotaErrorCode::ProviderUnavailable,
        ClaudeQuotaFailureOrigin::UsageProbeFailed,
    );
}

#[tokio::test]
async fn timeout_and_oversized_output_are_typed_process_failures() {
    let temp = TempDir::new().unwrap();
    let slow = fake(temp.path(), "/bin/sleep 30");
    let run = provider(
        vec![slow],
        UsageProbeLimits {
            deadline: Duration::from_secs(1),
            ..UsageProbeLimits::default()
        },
    )
    .run()
    .await;
    assert_failure(
        &run,
        QuotaErrorCode::ProviderUnavailable,
        ClaudeQuotaFailureOrigin::UsageProbeTimedOut,
    );

    let large_directory = TempDir::new().unwrap();
    let large = fake(large_directory.path(), "/usr/bin/yes report");
    let run = provider(
        vec![large],
        UsageProbeLimits {
            deadline: Duration::from_secs(20),
            max_stdout_bytes: 64 * 1024,
        },
    )
    .run()
    .await;
    assert_failure(
        &run,
        QuotaErrorCode::ProviderUnavailable,
        ClaudeQuotaFailureOrigin::UsageProbeOutputTooLarge,
    );
}

#[tokio::test]
async fn a_cancelled_run_is_marked_and_describes_no_attempt() {
    let temp = TempDir::new().unwrap();
    let script = fake(temp.path(), "printf 'never'");
    let control = Arc::new(UsageProbeControl::new());
    control.cancel_through(7);
    let run = ClaudeUsageReportProvider::with_parts(
        ClaudeCliLocator::with_candidates(vec![script]),
        UsageProbeEnvironment::from_lookup(|_| None::<OsString>),
        UsageProbeLimits::default(),
        control,
        7,
    )
    .run()
    .await;
    let error = run.result.expect_err("cancelled");
    assert!(error.is_claude_usage_report_cancelled());
    assert_eq!(error.claude_failure_origin(), None);
    assert!(run.summary.is_none());
}

#[tokio::test]
async fn no_output_text_or_canary_reaches_any_surface() {
    let run = run_output(ALL_ROWS).await;
    let surfaces = format!(
        "{:?}{}{}",
        run.result,
        serde_json::to_string(run.result.as_ref().unwrap()).unwrap(),
        serde_json::to_string(run.summary.as_ref().unwrap()).unwrap()
    );
    for canary in [
        "SESSION-CANARY",
        "PATH-CANARY",
        "TEXT-CANARY",
        "RESULT-CANARY",
        "alice@example.com",
    ] {
        assert!(!surfaces.contains(canary), "{canary}");
    }
    let failed = run_output("{\"type\":\"result\",\"result\":\"TEXT-CANARY\"}").await;
    let error = failed.result.expect_err("format changed");
    assert!(!format!("{error:?}").contains("TEXT-CANARY"));
    assert!(!serde_json::to_string(&error).unwrap().contains("TEXT-CANARY"));
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test -p needlbar-quota --test claude_usage_provider`
Expected: FAIL to compile with `unresolved import` for `ClaudeUsageReportProvider`.

- [ ] **Step 3: Extend the domain**

In `crates/needlbar-quota/src/domain.rs`, insert before `OtherFailure,` in `ClaudeQuotaFailureOrigin`:

```rust
    /// No executable `claude` at any fixed location.
    ClaudeCliNotFound,
    /// `rate_limits` was null, or `limits` was null or empty.
    UsageReportNoUsage,
    UsageProbeTimedOut,
    UsageProbeOutputTooLarge,
    /// The process could not start or exited unsuccessfully.
    UsageProbeFailed,
    UsageReportRateLimited,
    /// A run finished without a usable `usage_report`.
    UsageReportFormatChanged,
```

Add a field to `QuotaError` after `claude_credential_busy`:

```rust
    #[serde(skip)]
    claude_usage_report_cancelled: bool,
```

Initialize it to `false` in `QuotaError::new`, and add after `is_claude_credential_busy`:

```rust
    /// A run stopped because the app is stopping. It describes no outcome, so
    /// collectors drop it rather than report a Claude failure.
    pub const fn claude_usage_report_cancelled() -> Self {
        let mut error = Self::new(
            Some(ProviderId::Claude),
            QuotaErrorCode::ProviderUnavailable,
            "The Claude usage check was cancelled.",
        );
        error.claude_usage_report_cancelled = true;
        error
    }

    pub const fn is_claude_usage_report_cancelled(&self) -> bool {
        self.claude_usage_report_cancelled
    }
```

- [ ] **Step 4: Write the provider**

`crates/needlbar-quota/src/providers/claude_usage_provider.rs`:

```rust
//! Claude quota from `/usage` run by the user's installed `claude`.

use std::{env, path::PathBuf, sync::Arc, time::Instant};

use serde::Serialize;

use super::{
    claude_cli::ClaudeCliLocator,
    claude_usage_probe::{
        run_usage_probe, UsageProbeControl, UsageProbeEnvironment, UsageProbeFailure,
        UsageProbeLimits,
    },
    claude_usage_report::{
        parse_usage_report_stream, ClaudeUsageReportOutcome, ClaudeUsageRowKind,
        ClaudeUsageRowSummary,
    },
};
use crate::{ClaudeQuotaFailureOrigin, ProviderId, ProviderQuotaSnapshot, QuotaError, QuotaErrorCode};

/// What diagnostics may record about a run: closed values and counts only.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClaudeUsageProbeSummary {
    pub duration_ms: u64,
    pub row_kinds: Vec<ClaudeUsageRowKind>,
    pub unknown_row_count: u32,
    pub skipped_row_count: u32,
}

pub struct ClaudeUsageReportRun {
    pub result: Result<ProviderQuotaSnapshot, QuotaError>,
    pub summary: Option<ClaudeUsageProbeSummary>,
}

pub struct ClaudeUsageReportProvider {
    locator: ClaudeCliLocator,
    environment: UsageProbeEnvironment,
    limits: UsageProbeLimits,
    control: Arc<UsageProbeControl>,
    run_id: u64,
}

impl ClaudeUsageReportProvider {
    pub fn new(run_id: u64) -> Self {
        let home = env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("/nonexistent"));
        Self::with_parts(
            ClaudeCliLocator::for_home(&home),
            UsageProbeEnvironment::from_process(),
            UsageProbeLimits::default(),
            UsageProbeControl::shared(),
            run_id,
        )
    }

    pub fn with_parts(
        locator: ClaudeCliLocator,
        environment: UsageProbeEnvironment,
        limits: UsageProbeLimits,
        control: Arc<UsageProbeControl>,
        run_id: u64,
    ) -> Self {
        Self {
            locator,
            environment,
            limits,
            control,
            run_id,
        }
    }

    pub async fn run(&self) -> ClaudeUsageReportRun {
        let started = Instant::now();
        let Some(executable) = self.locator.locate() else {
            return finished(
                Err(failure(
                    QuotaErrorCode::NotInstalled,
                    "Claude Code was not found on this Mac.",
                    ClaudeQuotaFailureOrigin::ClaudeCliNotFound,
                )),
                ClaudeUsageRowSummary::default(),
                started,
            );
        };
        let output = run_usage_probe(
            &executable,
            &self.environment,
            self.limits,
            &self.control,
            self.run_id,
        )
        .await;
        let bytes = match output {
            Ok(bytes) => bytes,
            Err(UsageProbeFailure::Cancelled) => {
                return ClaudeUsageReportRun {
                    result: Err(QuotaError::claude_usage_report_cancelled()),
                    summary: None,
                };
            }
            Err(probe_failure) => {
                return finished(
                    Err(from_probe_failure(probe_failure)),
                    ClaudeUsageRowSummary::default(),
                    started,
                );
            }
        };
        let (result, rows) = match parse_usage_report_stream(&bytes) {
            ClaudeUsageReportOutcome::Windows { windows, rows } => (
                Ok(ProviderQuotaSnapshot {
                    provider: ProviderId::Claude,
                    windows,
                }),
                rows,
            ),
            ClaudeUsageReportOutcome::NoUsageAvailable { rows } => (
                Err(failure(
                    QuotaErrorCode::RequiresAuthentication,
                    "Claude Code reported no usage.",
                    ClaudeQuotaFailureOrigin::UsageReportNoUsage,
                )),
                rows,
            ),
            ClaudeUsageReportOutcome::RateLimited => (
                Err(failure(
                    QuotaErrorCode::RateLimited,
                    "The Claude usage check was rate limited.",
                    ClaudeQuotaFailureOrigin::UsageReportRateLimited,
                )),
                ClaudeUsageRowSummary::default(),
            ),
            ClaudeUsageReportOutcome::FormatChanged { rows } => (
                Err(failure(
                    QuotaErrorCode::SchemaChanged,
                    "Claude usage data was not in the expected format.",
                    ClaudeQuotaFailureOrigin::UsageReportFormatChanged,
                )),
                rows,
            ),
        };
        finished(result, rows, started)
    }
}

fn finished(
    result: Result<ProviderQuotaSnapshot, QuotaError>,
    rows: ClaudeUsageRowSummary,
    started: Instant,
) -> ClaudeUsageReportRun {
    ClaudeUsageReportRun {
        result,
        summary: Some(ClaudeUsageProbeSummary {
            duration_ms: u64::try_from(started.elapsed().as_millis()).unwrap_or(u64::MAX),
            row_kinds: rows.row_kinds,
            unknown_row_count: rows.unknown_row_count,
            skipped_row_count: rows.skipped_row_count,
        }),
    }
}

fn failure(
    code: QuotaErrorCode,
    message: &'static str,
    origin: ClaudeQuotaFailureOrigin,
) -> QuotaError {
    QuotaError::new(Some(ProviderId::Claude), code, message).with_claude_failure_origin(origin)
}

fn from_probe_failure(probe_failure: UsageProbeFailure) -> QuotaError {
    let (message, origin) = match probe_failure {
        UsageProbeFailure::TimedOut => (
            "The Claude usage check timed out.",
            ClaudeQuotaFailureOrigin::UsageProbeTimedOut,
        ),
        UsageProbeFailure::OutputTooLarge => (
            "The Claude usage check produced too much output.",
            ClaudeQuotaFailureOrigin::UsageProbeOutputTooLarge,
        ),
        UsageProbeFailure::LaunchFailed
        | UsageProbeFailure::ExitedUnsuccessfully
        | UsageProbeFailure::Cancelled => (
            "The Claude usage check did not finish.",
            ClaudeQuotaFailureOrigin::UsageProbeFailed,
        ),
    };
    failure(QuotaErrorCode::ProviderUnavailable, message, origin)
}
```

In `crates/needlbar-quota/src/providers/mod.rs` add `pub mod claude_usage_provider;`. In `crates/needlbar-quota/src/lib.rs` add:

```rust
pub use providers::claude_usage_provider::{
    ClaudeUsageProbeSummary, ClaudeUsageReportProvider, ClaudeUsageReportRun,
};
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cargo test -p needlbar-quota --test claude_usage_provider`
Expected: PASS, 10 tests.

- [ ] **Step 6: Commit**

```bash
git add crates/needlbar-quota/src/providers/claude_usage_provider.rs crates/needlbar-quota/src/providers/mod.rs crates/needlbar-quota/src/lib.rs crates/needlbar-quota/src/domain.rs crates/needlbar-quota/tests/claude_usage_provider.rs
git commit -m "feat(quota): add the Claude usage report provider and failure origins

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 4: Bridge export, cancel export and diagnostics summary

**Files:**
- Modify: `crates/needlbar-bridge/src/quota.rs`, `crates/needlbar-bridge/src/lib.rs`, `crates/needlbar-bridge/src/diagnostics.rs`, `crates/needlbar-bridge/src/test_runtime.rs`, `Sources/CNeedlbar/include/needlbar.h`
- Test: `crates/needlbar-bridge/tests/quota_contract.rs`, `crates/needlbar-bridge/tests/ffi_contract.rs`, `crates/needlbar-bridge/src/lib.rs` (unit tests)

**Interfaces:**
- Consumes: `ClaudeUsageReportProvider`, `ClaudeUsageReportRun`, `ClaudeUsageProbeSummary`, `UsageProbeControl`, new origins (Task 3).
- Produces: C `const char *needlbar_claude_usage_report_quota_snapshot_json(uint64_t run_id);` and `void needlbar_claude_usage_report_cancel_through(uint64_t run_id);`. Rust `quota::ClaudeUsageReportSource` with `run_usage_report`, `quota::collect_claude_usage_report(run_id)`, `quota::collect_claude_usage_report_with_source(source)`, `QuotaCollection.claude_usage_probe`, `diagnostics::record_claude_usage_probe(Option<ClaudeUsageProbeSummary>)`, `test_runtime::claude_usage_report_source()`. Diagnostics JSON gains optional `claudeUsageProbe` on the Claude provider, with `durationMs`, `rowKinds`, `unknownRowCount`, `skippedRowCount`.

- [ ] **Step 1: Write the failing tests**

Append to `crates/needlbar-bridge/tests/quota_contract.rs`, and add `collect_claude_usage_report_with_source, ClaudeUsageReportSource` to the `needlbar_bridge::quota` import and `ClaudeUsageProbeSummary, ClaudeUsageReportRun, ClaudeUsageRowKind` to the `needlbar_quota` import:

```rust
struct ScriptedUsageReportSource {
    result: Result<ProviderQuotaSnapshot, QuotaError>,
    summary: Option<ClaudeUsageProbeSummary>,
}

impl ClaudeUsageReportSource for ScriptedUsageReportSource {
    fn run_usage_report<'a>(
        &'a self,
    ) -> Pin<Box<dyn Future<Output = ClaudeUsageReportRun> + Send + 'a>> {
        Box::pin(async move {
            ClaudeUsageReportRun {
                result: self.result.clone(),
                summary: self.summary.clone(),
            }
        })
    }
}

fn fixture_summary() -> ClaudeUsageProbeSummary {
    ClaudeUsageProbeSummary {
        duration_ms: 1_500,
        row_kinds: vec![ClaudeUsageRowKind::WeeklyAll],
        unknown_row_count: 0,
        skipped_row_count: 0,
    }
}

#[tokio::test]
async fn usage_report_collection_uses_only_claude_and_carries_its_summary() {
    let collection = collect_claude_usage_report_with_source(Arc::new(ScriptedUsageReportSource {
        result: Ok(successful_snapshot(ProviderId::Claude, "claude.weekly")),
        summary: Some(fixture_summary()),
    }))
    .await;
    assert!(collection.claude_attempted);
    assert_eq!(collection.claude_usage_probe, Some(fixture_summary()));
    let value = serde_json::to_value(envelope_from_collection(collection)).unwrap();
    assert_eq!(value["data"]["providers"].as_array().map(Vec::len), Some(1));
    assert_eq!(value["data"]["providers"][0]["provider"], "claude");
    assert_eq!(value["errors"], serde_json::json!([]));
    assert!(value.to_string().find("durationMs").is_none(), "the summary stays out of the quota envelope");
}

#[tokio::test]
async fn a_cancelled_usage_report_is_dropped_and_describes_no_attempt() {
    let collection = collect_claude_usage_report_with_source(Arc::new(ScriptedUsageReportSource {
        result: Err(QuotaError::claude_usage_report_cancelled()),
        summary: None,
    }))
    .await;
    assert!(collection.providers.is_empty());
    assert!(collection.errors.is_empty());
    assert!(!collection.claude_attempted);
    assert_eq!(collection.claude_failure_origin, None);
}
```

In `crates/needlbar-bridge/tests/ffi_contract.rs`, add inside `provider_verification_exports_are_declared_in_the_public_c_header`:

```rust
    assert!(header.contains("const char *needlbar_claude_usage_report_quota_snapshot_json(uint64_t run_id);"));
    assert!(header.contains("void needlbar_claude_usage_report_cancel_through(uint64_t run_id);"));
    let usage_report: unsafe extern "C" fn(u64) -> *const std::os::raw::c_char =
        needlbar_bridge::needlbar_claude_usage_report_quota_snapshot_json;
    let cancel_usage_report: extern "C" fn(u64) =
        needlbar_bridge::needlbar_claude_usage_report_cancel_through;
    let _ = (usage_report, cancel_usage_report);
```

Add to the `#[cfg(test)] mod tests` in `crates/needlbar-bridge/src/lib.rs`:

```rust
    #[test]
    fn diagnostics_serialize_the_run_summary_as_closed_values_and_counts() {
        use needlbar_quota::{ClaudeUsageProbeSummary, ClaudeUsageRowKind};

        let _state_guard = DIAGNOSTICS_STATE_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        diagnostics::record_claude_usage_probe(Some(ClaudeUsageProbeSummary {
            duration_ms: 1_500,
            row_kinds: vec![ClaudeUsageRowKind::WeeklyAll, ClaudeUsageRowKind::WeeklyScoped],
            unknown_row_count: 2,
            skipped_row_count: 1,
        }));
        let json = serde_json::to_value(Envelope::success(
            diagnostics::DiagnosticsSnapshot::from_recorded_outcomes(),
        ))
        .expect("diagnostics JSON");
        assert_eq!(
            json["data"]["providers"][0]["claudeUsageProbe"],
            serde_json::json!({
                "durationMs": 1500,
                "rowKinds": ["weeklyAll", "weeklyScoped"],
                "unknownRowCount": 2,
                "skippedRowCount": 1,
            })
        );
        assert!(json["data"]["providers"][1].get("claudeUsageProbe").is_none());

        diagnostics::record_claude_usage_probe(None);
        let cleared = serde_json::to_value(Envelope::success(
            diagnostics::DiagnosticsSnapshot::from_recorded_outcomes(),
        ))
        .expect("diagnostics JSON");
        assert!(cleared["data"]["providers"][0].get("claudeUsageProbe").is_none());
    }
```

Extend the array in `diagnostics_serializes_every_closed_claude_failure_origin_by_its_stable_name` (`crates/needlbar-bridge/src/lib.rs:786-810`) with:

```rust
            (Origin::ClaudeCliNotFound, "claudeCliNotFound"),
            (Origin::UsageReportNoUsage, "usageReportNoUsage"),
            (Origin::UsageProbeTimedOut, "usageProbeTimedOut"),
            (Origin::UsageProbeOutputTooLarge, "usageProbeOutputTooLarge"),
            (Origin::UsageProbeFailed, "usageProbeFailed"),
            (Origin::UsageReportRateLimited, "usageReportRateLimited"),
            (Origin::UsageReportFormatChanged, "usageReportFormatChanged"),
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cargo test -p needlbar-bridge --features bridge-test-runtime --test quota_contract --test ffi_contract`
Expected: FAIL to compile with `no ClaudeUsageReportSource in quota`.

- [ ] **Step 3: Implement collection in `crates/needlbar-bridge/src/quota.rs`**

Extend the `needlbar_quota` import with `ClaudeUsageProbeSummary, ClaudeUsageReportProvider, ClaudeUsageReportRun, UsageProbeControl`. Add `pub claude_usage_probe: Option<ClaudeUsageProbeSummary>,` to `QuotaCollection`, and `claude_usage_probe: None,` to the literal in `collection_from_results`. Change the busy match arm to:

```rust
            // The read did not run or was cancelled, so there is no Claude outcome to report.
            Err(error)
                if error.is_claude_credential_busy() || error.is_claude_usage_report_cancelled() => {}
```

Add after `impl ClaudeUserInitiatedQuotaSource for ClaudeQuotaProvider`:

```rust
/// The Claude quota run. A dedicated collection, so a run of up to 30 seconds
/// never holds the Codex and Cursor refresh.
pub trait ClaudeUsageReportSource: Send + Sync {
    fn run_usage_report<'a>(
        &'a self,
    ) -> Pin<Box<dyn Future<Output = ClaudeUsageReportRun> + Send + 'a>>;
}

impl ClaudeUsageReportSource for ClaudeUsageReportProvider {
    fn run_usage_report<'a>(
        &'a self,
    ) -> Pin<Box<dyn Future<Output = ClaudeUsageReportRun> + Send + 'a>> {
        Box::pin(ClaudeUsageReportProvider::run(self))
    }
}

pub async fn collect_claude_usage_report(run_id: u64) -> QuotaCollection {
    #[cfg(feature = "bridge-test-runtime")]
    {
        let _ = run_id;
        if let Some(source) = crate::test_runtime::claude_usage_report_source() {
            return collect_claude_usage_report_with_source(source).await;
        }
        test_runtime_unavailable_collection()
    }
    #[cfg(not(feature = "bridge-test-runtime"))]
    {
        collect_claude_usage_report_with_source(Arc::new(ClaudeUsageReportProvider::new(run_id)))
            .await
    }
}

pub async fn collect_claude_usage_report_with_source(
    source: Arc<dyn ClaudeUsageReportSource>,
) -> QuotaCollection {
    let run = source.run_usage_report().await;
    let mut collection = collection_from_results([run.result]);
    collection.claude_usage_probe = run.summary;
    collection
}

pub fn cancel_claude_usage_report_through(run_id: u64) {
    UsageProbeControl::shared().cancel_through(run_id);
}
```

- [ ] **Step 4: Add the exports in `crates/needlbar-bridge/src/lib.rs`**

After `needlbar_claude_user_initiated_quota_snapshot_json`:

```rust
/// # Safety
///
/// The returned non-null pointer is Rust-owned and must be passed exactly once
/// to [`needlbar_free_string`]. `run_id` is at least 1 and larger than any ID
/// already passed to [`needlbar_claude_usage_report_cancel_through`].
#[no_mangle]
pub unsafe extern "C" fn needlbar_claude_usage_report_quota_snapshot_json(
    run_id: u64,
) -> *const c_char {
    cursor_credential_cleanup::schedule_obsolete_cursor_session_cleanup();
    let attempted_at = Utc::now().to_rfc3339_opts(SecondsFormat::Secs, true);
    ffi_envelope(|| {
        quota_operation_envelope(
            move || claude_usage_report_quota_envelope(run_id),
            &attempted_at,
            true,
        )
    })
}

/// Cancels every run whose ID is at most `run_id`, including one that has not
/// started yet. It signals the process group before returning.
#[no_mangle]
pub extern "C" fn needlbar_claude_usage_report_cancel_through(run_id: u64) {
    let _ = catch_unwind(|| quota::cancel_claude_usage_report_through(run_id));
}
```

Add next to `claude_preflight_quota_envelope`:

```rust
fn claude_usage_report_quota_envelope(run_id: u64) -> Envelope<quota::QuotaPayload> {
    diagnostics::record_claude_usage_probe(None);
    match collect_quota_on_bridge_thread(move || {
        Box::pin(quota::collect_claude_usage_report(run_id))
    }) {
        Ok(mut collection) => {
            diagnostics::record_claude_usage_probe(collection.claude_usage_probe.take());
            quota::envelope_from_collection(collection)
        }
        Err(error) => Envelope::failure(error),
    }
}
```

- [ ] **Step 5: Record the summary in `crates/needlbar-bridge/src/diagnostics.rs`**

Change the import to `use needlbar_quota::{ClaudeQuotaFailureOrigin, ClaudeUsageProbeSummary};`. Add to `ProviderDiagnostic` after `claude_quota_failure_origin`:

```rust
    #[serde(skip_serializing_if = "Option::is_none")]
    claude_usage_probe: Option<ClaudeUsageProbeSummary>,
```

Set `claude_usage_probe: None,` in `ProviderDiagnostic::new`. Add `claude_usage_probe: Option<ClaudeUsageProbeSummary>,` to `RecordedOutcomes`. In `from_recorded_outcomes`, add to the `ProviderDiagnostic` literal:

```rust
                        claude_usage_probe: if provider == DiagnosticProvider::Claude {
                            observations.claude_usage_probe.clone()
                        } else {
                            None
                        },
```

Add a function after `record_partial_quota`:

```rust
/// The summary of the latest Claude usage report run: closed values and counts.
pub fn record_claude_usage_probe(summary: Option<ClaudeUsageProbeSummary>) {
    RECORDED_OUTCOMES
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .claude_usage_probe = summary;
}
```

- [ ] **Step 6: Add the test-runtime source in `crates/needlbar-bridge/src/test_runtime.rs`**

Add after `claude_user_initiated_source`. Task 11 replaces this adapter with direct sources.

```rust
/// Reuses the existing Claude fixtures for the usage report export.
pub fn claude_usage_report_source() -> Option<Arc<dyn quota::ClaudeUsageReportSource>> {
    Some(Arc::new(FixtureUsageReportSource {
        fixture: claude_user_initiated_source()?,
    }))
}

struct FixtureUsageReportSource {
    fixture: Arc<dyn quota::ClaudeUserInitiatedQuotaSource>,
}

impl quota::ClaudeUsageReportSource for FixtureUsageReportSource {
    fn run_usage_report<'a>(
        &'a self,
    ) -> std::pin::Pin<
        Box<dyn std::future::Future<Output = needlbar_quota::ClaudeUsageReportRun> + Send + 'a>,
    > {
        Box::pin(async move {
            needlbar_quota::ClaudeUsageReportRun {
                result: self
                    .fixture
                    .fetch_with_credential_access(needlbar_quota::ClaudeCredentialAccess::BackgroundNoUI)
                    .await,
                summary: Some(needlbar_quota::ClaudeUsageProbeSummary {
                    duration_ms: 1,
                    row_kinds: vec![needlbar_quota::ClaudeUsageRowKind::Session],
                    unknown_row_count: 0,
                    skipped_row_count: 0,
                }),
            }
        })
    }
}
```

- [ ] **Step 7: Declare the exports**

In `Sources/CNeedlbar/include/needlbar.h` add `#include <stdint.h>` after the include guard, and after the Codex declaration:

```c
// Runs `/usage` through the user's installed claude. Blocks for at most about
// 31 seconds. Ownership matches needlbar_quota_snapshot_json. run_id is at
// least 1 and larger than any ID already passed to the cancel call.
const char *needlbar_claude_usage_report_quota_snapshot_json(uint64_t run_id);
// Cancels every run with an ID at most run_id, including one not yet started.
void needlbar_claude_usage_report_cancel_through(uint64_t run_id);
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `cargo test -p needlbar-bridge --features bridge-test-runtime`
Expected: PASS, including the new `quota_contract`, `ffi_contract` and unit tests.

- [ ] **Step 9: Commit**

```bash
git add crates/needlbar-bridge/src/quota.rs crates/needlbar-bridge/src/lib.rs crates/needlbar-bridge/src/diagnostics.rs crates/needlbar-bridge/src/test_runtime.rs crates/needlbar-bridge/tests/quota_contract.rs crates/needlbar-bridge/tests/ffi_contract.rs Sources/CNeedlbar/include/needlbar.h
git commit -m "feat(bridge): export the Claude usage report run and its cancel call

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 5: Swift bridge, repository and diagnostics decoding

**Files:**
- Modify: `Sources/NeedlbarCore/Bridge/RustBridge.swift`, `Sources/NeedlbarCore/Repositories/QuotaRepository.swift`, `Sources/NeedlbarCore/Diagnostics/DiagnosticsSnapshot.swift`
- Test: `Tests/NeedlbarCoreTests/BridgeDecodingTests.swift`, `Tests/NeedlbarCoreTests/DiagnosticsTests.swift`

**Interfaces:**
- Consumes: the C exports (Task 4); diagnostics JSON `claudeUsageProbe`.
- Produces: `RustBridge.claudeUsageReportEnvelope(runID: UInt64) throws -> BridgeEnvelope<BridgeQuotaPayload>`, `RustBridge.cancelClaudeUsageReport(through: UInt64)`; init params `claudeUsageReportQuotaCall: @Sendable (UInt64) -> UnsafePointer<CChar>?` and `claudeUsageReportCancelCall: @Sendable (UInt64) -> Void`; `QuotaRefreshIntent.claudeUsageReport(runID: UInt64)`; `QuotaRepository.cancelClaudeUsageReport(through: UInt64)` with a no-op default; `ClaudeUsageRowKind` (`session`, `weeklyAll`, `weeklyScoped`); `ClaudeUsageProbeDiagnostics { durationMs: UInt64, rowKinds: [ClaudeUsageRowKind], unknownRowCount: Int, skippedRowCount: Int, logFields: String }`; `ProviderDiagnostics.claudeUsageProbe`; new `ClaudeQuotaFailureOrigin` cases; `QuotaDiagnosticsSource.usageReport`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/NeedlbarCoreTests/BridgeDecodingTests.swift`:

```swift
@Test func claudeUsageReportRefreshPassesTheRunIDUsesOnlyItsBridgeCallAndFreesOnce() throws {
    let calls = CallRecorder()
    let frees = FreeRecorder()
    let returnedPointer = try CStringPointer(quotaCString(provider: "claude"))
    let bridge = RustBridge(
        quotaCall: { calls.record("background"); return quotaCString(provider: "claude") },
        claudeUsageReportQuotaCall: { runID in calls.record("report-\(runID)"); return returnedPointer.pointer },
        codexQuotaCall: { calls.record("codex"); return quotaCString(provider: "codex") },
        free: { frees.release($0) }
    )

    let result = try RustQuotaRepository(bridge: bridge).refresh(intent: .claudeUsageReport(runID: 42))

    #expect(calls.values == ["report-42"])
    #expect(Set(result.snapshots.keys) == [.claude])
    #expect(frees.count == 1)
}

@Test func claudeUsageReportCancelReachesTheBridgeWithTheRunID() {
    let calls = CallRecorder()
    let bridge = RustBridge(claudeUsageReportCancelCall: { runID in calls.record("cancel-\(runID)") })
    RustQuotaRepository(bridge: bridge).cancelClaudeUsageReport(through: 9)
    #expect(calls.values == ["cancel-9"])
}
```

Append to `Tests/NeedlbarCoreTests/DiagnosticsTests.swift`:

```swift
@Test func diagnosticsDecoderAcceptsTheUsageReportSourceOriginsAndRunSummary() throws {
    for origin in [
        "claudeCliNotFound", "usageReportNoUsage", "usageProbeTimedOut", "usageProbeOutputTooLarge",
        "usageProbeFailed", "usageReportRateLimited", "usageReportFormatChanged",
    ] {
        let payload = """
        {"schemaVersion":"needlbar.v1","ok":true,"generatedAt":"2026-11-03T12:00:00Z","data":{"providers":[{"provider":"claude","usageStatus":"available","quotaStatus":"error","usageSource":"local","quotaSource":"usageReport","lastAttemptAt":"2026-11-03T11:59:59Z","claudeQuotaFailureOrigin":"\(origin)","claudeUsageProbe":{"durationMs":1832,"rowKinds":["weeklyAll","weeklyScoped"],"unknownRowCount":1,"skippedRowCount":2}}]},"errors":[]}
        """
        let provider = try #require(BridgeDecoder().decodeDiagnosticsEnvelope(Data(payload.utf8)).data?.providers.first)
        #expect(provider.claudeQuotaFailureOrigin?.rawValue == origin)
        #expect(provider.quotaSource == .usageReport)
        #expect(provider.claudeUsageProbe == ClaudeUsageProbeDiagnostics(
            durationMs: 1_832, rowKinds: [.weeklyAll, .weeklyScoped], unknownRowCount: 1, skippedRowCount: 2))
        #expect(provider.claudeUsageProbe?.logFields == "durationMs=1832 rows=weeklyAll,weeklyScoped unknownRows=1 skippedRows=2")
    }
}

@Test func anEmptyRunSummaryLogsNoRows() {
    #expect(ClaudeUsageProbeDiagnostics(durationMs: 3, rowKinds: [], unknownRowCount: 0, skippedRowCount: 0).logFields
        == "durationMs=3 rows=none unknownRows=0 skippedRows=0")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make swift-test SWIFT_TEST_FILTER=claudeUsageReport`
Expected: FAIL to compile with `extra argument 'claudeUsageReportQuotaCall'`.

- [ ] **Step 3: Extend `RustBridge`**

Add stored properties, init parameters with defaults, assignments and methods:

```swift
    private let claudeUsageReportQuotaCall: @Sendable (UInt64) -> UnsafePointer<CChar>?
    private let claudeUsageReportCancelCall: @Sendable (UInt64) -> Void
```

```swift
        claudeUsageReportQuotaCall: @escaping @Sendable (UInt64) -> UnsafePointer<CChar>? = { needlbar_claude_usage_report_quota_snapshot_json($0) },
        claudeUsageReportCancelCall: @escaping @Sendable (UInt64) -> Void = { needlbar_claude_usage_report_cancel_through($0) },
```

Place these two parameters directly after `claudeUserInitiatedQuotaCall`.

```swift
    /// Blocks for the whole run, so call it off the cooperative pool.
    public func claudeUsageReportEnvelope(runID: UInt64) throws -> BridgeEnvelope<BridgeQuotaPayload> {
        let call = claudeUsageReportQuotaCall
        return try decodeCString({ call(runID) }, decode: decoder.decodeQuotaEnvelope)
    }

    public func cancelClaudeUsageReport(through runID: UInt64) {
        claudeUsageReportCancelCall(runID)
    }
```

- [ ] **Step 4: Extend `QuotaRepository.swift`**

```swift
public enum QuotaRefreshIntent: Equatable, Sendable {
    case backgroundAll
    case claudePreflight
    case userInitiated(provider: ProviderID)
    /// One `claude -p /usage` run. `runID` lets a later cancel reach it even
    /// before it starts.
    case claudeUsageReport(runID: UInt64)
}

extension QuotaRefreshIntent {
    var includesClaude: Bool {
        switch self {
        case .backgroundAll, .claudePreflight, .userInitiated(provider: .claude), .claudeUsageReport: true
        case .userInitiated: false
        }
    }
}

public protocol QuotaRepository: Sendable {
    func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult
    func cancelClaudeUsageReport(through runID: UInt64)
}

public extension QuotaRepository {
    func refresh() throws -> QuotaRefreshResult {
        try refresh(intent: .backgroundAll)
    }

    func cancelClaudeUsageReport(through runID: UInt64) {}
}
```

In `RustQuotaRepository.refresh(intent:)` add:

```swift
        case .claudeUsageReport(let runID):
            return try refreshDedicated(bridge.claudeUsageReportEnvelope(runID: runID), for: .claude)
```

and to the struct:

```swift
    public func cancelClaudeUsageReport(through runID: UInt64) {
        bridge.cancelClaudeUsageReport(through: runID)
    }
```

- [ ] **Step 5: Extend `DiagnosticsSnapshot.swift`**

Add to `ProviderDiagnostics` `public let claudeUsageProbe: ClaudeUsageProbeDiagnostics?`, add `claudeUsageProbe` to `CodingKeys`, and decode it with `decodeIfPresent` in `init(from:)`. Add `case usageReport` to `QuotaDiagnosticsSource` and `case Self.usageReport.rawValue: self = .usageReport` to its decoder. Add the seven cases to `ClaudeQuotaFailureOrigin` before `otherFailure`:

```swift
    case claudeCliNotFound
    /// `rate_limits` was null, or `limits` was null or empty.
    case usageReportNoUsage
    case usageProbeTimedOut
    case usageProbeOutputTooLarge
    /// The process could not start or exited unsuccessfully.
    case usageProbeFailed
    case usageReportRateLimited
    /// A run finished without a usable `usage_report`.
    case usageReportFormatChanged
```

Append:

```swift
public enum ClaudeUsageRowKind: String, Decodable, Sendable, Equatable {
    case session
    case weeklyAll
    case weeklyScoped
}

/// What is recorded about a `/usage` run: closed values and counts, never text.
public struct ClaudeUsageProbeDiagnostics: Decodable, Sendable, Equatable {
    public let durationMs: UInt64
    public let rowKinds: [ClaudeUsageRowKind]
    public let unknownRowCount: Int
    public let skippedRowCount: Int

    public init(durationMs: UInt64, rowKinds: [ClaudeUsageRowKind], unknownRowCount: Int, skippedRowCount: Int) {
        self.durationMs = durationMs
        self.rowKinds = rowKinds
        self.unknownRowCount = unknownRowCount
        self.skippedRowCount = skippedRowCount
    }

    public var logFields: String {
        let rows = rowKinds.isEmpty ? "none" : rowKinds.map(\.rawValue).joined(separator: ",")
        return "durationMs=\(durationMs) rows=\(rows) unknownRows=\(unknownRowCount) skippedRows=\(skippedRowCount)"
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

`RefreshCoordinator.swift` has no exhaustive switch on the intent, and the `allCasesForTest` lists in the test files are local and still compile, so nothing else changes.

Run: `make swift-test SWIFT_TEST_FILTER=claudeUsageReport`
Expected: PASS for the two new bridge tests.

Run: `make swift-test SWIFT_TEST_FILTER=diagnosticsDecoder`
Expected: PASS, including the existing `diagnosticsDecoderRejectsUnknownProviderEnumsAndMalformedTimestamps`.

- [ ] **Step 7: Commit**

```bash
git add Sources/NeedlbarCore/Bridge/RustBridge.swift Sources/NeedlbarCore/Repositories/QuotaRepository.swift Sources/NeedlbarCore/Diagnostics/DiagnosticsSnapshot.swift Tests/NeedlbarCoreTests/BridgeDecodingTests.swift Tests/NeedlbarCoreTests/DiagnosticsTests.swift
git commit -m "feat(core): reach the Claude usage report through the repository

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 6: Probe schedule

**Files:**
- Create: `Sources/NeedlbarCore/Refresh/ClaudeUsageProbeSchedule.swift`
- Modify: `Sources/NeedlbarCore/Refresh/QuotaRefreshActivity.swift:47-49`, `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift:433-443`
- Test: `Tests/NeedlbarCoreTests/ClaudeUsageProbeScheduleTests.swift`

**Interfaces:**
- Consumes: `QuotaRefreshTrigger`.
- Produces: new triggers `.usageRecordsChanged`, `.windowReset`, `.backoffRetry`, `.periodic`. `struct ClaudeUsageProbeSchedule` (internal): `static minimumInterval`, `static periodicInterval`, `static backoffSteps`, `pendingTrigger`, `mutating request(_ trigger: QuotaRefreshTrigger, now: Date, inFlight: Bool) -> Action` where `Action` is `.start` or `.none`; `dueTrigger(resetTimes: [Date], now: Date, inFlight: Bool) -> QuotaRefreshTrigger?`; `mutating recordStart(at: Date)`; `mutating recordSuccess()`; `mutating recordFailure(trigger: QuotaRefreshTrigger, at: Date, retriesWhenBackoffEnds: Bool)`.

- [ ] **Step 1: Write the failing test**

`Tests/NeedlbarCoreTests/ClaudeUsageProbeScheduleTests.swift`:

```swift
import Foundation
import Testing
@testable import NeedlbarCore

@Suite("ClaudeUsageProbeSchedule")
struct ClaudeUsageProbeScheduleTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    @Test func theFirstAutomaticRequestStartsAtOnce() {
        var schedule = ClaudeUsageProbeSchedule()
        #expect(schedule.request(.startup, now: start, inFlight: false) == .start)
    }

    @Test func automaticRunsAreAtLeastFiveMinutesApartAndARefusedChangeStaysPending() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.recordStart(at: start)
        #expect(schedule.request(.usageRecordsChanged, now: at(299), inFlight: false) == .none)
        #expect(schedule.pendingTrigger == .usageRecordsChanged)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(299), inFlight: false) == nil)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(300), inFlight: false) == .usageRecordsChanged)
        schedule.recordStart(at: at(300))
        #expect(schedule.pendingTrigger == nil)
    }

    @Test func onlyOneRunAtATime() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.recordStart(at: start)
        #expect(schedule.request(.startup, now: at(600), inFlight: true) == .none)
        #expect(schedule.pendingTrigger == .startup)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(600), inFlight: true) == nil)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(600), inFlight: false) == .startup)
    }

    @Test func manualSkipsIntervalAndBackoffButJoinsARunInFlight() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.recordStart(at: start)
        schedule.recordFailure(trigger: .startup, at: start, retriesWhenBackoffEnds: true)
        #expect(schedule.request(.manual, now: at(1), inFlight: false) == .start)
        #expect(schedule.request(.manual, now: at(1), inFlight: true) == .none)
        #expect(schedule.pendingTrigger == nil, "joining leaves nothing queued")
    }

    @Test func backoffIsFiveTenTwentyThenThirtyMinutesAndAnySuccessResetsIt() {
        var schedule = ClaudeUsageProbeSchedule()
        var clock: TimeInterval = 0
        for wait in [300.0, 600, 1_200, 1_800, 1_800] {
            schedule.recordStart(at: at(clock))
            schedule.recordFailure(trigger: .backoffRetry, at: at(clock), retriesWhenBackoffEnds: true)
            #expect(schedule.dueTrigger(resetTimes: [], now: at(clock + wait - 1), inFlight: false) == nil)
            #expect(schedule.dueTrigger(resetTimes: [], now: at(clock + wait), inFlight: false) == .backoffRetry)
            clock += wait
        }
        schedule.recordStart(at: at(clock))
        schedule.recordSuccess()
        schedule.recordFailure(trigger: .usageRecordsChanged, at: at(clock), retriesWhenBackoffEnds: true)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(clock + 300), inFlight: false) == .backoffRetry,
                "the count restarted at five minutes")
    }

    @Test func aManualFailureNeitherCountsNorClearsAutomaticBackoff() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.recordStart(at: start)
        schedule.recordFailure(trigger: .startup, at: start, retriesWhenBackoffEnds: true)
        schedule.recordStart(at: at(10))
        schedule.recordFailure(trigger: .manual, at: at(10), retriesWhenBackoffEnds: true)
        #expect(schedule.consecutiveAutomaticFailures == 1)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(299), inFlight: false) == nil)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(310), inFlight: false) == .backoffRetry)
    }

    @Test func notInstalledAndSignedOutDoNotRetryWhenBackoffEndsButRunOnTheNextTrigger() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.recordStart(at: start)
        schedule.recordFailure(trigger: .startup, at: start, retriesWhenBackoffEnds: false)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(300), inFlight: false) == nil, "backoff ended, no retry")
        #expect(schedule.dueTrigger(resetTimes: [], now: at(899), inFlight: false) == nil)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(900), inFlight: false) == .periodic,
                "the periodic run is a trigger like any other")
        #expect(schedule.request(.usageRecordsChanged, now: at(299), inFlight: false) == .none)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(300), inFlight: false) == .usageRecordsChanged)
    }

    @Test func aPassedResetIsDueOncePerRun() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.recordStart(at: start)
        let reset = at(400)
        #expect(schedule.dueTrigger(resetTimes: [reset], now: at(399), inFlight: false) == nil)
        #expect(schedule.dueTrigger(resetTimes: [reset], now: at(400), inFlight: false) == .windowReset)
        schedule.recordStart(at: at(400))
        #expect(schedule.dueTrigger(resetTimes: [reset], now: at(1_299), inFlight: false) == nil)
        #expect(schedule.dueTrigger(resetTimes: [reset], now: at(9_000), inFlight: false) != .windowReset,
                "a run that started at or after the reset has covered it, whatever it returned")
    }

    @Test func aResetInsideTheIntervalWaitsForTheInterval() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.recordStart(at: start)
        #expect(schedule.dueTrigger(resetTimes: [at(100)], now: at(200), inFlight: false) == nil)
        #expect(schedule.dueTrigger(resetTimes: [at(100)], now: at(300), inFlight: false) == .windowReset)
    }

    @Test func aClockSetBackwardsDoesNotBlockAutomaticRuns() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.recordStart(at: start)
        schedule.recordFailure(trigger: .startup, at: start, retriesWhenBackoffEnds: true)
        #expect(schedule.request(.usageRecordsChanged, now: at(-86_400), inFlight: false) == .start)
    }

    // MARK: - Periodic

    @Test func aQuietScheduleIsDueEveryFifteenMinutes() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.recordStart(at: start)
        schedule.recordSuccess()
        #expect(schedule.dueTrigger(resetTimes: [], now: at(899), inFlight: false) == nil)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(900), inFlight: false) == .periodic)
        schedule.recordStart(at: at(900))
        schedule.recordSuccess()
        #expect(schedule.dueTrigger(resetTimes: [], now: at(1_799), inFlight: false) == nil)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(1_800), inFlight: false) == .periodic)
    }

    @Test func thereIsNoPeriodicRunBeforeTheFirstRun() {
        let schedule = ClaudeUsageProbeSchedule()
        #expect(schedule.dueTrigger(resetTimes: [], now: at(86_400), inFlight: false) == nil)
    }

    @Test func thePeriodicRunComesLastInPriority() {
        var pending = ClaudeUsageProbeSchedule()
        pending.recordStart(at: start)
        _ = pending.request(.usageRecordsChanged, now: at(1), inFlight: false)
        #expect(pending.dueTrigger(resetTimes: [], now: at(900), inFlight: false) == .usageRecordsChanged)

        var reset = ClaudeUsageProbeSchedule()
        reset.recordStart(at: start)
        #expect(reset.dueTrigger(resetTimes: [at(500)], now: at(900), inFlight: false) == .windowReset)

        var retry = ClaudeUsageProbeSchedule()
        retry.recordStart(at: start)
        retry.recordFailure(trigger: .startup, at: start, retriesWhenBackoffEnds: true)
        #expect(retry.dueTrigger(resetTimes: [], now: at(900), inFlight: false) == .backoffRetry)
    }

    @Test func thePeriodicRunStaysBehindBackoffAndASingleRun() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.recordStart(at: start)
        for _ in 0 ..< 3 {
            schedule.recordFailure(trigger: .startup, at: start, retriesWhenBackoffEnds: false)
        }
        #expect(schedule.dueTrigger(resetTimes: [], now: at(900), inFlight: false) == nil, "twenty minutes of backoff")
        #expect(schedule.dueTrigger(resetTimes: [], now: at(1_199), inFlight: false) == nil)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(1_200), inFlight: false) == .periodic)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(1_200), inFlight: true) == nil)
    }

    @Test func aClockSetBackwardsNeverMakesThePeriodicRunDue() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.recordStart(at: start)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(-1), inFlight: false) == nil)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(-86_400), inFlight: false) == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeUsageProbeScheduleTests`
Expected: FAIL to compile with `cannot find 'ClaudeUsageProbeSchedule' in scope`.

- [ ] **Step 3: Write the schedule**

`Sources/NeedlbarCore/Refresh/ClaudeUsageProbeSchedule.swift`:

```swift
import Foundation

/// When a `claude -p /usage` run may start. A value with no clock, process or
/// store, owned by `RefreshCoordinator`.
struct ClaudeUsageProbeSchedule: Sendable, Equatable {
    enum Action: Equatable, Sendable {
        case start
        /// Refused or joined. A refused startup or usage change stays in
        /// `pendingTrigger`; a manual request joins the run in flight.
        case none
    }

    static let minimumInterval: TimeInterval = 5 * 60
    /// Keeps readings current during quiet periods (user decision, 2026-11-03).
    static let periodicInterval: TimeInterval = 15 * 60
    static let backoffSteps: [TimeInterval] = [5 * 60, 10 * 60, 20 * 60, 30 * 60]

    private(set) var lastStartedAt: Date?
    private(set) var consecutiveAutomaticFailures = 0
    private(set) var backoffUntil: Date?
    private(set) var pendingTrigger: QuotaRefreshTrigger?
    private var retryPending = false

    mutating func request(_ trigger: QuotaRefreshTrigger, now: Date, inFlight: Bool) -> Action {
        if trigger == .manual { return inFlight ? .none : .start }
        guard !inFlight, automaticRunIsAllowed(now: now) else {
            pendingTrigger = pendingTrigger ?? trigger
            return .none
        }
        return .start
    }

    /// The automatic run that is due now, if any. A pending request comes
    /// first, then a passed reset, then a retry after backoff, then the periodic run.
    func dueTrigger(resetTimes: [Date], now: Date, inFlight: Bool) -> QuotaRefreshTrigger? {
        guard !inFlight, automaticRunIsAllowed(now: now) else { return nil }
        if let pendingTrigger { return pendingTrigger }
        let resetPassed = resetTimes.contains { reset in
            reset <= now && (lastStartedAt.map { $0 < reset } ?? true)
        }
        if resetPassed { return .windowReset }
        if retryPending { return .backoffRetry }
        return periodicRunIsDue(now: now) ? .periodic : nil
    }

    mutating func recordStart(at date: Date) {
        lastStartedAt = date
        pendingTrigger = nil
        retryPending = false
    }

    mutating func recordSuccess() {
        consecutiveAutomaticFailures = 0
        backoffUntil = nil
        retryPending = false
    }

    /// A manual failure neither counts nor clears the automatic backoff.
    mutating func recordFailure(trigger: QuotaRefreshTrigger, at date: Date, retriesWhenBackoffEnds: Bool) {
        retryPending = retriesWhenBackoffEnds
        guard trigger != .manual else { return }
        let step = Self.backoffSteps[min(consecutiveAutomaticFailures, Self.backoffSteps.count - 1)]
        consecutiveAutomaticFailures += 1
        backoffUntil = date.addingTimeInterval(step)
    }

    /// A negative age means the clock was set back, so it never makes this due.
    private func periodicRunIsDue(now: Date) -> Bool {
        guard let lastStartedAt else { return false }
        return now.timeIntervalSince(lastStartedAt) >= Self.periodicInterval
    }

    private func automaticRunIsAllowed(now: Date) -> Bool {
        if let lastStartedAt {
            let age = now.timeIntervalSince(lastStartedAt)
            // A negative age means the clock was set back, not that a run just started.
            if age >= 0, age < Self.minimumInterval { return false }
        }
        if let backoffUntil {
            let remaining = backoffUntil.timeIntervalSince(now)
            if remaining > 0, remaining <= Self.backoffSteps[Self.backoffSteps.count - 1] { return false }
        }
        return true
    }
}
```

Note the pending rule: only `.startup` and `.usageRecordsChanged` go through `request`. `.windowReset`, `.backoffRetry` and `.periodic` come from `dueTrigger`, are derived again on every tick and never become pending.

In `Sources/NeedlbarCore/Refresh/QuotaRefreshActivity.swift:47-49`:

```swift
public enum QuotaRefreshTrigger: String, Sendable, Equatable {
    case startup, scheduled, wake, connectivity, popover, manual
    case usageRecordsChanged, windowReset, backoffRetry, periodic
}
```

In `backgroundRequestIsDue` (`RefreshCoordinator.swift:440`), the only exhaustive `switch` over this enum, change the last case to:

```swift
        case .startup, .manual, .popover, .usageRecordsChanged, .windowReset, .backoffRetry, .periodic:
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeUsageProbeScheduleTests`
Expected: PASS, 15 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/NeedlbarCore/Refresh/ClaudeUsageProbeSchedule.swift Sources/NeedlbarCore/Refresh/QuotaRefreshActivity.swift Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift Tests/NeedlbarCoreTests/ClaudeUsageProbeScheduleTests.swift
git commit -m "feat(core): add the Claude usage probe schedule

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 7: Coordinator runs the probe on its own slot

Claude leaves `.backgroundAll` here at the coordinator level. The production app still gets Claude from the old aggregate until Task 9; this commit is an intermediate state, not a shippable one.

**Files:**
- Modify: `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`, `Sources/NeedlbarCore/Refresh/QuotaRefreshActivity.swift:5,7-45`, `Sources/NeedlbarCore/Repositories/QuotaRepository.swift` (`includesClaude`), `Sources/Needlbar/Diagnostics/QuotaRefreshDiagnosticsReporter.swift`, `Sources/Needlbar/Diagnostics/ClaudeQuotaFailureDiagnosticsReporter.swift:40-49,98-110`
- Create: `Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift`
- Modify: `Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift`, `Tests/NeedlbarTests/ClaudeAccessExpiredPresentationTests.swift`, `Tests/NeedlbarTests/ClaudeQuotaFailureDiagnosticsReporterTests.swift`
- Delete: `Tests/NeedlbarCoreTests/ClaudeKeychainAccessTests.swift`, `Tests/NeedlbarCoreTests/ClaudeAccessExpiredReasonTests.swift`. They drive Claude through `.backgroundAll`, which no longer carries it. Their production code goes in Tasks 10 and 11.

**Interfaces:**
- Consumes: `ClaudeUsageProbeSchedule`, new triggers (Task 6); `QuotaRefreshIntent.claudeUsageReport(runID:)`, `cancelClaudeUsageReport(through:)`, `ClaudeUsageProbeDiagnostics` (Task 5).
- Produces: `RefreshCoordinator.init(… quotaRepository:, claudeUsageRepository: (any QuotaRepository)? = nil, …)` on both initializers; internal init parameter `backgroundQuotaOperationCompleted: (@Sendable () async -> Void)? = nil`, fired once per completed current-generation `.backgroundAll` attempt; `RefreshCoordinator.claudeUsageTickInterval = .seconds(60)`; `quotaAttemptObserver` now reports Claude runs only; `QuotaAttemptEvent.claudeUsageProbe: ClaudeUsageProbeDiagnostics?`; `ClaudeQuotaFailureDiagnosticEvent.usageProbe`.

- [ ] **Step 1: Write the failing test**

`Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift`:

```swift
import Foundation
import Testing
@testable import NeedlbarCore

// Everything is synthetic: fake repositories and a manual clock. Nothing here
// touches a process, the network, credentials or the Keychain.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ClaudeUsageProbeCoordinatorTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Triggers

    @Test func appStartRunsOnceAndPassesTheGenerationAsTheRunID() async throws {
        let harness = Harness()
        await harness.coordinator.start()
        await harness.waitUntilCompletedRuns(1)
        #expect(harness.probe.runIDs == [1])
        #expect(harness.events.values.first?.trigger == .startup)
        await harness.coordinator.stop()
    }

    @Test func openingThePopoverAloneNeverStartsARunEvenWithOneOverdue() async throws {
        let harness = Harness()
        await harness.startedAndIdle()
        // The clock jumps past the periodic interval without waking the tick.
        harness.clock.setNowWithoutWakingSleepers(Self.start.addingTimeInterval(3_600))
        await harness.coordinator.popoverOpened()
        await harness.other.waitUntilCallCount(2)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1)
        // A run really was overdue: the tick starts it, not the popover.
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)
        #expect(harness.events.values.last?.trigger == .periodic)
        await harness.coordinator.stop()
    }

    @Test func wakeAndConnectivityNeverStartARunEvenWithOneOverdue() async throws {
        let harness = Harness()
        await harness.startedAndIdle()
        let token = await harness.coordinator.recoveryRequestToken()
        harness.clock.setNowWithoutWakingSleepers(Self.start.addingTimeInterval(3_600))
        await token.submit(.wake)
        await harness.other.waitUntilCallCount(2)
        await token.submit(.connectivity)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1)
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)
        #expect(harness.events.values.last?.trigger == .periodic)
        await harness.coordinator.stop()
    }

    @Test func theFiveMinuteTimerStartsNoRunBeforeThePeriodicInterval() async throws {
        let harness = Harness()
        await harness.startedAndIdle()
        await harness.advance(minutes: 14)
        await harness.other.waitUntilCallCount(3) // Codex and Cursor keep their five-minute cadence.
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1)
        await harness.coordinator.stop()
    }

    @Test func aQuietPeriodStartsAPeriodicRunEveryFifteenMinutes() async throws {
        let harness = Harness()
        await harness.startedAndIdle()
        await harness.advance(minutes: 15)
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)
        await harness.advance(minutes: 14)
        await settle(watchingFor: { harness.probe.callCount > 2 })
        #expect(harness.probe.callCount == 2)
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(3)
        await harness.waitUntilCompletedRuns(3)
        #expect(harness.probe.startTimes.map { $0.timeIntervalSince(Self.start) } == [0, 900, 1_800])
        #expect(harness.probe.triggersSeen(in: harness.events) == [.startup, .periodic, .periodic])
        await harness.coordinator.stop()
    }

    @Test func aChangedUsageTotalStartsARunButTheFirstObservationDoesNot() async throws {
        let harness = Harness(claudeTotal: 100)
        await harness.startedAndIdle()
        await harness.waitUntilUsageApplied(100)
        await harness.coordinator.requestUsageRefresh()
        await harness.usage.waitUntilCallCount(2)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1, "an unchanged total is no trigger")

        harness.clock.setNowWithoutWakingSleepers(Self.start.addingTimeInterval(301))
        harness.usage.setClaudeTotal(250)
        await harness.coordinator.requestUsageRefresh()
        await harness.probe.waitUntilCallCount(2)
        #expect(harness.probe.triggersSeen(in: harness.events) == [.startup, .usageRecordsChanged])
        await harness.coordinator.stop()
    }

    @Test func aChangeInsideTheIntervalRunsWhenTheIntervalEnds() async throws {
        let harness = Harness(claudeTotal: 100)
        await harness.startedAndIdle()
        await harness.waitUntilUsageApplied(100)
        harness.usage.setClaudeTotal(250)
        await harness.coordinator.requestUsageRefresh()
        await harness.waitUntilUsageApplied(250)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1, "inside five minutes")

        await harness.advance(minutes: 4)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1)
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(2)
        #expect(harness.probe.startTimes.last == Self.start.addingTimeInterval(300))
        await harness.coordinator.stop()
    }

    @Test func passingADisplayedResetStartsOneRun() async throws {
        let reset = Self.start.addingTimeInterval(600)
        let harness = Harness()
        harness.probe.script(.result(try weeklyQuota(resetsAt: reset)))
        harness.probe.script(.result(try weeklyQuota(resetsAt: reset.addingTimeInterval(604_800))))
        await harness.startedAndIdle()
        await harness.advance(minutes: 9)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1)
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)
        #expect(harness.events.values.last?.trigger == .windowReset)
        // Nothing runs again until the periodic interval from this run: not the same reset.
        await harness.advance(minutes: 14)
        await settle(watchingFor: { harness.probe.callCount > 2 })
        #expect(harness.probe.callCount == 2)
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(3)
        await harness.waitUntilCompletedRuns(3)
        #expect(harness.probe.startTimes.last == reset.addingTimeInterval(900))
        #expect(harness.events.values.last?.trigger == .periodic)
        await harness.coordinator.stop()
    }

    // MARK: - Manual

    @Test func manualRefreshSkipsTheIntervalAndBackoff() async throws {
        let harness = Harness()
        harness.probe.script(.result(providerUnavailable()))
        await harness.startedAndIdle()
        await harness.coordinator.manualRefresh()
        await harness.probe.waitUntilCallCount(2)
        #expect(harness.probe.startTimes == [Self.start, Self.start])
        await harness.coordinator.stop()
    }

    @Test func manualRefreshJoinsARunInFlight() async throws {
        let harness = Harness()
        harness.probe.holdNext()
        await harness.coordinator.start()
        await harness.probe.waitUntilHeld()
        await harness.coordinator.manualRefresh()
        await harness.coordinator.manualRefresh()
        harness.probe.release()
        await harness.waitUntilCompletedRuns(1)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1)
        await harness.coordinator.stop()
    }

    // MARK: - One at a time, and independent of other providers

    @Test func otherProvidersKeepRefreshingWhileARunIsHeld() async throws {
        let harness = Harness()
        harness.probe.holdNext()
        await harness.coordinator.start()
        await harness.probe.waitUntilHeld()
        await harness.other.waitUntilCallCount(1)
        await harness.coordinator.manualRefresh()
        await harness.other.waitUntilCallCount(2)
        await pollUntil { await harness.store.snapshot(for: .codex).quota != nil }
        #expect(harness.probe.isHeld)
        #expect(harness.probe.callCount == 1)
        harness.probe.release()
        await harness.coordinator.stop()
    }

    // MARK: - Backoff

    @Test func retryableFailuresBackOffFiveTenTwentyThenThirtyAndSuccessResets() async throws {
        let harness = Harness()
        for _ in 0 ..< 5 { harness.probe.script(.result(providerUnavailable())) }
        harness.probe.script(.result(try weeklyQuota(resetsAt: Self.start.addingTimeInterval(9_000_000))))
        harness.probe.script(.result(providerUnavailable()))
        await harness.startedAndIdle()
        // The waits of 20 and 30 minutes cross the periodic interval: backoff holds it back.
        for (index, minutes) in [5, 10, 20, 30, 30].enumerated() {
            await harness.advance(minutes: minutes - 1)
            await settle(watchingFor: { harness.probe.callCount > index + 1 })
            #expect(harness.probe.callCount == index + 1, "still waiting before minute \(minutes)")
            await harness.advance(minutes: 1)
            await harness.probe.waitUntilCallCount(index + 2)
            await harness.waitUntilCompletedRuns(index + 2)
        }
        let offsets = harness.probe.startTimes.map { $0.timeIntervalSince(Self.start) }
        #expect(offsets == [0, 300, 900, 2_100, 3_900, 5_700])
        #expect(harness.probe.triggersSeen(in: harness.events)
            == [.startup, .backoffRetry, .backoffRetry, .backoffRetry, .backoffRetry, .backoffRetry])
        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == nil, "the last run succeeded")

        // Success clears the retry: the next run is the periodic one.
        await harness.advance(minutes: 14)
        await settle(watchingFor: { harness.probe.callCount > 6 })
        #expect(harness.probe.callCount == 6)
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(7)
        await harness.waitUntilCompletedRuns(7)
        #expect(harness.events.values.last?.trigger == .periodic)

        // Success also reset the count: this failure waits five minutes, not thirty.
        await harness.advance(minutes: 5)
        await harness.probe.waitUntilCallCount(8)
        #expect(harness.probe.startTimes.last == Self.start.addingTimeInterval(5_700 + 900 + 300))
        await harness.coordinator.stop()
    }

    @Test func notInstalledAndNoUsageRetryOnlyOnATriggerAndUnderBackoff() async throws {
        for code in ["notInstalled", "requiresAuthentication"] {
            let harness = Harness(claudeTotal: 100)
            harness.probe.script(.result(claudeError(code)))
            harness.probe.script(.result(claudeError(code)))
            await harness.startedAndIdle()
            await harness.waitUntilUsageApplied(100)
            // The five-minute backoff ends here and nothing retries by itself.
            await harness.advance(minutes: 14)
            await settle(watchingFor: { harness.probe.callCount > 1 })
            #expect(harness.probe.callCount == 1, "\(code) does not retry when backoff ends")

            await harness.advance(minutes: 1)
            await harness.probe.waitUntilCallCount(2)
            await harness.waitUntilCompletedRuns(2)
            #expect(harness.events.values.last?.trigger == .periodic, "\(code)")

            // The second failure backs off ten minutes, which also holds a real trigger.
            harness.usage.setClaudeTotal(250)
            await harness.coordinator.requestUsageRefresh()
            await harness.waitUntilUsageApplied(250)
            await harness.advance(minutes: 9)
            await settle(watchingFor: { harness.probe.callCount > 2 })
            #expect(harness.probe.callCount == 2, "\(code) waits for backoff")
            await harness.advance(minutes: 1)
            await harness.probe.waitUntilCallCount(3)
            #expect(harness.probe.startTimes.last == Self.start.addingTimeInterval(1_500), "\(code)")
            await harness.coordinator.stop()
        }
    }

    @Test func aFailedPeriodicRunKeepsTheReadingAsLastKnownAndBacksOff() async throws {
        let harness = Harness()
        harness.probe.script(.result(try weeklyQuota(resetsAt: Self.start.addingTimeInterval(9_000_000))))
        harness.probe.script(.result(providerUnavailable()))
        await harness.startedAndIdle()
        await harness.advance(minutes: 15)
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)
        #expect(harness.events.values.last?.trigger == .periodic)
        #expect(harness.events.values.last?.outcome == .failure)
        let selected = ClaudeQuotaPresentationSelector.select(
            snapshot: await harness.store.snapshot(for: .claude), now: harness.clock.now).sevenDay
        #expect(selected?.isLastKnown == true)
        #expect(selected?.remainingPercent == 26)
        #expect(selected?.observedAt == Self.start, "labelled with the time it was checked")

        await harness.advance(minutes: 5)
        await harness.probe.waitUntilCallCount(3)
        await harness.waitUntilCompletedRuns(3)
        #expect(harness.probe.startTimes.last == Self.start.addingTimeInterval(1_200))
        #expect(harness.events.values.last?.trigger == .backoffRetry)
        await harness.coordinator.stop()
    }

    // MARK: - Stop and generation

    @Test func stopCancelsTheRunInFlightAndDropsItsResult() async throws {
        let harness = Harness()
        harness.probe.holdNext()
        await harness.coordinator.start()
        await harness.probe.waitUntilHeld()
        await harness.coordinator.stop()
        #expect(harness.probe.cancelledThrough == [1])
        harness.probe.script(.result(try weeklyQuota(resetsAt: nil)))
        harness.probe.release()
        await settle(watchingFor: { harness.events.values.contains { $0.phase == .completed } })
        #expect(await harness.store.snapshot(for: .claude).quota == nil)
        #expect(harness.events.values.map(\.phase) == [.started, .invalidated])
    }

    @Test func stopWithNoRunInFlightCancelsNothing() async throws {
        let harness = Harness()
        await harness.startedAndIdle()
        await harness.coordinator.stop()
        #expect(harness.probe.cancelledThrough.isEmpty)
    }

    @Test func restartWaitsForTheOldPhysicalCallThenRunsOnce() async throws {
        let harness = Harness()
        harness.probe.holdNext()
        await harness.coordinator.start()
        await harness.probe.waitUntilHeld()
        await harness.coordinator.stop()
        await harness.coordinator.start()
        #expect(harness.probe.callCount == 1)
        harness.probe.release()
        await harness.probe.waitUntilCallCount(2)
        #expect(harness.probe.runIDs == [1, 3], "a stop and a start each advance the generation")
        await harness.coordinator.stop()
    }

    @Test func aThrownFailureMarksOnlyClaude() async throws {
        let harness = Harness()
        harness.probe.script(.failure(BridgeFailure.nullPointer))
        await harness.startedAndIdle()
        await pollUntil { await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == .couldNotUpdateQuota }
        await pollUntil { await harness.store.snapshot(for: .codex).quota != nil }
        #expect(await harness.store.snapshot(for: .codex).quotaStatus == .fresh)
        await harness.coordinator.stop()
    }

    @Test func aBackgroundBridgeFailureLeavesClaudeAlone() async throws {
        let harness = Harness()
        harness.other.scriptFailure(BridgeFailure.nullPointer)
        harness.probe.script(.result(try weeklyQuota(resetsAt: nil)))
        await harness.startedAndIdle()
        await pollUntil { await harness.store.snapshot(for: .codex).quotaStatus != .unavailable }
        let claude = await harness.store.snapshot(for: .claude)
        #expect(claude.quotaStatus == .fresh)
        #expect(claude.claudeQuotaFailureReason == nil)
        await harness.coordinator.stop()
    }

    // MARK: - Diagnostics

    @Test func diagnosticsAreReadOncePerRunSharedWithTheReporterAndAddedToTheEvent() async throws {
        let harness = Harness()
        harness.probe.script(.result(claudeError("schemaChanged")))
        harness.diagnostics.script { now in
            diagnosticsRead(origin: "usageReportFormatChanged", lastAttemptAt: now)
        }
        await harness.startedAndIdle()
        #expect(harness.diagnostics.readCount == 1)
        #expect(harness.diagnostics.reportCount == 1)
        #expect(harness.events.values.last?.claudeUsageProbe == ClaudeUsageProbeDiagnostics(
            durationMs: 1_500, rowKinds: [.weeklyAll], unknownRowCount: 2, skippedRowCount: 1))
        #expect(harness.events.values.last?.outcome == .failure)
        await harness.coordinator.stop()
    }

    @Test func aBackgroundRefreshReadsNoClaudeDiagnosticsAndEmitsNoAttempt() async throws {
        let harness = Harness(claudeRepository: false)
        await harness.coordinator.start()
        await harness.other.waitUntilCallCount(1)
        await pollUntil { await harness.store.snapshot(for: .codex).quota != nil }
        await settle(watchingFor: { harness.diagnostics.readCount > 0 })
        #expect(harness.diagnostics.readCount == 0)
        #expect(harness.events.values.isEmpty)
        await harness.coordinator.stop()
    }

    @Test func withoutAClaudeRepositoryThereIsNoTick() async throws {
        let harness = Harness(claudeRepository: false)
        await harness.coordinator.start()
        await harness.clock.waitUntilSleeperCount(2)
        await settle(watchingFor: { harness.clock.sleeperCount > 2 })
        #expect(harness.clock.sleeperCount == 2)
        await harness.coordinator.stop()
    }

    @Test func noRawCanaryReachesTheStoreOrTheEvents() async throws {
        let harness = Harness()
        harness.probe.script(.result(claudeError("schemaChanged")))
        await harness.startedAndIdle()
        let reason = await harness.store.snapshot(for: .claude).claudeQuotaFailureReason
        let surfaces = "\(String(describing: reason)) \(harness.events.values)"
        #expect(!surfaces.contains(canaryMessage))
        await harness.coordinator.stop()
    }
}

// MARK: - Fixtures

private let canaryMessage = "RAW_OUTPUT_TOKEN_PATH_CANARY"

private func claudeError(_ code: String) -> QuotaRefreshResult {
    .init(snapshots: [:], errors: [.claude: .init(provider: "claude", code: code, message: canaryMessage, action: nil)])
}

private func providerUnavailable() -> QuotaRefreshResult { claudeError("providerUnavailable") }

private func weeklyQuota(resetsAt: Date?) throws -> QuotaRefreshResult {
    .init(snapshots: [.claude: QuotaSnapshot(windows: [
        try QuotaWindow(id: "claude.weekly", title: "Weekly", usedPercent: 74, resetsAt: resetsAt),
    ])], errors: [:])
}

private func diagnosticsRead(origin: String, lastAttemptAt: Date) -> ClaudeQuotaDiagnosticsRead {
    let attempt = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: floor(lastAttemptAt.timeIntervalSince1970)))
    let json = """
    {"schemaVersion":"needlbar.v1","ok":true,"generatedAt":"\(attempt)","data":{"providers":[{"provider":"claude","usageStatus":"available","quotaStatus":"error","usageSource":"local","quotaSource":"usageReport","lastAttemptAt":"\(attempt)","claudeQuotaFailureOrigin":"\(origin)","claudeUsageProbe":{"durationMs":1500,"rowKinds":["weeklyAll"],"unknownRowCount":2,"skippedRowCount":1}}]},"errors":[]}
    """
    return Result { try BridgeDecoder().decodeDiagnosticsEnvelope(Data(json.utf8)) }
}

private func usage(total: UInt64) -> UsageSnapshot {
    let period = UsagePeriod(inputTokens: total, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0,
                             totalTokens: total, estimatedCostUSD: 0)
    return UsageSnapshot(inputTokens: total, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0,
                         totalTokens: total, estimatedCostUSD: 0, today: period, last7Days: period, last30Days: period)
}

// MARK: - Test doubles

private struct Harness {
    let store: ProviderSnapshotStore
    let probe: ProbeRepository
    let other: BackgroundRepository
    let usage: ScriptedUsageRepository
    let diagnostics: FakeDiagnostics
    let clock: ManualClock
    let events = AttemptEvents()
    let coordinator: RefreshCoordinator

    init(claudeRepository: Bool = true, claudeTotal: UInt64 = 0) {
        let clock = ManualClock(now: ClaudeUsageProbeCoordinatorTests.start)
        let events = self.events
        let probe = ProbeRepository(clock: clock)
        let diagnostics = FakeDiagnostics(clock: clock)
        let other = BackgroundRepository()
        let usage = ScriptedUsageRepository(claudeTotal: claudeTotal)
        let store = ProviderSnapshotStore(now: { clock.now })
        self.store = store
        self.probe = probe
        self.other = other
        self.usage = usage
        self.diagnostics = diagnostics
        self.clock = clock
        coordinator = RefreshCoordinator(
            usageRepository: usage,
            quotaRepository: other,
            claudeUsageRepository: claudeRepository ? probe : nil,
            store: store,
            clock: clock,
            claudeQuotaDiagnostics: diagnostics.completion,
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

    func waitUntilUsageApplied(_ total: UInt64) async {
        await pollUntil { await store.snapshot(for: .claude).usage?.totalTokens == total }
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

private final class AttemptEvents: @unchecked Sendable {
    private let lock = NSLock()
    let changes = ConditionWaiters()
    private var recorded: [QuotaAttemptEvent] = []
    var values: [QuotaAttemptEvent] { lock.withLock { recorded } }
    func record(_ event: QuotaAttemptEvent) {
        lock.withLock { recorded.append(event) }
        changes.signal()
    }
}

private final class ProbeRepository: QuotaRepository, @unchecked Sendable {
    enum Outcome {
        case result(QuotaRefreshResult)
        case failure(any Error)

        func get() throws -> QuotaRefreshResult {
            switch self {
            case .result(let result): return result
            case .failure(let error): throw error
            }
        }
    }

    private let clock: ManualClock
    private let lock = NSLock()
    private let changes = ConditionWaiters()
    private let gate = DispatchSemaphore(value: 0)
    private var outcomes: [Outcome] = []
    private var holds = false
    private var held = false
    private var recordedRunIDs: [UInt64] = []
    private var recordedStarts: [Date] = []
    private var recordedCancels: [UInt64] = []

    init(clock: ManualClock) { self.clock = clock }

    var callCount: Int { lock.withLock { recordedRunIDs.count } }
    var runIDs: [UInt64] { lock.withLock { recordedRunIDs } }
    var startTimes: [Date] { lock.withLock { recordedStarts } }
    var cancelledThrough: [UInt64] { lock.withLock { recordedCancels } }
    var isHeld: Bool { lock.withLock { held } }

    func script(_ outcome: Outcome) { lock.withLock { outcomes.append(outcome) } }
    func holdNext() { lock.withLock { holds = true } }
    func release() { gate.signal() }
    func waitUntilHeld() async { await changes.wait { self.isHeld } }
    func waitUntilCallCount(_ expected: Int) async { await changes.wait { self.callCount >= expected } }

    func triggersSeen(in events: AttemptEvents) -> [QuotaRefreshTrigger] {
        events.values.filter { $0.phase == .started }.map(\.trigger)
    }

    func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult {
        guard case .claudeUsageReport(let runID) = intent else { throw BridgeFailure.nullPointer }
        let hold = lock.withLock { () -> Bool in
            recordedRunIDs.append(runID)
            recordedStarts.append(clock.now)
            let hold = holds
            holds = false
            held = hold
            return hold
        }
        changes.signal()
        if hold {
            _ = gate.wait(timeout: .now() + .seconds(30))
            lock.withLock { held = false }
            changes.signal()
        }
        // With nothing scripted a run succeeds. An empty result would count as a
        // retryable failure and start a backoff retry at five minutes.
        let scripted = lock.withLock { outcomes.isEmpty ? nil : outcomes.removeFirst() }
        return try scripted?.get() ?? weeklyQuota(resetsAt: nil)
    }

    func cancelClaudeUsageReport(through runID: UInt64) {
        lock.withLock { recordedCancels.append(runID) }
    }
}

/// The Codex and Cursor refresh.
private final class BackgroundRepository: QuotaRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let changes = ConditionWaiters()
    private var calls = 0
    private var failure: (any Error)?

    var callCount: Int { lock.withLock { calls } }
    func scriptFailure(_ error: any Error) { lock.withLock { failure = error } }
    func waitUntilCallCount(_ expected: Int) async { await changes.wait { self.callCount >= expected } }

    func refresh(intent: QuotaRefreshIntent) throws -> QuotaRefreshResult {
        guard intent == .backgroundAll else { throw BridgeFailure.nullPointer }
        let error = lock.withLock { () -> (any Error)? in
            calls += 1
            return failure
        }
        changes.signal()
        if let error { throw error }
        return .init(snapshots: [.codex: QuotaSnapshot(windows: [
            try QuotaWindow(id: "codex.primary", title: "Primary", usedPercent: 10, resetsAt: nil),
        ])], errors: [:])
    }
}

private final class ScriptedUsageRepository: UsageRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let changes = ConditionWaiters()
    private var total: UInt64
    private var calls = 0

    init(claudeTotal: UInt64) { total = claudeTotal }

    func setClaudeTotal(_ value: UInt64) { lock.withLock { total = value } }
    func waitUntilCallCount(_ expected: Int) async {
        await changes.wait { self.lock.withLock { self.calls } >= expected }
    }

    func refresh() throws -> UsageRefreshResult {
        let current = lock.withLock { () -> UInt64 in
            calls += 1
            return total
        }
        changes.signal()
        return .init(snapshots: [.claude: usage(total: current)], errors: [:])
    }
}

private final class FakeDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private let clock: ManualClock
    private var respond: @Sendable (Date) -> ClaudeQuotaDiagnosticsRead = { _ in .failure(BridgeFailure.nullPointer) }
    private var reads = 0
    private var reports = 0

    init(clock: ManualClock) { self.clock = clock }

    var readCount: Int { lock.withLock { reads } }
    var reportCount: Int { lock.withLock { reports } }

    func script(_ respond: @escaping @Sendable (Date) -> ClaudeQuotaDiagnosticsRead) {
        lock.withLock { self.respond = respond }
    }

    var completion: ClaudeQuotaCompletionDiagnostics {
        ClaudeQuotaCompletionDiagnostics(
            read: { [self] in
                let respond = lock.withLock { () -> @Sendable (Date) -> ClaudeQuotaDiagnosticsRead in
                    reads += 1
                    return self.respond
                }
                return respond(clock.now)
            },
            report: { [self] _ in lock.withLock { reports += 1 } }
        )
    }
}

private final class ManualClock: ClockLike, @unchecked Sendable {
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

    func setNowWithoutWakingSleepers(_ value: Date) { lock.withLock { date = value } }

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

- [ ] **Step 2: Run test to verify it fails**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeUsageProbeCoordinatorTests`
Expected: FAIL to compile with `extra argument 'claudeUsageRepository' in call`.

- [ ] **Step 3: Extend the attempt event**

In `Sources/NeedlbarCore/Refresh/QuotaRefreshActivity.swift`, change line 5 so logs stop naming a retired path, keeping the case name:

```swift
public enum QuotaObservationSource: String, Sendable { case direct = "usageReport", statusLine, unavailable }
```

Add to `QuotaAttemptEvent` a stored `public let claudeUsageProbe: ClaudeUsageProbeDiagnostics?`, a final init parameter `claudeUsageProbe: ClaudeUsageProbeDiagnostics? = nil`, and the assignment.

- [ ] **Step 4: Change the coordinator**

In `Sources/NeedlbarCore/Repositories/QuotaRepository.swift`:

```swift
extension QuotaRefreshIntent {
    var includesClaude: Bool {
        switch self {
        case .claudePreflight, .userInitiated(provider: .claude), .claudeUsageReport: true
        case .backgroundAll, .userInitiated: false
        }
    }
}
```

In `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`:

Add below `popoverQuotaRefreshThreshold`:

```swift
    /// How often a passed reset, a deferred usage change, a backoff retry and the
    /// periodic run are checked. It reads only actor and store state.
    static let claudeUsageTickInterval: Duration = .seconds(60)
```

Add to the stored properties:

```swift
    private let claudeUsageRepository: (any QuotaRepository)?
    private let backgroundQuotaOperationCompleted: (@Sendable () async -> Void)?
    /// Reports Claude runs. `quotaAttemptLedger` only gates the other refresh.
    private let claudeUsageAttemptLedger: QuotaAttemptLedger
    private var claudeUsageSchedule = ClaudeUsageProbeSchedule()
    /// Retained until the physical call returns, so runs never overlap across a restart.
    private var claudeUsageProbeTask: Task<Void, Never>?
    private var claudeUsageTickTask: Task<Void, Never>?
    private var lastClaudeUsageTotalTokens: UInt64?
```

In both initializers add `claudeUsageRepository: (any QuotaRepository)? = nil` directly after `quotaRepository`. In the internal initializer also add `backgroundQuotaOperationCompleted: (@Sendable () async -> Void)? = nil` directly before `claudeQuotaOperationCompleted`, so a renamed argument stays in a valid position. The public initializer forwards `claudeUsageRepository: claudeUsageRepository` and `backgroundQuotaOperationCompleted: nil`. In the internal initializer body, replace `self.quotaAttemptLedger = QuotaAttemptLedger(observer: quotaAttemptObserver)` with:

```swift
        self.claudeUsageRepository = claudeUsageRepository
        self.backgroundQuotaOperationCompleted = backgroundQuotaOperationCompleted
        self.quotaAttemptLedger = QuotaAttemptLedger(observer: nil)
        self.claudeUsageAttemptLedger = QuotaAttemptLedger(observer: quotaAttemptObserver)
```

Add to `deinit`: `claudeUsageProbeTask?.cancel()` and `claudeUsageTickTask?.cancel()`.

In `start()`, after `quotaAttemptLedger.advance(to: runGeneration)` add:

```swift
        claudeUsageAttemptLedger.advance(to: runGeneration)
        claudeUsageSchedule = ClaudeUsageProbeSchedule()
        lastClaudeUsageTotalTokens = nil
```

and insert `requestClaudeUsageProbe(trigger: .startup)` directly before `requestQuotaRefresh(trigger: .startup)`.

In `manualRefresh()`, insert `requestClaudeUsageProbe(trigger: .manual)` directly after `requestStatusLineRead()`.

In `stop()`, replace the first two lines with:

```swift
        let stoppedGeneration = runGeneration
        let probeInFlight = claudeUsageProbeTask != nil
        runGeneration &+= 1
        quotaAttemptLedger.advance(to: runGeneration)
        claudeUsageAttemptLedger.advance(to: runGeneration)
        if probeInFlight {
            claudeUsageProbeTask?.cancel()
            // A cancel by ID also reaches a run still on its way into the bridge.
            claudeUsageRepository?.cancelClaudeUsageReport(through: stoppedGeneration)
        }
        claudeUsageTickTask?.cancel()
        claudeUsageTickTask = nil
```

At the end of `scheduleSafetyRefreshes()` add:

```swift
        guard claudeUsageRepository != nil else { return }
        claudeUsageTickTask = Task { [weak self, clock, generation] in
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: Self.claudeUsageTickInterval)
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                await self?.evaluateClaudeUsageProbeTriggers(generation: generation)
            }
        }
```

Add these methods after `beginQuotaRefresh`:

```swift
    private func requestClaudeUsageProbe(trigger: QuotaRefreshTrigger) {
        guard isRunning, claudeUsageRepository != nil else { return }
        let action = claudeUsageSchedule.request(trigger, now: clock.now, inFlight: claudeUsageProbeTask != nil)
        if action == .start { beginClaudeUsageProbe(trigger: trigger) }
    }

    /// Starts the run that is due, if any: a deferred request, a displayed window
    /// whose reset has passed, a retry after backoff, or the periodic run.
    private func evaluateClaudeUsageProbeTriggers(generation: UInt64) async {
        guard isRunning, generation == runGeneration, claudeUsageRepository != nil else { return }
        let snapshot = await store.snapshot(for: .claude)
        guard isRunning, generation == runGeneration else { return }
        let now = clock.now
        let selection = ClaudeQuotaPresentationSelector.select(snapshot: snapshot, now: now)
        let resetTimes = [selection.fiveHour, selection.sevenDay, selection.fable].compactMap { $0?.resetsAt }
        if let trigger = claudeUsageSchedule.dueTrigger(
            resetTimes: resetTimes, now: now, inFlight: claudeUsageProbeTask != nil
        ) {
            beginClaudeUsageProbe(trigger: trigger)
        }
    }

    /// A run can take 30 seconds, so it uses a dispatch thread rather than a
    /// cooperative one, and its own slot rather than the Codex and Cursor one.
    private func beginClaudeUsageProbe(trigger: QuotaRefreshTrigger) {
        guard let repository = claudeUsageRepository, claudeUsageProbeTask == nil else { return }
        let generation = runGeneration
        let clock = clock
        let ledger = claudeUsageAttemptLedger
        let id = UUID()
        claudeUsageSchedule.recordStart(at: clock.now)
        ledger.reserve(id: id, generation: generation, trigger: trigger)
        claudeUsageProbeTask = Task { [weak self, repository, clock, ledger] in
            guard !Task.isCancelled, let attempt = ledger.claim(
                id: id, generation: generation, at: clock.now, backgroundClock: nil
            ) else {
                await self?.finishClaudeUsageProbe(.failure(CancellationError()), trigger: trigger,
                                                   applyResult: false, generation: generation, attempt: nil)
                return
            }
            let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<QuotaRefreshResult, Error>, Never>) in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(returning: Result {
                        try repository.refresh(intent: .claudeUsageReport(runID: generation))
                    })
                }
            }
            await self?.finishClaudeUsageProbe(result, trigger: trigger, applyResult: !Task.isCancelled,
                                               generation: generation, attempt: attempt)
        }
    }

    private func finishClaudeUsageProbe(
        _ result: Result<QuotaRefreshResult, Error>,
        trigger: QuotaRefreshTrigger,
        applyResult: Bool,
        generation: UInt64,
        attempt: QuotaAttemptEvent?
    ) async {
        defer {
            claudeUsageProbeTask = nil
            if let pending = claudeUsageSchedule.pendingTrigger {
                requestClaudeUsageProbe(trigger: pending)
            }
        }
        guard applyResult, generation == runGeneration else { return }
        recordClaudeUsageOutcome(result, trigger: trigger, at: clock.now)
        var application = QuotaApplication()
        await applyQuotaResult(result, intent: .claudeUsageReport(runID: generation), applyResult: true,
                               generation: generation, attempt: attempt,
                               claudeAttemptStartedAt: attempt?.startedAt, excludingClaude: false,
                               into: &application)
    }

    private func recordClaudeUsageOutcome(
        _ result: Result<QuotaRefreshResult, Error>, trigger: QuotaRefreshTrigger, at date: Date
    ) {
        var retries = true
        if case .success(let refresh) = result {
            if refresh.errors[.claude] == nil, refresh.snapshots[.claude] != nil {
                claudeUsageSchedule.recordSuccess()
                return
            }
            // Not installed and no usage wait for the next trigger, which includes
            // the periodic run (spec §8).
            let code = refresh.errors[.claude]?.code
            retries = code != "notInstalled" && code != "requiresAuthentication"
        }
        claudeUsageSchedule.recordFailure(trigger: trigger, at: date, retriesWhenBackoffEnds: retries)
    }

    /// Compares the Claude total from the existing usage refresh. The first
    /// observation after start only sets the baseline, because start runs anyway.
    private func noteClaudeUsageRecords(_ total: UInt64?) {
        guard let total else { return }
        defer { lastClaudeUsageTotalTokens = total }
        guard let previous = lastClaudeUsageTotalTokens, previous != total else { return }
        requestClaudeUsageProbe(trigger: .usageRecordsChanged)
    }
```

In `finishUsageRefresh`, at the end of `case .success(let refresh):` after the errors loop, add `noteClaudeUsageRecords(refresh.snapshots[.claude]?.totalTokens)`.

In `applyQuotaResult`, add a helper and use it in both places in `.failure`:

```swift
    private func requestedProviders(for intent: QuotaRefreshIntent) -> [ProviderID] {
        switch intent {
        case .userInitiated(let provider): [provider]
        case .claudeUsageReport, .claudePreflight: [.claude]
        case .backgroundAll: [.codex, .cursor]
        }
    }
```

Replace lines 747-757, from `var requestedProviders: Set<ProviderID>` through the end of `matchingErrors`, with:

```swift
                var requested = Set(requestedProviders(for: intent))
                if excludingClaude { requested.remove(.claude) }
                let matchingErrors = bridgeErrors.filter {
                    guard let provider = $0.providerID else { return false }
                    return requested.contains(provider)
                }
```

Replace lines 773-779 with:

```swift
            for provider in requestedProviders(for: intent) where !(excludingClaude && provider == .claude) {
```

Replace everything from line 790 (`if includesClaude {`) to the end of `applyQuotaResult` with:

```swift
        if includesClaude {
            if let claudeDiagnosticsRead { await claudeQuotaDiagnostics?.report(claudeDiagnosticsRead) }
            await claudeQuotaOperationCompleted?()
        } else if case .backgroundAll = intent {
            await backgroundQuotaOperationCompleted?()
        }
        guard generation == runGeneration, isRunning, !Task.isCancelled, let attempt else { return }
        guard case .claudeUsageReport = intent else {
            quotaAttemptLedger.complete(attempt)
            return
        }
        let snapshot = await store.snapshot(for: .claude)
        guard generation == runGeneration, isRunning, !Task.isCancelled else { return }
        let completedAt = clock.now
        let selection = ClaudeQuotaPresentationSelector.select(snapshot: snapshot, now: completedAt)
        let outcome = quotaAttemptOutcome(for: result, intent: intent)
        claudeUsageAttemptLedger.complete(QuotaAttemptEvent(
            id: attempt.id, generation: generation, trigger: attempt.trigger, phase: .completed,
            startedAt: attempt.startedAt, completedAt: completedAt, outcome: outcome,
            directLastSuccessfulAt: snapshot.quotaLastSuccessfulAt,
            failureAttemptAt: outcome == .success ? nil : attempt.startedAt,
            fiveHourSource: observationSource(selection.fiveHour),
            sevenDaySource: observationSource(selection.sevenDay),
            fableSource: observationSource(selection.fable),
            fiveHourReceiptAt: snapshot.claudeStatusLineQuota?.fiveHour?.receivedAt,
            sevenDayReceiptAt: snapshot.claudeStatusLineQuota?.sevenDay?.receivedAt,
            claudeUsageProbe: claudeUsageProbe(in: claudeDiagnosticsRead)))
    }

    private func claudeUsageProbe(in read: ClaudeQuotaDiagnosticsRead?) -> ClaudeUsageProbeDiagnostics? {
        guard case .success(let envelope)? = read else { return nil }
        return envelope.data?.providers.first { $0.provider == .claude }?.claudeUsageProbe
    }
```

`.claudeUsageReport` must not be queued through the quota slot, so `beginQuotaRefresh` is never called with it.

- [ ] **Step 5: Update the two reporters**

In `Sources/Needlbar/Diagnostics/QuotaRefreshDiagnosticsReporter.swift` `productionSink`, change the fields:

```swift
        let fields = "trigger=\(event.trigger.rawValue) phase=\(event.phase.rawValue) outcome=\(event.outcome?.rawValue ?? "-")"
            + " start=\(timestamp(event.startedAt)) complete=\(timestamp(event.completedAt))"
            + " usageReportSuccess=\(timestamp(event.directLastSuccessfulAt)) failureAttempt=\(timestamp(event.failureAttemptAt))"
            + " fiveHour=\(event.fiveHourSource.rawValue) sevenDay=\(event.sevenDaySource.rawValue) fable=\(event.fableSource.rawValue)"
            + " fiveHourReceipt=\(timestamp(event.fiveHourReceiptAt)) sevenDayReceipt=\(timestamp(event.sevenDayReceiptAt))"
            + (event.claudeUsageProbe.map { " \($0.logFields)" } ?? "")
```

In `Sources/Needlbar/Diagnostics/ClaudeQuotaFailureDiagnosticsReporter.swift`:

```swift
struct ClaudeQuotaFailureDiagnosticEvent: Equatable, Sendable {
    let origin: ClaudeQuotaFailureOrigin
    let code: ClaudeQuotaFailureDiagnosticCode
    let attemptAt: String
    let usageProbe: ClaudeUsageProbeDiagnostics?

    init(origin: ClaudeQuotaFailureOrigin, code: ClaudeQuotaFailureDiagnosticCode, attemptAt: String,
         usageProbe: ClaudeUsageProbeDiagnostics? = nil) {
        self.origin = origin
        self.code = code
        self.attemptAt = attemptAt
        self.usageProbe = usageProbe
    }

    /// The whole OSLog line, built only from closed values, counts and the
    /// formatted attempt time.
    var message: String {
        let base = "claudeQuotaFailure origin=\(origin.rawValue) code=\(code.rawValue) attempt=\(attemptAt)"
        return usageProbe.map { "\(base) \($0.logFields)" } ?? base
    }
}
```

and pass `usageProbe: provider.claudeUsageProbe` where `event(from:)` builds the event.

Append to `Tests/NeedlbarTests/ClaudeQuotaFailureDiagnosticsReporterTests.swift`:

```swift
@Test func reporterLogLineAddsTheRunSummaryAndNothingElse() throws {
    let json = """
    {"schemaVersion":"needlbar.v1","ok":true,"generatedAt":"2026-11-03T12:00:00Z","data":{"providers":[{"provider":"claude","usageStatus":"available","quotaStatus":"error","usageSource":"local","quotaSource":"usageReport","lastAttemptAt":"2026-11-03T11:59:59Z","quotaErrorCode":"schemaChanged","claudeQuotaFailureOrigin":"usageReportFormatChanged","claudeUsageProbe":{"durationMs":1832,"rowKinds":["weeklyAll"],"unknownRowCount":1,"skippedRowCount":0},"rawOutputCanary":"TEXT-CANARY"}]},"errors":[]}
    """
    let sink = DiagnosticEventSink()
    let reporter = ClaudeQuotaFailureDiagnosticsReporter(
        readDiagnostics: { try BridgeDecoder().decodeDiagnosticsEnvelope(Data(json.utf8)) },
        sink: { sink.append($0) }
    )
    reporter.reportLatestClaudeQuotaFailure()
    #expect(sink.values.map(\.message) == [
        "claudeQuotaFailure origin=usageReportFormatChanged code=schemaChanged attempt=2026-11-03T11:59:59Z durationMs=1832 rows=weeklyAll unknownRows=1 skippedRows=0",
    ])
}
```

Run `git rm Tests/NeedlbarCoreTests/ClaudeKeychainAccessTests.swift Tests/NeedlbarCoreTests/ClaudeAccessExpiredReasonTests.swift`.

- [ ] **Step 6: Run the new tests**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeUsageProbeCoordinatorTests`
Expected: PASS, 23 tests.

- [ ] **Step 7: Port the existing coordinator tests**

Run this script once from the repository root. It is not committed.

```bash
/usr/bin/python3 -I - <<'PY'
import pathlib, re

path = pathlib.Path("Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift")
source = path.read_text()

def span(text, name):
    match = re.search(r"^[ \t]*(?:@MainActor\n[ \t]*)?@Test(?:\([^\n]*\))?\s*(?:\n[ \t]*)?func " + name + r"\(", text, re.M)
    assert match, name
    index = text.index("{", match.end())
    depth = 0
    for position in range(index, len(text)):
        if text[position] == "{":
            depth += 1
        elif text[position] == "}":
            depth -= 1
            if depth == 0:
                return match.start(), position + 1
    raise AssertionError(name)

def edit(name, transform):
    global source
    start, end = span(source, name)
    source = source[:start] + transform(source[start:end]) + source[end:]

EMPTY = "QuotaRefreshSpy(result: .init(snapshots: [:], errors: [:]))"

def to_probe(body):
    assert "quotaRepository: quota," in body
    return body.replace("quotaRepository: quota,", f"quotaRepository: {EMPTY}, claudeUsageRepository: quota,")

# Attempt events now describe Claude runs only.
for name in [
    "attemptIsInProgressUntilStoreAndLegacyCallbackComplete",
    "blockedAttemptInvalidatesOnceAndRestartUsesNewIdentityAndGeneration",
    "attemptSourceTreatsStatusLineOlderThanTwentyFourHoursAsUnavailableAndKeepsItsReceipt",
    "statusLineOnlyRecoveryDoesNotEmitDirectAttemptOrSuccess",
    "stopDuringLegacyCallbackInvalidatesAndCannotCompleteAfterResume",
]:
    edit(name, to_probe)

edit(
    "expiryPreservesDirectSuccessAndBridgeReceiptsThenSuccessReplacesIt",
    lambda body: to_probe(body).replace("await coordinator.popoverOpened()", "await coordinator.manualRefresh()"),
)

def drop_codex_tail(body):
    body = to_probe(body)
    start = body.index("    let claudeFailure = events.values.last\n")
    end = body.index("    await coordinator.stop()\n", start)
    return body[:start] + body[end:]

edit("currentResultDeterminesAttemptOutcomeWithoutCachedSuccessInference", drop_codex_tail)

# Codex verification no longer emits attempt events.
start, end = span(source, "codexOnlyCompletionKeepsThePriorClaudeProjection")
source = source[:start] + source[end:].lstrip("\n")

# These use the callback as a barrier for the background refresh.
for name in [
    "recoveryUsesFreshPopoverAttemptRatherThanStartupAttempt",
    "recoveryBeforeAndImmediatelyAfterStartDoesNotDuplicateStartup",
    "recoveryBurstQueuesOneAggregateFollowUp",
    "forcedAggregateUpgradesPendingRecoveryWithoutAnotherTicket",
    "periodicAndRecoveryBoundaryShareOnePhysicalAttempt",
    "returnedClaudeQuotaErrorsMapOnlyAllowlistedCodesToSafeReasons",
    "claudeQuotaCompletionHandlerBlocksQueuedQuotaUntilItCompletes",
    "staleClaudeGenerationSkipsCompletionHandlerAfterApplicationGate",
    "claudeQuotaCompletionHandlerSkipsCodexOnlyAndCancelledRefreshes",
]:
    edit(name, lambda body: body.replace("claudeQuotaOperationCompleted:", "backgroundQuotaOperationCompleted:"))

path.write_text(source)

presentation = pathlib.Path("Tests/NeedlbarTests/ClaudeAccessExpiredPresentationTests.swift")
source = presentation.read_text()
start, end = span(source, "reporterSharesTheCoordinatorReadAndLogsOnlyAllowlistedFields")
source = source[:start] + source[end:].lstrip("\n")
presentation.write_text(source)
PY
```

- [ ] **Step 8: Run the affected suites**

Run: `make swift-test SWIFT_TEST_FILTER=RefreshCoordinatorTests`
Expected: PASS.

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeStatusLineFallbackIntegrationTests`
Expected: PASS. A `.backgroundAll` result naming Claude is still applied generically, which is why this fake keeps working; Rust stops producing one in Task 9.

- [ ] **Step 9: Run the full Swift suite and commit**

Run: `make swift-test`
Expected: PASS.

```bash
git add Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift Sources/NeedlbarCore/Refresh/QuotaRefreshActivity.swift Sources/NeedlbarCore/Repositories/QuotaRepository.swift Sources/Needlbar/Diagnostics/QuotaRefreshDiagnosticsReporter.swift Sources/Needlbar/Diagnostics/ClaudeQuotaFailureDiagnosticsReporter.swift Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift Tests/NeedlbarTests/ClaudeAccessExpiredPresentationTests.swift Tests/NeedlbarTests/ClaudeQuotaFailureDiagnosticsReporterTests.swift
git commit -m "feat(core): run the Claude usage report on its own schedule and slot

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 8: Failure copy, source order, freshness and only-Fable presentation

**Files:**
- Modify: `Sources/NeedlbarCore/Models/ClaudeQuotaFailureReason.swift`, `Sources/NeedlbarCore/Presentation/ClaudeQuotaPresentationSelector.swift:33,54-76`, `Sources/NeedlbarWidgetSupport/WidgetPresentation.swift:10-21,44-59`, `WidgetExtension/NeedlbarOverviewWidget.swift:61-69,130`, `Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift:114,120-122`, `Sources/Needlbar/Settings/SettingsView.swift:265`
- Create: `Tests/NeedlbarCoreTests/ClaudeUsageReportReasonTests.swift`, `Tests/NeedlbarCoreTests/ClaudeUsageFreshnessTests.swift`, `Tests/NeedlbarTests/ClaudeUsageReportPresentationTests.swift`
- Modify: `Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift:894-906,946-958`, `Tests/NeedlbarCoreTests/ClaudeQuotaPresentationSelectorTests.swift:10-11,23`, `Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift`, `Tests/NeedlbarTests/ClaudeQuotaFreshnessPresentationTests.swift:36,123,186-187,212-241,260`, `Tests/NeedlbarWidgetSupportTests/WidgetProjectionTests.swift`

**Interfaces:**
- Consumes: bridge error codes from Task 4; `ClaudeUsageProbeSchedule.periodicInterval` (Task 6); `RefreshCoordinator.claudeUsageTickInterval` and the `Harness` in `ClaudeUsageProbeCoordinatorTests` (Task 7).
- Produces: `ClaudeQuotaFailureReason` cases `claudeCodeNotInstalled`, `claudeCodeSignInRequired`, `claudeCodeCheckFailed`, `usageReportFormatChanged`, keys `claudeQuota.reason.<case>` and `claudeQuota.reason.<case>.detail`. Selector: newest valid reading wins per window; `recentDirectInterval` is 20 minutes. `WidgetPresentation.claudeQuotaFreshnessHorizon` and `WidgetPresentation.freshness(_ row: WidgetQuotaRow, now: Date)`.

- [ ] **Step 1: Write the failing tests**

`Tests/NeedlbarCoreTests/ClaudeUsageReportReasonTests.swift`:

```swift
import Foundation
import NeedlbarClaudeStatusLineSupport
import NeedlbarWidgetSupport
import Testing
@testable import NeedlbarCore

@Suite("ClaudeUsageReportReasons")
struct ClaudeUsageReportReasonTests {
    @Test(arguments: [
        ("notInstalled", ClaudeQuotaFailureReason.claudeCodeNotInstalled),
        ("requiresAuthentication", .claudeCodeSignInRequired),
        ("providerUnavailable", .claudeCodeCheckFailed),
        ("rateLimited", .temporarilyLimited),
        ("schemaChanged", .usageReportFormatChanged),
        ("internalError", .couldNotUpdateQuota),
        ("", .couldNotUpdateQuota),
    ])
    func eachBridgeCodeMapsToItsStateFromTheSpec(code: String, expected: ClaudeQuotaFailureReason) {
        #expect(ClaudeQuotaFailureReason(errorCode: code, associatedOrigin: nil) == expected)
    }

    @Test func theGuidanceIsInTheShortTextBecauseTheDashboardShowsNoDetailLine() {
        #expect(ClaudeQuotaFailureReason.claudeCodeNotInstalled.displayText == "Install Claude Code to see quota")
        #expect(ClaudeQuotaFailureReason.claudeCodeSignInRequired.displayText == "Sign in with claude in Terminal")
        #expect(ClaudeQuotaFailureReason.claudeCodeCheckFailed.displayText == "Could not check Claude Code")
        #expect(ClaudeQuotaFailureReason.usageReportFormatChanged.displayText == "Could not read Claude Code's usage report")
        #expect(ClaudeQuotaFailureReason.claudeCodeNotInstalled.detailText != nil)
        #expect(ClaudeQuotaFailureReason.claudeCodeSignInRequired.detailText != nil)
        #expect(ClaudeQuotaFailureReason.claudeCodeCheckFailed.detailText == nil)
        #expect(ClaudeQuotaFailureReason.usageReportFormatChanged.detailText == nil)
    }

    @Test func theNewCopyComesFromLocalizableKeys() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("needlbar-usage-report-\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let table = """
        "claudeQuota.reason.claudeCodeNotInstalled" = "A";
        "claudeQuota.reason.claudeCodeNotInstalled.detail" = "B";
        "claudeQuota.reason.claudeCodeSignInRequired" = "C";
        "claudeQuota.reason.claudeCodeSignInRequired.detail" = "D";
        "claudeQuota.reason.claudeCodeCheckFailed" = "E";
        "claudeQuota.reason.usageReportFormatChanged" = "F";
        """
        try Data(table.utf8).write(to: directory.appendingPathComponent("Localizable.strings"))
        let bundle = try #require(Bundle(url: directory))
        #expect(ClaudeQuotaFailureReason.claudeCodeNotInstalled.localizedDisplayText(bundle: bundle) == "A")
        #expect(ClaudeQuotaFailureReason.claudeCodeNotInstalled.localizedDetailText(bundle: bundle) == "B")
        #expect(ClaudeQuotaFailureReason.claudeCodeSignInRequired.localizedDisplayText(bundle: bundle) == "C")
        #expect(ClaudeQuotaFailureReason.claudeCodeSignInRequired.localizedDetailText(bundle: bundle) == "D")
        #expect(ClaudeQuotaFailureReason.claudeCodeCheckFailed.localizedDisplayText(bundle: bundle) == "E")
        #expect(ClaudeQuotaFailureReason.usageReportFormatChanged.localizedDisplayText(bundle: bundle) == "F")
    }

    // MARK: - Source order

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(reportAge: TimeInterval, statusLineAge: TimeInterval, failed: Bool = false) throws -> ProviderSnapshot {
        let reportAt = now.addingTimeInterval(-reportAge)
        return ProviderSnapshot(
            provider: .claude, usage: nil,
            quota: QuotaSnapshot(windows: [try QuotaWindow(id: "claude.weekly", title: "Weekly", usedPercent: 10, resetsAt: nil)]),
            usageStatus: .fresh,
            quotaStatus: failed ? .error(message: "fixture", lastSuccessfulAt: reportAt) : .fresh,
            updatedAt: now, quotaLastSuccessfulAt: reportAt,
            claudeStatusLineQuota: StatusLineQuotaRecord(
                schemaVersion: StatusLineQuotaRecord.currentSchemaVersion, generation: UUID(), fiveHour: nil,
                sevenDay: StatusLineWindowObservation(usedPercent: 40, resetsAt: nil, receivedAt: now.addingTimeInterval(-statusLineAge)))
        )
    }

    @Test func aNewerStatusLineReadingWinsOverARecentReport() throws {
        let selected = ClaudeQuotaPresentationSelector.select(
            snapshot: try snapshot(reportAge: 300, statusLineAge: 30), now: now).sevenDay
        #expect(selected?.source == .claudeCodeStatusLine)
        #expect(selected?.remainingPercent == 60)
    }

    @Test func aNewerReportWinsOverARecentStatusLineEvenAfterALaterFailure() throws {
        let selected = ClaudeQuotaPresentationSelector.select(
            snapshot: try snapshot(reportAge: 30, statusLineAge: 300, failed: true), now: now).sevenDay
        #expect(selected?.source == .direct)
        #expect(selected?.isLastKnown == true)
    }

    @Test func aTieGoesToTheReport() throws {
        let selected = ClaudeQuotaPresentationSelector.select(
            snapshot: try snapshot(reportAge: 60, statusLineAge: 60), now: now).sevenDay
        #expect(selected?.source == .direct)
    }

    // MARK: - Consumers with a window missing

    private func weeklyAndFable() throws -> QuotaSnapshot {
        QuotaSnapshot(windows: [
            try QuotaWindow(id: "claude.weekly", title: "Weekly", usedPercent: 74, resetsAt: now.addingTimeInterval(86_400)),
            try QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "Fable weekly", usedPercent: 0, resetsAt: nil),
        ])
    }

    @Test func theHeadlineUsesTheWeeklyWindowWhenThereIsNoSession() async throws {
        let store = ProviderSnapshotStore(now: { self.now })
        await store.applyQuota(try weeklyAndFable(), for: .claude, at: now)
        let headline = HeadlineQuotaSelector.mostConstrained([await store.snapshot(for: .claude)], now: now)
        #expect(headline?.id == "claude.weekly")
        #expect(headline?.remainingPercent == 26)
    }

    @Test func fableAloneNeverBecomesTheHeadline() async throws {
        let store = ProviderSnapshotStore(now: { self.now })
        await store.applyQuota(QuotaSnapshot(windows: [
            try QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "Fable weekly", usedPercent: 3, resetsAt: nil),
        ]), for: .claude, at: now)
        #expect(HeadlineQuotaSelector.mostConstrained([await store.snapshot(for: .claude)], now: now) == nil)
    }

    @Test func theWidgetAcceptsWeeklyOnlyAndFableOnly() async throws {
        let store = ProviderSnapshotStore(now: { self.now })
        await store.applyQuota(try weeklyAndFable(), for: .claude, at: now)
        var projection = try WidgetProjectionMapper(now: now).map(await store.captureForWidget(exportedAt: now))
        #expect(projection.quotaRows[0].headline?.id == .claudeWeekly)

        await store.applyQuota(QuotaSnapshot(windows: [
            try QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "Fable weekly", usedPercent: 3, resetsAt: nil),
        ]), for: .claude, at: now)
        projection = try WidgetProjectionMapper(now: now).map(await store.captureForWidget(exportedAt: now))
        #expect(projection.quotaRows[0].headline == nil)
    }

    @Test func theExportAcceptsWeeklyOnlyAndDropsFable() async throws {
        let store = ProviderSnapshotStore(now: { self.now })
        await store.applyQuota(try weeklyAndFable(), for: .claude, at: now)
        let data = try SnapshotExporter().encode(await store.captureForExport(exportedAt: now))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("claude.weekly"))
        #expect(!text.contains("claude.session"))
        #expect(!text.contains("claude.fable.weekly"))
    }

    @Test func alertKeysAreUnchangedAndAMissingWindowIsSimplyAbsent() throws {
        #expect(QuotaAlertKey.isAllowed(provider: .claude, windowID: "claude.session"))
        #expect(QuotaAlertKey.isAllowed(provider: .claude, windowID: "claude.weekly"))
        #expect(!QuotaAlertKey.isAllowed(provider: .claude, windowID: QuotaWindow.claudeFableWeeklyID))
    }
}
```

`Tests/NeedlbarTests/ClaudeUsageReportPresentationTests.swift`:

```swift
import Foundation
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore
import NeedlbarClaudeStatusLineSupport

@Suite("ClaudeUsageReportPresentation")
@MainActor
struct ClaudeUsageReportPresentationTests {
    private let now = Date()

    private func claude(
        windows: [QuotaWindow]?, reason: ClaudeQuotaFailureReason? = nil, age: TimeInterval = 60,
        statusLine: StatusLineQuotaRecord? = nil
    ) -> ProviderSnapshot {
        let at = now.addingTimeInterval(-age)
        return ProviderSnapshot(
            provider: .claude, usage: nil, quota: windows.map { QuotaSnapshot(windows: $0) }, usageStatus: .fresh,
            quotaStatus: reason == nil ? .fresh : .error(message: "fixture", lastSuccessfulAt: windows == nil ? nil : at),
            updatedAt: now, claudeQuotaFailureReason: reason,
            quotaLastSuccessfulAt: windows == nil ? nil : at, claudeStatusLineQuota: statusLine)
    }

    private func weekly() throws -> QuotaWindow {
        try QuotaWindow(id: "claude.weekly", title: "Weekly", usedPercent: 74, resetsAt: now.addingTimeInterval(86_400))
    }

    private func fable() throws -> QuotaWindow {
        try QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "Fable weekly", usedPercent: 0, resetsAt: nil)
    }

    private func dashboardRow(_ snapshot: ProviderSnapshot) -> SystemDashboardPresentation.AIProvider {
        let combined = CombinedUsageSnapshot(system: nil, providers: [
            snapshot,
            ProviderSnapshot(provider: .codex, usage: nil, quota: nil, usageStatus: .fresh, quotaStatus: .unavailable, updatedAt: now),
            ProviderSnapshot(provider: .cursor, usage: nil, quota: nil, usageStatus: .fresh, quotaStatus: .unavailable, updatedAt: now),
        ], capturedAt: now, systemAvailability: [:])
        let configuration = SystemMonitorConfiguration(aiOrder: [.claude, .codex, .cursor], dashboardVisibleModules: [.ai])
        return SystemDashboardPresentation(snapshot: combined, configuration: configuration, now: now)
            .ai.first { $0.provider == .claude }!
    }

    @Test func weeklyOnlyShowsNoSessionRowAndNoMadeUpZero() throws {
        let snapshot = claude(windows: [try weekly(), try fable()])
        let popover = ProviderPopoverPresentation(snapshot: snapshot, now: now)
        #expect(popover.claudeFiveHour == nil)
        #expect(popover.claudeSevenDay?.remaining == "26%")
        #expect(popover.claudeFable?.remaining == "100%")
        #expect(popover.headlineQuotaRemaining == "26%")
        #expect(!popover.quotaUnavailable)
        #expect(dashboardRow(snapshot).compactQuotaValue == "26%")
    }

    @Test func onlyFableIsNotQuotaUnavailableAndHasNoHeadline() throws {
        let popover = ProviderPopoverPresentation(snapshot: claude(windows: [try fable()]), now: now)
        #expect(!popover.quotaUnavailable)
        #expect(popover.claudeFable != nil)
        #expect(popover.headlineQuotaRemaining == nil)
        #expect(dashboardRow(claude(windows: [try fable()])).compactQuotaValue == "—")
    }

    @Test func noWindowsAtAllStaysQuotaUnavailableWithoutAValue() {
        let popover = ProviderPopoverPresentation(
            snapshot: claude(windows: nil, reason: .claudeCodeNotInstalled), now: now)
        #expect(popover.quotaUnavailable)
        #expect(popover.headlineQuotaRemaining == nil)
        #expect(popover.lastKnownQuotaRemaining == nil)
        #expect(popover.quotaLastCheckedText == nil)
    }

    @Test func failuresKeepLastKnownValuesWithTheirCheckedTime() throws {
        for reason in [ClaudeQuotaFailureReason.claudeCodeCheckFailed, .temporarilyLimited, .usageReportFormatChanged] {
            let popover = ProviderPopoverPresentation(
                snapshot: claude(windows: [try weekly()], reason: reason, age: 7_200), now: now)
            #expect(popover.quotaIsLastKnown)
            #expect(popover.lastKnownQuotaRemaining == "26%")
            #expect(popover.quotaLastCheckedText != nil)
            #expect(popover.quotaFailureReasonText == reason.displayText)
        }
    }

    @Test func notInstalledAndSignedOutOfferTheUsageLinkAndNoLaunchButton() throws {
        for reason in [ClaudeQuotaFailureReason.claudeCodeNotInstalled, .claudeCodeSignInRequired] {
            let popover = ProviderPopoverPresentation(snapshot: claude(windows: nil, reason: reason), now: now)
            #expect(popover.quotaFailureReasonText == reason.displayText)
            #expect(popover.quotaFailureDetailText == reason.detailText)
            #expect(popover.authenticationAction == .openClaudeUsage(title: "View Claude usage"))
            #expect(!popover.requiresProviderSignIn)
            #expect(dashboardRow(claude(windows: nil, reason: reason)).quotaFailureReasonText == reason.displayText)
        }
    }

    @Test func withRecentStatusLineValuesTheGuidanceMovesToTheFableLine() throws {
        let record = StatusLineQuotaRecord(
            schemaVersion: StatusLineQuotaRecord.currentSchemaVersion, generation: UUID(),
            fiveHour: StatusLineWindowObservation(usedPercent: 25, resetsAt: nil, receivedAt: now.addingTimeInterval(-30)),
            sevenDay: StatusLineWindowObservation(usedPercent: 35, resetsAt: nil, receivedAt: now.addingTimeInterval(-30)))
        for reason in [ClaudeQuotaFailureReason.claudeCodeNotInstalled, .claudeCodeSignInRequired] {
            let popover = ProviderPopoverPresentation(
                snapshot: claude(windows: [try fable()], reason: reason, age: 3_600, statusLine: record), now: now)
            #expect(popover.hasRecentClaudeQuota)
            #expect(popover.quotaFailureReasonText == nil)
            #expect(popover.fableFailureReasonText == reason.displayText)
        }
    }

    @Test func noCopyOffersAnAutomaticSignIn() {
        for reason in [ClaudeQuotaFailureReason.claudeCodeNotInstalled, .claudeCodeSignInRequired,
                       .claudeCodeCheckFailed, .usageReportFormatChanged] {
            let text = "\(reason.displayText) \(reason.detailText ?? "")"
            for forbidden in ["Keychain", "credential", "Always Allow", "token"] {
                #expect(!text.localizedCaseInsensitiveContains(forbidden), "\(reason) \(forbidden)")
            }
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeUsageReportReasonTests`
Expected: FAIL to compile with `type 'ClaudeQuotaFailureReason' has no member 'claudeCodeNotInstalled'`.

- [ ] **Step 3: Add the reasons**

In `Sources/NeedlbarCore/Models/ClaudeQuotaFailureReason.swift`, add the cases:

```swift
    /// No executable `claude` at the fixed locations.
    case claudeCodeNotInstalled
    /// `rate_limits` was null, or `limits` was null or empty.
    case claudeCodeSignInRequired
    /// The run timed out, produced too much output, or did not finish.
    case claudeCodeCheckFailed
    /// A run finished without a usable usage report.
    case usageReportFormatChanged
```

Add to `localizedDisplayText`:

```swift
        case .claudeCodeNotInstalled:
            String(
                localized: "claudeQuota.reason.claudeCodeNotInstalled",
                defaultValue: "Install Claude Code to see quota",
                bundle: bundle,
                comment: "Claude quota reason: the Claude Code command-line tool was not found on this Mac. Shown beside the View Claude usage link."
            )
        case .claudeCodeSignInRequired:
            String(
                localized: "claudeQuota.reason.claudeCodeSignInRequired",
                defaultValue: "Sign in with claude in Terminal",
                bundle: bundle,
                comment: "Claude quota reason: Claude Code reported no usage, usually because it is signed out. Keep 'claude' as the command name. Needlbar offers no button for this."
            )
        case .claudeCodeCheckFailed:
            String(
                localized: "claudeQuota.reason.claudeCodeCheckFailed",
                defaultValue: "Could not check Claude Code",
                bundle: bundle,
                comment: "Claude quota reason: running Claude Code to read usage timed out, produced too much output, or did not finish."
            )
        case .usageReportFormatChanged:
            String(
                localized: "claudeQuota.reason.usageReportFormatChanged",
                defaultValue: "Could not read Claude Code's usage report",
                bundle: bundle,
                comment: "Claude quota reason: Claude Code finished but gave no usage report Needlbar can read."
            )
```

Add to `localizedDetailText`:

```swift
        case .claudeCodeNotInstalled:
            String(
                localized: "claudeQuota.reason.claudeCodeNotInstalled.detail",
                defaultValue: "Needlbar reads quota from the Claude Code command-line tool and did not find it on this Mac. View Claude usage still opens the usage page.",
                bundle: bundle,
                comment: "Second line for the not-installed reason, shown in the provider popover and Settings."
            )
        case .claudeCodeSignInRequired:
            String(
                localized: "claudeQuota.reason.claudeCodeSignInRequired.detail",
                defaultValue: "Claude Code reported no usage for this Mac. Needlbar updates at its next check and never opens a sign-in itself.",
                bundle: bundle,
                comment: "Second line for the sign-in reason, shown in the provider popover and Settings."
            )
```

Add `.claudeCodeCheckFailed, .usageReportFormatChanged` to the `nil` case list of `localizedDetailText`, and all four new cases to the `nil` lists of `localizedKeychainAccessActionTitle` and `localizedKeychainAccessActionDetail`. Replace the mapping initializer body with:

```swift
        switch (errorCode, associatedOrigin) {
        case ("authenticationExpired", .keychainCredentialExpired?),
             ("authenticationExpired", .fileCredentialExpired?):
            self = .claudeCodeAccessExpired
        case ("notInstalled", _): self = .claudeCodeNotInstalled
        case ("requiresAuthentication", _): self = .claudeCodeSignInRequired
        case ("authenticationExpired", _): self = .quotaAccessUnavailable
        case ("permissionDenied", _): self = .credentialAccessUnavailable
        case ("networkUnavailable", _): self = .connectionUnavailable
        case ("rateLimited", _): self = .temporarilyLimited
        case ("providerUnavailable", _): self = .claudeCodeCheckFailed
        case ("schemaChanged", _): self = .usageReportFormatChanged
        default: self = .couldNotUpdateQuota
        }
```

- [ ] **Step 4: Make the newest valid reading win**

Replace `choose` in `Sources/NeedlbarCore/Presentation/ClaudeQuotaPresentationSelector.swift`:

```swift
    /// A newer valid reading wins regardless of source (spec §5), the report on a
    /// tie. A reading whose time is unusable ranks below any dated one.
    private static func choose(
        direct: QuotaWindow?,
        statusLine: StatusLineWindowObservation?,
        snapshot: ProviderSnapshot,
        now: Date
    ) -> DisplayedClaudeWindow? {
        let directDisplay = direct.map { directWindow($0, snapshot: snapshot, now: now) }
        let statusDisplay = statusLine.flatMap { statusLineWindow($0, now: now) }
        switch (directDisplay, statusDisplay) {
        case let (.some(direct), .some(bridge)):
            switch (direct.observedAt, bridge.observedAt) {
            case let (.some(a), .some(b)): return a >= b ? direct : bridge
            case (.some, nil): return direct
            case (nil, .some): return bridge
            case (nil, nil): return direct
            }
        case let (.some(direct), nil): return direct
        case let (nil, .some(bridge)): return bridge
        case (nil, nil): return nil
        }
    }
```

- [ ] **Step 5: Fix the presentation and Settings copy**

In `Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift`:

```swift
            quotaUnavailable = !hasRecentClaudeQuota && main.isEmpty && projectedFallback.isEmpty && selected.fable == nil
```

```swift
            let reasonSitsOnTheFableLine = reason == .claudeCodeAccessExpired || reason == .credentialAccessUnavailable
                || reason == .claudeCodeNotInstalled || reason == .claudeCodeSignInRequired
            fableFailureReasonText = hasRecentClaudeQuota && reasonSitsOnTheFableLine ? reason?.displayText : nil
```

Update the comment above it to read: "While status-line windows are recent, a reason the user can act on is shown once, on the Fable line it keeps from updating."

In `Sources/Needlbar/Settings/SettingsView.swift:265`:

```swift
                Text("Quota comes from Claude Code's /usage report, run on this Mac. Sign-in stays with Claude Code.")
```

- [ ] **Step 6: Update the mapping tables**

In `Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift`, in both tables (`returnedClaudeQuotaErrorsMapOnlyAllowlistedCodesToSafeReasons` and `bridgeFailuresAndUntypedQuotaFailuresUseSafeClaudeReasons`), change these rows:

```swift
            ("requiresAuthentication", .claudeCodeSignInRequired),
            ("notInstalled", .claudeCodeNotInstalled),
            ("providerUnavailable", .claudeCodeCheckFailed),
            ("schemaChanged", .usageReportFormatChanged),
```

In `Tests/NeedlbarTests/ClaudeQuotaFreshnessPresentationTests.swift`, `ageBoundarySwitchesEverySurfaceFromDirectToCurrentBridge` asserts the old rule: its bridge reading is already newer than the report in the first frame. Run this once to make it assert the new rule across every surface:

```bash
/usr/bin/python3 -I - <<'PY'
import pathlib
path = pathlib.Path("Tests/NeedlbarTests/ClaudeQuotaFreshnessPresentationTests.swift")
source = path.read_text()
start = source.index("func ageBoundarySwitchesEverySurfaceFromDirectToCurrentBridge")
end = source.index("    @Test", start)
body = source[start:end]
for old, new in [
    ("func ageBoundarySwitchesEverySurfaceFromDirectToCurrentBridge", "func aNewerCurrentBridgeWinsOnEverySurfaceAcrossTheDirectAgeBoundary"),
    ("receivedAt: success.addingTimeInterval(1)), sevenDay: nil)", "receivedAt: success.addingTimeInterval(800)), sevenDay: nil)"),
    ('#expect(values == ["75%", "50%"])', '#expect(values == ["50%", "50%"])'),
    ('#expect(sources == ["Claude usage", "Reported by Claude Code"])', '#expect(sources == ["Reported by Claude Code", "Reported by Claude Code"])'),
]:
    assert old in body, old
    body = body.replace(old, new)
path.write_text(source[:start] + body + source[end:])
PY
```

In `Tests/NeedlbarCoreTests/ClaudeQuotaPresentationSelectorTests.swift`, the test `failedDirectStreamRetainsValueAndTimestampButPrefersRecentBridge` still passes because its bridge reading is newer. Run the suites; if another test asserts that an older recent status line beats a newer last-known report, or that an older recent report beats a newer status line, change its expectation to the newest reading and name the test in the commit message, because spec §5 requires that.

- [ ] **Step 7: Run tests to verify they pass**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeUsageReport`
Expected: PASS for both new suites.

Run: `make swift-test`
Expected: PASS.

- [ ] **Step 8: Write the failing freshness tests**

A run every 15 minutes through a 60-second tick with a run of up to 31 s finishes up to 16:31 after the last start, so a 15-minute window flips the label just before each refresh (Decisions 3a).

`Tests/NeedlbarCoreTests/ClaudeUsageFreshnessTests.swift`:

```swift
import Foundation
import Testing
@testable import NeedlbarCore

@Suite("ClaudeUsageFreshness")
struct ClaudeUsageFreshnessTests {
    private let success = Date(timeIntervalSince1970: 1_800_000_000)

    private func report(status: DataStatus = .fresh) throws -> ProviderSnapshot {
        ProviderSnapshot(
            provider: .claude, usage: nil,
            quota: QuotaSnapshot(windows: [try QuotaWindow(
                id: "claude.weekly", title: "Weekly", usedPercent: 74, resetsAt: success.addingTimeInterval(86_400))]),
            usageStatus: .fresh, quotaStatus: status, updatedAt: success, quotaLastSuccessfulAt: success)
    }

    @Test(arguments: [1_199.0, 1_200.0, 1_201.0])
    func aReportStaysCurrentForTwentyMinutes(age: Double) throws {
        let selected = ClaudeQuotaPresentationSelector.select(
            snapshot: try report(), now: success.addingTimeInterval(age)).sevenDay
        #expect(selected?.isLastKnown == (age >= 1_200))
        #expect(selected?.observedAt == success)
    }

    @Test func theWindowOutlastsTheSlowestPeriodicRefresh() {
        let tick = TimeInterval(RefreshCoordinator.claudeUsageTickInterval.components.seconds)
        // The process deadline plus its termination grace, from `claude_usage_probe.rs`.
        let slowestRun: TimeInterval = 30 + 1
        #expect(ClaudeQuotaPresentationSelector.recentDirectInterval
            > ClaudeUsageProbeSchedule.periodicInterval + tick + slowestRun)
    }

    @Test(arguments: [900.0, 1_199.0, 1_200.0, 7_200.0])
    func aFailedRunIsLastKnownAtOnceAndKeepsItsCheckedTime(age: Double) throws {
        let failed = try report(status: .error(message: "fixture", lastSuccessfulAt: success))
        let selected = ClaudeQuotaPresentationSelector.select(
            snapshot: failed, now: success.addingTimeInterval(age)).sevenDay
        #expect(selected?.isLastKnown == true)
        #expect(selected?.observedAt == success)
        #expect(selected?.remainingPercent == 26)
    }

    @Test func theStatusLineWindowsDoNotChange() {
        #expect(ClaudeQuotaPresentationSelector.recentStatusLineInterval == 15 * 60)
        #expect(ClaudeQuotaPresentationSelector.maximumStatusLineAge == 24 * 60 * 60)
    }
}
```

Add to `ClaudeUsageProbeCoordinatorTests`, under `// MARK: - Backoff`:

```swift
    @Test func aReadingStaysCurrentUntilThePeriodicRefreshReplacesIt() async throws {
        let far = Self.start.addingTimeInterval(9_000_000)
        let harness = Harness()
        harness.probe.script(.result(try weeklyQuota(resetsAt: far)))
        harness.probe.script(.result(try weeklyQuota(resetsAt: far)))
        await harness.startedAndIdle()
        await harness.advance(minutes: 14)
        // The slowest refresh finishes 991 s after the last start.
        let beforeRefresh = ClaudeQuotaPresentationSelector.select(
            snapshot: await harness.store.snapshot(for: .claude), now: Self.start.addingTimeInterval(991)).sevenDay
        #expect(beforeRefresh?.isLastKnown == false)
        #expect(beforeRefresh?.observedAt == Self.start)

        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)
        let afterRefresh = ClaudeQuotaPresentationSelector.select(
            snapshot: await harness.store.snapshot(for: .claude), now: harness.clock.now).sevenDay
        #expect(afterRefresh?.isLastKnown == false)
        #expect(afterRefresh?.observedAt == Self.start.addingTimeInterval(900))
        await harness.coordinator.stop()
    }
```

Add to `WidgetProjectionTests` in `Tests/NeedlbarWidgetSupportTests/WidgetProjectionTests.swift`:

```swift
    @Test
    func aClaudeQuotaRowStaysFreshForTwentyMinutesAndOthersForFifteen() throws {
        let now = referenceDate
        func quotaRow(_ provider: WidgetProvider, age: TimeInterval) throws -> WidgetQuotaRow {
            try WidgetQuotaRow(provider: provider, stream: .fresh, lastSuccessfulAt: now.addingTimeInterval(-age), headline: nil)
        }
        #expect(WidgetPresentation.freshness(try quotaRow(.claude, age: 1_199), now: now) == .fresh)
        #expect(WidgetPresentation.freshness(try quotaRow(.claude, age: 1_200), now: now) == .stale)
        #expect(WidgetPresentation.freshness(try quotaRow(.codex, age: 899), now: now) == .fresh)
        #expect(WidgetPresentation.freshness(try quotaRow(.codex, age: 900), now: now) == .stale)
    }

    @Test
    func theNextDeadlineUsesTheClaudeQuotaRowsOwnHorizon() throws {
        let projection = try WidgetProjection(
            quotaRows: [
                try WidgetQuotaRow(provider: .claude, stream: .fresh, lastSuccessfulAt: referenceDate, headline: nil),
                try WidgetQuotaRow(provider: .codex, stream: .unavailable, lastSuccessfulAt: nil, headline: nil),
            ],
            usageRows: makeUnavailableUsageRows(),
            today: unavailableToday
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(WidgetPresentation.nextDeadline(after: referenceDate, projection: projection, calendar: calendar)
            == referenceDate.addingTimeInterval(1_200))
    }
```

- [ ] **Step 9: Run tests to verify they fail**

The widget tests call an overload that does not exist yet, so nothing compiles until Step 10 adds it. To see the freshness failures first, leave the two widget tests out of the file until Step 10.

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeUsageFreshnessTests`
Expected: FAIL at `aReportStaysCurrentForTwentyMinutes(age: 1199.0)` and `theWindowOutlastsTheSlowestPeriodicRefresh`.

- [ ] **Step 10: Change the freshness windows**

Add the two widget tests from Step 8 if they were left out, then in `Sources/NeedlbarCore/Presentation/ClaudeQuotaPresentationSelector.swift`:

```swift
    /// Longer than the slowest periodic refresh, which can finish 16:31 after the
    /// last run started, so the label does not flip just before each refresh.
    public static let recentDirectInterval: TimeInterval = 20 * 60
```

Leave `recentStatusLineInterval` and `maximumStatusLineAge` as they are.

In `Sources/NeedlbarWidgetSupport/WidgetPresentation.swift`, keep `freshnessHorizon` and change these parts. Existing callers of `freshness(_:lastSuccessfulAt:now:)` keep 15 minutes through the default:

```swift
    public static let freshnessHorizon: TimeInterval = 15 * 60
    /// Claude quota can refresh only every 15 minutes, while Codex and usage refresh
    /// every 5, so its row keeps the app's 20-minute window.
    public static let claudeQuotaFreshnessHorizon: TimeInterval = 20 * 60

    private static func quotaHorizon(for provider: WidgetProvider) -> TimeInterval {
        provider == .claude ? claudeQuotaFreshnessHorizon : freshnessHorizon
    }

    public static func freshness(
        _ state: WidgetStreamState,
        lastSuccessfulAt: Date?,
        now: Date,
        horizon: TimeInterval = freshnessHorizon
    ) -> WidgetDisplayFreshness {
        guard let timestamp = lastSuccessfulAt, timestamp <= now else {
            return .unavailable
        }
        return state == .fresh && now.timeIntervalSince(timestamp) < horizon ? .fresh : .stale
    }

    public static func freshness(_ row: WidgetQuotaRow, now: Date) -> WidgetDisplayFreshness {
        freshness(row.stream, lastSuccessfulAt: row.lastSuccessfulAt, now: now, horizon: quotaHorizon(for: row.provider))
    }
```

and in `nextDeadline`:

```swift
        let stale = projection.quotaRows.compactMap { row in
            row.lastSuccessfulAt?.addingTimeInterval(quotaHorizon(for: row.provider))
        } + projection.usageRows.compactMap { $0.lastSuccessfulAt?.addingTimeInterval(freshnessHorizon) }
```

In `WidgetExtension/NeedlbarOverviewWidget.swift`, `overallFreshnessLabel` becomes:

```swift
    private var overallFreshnessLabel: String {
        guard let projection = entry.projection else { return "Quota unavailable" }
        let quotaIsFresh = projection.quotaRows.allSatisfy {
            WidgetPresentation.freshness($0, now: entry.date) == .fresh
        }
        let usageIsFresh = projection.usageRows.allSatisfy {
            WidgetPresentation.freshness($0.stream, lastSuccessfulAt: $0.lastSuccessfulAt, now: entry.date) == .fresh
        }
        return quotaIsFresh && usageIsFresh ? "Fresh" : "Stale"
    }
```

and in `quotaLine`, change the condition to `WidgetPresentation.freshness(row!, now: entry.date) == .fresh`.

- [ ] **Step 11: Update the tests that pin the old boundary**

Run this once from the repository root. It changes only tests of the direct window. These pin the status-line window and stay as they are: `ClaudeQuotaFreshnessPresentationTests.swift:127`, `ClaudeQuotaPresentationSelectorTests.swift:115-126,251-261`, `ClaudeStatusLineMaximumAgeTests.swift:76-82`, `ClaudeStatusLineMaximumAgePresentationTests.swift:107`, `PopoverPresentationTests.swift:273`, `SystemDashboardPopoverTests.swift:615`, `HeadlineQuotaSelectorTests.swift:95,124`. `ClaudeQuotaPresentationSelectorTests.swift:69` has a failed status, so its 1,000-second age does not matter.

```bash
/usr/bin/python3 -I - <<'PY'
import pathlib

def edit(name, pairs):
    path = pathlib.Path(name)
    source = path.read_text()
    for old, new, count in pairs:
        assert source.count(old) == count, (old, source.count(old))
        source = source.replace(old, new)
    path.write_text(source)

edit("Tests/NeedlbarCoreTests/ClaudeQuotaPresentationSelectorTests.swift", [
    ('''    @Test(arguments: [899.0, 900.0, 901.0])
    func directObservationExpiresAtStrictFifteenMinuteBoundary(age: Double) throws {''',
     '''    @Test(arguments: [1_199.0, 1_200.0, 1_201.0])
    func directObservationExpiresAtStrictTwentyMinuteBoundary(age: Double) throws {''', 1),
    ("#expect(selected.fiveHour?.isLastKnown == (age >= 900))", "#expect(selected.fiveHour?.isLastKnown == (age >= 1_200))", 1),
])
edit("Tests/NeedlbarTests/ClaudeQuotaFreshnessPresentationTests.swift", [
    # Lines 36, 224 and 260: the three tickers that cross the direct boundary.
    ("TwoFrameQuotaClock(initial: success.addingTimeInterval(899))", "TwoFrameQuotaClock(initial: success.addingTimeInterval(1_199))", 3),
    # Line 123.
    ('("direct age", [try window()], success, nil, 899,', '("direct age", [try window()], success, nil, 1_199,', 1),
    # Lines 186-187.
    ("settings.reproject(at: now.addingTimeInterval(900))", "settings.reproject(at: now.addingTimeInterval(1_200))", 1),
    ("dashboard.reproject(at: now.addingTimeInterval(900))", "dashboard.reproject(at: now.addingTimeInterval(1_200))", 1),
])
PY
```

- [ ] **Step 12: Run tests to verify they pass**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeUsageFreshnessTests`
Expected: PASS.

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeQuotaFreshnessPresentationTests`
Expected: PASS.

Run: `make swift-test SWIFT_TEST_FILTER=WidgetProjectionTests`
Expected: PASS, including the unchanged `exactlyFifteenMinutesOldFreshValueIsStale`.

Run: `make widget-extension-test`
Expected: exits 0.

Run: `make swift-test`
Expected: PASS. If a test outside the Step 11 list fails because a Claude report between 15 and 20 minutes old is now current, change its age or expectation to match the 20-minute window and name it in the commit message.

- [ ] **Step 13: Commit**

```bash
git add Sources/NeedlbarCore/Models/ClaudeQuotaFailureReason.swift Sources/NeedlbarCore/Presentation/ClaudeQuotaPresentationSelector.swift Sources/NeedlbarWidgetSupport/WidgetPresentation.swift WidgetExtension/NeedlbarOverviewWidget.swift Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift Sources/Needlbar/Settings/SettingsView.swift Tests/NeedlbarCoreTests/ClaudeUsageReportReasonTests.swift Tests/NeedlbarCoreTests/ClaudeUsageFreshnessTests.swift Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift Tests/NeedlbarTests/ClaudeUsageReportPresentationTests.swift Tests/NeedlbarTests/ClaudeQuotaFreshnessPresentationTests.swift Tests/NeedlbarWidgetSupportTests/WidgetProjectionTests.swift Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift Tests/NeedlbarCoreTests/ClaudeQuotaPresentationSelectorTests.swift
git commit -m "feat: add usage report failure copy, source order and freshness window

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 9: Switch production to the usage report

After this task the app reads Claude quota only through `/usage`. The old Rust path still exists but nothing automatic reaches it.

**Files:**
- Modify: `crates/needlbar-bridge/src/quota.rs:53-69,139-146`, `crates/needlbar-bridge/src/test_runtime.rs` (`AllQuotaProviders`, `all_quota_providers`), `crates/needlbar-bridge/src/diagnostics.rs:33-38,61-64`, `crates/needlbar-bridge/tests/quota_contract.rs`, `crates/needlbar-bridge/tests/redaction_contract.rs`
- Modify: `Sources/Needlbar/App/AppDelegate.swift:191-199`, `Sources/NeedlbarCore/Refresh/UsageFileWatcher.swift:175`
- Test: as listed

**Interfaces:**
- Consumes: `RefreshCoordinator(claudeUsageRepository:)` (Task 7); `needlbar_claude_usage_report_quota_snapshot_json` (Task 4).
- Produces: `quota::collect_quota_with_providers(codex, cursor)`, `test_runtime::background_quota_providers()`, diagnostics `quotaSource` `usageReport` for Claude.

- [ ] **Step 1: Write the failing tests**

In `crates/needlbar-bridge/tests/quota_contract.rs`, delete `ordinary_all_provider_collection_uses_background_claude_credential_access`, `struct BusyClaudeResolver` and `busy_claude_keychain_read_is_skipped_while_codex_and_cursor_still_report`. Replace `quota_collection_keeps_successes_and_stable_provider_order_when_codex_auth_fails` and `quota_collection_with_only_provider_errors_is_a_successful_bridge_response` with:

```rust
#[tokio::test]
async fn background_collection_never_names_claude_and_keeps_codex_and_cursor_independent() {
    let collection = collect_quota_with_providers(
        Arc::new(FakeProvider {
            result: Err(authentication_error()),
        }),
        Arc::new(FakeProvider {
            result: Ok(successful_snapshot(ProviderId::Cursor, "cursor.plan")),
        }),
    )
    .await;
    assert!(!collection.claude_attempted);
    let value = serde_json::to_value(envelope_from_collection(collection)).expect("quota envelope");
    assert_eq!(value["ok"], true);
    assert_eq!(value["data"]["providers"].as_array().unwrap().len(), 1);
    assert_eq!(value["data"]["providers"][0]["provider"], "cursor");
    assert_eq!(value["errors"].as_array().unwrap().len(), 1);
    assert_eq!(value["errors"][0]["provider"], "codex");
    assert_eq!(value["errors"][0]["code"], "requiresAuthentication");
}

#[tokio::test]
async fn background_collection_with_only_provider_errors_is_a_successful_bridge_response() {
    let collection = collect_quota_with_providers(
        Arc::new(FakeProvider {
            result: Err(authentication_error()),
        }),
        Arc::new(FakeProvider {
            result: Err(QuotaError::new(
                Some(ProviderId::Cursor),
                QuotaErrorCode::ProviderUnavailable,
                "Cursor personal quota is unavailable.",
            )),
        }),
    )
    .await;
    let value = serde_json::to_value(envelope_from_collection(collection)).expect("quota envelope");
    assert_eq!(value["ok"], true);
    assert_eq!(value["data"]["providers"], serde_json::json!([]));
    assert_eq!(value["errors"].as_array().unwrap().len(), 2);
    assert_eq!(value["errors"][0]["provider"], "codex");
    assert_eq!(value["errors"][1]["provider"], "cursor");
    assert_eq!(value["errors"][1]["code"], "providerUnavailable");
}
```

In `crates/needlbar-bridge/tests/redaction_contract.rs`, import `needlbar_claude_usage_report_quota_snapshot_json`, and add below the constants:

```rust
unsafe extern "C" fn claude_usage_report_export() -> *const c_char {
    needlbar_claude_usage_report_quota_snapshot_json(1)
}
```

In `provider_credential_canaries_never_cross_real_bridge_envelopes`, add `let claude_report = ffi_json(claude_usage_report_export);` before `let diagnostics = …`, add `assert_safe_output(&claude_report);`, and replace the assertions on `quota_value["errors"]` with:

```rust
    assert!(quota_value["errors"]
        .as_array()
        .expect("quota errors")
        .iter()
        .all(|error| error["provider"] != "claude"));
    assert_eq!(quota_value["errors"][0]["code"], "networkUnavailable");
    assert_eq!(quota_value["errors"][1]["provider"], "cursor");
    assert_eq!(quota_value["errors"][1]["code"], "providerUnavailable");
    assert!(quota_value["errors"][1].get("action").is_none());
    let claude_value: serde_json::Value =
        serde_json::from_str(&claude_report).expect("Claude report JSON");
    assert_error_shape(&claude_value["errors"], "requiresAuthentication");
```

Add a test:

```rust
#[test]
fn claude_diagnostics_name_the_usage_report_source_and_record_the_run() {
    let _serial = test_runtime::serial_guard();
    test_runtime::install_provider_verification_fixture(
        Ok(test_runtime::fixture_snapshot(ProviderId::Claude, "claude.weekly", 20.0)),
        Ok(test_runtime::fixture_snapshot(ProviderId::Codex, "codex.primary", 50.0)),
    );
    let _clear = RuntimeCleanup;
    let _ = ffi_json(claude_usage_report_export);
    let diagnostics = diagnostics_by_provider(&ffi_json(needlbar_diagnostics_json));
    assert_eq!(diagnostics["claude"]["quotaSource"], "usageReport");
    assert_eq!(diagnostics["codex"]["quotaSource"], "oauth");
    assert_eq!(diagnostics["claude"]["claudeUsageProbe"]["durationMs"], 1);
    assert_eq!(diagnostics["claude"]["quotaStatus"], "available");
}
```

In `Tests/NeedlbarCoreTests/BridgeIntegrationSmokeTests.swift`, inside the existing `fixtureBridgeABISnapshotsMergeAllProvidersAndPreservePartialFailure`, add directly after `let quota = try RustQuotaRepository(bridge: bridge).refresh()`. It stays inside this test because a second concurrent fixture session would be refused:

```swift
    #expect(quota.snapshots[.claude] == nil)
    #expect(quota.errors[.claude] == nil)
    #expect(quota.snapshots[.codex] != nil)
    let report = try RustQuotaRepository(bridge: bridge).refresh(intent: .claudeUsageReport(runID: 1))
    #expect(report.snapshots[.claude] != nil)
```

Production wiring is checked by the source contract in Task 12.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cargo test -p needlbar-bridge --features bridge-test-runtime --test quota_contract`
Expected: FAIL to compile, `collect_quota_with_providers` takes 3 arguments.

- [ ] **Step 3: Remove Claude from the aggregate**

In `crates/needlbar-bridge/src/quota.rs`:

```rust
/// Collects Codex and Cursor concurrently. Claude has its own collection and
/// slot, so a run of up to 30 seconds cannot hold these two.
pub async fn collect_quota() -> QuotaCollection {
    #[cfg(feature = "bridge-test-runtime")]
    if let Some((codex, cursor)) = crate::test_runtime::background_quota_providers() {
        return collect_quota_with_providers(codex, cursor).await;
    }
    #[cfg(feature = "bridge-test-runtime")]
    return test_runtime_unavailable_collection();
    #[cfg(not(feature = "bridge-test-runtime"))]
    {
        collect_quota_with_providers(
            Arc::new(CodexQuotaProvider::new()),
            Arc::new(CursorQuotaProvider::new()),
        )
        .await
    }
}
```

```rust
pub async fn collect_quota_with_providers(
    codex: Arc<dyn QuotaProvider>,
    cursor: Arc<dyn QuotaProvider>,
) -> QuotaCollection {
    let (codex, cursor) = tokio::join!(codex.fetch(), cursor.fetch());
    collection_from_results([codex, cursor])
}
```

In `crates/needlbar-bridge/src/test_runtime.rs`, change `type AllQuotaProviders` to a two-tuple named `BackgroundQuotaProviders` and replace `all_quota_providers` with:

```rust
/// Factory-level fixture injection for the Codex and Cursor refresh.
pub fn background_quota_providers() -> Option<BackgroundQuotaProviders> {
    let runtime = fixture_runtime()?;
    let cursor_unavailable = || {
        Err(QuotaError::new(
            Some(ProviderId::Cursor),
            QuotaErrorCode::ProviderUnavailable,
            "Cursor personal quota is available in Cursor Spending.",
        ))
    };
    Some(match runtime.mode {
        FixtureMode::Integration => (
            Arc::new(FixtureQuotaProvider::success(ProviderId::Codex, "codex.primary", 50.0)),
            Arc::new(FixtureQuotaProvider::failure(
                ProviderId::Cursor,
                QuotaErrorCode::ProviderUnavailable,
                "Cursor quota is unavailable in Needlbar.".to_owned(),
            )),
        ),
        FixtureMode::Redaction {
            codex_failure,
            cursor_failure,
            ..
        } => (
            Arc::new(FixtureQuotaProvider::failure(
                ProviderId::Codex,
                QuotaErrorCode::NetworkUnavailable,
                codex_failure,
            )),
            Arc::new(FixtureQuotaProvider::failure(
                ProviderId::Cursor,
                QuotaErrorCode::ProviderUnavailable,
                cursor_failure,
            )),
        ),
        FixtureMode::ProviderVerification(fixture) => {
            fixture.record_creation(ProviderId::Codex);
            fixture.record_creation(ProviderId::Cursor);
            (
                Arc::new(ProviderVerificationQuotaProvider::new(
                    ProviderId::Codex,
                    fixture.codex_result.clone(),
                    fixture.clone(),
                )),
                Arc::new(ProviderVerificationQuotaProvider::new(
                    ProviderId::Cursor,
                    cursor_unavailable(),
                    fixture,
                )),
            )
        }
        FixtureMode::ProviderVerificationBlocking(blocking) => (
            Arc::new(ProviderVerificationQuotaProvider::new(
                ProviderId::Codex,
                blocking.fixture.codex_result.clone(),
                blocking.fixture.clone(),
            )),
            Arc::new(ProviderVerificationQuotaProvider::new(
                ProviderId::Cursor,
                cursor_unavailable(),
                blocking.fixture,
            )),
        ),
        FixtureMode::ProviderVerificationPanic => (Arc::new(PanicProvider), Arc::new(PanicProvider)),
    })
}
```

`usage_envelope` already uses the fixture's `claude_failure`, so `FixtureMode::Redaction` keeps that field.

In `crates/needlbar-bridge/src/diagnostics.rs`:

```rust
    fn quota_source(self) -> QuotaSource {
        match self {
            Self::Cursor => QuotaSource::Unavailable,
            Self::Claude => QuotaSource::UsageReport,
            Self::Codex => QuotaSource::OAuth,
        }
    }
```

and add to `QuotaSource`:

```rust
    #[serde(rename = "usageReport")]
    UsageReport,
```

Search the bridge tests for an all-provider assertion on Claude: `diagnostics_marks_cursor_provider_unavailable…` reads only Codex and Cursor and stays. `provider_verification_preserves_unrelated_diagnostics_and_records_permission_denied` still holds because `record_partial_quota` preserves omitted providers (`crates/needlbar-bridge/src/lib.rs:414-424`). `crates/needlbar-bridge/src/lib.rs` tests call `diagnostics::record_quota` directly and are unaffected.

- [ ] **Step 4: Wire production**

In `Sources/Needlbar/App/AppDelegate.swift`, in the `RefreshCoordinator(...)` call, directly after `quotaRepository: RustQuotaRepository(bridge: bridge),` add:

```swift
                claudeUsageRepository: RustQuotaRepository(bridge: bridge),
```

In `Sources/NeedlbarCore/Refresh/UsageFileWatcher.swift:175`, stop leaking the descriptor into spawned processes:

```swift
        let descriptor = open(directory.path, O_EVTONLY | O_CLOEXEC)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cargo test --workspace --features bridge-test-runtime`
Expected: PASS.

Run: `make swift-test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add crates/needlbar-bridge/src/quota.rs crates/needlbar-bridge/src/test_runtime.rs crates/needlbar-bridge/src/diagnostics.rs crates/needlbar-bridge/tests/quota_contract.rs crates/needlbar-bridge/tests/redaction_contract.rs Sources/Needlbar/App/AppDelegate.swift Sources/NeedlbarCore/Refresh/UsageFileWatcher.swift Tests/NeedlbarCoreTests/BridgeIntegrationSmokeTests.swift
git commit -m "feat: read Claude quota only from the usage report

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 10: Remove the Allow Keychain access action

**Files:**
- Modify: `Sources/NeedlbarCore/Models/ClaudeQuotaFailureReason.swift`, `Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift`, `Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift`, `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift`, `Sources/Needlbar/Settings/SettingsView.swift`, `Sources/Needlbar/Settings/SettingsActions.swift`, `Sources/Needlbar/MenuBar/MenuBarController.swift`, `Sources/Needlbar/App/AppDelegate.swift`, `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`
- Delete: `Tests/NeedlbarTests/ClaudeKeychainAccessPresentationTests.swift`
- Create: `Tests/NeedlbarCoreTests/ClaudeUsageReportSourceContractTests.swift`
- Modify tests: `Tests/NeedlbarTests/MenuBarControllerTests.swift`, `Tests/NeedlbarTests/PopoverPresentationTests.swift`, `Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift`

**Interfaces:**
- Consumes: the working usage report path (Tasks 7-9).
- Produces: `RefreshCoordinator.applyQuotaResult` without `excludingClaude`; `SettingsActions.init()` and `init(loginCoordinator:snapshotExportController:)` without the Keychain operation; `MenuBarController` initializers without `onClaudeKeychainAccessRequested`; `SystemDashboardPopoverView` without `onClaudeKeychainAccessAction`.

- [ ] **Step 1: Write the failing test**

`Tests/NeedlbarCoreTests/ClaudeUsageReportSourceContractTests.swift`:

```swift
import Foundation
import Testing

// Source-level checks that retired Claude paths stay retired. This file is under
// Tests, so it does not match itself.
@Suite("ClaudeUsageReportSourceContract")
struct ClaudeUsageReportSourceContractTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func swiftSources() throws -> [(path: String, text: String)] {
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        let enumerator = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var files: [(path: String, text: String)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append((url.path, try String(contentsOf: url, encoding: .utf8)))
        }
        #expect(files.count > 50, "the source walk found the tree")
        return files
    }

    static func expectAbsent(_ forbidden: [String]) throws {
        for file in try swiftSources() {
            for text in forbidden {
                #expect(!file.text.contains(text), "\(file.path) still contains \(text)")
            }
        }
    }

    @Test func theKeychainActionIsGone() throws {
        try Self.expectAbsent([
            "Allow Keychain access",
            "Always Allow",
            "requestClaudeKeychainAccess",
            "allowClaudeKeychainAccess",
            "keychainAccessAction",
            "claudeKeychainAccess",
            "ClaudeKeychainAccess",
            "credentialAccessUnavailable",
            "Credential access unavailable",
        ])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeUsageReportSourceContract`
Expected: FAIL naming `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift` and `requestClaudeKeychainAccess`, among others.

- [ ] **Step 3: Remove the reason and copy**

In `ClaudeQuotaFailureReason.swift`, delete `case credentialAccessUnavailable`; the properties `keychainAccessActionTitle` and `keychainAccessActionDetail`; the functions `localizedKeychainAccessActionTitle` and `localizedKeychainAccessActionDetail`; the `.credentialAccessUnavailable` display case; `.credentialAccessUnavailable` from the `nil` list in `localizedDetailText`; and `case ("permissionDenied", _): self = .credentialAccessUnavailable`. `permissionDenied` now falls to `couldNotUpdateQuota`.

- [ ] **Step 4: Remove it from every surface**

`ProviderPopoverView.swift`: delete `case allowClaudeKeychainAccess(title: String)`; `keychainAccessAction` and `keychainAccessDetailText` with their comments; the assignments in both branches of `init`; `|| reason == .credentialAccessUnavailable` from `reasonSitsOnTheFableLine`; the `if let keychainAccessAction = presentation.keychainAccessAction { … }` view block; and `, let .allowClaudeKeychainAccess(title)` from the `title` switch.

`SystemDashboardModel.swift`: delete the fields `keychainAccessAction`, `keychainAccessDetailText` and the two arguments `keychainAccessAction: popover.keychainAccessAction,` and `keychainAccessDetailText: popover.keychainAccessDetailText,`.

`SystemDashboardPopoverView.swift`: delete the stored `onClaudeKeychainAccessAction`, its parameter in both initializers, its assignments including `onClaudeKeychainAccessAction = { _ in }`, the function `claudeKeychainAccessButton` with its comment, both calls `claudeKeychainAccessButton(provider)`, and `, let .allowClaudeKeychainAccess(title)` in `visibleActionTitle` and `accessibilityActionTitle`.

`SettingsView.swift`: delete the block starting `if case let .allowClaudeKeychainAccess(title)? = claudeQuotaPresentation.value.keychainAccessAction {`. The trailing `VStack` keeps the one `View Claude usage` button.

`SettingsActions.swift`: delete `isRequestingClaudeKeychainAccess`, `claudeKeychainAccessOperation` (property, both parameters, both assignments) and `requestClaudeKeychainAccess`. The second initializer becomes:

```swift
    public init() {
        loginStates = [:]
        exportState = .idle
        loginCoordinator = nil
        snapshotExportController = nil
    }
```

`MenuBarController.swift`: delete `onClaudeKeychainAccessRequested` (stored property, parameter and assignment in each of the two controllers, and the forwarding arguments), the `onClaudeKeychainAccessAction:` argument in the dashboard view, and both `case .allowClaudeKeychainAccess:` arms.

`AppDelegate.swift`: delete the `claudeKeychainAccessOperation:` argument so the call reads:

```swift
            let actions = SettingsActions(
                loginCoordinator: loginCoordinator,
                snapshotExportController: snapshotExportController
            )
```

and delete the `onClaudeKeychainAccessRequested:` argument.

- [ ] **Step 5: Remove the read and its sequencing from the coordinator**

In `RefreshCoordinator.swift`: delete `claudeKeychainAccessInFlight`, `claudeKeychainAccessEpoch` and their comments; the line `if provider == .claude, claudeKeychainAccessInFlight { return false }` with its comment; `requestClaudeKeychainAccess()` with its comment; `let keychainAccessEpoch = claudeKeychainAccessEpoch` and the `keychainAccessEpoch:` arguments in `beginQuotaRefresh`; the `keychainAccessEpoch` parameter of `finishQuotaRefresh`. Replace the end of `finishQuotaRefresh` (the comment and the `overlappedKeychainAccess` line through the `applyQuotaResult` call) with:

```swift
        await applyQuotaResult(result, intent: intent, applyResult: applyResult, generation: generation,
                               attempt: attempt, claudeAttemptStartedAt: attempt?.startedAt,
                               into: &application)
```

In `applyQuotaResult`: rename the first parameter `_ result`, delete the `excludingClaude` parameter, delete the local `result` computation, and replace `let includesClaude = intent.includesClaude && !excludingClaude` with `let includesClaude = intent.includesClaude`. Delete `, !excludingClaude` from both `intent == .claudePreflight` conditions, delete `if excludingClaude { requested.remove(.claude) }`, change `var requested` to `let requested`, and change the provider loop to `for provider in requestedProviders(for: intent) {`. Update the doc comment to: "Stores one attempt's result. `attempt` is the ledger's record of it." In `finishClaudeUsageProbe`, delete `excludingClaude: false,`.

- [ ] **Step 6: Remove the tests of the action**

```bash
git rm Tests/NeedlbarTests/ClaudeKeychainAccessPresentationTests.swift
```

In `Tests/NeedlbarTests/MenuBarControllerTests.swift`, delete `theKeychainAccessActionDismissesThePanelAndRequestsAccessOnce`, the helper parameter `onClaudeKeychainAccessRequested: @escaping @MainActor () -> Void = {},` and the forwarding `onClaudeKeychainAccessRequested: onClaudeKeychainAccessRequested,`.

In `Tests/NeedlbarTests/PopoverPresentationTests.swift`, in `everySafeClaudeQuotaReasonRendersItsExactAllowlistedText`, replace the row `(.credentialAccessUnavailable, "Credential access unavailable"),` with these four:

```swift
        (.claudeCodeNotInstalled, "Install Claude Code to see quota"),
        (.claudeCodeSignInRequired, "Sign in with claude in Terminal"),
        (.claudeCodeCheckFailed, "Could not check Claude Code"),
        (.usageReportFormatChanged, "Could not read Claude Code's usage report"),
```

In `Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift`, in both reason tables, change `("permissionDenied", .credentialAccessUnavailable),` to `("permissionDenied", .couldNotUpdateQuota),`.

- [ ] **Step 7: Run tests to verify they pass**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeUsageReportSourceContract`
Expected: PASS.

Run: `make swift-test`
Expected: PASS. The exports `needlbar_claude_user_initiated_…` and `needlbar_claude_preflight_…` still exist and Task 11 removes them.

- [ ] **Step 8: Commit**

```bash
git add -A Sources Tests
git commit -m "feat: remove the Allow Keychain access action

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 11: Remove the login-path leftovers and old exports

**Files:**
- Modify: `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`, `Sources/NeedlbarCore/Repositories/QuotaRepository.swift`, `Sources/NeedlbarCore/Bridge/RustBridge.swift`, `Sources/NeedlbarCore/Models/ClaudeQuotaFailureReason.swift`, `Sources/NeedlbarCore/Diagnostics/ClaudeQuotaCompletionDiagnostics.swift`, `Sources/Needlbar/Authentication/ProviderLoginCoordinator.swift`, `Sources/Needlbar/App/AppDelegate.swift`, `Sources/Needlbar/Settings/SettingsView.swift`, `Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift`, `Sources/NeedlbarSettingsStudioReviewSupport/SettingsStudioReviewFixtures.swift`, `Sources/CNeedlbar/include/needlbar.h`
- Modify: `crates/needlbar-bridge/src/quota.rs`, `crates/needlbar-bridge/src/lib.rs`, `crates/needlbar-bridge/src/test_runtime.rs`, `crates/needlbar-bridge/tests/ffi_contract.rs`, `crates/needlbar-bridge/tests/quota_contract.rs`, `crates/needlbar-bridge/tests/redaction_contract.rs`
- Delete: `Tests/NeedlbarTests/ClaudeAccessExpiredPresentationTests.swift`
- Modify tests: `Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift`, `Tests/NeedlbarCoreTests/BridgeDecodingTests.swift`, `Tests/NeedlbarCoreTests/ClaudeStatusLineMaximumAgeTests.swift`, `Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift`, `Tests/NeedlbarCoreTests/ClaudeUsageReportReasonTests.swift`, `Tests/NeedlbarCoreTests/ClaudeUsageReportSourceContractTests.swift`, `Tests/NeedlbarTests/ClaudeStatusLineMaximumAgePresentationTests.swift`, `Tests/NeedlbarTests/ClaudeQuotaFailureDiagnosticsReporterTests.swift`, `Tests/NeedlbarTests/ProviderLoginCoordinatorTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces: `ClaudeQuotaFailureReason.init(errorCode:)`; `QuotaRefreshIntent` with `.backgroundAll`, `.userInitiated(provider:)`, `.claudeUsageReport(runID:)`; `includesClaude` true only for `.claudeUsageReport`; `RefreshCoordinator.refreshQuota(afterUserAuthenticationFor:)` accepts only `.codex`; `ProviderLoginCommandResolver` refuses `.claude`; `test_runtime::claude_usage_report_source()` with direct fixtures; `ProviderVerificationFixture.claude_fetches() -> usize`.

- [ ] **Step 1: Write the failing tests**

Add to `ClaudeUsageReportSourceContractTests`:

```swift
    @Test func needlbarNeverRunsClaudeAuthOrAPreflight() throws {
        try Self.expectAbsent([
            "\"auth\", \"login\"",
            "--claudeai",
            "preflightClaudeLogin",
            "ClaudeLoginPreflightOutcome",
            "claudePreflight",
            "claudeUserInitiated",
            "needlbar_claude_preflight",
            "needlbar_claude_user_initiated",
            "macOS may request access to Claude Code credentials",
            "claudeCodeAccessExpired",
            "ClaudeQuotaFailureOriginAssociation",
        ])
    }

    @Test func productionInjectsTheUsageReportRepository() throws {
        let appDelegate = Self.root.appendingPathComponent("Sources/Needlbar/App/AppDelegate.swift")
        let text = try String(contentsOf: appDelegate, encoding: .utf8)
        #expect(text.contains("claudeUsageRepository: RustQuotaRepository(bridge: bridge)"))
    }
```

Append to `Tests/NeedlbarTests/ProviderLoginCoordinatorTests.swift`:

```swift
@Test func theProductionResolverNeverBuildsAClaudeCommand() {
    let root = URL(fileURLWithPath: "/tmp/needlbar-login-tests")
    let resolver = ProviderLoginCommandResolver(
        environment: ["HOME": root.path, "PATH": "/usr/bin"],
        homeDirectory: root,
        executablePredicate: { _ in
            Issue.record("Claude must not resolve an executable")
            return true
        }
    )
    #expect(throws: ProviderLoginCommandResolutionError.unsupportedProvider) {
        try resolver.command(for: .claude)
    }
    #expect(resolver.candidateURLs(for: .claude).isEmpty)
}

@MainActor
@Test func connectingClaudeThroughTheProductionResolverNeverLaunches() async {
    let root = URL(fileURLWithPath: "/tmp/needlbar-login-tests")
    let coordinator = ProviderLoginCoordinator(
        resolver: ProviderLoginCommandResolver(
            environment: ["HOME": root.path, "PATH": "/usr/bin"],
            homeDirectory: root,
            executablePredicate: { _ in true }
        ),
        runner: ImmediateLoginRunner(outcomes: [:]),
        refreshQuota: { _ in
            Issue.record("Claude has no login verification")
            return false
        }
    )
    #expect(!coordinator.connect(.claude))
    #expect(coordinator.state(for: .claude) == .failed(.unsupportedProvider))
}
```

Add to `RefreshCoordinatorTests`:

```swift
@Test func claudeHasNoAuthenticationVerification() async throws {
    let quota = BlockingIntentQuotaRepository()
    let coordinator = makeRunningCoordinator(quota: quota)
    await coordinator.start()
    await quota.waitUntilCallCount(1)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))

    let verified = await coordinator.refreshQuota(afterUserAuthenticationFor: .claude)
    #expect(verified == false)
    #expect(quota.callCount == 1)
    await coordinator.stop()
}
```

Add to `ClaudeUsageProbeCoordinatorTests` (under the fixtures it uses), replacing the coverage of the deleted `bridgeFailuresAndUntypedQuotaFailuresUseSafeClaudeReasons`:

```swift
    @Test(arguments: [
        ("requiresAuthentication", ClaudeQuotaFailureReason.claudeCodeSignInRequired),
        ("notInstalled", .claudeCodeNotInstalled),
        ("providerUnavailable", .claudeCodeCheckFailed),
        ("rateLimited", .temporarilyLimited),
        ("schemaChanged", .usageReportFormatChanged),
        ("unknown-code", .couldNotUpdateQuota),
    ])
    func aBridgeFailureThrownByARunMapsToItsSafeReason(code: String, expected: ClaudeQuotaFailureReason) async throws {
        let harness = Harness()
        harness.probe.script(.failure(BridgeFailure.bridgeFailed([
            .init(provider: "claude", code: code, message: canaryMessage, action: nil),
        ])))
        await harness.startedAndIdle()
        #expect(await harness.store.snapshot(for: .claude).claudeQuotaFailureReason == expected)
        await harness.coordinator.stop()
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make swift-test SWIFT_TEST_FILTER=needlbarNeverRunsClaudeAuthOrAPreflight`
Expected: FAIL naming `ProviderLoginCoordinator.swift` and `"auth", "login"`.

- [ ] **Step 3: Simplify the Swift models**

`QuotaRepository.swift`:

```swift
public enum QuotaRefreshIntent: Equatable, Sendable {
    /// Codex and Cursor. Claude never runs here.
    case backgroundAll
    case userInitiated(provider: ProviderID)
    /// One `claude -p /usage` run. `runID` lets a later cancel reach it even
    /// before it starts.
    case claudeUsageReport(runID: UInt64)
}

extension QuotaRefreshIntent {
    var includesClaude: Bool {
        if case .claudeUsageReport = self { true } else { false }
    }
}
```

In `RustQuotaRepository.refresh(intent:)`, delete the `.claudePreflight` case and replace the `.userInitiated(provider: .claude)` case with:

```swift
        case .userInitiated(provider: .claude):
            throw safeFailure(provider: .claude, code: "unsupportedProvider", message: "Claude quota updates through Claude Code's usage report.")
```

`RustBridge.swift`: delete `claudePreflightQuotaCall`, `claudeUserInitiatedQuotaCall` (properties, parameters, assignments) and `claudePreflightQuotaEnvelope`, `claudeUserInitiatedQuotaEnvelope`.

`ClaudeQuotaFailureReason.swift`: delete `case claudeCodeAccessExpired` with its comment and its display and detail cases. Replace the initializer:

```swift
    /// Maps a completed attempt's Claude error code to a safe reason.
    init(errorCode: String) {
        switch errorCode {
        case "notInstalled": self = .claudeCodeNotInstalled
        case "requiresAuthentication": self = .claudeCodeSignInRequired
        case "authenticationExpired": self = .quotaAccessUnavailable
        case "networkUnavailable": self = .connectionUnavailable
        case "rateLimited": self = .temporarilyLimited
        case "providerUnavailable": self = .claudeCodeCheckFailed
        case "schemaChanged": self = .usageReportFormatChanged
        default: self = .couldNotUpdateQuota
        }
    }
```

`ClaudeQuotaCompletionDiagnostics.swift`: delete `enum ClaudeQuotaFailureOriginAssociation`.

`ProviderPopoverView.swift`: `reasonSitsOnTheFableLine` becomes `reason == .claudeCodeNotInstalled || reason == .claudeCodeSignInRequired`.

- [ ] **Step 4: Simplify the coordinator**

In `RefreshCoordinator.swift`, delete `enum ClaudeLoginPreflightOutcome`; `struct ClaudePreflightWaiter`; `queuedClaudePreflight`, `claudePreflightWaiters`, `completingClaudePreflightWaiters` and every use in `stop()`; `preflightClaudeLogin()`; `moveClaudePreflightWaiters`, `resumeCompletingClaudePreflightWaiters`, `resumeAllClaudePreflightWaiters`, all three `claudePreflightOutcome` functions and `claudeResultFailed`; `preflightOutcome` from `QuotaApplication`; the `isClaudePreflight` lines and its block in the `defer` of `finishQuotaRefresh`; and the first block of `drainQueuedQuotaRefreshes` (`if queuedClaudePreflight { … }`).

Change the guard in `refreshQuota(afterUserAuthenticationFor:)`:

```swift
        guard isRunning, provider == .codex else { return false }
```

Change the helper:

```swift
    private func requestedProviders(for intent: QuotaRefreshIntent) -> [ProviderID] {
        switch intent {
        case .userInitiated(let provider): [provider]
        case .claudeUsageReport: [.claude]
        case .backgroundAll: [.codex, .cursor]
        }
    }
```

Replace `applyQuotaResult` down to the `guard applyResult, generation == runGeneration else { return }` that precedes the completion block with:

```swift
    /// Stores one attempt's result. `attempt` is the ledger's record of it.
    private func applyQuotaResult(
        _ result: Result<QuotaRefreshResult, Error>,
        intent: QuotaRefreshIntent,
        applyResult: Bool,
        generation: UInt64,
        attempt: QuotaAttemptEvent?,
        into application: inout QuotaApplication
    ) async {
        guard applyResult, generation == runGeneration else { return }
        let includesClaude = intent.includesClaude
        // Read the bridge diagnostics record once for this run and share that
        // read with the reporter.
        var claudeDiagnosticsRead: ClaudeQuotaDiagnosticsRead?
        if includesClaude, let claudeQuotaDiagnostics {
            let read = await claudeQuotaDiagnostics.read()
            guard generation == runGeneration else { return }
            claudeDiagnosticsRead = read
        }
        switch result {
        case .success(let refresh):
            let refreshedAt = clock.now
            if case .backgroundAll = intent, !refresh.snapshots.isEmpty {
                lastBackgroundQuotaSuccessfulAt = refreshedAt
            }
            for (provider, quota) in refresh.snapshots {
                guard generation == runGeneration, applyResult else { return }
                if let quotaApplicationWillApply {
                    await quotaApplicationWillApply()
                }
                guard generation == runGeneration, applyResult else { return }
                await store.applyQuota(quota, for: provider, at: refreshedAt)
            }
            for (provider, error) in refresh.errors {
                guard generation == runGeneration, applyResult else { return }
                await store.markQuotaFailure(
                    for: provider,
                    status: quotaStatus(for: error),
                    claudeFailureReason: provider == .claude ? ClaudeQuotaFailureReason(errorCode: error.code) : nil,
                    at: refreshedAt
                )
            }
            if case .userInitiated(let provider) = intent {
                application.verificationSucceeded = refresh.snapshots[provider] != nil
            }
        case .failure(let error):
            if let bridgeFailure = error as? BridgeFailure,
               case .bridgeFailed(let bridgeErrors) = bridgeFailure
            {
                let requested = Set(requestedProviders(for: intent))
                let matchingErrors = bridgeErrors.filter {
                    guard let provider = $0.providerID else { return false }
                    return requested.contains(provider)
                }
                if !matchingErrors.isEmpty {
                    for error in matchingErrors {
                        guard let provider = error.providerID, generation == runGeneration, applyResult else { return }
                        await store.markQuotaFailure(
                            for: provider,
                            status: quotaStatus(for: error),
                            claudeFailureReason: provider == .claude ? ClaudeQuotaFailureReason(errorCode: error.code) : nil,
                            at: clock.now
                        )
                    }
                    break
                }
            }
            let status = DataStatus.error(message: String(describing: error), lastSuccessfulAt: nil)
            for provider in requestedProviders(for: intent) {
                guard generation == runGeneration, applyResult else { return }
                await store.markQuotaFailure(
                    for: provider,
                    status: status,
                    claudeFailureReason: provider == .claude ? .couldNotUpdateQuota : nil,
                    at: clock.now
                )
            }
        }
```

The call in `finishQuotaRefresh` becomes:

```swift
        await applyQuotaResult(result, intent: intent, applyResult: applyResult, generation: generation,
                               attempt: attempt, into: &application)
```

and the call in `finishClaudeUsageProbe` drops `claudeAttemptStartedAt: attempt?.startedAt,`.

- [ ] **Step 5: Remove Claude from the login coordinator and its copy**

In `ProviderLoginCoordinator.swift`:

```swift
    public func command(for provider: ProviderID) throws -> ProviderLoginCommand {
        guard provider == .codex else {
            throw ProviderLoginCommandResolutionError.unsupportedProvider
        }
        guard let executableURL = candidateURLs(for: provider).first(where: executablePredicate) else {
            throw ProviderLoginCommandResolutionError.cliNotInstalled
        }
        let standardizedURL = executableURL.standardizedFileURL
        return ProviderLoginCommand(
            provider: provider,
            executableURL: standardizedURL,
            arguments: ["login"],
            environment: childEnvironment(for: provider, executableURL: standardizedURL)
        )
    }
```

In `candidateURLs(for:)` replace the `executableName` switch with:

```swift
        guard provider == .codex else { return [] }
        let executableName = "codex"
```

Delete `"CLAUDE_CONFIG_DIR", ` from `allowedEnvironmentKeys` and the line `child["CLAUDE_CONFIG_DIR"] = provider == .claude ? environment["CLAUDE_CONFIG_DIR"] : nil`. Delete `preflightClaudeLogin` (property, parameter, assignment), the `if provider == .claude { … }` block in `connect`, and the functions `runClaudePreflight` and `resolveAndRunClaude`.

In `AppDelegate.swift`, the login coordinator becomes:

```swift
            let loginCoordinator = ProviderLoginCoordinator(
                refreshQuota: { provider in
                    await refreshCoordinator.refreshQuota(afterUserAuthenticationFor: provider)
                }
            )
```

In `SettingsView.swift` `loginStatusCopy`:

```swift
        case .idle:
            "Sign in opens the provider's browser flow."
```

```swift
        case .refreshingQuota:
            "Verifying quota…"
```

In `SettingsStudioReviewFixtures.swift`, delete `preflightClaudeLogin: { .requiresAuthentication },`.

- [ ] **Step 6: Remove the exports from Rust**

`crates/needlbar-bridge/src/quota.rs`: delete `ClaudeUserInitiatedQuotaSource` and its impl, `collect_claude_user_initiated`, `collect_claude_preflight`, `collect_claude_preflight_with_source`, `collect_claude_user_initiated_with_source`. The import becomes:

```rust
use needlbar_quota::{
    ClaudeQuotaFailureOrigin, ClaudeUsageProbeSummary, ClaudeUsageReportProvider,
    ClaudeUsageReportRun, ProviderId, ProviderQuotaSnapshot, QuotaError, QuotaErrorCode,
    QuotaProvider, UsageProbeControl,
};
```

`crates/needlbar-bridge/src/lib.rs`: delete `needlbar_claude_preflight_quota_snapshot_json`, `needlbar_claude_user_initiated_quota_snapshot_json`, `ffi_claude_user_initiated_quota_envelope`, `ffi_claude_preflight_quota_envelope`, `claude_user_initiated_quota_envelope`, `claude_preflight_quota_envelope`, and the test `real_claude_credential_failures_reach_diagnostics_as_split_origins`.

`Sources/CNeedlbar/include/needlbar.h`: delete the two declarations and their comments.

`crates/needlbar-bridge/tests/ffi_contract.rs`: delete both `header.contains` lines for the old exports and the `claude` and `claude_preflight` bindings, and add:

```rust
    assert!(!header.contains("needlbar_claude_user_initiated"));
    assert!(!header.contains("needlbar_claude_preflight"));
    let _ = (usage, quota, codex, diagnostics, analytics);
```

`crates/needlbar-bridge/src/test_runtime.rs`: delete `claude_user_initiated_source`, `FixtureUsageReportSource`, `ProviderVerificationClaudeSource`, `BlockingClaudeSource`, `PanicClaudeSource` and `FixtureClaudeUserInitiatedSource`. Change `claude_accesses: Vec<…>` to `claude_fetches: usize`, and replace `claude_accesses()` and `record_claude_access` with:

```rust
    pub fn claude_fetches(&self) -> usize {
        self.observations
            .lock()
            .expect("provider verification observations lock")
            .claude_fetches
    }

    fn record_claude_fetch(&self) {
        self.observations
            .lock()
            .expect("provider verification observations lock")
            .claude_fetches += 1;
    }
```

In `ProviderVerificationQuotaProvider::fetch`, use `ProviderId::Claude => self.fixture.record_claude_fetch(),`. Add:

```rust
fn fixture_summary() -> needlbar_quota::ClaudeUsageProbeSummary {
    needlbar_quota::ClaudeUsageProbeSummary {
        duration_ms: 1,
        row_kinds: vec![needlbar_quota::ClaudeUsageRowKind::Session],
        unknown_row_count: 0,
        skipped_row_count: 0,
    }
}

type UsageReportFuture<'a> = std::pin::Pin<
    Box<dyn std::future::Future<Output = needlbar_quota::ClaudeUsageReportRun> + Send + 'a>,
>;

enum FixtureUsageReportSource {
    Scripted(Result<ProviderQuotaSnapshot, QuotaError>),
    Recording(ProviderVerificationFixture),
    Blocking(BlockingClaudeFixture),
    Panicking,
}

impl quota::ClaudeUsageReportSource for FixtureUsageReportSource {
    fn run_usage_report<'a>(&'a self) -> UsageReportFuture<'a> {
        Box::pin(async move {
            let result = match self {
                Self::Scripted(result) => result.clone(),
                Self::Recording(fixture) => {
                    fixture.record_claude_fetch();
                    fixture.claude_result.clone()
                }
                Self::Blocking(blocking) => {
                    blocking.fixture.record_claude_fetch();
                    blocking.wait_for_release();
                    blocking.fixture.claude_result.clone()
                }
                Self::Panicking => panic!("provider verification fixture panic"),
            };
            needlbar_quota::ClaudeUsageReportRun {
                result,
                summary: Some(fixture_summary()),
            }
        })
    }
}

pub fn claude_usage_report_source() -> Option<Arc<dyn quota::ClaudeUsageReportSource>> {
    let runtime = fixture_runtime()?;
    Some(Arc::new(match runtime.mode {
        FixtureMode::Integration => FixtureUsageReportSource::Scripted(Ok(fixture_snapshot(
            ProviderId::Claude,
            "claude.session",
            20.0,
        ))),
        FixtureMode::Redaction { claude_failure, .. } => FixtureUsageReportSource::Scripted(Err(
            QuotaError::new(
                Some(ProviderId::Claude),
                QuotaErrorCode::RequiresAuthentication,
                Box::leak(claude_failure.into_boxed_str()),
            ),
        )),
        FixtureMode::ProviderVerification(fixture) => {
            fixture.record_creation(ProviderId::Claude);
            FixtureUsageReportSource::Recording(fixture)
        }
        FixtureMode::ProviderVerificationBlocking(blocking) => {
            FixtureUsageReportSource::Blocking(blocking)
        }
        FixtureMode::ProviderVerificationPanic => FixtureUsageReportSource::Panicking,
    }))
}
```

- [ ] **Step 7: Port the Rust tests**

`crates/needlbar-bridge/tests/quota_contract.rs`: delete `RecordingClaudeResolver`, `RecordingClaudeSource`, `claude_preflight_uses_only_claude_without_keychain_ui`, `claude_user_initiated_collection_uses_only_claude_with_ui_access`, `claude_permission_denial_uses_safe_bridge_copy_without_token_data`, and the imports they need. Replace `bridge_keeps_fable_as_an_additive_claude_window` with:

```rust
#[tokio::test]
async fn bridge_carries_only_the_windows_the_report_gave() {
    let snapshot = ProviderQuotaSnapshot {
        provider: ProviderId::Claude,
        windows: vec![
            QuotaWindow::new("claude.weekly", "Weekly", 74.0, None).unwrap(),
            QuotaWindow::new("claude.fable.weekly", "Fable weekly", 0.0, None).unwrap(),
        ],
    };
    let collection = collect_claude_usage_report_with_source(Arc::new(ScriptedUsageReportSource {
        result: Ok(snapshot),
        summary: Some(fixture_summary()),
    }))
    .await;
    let value = serde_json::to_value(envelope_from_collection(collection)).unwrap();
    let windows = &value["data"]["providers"][0]["windows"];
    assert_eq!(windows.as_array().map(Vec::len), Some(2));
    assert_eq!(windows[0]["id"], "claude.weekly");
    assert_eq!(windows[1]["id"], "claude.fable.weekly");
    assert_eq!(windows[1]["usedPercent"].as_f64(), Some(0.0));
}
```

`crates/needlbar-bridge/tests/redaction_contract.rs`: run this script once:

```bash
/usr/bin/python3 -I - <<'PY'
import pathlib
path = pathlib.Path("crates/needlbar-bridge/tests/redaction_contract.rs")
source = path.read_text()
source = source.replace("needlbar_analytics_snapshot_json, needlbar_claude_user_initiated_quota_snapshot_json,", "needlbar_analytics_snapshot_json, needlbar_claude_usage_report_quota_snapshot_json,")
body_start = source.index("#[test]")
head, body = source[:body_start], source[body_start:]
body = body.replace("unsafe { needlbar_claude_user_initiated_quota_snapshot_json() }", "unsafe { claude_usage_report_export() }")
body = body.replace("needlbar_claude_user_initiated_quota_snapshot_json", "claude_usage_report_export")
body = body.replace('assert_eq!(fixture.claude_accesses(), vec!["userInitiatedAllowUI"]);', "assert_eq!(fixture.claude_fetches(), 1);")
body = body.replace('assert_eq!(denied.claude_accesses(), vec!["userInitiatedAllowUI"]);', "assert_eq!(denied.claude_fetches(), 1);")
body = body.replace("assert!(fixture.claude_accesses().is_empty());", "assert_eq!(fixture.claude_fetches(), 0);")
path.write_text(head + body)
PY
```

- [ ] **Step 8: Port the Swift tests**

Run this script once from the repository root:

```bash
/usr/bin/python3 -I - <<'PY'
import pathlib, re

def load(name):
    return pathlib.Path(name), pathlib.Path(name).read_text()

def span(text, name):
    match = re.search(r"^[ \t]*(?:@MainActor\n[ \t]*)?@Test(?:\([^\n]*\))?\s*(?:\n[ \t]*)?func " + name + r"\(", text, re.M)
    assert match, name
    index = text.index("{", match.end())
    depth = 0
    for position in range(index, len(text)):
        if text[position] == "{":
            depth += 1
        elif text[position] == "}":
            depth -= 1
            if depth == 0:
                return match.start(), position + 1
    raise AssertionError(name)

def delete(text, name):
    start, end = span(text, name)
    return text[:start] + text[end:].lstrip("\n")

def swap(body):
    return re.sub(r"\b(claude|codex)\b", lambda match: "codex" if match.group(1) == "claude" else "claude", body)

# RefreshCoordinatorTests: Codex is the only provider with a verification path.
path, source = load("Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift")
for name in [
    "claudePreflightClassifiesTheCurrentSilentResultBeforeCachedQuota",
    "claudePreflightCoalescesCallersAndStopCompletesThemOnceWithFailure",
    "bridgeFailuresAndUntypedQuotaFailuresUseSafeClaudeReasons",
    "simultaneousProviderVerificationsRunInStableProviderOrderAndResumeOnlyTheirWaiters",
]:
    source = delete(source, name)
for name in [
    "authenticationVerificationDoesNotTriggerUsageRefresh",
    "claudeAuthenticationVerificationReturnsTrueOnlyAfterFreshClaudeQuota",
    "permissionDeniedVerificationPreservesLastKnownGoodQuotaAndReturnsFalse",
    "malformedDedicatedVerificationMarksOnlyTheRequestedQuotaStaleAndPreservesItsValue",
    "userVerificationQueuedDuringBackgroundRefreshIsNotMergedAway",
    "concurrentClaudeVerificationsCoalesceToOneFollowUpAndResumeAllWaitersOnce",
    "stopAndRestartResumeOutstandingVerificationWaitersFalseAndIgnoreLateQuota",
    "providerOnlyVerificationDoesNotAdvanceBackgroundFreshnessAndPopoverQueuesBackgroundAll",
    "stopDuringQuotaStoreApplicationResumesCapturedVerificationWaiterFalseExactlyOnce",
    "sameProviderVerificationJoiningDuringQuotaApplicationUsesTheActiveResult",
    "restartedGenerationKeepsNewProviderWaiterSeparateFromLateOldCompletion",
]:
    start, end = span(source, name)
    source = source[:start] + swap(source[start:end]) + source[end:]
source = source.replace("claudeAuthenticationVerificationReturnsTrueOnlyAfterFreshClaudeQuota", "codexAuthenticationVerificationReturnsTrueOnlyAfterFreshCodexQuota")
source = source.replace("concurrentClaudeVerificationsCoalesceToOneFollowUpAndResumeAllWaitersOnce", "concurrentCodexVerificationsCoalesceToOneFollowUpAndResumeAllWaitersOnce")
start, end = span(source, "queuedBackgroundRunsAfterItsFiniteAheadBatchDespiteLaterUserRequests")
source = source[:start] + '''@Test func queuedBackgroundRunsAfterItsFiniteAheadBatchDespiteLaterUserRequests() async throws {
    let quota = BlockingIntentQuotaRepository()
    let registrations = QuotaIntentRegistrationGate()
    let coordinator = makeRunningCoordinator(quota: quota, quotaIntentRegistered: registrations.record)
    await coordinator.start()
    await quota.waitUntilCallCount(1)

    let ahead = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .codex) }
    await registrations.waitUntil([.userInitiated(provider: .codex)])
    let manual = Task { await coordinator.manualRefresh() }
    await registrations.waitUntil([.userInitiated(provider: .codex), .backgroundAll])
    let behind = Task { await coordinator.refreshQuota(afterUserAuthenticationFor: .codex) }
    await registrations.waitUntil([.userInitiated(provider: .codex), .backgroundAll, .userInitiated(provider: .codex)])

    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    await quota.waitUntilCallCount(2)
    #expect(quota.intents[1] == .userInitiated(provider: .codex))
    try quota.releaseNext(with: quotaResult(for: .codex))
    #expect(await ahead.valueUnlessCancelled == true)
    await quota.waitUntilCallCount(3)
    #expect(quota.intents[2] == .backgroundAll)
    try quota.releaseNext(with: .init(snapshots: [:], errors: [:]))
    await quota.waitUntilCallCount(4)
    #expect(quota.intents[3] == .userInitiated(provider: .codex))
    try quota.releaseNext(with: quotaResult(for: .codex))
    #expect(await behind.valueUnlessCancelled == true)
    _ = await manual.valueUnlessCancelled
    await coordinator.stop()
}''' + source[end:]
path.write_text(source)

# BridgeDecodingTests: the dedicated Claude call is now the usage report.
path, source = load("Tests/NeedlbarCoreTests/BridgeDecodingTests.swift")
for name in [
    "claudePreflightQuotaRefreshUsesOnlyTheSilentClaudeBridgeCallAndFreesOnce",
    "claudePreflightRejectsMultipleCurrentErrorsInsteadOfSelectingOne",
]:
    source = delete(source, name)
source = source.replace("claudeUserInitiatedQuotaCall: {", "claudeUsageReportQuotaCall: { _ in")
source = source.replace("RustQuotaRepository(bridge: bridge).refresh(intent: .userInitiated(provider: .claude))", "RustQuotaRepository(bridge: bridge).refresh(intent: .claudeUsageReport(runID: 1))")
source = source.replace("claudeUserInitiatedQuotaRefreshUsesOnlyClaudeBridgeCallAndFreesOnce", "usageReportRefreshUsesOnlyClaudeBridgeCallAndFreesOnce")
path.write_text(source)

# The reporter test only proves no quota closure is called.
path, source = load("Tests/NeedlbarTests/ClaudeQuotaFailureDiagnosticsReporterTests.swift")
source = re.sub(r"\s*claudePreflightQuotaCall: \{\n.*?\n\s*\},", "", source, count=1, flags=re.S)
source = source.replace("claudeUserInitiatedQuotaCall: {", "claudeUsageReportQuotaCall: { _ in")
path.write_text(source)

# The status-line age tests only need a reason that sits on the Fable line.
for name in ["Tests/NeedlbarCoreTests/ClaudeStatusLineMaximumAgeTests.swift",
             "Tests/NeedlbarTests/ClaudeStatusLineMaximumAgePresentationTests.swift"]:
    path, source = load(name)
    source = source.replace(".claudeCodeAccessExpired", ".claudeCodeSignInRequired")
    source = re.sub(r'static let shortText = "[^"]*"', 'static let shortText = "Sign in with claude in Terminal"', source)
    source = re.sub(r'static let detailText = "[^"]*"', 'static let detailText = "Claude Code reported no usage for this Mac. Needlbar updates at its next check and never opens a sign-in itself."', source)
    path.write_text(source)

# ProviderLoginCoordinatorTests: a fake resolver can still return a command for
# any provider, which keeps the admission and reaping coverage; the production
# resolver refuses Claude and has its own tests.
path, source = load("Tests/NeedlbarTests/ProviderLoginCoordinatorTests.swift")
for name in [
    "resolverBuildsOnlyTheFixedClaudeAndCodexCommands",
    "claudeFreshPreflightConnectsWithoutResolvingOrLaunchingTheCLI",
    "claudeAuthenticationPreflightRunsTheFixedCLIThenOneVerifier",
    "claudePermissionPreflightRunsOneInteractiveVerifierWithoutCLIAndStopsAfterDenial",
    "stoppingClaudeDuringPreflightCannotStartCLIOrInteractiveVerification",
    "resolverBuildsMinimalProviderScopedEnvironment",
]:
    source = delete(source, name)
start, end = span(source, "resolverUsesPathBeforeFixedFallbackLocations")
source = source[:start] + swap(source[start:end]) + source[end:]
source = re.sub(r",\s*\n\s*preflightClaudeLogin: \{[^\n]*\}", "", source)
source = source.replace("#expect(missingCLI.connect(.claude))", "#expect(!missingCLI.connect(.claude))")
source += '''
@Test func resolverBuildsOnlyTheFixedCodexCommand() throws {
    let root = URL(fileURLWithPath: "/tmp/needlbar-login-tests")
    let resolver = ProviderLoginCommandResolver(
        environment: ["HOME": root.path, "PATH": "/usr/bin"],
        homeDirectory: root,
        executablePredicate: { url in url.lastPathComponent == "codex" }
    )
    let codex = try resolver.command(for: .codex)
    #expect(codex.arguments == ["login"])
    #expect(codex.provider == .codex)
}

@Test func resolverBuildsMinimalCodexEnvironment() throws {
    let home = URL(fileURLWithPath: "/tmp/needlbar-login-tests/home")
    let selected = URL(fileURLWithPath: "/tmp/needlbar-login-tests/wrapper/bin/codex")
    let resolver = ProviderLoginCommandResolver(
        environment: [
            "HOME": home.path,
            "USER": "test-user",
            "LANG": "en_US.UTF-8",
            "PATH": "/tmp/needlbar-login-tests/wrapper/bin",
            "CLAUDE_CONFIG_DIR": "/tmp/claude-config",
            "CODEX_HOME": "/tmp/codex-home",
            "OPENAI_API_KEY": "must-not-leak",
            "FIXTURE_SECRET": "must-not-leak",
        ],
        homeDirectory: home,
        executablePredicate: { $0.standardizedFileURL == selected.standardizedFileURL }
    )
    let environment = try resolver.command(for: .codex).environment
    #expect(environment["PATH"] == "/tmp/needlbar-login-tests/wrapper/bin:/tmp/needlbar-login-tests/wrapper/bin")
    #expect(environment["CODEX_HOME"] == "/tmp/codex-home")
    #expect(environment["CLAUDE_CONFIG_DIR"] == nil)
    #expect(environment["OPENAI_API_KEY"] == nil)
    #expect(environment["FIXTURE_SECRET"] == nil)
    #expect(Set(environment.keys).isSubset(of: ProviderLoginCommandResolver.allowedEnvironmentKeys))
}
'''
path.write_text(source)

# The new test files call the initializer without an origin.
path, source = load("Tests/NeedlbarCoreTests/ClaudeUsageReportReasonTests.swift")
source = source.replace("ClaudeQuotaFailureReason(errorCode: code, associatedOrigin: nil)", "ClaudeQuotaFailureReason(errorCode: code)")
path.write_text(source)
PY
git rm Tests/NeedlbarTests/ClaudeAccessExpiredPresentationTests.swift
```

The script keeps tests that connect `.claude` through a fake resolver, because they cover generic admission and reaping, and the generic path now serves any provider a resolver accepts. If one of them relied on the removed preflight suspension and fails, change only that test's provider to `.codex`; do not restore the preflight.

- [ ] **Step 9: Run tests to verify they pass**

Run: `cargo test --workspace --features bridge-test-runtime`
Expected: PASS.

Run: `make swift-test`
Expected: PASS, including `ClaudeUsageReportSourceContract`.

- [ ] **Step 10: Commit**

```bash
git add -A Sources Tests crates
git commit -m "feat: remove the Claude login, preflight and verification paths

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 12: Delete the Claude credential and endpoint code

**Files:**
- Delete: `crates/needlbar-quota/src/providers/claude_credentials.rs`, `crates/needlbar-quota/src/providers/claude.rs`, `crates/needlbar-quota/tests/claude.rs`, `Fixtures/quota/claude/usage-success.json`, `Fixtures/quota/claude/usage-fable-success.json`, `Fixtures/quota/claude/usage-malformed.json`
- Create: `crates/needlbar-quota/tests/claude_source_contract.rs`
- Modify: `crates/needlbar-quota/src/lib.rs`, `crates/needlbar-quota/src/providers/mod.rs`, `crates/needlbar-quota/src/http.rs`, `crates/needlbar-quota/src/domain.rs`, `crates/needlbar-quota/Cargo.toml`, `Cargo.toml`, `Cargo.lock`, `crates/needlbar-bridge/src/quota.rs`, `crates/needlbar-bridge/src/lib.rs`, `Sources/NeedlbarCore/Diagnostics/DiagnosticsSnapshot.swift`
- Modify tests: `Tests/NeedlbarCoreTests/DiagnosticsTests.swift`, `Tests/NeedlbarCoreTests/BridgeDecodingTests.swift`, `Tests/NeedlbarTests/ClaudeQuotaFailureDiagnosticsReporterTests.swift`

**Interfaces:**
- Consumes: nothing still references the old types after Task 11.
- Produces: the final `ClaudeQuotaFailureOrigin` set in Rust and Swift: `claudeCliNotFound`, `usageReportNoUsage`, `usageProbeTimedOut`, `usageProbeOutputTooLarge`, `usageProbeFailed`, `usageReportRateLimited`, `usageReportFormatChanged`, `otherFailure`.

- [ ] **Step 1: Write the failing test**

`crates/needlbar-quota/tests/claude_source_contract.rs`:

```rust
//! Source-level checks that the Claude path reads no Keychain item or credential
//! file and calls no private endpoint. This file is outside the scanned trees.

use std::{
    fs,
    path::{Path, PathBuf},
};

use needlbar_quota::USAGE_PROBE_ARGUMENTS;

fn rust_files(directory: &Path, files: &mut Vec<PathBuf>) {
    for entry in fs::read_dir(directory).unwrap() {
        let path = entry.unwrap().path();
        if path.is_dir() {
            rust_files(&path, files);
        } else if path.extension().is_some_and(|extension| extension == "rs") {
            files.push(path);
        }
    }
}

fn scanned_sources() -> Vec<(PathBuf, String)> {
    let manifest = Path::new(env!("CARGO_MANIFEST_DIR"));
    let mut files = Vec::new();
    rust_files(&manifest.join("src"), &mut files);
    rust_files(&manifest.join("../needlbar-bridge/src"), &mut files);
    assert!(files.len() > 10, "the source walk found the tree");
    files
        .into_iter()
        .map(|path| {
            let text = fs::read_to_string(&path).unwrap();
            (path, text)
        })
        .collect()
}

#[test]
fn the_claude_path_has_no_keychain_credential_file_or_endpoint_call() {
    for (path, text) in scanned_sources() {
        for forbidden in [
            "security_framework",
            "SecItem",
            "SecKeychain",
            "kSecClass",
            "Claude Code-credentials",
            ".credentials.json",
            "claudeAiOauth",
            "api.anthropic.com",
            "oauth/usage",
            "anthropic-beta",
            "/usr/bin/security",
            "ClaudeCredential",
            "ClaudeOAuthSecret",
        ] {
            assert!(
                !text.contains(forbidden),
                "{} still contains {forbidden}",
                path.display()
            );
        }
    }
}

#[test]
fn the_manifests_no_longer_depend_on_the_keychain_crates() {
    let manifest = Path::new(env!("CARGO_MANIFEST_DIR"));
    for file in ["Cargo.toml", "../../Cargo.toml"] {
        let text = fs::read_to_string(manifest.join(file)).unwrap();
        for forbidden in ["security-framework", "core-foundation", "zeroize"] {
            assert!(!text.contains(forbidden), "{file} still lists {forbidden}");
        }
    }
}

#[test]
fn the_probe_uses_no_shell_or_path_search_and_never_a_login_command() {
    let manifest = Path::new(env!("CARGO_MANIFEST_DIR"));
    for file in ["src/providers/claude_usage_probe.rs", "src/providers/claude_cli.rs"] {
        let text = fs::read_to_string(manifest.join(file)).unwrap();
        for forbidden in ["/bin/sh", "/bin/zsh", "/bin/bash", "\"-c\"", "\"-lc\"", "var_os(\"PATH\")"] {
            assert!(!text.contains(forbidden), "{file} contains {forbidden}");
        }
    }
    for argument in USAGE_PROBE_ARGUMENTS {
        assert!(!argument.contains("auth"), "{argument}");
        assert!(!argument.contains("login"), "{argument}");
    }
}

#[test]
fn logs_and_errors_have_no_path_to_raw_output() {
    let manifest = Path::new(env!("CARGO_MANIFEST_DIR"));
    for file in [
        "src/providers/claude_usage_probe.rs",
        "src/providers/claude_usage_report.rs",
        "src/providers/claude_usage_provider.rs",
    ] {
        let text = fs::read_to_string(manifest.join(file)).unwrap();
        for forbidden in ["println!", "eprintln!", "dbg!", "from_utf8", "to_string_lossy", "tracing::", "log::"] {
            assert!(!text.contains(forbidden), "{file} contains {forbidden}");
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test -p needlbar-quota --test claude_source_contract`
Expected: FAIL with `claude_credentials.rs still contains security_framework` or similar.

- [ ] **Step 3: Delete the code**

```bash
git rm crates/needlbar-quota/src/providers/claude_credentials.rs crates/needlbar-quota/src/providers/claude.rs crates/needlbar-quota/tests/claude.rs Fixtures/quota/claude/usage-success.json Fixtures/quota/claude/usage-fable-success.json Fixtures/quota/claude/usage-malformed.json
```

`crates/needlbar-quota/src/providers/mod.rs`:

```rust
use async_trait::async_trait;

use crate::{ProviderQuotaSnapshot, QuotaError};

pub mod claude_cli;
pub mod claude_usage_probe;
pub mod claude_usage_provider;
pub mod claude_usage_report;
pub mod codex;
pub mod cursor;

#[async_trait]
pub trait QuotaProvider: Send + Sync {
    async fn fetch(&self) -> Result<ProviderQuotaSnapshot, QuotaError>;
}
```

`crates/needlbar-quota/src/lib.rs`:

```rust
//! Provider quota retrieval. This crate deliberately keeps credentials and
//! provider responses on the Rust side of the bridge.

mod domain;
mod http;
pub mod providers;

pub use domain::{
    normalize_percent, ClaudeQuotaFailureOrigin, ProviderId, ProviderQuotaSnapshot, QuotaError,
    QuotaErrorCode, QuotaWindow,
};
pub use http::RedactingHttpClient;
pub use providers::claude_cli::ClaudeCliLocator;
pub use providers::claude_usage_probe::{
    run_usage_probe, UsageProbeControl, UsageProbeEnvironment, UsageProbeFailure, UsageProbeLimits,
    USAGE_PROBE_ARGUMENTS,
};
pub use providers::claude_usage_provider::{
    ClaudeUsageProbeSummary, ClaudeUsageReportProvider, ClaudeUsageReportRun,
};
pub use providers::claude_usage_report::{
    parse_usage_report_stream, ClaudeUsageReportOutcome, ClaudeUsageRowKind, ClaudeUsageRowSummary,
};
pub use providers::codex::{CodexQuotaProvider, CodexQuotaSource};
pub use providers::cursor::CursorQuotaProvider;
pub use providers::QuotaProvider;
```

`crates/needlbar-quota/src/http.rs`: change the import to `use crate::{QuotaError, QuotaErrorCode};`; delete `ANTHROPIC_USAGE_HOST`, `pub fn new()` and `impl Default for RedactingHttpClient`. Change the comment on `MAX_RESPONSE_BODY_BYTES` to start "A small quota document does not need unbounded buffering." Replace the 401 and 403 arm of `status_error`, and drop the status tag from the 5xx arm:

```rust
        401 | 403 => QuotaError::new(
            None,
            QuotaErrorCode::AuthenticationExpired,
            "Provider authentication has expired.",
        ),
```

```rust
        500..=599 => QuotaError::new(
            None,
            QuotaErrorCode::ServiceUnavailable,
            "The quota service is temporarily unavailable.",
        )
        .with_retry_after(retry_after),
```

`crates/needlbar-quota/src/domain.rs`: delete from `ClaudeQuotaFailureOrigin` the cases `CredentialMissing`, `KeychainCredentialExpired`, `FileCredentialExpired`, `CredentialAccessDenied`, `CredentialStoreAmbiguous`, `CredentialFormatUnrecognized`, `UsageEndpointUnauthorized`, `UsageEndpointForbidden`, `UsageEndpointServerError`, `UsageResponseUnrecognized`. Delete `enum ClaudeUsageEndpointStatus`; the fields `usage_endpoint_status` and `claude_credential_busy` with their initializers; and the functions `claude_credential_busy`, `is_claude_credential_busy`, `with_usage_endpoint_status`, `usage_endpoint_status`.

`crates/needlbar-quota/Cargo.toml` `[dependencies]` becomes the block below, and the `[target.'cfg(target_os = "macos")'.dependencies]` section is removed:

```toml
[dependencies]
serde.workspace = true
serde_json.workspace = true
chrono.workspace = true
thiserror.workspace = true
async-trait.workspace = true
reqwest.workspace = true
tokio.workspace = true
tempfile.workspace = true
libc.workspace = true

[dev-dependencies]
tempfile.workspace = true
```

In the workspace `Cargo.toml`, delete the lines `security-framework = "3.7.0"`, `security-framework-sys = "2.17.0"`, `core-foundation = "0.10"`, `core-foundation-sys = "0.8.7"`, `zeroize = "1.8"`.

`crates/needlbar-bridge/src/quota.rs`: the drop arm becomes:

```rust
            // The run was cancelled, so there is no Claude outcome to report.
            Err(error) if error.is_claude_usage_report_cancelled() => {}
```

In the unit tests of `crates/needlbar-bridge/src/lib.rs`, replace the origin array in `diagnostics_serializes_every_closed_claude_failure_origin_by_its_stable_name` with:

```rust
        for (origin, name) in [
            (Origin::ClaudeCliNotFound, "claudeCliNotFound"),
            (Origin::UsageReportNoUsage, "usageReportNoUsage"),
            (Origin::UsageProbeTimedOut, "usageProbeTimedOut"),
            (Origin::UsageProbeOutputTooLarge, "usageProbeOutputTooLarge"),
            (Origin::UsageProbeFailed, "usageProbeFailed"),
            (Origin::UsageReportRateLimited, "usageReportRateLimited"),
            (Origin::UsageReportFormatChanged, "usageReportFormatChanged"),
            (Origin::OtherFailure, "otherFailure"),
        ] {
```

and run this for the fixtures in the same file:

```bash
/usr/bin/perl -pi -e 's/ClaudeQuotaFailureOrigin::UsageEndpointUnauthorized/ClaudeQuotaFailureOrigin::UsageProbeTimedOut/g; s/ClaudeQuotaFailureOrigin::UsageEndpointForbidden/ClaudeQuotaFailureOrigin::UsageProbeFailed/g; s/ClaudeQuotaFailureOrigin::KeychainCredentialExpired/ClaudeQuotaFailureOrigin::UsageReportFormatChanged/g; s/"usageEndpointForbidden"/"usageProbeFailed"/g; s/"keychainCredentialExpired"/"usageReportFormatChanged"/g' crates/needlbar-bridge/src/lib.rs
```

- [ ] **Step 4: Trim the Swift origin enum and its tests**

In `Sources/NeedlbarCore/Diagnostics/DiagnosticsSnapshot.swift`, delete the same ten cases from `ClaudeQuotaFailureOrigin`.

`Tests/NeedlbarCoreTests/DiagnosticsTests.swift`: in `diagnosticsDecoderAcceptsOnlyClosedClaudeFailureOriginsAndOptionalAttemptTime` use:

```swift
    let origins: [ClaudeQuotaFailureOrigin] = [
        .claudeCliNotFound, .usageReportNoUsage, .usageProbeTimedOut, .usageProbeOutputTooLarge,
        .usageProbeFailed, .usageReportRateLimited, .usageReportFormatChanged, .otherFailure,
    ]
```

Delete `diagnosticsDecoderAcceptsTheSplitOtherFailureOriginsByTheirRustNames`, which `diagnosticsDecoderAcceptsTheUsageReportSourceOriginsAndRunSummary` from Task 5 replaces. In any remaining payload in that file that names an old origin, use `usageProbeFailed`.

`Tests/NeedlbarCoreTests/BridgeDecodingTests.swift`, in `rustBridgeDiagnosticsEnvelopeDecodesEachSplitOtherFailureOriginAndFreesItsPointer`:

```swift
    for origin in [
        "claudeCliNotFound", "usageReportNoUsage", "usageProbeTimedOut", "usageProbeOutputTooLarge",
        "usageProbeFailed", "usageReportRateLimited", "usageReportFormatChanged",
    ] {
```

`Tests/NeedlbarTests/ClaudeQuotaFailureDiagnosticsReporterTests.swift`: replace the `cases` array in `reporterLogsEachSplitOtherFailureOriginWithItsProducerCode` with:

```swift
    let cases = [
        ("claudeCliNotFound", "notInstalled"),
        ("usageReportNoUsage", "requiresAuthentication"),
        ("usageProbeTimedOut", "providerUnavailable"),
        ("usageProbeOutputTooLarge", "providerUnavailable"),
        ("usageProbeFailed", "providerUnavailable"),
        ("usageReportRateLimited", "rateLimited"),
        ("usageReportFormatChanged", "schemaChanged"),
    ]
```

Replace its `allCasesForTest` with:

```swift
    static let allCasesForTest: [Self] = [
        .claudeCliNotFound, .usageReportNoUsage, .usageProbeTimedOut, .usageProbeOutputTooLarge,
        .usageProbeFailed, .usageReportRateLimited, .usageReportFormatChanged, .otherFailure,
    ]
```

and replace any other old origin string in that file with `usageProbeFailed`:

```bash
/usr/bin/perl -pi -e 's/"(keychainCredentialExpired|fileCredentialExpired|credentialMissing|credentialAccessDenied|usageEndpointUnauthorized|usageEndpointForbidden)"/"usageProbeFailed"/g; s/origin=(keychainCredentialExpired|fileCredentialExpired|credentialMissing|credentialAccessDenied|usageEndpointUnauthorized|usageEndpointForbidden)/origin=usageProbeFailed/g' Tests/NeedlbarTests/ClaudeQuotaFailureDiagnosticsReporterTests.swift
```

Add to `ClaudeUsageReportSourceContractTests`:

```swift
    @Test func noSwiftCodeNamesARetiredOrigin() throws {
        try Self.expectAbsent([
            "credentialMissing", "keychainCredentialExpired", "fileCredentialExpired",
            "credentialStoreAmbiguous", "credentialFormatUnrecognized",
            "usageEndpointUnauthorized", "usageEndpointForbidden", "usageEndpointServerError",
            "usageResponseUnrecognized",
        ])
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cargo test --workspace --features bridge-test-runtime`
Expected: PASS. `Cargo.lock` loses the crate's direct edges. `security-framework` may stay in the lock as a transitive dependency of `reqwest`'s TLS stack; that is expected and the manifest test checks only the manifests.

Run: `cargo test --workspace`
Expected: PASS, matching `.github/workflows/ci.yml:46`.

Run: `cargo test -p needlbar-quota --test codex --test cursor`
Expected: PASS and unchanged: Codex keeps working.

Run: `make swift-test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A crates Cargo.toml Cargo.lock Fixtures Sources Tests
git commit -m "feat(quota): delete the Claude Keychain, credential and endpoint code

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 13: Documentation and release contract

Everything here says prepared, not released. No document claims runtime verification, because none has run yet.

**Files:**
- Modify: `docs/superpowers/specs/2026-10-07-claude-refresh-reliability-design.md`, `docs/superpowers/specs/2026-10-22-claude-credential-renewal-design.md`, `docs/superpowers/specs/2026-09-15-claude-passive-quota-recovery-design.md`, `docs/superpowers/specs/2026-09-25-claude-statusline-quota-bridge-design.md`, `docs/providers/claude.md`, `docs/privacy.md`, `docs/architecture.md`, `docs/HANDOFF.md`, `docs/STATUS.md`, `README.md`, `docs/releases/v0.3.15.md`, `docs/superpowers/plans/2026-11-02-v0.3.15-release.md`
- Test: `scripts/tests/notarize-app-tests.sh:2239`

**Interfaces:**
- Consumes: the implemented behaviour of Tasks 1-12.
- Produces: README heading `### Claude quota from the Claude Code usage report (v0.3.15 prepared)`, named by the historical fixture.

- [ ] **Step 1: Point the release contract at the new heading**

Replace line 2239 of `scripts/tests/notarize-app-tests.sh` with:

```ruby
abort 'historical fixture: v0.3.15 prepared section missing' unless document.sub!(/^### Claude quota from the Claude Code usage report \(v0\.3\.15 prepared\)\n.*?(?=^### |\z)/m, '')
```

- [ ] **Step 2: Run the contract to verify it fails**

Run: `./scripts/tests/notarize-app-tests.sh`
Expected: FAIL with `historical fixture: v0.3.15 prepared section missing`.

- [ ] **Step 3: Update the README, notes, plan and specs**

Run this script once from the repository root:

```bash
/usr/bin/python3 -I - <<'PY'
import pathlib, re

def insert_before_first_section(name, note):
    path = pathlib.Path(name)
    source = path.read_text()
    match = re.search(r"^## ", source, re.M)
    assert match, name
    path.write_text(source[:match.start()] + note.strip() + "\n\n" + source[match.start():])

insert_before_first_section("docs/superpowers/specs/2026-10-07-claude-refresh-reliability-design.md", """
> **Amendment — 2026-11-03:** Approved by the user in
> `2026-11-03-claude-usage-report-source-design.md`. "No Claude
> authentication/configuration write" no longer covers a renewal performed by
> Claude Code itself during a spawned `/usage`. Needlbar itself still performs no
> authentication or configuration write. Where this design says "direct", builds
> prepared from that design read the usage report instead of the usage endpoint.
""")
insert_before_first_section("docs/superpowers/specs/2026-10-22-claude-credential-renewal-design.md", """
> **Amendment — 2026-11-03:** Approved by the user in
> `2026-11-03-claude-usage-report-source-design.md`. Q7 closes: the direct token
> path is retired. Option C's click-only condition is superseded for `/usage`,
> which now runs automatically under that design's limits. The objection that
> retirement loses Fable is answered by `weekly_scoped` rows in the usage report.
""")
insert_before_first_section("docs/superpowers/specs/2026-09-15-claude-passive-quota-recovery-design.md", """
> **Amendment — 2026-11-03:** Approved by the user in
> `2026-11-03-claude-usage-report-source-design.md`. The ban on Terminal
> instructions gains an exception for the signed-out and not-installed states,
> which tell the user to sign in with `claude` in Terminal or to install Claude
> Code. Neither offers a launch button. The 2026-11-02 `Allow Keychain access`
> amendment is withdrawn: that action was never released and is removed.
""")
insert_before_first_section("docs/superpowers/specs/2026-09-25-claude-statusline-quota-bridge-design.md", """
> **Amendment — 2026-11-03:** Approved by the user in
> `2026-11-03-claude-usage-report-source-design.md`. The status line becomes the
> secondary source, after the usage report and before last-known values. A newer
> valid reading wins regardless of source.
""")

path = pathlib.Path("README.md")
source = path.read_text()
section = """### Claude quota from the Claude Code usage report (v0.3.15 prepared)

The prepared v0.3.15 changes replace how Needlbar gets Claude quota. Needlbar no
longer reads Claude Code's Keychain item or credentials file and no longer calls
the usage endpoint. It runs `/usage` through your installed `claude`
(`~/.local/bin/claude`, `/opt/homebrew/bin/claude` or `/usr/local/bin/claude`,
never through a shell) and reads the documented `usage_report` field, which is
marked experimental. Runs happen at app start, on manual refresh, when Claude
Code's local usage records change, when a displayed window's reset passes, and
after 15 minutes without a run, at most once every 5 minutes. Opening the dashboard
alone starts none. A reading stays current for 20 minutes, and usage outside Claude
Code appears within about 15 minutes while the app is running and the Mac is awake.
That can mean about 96 runs a day from the periodic run alone, and up to 288 a day with other triggers, because runs are at least 5 minutes apart. A run is
limited to 30 seconds and 1 MiB of output, works in one fixed folder in the temporary directory that is emptied before each run,
and its output is neither logged nor stored. The status line remains the second
source and last-known values the third; a newer valid reading wins. A window the
report omits is hidden, not shown as zero. Without Claude Code the app shows
install guidance and the usage link; with no usage available it says to sign in
with `claude` in Terminal and offers no button. Needlbar never runs `claude auth`
and writes no Claude configuration, though Claude Code may renew its own login
during a run, and `claude` itself may show a Keychain prompt. **Allow Keychain
access**, which an earlier prepared build had, is removed. This has not run for
24 hours on a real machine, and duration, memory, CPU, the cost of up to 288 runs a day and any rate limit on `/usage` have not been measured. It is not part of any
public release yet.

"""
source, count = re.subn(r"^### Claude Keychain access action \(v0\.3\.15 prepared\)\n.*?(?=^### )", lambda _: section, source, count=1, flags=re.M | re.S)
assert count == 1
path.write_text(source)

pathlib.Path("docs/releases/v0.3.15.md").write_text("""Needlbar v0.3.15 changes where the Claude quota comes from. It no longer reads Claude Code's Keychain item or credentials file and no longer calls the usage endpoint, so Needlbar stops causing Keychain dialogs of its own.

- Needlbar now runs `/usage` through your installed Claude Code command-line tool and reads its usage report. The command is fixed and runs without a shell, in one fixed folder in the temporary directory that is emptied before each run, for at most 30 seconds. Its output is not logged or stored.
- Runs happen when Needlbar starts, when you refresh, when Claude Code's local usage records change, when a displayed window's reset passes, and after 15 minutes without a run, at most once every 5 minutes. Opening the dashboard does not start one. After repeated failures Needlbar waits 5, 10, 20, then 30 minutes.
- A window the report leaves out is hidden, never shown as zero. On accounts without a five-hour window, the quota shows the weekly windows.
- The Claude Code status line stays as the second source and last-known values as the third, labelled with the time they were checked. A newer valid reading wins whichever source it came from.
- Without Claude Code, Needlbar shows install guidance and the usage link. When Claude Code reports no usage, it says to sign in with `claude` in Terminal. It never runs `claude auth` or opens a login flow.

Known limits: usage outside Claude Code, such as on the web, appears within about 15 minutes while Needlbar is running and the Mac is awake. That means about 96 runs a day from the periodic run alone, and up to 288 a day with other triggers, because runs are at least 5 minutes apart, whose memory and CPU cost has not been measured. A reading shows as last known after a failed run or once it is 20 minutes old. The usage report is marked experimental and can change, in which case Needlbar shows last-known values. API-key and usage-billed Claude Code sessions do not produce a usage report. Fable matching depends on a display label. Claude Code may renew its own login during a run, and `claude` itself may show a Keychain prompt. Native overnight, quota-reset, sustained unattended, and native macOS 14 acceptance remain unverified.
""")

path = pathlib.Path("docs/superpowers/plans/2026-11-02-v0.3.15-release.md")
source = path.read_text()
note = """> **Amendment — 2026-11-03:** Superseded before any tag. The candidate this plan
> prepared was never tagged or published. `docs/superpowers/plans/2026-11-03-claude-usage-report-source.md`
> replaces its product content and `docs/releases/v0.3.15.md` was rewritten. A new
> release plan is needed, and spec §11 of the usage report design holds a release
> gate: no public build until the user decides the terms question.

"""
heading = source.index("\n\n") + 2
path.write_text(source[:heading] + note + source[heading:])
PY
```

- [ ] **Step 4: Run the contract to verify it passes**

Run: `./scripts/tests/notarize-app-tests.sh`
Expected: exits 0.

Run: `env -u LANG -u LC_ALL -u LC_CTYPE ./scripts/tests/notarize-app-tests.sh`
Expected: exits 0.

- [ ] **Step 5: Update the runbook, privacy policy and architecture**

Run this script once from the repository root:

```bash
/usr/bin/python3 -I - <<'PY'
import pathlib

def replace(name, pairs):
    path = pathlib.Path(name)
    source = path.read_text()
    for old, new in pairs:
        assert old in source, (name, old[:60])
        source = source.replace(old, new)
    path.write_text(source)

# docs/providers/claude.md: everything after the usage source is rewritten.
path = pathlib.Path("docs/providers/claude.md")
source = path.read_text()
keep = source[: source.index("## Authentication source and precedence")]
path.write_text(keep + """## Quota source

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
- **Limits:** one fixed working directory, `<TMPDIR>/needlbar-claude-usage`, created with mode 0700, refused if it is a symlink or not a directory, and emptied before each run; no standard input; an
  environment of only `HOME`, `USER`, `LOGNAME`, `TMPDIR`, a fixed `PATH`, and `CLAUDE_CONFIG_DIR`
  if the app already has it; 30 seconds, then the process group is terminated; 1 MiB of standard
  output, then the same; standard error discarded; cancelled when the app stops.
- **When:** at app start, on manual refresh, when Claude Code's local usage records change, when a
  displayed window's reset passes, and after 15 minutes without a run. Automatic runs happen at most
  once every 5 minutes and only one at a time. Manual refresh skips the interval and backoff but joins
  a run in flight. Opening the dashboard, waking the Mac and regaining a connection start no run
  themselves, though the once-a-minute check can find a run overdue after sleep and start it.
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
| No usage available, or signed out | **Sign in with claude in Terminal**; no launch button | Last known or none | Next trigger, with backoff |
| Timed out, too much output, or the process failed | **Could not check Claude Code** and the last checked time | Last known | Backoff |
| Rate limited | **Temporarily limited** and the last checked time | Last known | Backoff |
| No readable report | **Could not read Claude Code's usage report** and the last checked time | Last known | Backoff |

The run after 15 minutes counts as a trigger, so the first two states are tried again about every
15 minutes, further apart under backoff. How a signed-out `claude` reports itself in this mode has not
been observed. Until it is, a non-zero exit counts as a process failure, and only a null `rate_limits` or empty `limits` shows the
sign-in guidance. API-key, usage-billed and `claude setup-token` sessions produce no `usage_report`,
so they show the no-readable-report state. Usage outside Claude Code, such as on the web, appears
within about 15 minutes while the app is running and the Mac is awake. That means about 96 runs a day from the periodic run alone, and up to 288 a day with other triggers, because runs are at least 5 minutes apart,
whose memory and CPU cost has not been measured.

Diagnostics record the failure reason, the run duration and the row kinds seen, never tokens, output
text or emails. The `ClaudeQuotaFailureDiagnostic` and `QuotaRefreshDiagnostic` log categories stay
on this Mac.

**View Claude usage** opens only `https://claude.ai/settings/usage` after an explicit click.

Needlbar does not own Claude credentials and therefore does not provide a Claude Disconnect button. Sign out or revoke the provider session through Claude's supported controls; Needlbar will then show the no-usage state on the next run.
""")

# docs/privacy.md
path = pathlib.Path("docs/privacy.md")
source = path.read_text()
rows = source.split("\n")
index = next(i for i, row in enumerate(rows) if row.startswith("| Claude | `~/.claude/projects`"))
rows[index] = ("| Claude | `~/.claude/projects` and `~/.claude/transcripts`, delegated to the pinned `tokscale-core` engine | "
               "Prepared for the next release, not in v0.3.14: none read by Needlbar. Quota comes from `/usage` run by the user's "
               "installed `claude`, which uses its own login. v0.3.14 still reads Claude Code's Keychain item or credentials file. |")
path.write_text("\n".join(rows))

replace("docs/privacy.md", [
    ("- Claude and Codex quota requests go directly to their providers. Needlbar does not proxy or relay those requests.\n",
     "- Codex quota requests go directly to the provider. Prepared for the next release, not in v0.3.14: Claude quota comes from `/usage` run by the user's installed `claude`, and Needlbar makes no Claude request itself. Needlbar does not proxy or relay these requests.\n"),
    ("- Claude and Codex browser sign-in is explicit. Their buttons launch the installed provider\n  CLI, which owns browser navigation, OAuth callbacks, refresh, and credential storage.\n",
     "- Codex browser sign-in is explicit. Its button launches the installed provider CLI, which owns\n  browser navigation, OAuth callbacks, refresh, and credential storage. Prepared for the next\n  release, not in v0.3.14: Needlbar has no Claude sign-in and never runs `claude auth`.\n"),
    ("- Claude quota uses the Anthropic OAuth usage endpoint with existing local OAuth evidence.\n  Background Keychain access is interaction-forbidden and never prompts. Only the explicit\n  post-login Claude verification path may allow a macOS Keychain permission prompt.\n",
     "- Prepared for the next release, not in v0.3.14: Needlbar makes no Claude network request. It runs\n  `/usage` through the user's installed `claude`, with a fixed command, no shell, one fixed working\n  folder in the temporary directory that is emptied before each run, a minimal environment and a 30-second limit. Any network use, login renewal or Keychain\n  prompt during that run belongs to `claude`. Needlbar reads only the `usage_report` field and an\n  error label, and discards the rest without logging or storing it. It reads no Claude Keychain item\n  or credential file. v0.3.14 still uses the Anthropic usage endpoint with existing local evidence.\n"),
    ("Needlbar does not log authorization headers,\ncookies, response bodies, prompt text, response text, or source code. Raw Claude credential\nmaterial is held only ephemerally inside the Rust quota adapter, with zeroizing storage where\nNeedlbar owns the buffer; it is not persisted by Needlbar, copied into Swift, or exposed\nthrough the C ABI. A failed request",
     "Needlbar does not log authorization headers,\ncookies, response bodies, prompt text, response text, command output, or source code. A failed request"),
    ("Claude and Codex use provider-native CLI/browser sign-in. Needlbar does not own their\ncredentials and has no separate disconnect action; sign out or revoke access through the\nprovider's supported app/CLI controls, then retry in Needlbar. If the CLI is not installed,\nNeedlbar reports a provider-scoped failure and leaves other providers available. If Claude\nKeychain access is denied or cancelled, grant access in macOS when appropriate or complete\nprovider re-authentication, then retry; Needlbar does not broaden the Keychain query or fall\nback to browser-cookie crawling.\n",
     "Claude and Codex use provider-native CLI/browser sign-in. Needlbar does not own their\ncredentials and has no separate disconnect action; sign out or revoke access through the\nprovider's supported app/CLI controls, then retry in Needlbar. If the CLI is not installed,\nNeedlbar reports a provider-scoped failure and leaves other providers available. Needlbar does\nnot crawl browser cookies. Prepared for the next release, not in v0.3.14: when Claude Code reports\nno usage, Needlbar says to sign in with `claude` in Terminal and offers no button.\n"),
    ("Only the minimum normalized data needed for Claude and Codex quota requests leaves the machine,\nand those requests go directly to their providers.",
     "Only the minimum normalized data needed for Codex quota requests leaves the machine, and those\nrequests go directly to the provider. Prepared for the next release, not in v0.3.14: Needlbar sends\nnothing for Claude quota; the installed `claude` does its own work when Needlbar runs `/usage`."),
])

# docs/architecture.md
replace("docs/architecture.md", [
    ("                    │   └── Claude and Codex quota/auth adapters; Cursor unavailable result\n",
     "                    │   └── Claude usage report runner, Codex quota/auth adapter; Cursor unavailable result\n"),
    ("Needlbar's AppKit layer also owns `ProviderLoginCoordinator`. It launches only the fixed\nprovider commands through the installed executable's direct path,",
     "Needlbar's AppKit layer also owns `ProviderLoginCoordinator`. It launches only the fixed\nCodex login command through the installed executable's direct path,"),
    ("Claude OAuth evidence -> Anthropic usage API ───────┐\nCodex OAuth -> OpenAI usage API -> CLI RPC fallback ├─> quota envelope\nCursor quota unavailable; Settings/popover open Spending dashboard ─┘\n```\n",
     "Codex OAuth -> OpenAI usage API -> CLI RPC fallback ┐\nCursor quota unavailable; Settings/popover open Spending dashboard ┴─> quota envelope\n\nInstalled claude -> /usage -> usage_report ───────────> Claude quota envelope\n```\n"),
    ("Claude and Codex login are explicit user actions. After a successful provider CLI exit,\n`NeedlbarCore` requests a quota-only refresh for that provider. Claude's dedicated\npost-authentication bridge path may allow the exact provider-owned macOS Keychain item to\nbe read; ordinary background refresh always uses interaction-forbidden access. Codex uses\nits provider-specific quota path. A failed verification preserves the last-known-good\nquota state and does not mark all-provider background refresh fresh.\n",
     "Codex login is an explicit user action. After a successful CLI exit, `NeedlbarCore` requests a\nquota-only refresh for Codex. A failed verification preserves the last-known-good quota state and\ndoes not mark the background refresh fresh.\n\nPrepared for the next release, not in v0.3.14: Claude has no login path. `RefreshCoordinator` runs\nClaude on its own slot, off the cooperative pool, under `ClaudeUsageProbeSchedule`: at app start, on\nmanual refresh, when the Claude total in the usage refresh changes, when a displayed reset passes,\nand after 15 minutes without a run, at most once every 5 minutes with backoff. The Codex and Cursor refresh never waits for it.\nA stop cancels by run ID through `needlbar_claude_usage_report_cancel_through`, which signals the\nprocess group before returning.\n"),
    ("const char *needlbar_claude_user_initiated_quota_snapshot_json(void);\n",
     "const char *needlbar_claude_usage_report_quota_snapshot_json(uint64_t run_id);\nvoid needlbar_claude_usage_report_cancel_through(uint64_t run_id);\n"),
    ("Credential resolution and provider responses stay in Rust and are redacted before any error crosses the bridge. The raw Claude credential is ephemeral and zeroizing inside\n`needlbar-quota`; it is never persisted by Needlbar or exported through the C ABI. Cursor\nhas no credential integration",
     "Credential resolution and provider responses stay in Rust and are redacted before any error crosses the bridge. Needlbar holds no Claude credential, and `claude` output stays inside\n`needlbar-quota`, which passes only windows and closed labels over the C ABI. Cursor\nhas no credential integration"),
])
PY
```

- [ ] **Step 6: Update HANDOFF and STATUS**

Run this script once from the repository root:

```bash
/usr/bin/python3 -I - <<'PY'
import pathlib, re

path = pathlib.Path("docs/HANDOFF.md")
source = path.read_text()
old = """**Checkpoint:** 2026-11-02, updated after the v0.3.14 release and for the Claude
Keychain access action, which is prepared and not released (first written"""
new = """**Checkpoint:** 2026-11-03, updated for the Claude usage report source, which is
prepared and not released; it replaces the Claude Keychain access action of
2026-11-02, which was never released (first written"""
assert old in source
source = source.replace(old, new)
section = """## Claude usage report source (prepared for v0.3.15, not released)

Design: `docs/superpowers/specs/2026-11-03-claude-usage-report-source-design.md`. Plan:
`docs/superpowers/plans/2026-11-03-claude-usage-report-source.md`. Needlbar no longer reads
Claude's Keychain item or credentials file and no longer calls the usage endpoint. It runs `/usage`
through the installed `claude` and reads `usage_report`, with the status line second and last-known
values third. **Allow Keychain access** and `requestClaudeKeychainAccess` are removed; that action
never shipped. Runs have their own slot and schedule in `RefreshCoordinator`, so Codex and Cursor
never wait for them, and the popover, wake and connectivity start none. A periodic run after 15
minutes without one keeps readings current (user decision, 2026-11-03), and a reading stays current
for 20 minutes, including on the widget's Claude row.

None of this has run for 24 hours on a real machine. Still open: how a signed-out `claude` reports
itself in this mode, run duration, memory and CPU, the cost of up to 288 runs a day, whether `/usage`
has its own rate limit, and whether 30 seconds is the right deadline. Those checks are user-run; see Task 14 of the plan.

**Release gate (spec §11):** before any public build, the user decides how to resolve the terms
question in spec §3: ask Anthropic, or ship on a stated reading. Until then the build runs on this
Mac only. No tag or release is authorized, and the v0.3.15 release plan of 2026-11-02 is superseded.

"""
source, count = re.subn(r"^## Claude Keychain access action \(prepared for v0\.3\.15, not released\)\n.*?(?=^## CI runners)", lambda _: section, source, count=1, flags=re.M | re.S)
assert count == 1
old = "- `crates/needlbar-quota/src/providers/claude_credentials.rs`\n"
new = """- `crates/needlbar-quota/src/providers/claude_usage_provider.rs`
- `crates/needlbar-quota/src/providers/claude_usage_probe.rs`
- `crates/needlbar-quota/src/providers/claude_usage_report.rs`
- `Sources/NeedlbarCore/Refresh/ClaudeUsageProbeSchedule.swift`
"""
assert old in source
source = source.replace(old, new)
old = "Known open items:\n\n"
new = """Known open items:

- The Claude usage report source needs the user-run acceptance in Task 14 of its plan and a decision
  on the release gate. The items below describe v0.3.14 and earlier and are kept as history.
"""
assert old in source
source = source.replace(old, new)
path.write_text(source)

path = pathlib.Path("docs/STATUS.md")
source = path.read_text()
header = "# Needlbar Development Status\n\n"
assert source.startswith(header)
entry = """## 2026-11-03 Claude usage report source (prepared, not released)

Implements `docs/superpowers/specs/2026-11-03-claude-usage-report-source-design.md` through
`docs/superpowers/plans/2026-11-03-claude-usage-report-source.md`. Not merged, tagged or released.

- **Source.** Claude quota now comes from `/usage` run by the installed `claude`, read through the
  documented `usage_report` field. The status line is second and last-known values third. A newer
  valid reading wins. Claude left the all-provider refresh, so Codex and Cursor never wait for it.
- **Removed.** Claude's Keychain read, credential-file read and direct endpoint; the
  **Allow Keychain access** action, which never shipped; the keychain sequencing; the Claude login,
  preflight and verification paths; the two matching C exports; and the Keychain crates as direct
  dependencies. Codex code is unchanged and its tests run in every gate.
- **Runs.** App start, manual refresh, a changed Claude total in the usage refresh, a passed reset of
  a displayed window, and 15 minutes since the last run (user decision, 2026-11-03), at most once every
  5 minutes, with backoff of 5, 10, 20, then 30 minutes. The popover, wake, connectivity and the
  five-minute timer start none.
- **Freshness.** A report reading is current for 20 minutes, because a refresh due at 15 can finish
  about a minute and a half later. The widget's Claude quota row follows it; Codex, usage and the
  status line keep their windows.
- **Change detection.** The usage file watcher fires only for a root directory's own entries, for
  every provider, so it cannot see an append to a session file. The Claude total from the existing
  usage refresh serves instead, at most 5 minutes late. No new watcher was added.
- **Deviation from the design, reported to the user.** The design reads only `usage_report`, but that
  field has no rate-limit signal, so the parser also reads the documented closed `error` value on the
  same line, only when no report arrived. API-key, usage-billed and setup-token sessions produce no
  report and show the no-readable-report state.

Not established: no run on a real machine. A 24-hour run across a login renewal, how a signed-out
`claude` reports itself, duration, memory, CPU, any rate limit on `/usage`, and the 30-second deadline
are all user-run and open. So are the cost of up to 288 runs a day and whether the label stays steady
across them. **Release gate:** no public build until the user resolves the
terms question in spec §3. No Keychain item, credential file or cookie was read for this work, and no
agent ran `claude`.

"""
path.write_text(header + entry + source[len(header):])
PY
```

The entry names no commit hash, run ID, asset ID, `releases/tag/` or `report 0.3.`, because the public-record decoys in `scripts/tests/notarize-app-tests.sh` rewrite the first occurrence of those values.

- [ ] **Step 7: Verify documentation claims and contracts**

Run: `./scripts/tests/notarize-app-tests.sh`
Expected: exits 0.

Run: `git diff --check`
Expected: no output.

Run: `grep -n 'Keychain\|credentials.json\|usage endpoint' docs/providers/claude.md`
Expected: only the v0.3.14 sentence in the first paragraph of `## Quota source`, the sentence that Needlbar reads no Claude Keychain item, and the sentence that `claude` itself may show a Keychain prompt.

Run: `grep -c '0\.3\.15' README.md`
Expected: `2`, the prepared heading and its first sentence.

- [ ] **Step 8: Commit**

```bash
git add README.md docs scripts/tests/notarize-app-tests.sh
git commit -m "docs: describe the Claude usage report source as prepared

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 14: Final gate and local acceptance

Only Steps 1-3 are for an implementer. Everything marked **USER-RUN** is for the user. Implementers do not run `claude`, install or launch the app, or read logs of a live app.

**Files:**
- Modify: `docs/STATUS.md` (one verification line now; acceptance results only after the user reports them)
- Modify when the user reports results: `docs/superpowers/specs/2026-11-03-claude-usage-report-source-design.md`

**Interfaces:**
- Consumes: Tasks 1-13.
- Produces: the implementer's verification line, and a checklist the user can run.

### Implementer

- [ ] **Step 1: Run the project gate**

Run: `make test`
Expected: exits 0. It covers the release-profile test, `cargo test --workspace --features bridge-test-runtime`, the bridge archive surface, the Swift suite, and the package and notarize contracts, all with fakes.

Run: `cargo test --workspace`
Expected: exits 0, matching CI without the fixture feature.

- [ ] **Step 2: Verify the removal**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeUsageReportSourceContract`
Expected: PASS.

Run: `cargo test -p needlbar-quota --test claude_source_contract`
Expected: PASS.

Run: `grep -rn 'needlbar_claude_user_initiated\|needlbar_claude_preflight' Sources crates scripts`
Expected: only the two negative assertions in `crates/needlbar-bridge/tests/ffi_contract.rs`.

Run: `git status --short`
Expected: clean except what Step 3 changes.

An implementer may also run `make package`, which builds and signs `dist/Needlbar.app` with the local identity and launches nothing. It must not open or install the result.

- [ ] **Step 3: Record verification and stop**

Add this line at the end of the new entry in `docs/STATUS.md`, using the counts the run printed. Keep it free of hashes and run IDs.

```text
Local verification on this branch: `make test` and `cargo test --workspace` passed (`<swift count>` Swift and `<rust count>` Rust tests). All process tests used a fake `claude`.
```

```bash
git add docs/STATUS.md
git commit -m "docs: record the usage report source verification

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Stop here and report to the user. Do not merge, push, install or tag. Hand over Steps 4-9 as the user's checklist.

### USER-RUN

- [ ] **Step 4: USER-RUN: decide on installing a local build**

Installing needs the user's separate request. Built with `make package`, the app is signed with the local identity. Since the release build signs with hardened runtime and this one does not (`scripts/package-app.sh:103`, `scripts/notarize-app.sh:134-136`), acceptance on a local build does not prove the notarized build behaves the same; repeat Step 7 on the first Developer ID build. Expected: the user says whether to install. An agent may then do it only as that request states.

- [ ] **Step 5: USER-RUN: see how a signed-out `claude` reports itself**

A temporary `CLAUDE_CONFIG_DIR` should make `claude` look signed out without touching the real login: Claude Code derives a different Keychain service and credentials path from it. That derivation is inferred from earlier observations, so the user decides whether to accept this. Run this in Terminal. It prints only line types, the error label and the report's shape, never the text:

```bash
probe_dir="$(mktemp -d)"
CLAUDE_CONFIG_DIR="$probe_dir" claude -p /usage --no-session-persistence --strict-mcp-config --settings '{"disableAllHooks":true}' --output-format stream-json --verbose </dev/null >"$probe_dir/out.jsonl" 2>/dev/null
echo "exit=$?"
/usr/bin/python3 -I -c '
import json, sys
for line in open(sys.argv[1]):
    try:
        message = json.loads(line)
    except ValueError:
        print("non-json line")
        continue
    if not isinstance(message, dict):
        continue
    report = message.get("usage_report", "absent")
    if isinstance(report, dict):
        report = "rate_limits=" + ("null" if report.get("rate_limits") is None else "object")
    print(message.get("type"), message.get("subtype"), "error=" + str(message.get("error")), "usage_report=" + str(report))
' "$probe_dir/out.jsonl"
rm -rf "$probe_dir"
```

What Needlbar would show for each result:

| Result | Today's state |
|---|---|
| `exit` not 0 | Could not check Claude Code |
| `exit=0`, `rate_limits=null` or empty `limits` | Could not check Claude Code (amended 2026-11-03: the CLI also reports this while its own usage fetch is failing, so it is not treated as signed out) |
| `exit=0`, `usage_report=absent` or `None` | Could not read Claude Code's usage report |
| `error=rate_limit`, no report | Temporarily limited |

Report the printed lines. This run is the only way to learn what a real signed-out `claude` prints; if it differs from the table, the user decides whether to add a signed-out state, which amends spec §8 and adds a parser or provider test first. This is also the one chance to see whether `error=rate_limit` can appear.

- [ ] **Step 6: USER-RUN: measure duration, memory and CPU, and decide the deadline**

Run five times in Terminal, a minute or more apart, with normal login:

```bash
/usr/bin/time -l claude -p /usage --no-session-persistence --strict-mcp-config --settings '{"disableAllHooks":true}' --output-format stream-json --verbose </dev/null 2>&1 >/dev/null | /usr/bin/grep -E 'real|maximum resident|user|sys'
```

Record for each run: real seconds, maximum resident set size, user and system seconds. Report the numbers only. Multiply user plus system seconds by 288 for the worst-case CPU of a day.

**30-second decision:** if any run takes more than 20 seconds, or a cold start after a login renewal comes near 30, the deadline changes in spec §6 before release and `UsageProbeLimits::default` changes with it, with a test. If all runs stay well under, record the numbers and keep 30 seconds.

- [ ] **Step 7: USER-RUN: observe for at least 24 hours, across a login renewal**

Leave the installed build running through at least one login renewal by Claude Code, which the 2026-10 logs put at about every eight hours while Claude Code is in use. Then run:

```bash
/usr/bin/log show --last 24h --style compact --predicate 'subsystem == "com.taejunoh.needlbar" AND category == "QuotaRefreshDiagnostic"' | /usr/bin/grep -c 'phase=completed'
/usr/bin/log show --last 24h --style compact --predicate 'subsystem == "com.taejunoh.needlbar" AND category == "QuotaRefreshDiagnostic"' | /usr/bin/grep 'phase=completed' | /usr/bin/grep -c 'trigger=periodic'
/usr/bin/log show --last 24h --style compact --predicate 'subsystem == "com.taejunoh.needlbar" AND category == "QuotaRefreshDiagnostic"' | /usr/bin/grep 'phase=completed' | /usr/bin/tail -n 40
/usr/bin/log show --last 24h --style compact --predicate 'subsystem == "com.taejunoh.needlbar" AND category == "ClaudeQuotaFailureDiagnostic"' | /usr/bin/tail -n 40
/usr/bin/log show --last 24h --style compact --predicate 'process == "SecurityAgent"' | /usr/bin/tail -n 40
```

Check and report:

- [ ] Needlbar causes no `SecurityAgent` dialog. A dialog naming `claude` or `security` is recorded honestly as that tool's, per spec §12, along with what triggered it.
- [ ] No macOS Files-and-Folders or other privacy prompt names Needlbar.
- [ ] Quota keeps updating after a renewal with no user action: `outcome=success` lines continue past it.
- [ ] `rows=` shows `weeklyAll,weeklyScoped` on this account, and no made-up session value appears.
- [ ] Automatic `start=` times are never under 5 minutes apart; only `trigger=manual` may be closer.
- [ ] `trigger=usageRecordsChanged` appears while Claude Code is in use and stops when it is idle, which also shows a run does not trigger itself.
- [ ] While idle and awake, `trigger=periodic` appears about every 15 minutes and nothing else does.
- [ ] Opening the dashboard adds no `quotaRefresh` line of its own. A `trigger=periodic` line may still fall at the same moment.
- [ ] Codex and Cursor quota keep updating during a run.
- [ ] The cost of up to 288 runs a day: the number of completed runs, their total `durationMs`, and the Step 6 memory and CPU figures scaled to that count, including any noticeable fan, battery or slowdown. If it is not acceptable, a longer interval is a design change for the user to approve.
- [ ] Label stability: while runs succeed, the dashboard, Settings and the widget's Claude row stay current across each refresh and never flip to **Last known** or **Stale** just before one. **Last known** appears only after a failed run, or when the Mac slept past 20 minutes, until the next run finishes.
- [ ] A signed-in session never shows **Could not check Claude Code** for long. An `origin=usageReportNoUsage` or `origin=usageReportRateLimited` line while signed in suggests `/usage` has a limit at this rate; report it (amended 2026-11-03: a null usage report is no longer treated as signed out).
- [ ] No token, email, output text or path appears in any of these lines.

- [ ] **Step 8: USER-RUN: decide the release gate**

Spec §11: before any public build, decide how to resolve the §3 question, ask Anthropic or ship on a stated reading of the terms. Until then the build runs on this Mac only. A public release then needs a new release plan and the user's separate request.

- [ ] **Step 9: Record results when the user reports them**

Only after the user reports Steps 5-7, an agent adds a dated, local-only receipt to `docs/STATUS.md`, with no hash or run ID, and amends the spec if a mapping or the deadline changed. Without a report, the docs keep saying unverified.

---

## Self-Review Against The Spec

| Spec | Requirement | Where |
|---|---|---|
| §5 | Source order: usage report, status line, last known; newer valid reading wins; no invented value | Task 8 Step 4, tests in Task 8; existing store and selector keep last-known labels |
| §5 | Removed: Keychain and credentials read, direct endpoint | Task 12 |
| §5 | Removed: button, copy, tests, `requestClaudeKeychainAccess`, sequencing | Task 10; lock in Task 12 |
| §5 | Removed: login-path leftovers | Task 11 |
| §5 | Unit boundaries and placement | Tasks 1, 2, 3, 6; Decisions 1 |
| §6 | Five triggers, 5-minute cap, single run, manual joins; dashboard, wake and connectivity start none | Tasks 6, 7; Decisions 2, 3 |
| §6 | Periodic run: 15 minutes, last in priority, behind the gate, never from a negative age, a trigger for every state | Task 6 `// MARK: - Periodic`; Task 7 `aQuietPeriodStartsAPeriodicRunEveryFifteenMinutes`, `notInstalledAndNoUsageRetryOnlyOnATriggerAndUnderBackoff`, `aFailedPeriodicRunKeepsTheReadingAsLastKnownAndBacksOff` |
| §6 | 20-minute freshness, status line unchanged, widget's Claude row | Task 8 Steps 8-12; Decisions 3a |
| §6 | Backoff 5, 10, 20, 30; success resets | Task 6; Task 7 `retryableFailuresBackOff…` |
| §6 | Locator order, symlinks, no shell or `PATH` | Task 2; Task 12 source contract |
| §6 | Fixed argv | Task 2 |
| §6 | Fixed emptied working directory, stdin, environment, deadline, 1 MiB, stderr, cancel, generation | Task 2; Task 4 cancel export; Task 7 `stopCancels…`, `restartWaits…` |
| §6 | Real duration measured; deadline change goes in the spec | Task 14 Step 6 |
| §6 | No `claude auth`, no login flow, no config write | Task 11; source contract |
| §7 | Parsing rules, including `session` key vs `session` row | Task 1 |
| §7 | No new storage | Task 1 discards; Task 4 stores only a summary in memory |
| §8 | Five states with copy and next attempt | Decisions 6; Tasks 3, 6, 7, 8 |
| §8 | Signed-out behaviour until observed; user-run check | Task 3 test; Task 14 Step 5 |
| §8 | No made-up zero; diagnostics contents | Task 8; Tasks 3, 4, 7 |
| §9 | Each automated case | all rows, `session` missing, only Fable, percent over 100, malformed, unknown, null `rate_limits`, no report (Task 1); timeout, oversized, non-zero, CLI missing (Tasks 2, 3); interval, backoff, single run, manual join, periodic run (Tasks 6, 7); freshness boundary and label across a refresh (Task 8); no shell, argv, environment (Tasks 2, 12); source order, last known (Task 8); no secret in logs (Tasks 1, 3, 7, 9, 12); no Keychain or endpoint (Task 12) |
| §9 | Real-machine acceptance, including the cost of up to 288 runs a day and label stability | Task 14 Steps 5-7, user-run |
| §10 | Each listed document, dated notes | Task 13 |
| §11 | Not tagged; new plan and notes; release gate; fallback | Task 13 notes and plan amendment; HANDOFF; Task 14 Step 8. The fallback (status line, last known, usage link) needs no code: it is what the app shows when `/usage` is not run, and removing the run is a later decision |
| §12 | Known limits stated, including usage outside Claude Code within about 15 minutes and up to 288 runs a day | `docs/providers/claude.md`, README, release notes in Task 13 |

**Placeholder scan.** The only value left open is the counts in the Task 14 Step 3 line, printed by that run. Test-file edits by script name each test.

**Type consistency, checked across tasks.** `ClaudeUsageReportProvider::with_parts(locator, environment, limits, control, run_id)`; `run_usage_probe(executable, environment, limits, control, run_id)`; `ClaudeUsageReportRun { result, summary }`; `collect_quota_with_providers(codex, cursor)` after Task 9; `QuotaRefreshIntent.claudeUsageReport(runID:)`; `QuotaRepository.cancelClaudeUsageReport(through:)`; `RustBridge.claudeUsageReportEnvelope(runID:)`; `ClaudeUsageProbeSchedule.periodicInterval`, `request(_:now:inFlight:)`, `dueTrigger(resetTimes:now:inFlight:)`, `recordFailure(trigger:at:retriesWhenBackoffEnds:)`; `ClaudeQuotaFailureReason.init(errorCode:associatedOrigin:)` until Task 11, then `init(errorCode:)`, with the one test call updated by the Task 11 script.
