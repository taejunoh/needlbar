# Fable Percent on the Overview Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the remaining Fable percent as small text at the right end of the Claude column's name line on the medium Overview widget, as approved in the 2026-11-13 design.

**Architecture:** The projection's Claude quota row gains one optional `fable` reading (percent and optional reset time), validated by one rule that the row, the projection and the app's mapper share; the schema version stays 1. `WidgetProjectionMapper` copies it from the `claude.fable.weekly` window and drops it without throwing when it cannot be carried. `WidgetPresentation` turns it into the text, colour level, VoiceOver suffix and one more reload deadline, and the widget view only lays the text out on the name line.

**Tech Stack:** Swift 6 and Swift Testing, SwiftUI and WidgetKit in a macOS 14+ arm64 app extension, Foundation `JSONEncoder`/`JSONDecoder`.

## Global Constraints

Authoritative spec: `docs/superpowers/specs/2026-11-13-widget-fable-percent-design.md`. Copied from it verbatim:

- Status: "It authorizes an implementation plan only. Implementation, merge, installation, tag, and release each still need the user's separate request."
- Scope: "The medium **Overview** widget and the projection the app writes for it." and "The widget's family, tap target, refresh behaviour, columns, figures, bars, captions and footer are unchanged, and so is how the Claude headline is chosen."
- Where: "`Fable 71%` at the right end of the Claude column's name line, in caption size, on the same line as **Claude**. The widget gains no height."
- What: "the remaining Fable percent only, rounded to a whole number like the other figures. No reset time."
- "**The big Claude number stays the headline**, the lower of session and weekly, even when Fable is lower."
- Data: "The Claude quota row in the projection gains one optional reading, `fable`, with the remaining percent and an optional reset time. It carries no window ID and no timestamp of its own"
- "**Schema version stays 1.**" and "A projection with no Fable value encodes exactly as today."
- "**Both decode paths and both validators carry the field**: the row's own initializers and the raw row used by the projection decoder, and the row and projection validation."
- Validation: "rejecting the projection like any other invalid row: `fable` only on the Claude row; percent finite and within 0 to 100; reset time finite when present; the row has a last successful time."
- Mapper: "emits Fable only for the Claude provider, from the window `claude.fable.weekly` in the direct quota snapshot. It drops Fable, and never throws, when there are zero or several matching windows, the reset is not finite, or the row has no last successful time."
- "The headline allowlist is unchanged, so Fable never becomes the headline, and older widgets never see an unknown headline ID."
- The one rule: "**the Fable text appears only when the Claude column shows a figure and the row has a Fable value.** Its content depends only on its own value and reset; the column's caption carries freshness."
- States, with the text and what is "Added to the column's VoiceOver label":

  | State | Fable text | Added to the column's VoiceOver label |
  |---|---|---|
  | Value present, reset in the future or absent | `Fable 71%` | ", Fable 71 percent remaining" |
  | Claude reading stale | `Fable 71%`; the caption says **Last checked**, or **Awaiting fresh reading** if the headline reset passed | ", Fable 71 percent remaining" |
  | Headline reset passed, Fable reset not | `Fable 71%`, not dimmed, while the figure and bar dim | ", Fable 71 percent remaining" |
  | Fable reset passed (fresh or stale, headline valid or not) | `Fable —` | ", Fable awaiting fresh reading" |
  | No Fable value (a report with no Fable row, an unmatched label, an older file) | hidden | nothing |
  | No projection, or the Claude column shows `—` | hidden | nothing |
  | Codex column | never | nothing |

- Colour: "judged on the whole percent shown, as for the big figure: system orange below 20 percent, system red below 10 percent, otherwise the secondary colour. So 19.5 shows `20%` uncoloured, 99.6 shows `100%`, 0.4 shows `0%`. `Fable —` uses the secondary colour. There is no bar and no size change."
- "**Never invented:** a missing value is hidden, never shown as zero, and Fable is never estimated from the weekly value. Fable can read higher than the weekly figure; it is shown as reported."
- Layout: "the name line becomes a first-baseline row of the name, a spacer and the Fable text. The name keeps layout priority, so only the Fable text shrinks; it keeps one line, uses monospaced digits, and may scale down to 0.8."
- Updating: "When the row has a Fable reset time, it joins the widget's reload deadlines while it is in the future, so the widget redraws when it passes and shows `Fable —`. A reset already passed is not a deadline. Fable adds no countdown text, so it adds no countdown deadlines."
- "The widget extension's build and search-guard checks still pass. The search guard rejects certain words anywhere in the widget sources, comments included."
- "**Not automated, checked by the user on the installed widget** after a tagless Developer ID build and installation (both separate requests): light and dark appearance; `Fable 100%` fits on one line without truncation; the text reads as part of the Claude column; the low colour, when it occurs."
- Documentation: "Dated notes, each saying what changed and why" and "a new `docs/STATUS.md` entry marked prepared, not released."
- "`docs/architecture.md` and `docs/privacy.md` describe the projection only in general terms and stay unchanged. The acceptance driver's fixtures stay unchanged; the Fable text is a manual check."

Repository constraints:

- Implementers never run `claude`; never read `~/.claude/.credentials.json`, `~/.claude.json`, Keychain items or cookies; never launch, kill or install any Needlbar app or widget process (no `make smoke`, nothing copied into `/Applications`); never push, merge, tag or start a release. This plan ends with five local commits on `claude/widget-fable-line`.
- The widget extension compiles exactly `WidgetProjection.swift`, `WidgetPresentation.swift` and `NeedlbarOverviewWidget.swift` (`scripts/build-widget-extension.sh:12-14,54-56`). Add no file to `Sources/NeedlbarWidgetSupport`; extend the two that exist.
- No widget or support source may contain the case-sensitive words `NeedlbarCore`, `CNeedlbar`, `Rust`, `Keychain` or `URLSession`, comments included (`scripts/tests/widget-extension-tests.sh:25`). The widget source may not contain `AcceptanceFixture` (`scripts/tests/acceptance-build-isolation-tests.sh:17`). The code in this plan contains none of them; keep it that way if a comment is reworded.
- Widget code builds with `-target arm64-apple-macosx14.0 -swift-version 6 -application-extension`. CI builds with Xcode 16.2 and Swift 6.0, which is stricter than the local Swift 6.4 in places (for example, an implicit `switch` return is valid only as the sole expression of a body). Use the code in this plan as written and add no newer-only syntax.
- Bare `swift test` cannot link, because the tests need the bridge built with its test feature. Use `make swift-test SWIFT_TEST_FILTER=<name>` (`Makefile:9-53`). It builds that bridge, cleans the Swift build, runs the tests, then restores the normal bridge and cleans again, so each run takes about five minutes. Give it a timeout of at least ten minutes and let it finish; do not interrupt it.
- Never run `cargo fmt --all`. This plan changes no Rust file.
- In `README.md`, new text contains neither `0.3.14` nor `0.3.15`. The fixture at `scripts/tests/notarize-app-tests.sh:2239-2255` removes the two version sections, rewrites seven fixed phrases, and aborts with `historical fixture: v0.3.14 text remains` if either number remains anywhere else. Say "prepared, not released" without a version.
- New `docs/STATUS.md` text repeats no run ID, asset ID, commit hash, `releases/tag/`, or `report 0.3.`, because the decoys at `scripts/tests/notarize-app-tests.sh:2207-2229` rewrite the first occurrence. It says prepared, not released, and not seen on a real widget.
- Stage only the files each commit step lists. Never `git add -A` or `git add .`: `.superpowers/brainstorm/` is untracked and stays out.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Commands run from the repository root after `export PATH="$HOME/.cargo/bin:$PATH" MACOSX_DEPLOYMENT_TARGET=14.0`. `rg` and the `make` targets that use it need `PATH` prefixed with `/Users/taejunoh/.codex/plugins/.plugin-appserver/codex-cli/codex-path` on the maintainer's Mac.
- Line numbers are from commit `697563e`. Once an earlier step shifts a file, find the place by the quoted text. Every quoted "replace" text occurs exactly once in its file.

---

## Decisions Settled From The Code

### 1. Where the field goes, and the one validation rule

| Place | Today | Change |
|---|---|---|
| `WidgetQuotaRow`, `Sources/NeedlbarWidgetSupport/WidgetProjection.swift:47-89` | Four fields; a throwing initializer that refuses Cursor and a headline of the other provider; a hand-written `init(from:)` over a keyed container; synthesized `encode(to:)` | Gains `fable: WidgetFableReading?`, an initializer parameter defaulting to `nil`, a coding key, and `decodeIfPresent` (Task 1) |
| `RawQuotaRow`, `:311-316`, used by `WidgetProjection.init(from:)` at `:338-355` | Synthesized `Decodable`; the projection decoder reads this, not the row's own `init(from:)` | Gains `fable: WidgetFableReading?`, passed to the row initializer (Task 1) |
| `WidgetProjection.validate`, `:383-397` | Checks each row's headline, timestamps and reset | Also checks the row's Fable reading (Task 1) |
| `WidgetProjectionMapper.mapQuota`, `Sources/NeedlbarCore/Widget/WidgetProjectionMapper.swift:38-47` | Builds the headline from the allowlisted windows | Also passes `fableReading(...)`, which cannot throw (Task 2) |
| `WidgetQuotaColumn`, `Sources/NeedlbarWidgetSupport/WidgetPresentation.swift:50-61`, and `quotaColumn`, `:192-242` | Seven fields, memberwise initializer | Gains `fable: WidgetFableText?` and the label suffix (Task 3) |
| `nextDeadline`, `:313-334` | Resets come from the headlines | Also from the Fable readings (Task 3) |
| `QuotaColumnView`, `WidgetExtension/NeedlbarOverviewWidget.swift:113-117` | `Text(column.title).font(.headline)` | A first-baseline row of the name, a spacer and the Fable text (Task 3) |

- **One rule.** `WidgetFableReading.isValid(for:lastSuccessfulAt:)` holds the spec's four conditions. The row initializer, `WidgetProjection.validate` and the mapper all call it, so they cannot disagree. This is what makes "the mapper never throws for Fable" hold: the mapper keeps a reading only when the rule accepts it, and the rule is the only Fable check that can throw later.
- **Stricter than the headline at the row.** A row can be built with a headline of 101 percent, and only the projection refuses it (`WidgetProjectionTests.swift:62-78`). A row cannot be built with an invalid Fable reading at all. The spec asks for both validators to carry the field; using the full rule in both is the simplest way to do that.
- **Decoding.** Both paths use keyed containers or synthesized `Decodable`, which ignore keys they do not know, and `decodeIfPresent` reads a missing key and `null` as no value. A `fable` value of the wrong shape fails decoding and rejects the whole file, as a malformed headline does today.
- **Encoding.** `WidgetQuotaRow.encode(to:)` is synthesized, so a `nil` optional writes no key. A projection without Fable therefore encodes byte for byte as before; Task 1 pins this with the exact bytes the code at `697563e` produced.

