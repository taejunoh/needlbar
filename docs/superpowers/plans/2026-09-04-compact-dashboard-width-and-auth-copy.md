# Compact dashboard width and auth copy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Make only the main system-dashboard popover 312 points wide and make its quota/authentication copy fit and remain unambiguous at that width.

**Architecture:** SystemDashboardPanelSizing remains the sole width owner, so the measurement host, visible host, and frame-only resize path share 312 points. SystemDashboardPresentation owns the Remaining caption, DashboardReadabilityPolicy owns compact provider-status composition, and SystemDashboardPopoverView owns the short visible login label plus full accessibility/help identity. Do not alter snapshot, refresh, login-routing, Fable, menu-bar, or persistence behavior.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing, SwiftPM, existing Make package/smoke scripts, and the existing development-only packaged macOS app; no new dependencies.

---

## Authority, workspace, and execution rules

The approved source of truth is docs/superpowers/specs/2026-09-04-compact-dashboard-width-and-auth-copy-design.md. Read AGENTS.md, docs/STATUS.md, that spec, and this plan before implementation. The 2026-09-03 adaptive-sizing plan remains authoritative for measurement, screen clamping, in-place resizing, anchoring, scrolling, and native-evidence safety.

Execute only in:

~~~
/Users/taejunoh/Developer/LFG/needlbar/.worktrees/compact-dashboard-width-copy
~~~

Do not touch the parent checkout's dirty state, other worktrees, public v0.2.2 app, widgets, credentials, persisted settings except a restored native-inspection configuration, or untracked brainstorming files. Do not push, merge, publish, release, distribution-sign, or notarize.

Use strict TDD: write/adjust assertions, run focused RED, make only the listed production edit, run focused GREEN and git diff --check, then commit. Source Cargo before every Make command:

~~~
source /Users/taejunoh/.cargo/env
~~~

Run Make recipes serially. A focused test, fixture, mock-up, or macOS 26 host result is not native macOS 14 acceptance.

## Scope and invariants

- Only SystemDashboardPanelSizing.width changes from 340 to 312. Measurement and visible roots, initial presentation, and frame-only resize consume the constant.
- Preserve finite-positive natural height, 680 fallback, 180 minimum, 24-point inset, screen clamp, fixed header/footer, scrolling body, shared hierarchy, resize epsilon, original anchor, and no re-presentation for numeric equal-height updates.
- Remaining is exactly Quota remaining. Usage, Cost, Connection, quota selection, and absent-quota em dash behavior stay unchanged.
- Fresh/unavailable statuses remain omitted. A singleton abnormal stream is exactly Stale, Error, or Sign-in required. Two abnormal streams are exactly Usage <lower-case phrase> · Quota <lower-case phrase>.
- Browser login visibly reads Sign in. Its help and accessibility retain Sign in with Claude or Sign in with ChatGPT. Cursor remains Open Cursor Spending everywhere. Existing dismissal and callbacks remain unchanged.
- Do not change Fable, CPU graph/value alignment, metric selections, data/auth/refresh flows, Settings, Analytics…, menu-bar content, widgets, notifications, exports, package layout, signing, or release metadata.

## File map

| File | Responsibility |
| --- | --- |
| Sources/Needlbar/Modules/Overview/SystemDashboardPopoverSizing.swift | Change the sole fixed-width constant; preserve the height/resize policy. |
| Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift | Change only the Remaining caption generated for dashboard presentation. |
| Sources/Needlbar/Modules/Overview/SystemDashboardDisplayComponents.swift | Compose approved compact singleton and qualified provider statuses only. |
| Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift | Render Sign in for browser controls while retaining provider-specific accessibility/help text and Cursor title. |
| Tests/NeedlbarTests/MenuPanelPlacementTests.swift | Change the pure sizing-policy width expectation to 312. |
| Tests/NeedlbarTests/SystemDashboardPopoverTests.swift | Cover both fitting roots, existing height/all-enabled/Fable behavior, captions, statuses, and control copy identity. |
| Tests/NeedlbarTests/MenuBarControllerTests.swift | Change initial/resized panel width assertions to 312 while retaining anchoring/no-churn/action routing coverage. |
| README.md | Only after qualifying native evidence, state verified 312-point/short-copy behavior and reference the native capture. |
| docs/images/system-dashboard.png | Only after qualifying native evidence, hold the sanitized exact-app 312-point capture. |
| docs/STATUS.md | After verification, record commands, exact artifact/reinstall identity, evidence, limitations, and continuation point. |

