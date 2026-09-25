# Claude Code Status-Line Quota Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show recently reported Claude 5-hour and 7-day quota in Needlbar without repeated login while preserving the user's existing Claude Code status line and independently labeling Fable freshness.

**Architecture:** A signed, small Swift executable receives Claude Code's documented status-line JSON, streams the same stdin to the user's original command, and writes only validated quota windows into a private, generation-fenced local record. Needlbar connects/disconnects the wrapper only on explicit user action. NeedlbarCore retains the direct quota and status-line observations separately; presentation chooses each window's source and freshness without altering direct-only alerts, widget, or export data.

**Tech Stack:** Swift 6, macOS 14, Swift Testing, Foundation, Darwin POSIX file/process APIs, existing SwiftPM app packaging and signing scripts. Do not change the Rust quota/credential provider or pinned `tokscale-core` revision.

**Spec:** `docs/superpowers/specs/2026-09-25-claude-statusline-quota-bridge-design.md`

## Global Constraints

- The connection is opt-in and initially off; app launch and routine refresh never edit Claude Code settings.
- Keep the entire original `statusLine` object and command intact for restoration; do not log, display, or persist raw status-line stdin/output.
- No new access-token, refresh-token, cookie, OAuth, browser, or Keychain handling; leave the existing direct path unchanged and record its provider-policy concern.
- Five-hour and seven-day observations have independent timestamps and validity; status-line data cannot refresh or invent Fable.
- `receivedAt` means local receipt, not provider fetch. Identical payloads do not refresh apparent age; status-line values are never labeled `Live`.
- The original command must receive byte-identical stdin and keep its stdout/stderr/exit behavior even when Needlbar parsing or cache publication fails.
- A disabled generation cannot publish data; retained immutable metadata must still let a delayed wrapper run the original command.
- Preserve macOS 14 and arm64 release packaging; sign the helper before signing the outer app.
- Do not feed synthetic status-line quota into existing direct-only alert, widget, or export freshness without an explicit separate design.

## Review Focus

1. An external editor changes `settings.json` during connect/disconnect: abort a detected conflict, never silently replace unrelated edits; note that non-cooperating editors prevent an absolute CAS guarantee (Task 3 tests).
2. A wrapper starts or finishes across disconnect/reconnect: its original command still runs, but it cannot republish old quota into the new generation (Tasks 2–3 tests).
3. Oversized or malformed stdin: every byte still reaches the original command, while no raw JSON or partial quota enters the cache (Tasks 1–2 tests).
4. Two Claude sessions report different values: each window merges separately, duplicate/smaller same-reset observations cannot appear fresh again (Task 1 tests).
5. Direct Claude fetch fails while status-line data arrives: main quota can be recently reported, but Fable, direct error, alerts, widgets, and exports keep their independent status (Tasks 4–5 tests).

---

### Task 1: Pure status-line quota parsing and per-window merge

**Files:**
- Modify: `Package.swift`
- Create: `Sources/NeedlbarClaudeStatusLineSupport/StatusLineQuotaRecord.swift`
- Create: `Tests/NeedlbarClaudeStatusLineSupportTests/StatusLineQuotaRecordTests.swift`

**Interfaces:**
- Produces `StatusLineWindowObservation(usedPercent: Double, resetsAt: Date?, receivedAt: Date)` and `StatusLineQuotaRecord(schemaVersion: Int, generation: UUID, fiveHour: StatusLineWindowObservation?, sevenDay: StatusLineWindowObservation?)`.
- Produces `StatusLineQuotaParser.parse(_ data: Data, generation: UUID, receivedAt: Date) -> StatusLineQuotaRecord?` and `StatusLineQuotaMerger.merge(existing:incoming:) -> StatusLineQuotaRecord`.
- Parser input cap: 256 KiB. Status-line keys are `rate_limits.five_hour` and `rate_limits.seven_day`, each with `used_percentage` and optional integer `resets_at` in Unix seconds.

- [ ] **Step 1: Write the failing parser/merge tests.** In the new Swift Testing target, use literals such as:

