# Two-line menu-bar readability implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver approved A: small labels above bold, stable-width values on the existing native menu-bar button.

**Architecture:** Add raw Sendable segments alongside unchanged legacy text. A separate AppKit helper fits two-line segments first and draws a scale-correct template image. A focused button presenter owns geometry invalidation and text/icon fallback without replacing the native button or involving provider state.

**Tech Stack:** Swift 6, Swift Testing, AppKit, CoreText, existing Make targets; no dependencies.

---

## Authority and execution boundaries

Approved spec: `docs/superpowers/specs/2026-09-03-menubar-two-line-readability-design.md`. Read AGENTS.md, current STATUS, and original v0.1 design/plan before implementation. Current STATUS supersedes the stale bootstrap continuation. Preserve Fable's exact headline exclusion.

Work only in `/Users/taejunoh/Developer/LFG/needlbar/.worktrees/integration-main.d16P79`, branch `codex/claude-fable-quota`. Design checkpoint is `6d14734`; execution starts after this documentation commit. Do not touch the unrelated root checkout, Documents, public-release app, credentials, or persisted preferences. No push, merge, signing, or publication is authorized.

Root orchestrates and maintains STATUS; Terra owns layout/native reasoning; Luna owns bounded tests/mechanical edits. Assign explicit file ownership. Execute one numbered task at a time with spec/quality review and a plain full gate between tasks. Preserve others' changes and run Make commands serially.

- [x] Before application edits, capture baseline:

```bash
git status --short
git submodule update --init --recursive
source /Users/taejunoh/.cargo/env
make test
```

Require exit 0. Diagnose failure rather than reusing prior Fable evidence. `make swift-test SWIFT_TEST_FILTER=Name` installs the bridge test runtime and restores the production archive; naked `swift test` can miss symbols. Zero-test selections are not evidence. Commands below assume the Cargo environment above.

## File map

| Task | Files |
| --- | --- |
| 1 | Modify `Sources/Needlbar/MenuBar/MenuBarDashboardRenderer.swift` and `Tests/NeedlbarTests/MenuBarDashboardRendererTests.swift`: raw segments and fallback candidates. |
| 2 | Create `Sources/Needlbar/MenuBar/MenuBarDashboardTwoLineLayout.swift`, `Sources/Needlbar/MenuBar/MenuBarDashboardImageRenderer.swift`, `Tests/NeedlbarTests/MenuBarTwoLineLayoutTests.swift`, `Tests/NeedlbarTests/MenuBarStatusImageRendererTests.swift`: measured fit and drawing. |
| 3 | Create `Sources/Needlbar/MenuBar/MenuBarDashboardButtonPresenter.swift`, `Tests/NeedlbarTests/MenuBarDashboardButtonPresenterTests.swift`; modify `Sources/Needlbar/MenuBar/MenuBarController.swift` and `Tests/NeedlbarTests/MenuBarControllerTests.swift`: existing-button integration. |
| 4 | README.md, docs/STATUS.md, plan checkboxes: integration/native evidence and handoff. |

SwiftPM discovers these files in existing targets. No Package.swift, NeedlbarCore, Rust, provider, widget, export, or notification changes.

### Task 1: Add raw segments without changing legacy rendering

- [x] Add these RED tests to the existing renderer test file; reuse its file-private fixtures:

```swift
@Test func typedSegmentsPreserveValuesAndProviderOverflow() {
    let r = MenuBarDashboardRenderer.render(snapshot: fixtureCombinedSnapshot(),
        configuration: fixtureMonitorConfiguration(), availableWidth: 240)
    #expect(r.segments.map(\.moduleID) == [.cpu, .memory, .ai])
    #expect(r.segments.map(\.label) == ["CPU", "RAM", "Claude"])
    #expect(r.segments.map(\.primary.text) == ["24%", "80%", "32%"])
    #expect(r.segments[2].providerOverflowCount == 2)
    #expect(r.tooltip.contains("AI Claude 32%"))
    #expect(r.textCandidates.contains(r.title))
}
@Test func rawNetworkPartsSurviveLegacyWidthFailure() {
    var c = fixtureMonitorConfiguration(); c.visibleModules = [.network]
    let r = MenuBarDashboardRenderer.render(snapshot: fixtureCombinedSnapshot(), configuration: c, availableWidth: 1)
    #expect(r.usesIconFallback)
    #expect(r.segments[0].primary.text == "↑1K")
    #expect(r.segments[0].secondary?.text == "↓2K")
    #expect(r.segments[0].primary.widthSamples == ["↑999B", "↑999.9K", "↑999.9M", "↑999.9G", "↑—"])
}
@Test func unknownProviderRetainsItsSelectedFamily() {
    for metric in [AIProviderDisplayMetric.remaining, .usage, .cost, .connectionStatus] {
        var c = fixtureMonitorConfiguration(); c.visibleModules = [.ai]
        c.ai[.claude] = .init(metric: metric)
        let fresh = MenuBarDashboardRenderer.render(snapshot: fixtureCombinedSnapshot(), configuration: c, availableWidth: 240)
        let empty = CombinedUsageSnapshot(system: nil, providers: [], capturedAt: .distantPast, systemAvailability: [:])
        let missing = MenuBarDashboardRenderer.render(snapshot: empty, configuration: c, availableWidth: 240)
        #expect(fresh.segments[0].primary.widthSamples == missing.segments[0].primary.widthSamples)
        #expect(missing.segments[0].primary.text == "—")
        #expect(missing.segments[0].label == "Claude")
    }
}
@Test func staleLastKnownGoodKeepsTheSameSegments() {
    let base = fixtureCombinedSnapshot()
    let providers = base.providers.map { p in
        ProviderSnapshot(provider: p.provider, usage: p.usage, quota: p.quota,
            usageStatus: .stale(lastSuccessfulAt: base.capturedAt),
            quotaStatus: .stale(lastSuccessfulAt: base.capturedAt), updatedAt: p.updatedAt)
    }
    let stale = CombinedUsageSnapshot(system: base.system, providers: providers,
        capturedAt: base.capturedAt, systemAvailability: base.systemAvailability)
    let c = fixtureMonitorConfiguration()
    #expect(MenuBarDashboardRenderer.render(snapshot: base, configuration: c, availableWidth: 240).segments
        == MenuBarDashboardRenderer.render(snapshot: stale, configuration: c, availableWidth: 240).segments)
}
```

