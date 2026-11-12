# Claude Usage Probe Cadence and Deadline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop a change in Claude Code's local usage records from starting a `claude -p /usage` run, and give a run 60 seconds instead of 30, as approved in the 2026-11-12 design.

**Architecture:** Both changes are a removal and a constant inside existing units. `RefreshCoordinator` loses its usage-total comparison and `QuotaRefreshTrigger` loses the `usageRecordsChanged` case, so no code path can start a run from a usage refresh. `ClaudeUsageProbeSchedule` keeps its behaviour, and its 15-minute periodic run becomes the regular cadence. The deadline is the default of `UsageProbeLimits` in `needlbar-quota`; every comment, guard test and document that states it, or the bound derived from it (17:01, 1,021 seconds), follows.

**Tech Stack:** Rust 2021 (tokio process), Swift 6 / Swift Testing, the C header in `Sources/CNeedlbar`, macOS 14+ arm64.

## Global Constraints

Authoritative spec: `docs/superpowers/specs/2026-11-12-claude-usage-probe-cadence-design.md`. Copied from it verbatim:

- Status: "It authorizes an implementation plan only. Implementation, merge, installation, tag, and release each still need the user's separate request."
- Scope: "When Needlbar starts `claude -p /usage` and how long a run may take." and "The command, its arguments and environment, parsing, failure states, the status-line source, and the 20-minute freshness window are unchanged."
- Decision 1: "**A change in Claude Code's local usage records no longer starts a run.** The periodic run keeps readings current every 15 minutes, during use and in quiet periods alike."
- Decision 2: "**The run deadline is 60 seconds**, up from 30."
- App start: "Unchanged: a run starts at once."
- **Check now**: "Unchanged: starts at once, or joins the run in flight."
- Passing a displayed window's `resets_at`: "Unchanged: due on the next once-a-minute check once 5 minutes have passed since the last start."
- Retry after an automatic failure: "Unchanged: backoff of 5, 10, 20, then 30 minutes. A failure because Claude Code is not installed still does not retry when backoff ends; it waits for the next trigger, which is now the periodic run, a reset, **Check now** or app start."
- 15 minutes since the last start (periodic): "Unchanged."
- Change in Claude Code's local usage records: "**Removed.**"
- "The 5-minute minimum interval, single flight, the once-a-minute trigger check, and the rule that opening the dashboard, waking the Mac or regaining a connection starts no run all stay."
- "The pending-request path in `ClaudeUsageProbeSchedule` stays on purpose. After this change only an app start refused because an older run is still in flight uses it."
- "Needlbar still reads Claude Code's local usage records for token totals and costs; only the link from a change in them to a `/usage` run is removed."
- Age of a reading: "at most about 17 minutes before the next one lands: 15 minutes, plus up to one 60-second check, plus a run of up to 60 seconds and the stop grace (1,021 seconds). That is under the 20-minute freshness window by 2 minutes 59 seconds, by design."
- "A timeout stays an automatic failure with backoff. The 1 MiB output cap, the 0.5-second stop grace, the process-group kill after any exit, and stopping a run when the app quits are unchanged."
- `QuotaRefreshActivity.swift`: "remove the `usageRecordsChanged` trigger, which no longer has a caller. Nothing parses its log name, it is not stored, and it does not cross the Rust bridge. Removing it makes the absence of a usage-record run a compile-time fact."
- `ClaudeUsageProbeSchedule.swift`: "unchanged in behaviour; its comment on the refused request no longer names a usage change."
- New test: "a change in Claude usage totals starts no `/usage` run. The test changes the total once within 5 minutes of the startup run and once after 5 minutes, then expects only `[.startup, .periodic]`, with the second run starting 900 seconds after the first."
- Schedule tests "that used the removed trigger use `.startup` where they go through `request()`, and `.periodic` where they record a failure."
- "the freshness bound of 991 seconds (900 + 60 + 31) becomes 1,021 (900 + 60 + 61), and the "a 30-second run" message is updated"
- "the not-installed test uses periodic runs: failures at 0, 900 and 1,800 seconds, then the 20-minute backoff holds the periodic run due at 2,700 seconds until 3,000."
- Freshness guard: "uses 60 + 1 seconds and still holds, 1,021 under 1,200."
- "**Rust:** a test fixes the default deadline at 60 seconds."
- Documentation: "Dated notes or edits, each saying what changed and why"
- "No in-app text mentions the cadence or the deadline."
- "**Revisit** if runs approach 60 seconds, rather than raising the deadline again, or if a later CLI version changes the cost."

Repository constraints:

- Implementers never run `claude`; never read `~/.claude/.credentials.json`, `~/.claude.json`, Keychain items or cookies; never do anything that can change Claude Code's login state; never launch, kill or install any Needlbar app (no `make smoke`, nothing copied into `/Applications`); never push, merge, tag or start a release. This plan ends with three local commits on `claude/claude-usage-probe-cadence`.
- Tests never start the real `claude`. Rust process tests use the fake script from `fake_claude` in `crates/needlbar-quota/tests/claude_usage_probe.rs:21`. Swift tests use the fakes in `ClaudeUsageProbeCoordinatorTests.swift` and a manual clock.
- Never run `cargo fmt --all`: it reformats the vendored `vendor/tokscale-core` submodule. Check formatting only with `rustfmt --check --edition 2021 <files>`, which writes nothing.
- Bare `swift test` cannot link, because the tests need the bridge built with its test feature. Use `make swift-test SWIFT_TEST_FILTER=<name>` (`Makefile:9-53`). It builds that bridge, cleans the Swift build, runs the tests, then restores the normal bridge and cleans again, so each run takes about five minutes. Give it a timeout of at least ten minutes and let it finish; do not interrupt it.
- CI builds with Xcode 16.2 and Swift 6.0, which is stricter than the local Swift 6.4 in places (for example, an implicit `switch` return is valid only as the sole expression of a body). Use the code in this plan as written and add no newer-only syntax.
- In `README.md`, `0.3.15` may appear only inside the section `### Claude quota from the Claude Code usage report (v0.3.15 prepared)`, and that section may gain no `### ` heading, because the fixture at `scripts/tests/notarize-app-tests.sh:2239-2255` removes the section up to the next `### ` and aborts on any other `0.3.15`.
- New `docs/STATUS.md` text repeats no run ID, asset ID, release commit hash, `releases/tag/`, or `report 0.3.`, because the decoys at `scripts/tests/notarize-app-tests.sh:2207-2229` rewrite the first occurrence. Docs say prepared, not released.
- Stage only the files each commit step lists. Never `git add -A` or `git add .`: `.superpowers/brainstorm/` is untracked and stays out.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Commands run from the repository root after `export PATH="$HOME/.cargo/bin:$PATH" MACOSX_DEPLOYMENT_TARGET=14.0`. `rg` and the `make` targets that use it need `PATH` prefixed with `/Users/taejunoh/.codex/plugins/.plugin-appserver/codex-cli/codex-path` on the maintainer's Mac.
- Line numbers are from commit `fd021c8`. Once an earlier step shifts a file, find the place by the quoted text. Every quoted "replace" text occurs exactly once in its file.

---

## Decisions Settled From The Code

### 1. What starts a run today, and what goes

| Place | Today | Change |
|---|---|---|
| `RefreshCoordinator.start()`, `RefreshCoordinator.swift:198` | `requestClaudeUsageProbe(trigger: .startup)` | None |
| `RefreshCoordinator.manualRefresh()`, `:257` | `requestClaudeUsageProbe(trigger: .manual)` | None |
| `evaluateClaudeUsageProbeTriggers`, `:505-517`, every 60 s | Starts `claudeUsageSchedule.dueTrigger(...)`: a pending request, `.windowReset`, `.backoffRetry` or `.periodic` | None |
| `finishClaudeUsageProbe`, `:556-561` | Starts a pending request when a run ends | None. After this change only a refused `.startup` can be pending |
| `noteClaudeUsageRecords`, `:588-595`, called from `finishUsageRefresh` at `:669-672` | Compares the Claude total of each usage refresh with `lastClaudeUsageTotalTokens` (`:48`, reset at `:187`) and requests `.usageRecordsChanged` | Removed, with the field, its reset, the call, and the comment and generation guard at `:669-671` that exist only for the call (Task 2) |
| `QuotaRefreshTrigger.usageRecordsChanged`, `QuotaRefreshActivity.swift:52` | A case with one producer, above | Removed (Task 2). Its only other uses are the exhaustive `switch` at `RefreshCoordinator.swift:409` and tests |
| `UsageProbeLimits::default`, `claude_usage_probe.rs:48-55` | `deadline: Duration::from_secs(30)` | 60 (Task 1) |

The trigger's raw value reaches only the unified log (`QuotaRefreshDiagnosticsReporter.swift:45`, `trigger=\(event.trigger.rawValue)`). No Swift or Rust code parses it, stores it or sends it over the bridge, which matches the spec. The usage refresh itself is untouched: `store.applyUsage` still receives the Claude totals.

`ClaudeUsageProbeSchedule.request` treats every non-manual trigger alike (`ClaudeUsageProbeSchedule.swift:24-31`), so replacing `.usageRecordsChanged` with `.startup` in the schedule tests keeps what each test proves.

