# Provider Icon Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Vertically center the existing 18-point Claude, Codex, and Cursor brand icons with their provider titles in the main 312-point system-dashboard popover, without changing any provider detail row or dashboard behavior.

**Architecture:** Keep the SwiftUI change limited to the existing provider-title `HStack` in `SystemDashboardPopoverView`. Add a tiny internal semantic layout seam that the production `HStack` consumes and focused tests exercise; this avoids depending on SwiftUI's private hosted-view hierarchy while still testing the alignment policy, 18-point frame, 8-point gap, and center-error geometry. Existing caption/status/Fable `HStack`s remain literal `.firstTextBaseline` rows and are protected by existing dashboard sizing and presentation tests.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing, SwiftPM, existing Makefile package/smoke verification.

---

## Authority, workspace, and execution rules

The approved source of truth is `docs/superpowers/specs/2026-09-04-provider-icon-alignment-design.md`. Before changing code, read `AGENTS.md`, `docs/STATUS.md`, that spec, `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift`, `Sources/Needlbar/ProviderBrandIcon.swift`, and `Tests/NeedlbarTests/SystemDashboardPopoverTests.swift`.

Execute only in `/Users/taejunoh/Developer/LFG/needlbar/.worktrees/provider-brand-alignment` on branch `codex/provider-brand-alignment`. Preserve the parent checkout's existing `vendor/tokscale-core` state and untracked `.logs/` and `.superpowers/brainstorm/` content. Do not push, merge, publish, sign, notarize, alter credentials, edit provider assets, or change persisted settings unless separately requested.

Use test-first development. Run focused `make swift-test` gates serially because the target temporarily swaps the Rust bridge test runtime; source `/Users/taejunoh/.cargo/env` before each Make command. The semantic layout seam is deliberately the test boundary: do not test this correction with source-text grep, bitmap color sampling, or assumptions about SwiftUI's private `NSView` subview tree. A zero-test filter or current-host run is not macOS 14 acceptance.

## Scope and invariants

- Change only the provider-title/header `HStack` at `SystemDashboardPopoverView.providerRow(_:)`.
- One shared rule must apply to Claude, Codex, and Cursor: title-row vertical alignment is `.center`, icon frame remains 18×18 points, and icon-to-title spacing remains 8 points.
- Keep the provider title, value/action column, selected metric, provider order/visibility, brand asset mapping/rendering/fallback/accessibility, actions, refresh/authentication behavior, 312-point width, adaptive height, anchor, scrolling, and outside-click dismissal unchanged.
- Do not modify the caption/status `HStack` or the Fable row `HStack`; both remain `.firstTextBaseline` and retain their existing wrapping and text.
- Check light and dark hosted fixtures, 312-point width, and adaptive compact/full heights as regressions. Exact packaged-app native visual inspection in both appearances supplements—not replaces—the deterministic Swift geometry tests. macOS 14 remains a separately deferred acceptance gate.

## File map

| File | Responsibility |
| --- | --- |
| `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift` | Own the existing title-row `HStack` and a small internal semantic layout contract it consumes. |
| `Tests/NeedlbarTests/SystemDashboardPopoverTests.swift` | Verify the shared provider-title geometry contract in light/dark fixtures and retain adaptive-width/height/Fable regressions. |
| `docs/STATUS.md` | Record the implementation commit, command results, native observations/limits, and next continuation point after verification. |

No provider asset, resource, package, bridge, model, presenter, Settings, or test-target file change is planned.

### Task 1: Add a testable shared provider-title geometry contract

**Files:**
- Modify: `Tests/NeedlbarTests/SystemDashboardPopoverTests.swift`
- Modify: `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift`

- [ ] **Step 1: Add the focused failing geometry and appearance tests.**

Append these tests immediately before `dashboardReadabilityKeepsSizeStableAcrossAppearances` in `Tests/NeedlbarTests/SystemDashboardPopoverTests.swift`. The test uses the semantic geometry seam that production will use rather than parsing source or scanning pixels. It covers all three providers, the fixed 18-point frame, the eight-point gap, at-most-one-point vertical center error, and both hosted appearances.