```swift
let input = Data(#"{"rate_limits":{"five_hour":{"used_percentage":25,"resets_at":1790323200},"seven_day":{"used_percentage":60,"resets_at":1790841600}}}"#.utf8)
let parsed = StatusLineQuotaParser.parse(input, generation: generation, receivedAt: fixedDate)
#expect(parsed?.fiveHour?.usedPercent == 25)
#expect(parsed?.sevenDay?.usedPercent == 60)
#expect(parsed?.fiveHour?.receivedAt == fixedDate)
```

Add separately named tests for missing Fable field, null/malformed/NaN/out-of-range percentages, malformed reset seconds, >256 KiB, five-hour-only updates, identical replay, older reset, and smaller used percentage at the same reset. A missing window never updates the stored timestamp; only a changed, nonregressing window gets a new `receivedAt`. Explicitly test an undated window and its conservative same-window merge rule.

- [ ] **Step 2: Verify RED.** Run `swift test --filter StatusLineQuotaRecordTests`; expect missing target/symbol failure, not a passing test.
- [ ] **Step 3: Implement only the parser and deterministic merge.** Use strict DTO decoding or `JSONSerialization` for only the allowlisted keys; validate finite `[0,100]`, integral reset seconds, and record schema version. Do not serialize the original JSON into any model.
- [ ] **Step 4: Verify GREEN.** Run `swift test --filter StatusLineQuotaRecordTests`, then `PATH=/Users/taejunoh/.cargo/bin:$PATH make test`; require both exit 0.
- [ ] **Step 5: Commit.** Stage these three files and commit `feat: parse Claude Code status-line quota windows`.

### Task 2: Secure record store and transparent executable

**Files:**
- Modify: `Package.swift`
- Create: `Sources/NeedlbarClaudeStatusLineSupport/StatusLinePrivateStore.swift`
- Create: `Sources/NeedlbarClaudeStatusLineSupport/StatusLineCommandRunner.swift`
- Create: `Sources/NeedlbarClaudeStatusLine/main.swift`
- Create: `Tests/NeedlbarClaudeStatusLineSupportTests/StatusLinePrivateStoreTests.swift`
- Create: `Tests/NeedlbarClaudeStatusLineSupportTests/StatusLineCommandRunnerTests.swift`

**Interfaces:**
- `StatusLinePrivateStore.publish(_ incoming: StatusLineQuotaRecord) throws -> Bool` and `read(expectedGeneration: UUID) throws -> StatusLineQuotaRecord?` operate under one stable lock inode. `deactivate(generation:)` invalidates publication and removes its cache under the same lock.
- `StatusLineConnectionMetadata(generation: UUID, originalStatusLineJSON: Data?, originalCommand: String?, ownedStatusLineJSON: Data)` is the immutable private backup format shared with Task 3.
- `StatusLineCommandRunner.run(originalCommand: String?, generation: UUID, input: FileHandle, output: FileHandle, error: FileHandle, store: StatusLinePrivateStore, now: () -> Date) -> Int32` executes the original command or a minimal Needlbar status line when there was none; parse/cache errors are best effort and cannot change its result. The executable resolves immutable generation metadata; it never receives the original command as a shell argument in `settings.json`.

- [ ] **Step 1: Write failing file and process tests.** Use a temporary mode-0700 directory and synthetic command that copies stdin to a file, writes fixed bytes to stdout/stderr, and exits 17. Assert byte equality for normal and >256 KiB input, output streams, exit 17, inherited cwd/environment, malformed JSON, unwritable cache, and child cancellation. Create a blocked child fixture: deactivate while it runs, then unblock and assert no cache reappears. Add symlink, wrong owner/mode, older generation, and two concurrent-writer tests. Tests must inspect no real `~/.claude` files.

```swift
let bytes = Data(repeating: 0x51, count: 262_145)
let exitCode = StatusLineCommandRunner.run(
    originalCommand: "cat > \"$CAPTURE\"; printf ok; printf warning >&2; exit 17",
    generation: generation, input: inputHandle, output: outputHandle,
    error: errorHandle, store: store, now: { fixedDate }
)
#expect(exitCode == 17)
#expect(try Data(contentsOf: captureURL) == bytes)
#expect(try store.read(expectedGeneration: generation) == nil)
```

