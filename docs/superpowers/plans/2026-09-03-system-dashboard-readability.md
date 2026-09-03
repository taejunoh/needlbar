# System dashboard readability refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh only the main 360-point Needlbar system dashboard popover into a bright, high-contrast, balanced-density dashboard with aligned values and state-aware status text while preserving all existing data, actions, privacy, and panel behavior.

**Architecture:** Keep `SystemDashboardModel`, `SystemDashboardPresentation`, collectors, snapshot stores, provider actions, and refresh scheduling unchanged. Move the popover's reusable display primitives into one focused private Swift file: an adaptive shell, shared two-column metric rows, status policy, gauges, and chart/legend helpers. `SystemDashboardPopoverView` remains responsible for module order, model values, provider/Fable semantics, and existing callbacks; the display file owns only layout, typography, adaptive material, truncation, tooltips, and accessibility composition.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing, existing SwiftPM targets and Make verification commands; no new dependencies, preferences, network requests, timers, or schema changes.

---

## Authority, scope, and execution rules

Approved source of truth: `docs/superpowers/specs/2026-09-03-system-dashboard-readability-design.md`. Read `AGENTS.md`, `docs/STATUS.md`, the approved v0.1 design/plan, and the current source files before implementation. Work only in `/Users/taejunoh/Developer/LFG/needlbar/.worktrees/integration-main.d16P79` on `codex/claude-fable-quota`; never use `/Users/taejunoh/Documents`. Do not touch `.superpowers/brainstorm/`, the unrelated root checkout, the public v0.2.2 app, credentials, or persisted preferences.

This is a main-popover-only change. Do not modify menu-bar status-item layout, two-line headline rendering, notch/overflow behavior, widgets, notifications, Analytics, Settings, provider authentication, quota retrieval, collectors, formulas, units, snapshot models, bridge code, refresh cadence, or release packaging. Keep the existing 360-point width, 680-point maximum height, fixed header/footer shell, scroll view, Settings/Analytics callbacks, provider actions, Fable child semantics, local/public IP opt-ins, and outside-click dismissal.

Status assumption: the current system snapshot contract exposes only `fresh`, `stale`, and `unavailable`, while provider streams expose `fresh`, `stale`, `unavailable`, `requiresAuthentication`, and `error`; neither contract carries an in-flight `updating` state. This plan suppresses normal `Fresh`, renders the existing stale/error/authentication meanings, and does not invent a timer or model state. If an upstream approved change supplies an in-flight status before execution, map it to the literal `Updating` in `DashboardReadabilityPolicy` and add its fixture to the focused tests; otherwise `Updating` remains an explicitly unobservable state for this popover-only change.

Use strict TDD: write the focused failing test, run it and capture the intended failure, implement the smallest change, run the focused test, then run the complete gate before each scoped commit. Run Make recipes serially because this repository installs/restores a bridge test runtime. Never treat a zero-test filter, a bare `swift test`, or a serial-only workaround as the normal full gate.

## File map

| File | Responsibility in this plan |
| --- | --- |
| `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift` | Main popover shell, existing section order/model bindings, network disclosure, provider/Fable rows, and existing callbacks. Remove only private display helpers moved to the focused display file. |
| `Sources/Needlbar/Modules/Overview/SystemDashboardDisplayComponents.swift` | New private display boundary: status-label policy, adaptive high-contrast surface, shared metric grid/row, truncation/help/accessibility wrapper, section header, gauges, CPU bars, and compact trend legend. `RecentTrendChart` remains in its existing file. |
| `Tests/NeedlbarTests/SystemDashboardPopoverTests.swift` | Existing model and fitting regressions plus new readability policy, row-value, state, privacy, provider/Fable, and 360×680/360×400 tests. Keep its fixture in this file; do not change production models to make the fixture pass. |
| `README.md` | Existing system-monitor feature paragraph and existing screenshots only, updated after native acceptance. |
| `docs/STATUS.md` | Verification evidence, native acceptance observations/limitations, exact commands/logs, and continuation point, updated after native acceptance. |

No `Package.swift` change is planned: SwiftPM's existing `NeedlbarApp` target discovers the new source file automatically. No `SystemDashboardModel.swift` change is planned because normalized values, freshness, provider/Fable selection, and IP privacy already satisfy the data contract.

The new display file is justified because the current `SystemDashboardPopoverView.swift` contains the shell plus six section renderers and four reusable private display helpers in one 370-line file. The split is limited to display-only types; it is not a model or architectural refactor.

### Task 1: Define the readability contract with failing tests

**Files:**
- Modify: `Tests/NeedlbarTests/SystemDashboardPopoverTests.swift`
- Create later: `Sources/Needlbar/Modules/Overview/SystemDashboardDisplayComponents.swift`