### 2. Schema version 1, checked against the old code

Before any edit, a temporary test on a scratch copy at `697563e` decoded a file whose Claude row had `"fable":{"remainingPercent":71,"resetsAt":"2027-01-15T09:00:00Z"}`, through `WidgetProjection.decode` and through `WidgetQuotaRow`'s own decoder. Both succeeded and ignored the key. So a widget process from before this change reads a new file, without the Fable text. `anUnknownKeyOnAQuotaRowIsIgnored` in Task 1 keeps that property under test for the next field.

### 3. Presentation

- `WidgetFableText` holds the text and a colour level. The level is `nil` for `Fable —`; the view maps `.low` to orange, `.critical` to red, and everything else to the secondary colour.
- `WidgetQuotaColumn` gets an explicit internal initializer whose `fable` parameter defaults to `nil`. The existing tests compare whole columns built without it (`WidgetOverviewPresentationTests.swift:79-87,93-101,112-120,141-149,158-166`), so they keep compiling and now also assert that those columns carry no Fable text, including the Codex column and the unavailable column.
- The Fable text is computed after the `wholePercent` guard in `quotaColumn`, which is reached only when the column shows a figure. `unavailableColumn` never sets it. That is the spec's one rule.
- The reload change is one line: the Fable resets join the list that `nextDeadline` already filters to the future. The countdown steps still come from fresh headlines only.

### 4. Test mechanics

- **Filters.** Two suites are named `WidgetProjectionTests`, one in `NeedlbarWidgetSupportTests` and one in `NeedlbarCoreTests`. `SWIFT_TEST_FILTER=WidgetProjection` runs both and prints one `Test run with` line per test target: today 15 and 14 tests. `SWIFT_TEST_FILTER=NeedlbarWidgetSupportTests` runs the support target's two suites: today 36 tests. The filter is passed unquoted to the shell, so it holds no `|` or parentheses.
- **What fails first.** Task 1 and Task 3 fail to compile, because the tests name types that do not exist yet. In Task 2 the two tests that expect a copied value fail. Three tests pass before their implementation and are guards: the unknown-key test (Task 1), the mapper tests that expect Fable to be dropped (Task 2), and the test that Fable adds no countdown step (Task 3). The steps say so instead of pretending a failure. The Task 2 guards were checked against a naive mapper that copies the first Fable window unconditionally: they failed there with `Caught error: .invalidQuotaRow` and `Expectation failed: row.fable == nil`.
- **`make widget-extension-test` never compiles Swift**, because its `xcrun` is a fake (`scripts/tests/widget-extension-tests.sh:34-58`). The real compile runs only inside `make package`. Task 3 therefore also runs `./scripts/build-widget-extension.sh` directly: a real `swiftc` build into the git-ignored `.build/widget-extension`, signed ad hoc, with nothing installed or launched.
- **Layout, measured.** A SwiftUI view with the same modifiers, hosted in AppKit on the maintainer's Mac, measured the name line at 46 by 16 points before and 16 points high after, with or without the Fable text. `Fable 100%` in caption size with monospaced digits measured 58 points, so the line needs 108 points against a column of about 141. This is not a measurement of the installed widget; that is the user's manual check.
- **Verified while writing this plan.** The steps were first run one at a time on a scratch worktree at `697563e`: Task 1 Step 2, Task 2 Step 2 and Task 3 Step 2 failed as described, and Task 1 Step 4, Task 2 Step 4 and Task 3 Step 4 passed with the counts given. Those runs used `swift test --filter` against a bridge built with its test feature, which is the command `make swift-test` wraps. Then every "replace" in this file was extracted by a script and applied in order to a clean copy of that worktree; each quoted text matched exactly once, and the code was identical to the tree from the step runs apart from one reworded comment. On that tree the real widget build had no warning; `make swift-test` passed the whole Swift suite (880 tests, no failure); and `widget-extension-test`, `package-test`, `notarize-test` and the other shell-contract targets of `make test` passed. A README line naming the public version made `notarize-test` fail there, which is the reason for that rule in Global Constraints. Not run: `cargo test` and the vendored-crate test inside `make test`, because this plan changes no Rust file and no Rust test reads a file it changes; and CI's Xcode 16.2, which was not available locally. The repository itself was not changed.

### 5. Where the spec is silent

1. **Where the VoiceOver suffix goes.** At the end of the column's label, after the caption: "Claude, 77 percent remaining, weekly, resets in 6 days, Fable 71 percent remaining".
2. **Exactly at the reset.** A Fable reset equal to the entry's time counts as passed, the same comparison the headline uses (`WidgetPresentation.swift:186`).
3. **`Fable —` has no colour level**, even when the old percent was low.
4. **A report with Fable and no session or weekly window.** The row carries Fable and no headline, the column shows `—`, and the Fable text is hidden by the one rule. `theWidgetAcceptsWeeklyOnlyAndFableOnly` (`Tests/NeedlbarCoreTests/ClaudeUsageReportReasonTests.swift:120-131`) still passes unchanged.
5. **A deadline for hidden text.** The Fable reset joins the reload deadlines whenever the row has one, as §5 says, even in case 4. That costs at most one reload per Fable reset.
6. **The spacer** has a minimum length of 4 points, so the name and the text never touch.
7. **The 2026-11-06 design's §5** is not in the spec's list of notes. Its wording, "a reset", already covers Fable's reset; the §4 note added in Task 4 says so in one sentence.
8. **`docs/HANDOFF.md`** mentions the widget only in passing (lines 99, 149 and 184) and does not describe what it shows. Task 4 updates the checkpoint line and adds one paragraph beside the 2026-11-12 one.
9. **`README.md`** describes the widget of the public release. The Fable text is written there as prepared, not released, without a version number (see Global Constraints).

### 6. Documentation contracts

- `make notarize-test` reads `README.md` and `docs/STATUS.md`. None of the text this plan replaces is asserted there; the constraints on new text are in Global Constraints. Task 4 runs it alone before the full gate.
- The dated notes follow each document's own style: `**… (dated note, 2026-11-13):**` in the 2026-11-06 design, which already has one for the bar shape, and `> **Amendment — 2026-11-13:**` in the 2026-08-31 design, which has one for 2026-11-06. The 2026-09-02 design has no earlier amendment and gets the blockquote form.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `Sources/NeedlbarWidgetSupport/WidgetProjection.swift` | The projection, its coding and validation | `WidgetFableReading`; `WidgetQuotaRow.fable`; both decode paths; both validators (Task 1) |
| `Sources/NeedlbarCore/Widget/WidgetProjectionMapper.swift` | Store capture to projection | `fableReading`, which never throws (Task 2) |
| `Sources/NeedlbarWidgetSupport/WidgetPresentation.swift` | Every widget presentation decision | `WidgetFableText`; `WidgetQuotaColumn.fable`; label suffix; Fable reset as a deadline (Task 3) |
| `WidgetExtension/NeedlbarOverviewWidget.swift` | Layout, fonts, level to colour | The name line (Task 3) |
| `Tests/NeedlbarWidgetSupportTests/WidgetProjectionTests.swift` | Projection tests | Seven new tests and helpers (Task 1) |
| `Tests/NeedlbarCoreTests/WidgetProjectionTests.swift` | Mapper and publisher tests | One extended test, three new (Task 2) |
| `Tests/NeedlbarWidgetSupportTests/WidgetOverviewPresentationTests.swift` | Presentation tests | Nine new tests and a helper (Task 3) |
| `docs/superpowers/specs/2026-11-06-glanceable-overview-widget-design.md`, `docs/superpowers/specs/2026-08-31-needlbar-v0.2.1-widgets-notifications-design.md`, `docs/superpowers/specs/2026-09-02-claude-fable-quota-design.md` | Earlier designs | Dated notes (Task 4) |
| `README.md`, `docs/HANDOFF.md`, `docs/STATUS.md` | Current descriptions and records | Updated (Task 4) |

No file is created. Untouched: every script, `Package.swift`, the extension's Info.plist and entitlements, `WidgetProjectionPublisher.swift`, `HeadlineQuotaSelector.swift`, `docs/architecture.md`, `docs/privacy.md`, the acceptance fixtures, and every Rust file.

---

### Task 1: An optional Fable reading in the projection

**Files:**
- Modify: `Sources/NeedlbarWidgetSupport/WidgetProjection.swift:47-89,311-316,349-354,390-392`
- Test: `Tests/NeedlbarWidgetSupportTests/WidgetProjectionTests.swift:267-269,288`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `public struct WidgetFableReading: Codable, Sendable, Equatable { public let remainingPercent: Double; public let resetsAt: Date? }`
  - `public init(remainingPercent: Double, resetsAt: Date?)` on it
  - `public func isValid(for provider: WidgetProvider, lastSuccessfulAt: Date?) -> Bool` on it
  - `public let fable: WidgetFableReading?` on `WidgetQuotaRow`
  - `WidgetQuotaRow.init(provider:stream:lastSuccessfulAt:headline:fable:) throws`, where `fable` defaults to `nil`, so every existing call compiles unchanged
  - The JSON key `fable` on a quota row, an object with `remainingPercent` and an optional `resetsAt`

- [ ] **Step 1: Write the failing tests**

In `Tests/NeedlbarWidgetSupportTests/WidgetProjectionTests.swift`, replace

```swift
        #expect(WidgetPresentation.freshness(.stale, lastSuccessfulAt: referenceDate, now: referenceDate) == .stale)
    }
}
```

with