- [ ] **Step 2: Verify RED.** Run `swift test --filter NeedlbarClaudeStatusLineSupportTests`; expect missing store/runner behavior.
- [ ] **Step 3: Implement minimal secure store and runner.** Create the private directory mode 0700 and metadata/cache files mode 0600; use descriptor-relative `openat`/`O_NOFOLLOW`, `fstat`, exclusive temporary files, and atomic same-directory rename. Hold the stable lock across active-generation check, read, merge, and rename; never remove/recreate the lock inode. Start the original command before streaming fixed-size stdin chunks; keep only a bounded parsing copy, inherit output descriptors, propagate signals and child termination, and handle partial writes/`EINTR`/`EPIPE`. Choose an invocation shell by a documented compatibility rule and prove it with synthetic shell-specific fixtures before enabling an existing command; do not assume all user commands are POSIX-sh compatible. Keep immutable old-generation command metadata conservatively available after disconnect.

```swift
// The store lock covers all four actions, not just the final rename.
try store.withExclusiveLock {
    guard try store.activeGeneration() == incoming.generation else { return false }
    let merged = StatusLineQuotaMerger.merge(existing: try store.readLocked(), incoming: incoming)
    try store.atomicReplaceLocked(merged)
    return true
}
```

- [ ] **Step 4: Verify GREEN.** Run the support target tests and full `PATH=/Users/taejunoh/.cargo/bin:$PATH make test`; require exit 0.
- [ ] **Step 5: Commit.** Commit `feat: add generation-fenced Claude status-line helper`.

### Task 3: Opt-in settings transaction and exact restoration

**Files:**
- Create: `Sources/Needlbar/Claude/ClaudeStatusLineConnectionManager.swift`
- Create: `Tests/NeedlbarTests/ClaudeStatusLineConnectionManagerTests.swift`
- Modify: `Sources/Needlbar/Settings/SettingsView.swift`
- Modify: `Sources/Needlbar/Settings/SettingsWindowController.swift`
- Modify: `Sources/Needlbar/MenuBar/MenuBarController.swift`

**Interfaces:**
- `ClaudeStatusLineConnectionManager.inspect() -> ConnectionInspection`, `connect(expectedRevision: Data) throws -> ConnectionState`, `disconnect() throws -> ConnectionState`, and `recover() -> ConnectionState` are local-only. `ConnectionInspection` carries a SHA-256 `revision: Data` of the settings bytes and `state: ConnectionState`; never expose the bytes themselves. The state distinguishes `disconnected`, `waitingForData`, `connected(receivedAt:)`, `configurationChanged`, and `unsupportedConfiguration`.
- `ConnectionError.configurationChanged`, `.unsupportedStatusLine`, and `.unsafeSettingsFile` are sanitized failure cases; no case contains the original command or raw settings bytes.
- Manager owns the original raw top-level `statusLine` JSON object and an immutable private generation record. It installs a path-only helper command and owns only that exact replacement object. Retired command metadata is not automatically deleted: Claude Code may invoke an older configured wrapper after disconnect, and no reliable provider signal proves that cannot happen. The Settings disclosure names this private retained copy; no automatic cleanup is claimed.

- [ ] **Step 1: Write failing connection tests.** In synthetic config roots, verify default-off/no edit, pre-existing `statusLine` byte-for-byte restoration, absent entry removal, unrelated top-level fields preserved, `padding`/`refreshInterval` preserved, duplicate keys rejected, and non-command settings rejected. Simulate settings content changing between inspect/connect and before rename; assert conflict with original content intact. Simulate interruption after metadata preparation, ownership loss after user edit, repeated connect/disconnect, and old-generation delayed execution. Assert no raw command appears in a diagnostic string or app log seam.

```swift
let original = Data(#"{"statusLine":{"type":"command","command":"printf original","padding":2},"theme":"dark"}"#.utf8)
try original.write(to: settingsURL)
let revision = try manager.inspect().revision
_ = try manager.connect(expectedRevision: revision)
_ = try manager.disconnect()
#expect(try Data(contentsOf: settingsURL) == original)
```