```swift
@Test func providerTitleRowGeometryCentersEveryBrandWithoutChangingItsFrameOrGap() {
    let geometries = ProviderID.allCases.map { _ in
        ProviderTitleRowLayout.geometry(titleHeight: 20)
    }
    let first = geometries[0]

    #expect(geometries.count == 3)
    #expect(geometries.allSatisfy { $0 == first })
    #expect(first.verticalRule == .center)
    #expect(first.iconFrame == CGSize(width: 18, height: 18))
    #expect(first.horizontalSpacing == 8)
    #expect(first.verticalCenterError <= 1)
}

@Test @MainActor func providerTitleRowGeometryAndDashboardSizeStayStableAcrossAppearances() throws {
    let model = SystemDashboardModel(
        snapshot: dashboardFixtureSnapshot(),
        configuration: SystemMonitorConfiguration()
    )
    let height = try #require(SystemDashboardPopoverMeasurement.naturalHeight(for: model))
    let light = NSHostingController(rootView: SystemDashboardPopoverView(model: model, height: height))
    let dark = NSHostingController(rootView: SystemDashboardPopoverView(model: model, height: height))
    light.view.appearance = NSAppearance(named: .aqua)
    dark.view.appearance = NSAppearance(named: .darkAqua)
    light.view.layoutSubtreeIfNeeded()
    dark.view.layoutSubtreeIfNeeded()

    for _ in ProviderID.allCases {
        let geometry = ProviderTitleRowLayout.geometry(titleHeight: 20)
        #expect(geometry.verticalRule == .center)
        #expect(geometry.verticalCenterError <= 1)
    }
    #expect(light.view.fittingSize == dark.view.fittingSize)
    #expect(light.view.fittingSize.width == 312)
    #expect(dark.view.fittingSize.width == 312)
}
```

- [ ] **Step 2: Run the new focused test and capture the intended RED.**

Run:

```bash
source /Users/taejunoh/.cargo/env
make swift-test SWIFT_TEST_FILTER='providerTitleRowGeometry'
```

Expected: compilation fails because `ProviderTitleRowLayout` does not exist. Do not add a source-string assertion or weaken the test to only inspect a generated image.

- [ ] **Step 3: Add the minimal internal layout seam and wire the title row to it.**

At file scope in `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift`, directly above `public struct SystemDashboardPopoverView`, add the complete internal contract below. It records only the geometry owned by the title row; it does not select assets, apply icon offsets, alter a font, or introduce state.

```swift
enum ProviderTitleRowVerticalRule: Equatable {
    case center
}

struct ProviderTitleRowGeometry: Equatable {
    let verticalRule: ProviderTitleRowVerticalRule
    let iconFrame: CGSize
    let horizontalSpacing: CGFloat
    let verticalCenterError: CGFloat
}

enum ProviderTitleRowLayout {
    static let verticalRule: ProviderTitleRowVerticalRule = .center
    static let iconFrame = ProviderBrandIcon.iconFrame
    static let horizontalSpacing: CGFloat = 8

    static var swiftUIAlignment: VerticalAlignment {
        switch verticalRule {
        case .center:
            return .center
        }
    }

    static func geometry(titleHeight: CGFloat) -> ProviderTitleRowGeometry {
        let rowHeight = max(iconFrame.height, titleHeight)
        let iconCenterY = (rowHeight - iconFrame.height) / 2 + iconFrame.height / 2
        let titleCenterY = (rowHeight - titleHeight) / 2 + titleHeight / 2
        return ProviderTitleRowGeometry(
            verticalRule: verticalRule,
            iconFrame: iconFrame,
            horizontalSpacing: horizontalSpacing,
            verticalCenterError: abs(iconCenterY - titleCenterY)
        )
    }
}
```

Then replace only the title-row declaration in `providerRow(_:)`:

```swift
HStack(
    alignment: ProviderTitleRowLayout.swiftUIAlignment,
    spacing: ProviderTitleRowLayout.horizontalSpacing
) {
```

Leave the two following declarations byte-for-byte semantically unchanged:

```swift
HStack(alignment: .firstTextBaseline, spacing: 4) {
```

for the caption/status row, and:

```swift
HStack(alignment: .firstTextBaseline, spacing: 8) {
```

for the Fable weekly row. Do not change any child view in these three rows.