```swift
        #expect(WidgetPresentation.freshness(.stale, lastSuccessfulAt: referenceDate, now: referenceDate) == .stale)
    }

    // MARK: Fable reading

    @Test
    func aFableReadingRoundTripsWithAndWithoutAReset() throws {
        let readings = [
            WidgetFableReading(remainingPercent: 71.5, resetsAt: referenceDate.addingTimeInterval(3_600)),
            WidgetFableReading(remainingPercent: 71.5, resetsAt: nil),
        ]
        for reading in readings {
            let projection = try fableProjection(claude: claudeRow(fable: reading))
            let decoded = try WidgetProjection.decode(WidgetProjection.encode(projection), referenceDate: referenceDate)
            #expect(decoded == projection)
            #expect(decoded.quotaRows[0].fable == reading)
            #expect(decoded.quotaRows[1].fable == nil)

            // The row's own coding, which the projection decoder does not use.
            let row = try JSONDecoder().decode(WidgetQuotaRow.self, from: JSONEncoder().encode(projection.quotaRows[0]))
            #expect(row.fable == reading)
        }
    }

    @Test
    func aFileWithoutFableOrWithANullFableDecodesAsNoValue() throws {
        let withoutKey = try WidgetProjection.decode(document(), referenceDate: referenceDate)
        #expect(withoutKey.quotaRows[0].fable == nil)
        #expect(withoutKey.quotaRows[0].headline?.remainingPercent == 77)

        let null = try WidgetProjection.decode(document(claude: claudeRowJSON + ",\"fable\":null"), referenceDate: referenceDate)
        #expect(null.quotaRows[0].fable == nil)

        let present = try WidgetProjection.decode(document(claude: claudeRowJSON + fableJSON), referenceDate: referenceDate)
        #expect(present.quotaRows[0].fable
            == WidgetFableReading(remainingPercent: 71, resetsAt: referenceDate.addingTimeInterval(3_600)))
    }

    /// Schema version 1 is kept on the strength of this: a reader ignores a key it does not know.
    @Test
    func anUnknownKeyOnAQuotaRowIsIgnored() throws {
        let extraKeys = ",\"later\":{\"remainingPercent\":5},\"fable\":{\"remainingPercent\":71,\"resetsAt\":null,\"label\":\"x\"}"
        let decoded = try WidgetProjection.decode(document(claude: claudeRowJSON + extraKeys), referenceDate: referenceDate)
        #expect(decoded.quotaRows[0].headline?.remainingPercent == 77)
        #expect(decoded.quotaRows[0].fable == WidgetFableReading(remainingPercent: 71, resetsAt: nil))

        let row = try JSONDecoder().decode(
            WidgetQuotaRow.self,
            from: Data(#"{"provider":"claude","stream":"fresh","lastSuccessfulAt":0,"later":1,"fable":{"remainingPercent":71,"label":"x"}}"#.utf8)
        )
        #expect(row.fable == WidgetFableReading(remainingPercent: 71, resetsAt: nil))
    }

    @Test
    func aProjectionWithoutFableEncodesExactlyAsBefore() throws {
        let projection = try fableProjection(claude: claudeRow(fable: nil))
        let encoded = String(decoding: try WidgetProjection.encode(projection), as: UTF8.self)
        #expect(!encoded.contains("fable"))
        // The bytes the code before this change wrote for the same projection.
        #expect(encoded == #"{"quotaRows":[{"headline":{"id":"claude.weekly","remainingPercent":77},"lastSuccessfulAt":"2027-01-15T08:00:00Z","provider":"claude","stream":"fresh"},{"provider":"codex","stream":"unavailable"}],"schemaVersion":1,"today":{"completeness":"unavailable"},"usageRows":[{"provider":"claude","stream":"unavailable"},{"provider":"codex","stream":"unavailable"},{"provider":"cursor","stream":"unavailable"}]}"#)

        let withFable = try fableProjection(claude: claudeRow(fable: WidgetFableReading(remainingPercent: 71, resetsAt: nil)))
        #expect(String(decoding: try WidgetProjection.encode(withFable), as: UTF8.self)
            .contains(#""fable":{"remainingPercent":71},"headline""#))
    }

    @Test
    func fableIsRejectedOffTheClaudeRowOutOfRangeOrWithoutALastSuccessfulTime() {
        let valid = WidgetFableReading(remainingPercent: 71, resetsAt: nil)
        #expect(throws: WidgetProjectionError.invalidQuotaRow) {
            try WidgetQuotaRow(provider: .codex, stream: .fresh, lastSuccessfulAt: referenceDate, headline: nil, fable: valid)
        }
        #expect(throws: WidgetProjectionError.invalidQuotaRow) {
            try WidgetQuotaRow(provider: .claude, stream: .unavailable, lastSuccessfulAt: nil, headline: nil, fable: valid)
        }
        for percent in [101, -1, Double.nan, .infinity] {
            #expect(throws: WidgetProjectionError.invalidQuotaRow) {
                try claudeRow(fable: WidgetFableReading(remainingPercent: percent, resetsAt: nil))
            }
        }
        for reset in [Double.nan, .infinity, -.infinity] {
            #expect(throws: WidgetProjectionError.invalidQuotaRow) {
                try claudeRow(fable: WidgetFableReading(remainingPercent: 71, resetsAt: Date(timeIntervalSinceReferenceDate: reset)))
            }
        }
    }

    @Test
    func aFileWithAnInvalidFableIsRejectedLikeAnyOtherInvalidRow() {
        let onCodex = document(codex: codexRowJSON + fableJSON)
        let tooHigh = document(claude: claudeRowJSON + ",\"fable\":{\"remainingPercent\":101,\"resetsAt\":null}")
        let negative = document(claude: claudeRowJSON + ",\"fable\":{\"remainingPercent\":-1,\"resetsAt\":null}")
        let withoutLastSuccess = document(
            claude: #""provider":"claude","stream":"unavailable","lastSuccessfulAt":null,"headline":null"# + fableJSON
        )
        for bytes in [onCodex, tooHigh, negative, withoutLastSuccess] {
            #expect(throws: WidgetProjectionError.invalidQuotaRow) {
                try WidgetProjection.decode(bytes, referenceDate: referenceDate)
            }
        }
    }

    @Test
    func aStaleRowKeepsItsFable() throws {
        let reading = WidgetFableReading(remainingPercent: 0, resetsAt: referenceDate.addingTimeInterval(-60))
        let projection = try fableProjection(claude: claudeRow(stream: .stale, fable: reading))
        let decoded = try WidgetProjection.decode(WidgetProjection.encode(projection), referenceDate: referenceDate)
        #expect(decoded.quotaRows[0].stream == .stale)
        #expect(decoded.quotaRows[0].fable == reading)
        #expect(WidgetFableReading(remainingPercent: 100, resetsAt: nil).isValid(for: .claude, lastSuccessfulAt: referenceDate))
    }
}
```

In `Tests/NeedlbarWidgetSupportTests/WidgetProjectionTests.swift`, replace

```swift
private func makeUnavailableUsageRows() -> [WidgetUsageRow] {
```

with

```swift
private func claudeRow(stream: WidgetStreamState = .fresh, fable: WidgetFableReading?) throws -> WidgetQuotaRow {
    try WidgetQuotaRow(
        provider: .claude,
        stream: stream,
        lastSuccessfulAt: referenceDate,
        headline: WidgetQuotaHeadline(id: .claudeWeekly, remainingPercent: 77, resetsAt: nil),
        fable: fable
    )
}

private func fableProjection(claude: WidgetQuotaRow) throws -> WidgetProjection {
    try WidgetProjection(
        quotaRows: [claude, try WidgetQuotaRow(provider: .codex, stream: .unavailable, lastSuccessfulAt: nil, headline: nil)],
        usageRows: makeUnavailableUsageRows(),
        today: unavailableToday
    )
}

// `referenceDate` is 2027-01-15T08:00:00Z.
private let claudeRowJSON = #""provider":"claude","stream":"fresh","lastSuccessfulAt":"2027-01-15T08:00:00Z","headline":{"id":"claude.weekly","remainingPercent":77,"resetsAt":null}"#
private let codexRowJSON = #""provider":"codex","stream":"fresh","lastSuccessfulAt":"2027-01-15T08:00:00Z","headline":{"id":"codex.primary","remainingPercent":85,"resetsAt":null}"#
private let fableJSON = #","fable":{"remainingPercent":71,"resetsAt":"2027-01-15T09:00:00Z"}"#

/// A whole projection file whose two quota rows are the given JSON members, without braces.
private func document(claude: String = claudeRowJSON, codex: String = codexRowJSON) -> Data {
    let usage = ["claude", "codex", "cursor"].map {
        "{\"provider\":\"\($0)\",\"stream\":\"unavailable\",\"localDayKey\":null,\"utcOffsetSeconds\":null,\"lastSuccessfulAt\":null,\"todayTokens\":null,\"todayCostUSD\":null}"
    }.joined(separator: ",")
    let text = "{\"schemaVersion\":1,\"quotaRows\":[{" + claude + "},{" + codex + "}],\"usageRows\":[" + usage
        + "],\"today\":{\"completeness\":\"unavailable\",\"totalTokens\":null,\"estimatedCostUSD\":null}}"
    return Data(text.utf8)
}

private func makeUnavailableUsageRows() -> [WidgetUsageRow] {
```

What the tests cover from spec §6: a round trip with Fable, and with Fable and no reset; an old file without the key, a `null`, and an unknown extra key; no key when there is no value; the rejections (Codex row, 101, −1, NaN and a non-finite reset through the initializer, no last successful time); and an accepted stale row.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make swift-test SWIFT_TEST_FILTER=WidgetProjection`
Expected: the build fails with `error: cannot find type 'WidgetFableReading' in scope`, and make ends with `make: *** [swift-test] Error 1`. `anUnknownKeyOnAQuotaRowIsIgnored` would pass on today's decoder if it compiled; it is the guard for schema version 1 (Decisions 2), and it cannot compile until the type exists.

- [ ] **Step 3: Write the implementation**

In `Sources/NeedlbarWidgetSupport/WidgetProjection.swift`, replace

```swift
public struct WidgetQuotaRow: Codable, Sendable, Equatable {
    public let provider: WidgetProvider
    public let stream: WidgetStreamState
    public let lastSuccessfulAt: Date?
    public let headline: WidgetQuotaHeadline?

    public init(
        provider: WidgetProvider,
        stream: WidgetStreamState,
        lastSuccessfulAt: Date?,
        headline: WidgetQuotaHeadline?
    ) throws {
        guard provider != .cursor, headline.map({ $0.id.provider == provider }) ?? true else {
            throw WidgetProjectionError.invalidQuotaRow
        }
        self.provider = provider
        self.stream = stream
        self.lastSuccessfulAt = lastSuccessfulAt
        self.headline = headline
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case stream
        case lastSuccessfulAt
        case headline
    }
```

with

```swift
/// The remaining Fable percent, shown as secondary text on the Claude column. It has no
/// window ID and no timestamp of its own: it comes from the same report as the Claude
/// headline, so the row's freshness and last successful time apply to it.
public struct WidgetFableReading: Codable, Sendable, Equatable {
    public let remainingPercent: Double
    public let resetsAt: Date?

    public init(remainingPercent: Double, resetsAt: Date?) {
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
    }

    /// Whether a quota row for `provider` with this last successful time may carry the
    /// reading. The row, the projection and the app's mapper all use this one rule.
    public func isValid(for provider: WidgetProvider, lastSuccessfulAt: Date?) -> Bool {
        provider == .claude
            && lastSuccessfulAt != nil
            && remainingPercent.isFinite
            && (0...100).contains(remainingPercent)
            && (resetsAt?.timeIntervalSinceReferenceDate.isFinite ?? true)
    }
}

public struct WidgetQuotaRow: Codable, Sendable, Equatable {
    public let provider: WidgetProvider
    public let stream: WidgetStreamState
    public let lastSuccessfulAt: Date?
    public let headline: WidgetQuotaHeadline?
    /// Only on the Claude row. `nil` encodes as no key, as before the field existed.
    public let fable: WidgetFableReading?