- [ ] **Step 2: Verify RED.** Run `PATH=/Users/taejunoh/.cargo/bin:$PATH make swift-test SWIFT_TEST_FILTER=ClaudeStatusLineConnectionManagerTests`; expect tests to fail on the missing manager/behavior.
- [ ] **Step 3: Implement the narrow config editor and transaction.** Parse JSON while retaining byte ranges for top-level `statusLine`; reject duplicate/unsafe syntax. Save the original entry before replacing it, re-read and compare before atomic replacement, and re-check after rename for detectable conflict. On disconnect, restore only if the current entry matches the owned wrapper; otherwise leave user edits intact. Fence publication before cache removal and keep retired metadata for delayed invocations. Report unsupported nondefault `CLAUDE_CONFIG_DIR`/project override where detectable. Do not silently modify settings during `recover()`.

```swift
let original = try editor.inspectTopLevelStatusLine(settingsBytes)
try metadataStore.prepare(generation: generation, original: original)
guard try settingsReader.read() == settingsBytes else { throw ConnectionError.configurationChanged }
try settingsWriter.atomicReplace(editor.replacingStatusLine(with: ownedEntry))
```

- [ ] **Step 4: Add the explicit Settings toggle/state copy.** It explains event-driven updates, first-observation waiting, private original-command retention after disconnect for delayed invocations, and never presents the bridge as a Claude login. Wire the manager through Settings controller/menu-bar construction without invoking `connect` at launch.
- [ ] **Step 5: Verify GREEN.** Run focused Settings/manager tests and full `make test` with Cargo on `PATH`; require exit 0.
- [ ] **Step 6: Commit.** Commit `feat: opt in to reversible Claude status-line connection`.

### Task 4: Separate status-line state and source selection

**Files:**
- Modify: `Package.swift`
- Create: `Sources/NeedlbarCore/Repositories/ClaudeStatusLineCacheRepository.swift`
- Create: `Sources/NeedlbarCore/Presentation/ClaudeQuotaPresentationSelector.swift`
- Modify: `Sources/NeedlbarCore/Presentation/HeadlineQuotaSelector.swift`
- Modify: `Sources/NeedlbarCore/Models/ProviderSnapshot.swift`
- Modify: `Sources/NeedlbarCore/State/ProviderSnapshotStore.swift`
- Modify: `Sources/NeedlbarCore/Refresh/RefreshCoordinator.swift`
- Test: `Tests/NeedlbarCoreTests/ProviderSnapshotStoreTests.swift`
- Test: `Tests/NeedlbarCoreTests/RefreshCoordinatorTests.swift`
- Create: `Tests/NeedlbarCoreTests/ClaudeQuotaPresentationSelectorTests.swift`
- Test: `Tests/NeedlbarCoreTests/HeadlineQuotaSelectorTests.swift`

**Interfaces:**
- `ClaudeStatusLineCacheRepository.read(expectedGeneration: UUID) -> StatusLineQuotaRecord?` reads only the validated local record; no network, Keychain, or Claude child process.
- `ProviderSnapshot.claudeStatusLineQuota: StatusLineQuotaRecord?` and `ProviderSnapshotStore.applyClaudeStatusLineQuota(_:)` are separate from `quota`, `quotaStatus`, `quotaLastSuccessfulAt`, and `claudeQuotaFailureReason`.
- `ClaudeQuotaPresentationSelector.select(snapshot: ProviderSnapshot, now: Date) -> ClaudeQuotaSelection` returns `fiveHour`, `sevenDay`, and `fable` as independent `DisplayedClaudeWindow?` values. Each displayed window carries `remainingPercent: Double`, `source: ClaudeWindowSource` (`direct` or `claudeCodeStatusLine`), `observedAt: Date`, and `isLastKnown: Bool`. A status-line window is recently reported for at most 15 minutes after a **changed** observation and never beyond its passed reset; that limit is not proof of provider freshness.

