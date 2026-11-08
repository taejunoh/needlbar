# Glanceable Overview Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the medium Overview widget's same-weight text lines with two Claude and Codex columns (a large remaining percent, a bar, one line) and a one-line today footer, as approved in the 2026-11-06 design.

**Architecture:** Every decision the widget shows becomes a pure function in `Sources/NeedlbarWidgetSupport/WidgetPresentation.swift`, covered by a new Swift Testing suite: column state, text, colour level, spoken label, footer and next reload. `WidgetExtension/NeedlbarOverviewWidget.swift` keeps only layout, fonts, and the mapping from a level to a system colour. The projection, its mapper and publisher, the App Group file, and the timeline provider stay as they are. The provider already calls `nextDeadline`, which gains the countdown rule.

**Tech Stack:** Swift 6 and Swift Testing, SwiftUI and WidgetKit in a macOS 14+ arm64 app extension, Foundation `Decimal` and `DateFormatter`.

## Global Constraints

Authoritative spec: `docs/superpowers/specs/2026-11-06-glanceable-overview-widget-design.md`. Copied from it verbatim:

- Status: "It authorizes an implementation plan only. Implementation, merge, installation, tag, and release each still need the user's separate request."
- Scope: "The medium **Overview** widget's view only. The projection the app writes, the App Group contract, refresh behaviour, the widget's family, and its tap target are unchanged."
- Layout: "Two equal columns, then one footer line."
- Small line: "`<window> · resets in <time>`, for example `Weekly · resets in 6d`"
- Footer: "`Today <tokens> tokens` on the left, the estimated cost on the right"
- "**Headline window:** each column shows the existing headline window: the allowlisted window with the least remaining, as the projection already selects it."
- "**Window labels:** the existing fixed category labels (`Session`, `Weekly`, `Primary`, `Secondary`)."
- "**Fable:** not shown, because the projection has no Fable value. The dashboard and Settings still show it."
- "**Removed:** the header's **Fresh**/**Stale** label, per-row "Fresh · <time>" lines, the Cursor row, and the "Today updated" line."
- "**Percent:** the remaining percent, rounded to a whole number. The widget always shows remaining, regardless of the app's shared **Display value** setting."
- "**Reset countdown:** at least 1 day shows whole days (`6d`), at least 1 hour shows whole hours (`5h`), otherwise `<1h`. Values are rounded down."
- "**Tokens:** compact with one decimal place below 100 units (`1.2K`, `878M`, `1.4B`)."
- "**Cost:** two decimal places with `$`, the same estimate the widget shows today."
- "**Today:** the footer sums the providers whose today total is current, as today. The `Partial`/`Complete` and `Fresh`/`Stale` words are dropped. With no current contributor the footer is hidden."
- State "Fresh": "percent, normal" and "`<window> · resets in <time>`".
- State "Stale (older than 20 minutes for Claude, 15 for Codex, as now)": "percent, normal" and "`Last checked <time>`".
- State "Reset time passed": "percent, dimmed" and "`Awaiting fresh reading`".
- State "No displayable value": "`—`" and "`Quota unavailable`".
- "**Low remaining:** below 20 percent the figure and bar use the system orange; below 10 percent, the system red. Unavailable values have no colour."
- "**Last checked:** the time only when it is today, otherwise the short date and time."
- "**No invented values:** an unavailable value is never shown as zero."
- "The widget's timeline reloads at the earliest of the existing deadlines (a freshness boundary, a reset, local midnight) and the next moment the countdown text would change. While a reset is more than a day away that is the next whole-day boundary before it; within a day, the next whole hour. No reload is scheduled more often than once a minute."
- "Each column reads as one VoiceOver element, for example "Claude, 77 percent remaining, weekly, resets in 6 days", or "Claude, quota unavailable"."
- "Colours are system colours and work in light and dark appearance. The provider colours stay as accents on the bar only."
- "The widget extension's existing build and search-guard checks still pass."
- From §8, for the 2026-08-31 design: "Its other rules stand: the headline selection, fixed labels, no raw titles or errors, **Quota unavailable** instead of zero, and the fixed tap URL."

Repository constraints:

- Implementers never read Keychain items, cookies or credential files; never run `claude`; never launch, kill or install any Needlbar app (no `make smoke`, nothing copied into `/Applications`); never push, merge or tag.
- The widget extension compiles exactly `WidgetProjection.swift`, `WidgetPresentation.swift` and `NeedlbarOverviewWidget.swift` (`scripts/build-widget-extension.sh:12-14,54-56`). Do not add a file to `Sources/NeedlbarWidgetSupport`. Extend `WidgetPresentation.swift`.
- No widget or support source may contain the case-sensitive words `NeedlbarCore`, `CNeedlbar`, `Rust`, `Keychain` or `URLSession`, comments included (`scripts/tests/widget-extension-tests.sh:25`). The widget source may not contain `AcceptanceFixture` (`scripts/tests/acceptance-build-isolation-tests.sh:17`).
- Widget code builds with `-target arm64-apple-macosx14.0 -swift-version 6 -application-extension` (`scripts/build-widget-extension.sh:42-57`). Use macOS 14 APIs that are safe in app extensions. Use no shared mutable statics, such as a static `DateFormatter`.
- New `docs/STATUS.md` text repeats no run ID, asset ID, commit hash, `releases/tag/`, or `report 0.3.`, because the decoys at `scripts/tests/notarize-app-tests.sh:2207-2229` rewrite the first occurrence. It says prepared, not released, and not seen on a real widget.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Commands run from the repository root after `export PATH="$HOME/.cargo/bin:$PATH" MACOSX_DEPLOYMENT_TARGET=14.0`. `make widget-extension-test` needs `rg`. On the maintainer's Mac, also prefix `PATH` with `/Users/taejunoh/.codex/plugins/.plugin-appserver/codex-cli/codex-path`.
- Line numbers are from commit `10b098e`. Once an earlier task shifts a file, find the place by the quoted text.

---

## Decisions Settled From The Code

### 1. What becomes a pure function and what stays in the view

| Today (removed or replaced) | Pure function in `WidgetPresentation` | Stays in the view |
|---|---|---|
| `overallFreshnessLabel` and the title row (`WidgetExtension/NeedlbarOverviewWidget.swift:62-71,159-163`) | removed (see 6) | nothing |
| `quotaLine` (`:122-140`), its `Fresh ·`/`Stale ·` line (`:132-134`) and `resetLabel` (`Sources/NeedlbarWidgetSupport/WidgetPresentation.swift:51-54`) | `quotaStatus(_:now:)` returns a `WidgetQuotaStatus`. `quotaColumn(for:in:now:calendar:locale:)` returns a `WidgetQuotaColumn` (title, figure, bar fraction, level, dimmed, line, spoken label). Helpers: `countdown(until:now:)`, `remainingLevel(percent:)`, `lastCheckedTime(...)` | fonts, the two-column `HStack`, bar geometry, level to `.orange`/`.red`, provider accent, opacity when dimmed, accessibility modifiers |
| `todayLabel` (`:73-106`) and `todayUpdatedLabel` (`:108-120`) | `todayFooter(_:now:)` returns `WidgetTodayFooter?`, using `compactTokens(_:)` and `costText(_:)` | the footer `HStack`, hidden when the result is `nil` |
| `providerLabel` (`:142-148`) | `providerTitle(_:)` | nothing |
| `timestampFormatter` (`:150-155`) | `lastCheckedTime` builds its own formatter from an injected `Calendar` and `Locale` | passes the current calendar and `.current` locale |
| fixed Cursor row (`:166-168`) | removed | nothing |
| `nextDeadline` (`WidgetPresentation.swift:56-71`) | extended with `nextCountdownChange(until:now:)` and `minimumReloadInterval` | `getTimeline` (`NeedlbarOverviewWidget.swift:40-48`), unchanged |