- [x] **Step 1: Add failing policy and layout tests**

Append these tests to `Tests/NeedlbarTests/SystemDashboardPopoverTests.swift`, before its existing `dashboardFixtureSnapshot` helper. They intentionally reference the not-yet-created display policy and value descriptor.

```swift
@Test func dashboardReadabilitySuppressesNormalFreshnessAndPreservesActionStates() {
    #expect(DashboardReadabilityPolicy.systemStatus(.fresh) == nil)
    #expect(DashboardReadabilityPolicy.systemStatus(.stale) == "Stale")
    #expect(DashboardReadabilityPolicy.systemStatus(.unavailable) == nil)

    #expect(DashboardReadabilityPolicy.providerStatus(usage: .fresh, quota: .fresh) == nil)
    #expect(DashboardReadabilityPolicy.providerStatus(usage: .stale, quota: .fresh) == "Stale")
    #expect(DashboardReadabilityPolicy.providerStatus(usage: .fresh, quota: .requiresAuthentication) == "Authentication required")
    #expect(DashboardReadabilityPolicy.providerStatus(usage: .error, quota: .fresh) == "Error")
    #expect(DashboardReadabilityPolicy.providerStatus(usage: .unavailable, quota: .unavailable) == nil)
}

@Test func dashboardReadabilityKeepsFullValueForHelpAndAccessibility() {
    let address = "2600:1017:b82b:aeb6:819c:69d2:12ef:1fdd"
    let descriptor = DashboardMetricValue(address, truncation: .middle)

    #expect(descriptor.fullValue == address)
    #expect(descriptor.helpValue == address)
    #expect(descriptor.accessibilityValue == address)
    #expect(descriptor.truncation == .middle)
}

@Test func dashboardReadabilityUsesTailTruncationForOrdinaryText() {
    let descriptor = DashboardMetricValue("Authentication required", truncation: .tail)

    #expect(descriptor.truncation == .tail)
    #expect(descriptor.fullValue == "Authentication required")
}

@Test @MainActor func dashboardReadabilityFitsBothApprovedHeightsAndKeepsFooter() {
    let snapshot = dashboardFixtureSnapshot(
        claudeQuotaWindows: [
            try! QuotaWindow(id: "claude.session", title: "Session", usedPercent: 68, resetsAt: nil),
            try! QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "Fable weekly", usedPercent: 25, resetsAt: Date(timeIntervalSince1970: 20_000))
        ],
        perCoreUsage: Array(repeating: MetricPercentage(50)!, count: 15)
    )
    let model = SystemDashboardModel(snapshot: snapshot, configuration: SystemMonitorConfiguration())
    let regular = NSHostingController(rootView: SystemDashboardPopoverView(model: model, maximumHeight: 680))
    let short = NSHostingController(rootView: SystemDashboardPopoverView(model: model, maximumHeight: 400))

    #expect(regular.view.fittingSize.width == 360)
    #expect(regular.view.fittingSize.height == 680)
    #expect(short.view.fittingSize.width == 360)
    #expect(short.view.fittingSize.height == 400)
}

@Test @MainActor func dashboardReadabilityPreservesConfiguredOrderAndIPPrivacy() {
    var configuration = SystemMonitorConfiguration()
    configuration.order = [.ai, .network, .cpu, .battery, .memory, .disk]
    configuration.localIPEnabled = false
    configuration.publicIPEnabled = false

    let presentation = SystemDashboardPresentation(snapshot: dashboardFixtureSnapshot(), configuration: configuration)

    #expect(presentation.moduleIDs == configuration.order)
    #expect(presentation.network.primaryLocalAddress == nil)
    #expect(presentation.network.additionalLocalAddresses.isEmpty)
    #expect(presentation.network.publicIPAddress == nil)
}

@Test func dashboardReadabilityPreservesSeparateFableSemantics() throws {
    let windows = [
        try QuotaWindow(id: "claude.session", title: "Session", usedPercent: 68, resetsAt: nil),
        try QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "Fable weekly", usedPercent: 100, resetsAt: Date(timeIntervalSince1970: 20_000))
    ]
    let presentation = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(claudeQuotaWindows: windows),
        configuration: SystemMonitorConfiguration()
    )
    let claude = try #require(presentation.ai.first { $0.provider == .claude })

    #expect(claude.value == "32%")
    #expect(claude.fable?.remaining == "0%")
    #expect(presentation.ai.filter { $0.provider != .claude }.allSatisfy { $0.fable == nil })
}
```

- [x] **Step 2: Run the focused tests and capture the intended RED**

Run:

```bash
make swift-test SWIFT_TEST_FILTER='dashboardReadability'
```

Expected: compilation fails because `DashboardReadabilityPolicy` and `DashboardMetricValue` do not exist. The existing dashboard presentation/fitting tests are not RED evidence for this task; do not weaken them.