Append to existing `fableDoesNotChangeAdaptiveMenuTitleOrTooltip`, using its `before`/`after`:

```swift
#expect(after.segments == before.segments)
#expect(after.textCandidates == before.textCandidates)
```

- [x] Run `make swift-test SWIFT_TEST_FILTER=MenuBarDashboardRendererTests`; confirm missing-member RED.

- [x] Add before the existing render-result type:

```swift
public struct MenuBarDashboardValuePart: Equatable, Sendable {
    public let text: String
    public let widthSamples: [String]
    public init(_ text: String, samples: [String]) { self.text = text; self.widthSamples = samples }
}
public struct MenuBarDashboardSegment: Equatable, Sendable {
    public let moduleID: MonitorModuleID
    public let label: String
    public let compactLabel: String
    public let primary: MenuBarDashboardValuePart
    public let secondary: MenuBarDashboardValuePart?
    public let providerOverflowCount: Int
    public init(_ moduleID: MonitorModuleID, label: String, primary: MenuBarDashboardValuePart,
                secondary: MenuBarDashboardValuePart? = nil, providerOverflowCount: Int = 0,
                compactLabel: String? = nil) {
        self.moduleID = moduleID; self.label = label; self.primary = primary
        self.secondary = secondary; self.providerOverflowCount = providerOverflowCount
        self.compactLabel = compactLabel ?? label
    }
}
```

Add result fields; append defaulted initializer parameters after existing `usesIconFallback` (add its trailing comma), and assignments inside its body:

```swift
// Stored fields:
public let segments: [MenuBarDashboardSegment]
public let textCandidates: [String]
// Appended parameters:
segments: [MenuBarDashboardSegment] = [],
textCandidates: [String] = []
// Initializer body:
self.segments = segments
self.textCandidates = textCandidates
```

Add these complete helpers inside `MenuBarDashboardRenderer`, reusing existing formatter/selector methods:

```swift
private static let percentSamples = ["100%", "—"]
private static func segment(_ id: MonitorModuleID, snapshot: CombinedUsageSnapshot,
                            configuration: SystemMonitorConfiguration) -> MenuBarDashboardSegment {
    switch id {
    case .cpu:
        return .init(id, label: "CPU", primary: .init(percentage(snapshot.system?.cpu.totalUsage), samples: percentSamples))
    case .memory:
        let m = snapshot.system?.memory
        return .init(id, label: "RAM", primary: .init(percentage(used: m?.usedBytes, free: m?.freeBytes), samples: percentSamples))
    case .disk:
        let d = snapshot.system?.disks.first
        return .init(id, label: "Disk", primary: .init(percentage(used: d?.usedBytes, free: d?.freeBytes), samples: percentSamples), compactLabel: "DSK")
    case .battery:
        return .init(id, label: "BAT", primary: .init(percentage(snapshot.system?.battery.level), samples: percentSamples))
    case .network:
        let rates = ["999B", "999.9K", "999.9M", "999.9G", "—"]
        return .init(id, label: "NET",
            primary: .init("↑" + compactTransfer(snapshot.system?.network.uploadBytesPerSecond), samples: rates.map { "↑" + $0 }),
            secondary: .init("↓" + compactTransfer(snapshot.system?.network.downloadBytesPerSecond), samples: rates.map { "↓" + $0 }))
    case .ai:
        let providers = configuration.aiOrder.filter { configuration.ai[$0]?.isVisible ?? true }
        guard let provider = providers.first else {
            return .init(id, label: "AI", primary: .init("—", samples: percentSamples))
        }
        let preference = configuration.ai[provider] ?? AIProviderDisplayPreference()
        let samples: [String]
        switch preference.metric {
        case .remaining: samples = percentSamples
        case .usage: samples = ["999", "999.99K", "999.99M", "999.99B", "—"]
        case .cost: samples = ["$999,999.99", "—"]
        case .connectionStatus: samples = ["Connected", "Unavailable", "Sign in", "Stale", "Error", "—"]
        }
        return .init(id, label: providerLabel(provider), primary: .init(
            providerValue(preference.metric, snapshot: snapshot.providers.first { $0.provider == provider }), samples: samples),
            providerOverflowCount: max(0, providers.count - 1), compactLabel: compactProviderLabel(provider))
    }
}
private static func textCandidates(_ ids: [MonitorModuleID], snapshot: CombinedUsageSnapshot,
                                   configuration: SystemMonitorConfiguration) -> [String] {
    guard !ids.isEmpty else { return [] }
    return stride(from: min(3, ids.count), through: 1, by: -1).flatMap { count in
        [MenuBarDashboardRenderResult.Layout.compact, .expanded].map { layout in
            title(modules: Array(ids.prefix(count)), omittedCount: ids.count - count,
                  snapshot: snapshot, configuration: configuration, layout: layout)
        }
    }
}
```