Why one file: the widget build lists its sources by name (`scripts/build-widget-extension.sh:12-14,23-25,54-56`). Both fixtures copy the same two support files (`scripts/tests/widget-extension-tests.sh:17-19`, `scripts/tests/package-app-tests.sh:42-44`), and the fake compiler requires those names (`scripts/tests/widget-extension-tests.sh:44`). A new file would need four coordinated script edits. `WidgetPresentation.swift` grows from 72 to about 320 lines and still has one job: presentation.

### 2. Build and search-guard contract

- The guard is a word search, not an API or colour list (`scripts/tests/widget-extension-tests.sh:25-32`). `scripts/tests/widget-extension-search-guard-tests.sh:50-68` shows it fails closed when `rg` is missing, errors, or matches. The view needs no forbidden word.
- `make widget-extension-test` (`Makefile:81-83`) never compiles Swift, because its `xcrun` is a fake (`scripts/tests/widget-extension-tests.sh:34-58`). The real compile runs only inside `make package` (`scripts/package-app.sh:85-88`, CI `.github/workflows/ci.yml:65`). Tasks 3 and 4 therefore also run `./scripts/build-widget-extension.sh` directly. That is a real `swiftc` build into the git-ignored `.build/widget-extension`, signed ad hoc, with nothing installed or launched.
- The entitlement checks (`scripts/tests/widget-extension-tests.sh:82-86`) are unaffected.
- Before this plan was written, its code was compiled with the real build script on a scratch copy and checked with the guard's regex: no warnings and no match. All 34 support tests passed there.

### 3. Next reload and whether it needs a cap

- The app reloads the widget only when the projection bytes change (`Sources/NeedlbarCore/Widget/WidgetProjectionPublisher.swift:73-81`). The timeline's own reloads come from `nextDeadline`.
- Countdown text changes once a day while the reset is more than a day away, then once an hour. Within the last hour the reset itself, already a deadline, is the next change. Only fresh columns add steps, because a stale column shows **Last checked**, which changes only at midnight, already a deadline.
- Rounding down means the old text is still right exactly on a step (exactly 2 hours shows `2h`), so `nextCountdownChange` returns `now` there. The spec's one-minute floor turns that into a reload a minute later instead of an immediate loop, and it merges deadlines that fall seconds apart. The floor is needed and is `minimumReloadInterval = 60`.
- No further cap. The worst case is two columns on five-hour windows, about 24 hourly steps each per day. WidgetKit's own daily budget throttles beyond that; the cost is late text, never a wrong value. If the countdown visibly lags, a follow-up could emit one timeline entry per step instead of reloading, but that changes §5's wording and needs the user's approval.

### 4. Existing tests that assert removed text

- None does. The removed strings exist only in the view (`NeedlbarOverviewWidget.swift:62-71,101-105,108-120,132-134,166`), and no file under `Tests/`, `scripts/` or `Fixtures/` asserts them.
- `passedResetUsesFixedAwaitingFreshReadingLabel` (`Tests/NeedlbarWidgetSupportTests/WidgetProjectionTests.swift:244-249`) tests `resetLabel`, whose only caller is the old view (`NeedlbarOverviewWidget.swift:126`). Task 4 deletes both together, so the widget still compiles after Tasks 1 to 3. `aPassedResetDimsTheFigureAndAwaitsAFreshReading` replaces that coverage.
- These stay unchanged. `staleContributorRemainsInPartialTodayAggregate` (`WidgetProjectionTests.swift:266-275`) checks the projection's own `today` summary, which the app still writes. `theNextDeadlineUsesTheClaudeQuotaRowsOwnHorizon` (`:228-242`) still expects +1,200 seconds, above the floor. `Tests/NeedlbarCoreTests/WidgetProjectionTests.swift` tests only the mapper. The native acceptance widget fixtures (`Fixtures/acceptance/native-driver/widget/*.json`) are inputs with no expected text.

### 5. Where the spec is silent

- A fresh column with no reset time shows the window label alone (`Primary`), spoken "primary".
- Colour thresholds use the whole percent shown, so 19.6 shows `20%` at the normal level.
- A dimmed column keeps its level colour at 45 percent opacity.
- Tokens round down like the countdown, so 99,999 is `99.9K`, not `100.0K`. Below 1,000 they are whole, and `T` is used above 999B.
- Cost rounds half up with no thousands separator (`$1234.50`), like the approved mockup's `$226.27`.
- A headline whose percent is outside 0 to 100, or whose last success is after now, shows **Quota unavailable**. This cannot reach the widget after `WidgetProjection.decode` (`Sources/NeedlbarWidgetSupport/WidgetProjection.swift:383-397,443-449`).
- The countdown uses 24-hour days, so its steps match its reload times exactly.
- "Within a day, the next whole hour" means the next whole hour before the reset, which is when `5h` becomes `4h`.
- `.padding(10)` (`NeedlbarOverviewWidget.swift:177`) is dropped. With `containerBackground`, macOS 14 widgets already get system content margins, and the 36-point figure needs the height. The user's manual check confirms nothing clips.

### 6. Where the code and the spec disagree

- **Provider colours.** §6 says provider colours "stay" as bar accents, but the widget has no colour today (`NeedlbarOverviewWidget.swift:157-179`). The app's only provider colour is Claude's system orange (`Sources/Needlbar/ProviderBrandIcon.swift:135,241`), and Codex is monochrome (`:141`). The approved mockup used non-system hex colours. This plan uses `.orange` for Claude and `.blue` for Codex. Claude's bar is then orange both normally and below 20 percent, although its figure still turns orange and both turn red below 10 percent. If the user prefers another Claude accent, it is one argument in the view.
- **Title row.** §2's layout ("Two equal columns, then one footer line") and the approved layout A have no title row. §2's removal list and §8 name only the header's freshness word. This plan follows the layout and removes the `Needlbar` title row, and the dated note says so.

### 7. Documentation

- The 2026-08-31 design gets a dated amendment at the end of §3.1, before `### 3.2 Freshness and Staleness` (line 71). Its wording follows the new design's §8, plus the hidden footer and the title row from §2 and §3.
- `docs/STATUS.md` gets a new entry under its title (after line 1). It says prepared, not released, and not seen on a real widget, and it contains no hash or ID.

## File Structure

- Modify `Sources/NeedlbarWidgetSupport/WidgetPresentation.swift`: every widget presentation decision (types, formatting, columns, footer, reloads).
- Create `Tests/NeedlbarWidgetSupportTests/WidgetOverviewPresentationTests.swift`: the suite for those functions.
- Modify `Tests/NeedlbarWidgetSupportTests/WidgetProjectionTests.swift:244-249`: delete the `resetLabel` test.
- Modify `WidgetExtension/NeedlbarOverviewWidget.swift:59-180`: the new layout. Lines 1-57 and 182-197 are unchanged.
- Modify `docs/superpowers/specs/2026-08-31-needlbar-v0.2.1-widgets-notifications-design.md`: the dated amendment before line 71.
- Modify `docs/STATUS.md`: a new entry after line 1.

Untouched: `WidgetProjection.swift`, `Sources/NeedlbarCore/Widget/*`, the extension's Info.plist and entitlements, every script, and `Package.swift`.

---

### Task 1: Countdown, token, cost and colour-level text