### 2. Two code tasks, split at the deadline

Task 1 is the deadline and everything that states it. Task 2 is the trigger. A reviewer can accept one and reject the other, and each ends with its own test run. The spec's test list puts the 991-second bound and the "30-second run" message beside the coordinator tests; both come from the deadline, so they go in Task 1. Both tasks edit `ClaudeUsageProbeCoordinatorTests.swift`, in different tests.

### 3. Test mechanics

- **What can fail first.** The Rust default test fails on 30 seconds. The new coordinator test fails on today's code, because the pending usage change starts a run at 300 s. Removing the enum case is checked by the compiler. The two bound checks (1,021 seconds and `60 + 1`) pass before and after, because 1,021 is still under 1,200; they are guards that must state the new number, and Task 1 says so instead of pretending a failure.
- **Filters.** `SWIFT_TEST_FILTER=ClaudeUsageProbe` runs `ClaudeUsageProbeCoordinatorTests` and `ClaudeUsageProbeSchedule` (48 tests today, 47 once Task 2 Step 1 turns two tests into one) plus the one-test `ClaudeUsageProbeSwitch` suite of the app target. `SWIFT_TEST_FILTER=ClaudeUsage` also runs `ClaudeUsageFreshness`, the reason and source-contract suites, and the app target's other matching suites: today 68 tests in 5 suites and 16 tests in 4 suites. Each run prints one `Test run with` line per test target. The filter is passed unquoted to the shell, so it holds no `|` or parentheses.
- **Coordinator harness.** `Harness.advance(minutes:)` moves a manual clock one minute at a time and waits for all three timer loops to sleep again (`ClaudeUsageProbeCoordinatorTests.swift:645-651`), so a run decision for that minute has been taken before the next line. `settle(watchingFor:)` is for negative checks only (`TestWaiting.swift:63`). A failed run also emits a `.completed` event, so `waitUntilCompletedRuns` counts it.
- **Not-installed timeline, checked against `ClaudeUsageProbeSchedule`.** Failure at 0 backs off to 300 with no retry; the periodic run is due at 900. Failure at 900 backs off 10 minutes to 1,500; the periodic run is due at 1,800. Failure at 1,800 backs off 20 minutes to 3,000, which holds the periodic run due at 2,700. At 3,000 the remaining backoff is 0, so the run starts.
- **No test relies on the default deadline to end a hung fake.** Every Rust process test that waits on a slow script sets its own deadline (`claude_usage_probe.rs` tests use `limits(...)`; `claude_usage_provider.rs:181-187` uses 1 second), so the suite does not get slower.
- **Verified while writing this plan.** Every edit below was applied, in order, to scratch copies of the repository at `fd021c8`. There, Task 1 Step 2 and Task 2 Step 2 failed as described, Task 1 Step 8 and Task 2 Step 7 passed with the counts given, and the final tree passed `make test`, `cargo test --workspace` and CI's `cargo clippy` command. The new coordinator tests passed 15 runs in a row. The repository itself was not changed. CI's Xcode 16.2 was not available locally.

### 4. Where this plan goes beyond the spec's lists

The spec's §7 and §9 name the places to change. The code has a few more, and the plan handles them as follows.

1. **C header.** `Sources/CNeedlbar/include/needlbar.h:17-18` says the usage call "Blocks for at most about 31 seconds". The spec's comment list omits it. Task 1 makes it 61 seconds.
2. **Periodic interval comment.** `ClaudeUsageProbeSchedule.swift:14` says the periodic run "Keeps readings current during quiet periods". It is now the cadence during use too. Task 2 updates the comment; the value is untouched.
3. **Unused test helper.** `ScriptedUsageRepository.waitUntilCallCount` in the coordinator tests is used only by a test this plan removes. Task 2 removes it with its counter.
4. **A 288 that stays.** The 2026-11-03 spec's working-directory limit says "up to 288 new directories a day". The new spec names only the §9 and §12 figures. That sentence records why a per-run directory was rejected, so it stays as written.
5. **Release notes.** `docs/releases/v0.3.15.md` is the body of a release that was never published (`.github/workflows/release.yml:101`). It gets plain edits to the final behaviour, with the reason in the text and no dated history, which would read oddly in a public release body. STATUS and the commit carry the date.
6. **README, full day.** The spec says to change "the sentence saying a full day on a Developer ID build has not been observed" without saying to what. The two Developer ID logs in spec §1 cover about 18 hours each (18 h 36 min and 17 h 41 min), so the sentence now says that, and that a full day has still not been observed.
7. **A later timeout.** While this plan was written, the local unified log showed a second `usageProbeTimedOut` (30,552 ms) at 17:52 local on 2026-11-12, after the window the spec read (to 17:12). The documents below keep the spec's numbers, each tied to the date its log was read. It is reported with this plan and changes no decision.
8. **Left alone.** `claude_usage_probe.rs` says of the kill after exit that "This job repeats every few minutes". That is still true at 15 minutes.

### 5. Documentation contracts

- `make notarize-test` reads `README.md` and `docs/STATUS.md` (`scripts/tests/notarize-app-tests.sh`). It requires the README heading named in Global Constraints and the v0.3.14 facts, and it checks only that `docs/releases/v0.3.15.md` exists. None of the text this plan replaces is asserted there. Task 3 runs it inside `make test`.
- `Tests/NeedlbarCoreTests/ClaudeUsageReportSourceContractTests.swift` and `crates/needlbar-quota/tests/claude_source_contract.rs` scan sources for retired names and for raw-output paths. The comments this plan adds contain none of their forbidden strings.
- The 2026-11-03 spec and plan are amended with dated notes in the style they already use (`**Amended ...:**` in the spec header, `*Amended ...:*` inline, `> **Amendment — ...:**` in the plan).

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `crates/needlbar-quota/src/providers/claude_usage_probe.rs` | Runs `/usage` under fixed limits | Default deadline 60 s, with a comment (Task 1) |
| `crates/needlbar-quota/tests/claude_usage_probe.rs` | Probe process tests | New default-limits test (Task 1) |
| `crates/needlbar-bridge/src/quota.rs` | Bridge collections | Two comments (Task 1) |
| `Sources/CNeedlbar/include/needlbar.h` | C declarations | One comment (Task 1) |
| `Sources/NeedlbarCore/Presentation/ClaudeQuotaPresentationSelector.swift` | Freshness of Claude readings | One comment (Task 1) |
| `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift` | Starts and applies refreshes | One comment (Task 1); usage-change detection removed (Task 2) |
| `Sources/NeedlbarCore/Refresh/QuotaRefreshActivity.swift` | Trigger and attempt types | `usageRecordsChanged` removed (Task 2) |
| `Sources/NeedlbarCore/Refresh/ClaudeUsageProbeSchedule.swift` | When a run may start | Two comments (Task 2) |
| `Tests/NeedlbarCoreTests/ClaudeUsageFreshnessTests.swift` | Freshness guard | `60 + 1` (Task 1) |
| `Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift` | Coordinator behaviour | Bound and message (Task 1); new and rewritten tests (Task 2) |
| `Tests/NeedlbarCoreTests/ClaudeUsageProbeScheduleTests.swift` | Schedule behaviour | Removed trigger replaced (Task 2) |
| `docs/superpowers/specs/2026-11-03-claude-usage-report-source-design.md`, `docs/superpowers/plans/2026-11-03-claude-usage-report-source.md` | Earlier design and plan | Dated amendments (Task 3) |
| `README.md`, `docs/providers/claude.md`, `docs/privacy.md`, `docs/architecture.md`, `docs/HANDOFF.md`, `docs/releases/v0.3.15.md`, `docs/STATUS.md` | Current descriptions and records | Updated (Task 3) |

No file is created.

---

### Task 1: The 60-second deadline and every place that states it

**Files:**
- Modify: `crates/needlbar-quota/src/providers/claude_usage_probe.rs:48-55`
- Modify: `crates/needlbar-bridge/src/quota.rs:31,77`
- Modify: `Sources/CNeedlbar/include/needlbar.h:17-18`
- Modify: `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift:519`
- Modify: `Sources/NeedlbarCore/Presentation/ClaudeQuotaPresentationSelector.swift:33`
- Test: `crates/needlbar-quota/tests/claude_usage_probe.rs:90` (new test before the first existing one)
- Test: `Tests/NeedlbarCoreTests/ClaudeUsageFreshnessTests.swift:28`
- Test: `Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift:19,197-199`

**Interfaces:**
- Consumes: nothing from another task.
- Produces: `UsageProbeLimits::default().deadline == Duration::from_secs(60)` (`max_stdout_bytes` stays `1024 * 1024`). The slowest periodic refresh ends 900 + 60 + 61 = 1,021 seconds (17:01) after the last start, 2 minutes 59 seconds inside `ClaudeQuotaPresentationSelector.recentDirectInterval` (1,200 seconds). Task 3's documents use these numbers.

- [ ] **Step 1: Write the failing test**

In `crates/needlbar-quota/tests/claude_usage_probe.rs`, replace