- [x] **Step 3: Commit the test-only RED checkpoint**

Do not commit a test-only RED checkpoint. Keep the failing tests in the worktree, implement the display contract immediately in Task 2, and commit the test plus production display boundary together once the focused suite is green.

### Task 2: Implement the adaptive shell and shared grid primitives

**Files:**
- Create: `Sources/Needlbar/Modules/Overview/SystemDashboardDisplayComponents.swift`
- Modify: `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift`
- Test: `Tests/NeedlbarTests/SystemDashboardPopoverTests.swift`

- [x] **Step 1: Add the complete display policy and metric-value descriptor**

Create `Sources/Needlbar/Modules/Overview/SystemDashboardDisplayComponents.swift` with these complete declarations at the top. They are internal for `@testable` contract tests and private-view consumers; they do not alter model or snapshot types.

```swift
import SwiftUI

enum DashboardReadabilityPolicy {
    static func systemStatus(_ freshness: DashboardFreshness) -> String? {
        switch freshness {
        case .fresh, .unavailable: nil
        case .stale: "Stale"
        }
    }

    static func providerStatus(usage: PresentationFreshness, quota: PresentationFreshness) -> String? {
        var result: [String] = []
        for status in [usage, quota] {
            let label: String?
            switch status {
            case .fresh, .unavailable: label = nil
            case .stale: label = "Stale"
            case .requiresAuthentication: label = "Authentication required"
            case .error: label = "Error"
            }
            if let label, !result.contains(label) { result.append(label) }
        }
        return result.isEmpty ? nil : result.joined(separator: " · ")
    }
}

struct DashboardMetricValue {
    let fullValue: String
    let truncation: Text.TruncationMode

    init(_ fullValue: String, truncation: Text.TruncationMode = .tail) {
        self.fullValue = fullValue
        self.truncation = truncation
    }

    var helpValue: String { fullValue }
    var accessibilityValue: String { fullValue }
}
```

- [x] **Step 2: Add the complete adaptive shell, section header, and shared metric row**

Append these complete display components to `SystemDashboardDisplayComponents.swift`. The shell deliberately uses an adaptive system color with high opacity above the material so wallpaper cannot determine text contrast. The status label is absent for normal data and unavailable system data; provider authentication/error wording remains available through the existing provider action policy.

```swift
struct DashboardSurface<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background {
                ZStack {
                    Rectangle().fill(.regularMaterial)
                    Rectangle().fill(Color(nsColor: .windowBackgroundColor).opacity(0.94))
                }
            }
    }
}

struct DashboardSection<Content: View>: View {
    let title: String
    let icon: String
    let freshness: DashboardFreshness?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: icon)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(title).font(.headline.weight(.semibold))
                Spacer(minLength: 8)
                if let freshness, let status = DashboardReadabilityPolicy.systemStatus(freshness) {
                    Text(status)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                        .accessibilityLabel("\(title) data \(status)")
                }
            }
            content()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }
}

struct DashboardMetricRow: View {
    let label: String
    let value: DashboardMetricValue

    var body: some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .gridColumnAlignment(.leading)
                .layoutPriority(1)
            Text(value.fullValue)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(value.truncation)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .gridColumnAlignment(.trailing)
                .help(value.helpValue)
                .accessibilityValue(value.accessibilityValue)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value.accessibilityValue)")
    }
}

struct DashboardMetricGrid<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
            content()
        }
        .frame(maxWidth: .infinity)
    }
}

struct DashboardMetricText: View {
    let value: DashboardMetricValue

    var body: some View {
        Text(value.fullValue)
            .fontWeight(.semibold)
            .monospacedDigit()
            .lineLimit(1)
            .truncationMode(value.truncation)
            .help(value.helpValue)
            .accessibilityValue(value.accessibilityValue)
    }
}
```

- [x] **Step 3: Move and update the existing gauge/bar/legend helpers with complete declarations**

Remove the old private `DashboardSection`, `MetricGauge`, and `PerCoreActivityBars` declarations from `SystemDashboardPopoverView.swift`. Append these complete declarations to `SystemDashboardDisplayComponents.swift`. `RecentTrendChart` stays in `Sources/Needlbar/Modules/Overview/RecentTrendChart.swift` and remains unchanged.