**Files:**
- Modify: `Sources/NeedlbarWidgetSupport/WidgetPresentation.swift:7,13,49`
- Create: `Tests/NeedlbarWidgetSupportTests/WidgetOverviewPresentationTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `public enum WidgetCountdown: Equatable, Sendable { case days(Int), hours(Int), underOneHour; var text: String; var spokenText: String }`
  - `public enum WidgetRemainingLevel: Equatable, Sendable { case normal, low, critical }`
  - `WidgetPresentation.countdown(until reset: Date, now: Date) -> WidgetCountdown?`
  - `WidgetPresentation.compactTokens(_ value: UInt64) -> String`
  - `WidgetPresentation.costText(_ cost: Decimal) -> String`
  - `WidgetPresentation.remainingLevel(percent: Int) -> WidgetRemainingLevel`
  - private `secondsPerDay`, `secondsPerHour`
  - test-file globals `referenceDate`, `minute`, `hour`, `day`

- [ ] **Step 1: Write the failing tests**

Create `Tests/NeedlbarWidgetSupportTests/WidgetOverviewPresentationTests.swift`:

```swift
import Foundation
import Testing
@testable import NeedlbarWidgetSupport

@Suite
struct WidgetOverviewPresentationTests {
    // MARK: Formatting

    @Test
    func theCountdownRoundsDownToWholeDaysThenWholeHours() {
        func text(_ seconds: TimeInterval) -> String? {
            WidgetPresentation.countdown(until: referenceDate.addingTimeInterval(seconds), now: referenceDate)?.text
        }
        #expect(text(6 * day + 23 * hour + 59 * minute) == "6d")
        #expect(text(day) == "1d")
        #expect(text(day - 1) == "23h")
        #expect(text(5 * hour + 59 * minute) == "5h")
        #expect(text(hour) == "1h")
        #expect(text(hour - 1) == "<1h")
        #expect(text(1) == "<1h")
        #expect(text(0) == nil)
        #expect(text(-1) == nil)
    }

    @Test
    func theCountdownIsSpokenInWords() {
        #expect(WidgetCountdown.days(1).spokenText == "1 day")
        #expect(WidgetCountdown.days(6).spokenText == "6 days")
        #expect(WidgetCountdown.hours(1).spokenText == "1 hour")
        #expect(WidgetCountdown.hours(5).spokenText == "5 hours")
        #expect(WidgetCountdown.underOneHour.spokenText == "less than 1 hour")
    }

    @Test
    func aResetTooFarAwayHasNoCountdownInsteadOfTrapping() {
        let far = Date(timeIntervalSinceReferenceDate: 1e300)
        #expect(WidgetPresentation.countdown(until: far, now: referenceDate) == nil)
    }

    @Test
    func tokensUseOneDecimalBelowOneHundredUnitsAndRoundDown() {
        let cases: [(UInt64, String)] = [
            (0, "0"), (999, "999"), (1_000, "1.0K"), (1_250, "1.2K"), (99_999, "99.9K"),
            (100_000, "100K"), (999_999, "999K"), (1_000_000, "1.0M"), (878_000_000, "878M"),
            (1_400_000_000, "1.4B"), (999_999_999_999, "999B"), (1_000_000_000_000, "1.0T"),
            (.max, "18446744T"),
        ]
        for (value, expected) in cases {
            #expect(WidgetPresentation.compactTokens(value) == expected)
        }
    }

    @Test
    func costShowsTwoDecimalPlacesWithADollarSign() {
        let cases: [(String, String)] = [
            ("0", "$0.00"), ("1.5", "$1.50"), ("3.75", "$3.75"), ("2.345", "$2.35"),
            ("0.004", "$0.00"), ("226.27", "$226.27"), ("1234.5", "$1234.50"),
        ]
        for (value, expected) in cases {
            #expect(WidgetPresentation.costText(Decimal(string: value)!) == expected)
        }
    }

    @Test
    func theColourLevelChangesBelowTwentyAndBelowTenPercent() {
        #expect(WidgetPresentation.remainingLevel(percent: 100) == .normal)
        #expect(WidgetPresentation.remainingLevel(percent: 20) == .normal)
        #expect(WidgetPresentation.remainingLevel(percent: 19) == .low)
        #expect(WidgetPresentation.remainingLevel(percent: 10) == .low)
        #expect(WidgetPresentation.remainingLevel(percent: 9) == .critical)
        #expect(WidgetPresentation.remainingLevel(percent: 0) == .critical)
    }
}

private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
private let minute: TimeInterval = 60
private let hour: TimeInterval = 3_600
private let day: TimeInterval = 86_400
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make swift-test SWIFT_TEST_FILTER=WidgetOverviewPresentationTests`
Expected: the build fails with `error: type 'WidgetPresentation' has no member 'countdown'` and `error: cannot find 'WidgetCountdown' in scope`.

- [ ] **Step 3: Write the implementation**

In `Sources/NeedlbarWidgetSupport/WidgetPresentation.swift`, insert after the closing brace of `WidgetDisplayFreshness` (line 7):

```swift

/// A reset countdown, rounded down: whole days from one day, whole hours from one hour.
public enum WidgetCountdown: Equatable, Sendable {
    case days(Int)
    case hours(Int)
    case underOneHour

    public var text: String {
        switch self {
        case .days(let days): "\(days)d"
        case .hours(let hours): "\(hours)h"
        case .underOneHour: "<1h"
        }
    }

    public var spokenText: String {
        switch self {
        case .days(let days): days == 1 ? "1 day" : "\(days) days"
        case .hours(let hours): hours == 1 ? "1 hour" : "\(hours) hours"
        case .underOneHour: "less than 1 hour"
        }
    }
}

/// The colour of a shown percent. A column without a value has no level and no colour.
public enum WidgetRemainingLevel: Equatable, Sendable {
    case normal
    /// Below 20 percent: system orange.
    case low
    /// Below 10 percent: system red.
    case critical
}
```

Insert after `public static let claudeQuotaFreshnessHorizon: TimeInterval = 20 * 60` (line 13):

```swift

    private static let secondsPerDay: TimeInterval = 86_400
    private static let secondsPerHour: TimeInterval = 3_600