No new Swift files, Package manifest entries, preference keys, fixtures, or bridge/runtime APIs are needed.

### Task 1: Make the shared dashboard width 312 points and retain sizing behavior

**Files:**

- Modify: Tests/NeedlbarTests/MenuPanelPlacementTests.swift
- Modify: Tests/NeedlbarTests/SystemDashboardPopoverTests.swift
- Modify: Tests/NeedlbarTests/MenuBarControllerTests.swift
- Modify: Sources/Needlbar/Modules/Overview/SystemDashboardPopoverSizing.swift

- [ ] **Step 1: Write the 312-point RED assertions.**

In MenuPanelPlacementTests.dashboardSizingUsesApprovedWidthAndMeasuredHeight, replace only the width assertion:

~~~swift
#expect(SystemDashboardPanelSizing.width == 312)
~~~

Append this test to SystemDashboardPopoverTests.swift:

~~~swift
@Test @MainActor func dashboardMeasurementAndVisibleHostsUse312PointWidth() {
    let model = SystemDashboardModel(
        snapshot: dashboardFixtureSnapshot(),
        configuration: SystemMonitorConfiguration()
    )
    let measuring = NSHostingController(rootView: SystemDashboardPopoverView(measuring: model))
    let visible = NSHostingController(
        rootView: SystemDashboardPopoverView(model: model, height: 320)
    )

    measuring.view.layoutSubtreeIfNeeded()
    visible.view.layoutSubtreeIfNeeded()

    #expect(measuring.view.fittingSize.width == 312)
    #expect(visible.view.fittingSize == NSSize(width: 312, height: 320))
}
~~~

In dashboardVisibleViewUsesMeasuredOrScreenLimitedHeight and dashboardReadabilityKeepsSizeStableAcrossAppearances replace every expected 340 width with 312. Rename overviewUsesMeasured340PointContentBeforeFirstPresentation to overviewUsesMeasured312PointContentBeforeFirstPresentation and change its first-presented NSSize width to 312. In visibleModuleChangeResizesWithoutRepresentingAndKeepsAnchor change only resizedSizes.first?.width to 312. Keep all existing height, anchor, hosting-controller, numeric-no-churn, Fable, CPU, truncation, and appearance assertions.

- [ ] **Step 2: Run focused RED.**

Run:

~~~bash
source /Users/taejunoh/.cargo/env
make swift-test SWIFT_TEST_FILTER='dashboardSizingUsesApprovedWidthAndMeasuredHeight|dashboardMeasurementAndVisibleHostsUse312PointWidth|dashboardVisibleViewUsesMeasuredOrScreenLimitedHeight|dashboardReadabilityKeepsSizeStableAcrossAppearances|overviewUsesMeasured312PointContentBeforeFirstPresentation|visibleModuleChangeResizesWithoutRepresentingAndKeepsAnchor'
~~~

Expected: FAIL because the sizing constant and both fitting roots still report 340. Existing height-policy assertions pass; do not alter them.

- [ ] **Step 3: Change the sole width owner.**

In SystemDashboardPopoverSizing.swift, make this one-line replacement. Leave height(...) and shouldResize(...) unchanged.

~~~swift
static let width: CGFloat = 312
~~~

SystemDashboardPopoverView already uses SystemDashboardPanelSizing.width for measuring and visible roots; MenuBarController already uses it for resize(to:anchoredAt:). Do not duplicate 312 in either file.

- [ ] **Step 4: Run focused GREEN.**