Append these arguments after `usesIconFallback: fitted.usesIconFallback` in the existing render-result construction:

```swift
segments: configuredModuleIDs.map { segment($0, snapshot: snapshot, configuration: configuration) },
textCandidates: textCandidates(configuredModuleIDs, snapshot: snapshot, configuration: configuration)
```

Keep legacy fit/title/layout/moduleIDs/tooltip untouched. Raw segments include every configured visible module even when legacy fit fails. Native fit never gates on the old fallback flag. Candidates let geometry changes refit cached text without another request.

- [x] Run GREEN/full gate, update STATUS, and commit Task 1 only:

```bash
make swift-test SWIFT_TEST_FILTER=MenuBarDashboardRendererTests
make test
git diff --check
git add Sources/Needlbar/MenuBar/MenuBarDashboardRenderer.swift Tests/NeedlbarTests/MenuBarDashboardRendererTests.swift docs/STATUS.md
git commit -m "feat: model stable menu bar value segments"
```


### Task 2: Fit two-line columns first and draw at native scale

- [x] Create `Tests/NeedlbarTests/MenuBarTwoLineLayoutTests.swift`:

```swift
import AppKit
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

@MainActor @Suite struct MenuBarTwoLineLayoutTests {
    private func cpu(_ value: String) -> MenuBarDashboardSegment {
        .init(.cpu, label: "CPU", primary: .init(value, samples: ["100%", "—"]))
    }
    private func fit(_ s: [MenuBarDashboardSegment], width: CGFloat = 240, height: CGFloat = 24) -> MenuBarDashboardTwoLineLayout? {
        MenuBarDashboardTwoLineLayout.fit(s, width: width, height: height, scale: 2)
    }
    @Test func percentageTransitionsDoNotMoveNeighbors() throws {
        let ram = MenuBarDashboardSegment(.memory, label: "RAM", primary: .init("72%", samples: ["100%", "—"]))
        let baseline = try #require(fit([cpu("0%"), ram]))
        for value in ["9%", "10%", "99%", "100%", "—"] {
            let layout = try #require(fit([cpu(value), ram]))
            #expect(layout.size == baseline.size)
            #expect(layout.columnOrigins == baseline.columnOrigins)
        }
    }
    @Test func familiesAndNetworkHaveIndependentFiniteReservations() throws {
        for samples in [["999", "999.99K", "999.99M", "999.99B", "—"],
                        ["$999,999.99", "$0.00", "$1,234.56", "—"],
                        ["Connected", "Unavailable", "Sign in", "Stale", "Error", "—"]] {
            var widths = Set<CGFloat>()
            for value in samples {
                let s = MenuBarDashboardSegment(.ai, label: "Claude", primary: .init(value, samples: samples))
                widths.insert(try #require(fit([s])).size.width)
            }
            #expect(widths.count == 1)
        }
        let samples = ["↑999B", "↑999.9K", "↑999.9M", "↑999.9G", "↑—"]
        var downloadPositions = Set<CGFloat>()
        for value in samples {
            let s = MenuBarDashboardSegment(.network, label: "NET", primary: .init(value, samples: samples),
                secondary: .init("↓2K", samples: samples.map { $0.replacingOccurrences(of: "↑", with: "↓") }))
            let layout = try #require(fit([s]))
            downloadPositions.insert(try #require(layout.runs.first { $0.text == "↓2K" }).baseline.x)
        }
        #expect(downloadPositions.count == 1)
    }
    @Test func bothKindsOfOverflowRemainVisible() throws {
        let ram = MenuBarDashboardSegment(.memory, label: "RAM", primary: .init("72%", samples: ["100%", "—"]))
        let ai = MenuBarDashboardSegment(.ai, label: "Claude", primary: .init("8%", samples: ["100%", "—"]), providerOverflowCount: 2)
        let disk = MenuBarDashboardSegment(.disk, label: "Disk", primary: .init("96%", samples: ["100%", "—"]))
        let layout = try #require(fit([cpu("24%"), ram, ai, disk]))
        #expect(layout.moduleIDs == [.cpu, .memory, .ai])
        #expect(layout.runs.contains { $0.text == "+1" })
        #expect(layout.runs.contains { $0.text == "Claude +2" })
    }
    @Test func geometryAndOutOfEnvelopeValuesFailClosed() {
        #expect(fit([cpu("24%")], width: 21) == nil)
        #expect(fit([cpu("24%")], height: 12) == nil)
        #expect(fit([cpu("24%")], height: 22) != nil)
        let long = MenuBarDashboardSegment(.ai, label: "Claude",
            primary: .init(String(repeating: "9", count: 100), samples: ["999.99B"]))
        #expect(fit([long]) == nil)
        for width in stride(from: 22, through: 500, by: 7) {
            if let layout = fit([cpu("24%")], width: CGFloat(width)) {
                #expect(layout.size.width + MenuBarDashboardTwoLineLayout.chrome <= CGFloat(min(width, 240)))
            }
        }
    }
    @Test func compactLabelsFitBeforeDroppingThePrefix() throws {
        let full = MenuBarDashboardSegment(.ai, label: "Claude",
            primary: .init("8%", samples: ["100%", "—"]),
            providerOverflowCount: 2, compactLabel: "CL")
        let compact = MenuBarDashboardSegment(.ai, label: "CL",
            primary: full.primary, providerOverflowCount: 2)
        let short = try #require(fit([compact]))
        let selected = try #require(fit([full], width: short.size.width + MenuBarDashboardTwoLineLayout.chrome))
        #expect(selected.moduleIDs == [.ai])
        #expect(selected.runs.contains { $0.text == "CL +2" })
    }
}
```