- [ ] **Step 1: Write failing Core tests.** Given direct failure plus five-hour status-line 25% used, expect 75% remaining reported by Claude Code, while old Fable retains its original direct timestamp and direct reason remains stored. Test seven-day missing, identical replay after 20 minutes, expired reset, direct recovery taking precedence, and non-Claude provider unaffected. Verify `quotaAlertCapture`, `captureForWidget`, and `captureForExport` remain direct-only and do not become fresh when status-line state changes.

```swift
await store.markQuotaFailure(for: .claude, status: .requiresAuthentication,
                             claudeFailureReason: .quotaAccessUnavailable, at: failureDate)
await store.applyClaudeStatusLineQuota(statusLineRecord)
let snapshot = await store.snapshot(for: .claude)
let selected = ClaudeQuotaPresentationSelector.select(snapshot: snapshot, now: receiptDate)
#expect(selected.fiveHour?.remainingPercent == 75)
#expect(selected.fiveHour?.source == .claudeCodeStatusLine)
#expect(snapshot.claudeQuotaFailureReason == .quotaAccessUnavailable)
```

- [ ] **Step 2: Verify RED.** Run `PATH=/Users/taejunoh/.cargo/bin:$PATH make swift-test SWIFT_TEST_FILTER=ClaudeQuotaPresentationSelectorTests`; expect missing selector behavior.
- [ ] **Step 3: Implement local read and separate state.** `RefreshCoordinator` reads the local record during its existing cadence independently of direct provider success/failure and applies only a changed, active-generation observation. Do not route this through `ProviderSnapshotStore.applyQuota`; preserve single-flight/generation gating and direct error reason. The selector chooses direct when direct is fresh; otherwise status-line main windows where recent, with independently last-known/unavailable Fable.

```swift
// Separate state; this must not call applyQuota or clear the direct failure.
if let record = statusLineRepository.read(expectedGeneration: connectionGeneration) {
    await store.applyClaudeStatusLineQuota(record)
}
```

- [ ] **Step 4: Verify GREEN.** Run Core-focused suites and full `make test`; require exit 0.
- [ ] **Step 5: Commit.** Commit `feat: keep Claude status-line quota separate from direct quota`.

### Task 5: Render provenance and independent Fable status

**Files:**
- Modify: `Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift`
- Modify: `Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift`
- Modify: `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift`
- Modify: `Sources/Needlbar/Settings/SettingsView.swift`
- Test: `Tests/NeedlbarTests/SystemDashboardPopoverTests.swift`
- Test: `Tests/NeedlbarTests/PopoverPresentationTests.swift`
- Test: `Tests/NeedlbarTests/SettingsStudioTests.swift`

**Interfaces:**
- Present the selector's main windows as `Reported by Claude Code` with local receipt time, not `Live` or a server-fetch timestamp. Fable uses its own direct-source `Last known`/`Unavailable` and last-success time. Preserve the existing `View Claude usage` action.

- [ ] **Step 1: Write failing presentation tests.** Test direct failure + recent status-line + stale Fable, no status-line sample, 20-minute-old sample, reset-passed sample, and direct recovery. Assert no `Sign-in required` copy when a main status-line value is available. Assert Fable's old reset is not rendered as a current countdown. Test headline selection does not present stale direct values as current; Codex/Cursor unaffected.

```swift
let presentation = ProviderPopoverPresentation(snapshot: mixedSourceSnapshot, now: receiptDate)
#expect(presentation.headlineQuotaRemaining == "75%")
#expect(presentation.quotaSourceText == "Reported by Claude Code")
#expect(presentation.fableIsLastKnown)
#expect(presentation.quotaLastCheckedText != nil)
```

- [ ] **Step 2: Verify RED.** Run focused popover/Settings Swift tests; expect the new source/freshness assertions to fail.
- [ ] **Step 3: Implement the minimal row/label changes.** Keep the present compact layout, use the selector's per-window status, expose one source-time label, and avoid duplicate direct-error copy when main quota is available. Do not change local usage or API billing rows.