```swift
struct MetricGauge: View {
    let value: Double?
    let label: String
    let accessibilityMetric: String
    let tint: Color

    var body: some View {
        ZStack {
            if let value {
                Circle().stroke(tint.opacity(0.18), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, min(1, value / 100))))
                    .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle().strokeBorder(.tertiary, lineWidth: 7)
            }
            Text(label).font(.caption.weight(.semibold).monospacedDigit())
        }
        .frame(width: 52, height: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.map { "\(accessibilityMetric), \(label)" } ?? "\(accessibilityMetric) unavailable")
    }
}

struct PerCoreActivityBars: View {
    let values: [Double]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                GeometryReader { proxy in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.primary.opacity(0.10))
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.blue)
                            .frame(height: proxy.size.height * max(0, min(1, value / 100)))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("CPU core \(index + 1), \(Int(value.rounded()))%")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
        .accessibilityElement(children: .contain)
    }
}

struct DashboardTrendMetrics: View {
    let firstTitle: String
    let firstValue: DashboardMetricValue
    let firstColor: Color
    let secondTitle: String
    let secondValue: DashboardMetricValue
    let secondColor: Color
    let samples: [(Double?, Double?)]
    let accessibilityLabel: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                legend(firstTitle, firstValue, firstColor)
                legend(secondTitle, secondValue, secondColor)
            }
            RecentTrendChart(samples: samples, firstColor: firstColor, secondColor: secondColor)
                .frame(height: 34)
                .accessibilityLabel(accessibilityLabel)
        }
        .padding(.top, 3)
    }

    private func legend(_ title: String, _ value: DashboardMetricValue, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            DashboardMetricText(value: value).font(.caption2)
        }
    }
}
```

- [x] **Step 4: Run the focused GREEN tests and full automated gate**

Run serially:

```bash
make swift-test SWIFT_TEST_FILTER='dashboardReadability|dashboardPopover|dashboardPresentation'
make test
git diff --check
```

Expected: the focused readability, existing presentation, Fable, privacy, and fitting tests pass; `make test` exits 0 with all existing Swift/Rust/vendor/widget/package/notarization contracts. The 360×400 test must report a 360-point shell with the footer retained; no assertion may depend on wall-clock time or network access.

- [x] **Step 5: Commit the display boundary and contract tests**

```bash
git add Sources/Needlbar/Modules/Overview/SystemDashboardDisplayComponents.swift Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift Tests/NeedlbarTests/SystemDashboardPopoverTests.swift
git commit -m "feat: add readable dashboard display primitives"
```

### Task 3: Recompose all six sections and AI rows on the shared grid

**Files:**
- Modify: `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift`
- Modify: `Tests/NeedlbarTests/SystemDashboardPopoverTests.swift`

- [x] **Step 1: Replace the root body with the fixed shell and adaptive surface**

Replace `SystemDashboardPopoverView.body` with this complete property. It preserves the current header/footer actions and scrolling contract while routing background material through the new high-contrast shell.

```swift
public var body: some View {
    DashboardSurface {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.presentation.moduleIDs, id: \.self) { module in
                        dashboardSection(module)
                        if module != model.presentation.moduleIDs.last {
                            Divider().padding(.leading, 18)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Divider()
            footer
        }
    }
    .frame(width: 360, height: min(680, max(180, maximumHeight)))
}
```

- [x] **Step 2: Replace CPU, RAM, Disk, Network, and Battery section content**

Replace the complete `dashboardSection(_:)` method with this implementation. It uses the same model properties and formatters, but every current-value pair uses the shared grid and every long address/value keeps a complete help/accessibility value.