Run:

~~~bash
source /Users/taejunoh/.cargo/env
make swift-test SWIFT_TEST_FILTER='dashboardSizing|dashboardMeasurementAndVisibleHostsUse312PointWidth|dashboardNaturalHeightTracksEnabledModulesAndProviders|dashboardVisibleViewUsesMeasuredOrScreenLimitedHeight|dashboardReadabilityFittingIsStableAcrossLiveNumericChanges|dashboardReadabilityKeepsSizeStableAcrossAppearances|overviewUsesMeasured312PointContentBeforeFirstPresentation|visibleModuleChangeResizesWithoutRepresentingAndKeepsAnchor|visibleAIProviderChangeResizesWithoutRepresentingAndKeepsAnchor|failedResizeKeepsTheInstalledDashboardLayoutUnchanged'
git diff --check
~~~

Expected: PASS. This covers both 312-point roots, existing 180/680/24-point policy, all-enabled/Fable ordering, structural frame-only resize with original anchor, and numeric equal-height no-resize.

- [ ] **Step 5: Commit the width-only slice.**

~~~bash
git add \
  Sources/Needlbar/Modules/Overview/SystemDashboardPopoverSizing.swift \
  Tests/NeedlbarTests/MenuPanelPlacementTests.swift \
  Tests/NeedlbarTests/SystemDashboardPopoverTests.swift \
  Tests/NeedlbarTests/MenuBarControllerTests.swift
git commit -m "feat: compact dashboard width"
~~~

Expected: one focused commit containing only the shared-width production edit and its assertions.

### Task 2: Shorten Remaining and provider-status presentation copy

**Files:**

- Modify: Tests/NeedlbarTests/SystemDashboardPopoverTests.swift
- Modify: Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift
- Modify: Sources/Needlbar/Modules/Overview/SystemDashboardDisplayComponents.swift

- [ ] **Step 1: Write caption and status RED tests.**

In dashboardPresentationDefaultsToRemainingEvenWhenTokenUsageExists replace the old caption expectation:

~~~swift
#expect(presentation.ai.first(where: { $0.provider == .claude })?.caption == "Quota remaining")
~~~

Add this exact caption/no-quota regression:

~~~swift
@Test func dashboardPresentationKeepsNonRemainingCaptionsAndNoQuotaPlaceholder() {
    for (metric, caption) in [
        (AIProviderDisplayMetric.usage, "Tokens today"),
        (.cost, "Estimated cost today"),
        (.connectionStatus, "Connection"),
    ] {
        var configuration = SystemMonitorConfiguration()
        configuration.ai[.claude] = AIProviderDisplayPreference(metric: metric)
        let presentation = SystemDashboardPresentation(
            snapshot: dashboardFixtureSnapshot(), configuration: configuration
        )
        #expect(presentation.ai.first { $0.provider == .claude }?.caption == caption)
    }

    let noQuota = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(claudeHasQuota: false),
        configuration: SystemMonitorConfiguration()
    )
    #expect(noQuota.ai.first { $0.provider == .claude }?.value == "—")
}
~~~

Replace the two current provider-status tests with:

~~~swift
@Test func dashboardReadabilityUsesCompactSingletonProviderStatuses() {
    #expect(DashboardReadabilityPolicy.providerStatus(usage: .fresh, quota: .fresh) == nil)
    #expect(DashboardReadabilityPolicy.providerStatus(usage: .unavailable, quota: .unavailable) == nil)
    #expect(DashboardReadabilityPolicy.providerStatus(usage: .stale, quota: .fresh) == "Stale")
    #expect(DashboardReadabilityPolicy.providerStatus(usage: .fresh, quota: .error) == "Error")
    #expect(DashboardReadabilityPolicy.providerStatus(usage: .fresh, quota: .requiresAuthentication) == "Sign-in required")
}