```swift
if let source = presentation.quotaSourceText {
    Text(source).font(.caption).foregroundStyle(.secondary)
}
if presentation.fableIsLastKnown {
    Text("Fable · Last known").font(.caption).foregroundStyle(.secondary)
}
```

- [ ] **Step 4: Verify GREEN.** Run focused tests and full `make test`; require exit 0.
- [ ] **Step 5: Commit.** Commit `feat: show Claude status-line provenance and Fable age`.

### Task 6: Package, sign, and validate the helper

**Files:**
- Modify: `scripts/package-app.sh`
- Modify: `scripts/notarize-app.sh`
- Modify: `scripts/smoke-app.sh`
- Modify: `scripts/tests/package-app-tests.sh`
- Modify: `scripts/tests/notarize-app-tests.sh`
- Modify: `docs/STATUS.md`
- Modify: `README.md` only after native behavior is verified and the copy can be factual.

**Interfaces:**
- Production `Needlbar.app/Contents/MacOS/NeedlbarClaudeStatusLine` is arm64, signed before the outer app, and independently verified in the zipped/notarized artifact. Opt-in copies it atomically to a stable private executable path so app relocation/update cannot strand `statusLine.command`.

- [ ] **Step 1: Write failing packaging contract tests.** Extend fake Swift build to emit the helper; assert the real package script installs the fresh helper and signs it before the host. Extend notarization tests to require hardened-runtime Developer ID re-sign of helper before host, plus smoke checks for helper architecture/signature. These tests must fail on the current package scripts.

```bash
[[ -x "$fixture_root/dist/Needlbar.app/Contents/MacOS/NeedlbarClaudeStatusLine" ]] || fail 'status-line helper missing'
helper_sign_line=$(grep -n 'NeedlbarClaudeStatusLine' "$temp_root/codesign.log" | head -n 1 | cut -d: -f1)
host_sign_line=$(grep -n 'Needlbar.app' "$temp_root/codesign.log" | tail -n 1 | cut -d: -f1)
[[ "$helper_sign_line" -lt "$host_sign_line" ]] || fail 'helper signed after host'
```

- [ ] **Step 2: Verify RED.** Run `make package-test notarize-test`; expect the new helper assertions to fail.
- [ ] **Step 3: Implement packaging and stable helper copy.** Add the executable product to the package build, install it in the app, sign helper before host, verify strict/deep signatures, and update stable private helper atomically only for an already-enabled connection. Do not alter Claude Code settings on app upgrade. The app never executes an untrusted helper path from settings.

```bash
helper_source="$ROOT/.build/arm64-apple-macosx/release/NeedlbarClaudeStatusLine"
install -m 755 "$helper_source" "$CONTENTS_PATH/MacOS/NeedlbarClaudeStatusLine"
codesign --force --sign "$IDENTITY" "$CONTENTS_PATH/MacOS/NeedlbarClaudeStatusLine"
```

- [ ] **Step 4: Verify GREEN.** Run package/notarize/smoke contracts and full `PATH=/Users/taejunoh/.cargo/bin:$PATH make test`; require exit 0. Run `git diff --check` and verify no debug/raw status-line payload output.
- [ ] **Step 5: Native acceptance.** With the user's explicit opt-in, compare Needlbar 5-hour/7-day values and receipt labels against Claude Code after a genuine status-line event, verify the user's original status line still renders, then disconnect and compare the exact original settings entry. Do not access/print its command or store a real raw payload as evidence. If no event arrives, report `Waiting for Claude Code data` instead of claiming success.
- [ ] **Step 6: Update status and review.** Record test and native evidence plus any remaining Fable/direct-policy limitation in `docs/STATUS.md`; update README only for demonstrated behavior. Request independent spec and code-quality review, address findings, then commit `feat: package and verify Claude status-line bridge`.

## Final gates

- `PATH=/Users/taejunoh/.cargo/bin:$PATH make test` exits 0 on the final tree.
- `git diff --check` exits 0; branch has no uncommitted changes after its final commit.
- Existing status-line command is preserved and can be restored without exposing its content.
- No claim of fixed live Fable, installed app, pushed branch, PR, or release without its corresponding observed evidence and authorization.