```swift
@ViewBuilder
private func dashboardSection(_ module: MonitorModuleID) -> some View {
    switch module {
    case .cpu:
        DashboardSection(title: "CPU", icon: "cpu", freshness: model.presentation.cpu.freshness) {
            HStack(alignment: .center, spacing: 16) {
                MetricGauge(value: model.presentation.cpu.usagePercent, label: model.presentation.cpu.usage, accessibilityMetric: "CPU usage", tint: .blue)
                DashboardMetricGrid {
                    DashboardMetricRow(label: "Usage", value: .init(model.presentation.cpu.usage))
                    DashboardMetricRow(label: "Idle", value: .init(model.presentation.cpu.usagePercent.map { Self.percent(100 - $0) } ?? "—"))
                }
            }
            if !model.presentation.cpu.perCorePercents.isEmpty {
                PerCoreActivityBars(values: model.presentation.cpu.perCorePercents)
            }
        }
    case .memory:
        DashboardSection(title: "RAM", icon: "memorychip", freshness: model.presentation.memory.freshness) {
            HStack(alignment: .center, spacing: 16) {
                MetricGauge(value: model.presentation.memory.usedPercent, label: model.presentation.memory.usedPercent.map(Self.percent) ?? "—", accessibilityMetric: "RAM used", tint: .purple)
                DashboardMetricGrid {
                    DashboardMetricRow(label: "Used", value: .init(model.presentation.memory.used))
                    DashboardMetricRow(label: "Available", value: .init(model.presentation.memory.available))
                    DashboardMetricRow(label: "Swap", value: .init(model.presentation.memory.swap))
                    DashboardMetricRow(label: "Pressure", value: .init(model.presentation.memory.pressure))
                }
            }
        }
    case .disk:
        DashboardSection(title: "Disk", icon: "internaldrive", freshness: model.presentation.disk.freshness) {
            HStack(alignment: .center, spacing: 16) {
                MetricGauge(value: model.presentation.disk.usedPercent, label: model.presentation.disk.usedPercent.map(Self.percent) ?? "—", accessibilityMetric: "Disk used", tint: .cyan)
                DashboardMetricGrid {
                    DashboardMetricRow(label: "Name", value: .init(model.presentation.disk.name, truncation: .tail))
                    DashboardMetricRow(label: "Used", value: .init(model.presentation.disk.used))
                    DashboardMetricRow(label: "Available", value: .init(model.presentation.disk.free))
                }
            }
            DashboardTrendMetrics(
                firstTitle: "Read", firstValue: .init(model.presentation.disk.read), firstColor: .blue,
                secondTitle: "Write", secondValue: .init(model.presentation.disk.write), secondColor: .orange,
                samples: model.history.disk.map { ($0.readBytesPerSecond, $0.writeBytesPerSecond) },
                accessibilityLabel: "System disk I/O, read \(model.presentation.disk.read), write \(model.presentation.disk.write)"
            )
        }
    case .network:
        DashboardSection(title: "Network", icon: "network", freshness: model.presentation.network.freshness) {
            DashboardMetricGrid {
                DashboardMetricRow(label: "Download", value: .init(model.presentation.network.download))
                DashboardMetricRow(label: "Upload", value: .init(model.presentation.network.upload))
            }
            DashboardTrendMetrics(
                firstTitle: "Download", firstValue: .init(model.presentation.network.download), firstColor: .blue,
                secondTitle: "Upload", secondValue: .init(model.presentation.network.upload), secondColor: .orange,
                samples: model.history.network.map { ($0.downloadBytesPerSecond, $0.uploadBytesPerSecond) },
                accessibilityLabel: "Recent network transfer, download \(model.presentation.network.download), upload \(model.presentation.network.upload)"
            )
            networkAddresses
        }
    case .battery:
        DashboardSection(title: "Battery", icon: "battery.75", freshness: model.presentation.battery.freshness) {
            HStack(alignment: .center, spacing: 16) {
                MetricGauge(value: model.presentation.battery.levelPercent, label: model.presentation.battery.level, accessibilityMetric: "Battery level", tint: .green)
                DashboardMetricGrid {
                    DashboardMetricRow(label: "Level", value: .init(model.presentation.battery.level))
                    DashboardMetricRow(label: "Status", value: .init(model.presentation.battery.status))
                    DashboardMetricRow(label: "Health", value: .init(model.presentation.battery.health))
                }
            }
        }
    case .ai:
        aiSection
    }
}
```

- [x] **Step 3: Replace network addresses with privacy-preserving, truncating rows**

Replace the complete `networkAddresses` computed property with this implementation. The disclosure and opt-ins are unchanged; only display alignment, truncation mode, help, and accessibility composition are added.

```swift
@ViewBuilder
private var networkAddresses: some View {
    if let address = model.presentation.network.primaryLocalAddress {
        DashboardMetricRow(label: "Local IP", value: .init(address, truncation: .middle))
            .padding(.top, 5)
    }
    if !model.presentation.network.additionalLocalAddresses.isEmpty {
        DisclosureGroup("Additional addresses") {
            ForEach(model.presentation.network.additionalLocalAddresses, id: \.self) { address in
                DashboardMetricText(value: .init(address, truncation: .middle))
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(address)
                    .accessibilityLabel("Additional local IP, \(address)")
            }
        }
        .font(.caption)
        .padding(.top, 4)
    }
    if let publicIP = model.presentation.network.publicIPAddress {
        DashboardMetricRow(label: "Public IP", value: .init(publicIP, truncation: .middle))
            .padding(.top, 3)
    }
}
```

- [x] **Step 4: Add the complete AI section and preserve provider/Fable actions**

Add these complete properties and methods inside `SystemDashboardPopoverView`, replacing the old `.ai` case body and its `actionTitle` call site only. The provider metric remains the configured selected metric (remaining by default); the action remains the existing `onProviderAction` callback; Fable remains subordinate to Claude Remaining and never enters a headline or top-level provider list.