@Test func dashboardReadabilityQualifiesTwoAbnormalProviderStreamsWithCompactPhrases() {
    #expect(DashboardReadabilityPolicy.providerStatus(usage: .stale, quota: .error) == "Usage stale · Quota error")
    #expect(DashboardReadabilityPolicy.providerStatus(usage: .error, quota: .requiresAuthentication) == "Usage error · Quota sign-in required")
    #expect(DashboardReadabilityPolicy.providerStatus(usage: .stale, quota: .stale) == "Usage stale · Quota stale")
    #expect(DashboardReadabilityPolicy.providerStatus(usage: .unavailable, quota: .fresh) == nil)
}
~~~

Change the final expected status in dashboardReadabilityPreservesUnavailableAndStalePresentation to Sign-in required. Preserve its last-known-good value assertions.

- [ ] **Step 2: Run focused RED.**

~~~bash
source /Users/taejunoh/.cargo/env
make swift-test SWIFT_TEST_FILTER='dashboardPresentationDefaultsToRemainingEvenWhenTokenUsageExists|dashboardPresentationKeepsNonRemainingCaptionsAndNoQuotaPlaceholder|dashboardReadabilityUsesCompactSingletonProviderStatuses|dashboardReadabilityQualifiesTwoAbnormalProviderStreamsWithCompactPhrases|dashboardReadabilityPreservesUnavailableAndStalePresentation'
~~~

Expected: FAIL on old Most constrained quota remaining, Quota Authentication required, and title-cased qualified strings. Non-Remaining and no-quota regressions already pass.

- [ ] **Step 3: Implement the presentation-only strings.**

In SystemDashboardModel.providerCaption(_:) replace only this branch:

~~~swift
case .remaining: "Quota remaining"
~~~

Replace the complete providerStatus(usage:quota:) body in SystemDashboardDisplayComponents.swift with:

~~~swift
static func providerStatus(usage: PresentationFreshness, quota: PresentationFreshness) -> String? {
    let abnormal = [("Usage", usage), ("Quota", quota)].compactMap { stream, freshness -> (String, PresentationFreshness)? in
        switch freshness {
        case .fresh, .unavailable:
            nil
        case .stale, .requiresAuthentication, .error:
            (stream, freshness)
        }
    }

    guard !abnormal.isEmpty else { return nil }
    if abnormal.count == 1 {
        switch abnormal[0].1 {
        case .stale: return "Stale"
        case .requiresAuthentication: return "Sign-in required"
        case .error: return "Error"
        case .fresh, .unavailable: preconditionFailure("filtered above")
        }
    }

    return abnormal.map { stream, freshness in
        let phrase: String
        switch freshness {
        case .stale: phrase = "stale"
        case .requiresAuthentication: phrase = "sign-in required"
        case .error: phrase = "error"
        case .fresh, .unavailable: preconditionFailure("filtered above")
        }
        return "\(stream) \(phrase)"
    }
    .joined(separator: " · ")
}
~~~

Do not modify PresentationFreshness, DataStatus, fableStatus(_:), data models, refresh/auth code, or Settings.

- [ ] **Step 4: Run focused GREEN and neighboring regressions.**

~~~bash
source /Users/taejunoh/.cargo/env
make swift-test SWIFT_TEST_FILTER='dashboardPresentation|dashboardReadability|dashboardFable|ProviderSnapshotStore|BridgeDecoding'
git diff --check
~~~

Expected: PASS. Dashboard copy alone changes; Fable freshness/reset stays intact, missing quota remains an em dash, and bridge/store behavior is unchanged.

- [ ] **Step 5: Commit the copy slice.**

~~~bash
git add \
  Sources/Needlbar/Modules/Overview/SystemDashboardModel.swift \
  Sources/Needlbar/Modules/Overview/SystemDashboardDisplayComponents.swift \
  Tests/NeedlbarTests/SystemDashboardPopoverTests.swift
git commit -m "feat: compact dashboard quota copy"
~~~

Expected: one presentation-only commit with no collector, bridge, persistence, Fable, or menu-bar file.

### Task 3: Shorten browser-login button text without losing provider identity

**Files:**