Create `Tests/NeedlbarTests/MenuBarStatusImageRendererTests.swift`:

```swift
import AppKit
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

@MainActor @Suite struct MenuBarStatusImageRendererTests {
    @Test func bitmapUsesRequestedScaleAndClearMargins() throws {
        let s = MenuBarDashboardSegment(.cpu, label: "CPU", primary: .init("100%", samples: ["100%", "—"]))
        for scale in [CGFloat(1), CGFloat(2)] {
            let layout = try #require(MenuBarDashboardTwoLineLayout.fit([s], width: 240, height: 22, scale: scale))
            let image = try #require(MenuBarDashboardImageRenderer.render(layout, scale: scale))
            let rep = try #require(image.representations.first as? NSBitmapImageRep)
            #expect(image.isTemplate)
            #expect(rep.pixelsWide == Int(ceil(layout.size.width * scale)))
            #expect(rep.pixelsHigh == Int(ceil(layout.size.height * scale)))
            #expect(layout.runs.allSatisfy { NSRect(origin: .zero, size: layout.size).contains($0.inkRect) })
            #expect((0..<rep.pixelsWide).allSatisfy { (rep.colorAt(x: $0, y: 0)?.alphaComponent ?? 0) == 0 })
            #expect((0..<rep.pixelsWide).contains { x in
                (0..<rep.pixelsHigh).contains { (rep.colorAt(x: x, y: $0)?.alphaComponent ?? 0) > 0 }
            })
        }
    }
}
```

- [x] Run each new suite through `make swift-test SWIFT_TEST_FILTER=MenuBarTwoLineLayoutTests` and `make swift-test SWIFT_TEST_FILTER=MenuBarStatusImageRendererTests`; confirm missing-type RED.

- [x] Create `Sources/Needlbar/MenuBar/MenuBarDashboardTwoLineLayout.swift`:

```swift
import AppKit
import CoreText
import NeedlbarCore

enum MenuBarTextRole: Equatable { case label, value }

@MainActor enum MenuBarGlyphs {
    static func font(_ role: MenuBarTextRole) -> NSFont {
        role == .label ? .systemFont(ofSize: 7.5, weight: .regular)
            : .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    }
    static func line(_ text: String, _ role: MenuBarTextRole) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text,
            attributes: [.font: font(role), .foregroundColor: NSColor.black]) as CFAttributedString)
    }
    static func advance(_ text: String, _ role: MenuBarTextRole) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line(text, role), nil, nil, nil))
    }
    static func bounds(_ text: String, _ role: MenuBarTextRole) -> CGRect {
        guard !text.isEmpty else { return .zero }
        let rect = CTLineGetBoundsWithOptions(line(text, role), [.useGlyphPathBounds])
        return rect.isNull ? .zero : rect
    }
}

struct MenuBarDashboardTwoLineLayout: Equatable {
    struct Run: Equatable {
        let text: String
        let role: MenuBarTextRole
        let baseline: CGPoint
        let inkRect: CGRect
    }
    // Finite initial native-cell allowance, included in the total width budget.
    // The presenter validates the actual cell rectangle after installation.
    static let chrome: CGFloat = 8
    let size: CGSize
    let moduleIDs: [MonitorModuleID]
    let columnOrigins: [CGFloat]
    let runs: [Run]

    @MainActor static func fit(_ segments: [MenuBarDashboardSegment], width: CGFloat,
                              height: CGFloat, scale: CGFloat) -> Self? {
        guard width.isFinite || width == .infinity else { return nil }
        let budget = width == .infinity ? CGFloat(240) : min(240, width)
        guard budget.isFinite, budget >= 22, height.isFinite, height > 0,
              scale.isFinite, scale > 0, !segments.isEmpty else { return nil }
        func rounded(_ value: CGFloat) -> CGFloat { ceil(value * scale) / scale }
        func partWidth(_ part: MenuBarDashboardValuePart) -> CGFloat {
            rounded(([part.text] + part.widthSamples).map { MenuBarGlyphs.advance($0, .value) }.max() ?? 0) + 1
        }
        func label(_ s: MenuBarDashboardSegment, compact: Bool = false) -> String {
            (compact ? s.compactLabel : s.label) + (s.providerOverflowCount > 0 ? " +\(s.providerOverflowCount)" : "")
        }
        // Fixed bands include descenders, digits, arrows and each actual string.
        let sample = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789↑↓$%—+.,/"
        func band(_ role: MenuBarTextRole, _ texts: [String]) -> CGRect {
            texts.reduce(MenuBarGlyphs.bounds(sample, role)) { $0.union(MenuBarGlyphs.bounds($1, role)) }
        }
        let labelBand = band(.label, segments.flatMap { [label($0), label($0, compact: true)] })
        let valueTexts = segments.flatMap { s in
            [s.primary.text] + s.primary.widthSamples
                + (s.secondary.map { [$0.text] + $0.widthSamples } ?? [])
        }
        let valueBand = band(.value, valueTexts)
        let inset = max(1, 1 / scale)
        let valueBaseline = inset - valueBand.minY
        let labelBaseline = height - inset - labelBand.maxY
        guard labelBaseline + labelBand.minY >= valueBaseline + valueBand.maxY + 1 else { return nil }
        for count in stride(from: min(3, segments.count), through: 1, by: -1) {
            let shown = Array(segments.prefix(count))
            let omitted = segments.count - count
            for compact in [false, true] {
            var widths = shown.map { s -> CGFloat in
                let values = partWidth(s.primary) + (s.secondary.map { 3 + partWidth($0) } ?? 0)
                return rounded(max(MenuBarGlyphs.advance(label(s, compact: compact), .label) + 1, values))
            }
            if omitted > 0 { widths.append(rounded(MenuBarGlyphs.advance("+\(omitted)", .value)) + 1) }
            let total = rounded(8 + widths.reduce(0, +) + CGFloat(max(0, widths.count - 1)) * 8)
            guard total + chrome <= budget else { continue }
            var runs: [Run] = []
            var origins: [CGFloat] = []
            func append(_ text: String, _ role: MenuBarTextRole, x: CGFloat, y: CGFloat) {
                guard !text.isEmpty else { return }
                let ink = MenuBarGlyphs.bounds(text, role)
                let baseline = CGPoint(x: x - ink.minX, y: y)
                runs.append(Run(text: text, role: role, baseline: baseline,
                    inkRect: ink.offsetBy(dx: baseline.x, dy: baseline.y)))
            }
            var x: CGFloat = 4
            for (index, s) in shown.enumerated() {
                origins.append(x)
                append(label(s, compact: compact), .label, x: x, y: labelBaseline)
                append(s.primary.text, .value, x: x, y: valueBaseline)
                if let secondary = s.secondary {
                    append(secondary.text, .value, x: x + partWidth(s.primary) + 3, y: valueBaseline)
                }
                x += widths[index] + 8
            }
            if omitted > 0 { append("+\(omitted)", .value, x: x, y: valueBaseline) }
            let size = CGSize(width: total, height: height)
            guard runs.allSatisfy({ CGRect(origin: .zero, size: size).contains($0.inkRect) }) else { return nil }
            return Self(size: size, moduleIDs: shown.map(\.moduleID), columnOrigins: origins, runs: runs)
            }
        }
        return nil
    }
}
```