    public init(
        provider: WidgetProvider,
        stream: WidgetStreamState,
        lastSuccessfulAt: Date?,
        headline: WidgetQuotaHeadline?,
        fable: WidgetFableReading? = nil
    ) throws {
        guard provider != .cursor,
              headline.map({ $0.id.provider == provider }) ?? true,
              fable.map({ $0.isValid(for: provider, lastSuccessfulAt: lastSuccessfulAt) }) ?? true else {
            throw WidgetProjectionError.invalidQuotaRow
        }
        self.provider = provider
        self.stream = stream
        self.lastSuccessfulAt = lastSuccessfulAt
        self.headline = headline
        self.fable = fable
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case stream
        case lastSuccessfulAt
        case headline
        case fable
    }
```

The row's own decoder. In `Sources/NeedlbarWidgetSupport/WidgetProjection.swift`, replace

```swift
            lastSuccessfulAt: try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulAt),
            headline: headline
        )
    }
}
```

with

```swift
            lastSuccessfulAt: try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulAt),
            headline: headline,
            fable: try container.decodeIfPresent(WidgetFableReading.self, forKey: .fable)
        )
    }
}
```

The raw row the projection decoder reads. In `Sources/NeedlbarWidgetSupport/WidgetProjection.swift`, replace

```swift
        let lastSuccessfulAt: Date?
        let headline: RawQuotaHeadline?
    }
```

with

```swift
        let lastSuccessfulAt: Date?
        let headline: RawQuotaHeadline?
        let fable: WidgetFableReading?
    }
```

In `Sources/NeedlbarWidgetSupport/WidgetProjection.swift`, replace

```swift
                lastSuccessfulAt: row.lastSuccessfulAt,
                headline: headline
            )
        }
```

with

```swift
                lastSuccessfulAt: row.lastSuccessfulAt,
                headline: headline,
                fable: row.fable
            )
        }
```

The projection's validation. In `Sources/NeedlbarWidgetSupport/WidgetProjection.swift`, replace

```swift
                  row.headline == nil || row.lastSuccessfulAt != nil else {
                throw WidgetProjectionError.invalidQuotaRow
            }
```

with

```swift
                  row.headline == nil || row.lastSuccessfulAt != nil,
                  row.fable.map({ $0.isValid(for: row.provider, lastSuccessfulAt: row.lastSuccessfulAt) }) ?? true else {
                throw WidgetProjectionError.invalidQuotaRow
            }
```

`WidgetProjection.schemaVersion` stays `1`, and `WidgetQuotaWindowID` is untouched.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make swift-test SWIFT_TEST_FILTER=WidgetProjection`
Expected: `Test run with 22 tests in 1 suite passed` (the support target: 15 existing and 7 new) and `Test run with 14 tests in 1 suite passed` (the core target, unchanged), and make exits 0.

- [ ] **Step 5: Commit**

```bash
git add Sources/NeedlbarWidgetSupport/WidgetProjection.swift Tests/NeedlbarWidgetSupportTests/WidgetProjectionTests.swift
git commit -m "feat(widget): carry an optional Fable reading in the projection" \
  -m "The Claude quota row gains an optional fable reading with the remaining percent and an optional reset time. The schema version stays 1: readers ignore keys they do not know, and a projection without Fable encodes as before." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The mapper copies Fable and never throws for it

**Files:**
- Modify: `Sources/NeedlbarCore/Widget/WidgetProjectionMapper.swift:46-47`
- Test: `Tests/NeedlbarCoreTests/WidgetProjectionTests.swift:62-64`

**Interfaces:**
- Consumes, from Task 1: `WidgetFableReading(remainingPercent: Double, resetsAt: Date?)`, `WidgetFableReading.isValid(for: WidgetProvider, lastSuccessfulAt: Date?) -> Bool`, `WidgetQuotaRow.init(provider:stream:lastSuccessfulAt:headline:fable:) throws`, `WidgetQuotaRow.fable`. Existing: `QuotaWindow.claudeFableWeeklyID` (`"claude.fable.weekly"`, `Sources/NeedlbarCore/Models/QuotaSnapshot.swift:54`), `QuotaWindow.remainingPercent`, `QuotaWindow.resetsAt`, `WidgetProviderCapture.quota` and `.quotaLastSuccessfulAt`.
- Produces: `WidgetProjectionMapper.map(_:)` returns a projection whose Claude row has `fable` set when the direct quota snapshot holds exactly one valid `claude.fable.weekly` window. No signature changes.

- [ ] **Step 1: Write the tests**

In `Tests/NeedlbarCoreTests/WidgetProjectionTests.swift`, replace

```swift
    #expect(projection.quotaRows[0].headline?.id == .claudeSession)
    #expect(projection.quotaRows[1].headline?.id == .codexPrimary)
}
```

with

```swift
    #expect(projection.quotaRows[0].headline?.id == .claudeSession)
    #expect(projection.quotaRows[1].headline?.id == .codexPrimary)
    // Fable is lower than every allowlisted window and still never becomes the headline.
    #expect(projection.quotaRows[0].headline?.remainingPercent == 20)
    #expect(projection.quotaRows[0].fable == WidgetFableReading(remainingPercent: 0, resetsAt: now.addingTimeInterval(3600)))
    #expect(projection.quotaRows[1].fable == nil)
}

@Test func mapperCopiesFableWithoutAResetTime() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let claudeQuota = QuotaSnapshot(windows: [
        try QuotaWindow(id: "claude.weekly", title: "private", usedPercent: 23, resetsAt: now.addingTimeInterval(3600)),
        try QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "private", usedPercent: 29, resetsAt: nil),
    ])
    let row = try WidgetProjectionMapper(now: now).map(makeWidgetCapture(now: now, claudeQuota: claudeQuota)).quotaRows[0]
    #expect(row.headline?.id == .claudeWeekly)
    #expect(row.fable == WidgetFableReading(remainingPercent: 71, resetsAt: nil))
}

@Test func mapperDropsFableWithoutThrowingWhenItCannotBeCarried() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let reset = now.addingTimeInterval(3600)
    let weekly = try QuotaWindow(id: "claude.weekly", title: "private", usedPercent: 23, resetsAt: reset)
    func fable(usedPercent: Double = 29, resetsAt: Date?) throws -> QuotaWindow {
        try QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "private", usedPercent: usedPercent, resetsAt: resetsAt)
    }
    let cases: [[QuotaWindow]] = [
        [weekly],
        [weekly, try fable(resetsAt: reset), try fable(usedPercent: 40, resetsAt: reset)],
        [weekly, try fable(resetsAt: Date(timeIntervalSinceReferenceDate: .infinity))],
        [weekly, try fable(resetsAt: Date(timeIntervalSinceReferenceDate: .nan))],
    ]
    for windows in cases {
        let capture = try makeWidgetCapture(now: now, claudeQuota: QuotaSnapshot(windows: windows))
        let row = try WidgetProjectionMapper(now: now).map(capture).quotaRows[0]
        #expect(row.headline?.id == .claudeWeekly)
        #expect(row.fable == nil)
    }

    // A quota value with no last successful time: the row can carry neither a headline nor Fable.
    let fableOnly = QuotaSnapshot(windows: [try fable(resetsAt: reset)])
    let base = try makeWidgetCapture(now: now)
    let undated = WidgetStoreCapture(exportedAt: now, providers: base.providers.map { value in
        guard value.provider == .claude else { return value }
        return WidgetProviderCapture(
            provider: .claude,
            usage: value.usage,
            quota: fableOnly,
            usageStatus: value.usageStatus,
            quotaStatus: .unavailable,
            usageLastSuccessfulAt: value.usageLastSuccessfulAt,
            quotaLastSuccessfulAt: nil,
            usageDayProvenance: value.usageDayProvenance
        )
    })
    let undatedRow = try WidgetProjectionMapper(now: now).map(undated).quotaRows[0]
    #expect(undatedRow.lastSuccessfulAt == nil)
    #expect(undatedRow.headline == nil)
    #expect(undatedRow.fable == nil)
}

@Test func mapperIgnoresAFableWindowInTheCodexSnapshot() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let codexQuota = QuotaSnapshot(windows: [
        try QuotaWindow(id: "codex.primary", title: "private", usedPercent: 50, resetsAt: now.addingTimeInterval(3600)),
        try QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "private", usedPercent: 29, resetsAt: now.addingTimeInterval(3600)),
    ])
    let projection = try WidgetProjectionMapper(now: now).map(makeWidgetCapture(now: now, codexQuota: codexQuota))
    #expect(projection.quotaRows[1].headline?.id == .codexPrimary)
    #expect(projection.quotaRows[1].fable == nil)
    #expect(projection.quotaRows[0].fable == nil)
}
```

The first block extends `mapperFiltersProviderAndBreaksHeadlineTiesByLexicalID`, whose Claude snapshot already has a Fable window at 100 percent used (line 53). `100 - 29` is exactly 71 in floating point, so the copied value compares equal.

- [ ] **Step 2: Run the tests to verify the two copying tests fail**

Run: `make swift-test SWIFT_TEST_FILTER=WidgetProjection`
Expected: FAIL in `mapperCopiesFableWithoutAResetTime()` and `mapperFiltersProviderAndBreaksHeadlineTiesByLexicalID()` only, one issue each: `Expectation failed: row.fable == WidgetFableReading(remainingPercent: 71, resetsAt: nil)` and `Expectation failed: projection.quotaRows[0].fable == WidgetFableReading(remainingPercent: 0, resetsAt: now.addingTimeInterval(3600))`. The support target's line says `Test run with 22 tests in 1 suite passed`; the core target's says `Test run with 17 tests in 1 suite failed` and `with 2 issues`; make ends with `make: *** [swift-test] Error 1`. `mapperDropsFableWithoutThrowingWhenItCannotBeCarried()` and `mapperIgnoresAFableWindowInTheCodexSnapshot()` pass already, because nothing sets Fable yet; they guard the next step against a mapper that copies without checking (Decisions 4).

- [ ] **Step 3: Write the implementation**

In `Sources/NeedlbarCore/Widget/WidgetProjectionMapper.swift`, replace

```swift
        return try .init(provider: provider, stream: stream, lastSuccessfulAt: capture.quotaLastSuccessfulAt, headline: candidates.first)
    }