- Modify: Tests/NeedlbarTests/SystemDashboardPopoverTests.swift
- Modify: Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift
- Verify only: Tests/NeedlbarTests/MenuBarControllerTests.swift

- [ ] **Step 1: Add the view-copy RED test and preserve callback tests.**

Append this test:

~~~swift
@Test func dashboardBrowserLoginControlUsesShortVisibleTextAndFullProviderIdentity() {
    let claude = ProviderAuthenticationAction.browserLogin(title: "Sign in with Claude")
    let codex = ProviderAuthenticationAction.browserLogin(title: "Sign in with ChatGPT")
    let cursor = ProviderAuthenticationAction.openCursorSpending(title: "Open Cursor Spending")

    #expect(SystemDashboardPopoverView.visibleActionTitle(for: claude) == "Sign in")
    #expect(SystemDashboardPopoverView.visibleActionTitle(for: codex) == "Sign in")
    #expect(SystemDashboardPopoverView.visibleActionTitle(for: cursor) == "Open Cursor Spending")
    #expect(SystemDashboardPopoverView.accessibilityActionTitle(for: claude) == "Sign in with Claude")
    #expect(SystemDashboardPopoverView.accessibilityActionTitle(for: codex) == "Sign in with ChatGPT")
    #expect(SystemDashboardPopoverView.accessibilityActionTitle(for: cursor) == "Open Cursor Spending")
}
~~~

Do not weaken dashboardPresentationOffersOnlyExistingProviderAuthenticationActions, authenticationActionsRouteClaudeAndCodexToTheLoginCallbackExactlyOnce, cursorSpendingActionOpensFixedDashboardWithoutLoginOrSettings, or presentedProviderAuthenticationActionsDismissBeforeTheirCallbacks. They establish provider identity, once-only callbacks, and dismissal order.

- [ ] **Step 2: Run focused RED.**

~~~bash
source /Users/taejunoh/.cargo/env
make swift-test SWIFT_TEST_FILTER='dashboardBrowserLoginControlUsesShortVisibleTextAndFullProviderIdentity|dashboardPresentationOffersOnlyExistingProviderAuthenticationActions|authenticationActionsRouteClaudeAndCodexToTheLoginCallbackExactlyOnce|cursorSpendingActionOpensFixedDashboardWithoutLoginOrSettings|presentedProviderAuthenticationActionsDismissBeforeTheirCallbacks'
~~~

Expected: compilation FAIL because the two view-local copy functions do not exist. Do not change ProviderAuthenticationAction, MenuBarController, or Settings.

- [ ] **Step 3: Add view-local mapping and apply it to the button.**

Add these internal static helpers immediately above the existing private actionTitle(_:) helper:

~~~swift
static func visibleActionTitle(for action: ProviderAuthenticationAction) -> String {
    switch action {
    case .browserLogin:
        "Sign in"
    case let .openCursorSpending(title):
        title
    }
}

static func accessibilityActionTitle(for action: ProviderAuthenticationAction) -> String {
    switch action {
    case let .browserLogin(title), let .openCursorSpending(title):
        title
    }
}
~~~

Replace only the providerRow(_:) action-button block with:

~~~swift
if let action = provider.action {
    let visibleTitle = Self.visibleActionTitle(for: action)
    let identityTitle = Self.accessibilityActionTitle(for: action)
    Button(visibleTitle) { onProviderAction(provider.provider) }
        .buttonStyle(.borderless)
        .font(.caption)
        .help(identityTitle)
        .accessibilityLabel(identityTitle)
}
~~~

Delete the now-unused private actionTitle(_:) helper. Keep the containing .accessibilityElement(children: .contain), fableStatus(_:), footer buttons, Settings labels, and existing callbacks unchanged.

- [ ] **Step 4: Run focused GREEN.**