Layout is side-effect-free measured data; never store AppKit font/image objects in the Sendable raw result. Network download x uses its independent primary reservation. Provider overflow is a label badge and omitted modules are a separate +N run; neither creates another status item. Long valid values increase required width then use ordinary prefix/fallback, not truncation or altered formatting.

- [x] Create `Sources/Needlbar/MenuBar/MenuBarDashboardImageRenderer.swift`:

```swift
import AppKit
import CoreText

@MainActor enum MenuBarDashboardImageRenderer {
    static func render(_ layout: MenuBarDashboardTwoLineLayout, scale: CGFloat) -> NSImage? {
        guard scale.isFinite, scale > 0, layout.size.width > 0, layout.size.height > 0 else { return nil }
        let pixelWidth = ceil(layout.size.width * scale)
        let pixelHeight = ceil(layout.size.height * scale)
        guard pixelWidth.isFinite, pixelHeight.isFinite,
              pixelWidth > 0, pixelHeight > 0, pixelWidth <= 4096, pixelHeight <= 4096 else { return nil }
        let width = Int(pixelWidth), height = Int(pixelHeight)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        rep.size = layout.size
        let context = graphics.cgContext
        context.clear(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.scaleBy(x: scale, y: scale)
        context.textMatrix = .identity
        for run in layout.runs {
            context.textPosition = run.baseline
            CTLineDraw(MenuBarGlyphs.line(run.text, run.role), context)
        }
        let image = NSImage(size: layout.size)
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }
}
```

Do not use whole-font extreme bounding boxes, guessed NSString baselines, or lockFocus's implicit scale. The shared starting font pair remains subject to native acceptance. If 22-point glyph tests fail, tune that pair based on measured glyph bands rather than weakening no-clipping or shrinking indefinitely.

- [x] Run GREEN/full gate, update STATUS, and commit:

```bash
make swift-test SWIFT_TEST_FILTER=MenuBarTwoLineLayoutTests
make swift-test SWIFT_TEST_FILTER=MenuBarStatusImageRendererTests
make swift-test SWIFT_TEST_FILTER=MenuBarDashboardRendererTests
make test
git diff --check
git add Sources/Needlbar/MenuBar/MenuBarDashboardTwoLineLayout.swift Sources/Needlbar/MenuBar/MenuBarDashboardImageRenderer.swift Tests/NeedlbarTests/MenuBarTwoLineLayoutTests.swift Tests/NeedlbarTests/MenuBarStatusImageRendererTests.swift docs/STATUS.md
git commit -m "feat: fit and draw measured two-line menu bar"
```


### Task 3: Integrate the existing button and preserve lifecycle/fallback

**Execution refinements (2026-09-03):** A read-only native-boundary review found
two implementation details to correct while preserving the approved design.
The examples below are guidance; these refinements take precedence:

- Do not add test-only `renderCount` or `invalidate` APIs. Observe real installed
  image identity and length assignments through repeated `present` calls. Keep
  `refresh` as the production observer callback. A small geometry dependency
  may support deterministic scale/appearance tests if needed.
- Text fallback must include native cell padding in the total budget, not use
  ink-only measurement followed by unconstrained `variableLength`. Reserve the
  shared chrome, assign a finite measured length, and validate the actual
  `NSCell.titleRect(forBounds:)`; use the existing icon fallback if it cannot
  fit. Test the near-budget case. Task 2 already includes chrome in its fit:
  pass the full budget to it, without subtracting chrome twice.
- Filter window-specific observations to the button's current window; keep
  application screen-parameter observations global. Preserve no-op cache and
  post-application key behavior to prevent geometry feedback loops.

- [x] In `Tests/NeedlbarTests/MenuBarControllerTests.swift`, append these members to its existing fake handle; keep title/action/anchor/factory unchanged:

```swift
var tooltip = ""
var accessibilityLabel = ""
var usesIconFallback = false
var dashboardResults: [MenuBarDashboardRenderResult] = []
func presentDashboard(_ result: MenuBarDashboardRenderResult) {
    dashboardResults.append(result)
    title = result.title; tooltip = result.tooltip
    accessibilityLabel = result.usesIconFallback ? "Needlbar" : result.tooltip
    usesIconFallback = result.usesIconFallback
}
```

Add this controller regression:

```swift
@MainActor @Test func controllerPassesStructuredDashboardWithoutReplacingHandle() async throws {
    let c = ModuleConfiguration(defaults: freshMenuBarDefaults())
    let factory = FakeStatusItemFactory()
    let controller = makeMenuBarController(configuration: c, snapshotStore: ProviderSnapshotStore(),
        loginCoordinator: testLoginCoordinator(), statusItemFactory: factory)
    await controller.refresh()
    let item = try #require(factory.created.first)
    let result = try #require(item.dashboardResults.last)
    #expect(!result.segments.isEmpty)
    #expect(item.tooltip == result.tooltip)
    #expect(item.accessibilityLabel == result.tooltip)
    #expect(item.action != nil)
    #expect(item.presentationAnchor() == FakeStatusItemHandle.literalAnchor)
    await controller.refresh()
    #expect(factory.created.count == 1)
    #expect(factory.created.first === item)
}
```

Create `Tests/NeedlbarTests/MenuBarDashboardButtonPresenterTests.swift`:

```swift
import AppKit
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

@MainActor @Suite struct MenuBarDashboardButtonPresenterTests {
    @Test func imageTextIconTransitionsPreserveActionAndTooltip() throws {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        let target = NSObject(); button.target = target; button.action = NSSelectorFromString("perform:")
        var budget: Double = 240
        var imageAllowed = true
        let presenter = MenuBarDashboardButtonPresenter(button: button, width: { budget },
            setLength: { value in
                if value > 0 { button.setFrameSize(NSSize(width: value, height: button.frame.height)) }
            }, validateImage: { _, _ in imageAllowed })
        let s = MenuBarDashboardSegment(.cpu, label: "CPU", primary: .init("24%", samples: ["100%", "—"]))
        let result = MenuBarDashboardRenderResult(layout: .compact, title: "CPU 24%", moduleIDs: [.cpu],
            tooltip: "CPU 24%", segments: [s], textCandidates: ["CPU 24%"])
        presenter.present(result)
        #expect(button.image?.isTemplate == true)
        #expect(button.title.isEmpty)
        #expect(button.toolTip == result.tooltip)
        #expect(button.accessibilityLabel() == result.tooltip)
        let count = presenter.renderCount
        presenter.refresh()
        #expect(presenter.renderCount == count)
        imageAllowed = false; presenter.invalidate()
        #expect(button.image == nil)
        #expect(button.title == "CPU 24%")
        budget = 1; presenter.refresh()
        #expect(button.image != nil)
        #expect(button.title.isEmpty)
        #expect(button.frame.width == 22)
        #expect(button.accessibilityLabel() == "Needlbar")
        budget = 240; imageAllowed = true
        button.setFrameSize(NSSize(width: 240, height: 24)); presenter.refresh()
        #expect(button.image?.isTemplate == true)
        #expect(button.accessibilityLabel() == result.tooltip)
        button.setFrameSize(NSSize(width: 240, height: 12)); presenter.refresh()
        #expect(button.image == nil)
        #expect(button.title == "CPU 24%")
        #expect(button.target === target)
        #expect(button.action == NSSelectorFromString("perform:"))
    }
    @Test func geometryScaleAppearanceAndBudgetInvalidateIndependently() {
        let base = MenuBarDashboardButtonPresenter.Geometry(bounds: NSSize(width: 120, height: 24), budget: 240, scale: 2, appearance: .aqua)
        #expect(base != .init(bounds: base.bounds, budget: 100, scale: 2, appearance: .aqua))
        #expect(base != .init(bounds: base.bounds, budget: 240, scale: 1, appearance: .aqua))
        #expect(base != .init(bounds: base.bounds, budget: 240, scale: 2, appearance: .darkAqua))
        #expect(base != .init(bounds: NSSize(width: 120, height: 22), budget: 240, scale: 2, appearance: .aqua))
    }
    @Test func observationsDoNotRetainThePresenter() {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        var presenter: MenuBarDashboardButtonPresenter? = .init(button: button,
            width: { 240 }, setLength: { _ in })
        weak var weakPresenter = presenter
        presenter = nil
        #expect(weakPresenter == nil)
    }
}
```

- [x] Run `make swift-test SWIFT_TEST_FILTER=MenuBarControllerTests` and `make swift-test SWIFT_TEST_FILTER=MenuBarDashboardButtonPresenterTests`. Confirm controller missing-call and missing-presenter RED.

- [x] Create `Sources/Needlbar/MenuBar/MenuBarDashboardButtonPresenter.swift`:

```swift
import AppKit

// Created/mutated only by the main-actor presenter. Cleanup captures no presenter.
private final class MenuBarObservationBag {
    var notifications: [NSObjectProtocol] = []
    var appearance: NSKeyValueObservation?
    deinit {
        notifications.forEach(NotificationCenter.default.removeObserver)
        appearance?.invalidate()
    }
}

@MainActor final class MenuBarDashboardButtonPresenter {
    struct Geometry: Equatable {
        let bounds: NSSize
        let budget: Double
        let scale: CGFloat
        let appearance: NSAppearance.Name
    }
    private struct Key: Equatable {
        let result: MenuBarDashboardRenderResult
        let geometry: Geometry
        static func == (lhs: Self, rhs: Self) -> Bool {
            // Width assigned by this presenter is OUTPUT, not an invalidation
            // input. Available budget and height are independent inputs. This
            // prevents failed-image -> variable-title width oscillation.
            lhs.result == rhs.result
                && lhs.geometry.bounds.height == rhs.geometry.bounds.height
                && lhs.geometry.budget == rhs.geometry.budget
                && lhs.geometry.scale == rhs.geometry.scale
                && lhs.geometry.appearance == rhs.geometry.appearance
        }
    }
    private let button: NSButton
    private let width: @MainActor () -> Double
    private let setLength: @MainActor (CGFloat) -> Void
    private let validateImage: @MainActor (NSButton, NSImage) -> Bool
    private let observations = MenuBarObservationBag()
    private var latest: MenuBarDashboardRenderResult?
    private var lastKey: Key?
    private var applying = false
    private(set) var renderCount = 0

    init(button: NSButton, width: @escaping @MainActor () -> Double,
         setLength: @escaping @MainActor (CGFloat) -> Void,
         validateImage: @escaping @MainActor (NSButton, NSImage) -> Bool = { button, image in
             guard let rect = button.cell?.imageRect(forBounds: button.bounds) else { return false }
             return rect.width >= image.size.width && rect.height >= image.size.height
                 && button.bounds.contains(rect)
         }) {
        self.button = button; self.width = width; self.setLength = setLength
        self.validateImage = validateImage
        button.postsFrameChangedNotifications = true
        button.postsBoundsChangedNotifications = true
        for name in [NSView.frameDidChangeNotification, NSView.boundsDidChangeNotification] {
            observations.notifications.append(NotificationCenter.default.addObserver(
                forName: name, object: button, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.refresh() }
                })
        }
        // Read the button's CURRENT window on each event, handling a nil initial
        // window or later movement without retaining an obsolete window token.
        for name in [NSWindow.didChangeBackingPropertiesNotification,
                     NSWindow.didChangeScreenNotification,
                     NSApplication.didChangeScreenParametersNotification] {
            observations.notifications.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.refresh() }
                })
        }
        if let app = NSApp {
            observations.appearance = app.observe(\.effectiveAppearance) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
        }
    }
    private func geometry() -> Geometry {
        let rawBudget = width()
        let budget = rawBudget == .infinity ? 240 : (rawBudget.isFinite ? max(0, min(240, rawBudget)) : 0)
        return Geometry(bounds: button.bounds.size, budget: budget,
            scale: button.window?.backingScaleFactor ?? 1, appearance: button.effectiveAppearance.name)
    }
    func present(_ result: MenuBarDashboardRenderResult) { latest = result; refresh() }
    func invalidate() { lastKey = nil; refresh() }
    func refresh() {
        guard !applying, let result = latest else { return }
        let context = geometry()
        guard Key(result: result, geometry: context) != lastKey else { return }
        applying = true
        defer {
            applying = false
            // Cache POST-application size so frame notifications cannot loop.
            lastKey = Key(result: result, geometry: geometry())
        }
        renderCount += 1
        if let layout = MenuBarDashboardTwoLineLayout.fit(result.segments,
                width: CGFloat(context.budget), height: context.bounds.height, scale: context.scale),
           let image = MenuBarDashboardImageRenderer.render(layout, scale: context.scale) {
            button.attributedTitle = NSAttributedString(string: "")
            button.title = ""; button.image = image
            button.imagePosition = .imageOnly; button.imageScaling = .scaleNone
            setLength(layout.size.width + MenuBarDashboardTwoLineLayout.chrome)
            button.superview?.layoutSubtreeIfNeeded()
            if validateImage(button, image), button.bounds.width <= CGFloat(context.budget) {
                button.toolTip = result.tooltip
                button.setAccessibilityElement(true)
                button.setAccessibilityLabel(result.tooltip)
                return
            }
        }
        // Refit cached text on geometry-only changes; do not fetch snapshots.
        let candidates = result.textCandidates.isEmpty && !result.title.isEmpty ? [result.title] : result.textCandidates
        let font = NSFont.menuFont(ofSize: 0)
        let text = context.budget >= 22 ? candidates.first {
            ($0 as NSString).size(withAttributes: [.font: font]).width <= CGFloat(context.budget)
        } : nil
        button.attributedTitle = NSAttributedString(string: "")
        button.toolTip = result.tooltip
        button.setAccessibilityElement(true)
        if let text {
            button.image = nil; button.imagePosition = .noImage
            button.font = font; button.title = text
            button.setAccessibilityLabel(result.tooltip)
            setLength(NSStatusItem.variableLength)
        } else {
            button.title = ""
            button.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Needlbar")
            button.imagePosition = .imageOnly; button.imageScaling = .scaleProportionallyDown
            button.setAccessibilityLabel("Needlbar")
            setLength(22)
        }
    }
}
```

Tests inject cell validation only to drive deterministic failure branches; production must always validate its real NSCell image rect. The initial chrome allowance is not proof of every cell's padding. If current-host validation fails, measure the actual cell rectangle and adjust the single shared allowance within the total budget. Never silently scale down, bypass validation, or retry in a layout loop.

- [x] Add `func presentDashboard(_ result: MenuBarDashboardRenderResult)` to the existing StatusItemHandle protocol and this default body in its extension:

```swift
func presentDashboard(_ result: MenuBarDashboardRenderResult) {
    title = result.title; tooltip = result.tooltip
    accessibilityLabel = result.usesIconFallback ? "Needlbar" : result.tooltip
    usesIconFallback = result.usesIconFallback
}
```