```swift
@ViewBuilder
private var aiSection: some View {
    DashboardSection(title: "AI usage", icon: "sparkles", freshness: nil) {
        if model.presentation.ai.isEmpty {
            Text("No providers selected for the dashboard.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        ForEach(model.presentation.ai, id: \.provider) { provider in
            providerRow(provider)
        }
    }
}

@ViewBuilder
private func providerRow(_ provider: SystemDashboardPresentation.AIProvider) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: provider.provider.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(provider.provider.displayName)
                .fontWeight(.medium)
                .layoutPriority(1)
            Spacer(minLength: 8)
            DashboardMetricText(value: .init(provider.value))
            if let action = provider.action {
                Button(actionTitle(action)) { onProviderAction(provider.provider) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(provider.caption)
                .foregroundStyle(.secondary)
            if let status = DashboardReadabilityPolicy.providerStatus(usage: provider.usageStatus, quota: provider.quotaStatus) {
                Text("· \(status)")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption2)
        if let fable = provider.fable {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Fable weekly")
                Spacer(minLength: 8)
                DashboardMetricText(value: .init("\(fable.remaining) remaining"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let status = fableStatus(fable.freshness) {
                Text("\(fable.resetCaption) · \(status)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                Text(fable.resetCaption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    .accessibilityElement(children: .contain)
}

private func fableStatus(_ freshness: PresentationFreshness) -> String? {
    switch freshness {
    case .fresh, .unavailable: return nil
    case .stale: return "Stale"
    case .requiresAuthentication: return "Authentication required"
    case .error: return "Error"
    }
}
```

- [x] **Step 5: Replace the header/footer and remove obsolete local helpers**

Replace `header` and `footer` with these complete properties. Remove the old `trendMetrics`, `trendLegend`, `compactMetric`, `compactInlineMetric`, and `metricRow` methods after all call sites are gone. Keep `actionTitle` and `percent` exactly as existing behavior.

```swift
private var header: some View {
    HStack(alignment: .center, spacing: 10) {
        Image(systemName: "chart.bar.fill")
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 1) {
            Text("Needlbar").font(.headline.weight(.semibold))
            Text("System dashboard")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Spacer()
        Text("Live")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dashboard updates as metrics are collected")
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 8)
}

private var footer: some View {
    HStack {
        Button("Settings", action: onShowSettings)
        Spacer()
        Button("Analytics…", action: onShowAnalytics)
    }
    .buttonStyle(.borderless)
    .controlSize(.small)
    .font(.caption)
    .padding(.horizontal, 18)
    .padding(.vertical, 8)
}
```

- [x] **Step 6: Add state, long-value, dark-mode, and action regressions**

Append these tests to `SystemDashboardPopoverTests.swift`:

```swift
@Test @MainActor func dashboardReadabilityFittingIsStableAcrossLiveNumericChanges() {
    let configuration = SystemMonitorConfiguration()
    let first = dashboardFixtureSnapshot(capturedAt: Date(timeIntervalSince1970: 10_000))
    let second = dashboardFixtureSnapshot(capturedAt: Date(timeIntervalSince1970: 10_001), todayTokens: 1_683_150_000)
    let firstModel = SystemDashboardModel(snapshot: first, configuration: configuration)
    let secondModel = SystemDashboardModel(snapshot: second, configuration: configuration)
    let firstView = NSHostingController(rootView: SystemDashboardPopoverView(model: firstModel, maximumHeight: 680))
    let secondView = NSHostingController(rootView: SystemDashboardPopoverView(model: secondModel, maximumHeight: 680))

    #expect(firstView.view.fittingSize == secondView.view.fittingSize)
}

@Test @MainActor func dashboardReadabilityKeepsSizeStableAcrossAppearances() {
    let model = SystemDashboardModel(snapshot: dashboardFixtureSnapshot(), configuration: SystemMonitorConfiguration())
    let light = NSHostingController(rootView: SystemDashboardPopoverView(model: model, maximumHeight: 680))
    let dark = NSHostingController(rootView: SystemDashboardPopoverView(model: model, maximumHeight: 680))
    light.view.appearance = NSAppearance(named: .aqua)
    dark.view.appearance = NSAppearance(named: .darkAqua)

    #expect(light.view.fittingSize == dark.view.fittingSize)
    #expect(light.view.fittingSize.width == 360)
    #expect(dark.view.fittingSize.width == 360)
}

@Test func dashboardReadabilityPreservesUnavailableAndStalePresentation() {
    let stale = SystemDashboardPresentation(
        snapshot: dashboardFixtureSnapshot(
            networkAvailability: .stale(lastSuccessfulAt: Date(timeIntervalSince1970: 9_999)),
            diskAvailability: .stale(lastSuccessfulAt: Date(timeIntervalSince1970: 9_999)),
            claudeQuotaStatus: .requiresAuthentication,
            cursorQuotaStatus: .error(message: "refresh failed", lastSuccessfulAt: nil),
            cursorHasQuota: false
        ),
        configuration: SystemMonitorConfiguration()
    )

    #expect(stale.network.download == "2.0 KB/s")
    #expect(stale.disk.read == "10 B/s")
    #expect(stale.ai.first { $0.provider == .claude }?.value == "32%")
    #expect(stale.ai.first { $0.provider == .cursor }?.value == "—")
    #expect(DashboardReadabilityPolicy.systemStatus(stale.network.freshness) == "Stale")
    #expect(DashboardReadabilityPolicy.providerStatus(
        usage: stale.ai.first { $0.provider == .claude }!.usageStatus,
        quota: stale.ai.first { $0.provider == .claude }!.quotaStatus
    ) == "Authentication required")
}
```