```

Insert after the closing brace of `todayIsCurrent(_:now:)` (line 49), before `resetLabel`:

```swift

    // MARK: Formatting

    /// `nil` when the reset is not in the future or is too far away to count.
    public static func countdown(until reset: Date, now: Date) -> WidgetCountdown? {
        let remaining = reset.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        if remaining >= secondsPerDay {
            return Int(exactly: (remaining / secondsPerDay).rounded(.down)).map(WidgetCountdown.days)
        }
        if remaining >= secondsPerHour {
            return .hours(Int((remaining / secondsPerHour).rounded(.down)))
        }
        return .underOneHour
    }

    /// Whole tokens below 1,000; otherwise K, M, B or T with one decimal place below 100
    /// units. Rounded down, so a value never reads as the next unit up.
    public static func compactTokens(_ value: UInt64) -> String {
        let units: [(size: UInt64, suffix: String)] = [
            (1_000_000_000_000, "T"),
            (1_000_000_000, "B"),
            (1_000_000, "M"),
            (1_000, "K"),
        ]
        for unit in units where value >= unit.size {
            let tenths = value / (unit.size / 10)
            return tenths < 1_000
                ? "\(tenths / 10).\(tenths % 10)\(unit.suffix)"
                : "\(value / unit.size)\(unit.suffix)"
        }
        return "\(value)"
    }

    /// Two decimal places with a dollar sign, rounded half up.
    public static func costText(_ cost: Decimal) -> String {
        var value = cost
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        let parts = NSDecimalNumber(decimal: rounded).stringValue
            .split(separator: ".", omittingEmptySubsequences: false)
        let fraction = parts.count > 1 ? String(parts[1]) : ""
        return "$\(parts[0]).\(fraction.padding(toLength: 2, withPad: "0", startingAt: 0))"
    }

    /// Thresholds apply to the whole percent shown, so the colour never disagrees with it.
    public static func remainingLevel(percent: Int) -> WidgetRemainingLevel {
        if percent < 10 { return .critical }
        if percent < 20 { return .low }
        return .normal
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make swift-test SWIFT_TEST_FILTER=WidgetOverviewPresentationTests`
Expected: `Test run with 6 tests in 1 suite passed`, and make exits 0.

- [ ] **Step 5: Commit**

```bash
git add Sources/NeedlbarWidgetSupport/WidgetPresentation.swift Tests/NeedlbarWidgetSupportTests/WidgetOverviewPresentationTests.swift
git commit -m "feat(widget): add countdown, token, cost and colour level text" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Column states and the today footer

**Files:**
- Modify: `Sources/NeedlbarWidgetSupport/WidgetPresentation.swift` (after `WidgetRemainingLevel` and after `remainingLevel(percent:)`, both added in Task 1)
- Test: `Tests/NeedlbarWidgetSupportTests/WidgetOverviewPresentationTests.swift`

**Interfaces:**
- Consumes: `countdown(until:now:)`, `WidgetCountdown.text`/`.spokenText`, `remainingLevel(percent:)`, `compactTokens(_:)`, `costText(_:)` from Task 1, plus the existing `freshness(_:now:)` and `todayIsCurrent(_:now:)`.
- Produces:
  - `public enum WidgetQuotaStatus: Equatable, Sendable { case fresh(WidgetQuotaHeadline), stale(WidgetQuotaHeadline, lastCheckedAt: Date), awaitingFreshReading(WidgetQuotaHeadline), unavailable }`
  - `public struct WidgetQuotaColumn: Equatable, Sendable { title: String; figure: String; fraction: Double?; level: WidgetRemainingLevel?; isDimmed: Bool; detail: String; accessibilityLabel: String }` (internal memberwise init, used by tests through `@testable`)
  - `public struct WidgetTodayFooter: Equatable, Sendable { tokens: String; cost: String }`
  - `WidgetPresentation.providerTitle(_ provider: WidgetProvider) -> String`
  - `WidgetPresentation.quotaStatus(_ row: WidgetQuotaRow?, now: Date) -> WidgetQuotaStatus`
  - `WidgetPresentation.quotaColumn(for provider: WidgetProvider, in projection: WidgetProjection?, now: Date, calendar: Calendar, locale: Locale) -> WidgetQuotaColumn`
  - `WidgetPresentation.lastCheckedTime(_ checkedAt: Date, now: Date, calendar: Calendar, locale: Locale) -> String` (internal)
  - `WidgetPresentation.todayFooter(_ projection: WidgetProjection?, now: Date) -> WidgetTodayFooter?`
  - test helpers `posix`, `utc`, `weekly`, `primary`, `quota`, `noUsage`, `todayUsage`, `overview`, `column`, `shortText`, `currentDayAndOffset`

- [ ] **Step 1: Write the failing tests**

In `WidgetOverviewPresentationTests.swift`, inside `struct WidgetOverviewPresentationTests`, after `theColourLevelChangesBelowTwentyAndBelowTenPercent()`, add:

```swift

    // MARK: Columns

    @Test
    func aFreshColumnShowsTheWindowAndTheCountdown() throws {
        let projection = try overview(claude: quota(.claude, age: minute, headline: weekly(77, resetIn: 6 * day + 3 * hour)))
        #expect(column(.claude, projection) == WidgetQuotaColumn(
            title: "Claude",
            figure: "77%",
            fraction: 0.77,
            level: .normal,
            isDimmed: false,
            detail: "Weekly · resets in 6d",
            accessibilityLabel: "Claude, 77 percent remaining, weekly, resets in 6 days"
        ))
    }

    @Test
    func aFreshColumnWithoutAResetShowsTheWindowAlone() throws {
        let projection = try overview(codex: quota(.codex, age: minute, headline: primary(85, resetIn: nil)))
        #expect(column(.codex, projection) == WidgetQuotaColumn(
            title: "Codex",
            figure: "85%",
            fraction: 0.85,
            level: .normal,
            isDimmed: false,
            detail: "Primary",
            accessibilityLabel: "Codex, 85 percent remaining, primary"
        ))
    }

    @Test
    func aStaleColumnShowsWhenItWasLastCheckedWithTheTimeOnlyToday() throws {
        let claudeAge = 20 * minute
        let projection = try overview(
            claude: quota(.claude, age: claudeAge, headline: weekly(77, resetIn: day)),
            codex: quota(.codex, age: 15 * minute, headline: primary(85, resetIn: day))
        )
        let time = shortText(referenceDate.addingTimeInterval(-claudeAge), includingDate: false)
        #expect(column(.claude, projection) == WidgetQuotaColumn(
            title: "Claude",
            figure: "77%",
            fraction: 0.77,
            level: .normal,
            isDimmed: false,
            detail: "Last checked \(time)",
            accessibilityLabel: "Claude, 77 percent remaining, last checked \(time)"
        ))
        #expect(column(.codex, projection).detail.hasPrefix("Last checked "))

        let justFresh = try overview(codex: quota(.codex, age: 15 * minute - 1, headline: primary(85, resetIn: day)))
        #expect(column(.codex, justFresh).detail == "Primary · resets in 1d")

        let staleStream = try overview(claude: quota(.claude, age: minute, stream: .stale, headline: weekly(77, resetIn: day)))
        #expect(column(.claude, staleStream).detail.hasPrefix("Last checked "))
    }

    @Test
    func aStaleColumnFromAnEarlierDayShowsTheDateAndTime() throws {
        let checkedAt = referenceDate.addingTimeInterval(-9 * hour)
        let projection = try overview(claude: quota(.claude, age: 9 * hour, headline: weekly(77, resetIn: day)))
        let expected = shortText(checkedAt, includingDate: true)
        #expect(expected != shortText(checkedAt, includingDate: false))
        #expect(column(.claude, projection).detail == "Last checked \(expected)")
    }

    @Test
    func aPassedResetDimsTheFigureAndAwaitsAFreshReading() throws {
        let expected = WidgetQuotaColumn(
            title: "Claude",
            figure: "77%",
            fraction: 0.77,
            level: .normal,
            isDimmed: true,
            detail: "Awaiting fresh reading",
            accessibilityLabel: "Claude, 77 percent remaining, awaiting fresh reading"
        )
        let fresh = try overview(claude: quota(.claude, age: minute, headline: weekly(77, resetIn: -1)))
        #expect(column(.claude, fresh) == expected)
        let stale = try overview(claude: quota(.claude, age: hour, headline: weekly(77, resetIn: -1)))
        #expect(column(.claude, stale) == expected)
    }

    @Test
    func noDisplayableValueShowsADashNeverZero() throws {
        let expected = WidgetQuotaColumn(
            title: "Claude",
            figure: "—",
            fraction: nil,
            level: nil,
            isDimmed: false,
            detail: "Quota unavailable",
            accessibilityLabel: "Claude, quota unavailable"
        )
        #expect(column(.claude, nil) == expected)
        #expect(column(.claude, try overview()) == expected)
        let withoutHeadline = try overview(claude: quota(.claude, age: minute, headline: nil))
        #expect(column(.claude, withoutHeadline) == expected)
        let future = try overview(claude: quota(.claude, age: -minute, headline: weekly(77, resetIn: day)))
        #expect(column(.claude, future) == expected)
    }

    @Test
    func theColourLevelFollowsTheShownWholePercent() throws {
        func shown(_ remaining: Double) throws -> (String, WidgetRemainingLevel?) {
            let projection = try overview(claude: quota(.claude, age: minute, headline: weekly(remaining, resetIn: day)))
            let value = column(.claude, projection)
            return (value.figure, value.level)
        }
        #expect(try shown(19.6) == ("20%", .normal))
        #expect(try shown(19.4) == ("19%", .low))
        #expect(try shown(9.5) == ("10%", .low))
        #expect(try shown(9.4) == ("9%", .critical))
    }

    // MARK: Footer

    @Test
    func theFooterSumsOnlyProvidersWhoseTodayIsCurrent() throws {
        let projection = try overview(
            usage: [
                todayUsage(.claude, tokens: 1_234, cost: "1.25"),
                todayUsage(.codex, tokens: 878, cost: "2.50"),
                todayUsage(.cursor, tokens: 5_000, cost: "9.00", on: referenceDate.addingTimeInterval(-day)),
            ],
            today: WidgetTodaySummary(completeness: .complete, totalTokens: 7_112, estimatedCostUSD: Decimal(string: "12.75"))
        )
        #expect(WidgetPresentation.todayFooter(projection, now: referenceDate)
            == WidgetTodayFooter(tokens: "Today 2.1K tokens", cost: "$3.75"))
    }

    @Test
    func theFooterIsHiddenWithoutACurrentContributor() throws {
        #expect(WidgetPresentation.todayFooter(nil, now: referenceDate) == nil)
        #expect(WidgetPresentation.todayFooter(try overview(), now: referenceDate) == nil)
        let yesterdayOnly = try overview(
            usage: [
                todayUsage(.claude, tokens: 10, cost: "1.00", on: referenceDate.addingTimeInterval(-day)),
                noUsage(.codex),
                noUsage(.cursor),
            ],
            today: WidgetTodaySummary(completeness: .partial, totalTokens: 10, estimatedCostUSD: Decimal(string: "1.00"))
        )
        #expect(WidgetPresentation.todayFooter(yesterdayOnly, now: referenceDate) == nil)
    }
```

Append to the end of the file:

```swift
private let posix = Locale(identifier: "en_US_POSIX")

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func weekly(_ remaining: Double, resetIn seconds: TimeInterval?) -> WidgetQuotaHeadline {
    WidgetQuotaHeadline(id: .claudeWeekly, remainingPercent: remaining, resetsAt: seconds.map { referenceDate.addingTimeInterval($0) })
}

private func primary(_ remaining: Double, resetIn seconds: TimeInterval?) -> WidgetQuotaHeadline {
    WidgetQuotaHeadline(id: .codexPrimary, remainingPercent: remaining, resetsAt: seconds.map { referenceDate.addingTimeInterval($0) })
}

private func quota(
    _ provider: WidgetProvider,
    age: TimeInterval,
    stream: WidgetStreamState = .fresh,
    headline: WidgetQuotaHeadline?
) throws -> WidgetQuotaRow {
    try WidgetQuotaRow(provider: provider, stream: stream, lastSuccessfulAt: referenceDate.addingTimeInterval(-age), headline: headline)
}

private func noUsage(_ provider: WidgetProvider) -> WidgetUsageRow {
    WidgetUsageRow(provider: provider, stream: .unavailable, localDayKey: nil, utcOffsetSeconds: nil, lastSuccessfulAt: nil, todayTokens: nil, todayCostUSD: nil)
}

private func todayUsage(_ provider: WidgetProvider, tokens: UInt64, cost: String, on date: Date = referenceDate) -> WidgetUsageRow {
    let (dayKey, offset) = currentDayAndOffset(date)
    return WidgetUsageRow(provider: provider, stream: .fresh, localDayKey: dayKey, utcOffsetSeconds: offset, lastSuccessfulAt: referenceDate, todayTokens: tokens, todayCostUSD: Decimal(string: cost))
}

private func overview(
    claude: WidgetQuotaRow? = nil,
    codex: WidgetQuotaRow? = nil,
    usage: [WidgetUsageRow]? = nil,
    today: WidgetTodaySummary? = nil
) throws -> WidgetProjection {
    try WidgetProjection(
        quotaRows: [
            try claude ?? WidgetQuotaRow(provider: .claude, stream: .unavailable, lastSuccessfulAt: nil, headline: nil),
            try codex ?? WidgetQuotaRow(provider: .codex, stream: .unavailable, lastSuccessfulAt: nil, headline: nil),
        ],
        usageRows: usage ?? [noUsage(.claude), noUsage(.codex), noUsage(.cursor)],
        today: today ?? WidgetTodaySummary(completeness: .unavailable, totalTokens: nil, estimatedCostUSD: nil)
    )
}

private func column(_ provider: WidgetProvider, _ projection: WidgetProjection?) -> WidgetQuotaColumn {
    WidgetPresentation.quotaColumn(for: provider, in: projection, now: referenceDate, calendar: utc, locale: posix)
}

private func shortText(_ date: Date, includingDate: Bool) -> String {
    let formatter = DateFormatter()
    formatter.calendar = utc
    formatter.timeZone = utc.timeZone
    formatter.locale = posix
    formatter.dateStyle = includingDate ? .short : .none
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

private func currentDayAndOffset(_ date: Date) -> (String, Int) {
    let zone = TimeZone.current
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = zone
    formatter.dateFormat = "yyyy-MM-dd"
    return (formatter.string(from: date), zone.secondsFromGMT(for: date))
}
```

`referenceDate` is 2027-01-15 08:00 UTC, so a value 9 hours old is from the previous UTC day. The projections are built with `WidgetProjection.init`, which validates without a reference date, so a future last success (`age: -minute`) is accepted there, as it is not after `decode`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make swift-test SWIFT_TEST_FILTER=WidgetOverviewPresentationTests`
Expected: the build fails with `error: cannot find 'WidgetQuotaColumn' in scope` and `error: type 'WidgetPresentation' has no member 'quotaColumn'`.

- [ ] **Step 3: Write the implementation**

In `Sources/NeedlbarWidgetSupport/WidgetPresentation.swift`, insert after the closing brace of `WidgetRemainingLevel`:

```swift

/// What a quota column shows, before any text is made.
public enum WidgetQuotaStatus: Equatable, Sendable {
    case fresh(WidgetQuotaHeadline)
    case stale(WidgetQuotaHeadline, lastCheckedAt: Date)
    case awaitingFreshReading(WidgetQuotaHeadline)
    case unavailable
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
    public let accessibilityLabel: String
}

public struct WidgetTodayFooter: Equatable, Sendable {
    public let tokens: String
    public let cost: String
}
```

Insert after the closing brace of `remainingLevel(percent:)`:

```swift

    // MARK: Columns and footer

    public static func providerTitle(_ provider: WidgetProvider) -> String {
        switch provider {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }

    public static func quotaStatus(_ row: WidgetQuotaRow?, now: Date) -> WidgetQuotaStatus {
        guard let row,
              let headline = row.headline,
              headline.remainingPercent.isFinite,
              (0...100).contains(headline.remainingPercent),
              let checkedAt = row.lastSuccessfulAt else {
            return .unavailable
        }
        let state = freshness(row, now: now)
        guard state != .unavailable else { return .unavailable }
        if let reset = headline.resetsAt, reset <= now {
            return .awaitingFreshReading(headline)
        }
        return state == .fresh ? .fresh(headline) : .stale(headline, lastCheckedAt: checkedAt)
    }

    public static func quotaColumn(
        for provider: WidgetProvider,
        in projection: WidgetProjection?,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> WidgetQuotaColumn {
        let title = providerTitle(provider)
        let row = projection?.quotaRows.first { $0.provider == provider }
        let headline: WidgetQuotaHeadline
        let detail: String
        let spokenDetail: String
        var isDimmed = false
        switch quotaStatus(row, now: now) {
        case .unavailable:
            return WidgetQuotaColumn(
                title: title,
                figure: "—",
                fraction: nil,
                level: nil,
                isDimmed: false,
                detail: "Quota unavailable",
                accessibilityLabel: "\(title), quota unavailable"
            )
        case .fresh(let value):
            headline = value
            let window = value.id.categoryLabel
            if let reset = value.resetsAt, let countdown = countdown(until: reset, now: now) {
                detail = "\(window) · resets in \(countdown.text)"
                spokenDetail = "\(window.lowercased()), resets in \(countdown.spokenText)"
            } else {
                detail = window
                spokenDetail = window.lowercased()
            }
        case .stale(let value, let checkedAt):
            headline = value
            let time = lastCheckedTime(checkedAt, now: now, calendar: calendar, locale: locale)
            detail = "Last checked \(time)"
            spokenDetail = "last checked \(time)"
        case .awaitingFreshReading(let value):
            headline = value
            isDimmed = true
            detail = "Awaiting fresh reading"
            spokenDetail = "awaiting fresh reading"
        }
        let percent = Int(headline.remainingPercent.rounded())
        return WidgetQuotaColumn(
            title: title,
            figure: "\(percent)%",
            fraction: headline.remainingPercent / 100,
            level: remainingLevel(percent: percent),
            isDimmed: isDimmed,
            detail: detail,
            accessibilityLabel: "\(title), \(percent) percent remaining, \(spokenDetail)"
        )
    }

    /// The time only when it is the same day as `now`, otherwise the short date and time.
    static func lastCheckedTime(_ checkedAt: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateStyle = calendar.isDate(checkedAt, inSameDayAs: now) ? .none : .short
        formatter.timeStyle = .short
        return formatter.string(from: checkedAt)
    }

    /// Sums the providers whose today total is current. `nil` hides the footer.
    public static func todayFooter(_ projection: WidgetProjection?, now: Date) -> WidgetTodayFooter? {
        guard let projection else { return nil }
        var tokens: UInt64 = 0
        var cost = Decimal.zero
        var contributors = 0
        for row in projection.usageRows where todayIsCurrent(row, now: now) {
            guard let rowTokens = row.todayTokens, let rowCost = row.todayCostUSD else { continue }
            let (next, overflow) = tokens.addingReportingOverflow(rowTokens)
            guard !overflow else { return nil }
            var left = cost
            var right = rowCost
            var sum = Decimal()
            guard NSDecimalAdd(&sum, &left, &right, .plain) == .noError else { return nil }
            tokens = next
            cost = sum
            contributors += 1
        }
        guard contributors > 0 else { return nil }
        return WidgetTodayFooter(tokens: "Today \(compactTokens(tokens)) tokens", cost: costText(cost))
    }
```

The footer keeps the old view's rule (`NeedlbarOverviewWidget.swift:77-100`): only current rows with both values count, and an overflow hides the footer instead of showing a wrong total. Cursor's local usage still counts.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make swift-test SWIFT_TEST_FILTER=WidgetOverviewPresentationTests`
Expected: `Test run with 15 tests in 1 suite passed`, and make exits 0.

- [ ] **Step 5: Commit**

```bash
git add Sources/NeedlbarWidgetSupport/WidgetPresentation.swift Tests/NeedlbarWidgetSupportTests/WidgetOverviewPresentationTests.swift
git commit -m "feat(widget): add glanceable column and footer presentation" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Reload when the countdown text changes, at most once a minute

**Files:**
- Modify: `Sources/NeedlbarWidgetSupport/WidgetPresentation.swift:13` (constant) and `:56-71` (`nextDeadline`)
- Test: `Tests/NeedlbarWidgetSupportTests/WidgetOverviewPresentationTests.swift`

**Interfaces:**
- Consumes: `quotaStatus(_:now:)` (Task 2), `countdown(until:now:)` (Task 1).
- Produces:
  - `public static let minimumReloadInterval: TimeInterval = 60`
  - `WidgetPresentation.nextCountdownChange(until reset: Date, now: Date) -> Date?`
  - `WidgetPresentation.nextDeadline(after:projection:calendar:) -> Date`, same signature with the new rule, still called by `getTimeline` (`NeedlbarOverviewWidget.swift:45`)
  - test helper `nextReload(_:)`

- [ ] **Step 1: Write the failing tests**

Inside `struct WidgetOverviewPresentationTests`, after `theFooterIsHiddenWithoutACurrentContributor()`, add:

```swift

    // MARK: Reloads

    @Test
    func theNextCountdownChangeIsTheNextWholeDayOrHourBeforeTheReset() {
        func change(_ seconds: TimeInterval) -> Date? {
            WidgetPresentation.nextCountdownChange(until: referenceDate.addingTimeInterval(seconds), now: referenceDate)
        }
        #expect(change(3 * day + 5 * minute) == referenceDate.addingTimeInterval(5 * minute))
        #expect(change(2 * hour + 10 * minute) == referenceDate.addingTimeInterval(10 * minute))
        #expect(change(2 * hour) == referenceDate)
        #expect(change(59 * minute) == nil)
        #expect(change(0) == nil)
    }

    @Test
    func theNextReloadIncludesAFreshColumnsCountdownStep() throws {
        let hours = try overview(claude: quota(.claude, age: 0, headline: weekly(77, resetIn: 2 * hour + 10 * minute)))
        #expect(nextReload(hours) == referenceDate.addingTimeInterval(10 * minute))
        let days = try overview(codex: quota(.codex, age: 0, headline: primary(85, resetIn: 3 * day + 5 * minute)))
        #expect(nextReload(days) == referenceDate.addingTimeInterval(5 * minute))
    }

    @Test
    func aStaleColumnAddsNoCountdownStep() throws {
        let projection = try overview(claude: quota(.claude, age: 30 * minute, headline: weekly(77, resetIn: 2 * hour + 10 * minute)))
        #expect(nextReload(projection) == referenceDate.addingTimeInterval(2 * hour + 10 * minute))
    }

    @Test
    func theNextReloadIsNeverSoonerThanOneMinute() throws {
        let nearBoundary = try overview(claude: quota(.claude, age: 20 * minute - 10, headline: weekly(77, resetIn: nil)))
        #expect(nextReload(nearBoundary) == referenceDate.addingTimeInterval(minute))
        let onTheHour = try overview(claude: quota(.claude, age: 0, headline: weekly(77, resetIn: 2 * hour)))
        #expect(nextReload(onTheHour) == referenceDate.addingTimeInterval(minute))
    }
```

Append to the end of the file:

```swift

private func nextReload(_ projection: WidgetProjection) -> Date {
    WidgetPresentation.nextDeadline(after: referenceDate, projection: projection, calendar: utc)
}
```

In the stale case, the freshness boundary has already passed, so the candidates are the reset (+2 h 10 min) and UTC midnight (+16 h), and the reset wins. In `onTheHour`, the step falls exactly on `now`, so the floor gives +1 minute.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make swift-test SWIFT_TEST_FILTER=WidgetOverviewPresentationTests`
Expected: the build fails with `error: type 'WidgetPresentation' has no member 'nextCountdownChange'`.

- [ ] **Step 3: Write the implementation**

Insert after `public static let claudeQuotaFreshnessHorizon: TimeInterval = 20 * 60`:

```swift
    /// The widget never asks WidgetKit to reload sooner than this after the current entry.
    public static let minimumReloadInterval: TimeInterval = 60
```

Replace the whole of `nextDeadline(after:projection:calendar:)`, from `    public static func nextDeadline(` through its closing brace (lines 56-71), with:

```swift
    // MARK: Reloads

    /// The next moment a fresh column's countdown text changes, or `nil` within the last
    /// hour, where the reset itself is the next change. Equals `now` when `now` sits exactly
    /// on a step; `nextDeadline` then waits `minimumReloadInterval`.
    public static func nextCountdownChange(until reset: Date, now: Date) -> Date? {
        switch countdown(until: reset, now: now) {
        case .days(let days):
            return reset.addingTimeInterval(-Double(days) * secondsPerDay)
        case .hours(let hours):
            return reset.addingTimeInterval(-Double(hours) * secondsPerHour)
        case .underOneHour, nil:
            return nil
        }
    }

    /// The earliest of a freshness boundary, a reset, local midnight and a fresh column's
    /// next countdown step, but never sooner than `minimumReloadInterval` after `now`.
    public static func nextDeadline(
        after now: Date,
        projection: WidgetProjection,
        calendar: Calendar
    ) -> Date {
        let stale = projection.quotaRows.compactMap { row in
            row.lastSuccessfulAt?.addingTimeInterval(quotaHorizon(for: row.provider))
        } + projection.usageRows.compactMap { $0.lastSuccessfulAt?.addingTimeInterval(freshnessHorizon) }
        let reset = projection.quotaRows.compactMap(\.headline?.resetsAt)
        let midnight = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0),
            matchingPolicy: .nextTime
        )!
        let countdownSteps = projection.quotaRows.compactMap { row -> Date? in
            guard case .fresh(let headline) = quotaStatus(row, now: now),
                  let reset = headline.resetsAt else { return nil }
            return nextCountdownChange(until: reset, now: now)
        }
        let earliest = ((stale + reset + [midnight]).filter { $0 > now } + countdownSteps).min()!
        return max(earliest, now.addingTimeInterval(minimumReloadInterval))
    }
```

The existing deadlines and their `> now` filter are unchanged. Countdown steps skip that filter because a step can equal `now`, and the floor handles it.

- [ ] **Step 4: Run all support tests to verify they pass**

Run: `make swift-test SWIFT_TEST_FILTER=NeedlbarWidgetSupportTests`
Expected: `Test run with 35 tests in 2 suites passed`, including the unchanged `theNextDeadlineUsesTheClaudeQuotaRowsOwnHorizon`, and make exits 0.

- [ ] **Step 5: Confirm the unchanged widget still compiles for real**

Run: `./scripts/build-widget-extension.sh`
Expected: exit 0, codesign reports `valid on disk`, and the last line is `widget extension built with synthetic App Group identity`.

- [ ] **Step 6: Commit**

```bash
git add Sources/NeedlbarWidgetSupport/WidgetPresentation.swift Tests/NeedlbarWidgetSupportTests/WidgetOverviewPresentationTests.swift
git commit -m "feat(widget): reload when the countdown text changes" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The glanceable layout, cleanup and records

**Files:**
- Modify: `WidgetExtension/NeedlbarOverviewWidget.swift:59-180`
- Modify: `Sources/NeedlbarWidgetSupport/WidgetPresentation.swift:51-54` (delete `resetLabel`)
- Modify: `Tests/NeedlbarWidgetSupportTests/WidgetProjectionTests.swift:244-250` (delete its test)
- Modify: `docs/superpowers/specs/2026-08-31-needlbar-v0.2.1-widgets-notifications-design.md:70`
- Modify: `docs/STATUS.md:1`

**Interfaces:**
- Consumes: `WidgetPresentation.quotaColumn(for:in:now:calendar:locale:)`, `WidgetQuotaColumn`, `WidgetRemainingLevel`, `WidgetPresentation.todayFooter(_:now:)`, `WidgetTodayFooter` (Task 2); `nextDeadline` (Task 3, through the unchanged `getTimeline`).
- Produces: the shipped view `OverviewWidgetView` and the private `QuotaColumnView` and `QuotaBar`. No later task depends on them.

- [ ] **Step 1: Replace the view**

In `WidgetExtension/NeedlbarOverviewWidget.swift`, replace everything from `struct OverviewWidgetView: View {` (line 59) through its closing brace (line 180) with:

```swift
struct OverviewWidgetView: View {
    let entry: OverviewEntry

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private func column(_ provider: WidgetProvider) -> WidgetQuotaColumn {
        WidgetPresentation.quotaColumn(
            for: provider,
            in: entry.projection,
            now: entry.date,
            calendar: calendar,
            locale: .current
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 14) {
                QuotaColumnView(column: column(.claude), accent: .orange)
                QuotaColumnView(column: column(.codex), accent: .blue)
            }
            Spacer(minLength: 0)
            if let footer = WidgetPresentation.todayFooter(entry.projection, now: entry.date) {
                HStack {
                    Text(footer.tokens)
                    Spacer()
                    Text(footer.cost)
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
        }
        .widgetURL(URL(string: "needlbar://overview"))
    }
}

private struct QuotaColumnView: View {
    let column: WidgetQuotaColumn
    let accent: Color

    private var warning: Color? {
        switch column.level {
        case .critical: .red
        case .low: .orange
        case .normal, nil: nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(column.title)
                .font(.headline)
            Text(column.figure)
                .font(.system(size: 36, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(warning ?? Color.primary)
                .opacity(column.isDimmed ? 0.45 : 1)
            QuotaBar(fraction: column.fraction, fill: warning ?? accent)
                .opacity(column.isDimmed ? 0.45 : 1)
            Text(column.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(column.accessibilityLabel)
    }
}

private struct QuotaBar: View {
    let fraction: Double?
    let fill: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                if let fraction {
                    Capsule()
                        .fill(fill)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
        }
        .frame(height: 6)
    }
}
```

Lines 1-57 (file reading, `OverviewEntry`, `OverviewProvider`) and 182-197 (`NeedlbarOverviewWidget`, the bundle) stay exactly as they are. The calendar matches `getTimeline` (`NeedlbarOverviewWidget.swift:42-43`). The provider accents are the one place to change if the user picks other colours (Decision 6).

- [ ] **Step 2: Delete `resetLabel` and its test**

In `Sources/NeedlbarWidgetSupport/WidgetPresentation.swift`, delete these lines and the blank line after them:

```swift
    public static func resetLabel(_ reset: Date?, now: Date, formatter: DateFormatter) -> String? {
        guard let reset else { return nil }
        return reset <= now ? "Awaiting fresh reading" : formatter.string(from: reset)
    }
```

In `Tests/NeedlbarWidgetSupportTests/WidgetProjectionTests.swift`, delete these lines (244-249) and the blank line after them:

```swift
    @Test
    func passedResetUsesFixedAwaitingFreshReadingLabel() {
        let formatter = DateFormatter()
        #expect(WidgetPresentation.resetLabel(referenceDate.addingTimeInterval(-1), now: referenceDate, formatter: formatter) == "Awaiting fresh reading")
        #expect(WidgetPresentation.resetLabel(nil, now: referenceDate, formatter: formatter) == nil)
    }
```

- [ ] **Step 3: Compile the widget for real**

Run:

```bash
mkdir -p .build
./scripts/build-widget-extension.sh > .build/widget-build.log 2>&1; echo "build exit $?"
grep -ci warning .build/widget-build.log
tail -1 .build/widget-build.log
```

Expected: `build exit 0`, then `0` (no compiler warnings), then `widget extension built with synthetic App Group identity`. The log also shows codesign's `valid on disk` and `satisfies its Designated Requirement`. `.build/` is git-ignored.

- [ ] **Step 4: Check that removed text and forbidden words are gone**

Run:

```bash
rg -n 'Fresh ·|Stale ·|"Fresh"|"Stale"|"Partial"|"Complete"|Today updated|Today unavailable|Cursor —|resetLabel|AcceptanceFixture' WidgetExtension/NeedlbarOverviewWidget.swift Sources/NeedlbarWidgetSupport/WidgetPresentation.swift; echo "rg exit $?"
rg -n 'resetLabel' Sources Tests; echo "rg exit $?"
```

Expected: no matches, and `rg exit 1` twice.

- [ ] **Step 5: Run the widget build and search-guard checks**

Run: `make widget-extension-test`
Expected: `widget-extension search-guard regression passed` and then `widget-extension build/metadata contract passed`, and make exits 0.

- [ ] **Step 6: Run all support tests**

Run: `make swift-test SWIFT_TEST_FILTER=NeedlbarWidgetSupportTests`
Expected: `Test run with 34 tests in 2 suites passed`, and make exits 0.

- [ ] **Step 7: Commit the layout**

```bash
git add WidgetExtension/NeedlbarOverviewWidget.swift Sources/NeedlbarWidgetSupport/WidgetPresentation.swift Tests/NeedlbarWidgetSupportTests/WidgetProjectionTests.swift
git commit -m "feat(widget): show Claude and Codex as glanceable columns" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 8: Add the dated amendment to the 2026-08-31 design**

In `docs/superpowers/specs/2026-08-31-needlbar-v0.2.1-widgets-notifications-design.md`, insert after the paragraph ending `existing app UI; it does not promise a refresh.` (line 69), before the blank line and `### 3.2 Freshness and Staleness`:

```markdown

> **Amendment — 2026-11-06:** Approved by the user in
> `2026-11-06-glanceable-overview-widget-design.md`. The widget shows Claude and Codex as two
> columns, each with its remaining percent, a bar and one line, and a fresh row shows its
> reset as a countdown. The title row with its freshness indicator and the fixed Cursor row
> are removed. The today summary shows no completeness or freshness word and is hidden when
> no provider has a current today total; Cursor's local usage still counts toward it. A stale
> row shows **Last checked** with its time instead of a separate freshness line. The other
> rules stand: the headline selection, fixed labels, no raw titles or errors, **Quota
> unavailable** instead of zero, and the fixed `needlbar://overview` tap URL.
```

- [ ] **Step 9: Add the STATUS entry**

In `docs/STATUS.md`, insert after line 1 (`# Needlbar Development Status`), before `## 2026-11-05 Claude usage report source: local observation (not released)`:

```markdown

## 2026-11-06 Glanceable Overview widget (prepared, not released)

Implements `docs/superpowers/specs/2026-11-06-glanceable-overview-widget-design.md` through
`docs/superpowers/plans/2026-11-06-glanceable-overview-widget.md`. Not merged, installed, tagged or
released, and not yet seen on a real widget.

- **Layout.** Claude and Codex each get a column with the remaining percent of the headline window,
  a bar, and one line: `<window> · resets in <time>`, **Last checked** when stale, **Awaiting fresh
  reading** after a passed reset, or `—` with **Quota unavailable**. A footer shows today's tokens and
  estimated cost from providers whose today total is current, and is hidden when there are none. The
  title row, the Fresh/Stale and Partial/Complete words, the Cursor row and the Today updated line are
  gone.
- **Colour.** Below 20 percent the figure and bar use system orange, below 10 percent system red,
  judged on the whole percent shown. Bar accents are system orange for Claude and system blue for
  Codex.
- **Reloads.** The timeline also reloads when a fresh column's countdown text changes, and never
  sooner than one minute after the current entry.
- **Unchanged.** The projection, App Group contract, refresh behaviour, widget family and
  `needlbar://overview` tap target.
- **Verified.** Pure presentation tests, a real compile of the widget extension, the widget build and
  search-guard checks, and `make test`. Light and dark appearance on an installed widget is the user's
  manual check and has not been done.
```

- [ ] **Step 10: Run the full project gate**

Run: `make test`
Expected: exit 0. The STATUS entry contains no hash, run ID, asset ID, `releases/tag/` or `report 0.3.`, so `notarize-test` is unaffected.

- [ ] **Step 11: Commit the records**

```bash
git add docs/superpowers/specs/2026-08-31-needlbar-v0.2.1-widgets-notifications-design.md docs/STATUS.md
git commit -m "docs: record the glanceable Overview widget" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Manual check (USER-RUN, not for implementers)

When the user separately asks for an installed build, they check the widget in light and dark appearance, with a fresh value and, if one occurs, an old value. They also check that nothing clips at the medium size and that VoiceOver reads each column as one element. Implementers do not package, install or launch the app.

---

## Self-Review

**Spec coverage**

| Spec | Where |
|---|---|
| §1 header read Stale because of Cursor's row | Task 4 removes the header; columns judge their own freshness (Task 2) |
| §2 two columns, footer, headline window, window labels | Task 2 `quotaColumn` (uses the projection's headline and `categoryLabel`), Task 4 layout |
| §2 Fable not shown | No Fable value in the projection (`WidgetProjection.swift:15-19`); nothing added |
| §2 removed items | Task 4 Steps 1 and 4 |
| §3 percent, countdown, tokens, cost | Task 1 (`countdown`, `compactTokens`, `costText`), Task 2 (`Int(rounded())`) |
| §3 today footer, hidden without current contributors | Task 2 `todayFooter` and its two tests |
| §4 four states and their text | Task 2 column tests (fresh, stale today and earlier day, passed reset, unavailable) |
| §4 orange below 20, red below 10, no colour when unavailable | Task 1 level test, Task 2 shown-percent and unavailable tests, Task 4 `warning` mapping |
| §4 no invented values | Task 2 `noDisplayableValueShowsADashNeverZero` |
| §5 countdown reload steps, existing deadlines, once a minute | Task 3 |
| §6 one VoiceOver element per column, wording | Task 2 `accessibilityLabel` assertions, Task 4 `.accessibilityElement(children: .ignore)` |
| §6 system colours, provider accents on the bar only | Task 4 (`.orange`, `.red`, `.blue`, `.primary`, `.secondary`, `.quaternary`); Decision 6 |
| §7 automated tests; build and search-guard checks still pass | Tasks 1-3 tests; Task 4 Steps 3-6 and 10 |
| §7 manual light and dark check | Manual check (USER-RUN) |
| §8 dated note in the 2026-08-31 design | Task 4 Step 8 |
| STATUS entry | Task 4 Step 9 |

**Placeholder scan:** every code step has complete code, and every command has its expected result. No step says to handle edge cases without code.

**Type consistency:** `WidgetCountdown`, `WidgetRemainingLevel`, `WidgetQuotaStatus`, `WidgetQuotaColumn` (`title`, `figure`, `fraction`, `level`, `isDimmed`, `detail`, `accessibilityLabel`) and `WidgetTodayFooter` (`tokens`, `cost`) match between their definitions (Tasks 1 and 2), the tests, and the view (Task 4). `quotaColumn(for:in:now:calendar:locale:)`, `todayFooter(_:now:)`, `nextCountdownChange(until:now:)` and `nextDeadline(after:projection:calendar:)` are spelled the same everywhere. The test counts are 6 after Task 1, 15 after Task 2, and 19 after Task 3 in the new suite. `WidgetProjectionTests` has 16 until Task 4 deletes one, leaving 15, so the totals are 35 and then 34.