Replace only the four combined `reconcile(using:)` title/tooltip/AX/icon assignments with:

```swift
item.presentDashboard(rendered)
```

Keep action, snapshot-generation, and panel logic unchanged. In the existing private AppKitStatusItemHandle add:

```swift
private var dashboardPresenter: MenuBarDashboardButtonPresenter?
func presentDashboard(_ result: MenuBarDashboardRenderResult) {
    guard let button = statusItem.button else { return }
    if dashboardPresenter == nil {
        dashboardPresenter = MenuBarDashboardButtonPresenter(button: button,
            width: { [weak self] in self?.availableWidth ?? 240 },
            setLength: { [weak self] length in
                guard let self, self.statusItem.length != length else { return }
                self.statusItem.length = length
            })
    }
    dashboardPresenter?.present(result)
}
```

Retain existing legacy setters/factory/anchor method; the combined path's presenter owns only its visuals. The button remains action/tooltip/AX/anchor owner. Weak event callbacks and token cleanup follow the handle lifetime. There is one cached result/key, no history or new timer. Color/pressed tint stays AppKit-owned.

- [x] Run GREEN/full gate, update STATUS, and commit Task 3:

```bash
make swift-test SWIFT_TEST_FILTER=MenuBarDashboardButtonPresenterTests
make swift-test SWIFT_TEST_FILTER=MenuBarControllerTests
make swift-test SWIFT_TEST_FILTER=MenuPanelPlacementTests
make swift-test SWIFT_TEST_FILTER=MenuPanelPresenterTests
make test
git diff --check
git add Sources/Needlbar/MenuBar/MenuBarDashboardButtonPresenter.swift Sources/Needlbar/MenuBar/MenuBarController.swift Tests/NeedlbarTests/MenuBarDashboardButtonPresenterTests.swift Tests/NeedlbarTests/MenuBarControllerTests.swift docs/STATUS.md
git commit -m "feat: install two-line rendering on native status button"
```

### Task 4: Verify integration and exact development app, then document

- [ ] Run serial integrated gates and record exact logs/counts:

```bash
make test
make package
make smoke
git diff --check
```

Require all exit 0. Existing Fable, panel, widget, export and notification regressions remain part of the normal full gate. Do not replace failures with serial-only evidence or weaken assertions.

- [ ] Before relaunch, inspect processes read-only:

```bash
pgrep -fl Needlbar
```

Resolve each candidate's exact executable path. Stop only the confirmed worktree development executable with TERM, never a name-wide kill or historical PID. Launch only this worktree's newly packaged dist/Needlbar.app. Leave the public v0.2.2 app untouched. Load the applicable computer-use skill before desktop interaction. No login, credential reads, preference changes, or provider refresh is needed for typography.

- [ ] Record current-host native observations, not browser evidence:

  - One item; A's small labels/bold values readable at actual scale without dot separators.
  - Percent/arrow/unit glyphs fit the actual button/cell without silent scaling.
  - Configured order, max-three modules, both overflow indications and full tooltip.
  - Ordinary live updates keep neighbors stable within finite envelopes.
  - Current light/dark/pressed contrast and geometry/scale/fallback cases where available.
  - Same action, accessible name, panel below button, outside click and Escape dismissal.

Unobserved cases stay explicitly unverified; synthetic geometry tests do not prove every native display. Do not change OS appearance/display settings or unrelated apps implicitly. macOS 14 acceptance remains deferred. Sanitized screenshots may be saved under `/Users/taejunoh/Developer/LFG/needlbar-menubar-native-qa-20260903/`; no IP/account identifiers/secrets.

- [ ] After native verification replace the current README system-monitor paragraph with:

```markdown
The development build combines CPU, RAM, disk, network, battery, and AI usage
in one menu-bar item. New configurations show CPU, RAM, and AI; saved selections
and order are preserved. Small labels sit above prominent monospaced values,
with measured, stable-width columns. At most three configured summaries fit
within the conservative width budget; overflow and a full tooltip remain
available. Short-height or crowded layouts retain text and accessible icon
fallbacks. Settings includes a compact-defaults action.
```

Keep existing dashboard/Settings screenshots; browser prototypes are not native evidence. Root records actual commands, native outcomes, remaining limits, commits and continuation in STATUS; check off completed steps only. Separate menu-bar evidence from earlier Fable results. This remains a development build, not a public release.

- [ ] Verify docs and commit:

```bash
git diff --check
git add README.md docs/STATUS.md docs/superpowers/plans/2026-09-03-menubar-two-line-readability.md
git commit -m "docs: record verified two-line menu bar behavior"
```

## Self-review and execution handoff

Main-agent self-review checks spec coverage across Tasks 1–4, matching method/types, complete implementation/test blocks, two-line-first fitting independent of legacy success, raw Sendable data, both network reservations and overflow types, geometry-only text refitting, bounded observer lifetime, and distinct full/native gates. The proposed code has not been compiled as production code: RED/GREEN execution and native inspection remain required.

Self-review completed on 2026-09-03: compact-label attempts precede prefix reduction; finite reservations use typographic advances rather than digit ink widths; provider overflow and stale/missing families have explicit regressions. Native width assigned by the presenter is excluded from invalidation identity to prevent text/image failure oscillation. Scale-sized bitmaps, glyph margins, observer lifetime, cached-text refitting, and original action/anchor tests all have task coverage. Repository and SDK symbol checks informed the plan, but do not substitute for execution.

Recommended execution is the AGENTS-prescribed subagent workflow, one task at a time with review. This plan does not authorize push, merge, or release publication.