- [ ] **Step 4: Run the focused geometry, existing appearance, Fable, and adaptive-height regressions.**

Run:

```bash
source /Users/taejunoh/.cargo/env
make swift-test SWIFT_TEST_FILTER='providerTitleRowGeometry\|dashboardReadabilityKeepsSizeStableAcrossAppearances\|dashboardNaturalHeightTracksEnabledModulesAndProviders\|dashboardVisibleViewUsesMeasuredOrScreenLimitedHeight\|dashboardMeasurementAndVisibleHostsUse312PointWidth\|dashboardReadabilityPreservesSeparateFableSemantics'
git diff --check
```

Expected: every selected Swift test passes. The new tests prove one shared centered semantic rule with a 0-point modeled center difference (therefore within the 1-point contract), 18×18 icon frame, and 8-point gap. Existing tests prove light/dark fitting-size equality, retained 312-point width, adaptive compact/full height behavior, and Fable semantics; they must not be edited to accept a changed caption/status/Fable layout.

- [ ] **Step 5: Run the complete automated gate and commit the surgical implementation.**

Run:

```bash
source /Users/taejunoh/.cargo/env
make test
git diff --check
git add Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift Tests/NeedlbarTests/SystemDashboardPopoverTests.swift
git commit -m "fix: center dashboard provider brand icons"
```

Expected: `make test` exits 0, including the Rust, vendor, Swift, provider-brand asset, widget-extension, package, and notarization-shell contracts. The commit contains only the title-row layout seam, its one `HStack` use, and the focused tests.

### Task 2: Verify the packaged app at native scale and record the bounded evidence

**Files:**
- Modify: `docs/STATUS.md`

- [ ] **Step 1: Build and smoke-test the exact development package.**

Run:

```bash
source /Users/taejunoh/.cargo/env
make package
make smoke
codesign --verify --deep --strict dist/Needlbar.app
```

Expected: every command exits 0. Inspect only `dist/Needlbar.app`; do not replace or launch the public/release app, and do not perform browser login, Cursor Spending, credential, or provider actions.

- [ ] **Step 2: Perform bounded native visual verification in both appearances.**

Launch the exact packaged development bundle, open the system-dashboard popover with AI usage visible, and capture the Needlbar app window only (never a full-desktop capture) in Aqua and Dark Aqua. Verify Claude, Codex, and Cursor title rows each have an optically centered icon/title pair at native scale; confirm the title-value/action columns are unchanged, captions/status/Fable rows retain their previous baseline layout/wrapping, width remains 312 points, and compact/all-visible configurations still have content-driven heights. Also confirm the popover still anchors under its status item, scrolls when taller than the available screen, and dismisses on an outside click.

Expected: both sanitized app-window-only captures show the three title rows with no provider-specific offset. If a test fixture cannot safely produce a provider state, record it as unobserved rather than inferring it. Do not claim macOS 14 acceptance from the current host.

- [ ] **Step 3: Record exact evidence and limits, then commit the verification note.**

Append one dated `Provider icon alignment verification` subsection to `docs/STATUS.md`. State the implementation commit using the result of `git rev-parse --short HEAD`; list the actual exit results of the focused Swift command, `make test`, `make package`, `make smoke`, and strict `codesign`; and give the exact paths and dimensions of the two sanitized Needlbar-window-only captures. Record only observations actually made in Aqua and Dark Aqua. If a compact/full-height, anchor, scroll, or dismissal condition was not safely observed, state that it is unobserved and why; do not infer it. The subsection must also state that no provider login, Cursor Spending, credential action, asset fallback, or public/release app was used, and that native macOS 14 acceptance remains deferred. End with `Next action: parent review/integration.`

Then run:

```bash
git diff --check
git add docs/STATUS.md
git commit -m "docs: record provider icon alignment verification"
```

Expected: the record distinguishes automated, native, and unobserved evidence; it does not claim visual acceptance without the two app-window-only observations.

## Final implementation handoff

Before offering merge or push, report the two commit hashes, focused and complete test commands/results, package/smoke/codesign results, native capture paths and dimensions if obtained, and any unobserved native condition. Keep the branch unmerged and unpushed unless the user asks otherwise.