```rust
#[test]
fn locator_takes_the_first_executable_regular_file_in_order() {
```

with

```rust
#[test]
fn the_default_limits_are_sixty_seconds_and_one_mebibyte() {
    let limits = UsageProbeLimits::default();
    assert_eq!(limits.deadline, Duration::from_secs(60));
    assert_eq!(limits.max_stdout_bytes, 1024 * 1024);
}

#[test]
fn locator_takes_the_first_executable_regular_file_in_order() {
```

`UsageProbeLimits` and `Duration` are already imported at the top of that file.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cargo test -p needlbar-quota --test claude_usage_probe the_default_limits`
Expected: FAIL. The assertion output shows `left: 30s` and `right: 60s`, and the run ends with `test result: FAILED. 0 passed; 1 failed; 0 ignored; 0 measured; 17 filtered out`.

- [ ] **Step 3: Change the default**

In `crates/needlbar-quota/src/providers/claude_usage_probe.rs`, replace

```rust
impl Default for UsageProbeLimits {
    fn default() -> Self {
        Self {
            deadline: Duration::from_secs(30),
```

with

```rust
impl Default for UsageProbeLimits {
    /// The deadline is 60 seconds (30 before 2026-11-12). `/usage` scans the
    /// recent session transcripts, so a run takes longer as they grow, and a run
    /// stopped at the deadline has paid its whole cost and returns nothing.
    fn default() -> Self {
        Self {
            deadline: Duration::from_secs(60),
```

- [ ] **Step 4: Run the crate's tests to verify they pass**

Run: `cargo test -p needlbar-quota`
Expected: every `test result:` line says `ok`, and the one for `tests/claude_usage_probe.rs` says `18 passed; 0 failed`. The source-contract tests (`tests/claude_source_contract.rs`, `4 passed`) accept the new comment.

- [ ] **Step 5: Update the comments that state the deadline or its bound**

In `crates/needlbar-bridge/src/quota.rs`, replace

```rust
/// The Claude quota run. A dedicated collection, so a run of up to 30 seconds
```

with

```rust
/// The Claude quota run. A dedicated collection, so a run of up to 60 seconds
```

In `crates/needlbar-bridge/src/quota.rs`, replace

```rust
/// slot, so a run of up to 30 seconds cannot hold these two.
```

with

```rust
/// slot, so a run of up to 60 seconds cannot hold these two.
```

In `Sources/CNeedlbar/include/needlbar.h`, replace

```c
// 31 seconds. Ownership matches needlbar_quota_snapshot_json. run_id is at
```

with

```c
// 61 seconds. Ownership matches needlbar_quota_snapshot_json. run_id is at
```

In `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`, replace

```swift
    /// A run can take 30 seconds, so it uses a dispatch thread rather than a
```

with

```swift
    /// A run can take 60 seconds, so it uses a dispatch thread rather than a
```

In `Sources/NeedlbarCore/Presentation/ClaudeQuotaPresentationSelector.swift`, replace

```swift
    /// Longer than the slowest periodic refresh, which can finish 16:31 after the
```

with

```swift
    /// Longer than the slowest periodic refresh, which can finish 17:01 after the
```

- [ ] **Step 6: Update the Swift guards that state the deadline or its bound**

These three edits have no failing phase: 1,021 seconds is still under the 1,200-second window, so the checks pass before and after. They exist to hold the window above the slowest refresh, so they must state the new number.

In `Tests/NeedlbarCoreTests/ClaudeUsageFreshnessTests.swift`, replace

```swift
        let slowestRun: TimeInterval = 30 + 1
```

with

```swift
        let slowestRun: TimeInterval = 60 + 1
```

In `Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift`, replace

```swift
        #expect(harness.probe.everyCallRanOutsideAnyTask, "a 30-second run must not occupy a cooperative thread")
```

with

```swift
        #expect(harness.probe.everyCallRanOutsideAnyTask, "a 60-second run must not occupy a cooperative thread")
```

In `Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift`, replace

```swift
        // The slowest refresh finishes 991 s after the last start.
        let beforeRefresh = ClaudeQuotaPresentationSelector.select(
            snapshot: await harness.store.snapshot(for: .claude), now: Self.start.addingTimeInterval(991)).sevenDay
```

with

```swift
        // The slowest refresh finishes 1,021 s after the last start: 900 + 60 + 61.
        let beforeRefresh = ClaudeQuotaPresentationSelector.select(
            snapshot: await harness.store.snapshot(for: .claude), now: Self.start.addingTimeInterval(1_021)).sevenDay
```

- [ ] **Step 7: Check Rust formatting without writing**

Run: `rustfmt --check --edition 2021 crates/needlbar-quota/src/providers/claude_usage_probe.rs crates/needlbar-quota/tests/claude_usage_probe.rs crates/needlbar-bridge/src/quota.rs; echo "rustfmt exit $?"`
Expected: no diff, and `rustfmt exit 0`.

- [ ] **Step 8: Run the Claude usage Swift tests**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeUsage`
Expected: `Test run with 16 tests in 4 suites passed` and `Test run with 68 tests in 5 suites passed`, including `theWindowOutlastsTheSlowestPeriodicRefresh()` and `aReadingStaysCurrentUntilThePeriodicRefreshReplacesIt()`, and make exits 0. This also compiles the changed header and Swift comments.

- [ ] **Step 9: Commit**

```bash
git add crates/needlbar-quota/src/providers/claude_usage_probe.rs \
  crates/needlbar-quota/tests/claude_usage_probe.rs \
  crates/needlbar-bridge/src/quota.rs \
  Sources/CNeedlbar/include/needlbar.h \
  Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift \
  Sources/NeedlbarCore/Presentation/ClaudeQuotaPresentationSelector.swift \
  Tests/NeedlbarCoreTests/ClaudeUsageFreshnessTests.swift \
  Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift
git commit -m "fix(claude): give a /usage run 60 seconds" \
  -m "Runs reached 23 seconds and one was stopped at the 30-second deadline, after paying its whole cost. The slowest periodic refresh now ends 17:01 after the last start, still inside the 20-minute freshness window." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: A change in usage records starts no run

**Files:**
- Modify: `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift:22-23,48,187,409,588-595,669-672`
- Modify: `Sources/NeedlbarCore/Refresh/QuotaRefreshActivity.swift:50-53`
- Modify: `Sources/NeedlbarCore/Refresh/ClaudeUsageProbeSchedule.swift:8-9,14`
- Test: `Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift:84-118,250-279,772-793`
- Test: `Tests/NeedlbarCoreTests/ClaudeUsageProbeScheduleTests.swift:16-22,57,107-108,134,159-160`

**Interfaces:**
- Consumes: nothing from Task 1. The two tasks touch different tests in `ClaudeUsageProbeCoordinatorTests.swift`.
- Produces: `public enum QuotaRefreshTrigger: String, Sendable, Equatable` with exactly the cases `startup, scheduled, wake, connectivity, popover, manual, windowReset, backoffRetry, periodic`. A Claude run can start only as `startup`, `manual`, `windowReset`, `backoffRetry` or `periodic`, which are the names Task 3's documents and the manual check use. `ClaudeUsageProbeSchedule`'s API and behaviour are unchanged. `RefreshCoordinator` has no `noteClaudeUsageRecords` and no `lastClaudeUsageTotalTokens`.

- [ ] **Step 1: Write the failing test and rewrite the not-installed test**

Two tests expect a run after a usage-record change: `aChangedUsageTotalStartsARunButTheFirstObservationDoesNot` and `aChangeInsideTheIntervalRunsWhenTheIntervalEnds` (lines 84-118). One new test replaces both.

In `Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift`, replace everything from the line

```swift
    @Test func aChangedUsageTotalStartsARunButTheFirstObservationDoesNot() async throws {
```

up to, but not including, the line

```swift
    @Test func passingADisplayedResetStartsOneRun() async throws {
```

with this, keeping one blank line before that line

```swift
    @Test func aChangedUsageTotalStartsNoRun() async throws {
        let harness = Harness(claudeTotal: 100)
        await harness.startedAndIdle()
        await harness.waitUntilUsageApplied(100)

        // A change inside five minutes of the startup run.
        harness.usage.setClaudeTotal(250)
        await harness.coordinator.requestUsageRefresh()
        await harness.waitUntilUsageApplied(250)

        // A change more than five minutes after it.
        await harness.advance(minutes: 6)
        harness.usage.setClaudeTotal(400)
        await harness.coordinator.requestUsageRefresh()
        await harness.waitUntilUsageApplied(400)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1, "a change in usage records starts no run")

        // Only the periodic run follows, 15 minutes after the startup run.
        await harness.advance(minutes: 8)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1)
        await harness.advance(minutes: 1)
        await harness.probe.waitUntilCallCount(2)
        await harness.waitUntilCompletedRuns(2)
        #expect(harness.probe.startTimes.map { $0.timeIntervalSince(Self.start) } == [0, 900])
        #expect(harness.probe.triggersSeen(in: harness.events) == [.startup, .periodic])
        await harness.coordinator.stop()
    }

```

The not-installed test (lines 250-279) used a usage-record change as its "real trigger". It now uses periodic runs only.

In `Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift`, replace everything from the line

```swift
    @Test func notInstalledRetriesOnlyOnATriggerAndUnderBackoff() async throws {
```

up to, but not including, the line

```swift
    @Test func aFailedPeriodicRunKeepsTheReadingAsLastKnownAndBacksOff() async throws {
```

with this, keeping one blank line before that line

```swift
    @Test func notInstalledRetriesOnlyOnThePeriodicRunAndUnderBackoff() async throws {
        let harness = Harness()
        for _ in 0 ..< 3 { harness.probe.script(.result(claudeError("notInstalled"))) }
        await harness.startedAndIdle()
        // The five-minute backoff ends at 300 s and nothing retries by itself.
        await harness.advance(minutes: 14)
        await settle(watchingFor: { harness.probe.callCount > 1 })
        #expect(harness.probe.callCount == 1, "notInstalled does not retry when backoff ends")
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

```

- [ ] **Step 2: Run the tests to verify the new one fails**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeUsageProbe`
Expected: FAIL in `aChangedUsageTotalStartsNoRun()` only, with 4 issues: `Expectation failed: harness.probe.callCount == 1` twice, then the `startTimes` and `triggersSeen` expectations. The app target's line says `Test run with 1 test in 1 suite passed`; the core target's says `Test run with 47 tests in 2 suites failed` and `with 4 issues`; make ends with `make: *** [swift-test] Error 1`. `notInstalledRetriesOnlyOnThePeriodicRunAndUnderBackoff()` passes already, because it no longer changes the usage total.

- [ ] **Step 3: Remove the usage-change detection from `RefreshCoordinator`**

In `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`, replace

```swift
    private var claudeUsageTickTask: Task<Void, Never>?
    private var lastClaudeUsageTotalTokens: UInt64?
```

with

```swift
    private var claudeUsageTickTask: Task<Void, Never>?
```

In `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`, replace

```swift
        claudeUsageSchedule = ClaudeUsageProbeSchedule()
        lastClaudeUsageTotalTokens = nil
```

with

```swift
        claudeUsageSchedule = ClaudeUsageProbeSchedule()
```

In `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`, delete this block, with the blank line after it

```swift
    /// Compares the Claude total from the existing usage refresh. The first
    /// observation after start only sets the baseline, because start runs anyway.
    private func noteClaudeUsageRecords(_ total: UInt64?) {
        guard let total else { return }
        defer { lastClaudeUsageTotalTokens = total }
        guard let previous = lastClaudeUsageTotalTokens, previous != total else { return }
        requestClaudeUsageProbe(trigger: .usageRecordsChanged)
    }

```

In `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`, replace

```swift
                await store.markUsageFailure(for: provider, status: status(for: error), at: clock.now)
            }
            // The last store call suspended: a stop and start in that gap must not set
            // the new generation's baseline from this old result.
            guard generation == runGeneration, applyResult else { return }
            noteClaudeUsageRecords(refresh.snapshots[.claude]?.totalTokens)
        case .failure(let error):
```

with

```swift
                await store.markUsageFailure(for: provider, status: status(for: error), at: clock.now)
            }
        case .failure(let error):
```

The `.success` case now ends after the errors loop. `refresh` is still used by both loops above.

- [ ] **Step 4: Remove the trigger that has no caller, and correct the comments**

In `Sources/NeedlbarCore/Refresh/QuotaRefreshActivity.swift`, replace

```swift
    case usageRecordsChanged, windowReset, backoffRetry, periodic
```

with

```swift
    case windowReset, backoffRetry, periodic
```

In `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`, replace

```swift
        case .startup, .manual, .popover, .usageRecordsChanged, .windowReset, .backoffRetry, .periodic:
```

with

```swift
        case .startup, .manual, .popover, .windowReset, .backoffRetry, .periodic:
```

In `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`, replace

```swift
    /// How often a passed reset, a deferred usage change, a backoff retry and the
    /// periodic run are checked. It reads only actor and store state.
```

with

```swift
    /// How often a deferred startup run, a passed reset, a backoff retry and the
    /// periodic run are checked. It reads only actor and store state.
```

In `Sources/NeedlbarCore/Refresh/ClaudeUsageProbeSchedule.swift`, replace

```swift
        /// Refused or joined. A refused startup or usage change stays in
        /// `pendingTrigger`; a manual request joins the run in flight.
```

with

```swift
        /// Refused or joined. A refused startup request stays in
        /// `pendingTrigger`; a manual request joins the run in flight.
```

In `Sources/NeedlbarCore/Refresh/ClaudeUsageProbeSchedule.swift`, replace

```swift
    /// Keeps readings current during quiet periods (user decision, 2026-11-03).
```

with

```swift
    /// Keeps readings current, during use and in quiet periods alike (user
    /// decisions, 2026-11-03 and 2026-11-12).
```

- [ ] **Step 5: Replace the removed trigger in the schedule tests, and drop the unused test helper**

The schedule treats every non-manual trigger alike, so `.startup` stands in where a test calls `request()` and `.periodic` where it records a failure.

In `Tests/NeedlbarCoreTests/ClaudeUsageProbeScheduleTests.swift`, replace

```swift
    @Test func automaticRunsAreAtLeastFiveMinutesApartAndARefusedChangeStaysPending() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.recordStart(at: start)
        #expect(schedule.request(.usageRecordsChanged, now: at(299), inFlight: false) == .none)
        #expect(schedule.pendingTrigger == .usageRecordsChanged)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(299), inFlight: false) == nil)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(300), inFlight: false) == .usageRecordsChanged)
```

with

```swift
    @Test func automaticRunsAreAtLeastFiveMinutesApartAndARefusedRequestStaysPending() {
        var schedule = ClaudeUsageProbeSchedule()
        schedule.recordStart(at: start)
        #expect(schedule.request(.startup, now: at(299), inFlight: false) == .none)
        #expect(schedule.pendingTrigger == .startup)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(299), inFlight: false) == nil)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(300), inFlight: false) == .startup)
```

In `Tests/NeedlbarCoreTests/ClaudeUsageProbeScheduleTests.swift`, replace

```swift
        schedule.recordFailure(trigger: .usageRecordsChanged, at: at(clock), retriesWhenBackoffEnds: true)
```

with

```swift
        schedule.recordFailure(trigger: .periodic, at: at(clock), retriesWhenBackoffEnds: true)
```

In `Tests/NeedlbarCoreTests/ClaudeUsageProbeScheduleTests.swift`, replace

```swift
        #expect(schedule.request(.usageRecordsChanged, now: at(299), inFlight: false) == .none)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(300), inFlight: false) == .usageRecordsChanged)
    }
```

with

```swift
        #expect(schedule.request(.startup, now: at(299), inFlight: false) == .none)
        #expect(schedule.dueTrigger(resetTimes: [], now: at(300), inFlight: false) == .startup)
    }
```

In `Tests/NeedlbarCoreTests/ClaudeUsageProbeScheduleTests.swift`, replace

```swift
        #expect(schedule.request(.usageRecordsChanged, now: at(-86_400), inFlight: false) == .start)
```

with

```swift
        #expect(schedule.request(.startup, now: at(-86_400), inFlight: false) == .start)
```

In `Tests/NeedlbarCoreTests/ClaudeUsageProbeScheduleTests.swift`, replace

```swift
        _ = pending.request(.usageRecordsChanged, now: at(1), inFlight: false)
        #expect(pending.dueTrigger(resetTimes: [], now: at(900), inFlight: false) == .usageRecordsChanged)
```

with

```swift
        _ = pending.request(.startup, now: at(1), inFlight: false)
        #expect(pending.dueTrigger(resetTimes: [], now: at(900), inFlight: false) == .startup)
```

`waitUntilCallCount` on the usage fake was used only by a test Step 1 removed.

In `Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift`, replace

```swift
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
```

with

```swift
private final class ScriptedUsageRepository: UsageRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var total: UInt64

    init(claudeTotal: UInt64) { total = claudeTotal }

    func setClaudeTotal(_ value: UInt64) { lock.withLock { total = value } }

    func refresh() throws -> UsageRefreshResult {
        let current = lock.withLock { total }
        return .init(snapshots: [.claude: usage(total: current)], errors: [:])
    }
}
```

- [ ] **Step 6: Confirm nothing names the removed code**

Run: `rg -n "usageRecordsChanged|noteClaudeUsageRecords|lastClaudeUsageTotalTokens" Sources Tests crates WidgetExtension; echo "rg exit $?"`
Expected: no matches, and `rg exit 1`.

- [ ] **Step 7: Run the Claude usage Swift tests to verify they pass**

Run: `make swift-test SWIFT_TEST_FILTER=ClaudeUsage`
Expected: `Test run with 16 tests in 4 suites passed` and `Test run with 67 tests in 5 suites passed` (one fewer than before: two tests became one), including `aChangedUsageTotalStartsNoRun()` and `notInstalledRetriesOnlyOnThePeriodicRunAndUnderBackoff()`, and make exits 0. The build shows no new warning in the files this task changed.

- [ ] **Step 8: Commit**

```bash
git add Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift \
  Sources/NeedlbarCore/Refresh/QuotaRefreshActivity.swift \
  Sources/NeedlbarCore/Refresh/ClaudeUsageProbeSchedule.swift \
  Tests/NeedlbarCoreTests/ClaudeUsageProbeCoordinatorTests.swift \
  Tests/NeedlbarCoreTests/ClaudeUsageProbeScheduleTests.swift
git commit -m "fix(claude): stop starting /usage runs on usage-record changes" \
  -m "Each run makes claude scan the last 7 days of transcripts, and during use these changes started one every 5 minutes. The periodic run now keeps readings current every 15 minutes, and the usageRecordsChanged trigger is gone, so no code path can start a run from a usage refresh." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Documentation and records

**Files:**
- Modify: `docs/superpowers/specs/2026-11-03-claude-usage-report-source-design.md:14-16,139-150,157-159,194,198-199,280,319-321,327`
- Modify: `docs/superpowers/plans/2026-11-03-claude-usage-report-source.md:25-26`
- Modify: `README.md:204-210,220-225`
- Modify: `docs/providers/claude.md:39,46-48,82-84`
- Modify: `docs/privacy.md:110-115`
- Modify: `docs/architecture.md:181-182`
- Modify: `docs/HANDOFF.md:3-4,157-160,163-164`
- Modify: `docs/releases/v0.3.15.md:3,4,9`
- Modify: `docs/STATUS.md:1-3`

**Interfaces:**
- Consumes: from Task 1, the 60-second deadline and the 1,021-second (17:01) bound with its 2 minute 59 second margin. From Task 2, the remaining trigger names `startup`, `manual`, `windowReset`, `backoffRetry` and `periodic`.
- Produces: documents only. Nothing later depends on them.

Every number below is from the spec or follows from it (Decisions 4.6). Automatic runs are "in practice 15 minutes apart", a day has "about 96" periodic runs, and a reading can be "about 17 minutes" old before the next one lands.

- [ ] **Step 1: Amend the 2026-11-03 design**

Add the header note after the last existing amendment:

In `docs/superpowers/specs/2026-11-03-claude-usage-report-source-design.md`, replace

```markdown
each run, not a new temporary folder per run (§6). The smoke script switches the probe off
(§6).
```

with

```markdown
each run, not a new temporary folder per run (§6). The smoke script switches the probe off
(§6).

**Amended 2026-11-12:** a change in Claude Code's local usage records no longer starts a run,
and the run deadline is 60 seconds, up from 30. Each `/usage` run scans the last 7 days of
Claude Code transcripts, so runs slowed to a median of about 8 seconds and one was stopped at
the deadline, while usage-record changes started a run every 5 minutes during use. The design
is `docs/superpowers/specs/2026-11-12-claude-usage-probe-cadence-design.md`; §6, §9 and §12
below carry the dated changes.
```

Remove the trigger from the list, and say so under the existing 2026-11-04 note:

In `docs/superpowers/specs/2026-11-03-claude-usage-report-source-design.md`, replace

```markdown
- manual refresh
- a change in Claude Code's local usage records
- passing the `resets_at` of a displayed window
```

with

```markdown
- manual refresh
- passing the `resets_at` of a displayed window
```

In `docs/superpowers/specs/2026-11-03-claude-usage-report-source-design.md`, replace

```markdown
*Amended 2026-11-04:* the manual refresh control is **Check now**, on the dashboard's Claude row and in Settings beside **View Claude usage**.
```

with

```markdown
*Amended 2026-11-04:* the manual refresh control is **Check now**, on the dashboard's Claude row and in Settings beside **View Claude usage**.

*Amended 2026-11-12:* a change in Claude Code's local usage records was a trigger until this
date and is removed. Each run scans the last 7 days of transcripts, and during use those
changes started a run every 5 minutes. The periodic run now keeps readings current during use
and in quiet periods alike, so automatic runs are in practice 15 minutes apart. The 5-minute
minimum stays and matters only after a passed reset or a failed run.
```

The freshness margin:

In `docs/superpowers/specs/2026-11-03-claude-usage-report-source-design.md`, replace

```markdown
refresh that is due at 15 minutes can finish about a minute and a half later, so a shorter
window would flip the label just before each refresh. A failed run shows **Last known** at
```

with

```markdown
refresh that is due at 15 minutes can finish about two minutes later (amended 2026-11-12, from
about a minute and a half: with the 60-second deadline the slowest refresh ends 17:01 after
the last start), so a shorter
window would flip the label just before each refresh. A failed run shows **Last known** at
```

The deadline, and the clause this amendment uses:

In `docs/superpowers/specs/2026-11-03-claude-usage-report-source-design.md`, replace

```markdown
- a 30-second deadline, then terminate the process group
```

with

```markdown
- a 60-second deadline, then terminate the process group (amended 2026-11-12: it was 30
  seconds)
```

In `docs/superpowers/specs/2026-11-03-claude-usage-report-source-design.md`, replace

```markdown
Acceptance measures the real duration. If it does not fit, the deadline changes in
this specification before release.
```

with

```markdown
Acceptance measures the real duration. If it does not fit, the deadline changes in
this specification before release. *Amended 2026-11-12:* this clause was used. Runs reached
23.1 seconds and one was stopped at 30 seconds, so the deadline is now 60 seconds.
```

The "288 a day" figures in §9 and §12, and the §12 item that said the cost was unmeasured:

In `docs/superpowers/specs/2026-11-03-claude-usage-report-source-design.md`, replace

```markdown
- Record the cost of up to 288 runs a day, and whether the label stays current across them.
```

with

```markdown
- Record the cost of about 96 runs a day, plus runs after resets and retries, and whether the
  label stays current across them (amended 2026-11-12: it was up to 288 runs a day while
  usage-record changes started runs).
```

In `docs/superpowers/specs/2026-11-03-claude-usage-report-source-design.md`, replace

```markdown
  the app is running and awake. This means about 96 runs a day from the periodic run alone, and up to 288 a day with other triggers, because runs are at least 5 minutes apart, whose memory and CPU cost
  is unmeasured.
```

with

```markdown
  the app is running and awake. This means about 96 runs a day from the periodic run, plus runs
  after resets and retries after failures. *Amended 2026-11-12:* it was up to 288 a day while
  usage-record changes started runs, and its cost is no longer unmeasured (see the amended
  item on duration below).
```

In `docs/superpowers/specs/2026-11-03-claude-usage-report-source-design.md`, replace

```markdown
- Duration, memory, and CPU under repeated runs have not been measured.
```

with

```markdown
- *Amended 2026-11-12:* this item said that duration, memory, and CPU under repeated runs had
  not been measured. Duration has been, and it grows with the user's Claude Code use: a median
  of 4.9 s on 2026-11-05 and 8.1 s on 2026-11-12, with one run stopped at 30 seconds. One run
  on 2026-11-05 took about 5.2 s of CPU and 454 MB of peak memory; CPU and memory were not
  measured again. `docs/STATUS.md` has the details under 2026-11-05 and 2026-11-12.
```

- [ ] **Step 2: Amend the 2026-11-03 plan**

One note at the top, after the two existing amendments. The task text below it stays as the record of what was first written.

In `docs/superpowers/plans/2026-11-03-claude-usage-report-source.md`, replace

```markdown
> `NEEDLBAR_DISABLE_CLAUDE_USAGE_PROBE=1`, which `AppDelegate` honours by passing no Claude usage
> repository, so a smoke launch never starts a real `claude`.
```

with

```markdown
> `NEEDLBAR_DISABLE_CLAUDE_USAGE_PROBE=1`, which `AppDelegate` honours by passing no Claude usage
> repository, so a smoke launch never starts a real `claude`.
>
> **Amendment — 2026-11-12:** a change in Claude Code's local usage records no longer starts a
> run, and the deadline is 60 seconds, because each `/usage` run scans the last 7 days of
> transcripts (`docs/superpowers/specs/2026-11-12-claude-usage-probe-cadence-design.md`, implemented
> through `docs/superpowers/plans/2026-11-12-claude-usage-probe-cadence.md`). These parts below are
> superseded and kept as the record of what was first written. In Global Constraints, the usage
> records trigger and the 30-second deadline. Decisions 2, which detects a change in the usage
> records, and with it `.usageRecordsChanged` and `noteClaudeUsageRecords` in Tasks 6 and 7.
> Decisions 3a: the slowest refresh now ends 17:01 after the last start, not 16:31, and the margin
> is 2:59, not 3:29. In the Task 14 acceptance checklist: the 30-second decision; the
> `trigger=usageRecordsChanged` item, which can no longer appear; and every "288 runs a day"
> figure, which is now about 96 a day plus runs after resets and retries. Automatic starts are
> still never under 5 minutes apart, and are in practice 15 minutes apart except after a reset or
> a failure.
```

- [ ] **Step 3: Update `README.md`**

Both edits are inside the `(v0.3.15 prepared)` section. They add no heading and no `0.3.15`.

In `README.md`, replace

```markdown
marked experimental. Runs happen at app start, on manual refresh (**Check now**, in the dashboard and in Settings), when Claude
Code's local usage records change, when a displayed window's reset passes, and
after 15 minutes without a run, at most once every 5 minutes. Opening the dashboard
alone starts none. A reading stays current for 20 minutes, and usage outside Claude
Code appears within about 15 minutes while the app is running and the Mac is awake.
That can mean about 96 runs a day from the periodic run alone, and up to 288 a day with other triggers, because runs are at least 5 minutes apart. A run is
limited to 30 seconds and 1 MiB of output, works in one fixed folder in the temporary directory that is emptied before each run,
```

with

```markdown
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
limited to 60 seconds (30 before 2026-11-12, when one run was stopped at that limit) and 1 MiB of output, works in one fixed folder in the temporary directory that is emptied before each run,
```

In `README.md`, replace

```markdown
access**, which an earlier prepared build had, is removed. On one Mac, a local
ad-hoc build ran for about 38 hours: all 125 runs in the retained 17 hours of logs
succeeded, with a median of about 4.9 s and a maximum of about 19.3 s, and no Keychain
prompt appeared. One `claude` run took about 5.2 s of CPU and 454 MB of peak memory.
Any rate limit on `/usage` has not been measured, and a full day on a Developer ID
build has not been observed. It is not part of any
```

with

```markdown
access**, which an earlier prepared build had, is removed. On one Mac, a local
ad-hoc build ran for about 38 hours to 2026-11-05: all 125 runs in the retained 17 hours of logs
succeeded, with a median of about 4.9 s and a maximum of about 19.3 s, and no Keychain
prompt appeared. One `claude` run then took about 5.2 s of CPU and 454 MB of peak memory.
Runs got slower afterwards. Logs from Developer ID builds on the same Mac showed a median of
about 6.2 s over 140 runs (read on 2026-11-09) and about 8.1 s over 104 runs (read on
2026-11-12), when the longest completed run took 23.1 s and one run was stopped at the
30-second limit. CPU and memory were not measured again. The cost grows with the amount of
recent Claude Code transcripts, which is why usage-record changes no longer start runs and the
limit is 60 seconds.
Any rate limit on `/usage` has not been measured. Each of those two logs covers about 18
hours, so a full day on a Developer ID build has still not been observed. It is not part of any
```

- [ ] **Step 4: Update `docs/providers/claude.md`**

In `docs/providers/claude.md`, replace

```markdown
  if the app already has it; 30 seconds, then the process group is terminated; 1 MiB of standard
```

with

```markdown
  if the app already has it; 60 seconds (30 before 2026-11-12, when one run was stopped at that
  limit), then the process group is terminated; 1 MiB of standard
```

In `docs/providers/claude.md`, replace

```markdown
- **When:** at app start, on manual refresh (**Check now**, on the dashboard's Claude row and in Settings beside **View Claude usage**), when Claude Code's local usage records change, when a
  displayed window's reset passes, and after 15 minutes without a run. Automatic runs happen at most
  once every 5 minutes and only one at a time. Manual refresh skips the interval and backoff but joins
```

with

```markdown
- **When:** at app start, on manual refresh (**Check now**, on the dashboard's Claude row and in Settings beside **View Claude usage**), when a
  displayed window's reset passes, and after 15 minutes without a run. Automatic runs are in
  practice 15 minutes apart: the minimum of 5 minutes between them matters only after a reset or a
  failed run. Only one runs at a time. Since 2026-11-12 a change in Claude Code's local usage
  records no longer starts a run, because each run makes `claude` scan its session transcripts from
  the last 7 days and those changes started a run every 5 minutes during use. Manual refresh skips the interval and backoff but joins
```

In `docs/providers/claude.md`, replace

```markdown
so they show the no-readable-report state. Usage outside Claude Code, such as on the web, appears
within about 15 minutes while the app is running and the Mac is awake. That means about 96 runs a day from the periodic run alone, and up to 288 a day with other triggers, because runs are at least 5 minutes apart,
whose memory and CPU cost has not been measured.
```

with

```markdown
so they show the no-readable-report state. Usage, in Claude Code or outside it such as on the web,
appears within about 15 minutes while the app is running and the Mac is awake, or about 17 when a
run is slow. That means about 96 runs a day, plus runs after resets and retries after failures
(amended 2026-11-12: it was up to 288 a day while usage-record changes started runs). A run costs
more as the recent transcripts grow: on one Mac the median run took about 4.9 s on 2026-11-05 and
about 8.1 s on 2026-11-12, and one run on 2026-11-05 took about 5.2 s of CPU and 454 MB of peak
memory. CPU and memory were not measured again.
```

- [ ] **Step 5: Update `docs/privacy.md` and `docs/architecture.md`**

In `docs/privacy.md`, replace

```markdown
  the user's installed `claude` automatically, without a click: at app start, when Claude Code's local
  usage records change, after a displayed window resets, on backoff retries and every 15 minutes, as
  well as on manual refresh. Claude Code may renew its own login during such a run. Each run executes
  `/usage` through the user's installed `claude`, with a fixed command, no shell, one fixed working
  folder in the temporary directory that is emptied before each run, a minimal environment and a 30-second limit. Any network use, login renewal or Keychain
  prompt during that run belongs to `claude`. Needlbar reads only the `usage_report` field and an
```

with

```markdown
  the user's installed `claude` automatically, without a click: at app start, after a displayed
  window resets, on backoff retries and every 15 minutes, as
  well as on manual refresh. Since 2026-11-12 a change in Claude Code's local usage records no
  longer starts it, because each run makes `claude` scan its own session transcripts from the last
  7 days. Claude Code may renew its own login during such a run. Each run executes
  `/usage` through the user's installed `claude`, with a fixed command, no shell, one fixed working
  folder in the temporary directory that is emptied before each run, a minimal environment and a 60-second limit (30 seconds before 2026-11-12). Any network use, login renewal, Keychain
  prompt or transcript reading during that run belongs to `claude`. Needlbar reads only the `usage_report` field and an
```

In `docs/architecture.md`, replace

```markdown
manual refresh, when the Claude total in the usage refresh changes, when a displayed reset passes,
and after 15 minutes without a run, at most once every 5 minutes with backoff. The Codex and Cursor refresh never waits for it.
```

with

```markdown
manual refresh, when a displayed reset passes,
and after 15 minutes without a run, at most once every 5 minutes with backoff. Since 2026-11-12 a
changed Claude total in the usage refresh no longer starts a run, because each run scans the last 7
days of Claude Code transcripts, so automatic runs are in practice 15 minutes apart; the usage
refresh still reads that total for tokens and cost. A run is stopped after 60 seconds (30 before
that date). The Codex and Cursor refresh never waits for it.
```

- [ ] **Step 6: Update `docs/HANDOFF.md`**

In `docs/HANDOFF.md`, replace

```markdown
**Checkpoint:** 2026-11-05, updated for the Claude usage report source, which is
prepared and not released and passed about 38 hours of local observation; it replaces the Claude Keychain access action of
```

with

```markdown
**Checkpoint:** 2026-11-12, updated for the `/usage` cadence and deadline change, which is
prepared and not released and not yet run on a real machine; before that 2026-11-05, for the
Claude usage report source, which is
prepared and not released and passed about 38 hours of local observation; it replaces the Claude Keychain access action of
```

In `docs/HANDOFF.md`, replace

```markdown
started; a process that moved to its own session or group is not covered. Claude runs only on app start, manual refresh, usage-record changes, a
passed reset, a backoff retry and every 15 minutes; a dashboard open, waking or
regaining a connection starts none. If Codex is failing, each dashboard open
retries Codex; that starts no Claude run and no dialog.
```

with

```markdown
started; a process that moved to its own session or group is not covered. Claude runs only on app start, manual refresh, a
passed reset, a backoff retry and every 15 minutes; a dashboard open, waking or
regaining a connection starts none. If Codex is failing, each dashboard open
retries Codex; that starts no Claude run and no dialog.

**Cadence and deadline (2026-11-12, prepared, not released).** Design:
`docs/superpowers/specs/2026-11-12-claude-usage-probe-cadence-design.md`. Plan:
`docs/superpowers/plans/2026-11-12-claude-usage-probe-cadence.md`. A change in Claude Code's local
usage records no longer starts a run, and the run deadline is 60 seconds, up from 30. Claude Code
CLI 2.1.321 scans the last 7 days of transcripts on every `/usage` run; runs slowed to a median of
about 8.1 s and one was stopped at 30 seconds, while usage-record changes started a run every 5
minutes during use (STATUS, 2026-11-12). Automatic runs are now in practice 15 minutes apart, so a
reading can be about 17 minutes old before the next one lands, 2 minutes 59 seconds inside the
20-minute window. The `usageRecordsChanged` trigger no longer exists; Needlbar still reads the usage
records for tokens and cost. Revisit if runs approach 60 seconds, rather than raising the deadline
again, or if a later CLI version changes the cost. Not yet checked on a real machine: after
installation the unified log should show only the triggers `startup`, `manual`, `windowReset`,
`backoffRetry` and `periodic`, automatic starts at least 15 minutes apart except after a reset or a
failure, and no `usageProbeTimedOut` with `durationMs` under 60,000.
```

In `docs/HANDOFF.md`, replace

```markdown
logged run succeeded, no Keychain prompt appeared, and runs took about 5 s (maximum about 19.3 s).
Still open: how a signed-out `claude` reports itself in this mode, the same observation on a
```

with

```markdown
logged run succeeded, no Keychain prompt appeared, and runs took about 5 s (maximum about 19.3 s).
Logs from Developer ID builds were read on 2026-11-09 and 2026-11-12 for run counts, triggers and
durations (STATUS, 2026-11-12): the median rose to about 8.1 s and one run was stopped at 30 seconds.
Still open: how a signed-out `claude` reports itself in this mode, the same observation on a
```

- [ ] **Step 7: Update the prepared release notes**

These are plain edits to the final behaviour (Decisions 4.5). Each of the three texts is part of one long line.

In `docs/releases/v0.3.15.md`, replace

```markdown
that is emptied before each run, for at most 30 seconds, and Needlbar ends
```

with

```markdown
that is emptied before each run, for at most 60 seconds, and Needlbar ends
```

In `docs/releases/v0.3.15.md`, replace

```markdown
- Runs happen when Needlbar starts, when you choose **Check now** on the dashboard or in Settings, when Claude Code's local usage records change, when a displayed window's reset passes, and after 15 minutes without a run, at most once every 5 minutes. Opening the dashboard does not start one. After repeated failures Needlbar waits 5, 10, 20, then 30 minutes.
```

with

```markdown
- Runs happen when Needlbar starts, when you choose **Check now** on the dashboard or in Settings, when a displayed window's reset passes, and after 15 minutes without a run. Automatic runs are in practice 15 minutes apart, and at least 5 minutes apart after a reset or a failed run. A change in Claude Code's local usage records does not start a run, because each run makes Claude Code scan its session transcripts from the last 7 days. Opening the dashboard does not start one. After repeated failures Needlbar waits 5, 10, 20, then 30 minutes.
```

In `docs/releases/v0.3.15.md`, replace

```markdown
Known limits: usage outside Claude Code, such as on the web, appears within about 15 minutes while Needlbar is running and the Mac is awake. That means about 96 runs a day from the periodic run alone, and up to 288 a day with other triggers, because runs are at least 5 minutes apart, whose memory and CPU cost has not been measured. A reading shows as last known
```

with

```markdown
Known limits: usage, in Claude Code or outside it such as on the web, appears within about 15 minutes while Needlbar is running and the Mac is awake, or about 17 when a run is slow; **Check now** reads it at once. That means about 96 runs a day, plus runs after resets and retries after failures. A run takes longer as the session transcripts from the last 7 days grow: on one Mac the median run took about 8 seconds, and an earlier run used about 5 seconds of CPU and 454 MB of peak memory. A reading shows as last known
```

- [ ] **Step 8: Add the STATUS entry**

The new entry goes first, above the 2026-11-08 entry.

In `docs/STATUS.md`, replace

```markdown
# Needlbar Development Status

## 2026-11-08 Overview widget bar shape (prepared, not released)
```

with

```markdown
# Needlbar Development Status

## 2026-11-12 Claude usage probe cadence and deadline (prepared, not released)

Implements `docs/superpowers/specs/2026-11-12-claude-usage-probe-cadence-design.md` through
`docs/superpowers/plans/2026-11-12-claude-usage-probe-cadence.md`. Not merged, installed, tagged or
released, and not yet run on a real machine.

- **Change.** A change in Claude Code's local usage records no longer starts a `/usage` run, and
  the run deadline is 60 seconds, up from 30 (user decisions, 2026-11-12). App start, **Check now**,
  a passed reset, the backoff retry and the 15-minute periodic run are unchanged. So are the
  5-minute minimum interval, the backoff steps, the command, parsing and the 20-minute freshness
  window. The `usageRecordsChanged` trigger is removed from the code. Needlbar still reads Claude
  Code's usage records for token totals and cost.
- **Measurements.** Local-only receipts from the maintainer's Mac, read from Needlbar's unified log
  (`QuotaRefreshDiagnostic`, `durationMs`) on the date given:

  | Logs covering | Read on | Build | Claude Code CLI | Runs | Median | Longest completed | Over 20 s |
  |---|---|---|---|---|---|---|---|
  | 17 h to 2026-11-05 | 2026-11-05 | local ad-hoc | 2.1.292 | 125 | 4.9 s | 19.3 s | 0 |
  | 2026-11-08 12:42 to 11-09 07:18 | 2026-11-09 | Developer ID | 2.1.292 | 140 | 6.2 s | 22.5 s | 1 |
  | 2026-11-11 23:31 to 11-12 17:12 | 2026-11-12 | Developer ID, `8cd964c` | 2.1.321 | 104 | 8.1 s | 23.1 s | 5 |

  The CLI version per row follows from the install dates: 2.1.292 on 2026-10-07 and 2.1.321 on
  2026-11-09 at 17:09 local. The second row was a session receipt and is recorded here for the
  first time. One run on 2026-11-12 at 16:26 local was stopped at the 30-second deadline
  (`usageProbeTimedOut`, 30.5 s with the stop grace); its real length is unknown. The next two runs
  succeeded in 17.3 s and 10.8 s. Nine of the ten slowest runs that day fell between 12:11 and
  16:32, almost all started by usage-record changes while Claude Code was in use.
- **Cause, observed.** Text extracted from the installed CLI 2.1.321 shows `/usage` in
  non-interactive mode scanning the transcripts under `~/.claude/projects` whose modification time
  is within a 7-day constant (604,800,000 ms), to build its usage breakdown. No flag, environment
  variable or setting that turns this off was found. On 2026-11-12 the files in that window were
  1,665 transcripts, about 4.93 GB (sizes only; no content was read). About 0.7 GB of transcripts
  last modified on 2026-11-05 at 06:42 left the window on 2026-11-12 at 06:42, and quiet-time runs
  went from 7.56 s (06:36) to 6.0 s (06:51) after three hours at 7.6 to 7.7 s. That is one event:
  it shows that the volume in the window matters, not a rate per gigabyte.
- **Cause, inferred.** Each run reads those files in full, and no cache between runs was found.
  The second and third rows suggest 2.1.321 costs more per gigabyte than 2.1.292, because the
  median rose while the window shrank; no run of both versions on the same data was made. The 15 to
  30-second runs come from contention during heavy use: at the time of the investigation the Mac
  had about 15.9 GB of swap in use, a load average of 8 to 11, and `fseventsd` near 100 percent CPU
  after 41 days of uptime. Needlbar's own share is small: it logs completion 20 to 30 ms after the
  child exits.
- **Cost.** A run takes about 8 seconds of wall time at the median. CPU was last measured on
  2026-11-05, at 5.2 seconds for a 4.3-second run; the bytes actually read were not measured. While
  Claude Code was in use, usage-record changes started a run every 5 minutes, up to 12 an hour. On
  2026-11-05 they were 90 of 125 runs.
- **What the user sees.** Automatic runs are in practice 15 minutes apart, so a reading can be about
  17 minutes old before the next one lands: 15 minutes, one 60-second check, and a run of up to 60
  seconds with the stop grace, 1,021 seconds in all. That is 2 minutes 59 seconds inside the
  20-minute freshness window. During continuous use the age was typically 6 to 7 minutes before. A
  check that runs late under load can briefly show **Last known**. After a failed run the retry
  comes 5 minutes later, so the next reading is about 21 to 24 minutes old. The five-hour and
  seven-day alerts can arrive up to about 17 minutes after the change. **Check now** still reads at
  once, or joins a run in flight, which can now take about 60 seconds.
- **Options not taken.** A usage-record trigger held to 15 minutes after the last start, which
  differs from the periodic run by at most one once-a-minute check. A 15-minute minimum for every
  automatic run, which delays the run after a reset and the retry after a failure. A 45-second
  deadline, because the cost grows with transcript volume. Pointing `CLAUDE_CONFIG_DIR` at a smaller
  folder, which was not tested because it is expected to change where Claude Code finds its login.
- **Not in scope.** The periodic run still makes about 96 runs a day, each scanning up to the whole
  7-day window. A way to skip the scan, or a cache, would have to come from Claude Code. Revisit if
  runs approach 60 seconds, rather than raising the deadline again, or if a later CLI version
  changes the cost. The cause is specific to CLI 2.1.321 and to this Mac's data and load.
- **Verified.** A new test that a changed usage total starts no run; the rewritten schedule,
  coordinator and freshness tests; a Rust test that fixes the default deadline at 60 seconds;
  `make test`; and the `cargo test --workspace` and `cargo clippy` commands that CI runs. Every
  process test used a fake `claude`.

Not established: the change has not run on a real machine. After installation, the unified log
should show only the triggers `startup`, `manual`, `windowReset`, `backoffRetry` and `periodic`;
automatic starts at least 15 minutes apart except after a reset or a failure; and no
`usageProbeTimedOut` with `durationMs` under 60,000. No agent ran `claude` for this change, and the
implementation read no credential file and no Keychain item.

## 2026-11-08 Overview widget bar shape (prepared, not released)
```

- [ ] **Step 9: Check that the replaced statements are gone**

Run:

```bash
rg -n -e "usage records change" -e "usage-record changes, a" \
  -e "Claude total in the usage refresh changes" \
  -e "up to 288 a day with other triggers" -e "limited to 30 seconds" \
  -e "a 30-second limit" -e "at most 30 seconds" \
  -e "30 seconds, then the process group" \
  README.md docs/providers/claude.md docs/privacy.md docs/architecture.md \
  docs/HANDOFF.md docs/releases/v0.3.15.md; echo "rg exit $?"
rg -c "288" docs/superpowers/specs/2026-11-03-claude-usage-report-source-design.md
```

Expected: no matches and `rg exit 1` for the first command. The second prints `3`: the working-directory sentence that stays (Decisions 4.4) and the two amended items, which say what the figure was.

- [ ] **Step 10: Run the full project gate**

Run:

```bash
make test > "${TMPDIR:-/tmp}/needlbar-make-test.log" 2>&1; echo "make exit $?"
tail -n 1 "${TMPDIR:-/tmp}/needlbar-make-test.log"
grep -c '✘' "${TMPDIR:-/tmp}/needlbar-make-test.log"
```

Expected: `make exit 0`, the last line `notarize-app shell contracts passed`, and a count of `0`. The run takes well over ten minutes, so give it a timeout of at least thirty. `notarize-test` reads the README and STATUS edits; the new STATUS entry holds no run ID, asset ID, release commit hash, `releases/tag/` or `report 0.3.`.

- [ ] **Step 11: Run the two Rust commands CI runs outside `make test`**

Run:

```bash
cargo test --workspace 2>&1 | grep -E "^test result|FAILED|^error"
cargo clippy --workspace --all-targets --all-features -- -D warnings; echo "clippy exit $?"
```

Expected: every `test result:` line says `ok` with `0 failed` and no `FAILED` or `error` line appears; then `clippy exit 0` with no warning.

- [ ] **Step 12: Commit**

```bash
git add docs/superpowers/specs/2026-11-03-claude-usage-report-source-design.md \
  docs/superpowers/plans/2026-11-03-claude-usage-report-source.md \
  README.md docs/providers/claude.md docs/privacy.md docs/architecture.md \
  docs/HANDOFF.md docs/releases/v0.3.15.md docs/STATUS.md
git commit -m "docs: record the /usage cadence and deadline change" \
  -m "Usage-record changes no longer start runs and the deadline is 60 seconds. The 2026-11-03 design and plan carry dated amendments, and STATUS holds the measurements behind the decision." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short
```

Expected: `git status --short` shows only `?? .superpowers/brainstorm/`, plus this plan file if the main session has not committed it yet.

---

### Where the plan stops

After Task 3 the branch `claude/claude-usage-probe-cadence` holds three new local commits and is ready for review. Implementers stop here. Pushing the branch and opening a pull request is the main session's step, at the user's request. Merge, installation, tag and release each need the user's separate request and are not part of this plan.

### Manual check (USER-RUN, after installation, not for implementers)

Spec §8 lists what only a real machine can show. It applies once the user has asked for a build with this change to be installed, and has let it run for a few hours with Claude Code in use. Choose a `--last` value shorter than the time since that build started, so lines from the old build are not counted. These commands read Needlbar's own log lines and start nothing.

```bash
P='subsystem == "com.taejunoh.needlbar" AND category == "QuotaRefreshDiagnostic"'
/usr/bin/log show --last 6h --style compact --predicate "$P" | /usr/bin/grep 'phase=started' | /usr/bin/grep -o 'trigger=[A-Za-z]*' | /usr/bin/sort | /usr/bin/uniq -c
/usr/bin/log show --last 6h --style compact --predicate "$P" | /usr/bin/grep 'phase=started' | /usr/bin/sed -E 's/.*(trigger=[A-Za-z]+).*(start=[^ ]+).*/\1 \2/'
/usr/bin/log show --last 6h --style compact --predicate 'subsystem == "com.taejunoh.needlbar" AND category == "ClaudeQuotaFailureDiagnostic"' | /usr/bin/grep -o 'origin=usageProbeTimedOut.*durationMs=[0-9]*'
```

- [ ] The first command lists only `startup`, `manual`, `windowReset`, `backoffRetry` and `periodic`. `usageRecordsChanged` does not appear.
- [ ] In the second, automatic `start=` times are at least 15 minutes apart, except after a `windowReset` or a failure (`backoffRetry`). Only `manual` may be closer.
- [ ] The third prints nothing, or only lines whose `durationMs` is 60,000 or more.
- [ ] While runs succeed, the dashboard, Settings and the widget's Claude row do not flip to **Last known** just before a refresh.

If runs approach 60 seconds, that is the spec's signal to revisit the design, not to raise the deadline again.

---

## Self-Review

**1. Spec coverage**

| Spec | Requirement | Where |
|---|---|---|
| §3.1, §4 | A usage-record change starts no run; other triggers unchanged | Task 2 Steps 1, 3, 4 |
| §3.2, §6 | Deadline 60 seconds; cap, grace, group kill and cancel unchanged | Task 1 Steps 1-4 (only the default changes) |
| §4 | Pending-request path stays, used only by a refused app start | Task 2 leaves `ClaudeUsageProbeSchedule` code as is; Step 4 corrects its comment |
| §4 | Needlbar still reads usage records for totals and cost | Task 2 Step 3 removes only the comparison; `store.applyUsage` is untouched |
| §5 | 1,021 seconds, 2:59 under the window | Task 1 Step 6; Task 3 Steps 1, 6, 8 |
| §7 | `RefreshCoordinator`: `noteClaudeUsageRecords`, the field, its reset, the call with its comment and guard, the deferred-change comment, the `switch` | Task 2 Steps 3, 4 |
| §7 | `QuotaRefreshActivity`: remove `usageRecordsChanged` | Task 2 Step 4 |
| §7 | `ClaudeUsageProbeSchedule`: comment only | Task 2 Step 4 |
| §7 | Rust default deadline | Task 1 Step 3 |
| §7 | Comments with 30 seconds or 16:31 in the three named files | Task 1 Step 5, plus the C header (Decisions 4.1) |
| §8 | New negative test, `[.startup, .periodic]`, second run at 900 s | Task 2 Step 1 |
| §8 | Schedule tests use `.startup` and `.periodic` | Task 2 Step 5 |
| §8 | Coordinator tests removed or rewritten; 991 becomes 1,021; message | Task 2 Step 1; Task 1 Step 6 |
| §8 | Not-installed test at 0, 900, 1,800, then 3,000 | Task 2 Step 1 |
| §8 | Freshness guard `60 + 1` | Task 1 Step 6 |
| §8 | Rust test for the default | Task 1 Step 1 |
| §8 | Existing backoff, manual and single-flight tests still pass | Task 2 Step 7; Task 3 Step 10 |
| §8 | Real-machine check | Manual check, user-run after installation |
| §9 | 2026-11-03 spec: header note, triggers, 5-minute wording, margin, deadline, the clause, 288 in §9 and §12, unmeasured cost | Task 3 Step 1 |
| §9 | 2026-11-03 plan: amendment covering decisions, change detection, checklist | Task 3 Step 2 |
| §9 | README: triggers, 5-minute wording, 288, 30 seconds, cost observation, full-day sentence | Task 3 Step 3 |
| §9 | `providers/claude.md`, `privacy.md`, `architecture.md`, `HANDOFF.md`, `releases/v0.3.15.md` | Task 3 Steps 4-7 |
| §9 | STATUS entry with the §1 and §2 measurements and the decision | Task 3 Step 8 |
| §9 | No in-app text changes | No task touches `Sources/Needlbar` |
| §10 | Idle cost and upstream are out of scope; revisit rule | Recorded in Task 3 Steps 6 and 8; no code |

No gap found. Decisions 4 lists what the plan adds beyond the spec's lists and what it leaves alone.

**2. Placeholder scan:** every code and document step shows the full text to remove and to add, and every command has its expected result. No step says "TBD", "similar to" or "add tests for".

**3. Type consistency:** the plan uses `UsageProbeLimits::default()`, `deadline`, `max_stdout_bytes`, `QuotaRefreshTrigger` cases `.startup`, `.periodic`, `.windowReset`, `.backoffRetry`, `.manual`, and the harness members `Harness(claudeTotal:)`, `startedAndIdle()`, `waitUntilUsageApplied(_:)`, `advance(minutes:)`, `waitUntilCompletedRuns(_:)`, `usage.setClaudeTotal(_:)`, `probe.script(_:)`, `probe.callCount`, `probe.startTimes`, `probe.triggersSeen(in:)`, `probe.waitUntilCallCount(_:)` and the file-level `claudeError(_:)` and `settle(watchingFor:)`. Each exists at `fd021c8` with that spelling, and Task 2 removes only `ScriptedUsageRepository.waitUntilCallCount`, which nothing else calls. The test names `aChangedUsageTotalStartsNoRun` and `notInstalledRetriesOnlyOnThePeriodicRunAndUnderBackoff` are the same in Steps 1, 2 and 7 of Task 2.