- [x] **Step 7: Run the focused GREEN suite and the complete gate**

```bash
make swift-test SWIFT_TEST_FILTER='dashboardReadability|dashboardPresentation|dashboardFable|PopoverPresentation'
make test
git diff --check
```

Expected: all focused tests pass; the complete gate exits 0. Verify that no test changes provider fixture data, IP preferences, Fable projection, or refresh behavior merely to make the new layout fit.

- [x] **Step 8: Commit the recomposed popover**

```bash
git add Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift Sources/Needlbar/Modules/Overview/SystemDashboardDisplayComponents.swift Tests/NeedlbarTests/SystemDashboardPopoverTests.swift
git commit -m "feat: refresh system dashboard popover readability"
```

### Task 4: Automated gates, native acceptance, and documentation handoff

**Files:**
- Modify after native pass: `README.md`
- Modify after native pass: `docs/STATUS.md`
- Modify: this plan's checkboxes only as execution proceeds

- [x] **Step 1: Request the scoped two-stage implementation review**

After Task 3's focused and full gates pass, request a spec-compliance review against `docs/superpowers/specs/2026-09-03-system-dashboard-readability-design.md` and a separate code-quality review of the Task 2–3 diff. Reviewers must inspect only the approved main-popover scope, reject menu-bar/notch/status-item changes, verify that model/provider/auth/refresh behavior is untouched, and report actionable findings with exact file/line references. Apply only verified in-scope findings with a regression test, then rerun the affected focused suite and `git diff --check` before continuing.

- [x] **Step 2: Run the final focused consumers and package smoke gates**

Run serially from the isolated worktree:

```bash
make swift-test SWIFT_TEST_FILTER='dashboard|Fable|Popover|MenuBar|Widget|Quota|Export|AcceptanceFixture'
make acceptance-test
make test
make package
make smoke
git diff --check
```

Expected: each command exits 0. Record each command's actual output in a log under `/Users/taejunoh/Developer/LFG/`; do not claim CI or macOS 14 acceptance from these current-host gates. If a known process-fixture failure recurs, compare with a fresh unmodified baseline and report the ordinary gate as blocked; do not change unrelated process deadlines or weaken assertions.

- [x] **Step 3: Identify and launch only the exact development bundle for native inspection**

Resolve the development process and bundle path read-only before interacting with desktop UI:

```bash
ps -axo pid,etime,args | rg '/Users/taejunoh/Developer/LFG/needlbar/.worktrees/integration-main\.d16P79/.*/Needlbar\.app/Contents/MacOS/Needlbar$'
```

Use the exact packaged development app produced by `make package`, open its dashboard, and leave the separate public v0.2.2 app untouched. If the exact development process cannot be distinguished from the public process, stop native testing and record that blocker instead of terminating a process by name.

- [~] **Step 4: Capture native acceptance evidence at 360×680 and 360×400 (PARTIAL — 360×680 evidence captured; dark mode, 360×400, tooltip/accessibility, actions, and forced states unobserved)**

Inspect the exact development build and record sanitized evidence for:

1. light mode: bright adaptive shell, high-contrast labels, semibold monospaced values, stable right alignment, no normal `Fresh` labels;
2. dark mode: adaptive high-contrast shell and readable primary/secondary text;
3. ordinary live numeric updates: values change without column or shell width movement;
4. short available height: fixed header/footer remain visible while the section body scrolls;
5. long disk/IP/provider values: visible truncation does not collide, while hovering exposes the complete help/tooltip value and accessibility value is complete;
6. unchanged one-button panel anchor, outside-click dismissal, Settings, Analytics, Claude/Codex browser-login actions, Cursor Spending action, and Fable child without an extra action;
7. unavailable, stale, authentication-required, and refresh-error states: status text appears only where permitted and last-known-good values remain when present.

Capture only the exact app window or a narrow sanitized region; do not include account identifiers, IP addresses, credentials, raw provider responses, or a full desktop screenshot. Native macOS 14 acceptance remains deferred. If a native capability cannot be observed, mark it unobserved in STATUS rather than inferring it from an automated test.

- [x] **Step 5: Update README only after bounded native evidence; unobserved capabilities remain documented**