~~~bash
source /Users/taejunoh/.cargo/env
make swift-test SWIFT_TEST_FILTER='dashboardBrowserLoginControlUsesShortVisibleTextAndFullProviderIdentity|dashboardPresentationOffersOnlyExistingProviderAuthenticationActions|dashboardReadability|dashboardFable|authenticationActionsRouteClaudeAndCodexToTheLoginCallbackExactlyOnce|cursorSpendingActionOpensFixedDashboardWithoutLoginOrSettings|presentedProviderAuthenticationActionsDismissBeforeTheirCallbacks|PopoverPresentation|MenuPanel'
git diff --check
~~~

Expected: PASS. Browser controls show Sign in; Claude/Codex help/accessibility retains full provider identity and callbacks fire once; Cursor remains unchanged.

- [ ] **Step 5: Commit the control-copy slice.**

~~~bash
git add \
  Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift \
  Tests/NeedlbarTests/SystemDashboardPopoverTests.swift
git commit -m "feat: compact dashboard login control"
~~~

Expected: one view-presentation/accessibility commit, not an authentication-flow change.

### Task 4: Complete automated, package, and exact-app native verification

**Files:**

- Verify only: all code/test files from Tasks 1–3
- Update later only if verification is complete: README.md, docs/images/system-dashboard.png, docs/STATUS.md

- [ ] **Step 1: Run final focused and acceptance coverage serially.**

~~~bash
source /Users/taejunoh/.cargo/env
make swift-test SWIFT_TEST_FILTER='dashboard|SystemDashboard|MenuBarController|MenuPanel|PopoverPresentation|AcceptanceFixture'
make acceptance-test
~~~

Expected: PASS for width/height, all-enabled/Fable, captions, statuses, identity, in-place resize/original anchor, Settings/Analytics dismissal, and fixture compatibility. This is not the full gate.

- [ ] **Step 2: Run all repository and artifact gates.**

~~~bash
source /Users/taejunoh/.cargo/env
make test
make package
make smoke
git diff --check
git status --short
~~~

Expected: every command exits 0. Record actual suite counts/warnings; do not copy historical results. Stop on failure and use systematic debugging before modifying code.

- [ ] **Step 3: Resolve exact package identity before desktop use.**

~~~bash
APP_PATH="$PWD/dist/Needlbar.app"
test -x "$APP_PATH/Contents/MacOS/Needlbar"
plutil -lint "$APP_PATH/Contents/Info.plist"
codesign --verify --deep --strict "$APP_PATH"
shasum -a 256 "$APP_PATH/Contents/MacOS/Needlbar"
~~~

Expected: all pass for this worktree's packaged app. Load the computer-use skill before desktop interaction. Identify candidates by full executable path; TERM only a confirmed old development PID, never a name-wide kill or a public app.

- [ ] **Step 4: Inspect the exact package at native scale.**

Launch only "$PWD/dist/Needlbar.app", then open its own system dashboard. Record app-only sanitized evidence for:

1. exactly 312-point panel width;
2. all enabled CPU/RAM/Disk/Network/Battery/AI content, Claude/Codex/Cursor, and an eligible visible Fable row on a tall screen;
3. a compact configuration with reduced height after hiding configured sections/providers, then restored prior configuration;
4. short-screen scrolling with fixed header/footer;
5. light/dark readability, unchanged CPU gauge/bars/value alignment, stable anchor/bottom edge, and no visible motion for ordinary numeric updates;
6. Settings, Analytics…, provider-action, and outside-click behavior where safely observable, without invoking external provider actions;
7. if an already-safe development fixture can show it without production edits or credential access, a one-line 312-point Sign-in required quota status and visible Sign in button. Otherwise record this as unobserved; do not substitute mockups, synthetic imagery, or an automated result.

Do not trigger browser login, Cursor Spending, network refresh, credential access, or a new fixture mechanism. Capture no account ID, raw payload, credential, IP, browser, or full desktop. Record capture path, pixels/points, SHA-256, observations, and limitations. macOS 14 acceptance remains deferred.

- [ ] **Step 5: Reinstall and relaunch only after the exact package and native inspection pass.**

Resolve and print only these explicit targets; stop if either is not exact:

~~~bash
SOURCE_APP="$PWD/dist/Needlbar.app"
RUNTIME_ROOT="/Users/taejunoh/Developer/LFG/needlbar-runtime"
TARGET_APP="$RUNTIME_ROOT/latest/Needlbar.app"
printf '%s\n' "$SOURCE_APP" "$TARGET_APP"
test -d "$SOURCE_APP"
test -d "$TARGET_APP"
~~~

Inspect the PID whose command exactly contains TARGET_APP/Contents/MacOS/Needlbar, then TERM only that PID. Move the old TARGET_APP to a timestamped directory under RUNTIME_ROOT/backups (recoverable), copy SOURCE_APP to the empty target with ditto, launch only TARGET_APP, re-open its dashboard, and verify its executable SHA-256 equals SOURCE_APP. Repeat the 312-point/one-line visual check. Do not touch public apps, widgets, credentials, or unrelated processes. If backup/copy/relaunch is unsafe or blocked, stop and report it; do not delete the backup or use a substitute target.

### Task 5: Update documentation only after verified evidence exists

**Files:**

- Conditionally modify: docs/images/system-dashboard.png
- Conditionally modify: README.md
- Modify after Task 4 is recorded: docs/STATUS.md

- [ ] **Step 1: Apply the native-evidence threshold.**

Change README/image only if Tasks 4.1–4.5 pass and a sanitized exact-app 312-point capture exists. If an observation is unavailable, leave README.md and docs/images/system-dashboard.png unchanged; never use a mock-up or claim native success.

- [ ] **Step 2: Make bounded README/image edits only when allowed.**

Copy only the verified sanitized capture to docs/images/system-dashboard.png. In README's System monitor development-build section, use this exact image and factual sentence:

~~~markdown
<img src="docs/images/system-dashboard.png" alt="Needlbar development dashboard with system metrics and remaining AI quota" width="312" />

The dashboard uses a fixed 312-point width with content-sized height; remaining quota is labeled `Quota remaining`, and a single quota sign-in state reads `Sign-in required`.
~~~

Retain public-v0.2.2, provider, Fable, privacy, and macOS-14 caveats. Do not state that an auth fixture was observed when Task 4 recorded it unobserved.

- [ ] **Step 3: Record complete or bounded-unobserved evidence in STATUS.**

Append one dated checkpoint naming all three implementation commit IDs; focused/acceptance/full/package/smoke/diff exits; exact package and reinstall executable paths plus SHA-256; capture dimensions/paths/sanitization; each observed and unobserved item; macOS 14 deferral; reinstall result; and next continuation point. Do not repeat old test counts or make release/push claims.

- [ ] **Step 4: Validate and commit documentation separately.**

~~~bash
git diff --check
git diff -- README.md docs/images/system-dashboard.png docs/STATUS.md
git status --short
~~~

Expected: only evidence/docs files differ. If the threshold was not met, README.md and docs/images/system-dashboard.png do not appear; STATUS explains why.

With qualifying evidence:

~~~bash
git add README.md docs/images/system-dashboard.png docs/STATUS.md
git commit -m "docs: record compact dashboard verification"
~~~

Without it:

~~~bash
git add docs/STATUS.md
git commit -m "docs: record compact dashboard verification"
~~~

Expected: a fourth evidence-only commit; do not amend code commits.

## Final implementation handoff checklist

- [ ] The constant, both fitting roots, first presentation, and frame-only resize use exactly 312 points.
- [ ] Existing height fallback/minimum/inset/clamp, scroll, anchor, content-controller, and numeric no-churn behavior remains green.
- [ ] Approved caption, singleton/dual status strings, short browser labels, and full provider accessibility/help identity are exact.
- [ ] Fable, Cursor, Settings, menu-bar, widgets, refresh/auth, and persistence boundaries remain unchanged.
- [ ] Focused, acceptance, full, package, smoke, diff, native, and reinstall evidence is honest; README/image changes meet the evidence threshold.