```

with

```swift
        return try .init(
            provider: provider,
            stream: stream,
            lastSuccessfulAt: capture.quotaLastSuccessfulAt,
            headline: candidates.first,
            fable: fableReading(capture, provider: provider)
        )
    }

    /// Fable is secondary text, so anything wrong with it drops it and never throws: the
    /// publisher maps with `try?`, and a thrown error would stop every widget update.
    private func fableReading(_ capture: WidgetProviderCapture, provider: WidgetProvider) -> WidgetFableReading? {
        let windows = (capture.quota?.windows ?? []).filter { $0.id == QuotaWindow.claudeFableWeeklyID }
        guard provider == .claude, windows.count == 1 else { return nil }
        let reading = WidgetFableReading(remainingPercent: windows[0].remainingPercent, resetsAt: windows[0].resetsAt)
        return reading.isValid(for: provider, lastSuccessfulAt: capture.quotaLastSuccessfulAt) ? reading : nil
    }
```

The headline candidates above this line are unchanged: they still come only from `WidgetQuotaWindowID`, which has no Fable case, so Fable cannot become the headline.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make swift-test SWIFT_TEST_FILTER=WidgetProjection`
Expected: `Test run with 22 tests in 1 suite passed` and `Test run with 17 tests in 1 suite passed` (14 existing and 3 new), and make exits 0.

- [ ] **Step 5: Commit**

```bash
git add Sources/NeedlbarCore/Widget/WidgetProjectionMapper.swift Tests/NeedlbarCoreTests/WidgetProjectionTests.swift
git commit -m "feat(widget): map the Claude Fable window into the projection" \
  -m "The mapper copies claude.fable.weekly onto the Claude row and drops it, without throwing, when there are no or several such windows, the reset is not finite, or the row has no last successful time. The headline allowlist is unchanged." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The Fable text, its colour, its VoiceOver suffix, its reload deadline and the name line

**Files:**
- Modify: `Sources/NeedlbarWidgetSupport/WidgetPresentation.swift:50-61,230-242,312-313,321`
- Modify: `WidgetExtension/NeedlbarOverviewWidget.swift:113-117`
- Test: `Tests/NeedlbarWidgetSupportTests/WidgetOverviewPresentationTests.swift:212,271-272,301-308`

**Interfaces:**
- Consumes, from Task 1: `WidgetQuotaRow.fable: WidgetFableReading?`, `WidgetFableReading.remainingPercent`, `.resetsAt`. Existing: `WidgetPresentation.wholePercent(_:) -> Int?`, `WidgetPresentation.remainingLevel(percent:) -> WidgetRemainingLevel`, `WidgetRemainingLevel` (`.normal`, `.low`, `.critical`).
- Produces:
  - `public struct WidgetFableText: Equatable, Sendable { public let text: String; public let level: WidgetRemainingLevel? }`
  - `public let fable: WidgetFableText?` on `WidgetQuotaColumn`, and an internal initializer `WidgetQuotaColumn(title:figure:fraction:level:isDimmed:detail:fable:accessibilityLabel:)` where `fable` defaults to `nil`
  - `WidgetPresentation.quotaColumn(for:in:now:calendar:locale:)` sets `fable` and appends the suffix to `accessibilityLabel`; its signature is unchanged
  - `WidgetPresentation.nextDeadline(after:projection:calendar:)` also considers a future Fable reset; its signature is unchanged

- [ ] **Step 1: Write the failing tests**

In `Tests/NeedlbarWidgetSupportTests/WidgetOverviewPresentationTests.swift`, replace

```swift
    // MARK: Footer
```

with

```swift
    // MARK: Fable text

    @Test
    func theFableTextShowsTheWholePercentBesideAFreshFigure() throws {
        for resetIn in [6 * day, nil] as [TimeInterval?] {
            let projection = try overview(claude: quota(
                .claude, age: minute, headline: weekly(77, resetIn: 6 * day + 3 * hour), fable: fable(71.4, resetIn: resetIn)
            ))
            #expect(column(.claude, projection) == WidgetQuotaColumn(
                title: "Claude",
                figure: "77%",
                fraction: 0.77,
                level: .normal,
                isDimmed: false,
                detail: "Weekly · resets in 6d",
                fable: WidgetFableText(text: "Fable 71%", level: .normal),
                accessibilityLabel: "Claude, 77 percent remaining, weekly, resets in 6 days, Fable 71 percent remaining"
            ))
            #expect(column(.codex, projection).fable == nil)
        }
    }

    @Test
    func theFableTextIsShownAsReportedEvenAboveTheHeadline() throws {
        let projection = try overview(claude: quota(.claude, age: minute, headline: weekly(12, resetIn: day), fable: fable(90, resetIn: day)))
        let value = column(.claude, projection)
        #expect(value.figure == "12%")
        #expect(value.level == .low)
        #expect(value.fable == WidgetFableText(text: "Fable 90%", level: .normal))
    }

    @Test
    func aStaleColumnKeepsTheFableTextAndTheCaptionCarriesTheAge() throws {
        let age = 20 * minute
        let projection = try overview(claude: quota(.claude, age: age, headline: weekly(77, resetIn: day), fable: fable(71, resetIn: day)))
        let time = shortText(referenceDate.addingTimeInterval(-age), includingDate: false)
        let value = column(.claude, projection)
        #expect(value.detail == "Last checked \(time)")
        #expect(value.fable == WidgetFableText(text: "Fable 71%", level: .normal))
        #expect(value.accessibilityLabel == "Claude, 77 percent remaining, last checked \(time), Fable 71 percent remaining")
    }

    @Test
    func aPassedHeadlineResetDimsTheFigureButNotTheFableText() throws {
        let projection = try overview(claude: quota(.claude, age: minute, headline: weekly(77, resetIn: -1), fable: fable(71, resetIn: day)))
        let value = column(.claude, projection)
        #expect(value.isDimmed)
        #expect(value.detail == "Awaiting fresh reading")
        #expect(value.fable == WidgetFableText(text: "Fable 71%", level: .normal))
        #expect(value.accessibilityLabel == "Claude, 77 percent remaining, awaiting fresh reading, Fable 71 percent remaining")
    }

    @Test
    func aPassedFableResetShowsADashWhateverTheHeadlineState() throws {
        let awaiting = WidgetFableText(text: "Fable —", level: nil)
        // A low value, so a colour here would mean the old percent was still judged.
        let fresh = try overview(claude: quota(.claude, age: minute, headline: weekly(77, resetIn: day), fable: fable(5, resetIn: -1)))
        #expect(column(.claude, fresh).fable == awaiting)
        #expect(column(.claude, fresh).accessibilityLabel
            == "Claude, 77 percent remaining, weekly, resets in 1 day, Fable awaiting fresh reading")

        let exactlyAtTheReset = try overview(claude: quota(.claude, age: minute, headline: weekly(77, resetIn: day), fable: fable(5, resetIn: 0)))
        #expect(column(.claude, exactlyAtTheReset).fable == awaiting)

        let stale = try overview(claude: quota(.claude, age: hour, headline: weekly(77, resetIn: day), fable: fable(5, resetIn: -1)))
        #expect(column(.claude, stale).fable == awaiting)
        #expect(column(.claude, stale).accessibilityLabel.hasSuffix(", Fable awaiting fresh reading"))

        let bothPassed = try overview(claude: quota(.claude, age: minute, headline: weekly(77, resetIn: -1), fable: fable(5, resetIn: -1)))
        #expect(column(.claude, bothPassed).fable == awaiting)
        #expect(column(.claude, bothPassed).accessibilityLabel
            == "Claude, 77 percent remaining, awaiting fresh reading, Fable awaiting fresh reading")
    }

    @Test
    func theFableTextIsHiddenWithoutAValueOrWithoutAFigure() throws {
        let withoutFable = try overview(claude: quota(.claude, age: minute, headline: weekly(77, resetIn: day)))
        #expect(column(.claude, withoutFable).fable == nil)
        #expect(column(.claude, withoutFable).accessibilityLabel == "Claude, 77 percent remaining, weekly, resets in 1 day")

        #expect(column(.claude, nil).fable == nil)

        // The column shows a dash: no headline, or a last successful time after now.
        let withoutHeadline = try overview(claude: quota(.claude, age: minute, headline: nil, fable: fable(71, resetIn: day)))
        #expect(column(.claude, withoutHeadline).figure == "—")
        #expect(column(.claude, withoutHeadline).fable == nil)
        #expect(column(.claude, withoutHeadline).accessibilityLabel == "Claude, quota unavailable")
        let future = try overview(claude: quota(.claude, age: -minute, headline: weekly(77, resetIn: day), fable: fable(71, resetIn: day)))
        #expect(column(.claude, future).figure == "—")
        #expect(column(.claude, future).fable == nil)
    }

    @Test
    func theFableColourFollowsTheShownWholePercent() throws {
        func shown(_ remaining: Double) throws -> WidgetFableText? {
            let projection = try overview(claude: quota(.claude, age: minute, headline: weekly(77, resetIn: day), fable: fable(remaining, resetIn: day)))
            return column(.claude, projection).fable
        }
        #expect(try shown(99.6) == WidgetFableText(text: "Fable 100%", level: .normal))
        #expect(try shown(19.5) == WidgetFableText(text: "Fable 20%", level: .normal))
        #expect(try shown(19.4) == WidgetFableText(text: "Fable 19%", level: .low))
        #expect(try shown(9.5) == WidgetFableText(text: "Fable 10%", level: .low))
        #expect(try shown(9.4) == WidgetFableText(text: "Fable 9%", level: .critical))
        #expect(try shown(0.4) == WidgetFableText(text: "Fable 0%", level: .critical))
    }

    // MARK: Footer