Keep the existing screenshots and update the existing system-monitor feature paragraph with this exact factual text:

```markdown
The main dashboard combines CPU, RAM, disk, network, battery, and AI usage in one compact popover. It uses aligned high-contrast values, hides normal freshness noise, and keeps stale or failed states visible without changing the underlying metrics or provider actions.
```

Do not add a generated browser mockup or claim native macOS 14 support. Verify the README diff contains no credentials, account identifiers, IP addresses, or synthetic native evidence.

- [x] **Step 6: Record STATUS evidence and the next continuation point**

Append a dated section to `docs/STATUS.md` containing the exact implementation commits, focused/full/package/smoke command results, native evidence paths, observed light/dark/short-height/tooltip/action behaviors, unobserved limitations, and the explicit statement that macOS 14 acceptance remains deferred. State that the public v0.2.2 app and widgets were untouched and that no push/merge/release was performed.

- [x] **Step 7: Run final verification on the documentation checkpoint**

```bash
make test
make package
make smoke
git diff --check
git status --short
```

Expected: all commands exit 0; only the intended README, STATUS, and plan-checkbox changes remain. Review the diff for accidental changes to model, provider, auth, menu-bar, widget, notification, export, or packaging behavior.

- [x] **Step 8: Commit the verified documentation checkpoint**

```bash
git add README.md docs/STATUS.md docs/superpowers/plans/2026-09-03-system-dashboard-readability.md
git commit -m "docs: record verified dashboard readability refresh"
```

Do not push, merge, publish, sign, or release from this plan unless the user separately requests it.

## Execution acceptance checklist

- [~] The main popover remains exactly 360 points wide, with a maximum height of 680 points and a scrollable body at 360×400 (automated 360×400 fitting is covered; native short-screen scrolling is unobserved).
- [~] Header/footer, Settings, Analytics, outside-click dismissal, provider actions, panel anchoring, local/public IP privacy, and Fable subordinate semantics are unchanged (outside-click and Fable are observed; Settings/Analytics/provider actions are unobserved natively).
- [x] CPU, RAM, Disk, Network, Battery, and AI sections use the balanced-density arrangement and shared two-column value alignment.
- [x] Values use semibold monospaced digits, a finite minimum column separation, and stable fitting across live numeric changes.
- [~] Light/dark surfaces are adaptive high-contrast materials; tint is supplemental, not the only meaning carrier (bright shell observed; dark mode unobserved).
- [~] Normal `Fresh` labels are suppressed; permitted stale/error/authentication state text remains accessible and unavailable values remain `—` (normal live state observed; forced states unobserved natively).
- [~] Long ordinary values tail-truncate; address-like values middle-truncate; complete values remain available through help and accessibility (automated coverage; native tooltip/accessibility unobserved).
- [~] AI provider order/visibility, selected metric, Claude/Codex/Cursor actions, and separate Claude Fable remaining/reset/freshness remain unchanged (Claude/Fable observed; provider actions unobserved natively).
- [x] Automated focused/full/package/smoke gates pass, and native evidence is recorded separately from automated and macOS 14 evidence.
- [~] README and STATUS are changed only after bounded native evidence; no push/merge/release is performed (complete native and macOS 14 acceptance remain deferred).

## Plan self-review

Spec coverage: the file map and Tasks 2–3 cover the bright adaptive shell without a second corner clip, fixed dimensions, real `Grid`/`GridRow` alignment, explicit Disk Name/Used/Available rows, gauges/charts, network/IP privacy, AI provider/Fable rows, always-visible provider captions with suppressed normal status noise, adaptive warning emphasis, long-value help/accessibility, live-update stability, and light/dark size fitting. Task 4 covers native contrast/scroll/tooltip/action acceptance, README/STATUS timing, package/smoke gates, evidence hygiene, and deferred macOS 14 acceptance. The plan explicitly excludes menu-bar/notch/status-item work.

Placeholder scan: the plan contains no `TBD`, `TODO`, or unspecified implementation step. Every production code-changing step includes a complete declaration or replacement body and every test-changing step includes executable Swift test code.

Type consistency: `DashboardReadabilityPolicy.systemStatus` accepts `DashboardFreshness`; `providerStatus` accepts two existing `PresentationFreshness` values; `DashboardMetricValue` stores a `Text.TruncationMode`; `DashboardMetricRow` returns a two-cell `GridRow`, and `DashboardMetricGrid` returns a `Grid` that consumes those rows; `DashboardMetricText`, `DashboardSection`, `MetricGauge`, `PerCoreActivityBars`, and `DashboardTrendMetrics` are the exact names consumed by the view snippets. `FableQuotaDetail.freshness` remains `PresentationFreshness`, and `fableStatus` handles all five existing cases without changing model types or collapsing the provider action into an accessibility container.