```

In `Tests/NeedlbarWidgetSupportTests/WidgetOverviewPresentationTests.swift`, replace

```swift
    @Test
    func theNextReloadIsNeverSoonerThanOneMinute() throws {
```

with

```swift
    @Test
    func aFutureFableResetIsAReloadDeadlineAndAPassedOneIsNot() throws {
        // No headline reset, so the only other deadline is the 20-minute freshness boundary.
        let ahead = try overview(claude: quota(.claude, age: 0, headline: weekly(77, resetIn: nil), fable: fable(71, resetIn: 10 * minute)))
        #expect(nextReload(ahead) == referenceDate.addingTimeInterval(10 * minute))
        let passed = try overview(claude: quota(.claude, age: 0, headline: weekly(77, resetIn: nil), fable: fable(71, resetIn: -minute)))
        #expect(nextReload(passed) == referenceDate.addingTimeInterval(20 * minute))
        let none = try overview(claude: quota(.claude, age: 0, headline: weekly(77, resetIn: nil), fable: fable(71, resetIn: nil)))
        #expect(nextReload(none) == referenceDate.addingTimeInterval(20 * minute))
    }

    @Test
    func theFableResetAddsNoCountdownStep() throws {
        // A headline reset 2 h 10 min away adds a step at 10 minutes; the same Fable reset must not.
        let projection = try overview(claude: quota(.claude, age: 0, headline: weekly(77, resetIn: nil), fable: fable(71, resetIn: 2 * hour + 10 * minute)))
        #expect(nextReload(projection) == referenceDate.addingTimeInterval(20 * minute))
    }

    @Test
    func theNextReloadIsNeverSoonerThanOneMinute() throws {
```

In `Tests/NeedlbarWidgetSupportTests/WidgetOverviewPresentationTests.swift`, replace

```swift
private func quota(
    _ provider: WidgetProvider,
    age: TimeInterval,
    stream: WidgetStreamState = .fresh,
    headline: WidgetQuotaHeadline?
) throws -> WidgetQuotaRow {
    try WidgetQuotaRow(provider: provider, stream: stream, lastSuccessfulAt: referenceDate.addingTimeInterval(-age), headline: headline)
}
```

with

```swift
private func fable(_ remaining: Double, resetIn seconds: TimeInterval?) -> WidgetFableReading {
    WidgetFableReading(remainingPercent: remaining, resetsAt: seconds.map { referenceDate.addingTimeInterval($0) })
}

private func quota(
    _ provider: WidgetProvider,
    age: TimeInterval,
    stream: WidgetStreamState = .fresh,
    headline: WidgetQuotaHeadline?,
    fable: WidgetFableReading? = nil
) throws -> WidgetQuotaRow {
    try WidgetQuotaRow(
        provider: provider,
        stream: stream,
        lastSuccessfulAt: referenceDate.addingTimeInterval(-age),
        headline: headline,
        fable: fable
    )
}
```

The tests cover each row of the spec's state table. The Codex row of the table needs no test of its own: Task 1 proved such a row cannot be built, and the first test here checks that the Codex column carries no text while Claude's does.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make swift-test SWIFT_TEST_FILTER=NeedlbarWidgetSupportTests`
Expected: the build fails with `error: cannot find 'WidgetFableText' in scope`, `error: value of type 'WidgetQuotaColumn' has no member 'fable'` and `error: extra argument 'fable' in call`, and make ends with `make: *** [swift-test] Error 1`. `theFableResetAddsNoCountdownStep` would pass on today's `nextDeadline` if it compiled; it guards the next step against treating Fable's reset like a headline's.

- [ ] **Step 3: Write the presentation**

In `Sources/NeedlbarWidgetSupport/WidgetPresentation.swift`, replace

```swift
/// Everything the widget draws for one provider column.
public struct WidgetQuotaColumn: Equatable, Sendable {
    public let title: String
    public let figure: String
    /// Bar fill from 0 to 1. `nil` draws an empty track.
    public let fraction: Double?
    /// `nil` means no colour.
    public let level: WidgetRemainingLevel?
    public let isDimmed: Bool
    public let detail: String
    public let accessibilityLabel: String
}
```

with

```swift
/// The small Fable text at the right end of the Claude column's name line.
public struct WidgetFableText: Equatable, Sendable {
    /// `Fable 71%`, or `Fable —` once Fable's own reset has passed.
    public let text: String
    /// The level of the shown percent, or `nil` for the dash. Low is orange and critical is
    /// red; anything else uses the secondary colour.
    public let level: WidgetRemainingLevel?
}

/// Everything the widget draws for one provider column.
public struct WidgetQuotaColumn: Equatable, Sendable {
    public let title: String
    public let figure: String
    /// Bar fill from 0 to 1. `nil` draws an empty track.
    public let fraction: Double?
    /// `nil` means no colour.
    public let level: WidgetRemainingLevel?
    public let isDimmed: Bool
    public let detail: String
    /// `nil` hides the text: no Fable value, or the column shows no figure.
    public let fable: WidgetFableText?
    public let accessibilityLabel: String

    init(
        title: String,
        figure: String,
        fraction: Double?,
        level: WidgetRemainingLevel?,
        isDimmed: Bool,
        detail: String,
        fable: WidgetFableText? = nil,
        accessibilityLabel: String
    ) {
        self.title = title
        self.figure = figure
        self.fraction = fraction
        self.level = level
        self.isDimmed = isDimmed
        self.detail = detail
        self.fable = fable
        self.accessibilityLabel = accessibilityLabel
    }
}
```

In `Sources/NeedlbarWidgetSupport/WidgetPresentation.swift`, replace

```swift
        guard let percent = wholePercent(headline.remainingPercent) else {
            return unavailableColumn(title: title)
        }
        return WidgetQuotaColumn(
            title: title,
            figure: "\(percent)%",
            fraction: min(max(headline.remainingPercent, 0), 100) / 100,
            level: remainingLevel(percent: percent),
            isDimmed: isDimmed,
            detail: detail,
            accessibilityLabel: "\(title), \(percent) percent remaining, \(spokenDetail)"
        )
    }
```

with

```swift
        guard let percent = wholePercent(headline.remainingPercent) else {
            return unavailableColumn(title: title)
        }
        // Reached only when the column shows a figure, so Fable never sits beside a dash.
        // The row type already refuses Fable on Codex; the check keeps that true here too.
        let fable = provider == .claude ? fableReadout(row?.fable, now: now) : nil
        return WidgetQuotaColumn(
            title: title,
            figure: "\(percent)%",
            fraction: min(max(headline.remainingPercent, 0), 100) / 100,
            level: remainingLevel(percent: percent),
            isDimmed: isDimmed,
            detail: detail,
            fable: fable?.text,
            accessibilityLabel: "\(title), \(percent) percent remaining, \(spokenDetail)"
                + (fable.map { ", \($0.spoken)" } ?? "")
        )
    }

    /// The Fable text and its spoken form. They depend only on Fable's own value and reset;
    /// the column's caption carries freshness. `nil` when there is no value to show.
    private static func fableReadout(
        _ reading: WidgetFableReading?,
        now: Date
    ) -> (text: WidgetFableText, spoken: String)? {
        // Validation has already refused a value that is not finite; never show zero if that changes.
        guard let reading, let percent = wholePercent(reading.remainingPercent) else { return nil }
        if let reset = reading.resetsAt, reset <= now {
            return (WidgetFableText(text: "Fable —", level: nil), "Fable awaiting fresh reading")
        }
        return (
            WidgetFableText(text: "Fable \(percent)%", level: remainingLevel(percent: percent)),
            "Fable \(percent) percent remaining"
        )
    }
```

`unavailableColumn` (`:244-254`) is not edited: it uses the new initializer's default, so a column that shows `—` has no Fable text.

In `Sources/NeedlbarWidgetSupport/WidgetPresentation.swift`, replace

```swift
    /// next countdown step, but never sooner than `minimumReloadInterval` after `now`.
    public static func nextDeadline(
```

with

```swift
    /// next countdown step, but never sooner than `minimumReloadInterval` after `now`.
    /// Fable's reset counts as a reset, so its text turns to a dash when it passes; Fable
    /// shows no countdown, so it adds no countdown step.
    public static func nextDeadline(
```

In `Sources/NeedlbarWidgetSupport/WidgetPresentation.swift`, replace

```swift
        let reset = projection.quotaRows.compactMap(\.headline?.resetsAt)
```

with

```swift
        let reset = projection.quotaRows.compactMap(\.headline?.resetsAt)
            + projection.quotaRows.compactMap(\.fable?.resetsAt)
```

The existing `.filter { $0 > now }` a few lines below already drops a reset that has passed.

- [ ] **Step 4: Run all support tests to verify they pass**

Run: `make swift-test SWIFT_TEST_FILTER=NeedlbarWidgetSupportTests`
Expected: `Test run with 52 tests in 2 suites passed` (22 projection tests, and 21 existing plus 9 new presentation tests), and make exits 0. The five existing tests that compare whole columns pass unchanged, which shows those columns carry no Fable text.

- [ ] **Step 5: Commit the presentation**

```bash
git add Sources/NeedlbarWidgetSupport/WidgetPresentation.swift Tests/NeedlbarWidgetSupportTests/WidgetOverviewPresentationTests.swift
git commit -m "feat(widget): present the Fable percent, its colour and its reset" \
  -m "The Claude column carries Fable text only when it shows a figure and the row has a Fable value: the whole percent with the same 20 and 10 percent levels, or a dash once Fable's own reset has passed. The spoken label gains the same information, and a future Fable reset is one more reload deadline." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Lay the text out on the name line**

In `WidgetExtension/NeedlbarOverviewWidget.swift`, replace

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(column.title)
                .font(.headline)
            Text(column.figure)
```

with

```swift
    private func fableColor(_ level: WidgetRemainingLevel?) -> Color {
        switch level {
        case .critical: return .red
        case .low: return .orange
        case .normal, nil: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // The name keeps its size; only the Fable text may shrink. A caption is shorter
            // than the headline font, so the line is no taller with it.
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(column.title)
                    .font(.headline)
                    .lineLimit(1)
                    .layoutPriority(1)
                if let fable = column.fable {
                    Spacer(minLength: 4)
                    Text(fable.text)
                        .font(.caption)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(fableColor(fable.level))
                }
            }
            Text(column.figure)
```

Nothing else in the view changes. The Fable text has no opacity modifier, so it is not dimmed when the figure is. The column is still one accessibility element (`.accessibilityElement(children: .ignore)` at the end of the `VStack`), and its label now carries the suffix from Step 3. `fableColor` uses explicit `return`s so it compiles the same on Swift 6.0.

- [ ] **Step 7: Compile the widget for real**

Run:

```bash
mkdir -p .build
./scripts/build-widget-extension.sh > .build/widget-build.log 2>&1; echo "build exit $?"
grep -ci warning .build/widget-build.log
tail -1 .build/widget-build.log
```

Expected: `build exit 0`, then `0` (no compiler warnings), then `widget extension built with synthetic App Group identity`. The log also shows codesign's `valid on disk` and `satisfies its Designated Requirement`. `.build/` is git-ignored, and nothing is installed or launched.

- [ ] **Step 8: Run the widget build and search-guard checks**

Run:

```bash
rg -n 'NeedlbarCore|CNeedlbar|Rust|Keychain|URLSession|AcceptanceFixture' Sources/NeedlbarWidgetSupport WidgetExtension/NeedlbarOverviewWidget.swift; echo "rg exit $?"
make widget-extension-test
```

Expected: no matches and `rg exit 1`; then `widget-extension search-guard regression passed` and `widget-extension build/metadata contract passed`, and make exits 0.

- [ ] **Step 9: Commit the layout**

```bash
git add WidgetExtension/NeedlbarOverviewWidget.swift
git commit -m "feat(widget): show the Fable percent on the Claude name line" \
  -m "The name line is a first-baseline row of the name, a spacer and the Fable text in caption size. The name keeps layout priority, and the text keeps one line and may scale down to 0.8, so the widget gains no height." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Documentation and records

**Files:**
- Modify: `docs/superpowers/specs/2026-11-06-glanceable-overview-widget-design.md:9-10,37-38,66,77-78,95-96`
- Modify: `docs/superpowers/specs/2026-08-31-needlbar-v0.2.1-widgets-notifications-design.md:77-79,145-146`
- Modify: `docs/superpowers/specs/2026-09-02-claude-fable-quota-design.md:166-168`
- Modify: `README.md:330-332,394`
- Modify: `docs/HANDOFF.md:3-4,176-177`
- Modify: `docs/STATUS.md:3`

**Interfaces:**
- Consumes: from Tasks 1 to 3, the behaviour as built: the `fable` reading, the one rule for showing the text, `Fable —` after Fable's reset, the 20 and 10 percent levels, the label suffixes, and the extra reload deadline.
- Produces: documents only. Nothing later depends on them.

Each note says what changed and why. `docs/architecture.md`, `docs/privacy.md` and the acceptance fixtures stay unchanged, as the spec says.

- [ ] **Step 1: Add the dated notes to the 2026-11-06 design**

In `docs/superpowers/specs/2026-11-06-glanceable-overview-widget-design.md`, replace

```markdown
**Scope:** The medium **Overview** widget's view only. The projection the app writes, the
App Group contract, refresh behaviour, the widget's family, and its tap target are unchanged.
```

with

```markdown
**Scope:** The medium **Overview** widget's view only. The projection the app writes, the
App Group contract, refresh behaviour, the widget's family, and its tap target are unchanged.

**Dated note, 2026-11-13:** the projection is no longer unchanged. Its Claude quota row gains
an optional Fable reading, because the user asked to see the Fable limit on the widget
(`2026-11-13-widget-fable-percent-design.md`). The schema version stays 1, and the App Group
contract, refresh behaviour, family and tap target are still unchanged.
```

In `docs/superpowers/specs/2026-11-06-glanceable-overview-widget-design.md`, replace

```markdown
- **Fable:** not shown, because the projection has no Fable value. The dashboard and
  Settings still show it.
```

with

```markdown
- **Fable:** not shown, because the projection has no Fable value. The dashboard and
  Settings still show it.
- **Fable (dated note, 2026-11-13):** the line above no longer holds. The remaining Fable
  percent is shown as small text, `Fable 71%`, at the right end of the Claude column's name
  line, with no reset time and no added height, and the projection now carries the value. The
  user now spends the Fable limit through a Fable-based agent and asked for it as secondary
  information. The large Claude figure is still the headline window. Approved in
  `2026-11-13-widget-fable-percent-design.md`.
```

In `docs/superpowers/specs/2026-11-06-glanceable-overview-widget-design.md`, replace

```markdown
- **No invented values:** an unavailable value is never shown as zero.
```

with

```markdown
- **No invented values:** an unavailable value is never shown as zero.
- **Fable text (dated note, 2026-11-13):** added with the Fable percent in §2. It appears only
  when the Claude column shows a figure and the projection has a Fable value. It reads
  `Fable —` once Fable's own reset has passed, and is hidden when there is no value or the
  column shows `—`; a missing value is never shown as zero. It is system orange below 20
  percent and system red below 10, judged on the whole percent shown, and otherwise the
  secondary colour. It is not dimmed when the headline's reset has passed, because its content
  depends only on its own value and reset. Fable's reset is one of the resets §5 reloads at,
  and it adds no countdown step.
```

In `docs/superpowers/specs/2026-11-06-glanceable-overview-widget-design.md`, replace

```markdown
- Each column reads as one VoiceOver element, for example "Claude, 77 percent remaining,
  weekly, resets in 6 days", or "Claude, quota unavailable".
```

with

```markdown
- Each column reads as one VoiceOver element, for example "Claude, 77 percent remaining,
  weekly, resets in 6 days", or "Claude, quota unavailable".
- **VoiceOver (dated note, 2026-11-13):** when the Fable text shows, the Claude column's label
  ends with ", Fable 71 percent remaining", or ", Fable awaiting fresh reading" once Fable's
  reset has passed, so the column is still one element. Added because the label replaces the
  column's visible text, which now includes Fable. "The widget has no title row" below means
  the widget as a whole: each column starts with its name, and the Fable text shares that line.
```

In `docs/superpowers/specs/2026-11-06-glanceable-overview-widget-design.md`, replace

```markdown
- **Manual:** the user checks the installed widget in light and dark appearance, with a
  fresh and an old value if one occurs.
```

with

```markdown
- **Manual:** the user checks the installed widget in light and dark appearance, with a
  fresh and an old value if one occurs.
- **Fable (dated note, 2026-11-13):** added with the Fable percent in §2. The automated tests
  also cover the Fable reading in the projection and in the app's mapper, its text, colour and
  VoiceOver suffix in each state, and its reset as a reload deadline. The manual check adds
  that `Fable 100%` fits on one line, that the text reads as part of the Claude column, and
  the low colour when it occurs.
```

- [ ] **Step 2: Amend the 2026-08-31 design**

In `docs/superpowers/specs/2026-08-31-needlbar-v0.2.1-widgets-notifications-design.md`, replace

```markdown
> row shows **Last checked** with its time instead of a separate freshness line. The other
> rules stand: the headline selection, fixed labels, no raw titles or errors, **Quota
> unavailable** instead of zero, and the fixed `needlbar://overview` tap URL.
```

with

```markdown
> row shows **Last checked** with its time instead of a separate freshness line. The other
> rules stand: the headline selection, fixed labels, no raw titles or errors, **Quota
> unavailable** instead of zero, and the fixed `needlbar://overview` tap URL.

> **Amendment — 2026-11-13:** Approved by the user in
> `2026-11-13-widget-fable-percent-design.md`. The Claude column's name line can also show the
> remaining Fable percent as small text under the fixed label `Fable`, because the user asked
> to see that limit on the widget. It has no reset time and no bar. The headline rules above
> stand: the allowlist is unchanged, Fable never becomes the headline, and the label is fixed
> text in the widget, never the provider's window title. The text is hidden when there is no
> Fable value or the column shows **Quota unavailable**; it is never zero and never estimated.
```

In `docs/superpowers/specs/2026-08-31-needlbar-v0.2.1-widgets-notifications-design.md`, replace

```markdown
- allowlisted headline quota window identity, remaining percentage, fixed
  local category label, and nullable reset timestamp for Claude/Codex;
```

with

```markdown
- allowlisted headline quota window identity, remaining percentage, fixed
  local category label, and nullable reset timestamp for Claude/Codex;
- for Claude only, the remaining Fable percentage and its nullable reset timestamp, with no
  window identity, label or timestamp of its own (added 2026-11-13, approved in
  `2026-11-13-widget-fable-percent-design.md`, because the user asked to see Fable on the
  widget; the schema version stays 1, since a reader ignores a key it does not know);
```

- [ ] **Step 3: Amend the 2026-09-02 Fable design**

In `docs/superpowers/specs/2026-09-02-claude-fable-quota-design.md`, replace

```markdown
contract. Widget and notification ID allowlists remain unchanged: Fable is not
exported, widgeted, or notified, and tests must prove that unknown IDs retain
the existing ignore/reject behavior. No Settings or preference flag is added.
```

with

```markdown
contract. Widget and notification ID allowlists remain unchanged: Fable is not
exported, widgeted, or notified, and tests must prove that unknown IDs retain
the existing ignore/reject behavior. No Settings or preference flag is added.

> **Amendment — 2026-11-13:** Approved by the user in
> `2026-11-13-widget-fable-percent-design.md`. Fable is now shown on the Overview widget, as
> small secondary text on the Claude column, because the user asked to see it there. The
> widget projection carries its remaining percent and reset time as a separate optional
> reading. The widget's headline allowlist is still unchanged, so Fable never becomes the
> widget's headline, and Fable is still not exported or notified.
```

- [ ] **Step 4: Update `README.md`**

New README text carries no version number (Global Constraints).

In `README.md`, replace

```markdown
Claude when its selected metric is Remaining. It does not change the menu-bar
headline, snapshot export, widget, or quota notifications. Missing Fable data is
shown as unavailable rather than estimated from tokens or the overall weekly quota.
```

with

```markdown
Claude when its selected metric is Remaining. It does not change the menu-bar
headline, snapshot export, or quota notifications, and in the released app it does
not change the widget. Prepared, not released: the widget shows the remaining Fable
percent as small text beside the Claude name (see Widget and quota notifications).
Missing Fable data is shown as unavailable rather than estimated from tokens or the
overall weekly quota.
```

In `README.md`, replace

```markdown
## Native macOS 14 acceptance (maintainer-only)
```

with

```markdown
Prepared, not released: beside the Claude name, the widget also shows the remaining Fable
percent as small text, for example `Fable 71%`, when Claude Code's usage report includes a
Fable limit (added 2026-11-13 at the user's request). It has no reset time and no bar, and the
large Claude figure is still the lower of the session and weekly windows, because Fable is
part of the weekly pool. The text is hidden when there is no Fable value or the Claude quota is
unavailable, reads `Fable —` after Fable's own reset until the next reading, and is never
estimated. The projection carries only that percent and its reset time. It has not been seen
on an installed widget yet.

## Native macOS 14 acceptance (maintainer-only)
```

The new paragraph lands at the end of the `### Widget and quota notifications` section, after its existing paragraph.

- [ ] **Step 5: Update `docs/HANDOFF.md`**

In `docs/HANDOFF.md`, replace

```markdown
**Checkpoint:** 2026-11-12, updated for the `/usage` cadence and deadline change, which is
prepared and not released and not yet run on a real machine; before that 2026-11-05, for the
```

with

```markdown
**Checkpoint:** 2026-11-13, updated for the Fable percent on the Overview widget, which is
prepared and not released and not yet seen on a real widget; before that 2026-11-12, for the
`/usage` cadence and deadline change, which is
prepared and not released and not yet run on a real machine; before that 2026-11-05, for the
```

In `docs/HANDOFF.md`, replace

```markdown
`backoffRetry` and `periodic`, automatic starts at least 15 minutes apart except after a reset or a
failure, and no `usageProbeTimedOut` with `durationMs` under 60,000.
```

with

```markdown
`backoffRetry` and `periodic`, automatic starts at least 15 minutes apart except after a reset or a
failure, and no `usageProbeTimedOut` with `durationMs` under 60,000.

**Fable on the widget (2026-11-13, prepared, not released).** Design:
`docs/superpowers/specs/2026-11-13-widget-fable-percent-design.md`. Plan:
`docs/superpowers/plans/2026-11-13-widget-fable-percent.md`. The Overview widget's Claude column
shows the remaining Fable percent as small text on its name line, with no reset time, because the
user asked to see that limit at a glance. The large figure is still the lower of session and
weekly. The projection's Claude quota row carries an optional `fable` reading and the schema
version stays 1. The text is hidden without a Fable value or when the column shows `—`, and reads
`Fable —` after Fable's own reset. Not yet seen on a real widget. After installing, stop the old
widget process by its process ID and check its executable, or the missing text looks like a
missing value (STATUS, 2026-11-13). Fable is found in the usage report by its display name, so a
rename removes the text without notice.
```

- [ ] **Step 6: Add the STATUS entry**

In `docs/STATUS.md`, replace

```markdown
## 2026-11-12 Claude usage probe cadence and deadline (prepared, not released)
```

with

```markdown
## 2026-11-13 Fable percent on the Overview widget (prepared, not released)

Implements `docs/superpowers/specs/2026-11-13-widget-fable-percent-design.md` through
`docs/superpowers/plans/2026-11-13-widget-fable-percent.md`. Not merged, installed, tagged or
released, and not yet seen on a real widget.

- **Change.** The Claude column's name line ends with the remaining Fable percent as small text,
  for example `Fable 71%` (user decision, 2026-11-13; on 2026-11-06 the user had left Fable out).
  It has no reset time, no bar and no added height. The large Claude figure stays the headline,
  the lower of session and weekly, even when Fable is lower, because Fable is part of the weekly
  pool and not separate capacity.
- **States.** The text shows only when the Claude column shows a figure and the projection has a
  Fable value. It reads `Fable —` once Fable's own reset has passed, and is hidden when there is
  no value or the column shows `—`. It is system orange below 20 percent and system red below 10,
  judged on the whole percent shown, and is not dimmed with the figure. VoiceOver reads it at the
  end of the column's label. A missing value is never shown as zero or estimated.
- **Projection.** The Claude quota row gains an optional `fable` reading: the remaining percent
  and an optional reset time. The schema version stays 1, because a reader ignores a key it does
  not know: on a scratch copy, the code before this change decoded a file with the new key, and a
  projection without Fable encodes byte for byte as before. The mapper takes the value from the
  `claude.fable.weekly` window and drops it without failing when it cannot be carried, so a
  problem with Fable never stops widget updates. The headline allowlist is unchanged.
- **Reloads.** Fable's reset time is one more reload deadline while it is in the future. Fable
  adds no countdown step and no reload from the app.
- **Risks.** A widget process left from before installation shows no Fable text, which looks like
  a missing value: stop it by its process ID and check its executable after installing. Fable is
  found in the usage report by its display name, so a rename removes the text without notice. A
  report without Fable removes the text at once; there is no last-known Fable. Whether an account
  that has not used Fable receives a row, which would show `Fable 100%`, is not verified.
- **Verified.** Projection, mapper and presentation tests; a real compile of the widget
  extension; the widget build and search-guard checks; and `make test`.

Not established: the text has not been seen on a real widget. After a build and an installation,
each the user's separate request, the user checks light and dark appearance, that `Fable 100%`
fits on one line, that the text reads as part of the Claude column, and the low colour when it
occurs.

## 2026-11-12 Claude usage probe cadence and deadline (prepared, not released)
```

- [ ] **Step 7: Check the documentation contracts**

Run:

```bash
git diff -U0 -- README.md | grep '^+' | grep -c -e '0\.3\.14' -e '0\.3\.15'
git diff --name-only 697563e -- crates vendor Cargo.toml Cargo.lock docs/architecture.md docs/privacy.md Fixtures scripts Package.swift
make notarize-test 2>&1 | tail -n 1
```

Expected: `0` (no version number in the new README lines); no output from the second command (no Rust file, script, fixture, `docs/architecture.md` or `docs/privacy.md` changed since the spec commit); and `notarize-app shell contracts passed`.

- [ ] **Step 8: Run the full project gate**

Run:

```bash
make test > "${TMPDIR:-/tmp}/needlbar-make-test.log" 2>&1; echo "make exit $?"
tail -n 1 "${TMPDIR:-/tmp}/needlbar-make-test.log"
grep -c '✘' "${TMPDIR:-/tmp}/needlbar-make-test.log"
```

Expected: `make exit 0`, the last line `notarize-app shell contracts passed`, and a count of `0`. The run takes well over ten minutes, so give it a timeout of at least thirty. It includes the whole Swift suite, `widget-extension-test`, `package-test` and `notarize-test`. This plan changes no Rust file, so the two Rust commands CI runs outside `make test` are unaffected.

- [ ] **Step 9: Commit**

```bash
git add docs/superpowers/specs/2026-11-06-glanceable-overview-widget-design.md \
  docs/superpowers/specs/2026-08-31-needlbar-v0.2.1-widgets-notifications-design.md \
  docs/superpowers/specs/2026-09-02-claude-fable-quota-design.md \
  README.md docs/HANDOFF.md docs/STATUS.md
git commit -m "docs: record the Fable percent on the Overview widget" \
  -m "The 2026-11-06, 2026-08-31 and 2026-09-02 designs carry dated notes, and README, HANDOFF and STATUS describe the text as prepared, not released." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short
```

Expected: `git status --short` shows only `?? .superpowers/brainstorm/`, plus this plan file if the main session has not committed it yet.

---

### Where the plan stops

After Task 4 the branch `claude/widget-fable-line` holds five new local commits and is ready for review. Implementers stop here. Pushing the branch and opening a pull request is the main session's step, at the user's request. Merge, a tagless Developer ID build, installation, tag and release each need the user's separate request and are not part of this plan.

### Manual check (USER-RUN, after a build and an installation, not for implementers)

Spec §6 lists what only the installed widget can show. It applies once the user has separately asked for a tagless Developer ID build and for that build to be installed. Nothing here is run by this plan.

- [ ] After installing, the old widget process is gone. Replacing the app does not restart `NeedlbarWidgetExtension`: find its process ID, confirm with `lsof -p <pid> -a -d txt` that it maps the old executable, stop that process, then remove and re-add the widget and confirm the new process maps the installed file. An old process shows no Fable text, which looks like a missing value (spec §7).
- [ ] The text `Fable <percent>%` sits at the right end of the Claude name line, in light and in dark appearance, and reads as part of the Claude column.
- [ ] `Fable 100%` fits on one line without truncation. If the current value is lower, judge by the room left beside it.
- [ ] The widget is no taller than before, and the footer still fits.
- [ ] If a value below 20 or below 10 percent occurs, the text is orange or red while the desktop is in front.
- [ ] VoiceOver reads the Claude column as one element that ends with the Fable percent.

---

## Self-Review

**1. Spec coverage**

| Spec | Requirement | Where |
|---|---|---|
| §2 | `Fable 71%` at the right end of the name line, caption size, no added height | Task 3 Step 6; measured in Decisions 4; manual check |
| §2 | Whole percent, no reset time | Task 3 Step 3 (`wholePercent`); no reset text exists |
| §2 | The big number stays the headline, even when Fable is lower | Task 2 Step 1 (extended test, Fable at 0 percent); `WidgetQuotaWindowID` untouched |
| §3 | Optional `fable` reading on the Claude row, no window ID or timestamp | Task 1 Step 3 |
| §3 | Schema version stays 1; old and new readers; no key when there is no value | Task 1 Steps 1 and 3; Decisions 2 |
| §3 | Both decode paths and both validators | Task 1 Step 3 (row `init(from:)`, `RawQuotaRow`, row initializer, `validate`) |
| §3 | Validation: Claude only, 0 to 100 and finite, finite reset, last successful time | Task 1 Step 3 (`isValid`), Step 1 (rejection tests) |
| §3 | Mapper: Claude only, from `claude.fable.weekly`, drops and never throws | Task 2 Steps 1 and 3 |
| §3 | Headline allowlist unchanged | No task edits `WidgetQuotaWindowID` or the candidates |
| §4 | The one rule; each state's text and VoiceOver suffix | Task 3 Step 3; Step 1 tests, one per table row |
| §4 | Colour on the whole percent shown; `Fable —` secondary | Task 3 Step 1 (`theFableColourFollowsTheShownWholePercent`, the dash test); Step 6 (`fableColor`) |
| §4 | Never invented; shown as reported even above the weekly figure | Task 3 Step 1 (hidden test, above-the-headline test) |
| §4 | Layout: first-baseline row, name priority, one line, monospaced digits, scale to 0.8 | Task 3 Step 6 |
| §5 | Fable reset as a deadline only while in the future; no countdown step | Task 3 Step 3; Step 1 (two reload tests) |
| §6 | Projection tests | Task 1 Step 1 |
| §6 | Mapper tests, including the extended one | Task 2 Step 1 |
| §6 | Presentation tests | Task 3 Step 1 |
| §6 | Build and search-guard checks still pass | Task 3 Steps 7 and 8; Task 4 Step 8 |
| §6 | Not automated, checked by the user | Manual check (USER-RUN) |
| §7 | Old widget process; label dependence; no last-known Fable; unused limit | Recorded in Task 4 Steps 5 and 6; the first is also in the manual check |
| §8 | 2026-11-06 design: scope line, §2, §4, §6, §7 | Task 4 Step 1 |
| §8 | 2026-08-31 design: §3.1 and the §4.2 list | Task 4 Step 2 |
| §8 | 2026-09-02 design | Task 4 Step 3 |
| §8 | README: the Fable section and the widget section | Task 4 Step 4 |
| §8 | HANDOFF; STATUS entry marked prepared, not released | Task 4 Steps 5 and 6 |
| §8 | `architecture.md`, `privacy.md` and the acceptance fixtures unchanged | Task 4 Step 7 checks it |

No gap found. Decisions 5 lists where the spec is silent and what the plan does there.

**2. Placeholder scan:** every code and document step shows the full text to remove and to add, and every command has its expected result. No step says "TBD", "similar to" or "add tests for".

**3. Type consistency:** `WidgetFableReading` (`remainingPercent`, `resetsAt`, `init(remainingPercent:resetsAt:)`, `isValid(for:lastSuccessfulAt:)`) is defined in Task 1 and used with those spellings in Tasks 2 and 3. `WidgetQuotaRow.fable` and the `fable:` initializer parameter are the same in the row, the raw row, the mapper and all three test files. `WidgetFableText` (`text`, `level`) and `WidgetQuotaColumn.fable` are defined in Task 3 Step 3 and used in Step 1's tests and Step 6's view. `fableReading(_:provider:)` is the mapper's helper and `fableReadout(_:now:)` the presentation's; neither is called from another task. Existing names used as they are at `697563e`: `QuotaWindow.claudeFableWeeklyID`, `WidgetProviderCapture`, `WidgetStoreCapture`, `makeWidgetCapture(now:claudeQuota:codexQuota:)`, `makeUnavailableUsageRows()`, `unavailableToday`, `overview(claude:codex:usage:today:)`, `column(_:_:)`, `nextReload(_:)`, `shortText(_:includingDate:)`, `weekly(_:resetIn:)`, `wholePercent(_:)`, `remainingLevel(percent:)`. Test counts: the support target goes from 36 to 43 after Task 1 and 52 after Task 3; the core suite goes from 14 to 17 after Task 2.
