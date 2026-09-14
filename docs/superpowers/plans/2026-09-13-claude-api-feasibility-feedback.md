# Claude API Feasibility Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface and immediately flush safe native feasibility feedback without changing authentication, navigation policy, store behavior, or any production target.

**Architecture:** The existing Foundation support target gets two narrow seams: a token reducer that rejects stale callback results but does not make route decisions, and a file-descriptor event writer. The existing WebKit host remains responsible for current `WKNavigation` identity and current URL policy checks at each callback; it renders the reducer’s exact status beside Inspect.

**Tech Stack:** Swift 6, Foundation, Darwin POSIX, Swift Testing, AppKit, WebKit.

---

## File structure

- Modify `Sources/NeedlbarClaudeAPIBalanceFeasibilitySupport/ClaudeAPIBalanceFeasibilitySupport.swift`: retain launch/store/policy; add reducer, sanitized failure value, and fd writer.
- Modify `Tests/NeedlbarClaudeAPIBalanceFeasibilitySupportTests/ClaudeAPIBalanceFeasibilitySupportTests.swift`: synthetic reducer tests plus an in-process pipe test.
- Modify `Sources/NeedlbarClaudeAPIBalanceFeasibility/main.swift`: inline label and guarded host wiring only.
- Modify `docs/superpowers/specs/2026-09-13-claude-api-feasibility-feedback-design.md`: status only, exactly `Approved for implementation.`

Do not add a test target: the current support test target cannot import the executable’s top-level `NSApplication` entry point. The reducer and pipe test are the approved no-network/no-store/no-login native-feedback seam.

### Task 1: Test a compiling feedback contract and immediate event output

**Files:**

- Modify: `Tests/NeedlbarClaudeAPIBalanceFeasibilitySupportTests/ClaudeAPIBalanceFeasibilitySupportTests.swift`
- Modify: `Sources/NeedlbarClaudeAPIBalanceFeasibilitySupport/ClaudeAPIBalanceFeasibilitySupport.swift`

- [ ] **Step 1: Add this signature-compatible inert stub after the existing navigation policy. It is temporary test scaffolding, not production behavior.**

```swift
public struct ClaudeAPIBalanceFeasibilityCallback: Equatable, Sendable {
    public let generation: UInt64
    public let navigationID: UInt64
}
public struct ClaudeAPIBalanceFeasibilityFailure: Equatable, Sendable {
    public let domain: String
    public let code: Int
    public init(domain: String, code: Int) { self.domain = domain; self.code = code }
}
public enum ClaudeAPIBalanceFeasibilityFeedbackStatus: Equatable, Sendable {
    case loading, billingRouteLoaded, inspectionUnavailable, inspectionRequiresBillingRoute
    case inspectionCounts(sections: Int, labels: Int), unavailable(ClaudeAPIBalanceFeasibilityFailure)
    public var displayText: String { "stub" }
}
public struct ClaudeAPIBalanceFeasibilityFeedbackEmission: Equatable, Sendable {
    public let status: ClaudeAPIBalanceFeasibilityFeedbackStatus
    public let eventLine: String
}
public struct ClaudeAPIBalanceFeasibilityFeedback: Sendable {
    public init() {}
    public mutating func beginNavigation(navigationID: UInt64, approvedOrigin: Bool, approvedBillingRoute: Bool) -> (callback: ClaudeAPIBalanceFeasibilityCallback, emission: ClaudeAPIBalanceFeasibilityFeedbackEmission) {
        (.init(generation: 0, navigationID: navigationID), .init(status: .loading, eventLine: "stub"))
    }
    public func routeLoaded(for callback: ClaudeAPIBalanceFeasibilityCallback, isExactBillingRoute: Bool) -> ClaudeAPIBalanceFeasibilityFeedbackEmission? { nil }
    public func inspectionCounts(for callback: ClaudeAPIBalanceFeasibilityCallback, isExactBillingRoute: Bool, sections: Int, labels: Int) -> ClaudeAPIBalanceFeasibilityFeedbackEmission? { nil }
    public func inspectionUnavailable(for callback: ClaudeAPIBalanceFeasibilityCallback, isExactBillingRoute: Bool) -> ClaudeAPIBalanceFeasibilityFeedbackEmission? { nil }
    public func inspectionRequiresBillingRoute() -> ClaudeAPIBalanceFeasibilityFeedbackEmission { .init(status: .inspectionRequiresBillingRoute, eventLine: "stub") }
    public func provisionalFailure(for callback: ClaudeAPIBalanceFeasibilityCallback, isAllowedOrigin: Bool, failure: ClaudeAPIBalanceFeasibilityFailure) -> ClaudeAPIBalanceFeasibilityFeedbackEmission? { nil }
    public func isCurrent(_ callback: ClaudeAPIBalanceFeasibilityCallback) -> Bool { false }
    public mutating func invalidate() {}
}
public struct ClaudeAPIBalanceFeasibilityEventWriter: Sendable {
    public init(fileDescriptor: Int32) {}
    public func write(_ line: String) {}
}
```

- [ ] **Step 2: Add the following failing behavioral tests. Import `Darwin` in this test file for `pipe`, `read`, and `close`.**

```swift
@Test func feedbackStatesDescribeEvidenceWithoutAuthenticationOrSuccessClaims() {
    var feedback = ClaudeAPIBalanceFeasibilityFeedback()
    let start = feedback.beginNavigation(navigationID: 7, approvedOrigin: true, approvedBillingRoute: true)

    #expect(start.emission.status.displayText == "Loading approved billing page")
    #expect(start.emission.eventLine == "CLAUDE_API_BALANCE_FEASIBILITY navigationStarted approvedOrigin=true approvedBillingRoute=true")
    #expect(feedback.routeLoaded(for: start.callback, isExactBillingRoute: true)?.status.displayText == "Page loaded — authentication unproven")
    #expect(feedback.inspectionCounts(for: start.callback, isExactBillingRoute: true, sections: 1, labels: 1)?.status.displayText == "Inspection counts: sections 1, labels 1 — success unproven")
    #expect(feedback.inspectionUnavailable(for: start.callback, isExactBillingRoute: true)?.status.displayText == "Inspection unavailable")
    #expect(feedback.inspectionRequiresBillingRoute().status.displayText == "Inspect the approved billing page first")
}

@Test func feedbackSanitizesErrorFieldsAndRejectsReplacedOrClosedCallbacks() {
    var feedback = ClaudeAPIBalanceFeasibilityFeedback()
    let first = feedback.beginNavigation(navigationID: 7, approvedOrigin: true, approvedBillingRoute: true)
    let second = feedback.beginNavigation(navigationID: 8, approvedOrigin: true, approvedBillingRoute: true)
    let unsafe = ClaudeAPIBalanceFeasibilityFailure(domain: "https://user:password@example.test/path?token=secret", code: -1)

    #expect(unsafe.domain == "invalid")
    #expect(feedback.provisionalFailure(for: first.callback, isAllowedOrigin: true, failure: .init(domain: "NSURLErrorDomain", code: -1009)) == nil)
    #expect(feedback.provisionalFailure(for: second.callback, isAllowedOrigin: true, failure: .init(domain: "NSURLErrorDomain", code: -1009))?.eventLine == "CLAUDE_API_BALANCE_FEASIBILITY provisionalLoad=failed domain=NSURLErrorDomain code=-1009")
    feedback.invalidate()
    #expect(feedback.inspectionCounts(for: second.callback, isExactBillingRoute: true, sections: 1, labels: 1) == nil)
}

@Test func eventWriterMakesLineReadableBeforeWriterLeavesScope() throws {
    var descriptors: [Int32] = [0, 0]
    try #require(Darwin.pipe(&descriptors) == 0)
    defer { Darwin.close(descriptors[0]); Darwin.close(descriptors[1]) }
    try #require(Darwin.fcntl(descriptors[0], F_SETFL, O_NONBLOCK) != -1)

    let writer = ClaudeAPIBalanceFeasibilityEventWriter(fileDescriptor: descriptors[1])
    writer.write("CLAUDE_API_BALANCE_FEASIBILITY domProbe=unavailable")
    var bytes = Array(repeating: UInt8(0), count: 128)
    let count = bytes.withUnsafeMutableBytes { Darwin.read(descriptors[0], $0.baseAddress, $0.count) }
    try #require(count > 0)
    #expect(String(decoding: bytes.prefix(Int(count)), as: UTF8.self) == "CLAUDE_API_BALANCE_FEASIBILITY domProbe=unavailable\n")
}
```

- [ ] **Step 3: Run the focused test. The stub compiles; assertions, not missing symbols, must fail.**

Run:

```bash
make swift-test SWIFT_TEST_FILTER=NeedlbarClaudeAPIBalanceFeasibilitySupportTests
```

Expected: FAIL because the stub returns `stub`/nil and writes no pipe bytes. No WebKit view, network request, login, or website-data-store operation occurs.

- [ ] **Step 4: Replace the stub with this complete production implementation.**

```swift
public struct ClaudeAPIBalanceFeasibilityCallback: Equatable, Sendable {
    public let generation: UInt64
    public let navigationID: UInt64
}

public struct ClaudeAPIBalanceFeasibilityFailure: Equatable, Sendable {
    public let domain: String
    public let code: Int

    public init(domain: String, code: Int) {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-".unicodeScalars)
        self.domain = !domain.isEmpty && domain.unicodeScalars.count <= 128 &&
            domain.unicodeScalars.allSatisfy(allowed.contains) ? domain : "invalid"
        self.code = code
    }
}

public enum ClaudeAPIBalanceFeasibilityFeedbackStatus: Equatable, Sendable {
    case loading, billingRouteLoaded, inspectionUnavailable, inspectionRequiresBillingRoute
    case inspectionCounts(sections: Int, labels: Int), unavailable(ClaudeAPIBalanceFeasibilityFailure)

    public var displayText: String {
        switch self {
        case .loading: "Loading approved billing page"
        case .billingRouteLoaded: "Page loaded — authentication unproven"
        case let .inspectionCounts(sections, labels): "Inspection counts: sections \(sections), labels \(labels) — success unproven"
        case .inspectionUnavailable: "Inspection unavailable"
        case .inspectionRequiresBillingRoute: "Inspect the approved billing page first"
        case let .unavailable(failure): "Unavailable: \(failure.domain) (\(failure.code))"
        }
    }
}

public struct ClaudeAPIBalanceFeasibilityFeedbackEmission: Equatable, Sendable {
    public let status: ClaudeAPIBalanceFeasibilityFeedbackStatus
    public let eventLine: String
}

public struct ClaudeAPIBalanceFeasibilityFeedback: Sendable {
    private var generation: UInt64 = 0
    private var current: ClaudeAPIBalanceFeasibilityCallback?

    public init() {}

    public mutating func beginNavigation(navigationID: UInt64, approvedOrigin: Bool, approvedBillingRoute: Bool) -> (callback: ClaudeAPIBalanceFeasibilityCallback, emission: ClaudeAPIBalanceFeasibilityFeedbackEmission) {
        generation &+= 1
        let callback = ClaudeAPIBalanceFeasibilityCallback(generation: generation, navigationID: navigationID)
        current = callback
        return (callback, emit(.loading, "navigationStarted approvedOrigin=\(approvedOrigin) approvedBillingRoute=\(approvedBillingRoute)"))
    }

    public func isCurrent(_ callback: ClaudeAPIBalanceFeasibilityCallback) -> Bool { current == callback }
    public mutating func invalidate() { generation &+= 1; current = nil }

    public func routeLoaded(for callback: ClaudeAPIBalanceFeasibilityCallback, isExactBillingRoute: Bool) -> ClaudeAPIBalanceFeasibilityFeedbackEmission? {
        guard isCurrent(callback), isExactBillingRoute else { return nil }
        return emit(.billingRouteLoaded, "billingRouteLoaded=true authenticationProven=false")
    }
    public func inspectionCounts(for callback: ClaudeAPIBalanceFeasibilityCallback, isExactBillingRoute: Bool, sections: Int, labels: Int) -> ClaudeAPIBalanceFeasibilityFeedbackEmission? {
        guard isCurrent(callback), isExactBillingRoute else { return nil }
        return emit(.inspectionCounts(sections: sections, labels: labels), "creditBalanceSectionCount=\(sections) remainingBalanceLabelCount=\(labels) successProven=false")
    }
    public func inspectionUnavailable(for callback: ClaudeAPIBalanceFeasibilityCallback, isExactBillingRoute: Bool) -> ClaudeAPIBalanceFeasibilityFeedbackEmission? {
        guard isCurrent(callback), isExactBillingRoute else { return nil }
        return emit(.inspectionUnavailable, "domProbe=unavailable")
    }
    public func inspectionRequiresBillingRoute() -> ClaudeAPIBalanceFeasibilityFeedbackEmission {
        emit(.inspectionRequiresBillingRoute, "domProbe=notOnApprovedBillingRoute")
    }
    public func provisionalFailure(for callback: ClaudeAPIBalanceFeasibilityCallback, isAllowedOrigin: Bool, failure: ClaudeAPIBalanceFeasibilityFailure) -> ClaudeAPIBalanceFeasibilityFeedbackEmission? {
        guard isCurrent(callback), isAllowedOrigin else { return nil }
        return emit(.unavailable(failure), "provisionalLoad=failed domain=\(failure.domain) code=\(failure.code)")
    }
    private func emit(_ status: ClaudeAPIBalanceFeasibilityFeedbackStatus, _ payload: String) -> ClaudeAPIBalanceFeasibilityFeedbackEmission {
        .init(status: status, eventLine: "CLAUDE_API_BALANCE_FEASIBILITY \(payload)")
    }
}

public struct ClaudeAPIBalanceFeasibilityEventWriter: Sendable {
    public let fileDescriptor: Int32
    public init(fileDescriptor: Int32) { self.fileDescriptor = fileDescriptor }

    public func write(_ line: String) {
        let bytes = Array((line + "\n").utf8)
        bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fileDescriptor, base.advanced(by: offset), buffer.count - offset)
                guard count > 0 else { return }
                offset += Int(count)
            }
        }
    }
}
```

Add `import Darwin` to this support file. Route status is intentionally decided from an explicit current callback input, never a URL remembered at `didStart`.

- [ ] **Step 5: Re-run focused tests and commit.**

Run:

```bash
make swift-test SWIFT_TEST_FILTER=NeedlbarClaudeAPIBalanceFeasibilitySupportTests
```

Expected: PASS.

```bash
git add Sources/NeedlbarClaudeAPIBalanceFeasibilitySupport/ClaudeAPIBalanceFeasibilitySupport.swift Tests/NeedlbarClaudeAPIBalanceFeasibilitySupportTests/ClaudeAPIBalanceFeasibilitySupportTests.swift
git commit -m "test: specify Claude feasibility feedback"
```

### Task 2: Bind feedback only to the current native navigation

**Files:**

- Modify: `Sources/NeedlbarClaudeAPIBalanceFeasibility/main.swift`
- Modify: `docs/superpowers/specs/2026-09-13-claude-api-feasibility-feedback-design.md`

- [ ] **Step 1: Make all harness output use the tested writer and add the inline label.**

Add `import Darwin`; replace the sole `navigationGeneration` property with:

```swift
private let eventWriter = ClaudeAPIBalanceFeasibilityEventWriter(fileDescriptor: STDOUT_FILENO)
private var feedback = ClaudeAPIBalanceFeasibilityFeedback()
private var currentNavigation: WKNavigation?
private var currentCallback: ClaudeAPIBalanceFeasibilityCallback?
private var nextNavigationID: UInt64 = 0
private var statusLabel: NSTextField?
```

Replace the one-button stack construction with:

```swift
let inspect = NSButton(title: "Inspect approved billing DOM", target: self, action: #selector(inspectBillingDOM))
let status = NSTextField(labelWithString: ClaudeAPIBalanceFeasibilityFeedbackStatus.loading.displayText)
status.textColor = .secondaryLabelColor
let controls = NSStackView(views: [inspect, status])
controls.orientation = .horizontal
controls.alignment = .centerY
controls.spacing = 8
let stack = NSStackView(views: [view, controls])
stack.orientation = .vertical
stack.alignment = .leading
statusLabel = status
```

Add:

```swift
private func apply(_ emission: ClaudeAPIBalanceFeasibilityFeedbackEmission) {
    statusLabel?.stringValue = emission.status.displayText
    eventWriter.write(emission.eventLine)
}
private func isCurrent(_ view: WKWebView, navigation: WKNavigation, callback: ClaudeAPIBalanceFeasibilityCallback) -> Bool {
    guard webView === view, let currentNavigation else { return false }
    return currentNavigation === navigation && feedback.isCurrent(callback)
}
```

Replace every existing `print` in this file with the writer: all run-mode allowed-origin, blocked-origin, DOM, and provisional error events, plus both clear-store results. For the clear error, form `ClaudeAPIBalanceFeasibilityFailure(domain: error.domain, code: error.code)` before interpolation. The parser’s top-level usage error uses `ClaudeAPIBalanceFeasibilityEventWriter(fileDescriptor: STDOUT_FILENO).write(...)`. This preserves all legacy event payloads while giving every existing harness output immediate unbuffered delivery.

- [ ] **Step 2: Remove every use of `navigationGeneration` and replace lifecycle branches with current checks.**

In `windowWillClose`, replace its generation increment with:

```swift
feedback.invalidate()
currentNavigation = nil
currentCallback = nil
```

Replace `didStartProvisionalNavigation` with:

```swift
func webView(_ view: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    guard webView === view, let navigation else { return }
    nextNavigationID &+= 1
    let url = view.url
    let start = feedback.beginNavigation(
        navigationID: nextNavigationID,
        approvedOrigin: url.map(ClaudeAPIBalanceFeasibilityNavigationPolicy.allows) ?? false,
        approvedBillingRoute: url.map(ClaudeAPIBalanceFeasibilityNavigationPolicy.isBillingRoute) ?? false
    )
    currentNavigation = navigation
    currentCallback = start.callback
    apply(start.emission)
}
```

The start URL contributes diagnostic booleans only. It is never reused for a later route decision.

Replace `didFinish` and `didFailProvisionalNavigation` with:

```swift
func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) {
    guard let navigation, let callback = currentCallback,
          isCurrent(view, navigation: navigation, callback: callback),
          let url = view.url,
          ClaudeAPIBalanceFeasibilityNavigationPolicy.isBillingRoute(url),
          let emission = feedback.routeLoaded(for: callback, isExactBillingRoute: true)
    else { return }
    apply(emission)
}

func webView(_ view: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    guard let navigation, let callback = currentCallback,
          isCurrent(view, navigation: navigation, callback: callback)
    else { return }
    let failure = ClaudeAPIBalanceFeasibilityFailure(domain: (error as NSError).domain, code: (error as NSError).code)
    if let emission = feedback.provisionalFailure(for: callback, isAllowedOrigin: true, failure: failure) { apply(emission) }
}
```

Replace `inspectBillingDOM()` with the current-route checks before and after JavaScript. Capture the original `navigation`—never read and shadow it from `currentNavigation` in the completion:

```swift
@objc func inspectBillingDOM() {
    guard let view = webView, let navigation = currentNavigation, let callback = currentCallback,
          isCurrent(view, navigation: navigation, callback: callback),
          let url = view.url, ClaudeAPIBalanceFeasibilityNavigationPolicy.isBillingRoute(url)
    else { apply(feedback.inspectionRequiresBillingRoute()); return }

    view.evaluateJavaScript(probe) { [weak self, weak view, navigation] value, error in
        guard let self, let view,
              self.isCurrent(view, navigation: navigation, callback: callback),
              let url = view.url, ClaudeAPIBalanceFeasibilityNavigationPolicy.isBillingRoute(url)
        else { return }
        guard error == nil, let result = value as? [String: Any],
              let sections = result["creditBalanceSectionCount"] as? Int,
              let labels = result["remainingBalanceLabelCount"] as? Int,
              let emission = self.feedback.inspectionCounts(for: callback, isExactBillingRoute: true, sections: sections, labels: labels)
        else {
            if let emission = self.feedback.inspectionUnavailable(for: callback, isExactBillingRoute: true) { self.apply(emission) }
            return
        }
        self.apply(emission)
    }
}
```

Keep every `decidePolicyFor` and `createWebViewWith` decision unchanged: blocked navigations emit only the separate sanitized-origin policy event and cannot become Unavailable.

The provisional-error branch must not require `view.url`: it can be nil during
a failed initial load, which is precisely when feedback is needed. Its current
main-navigation identity was admitted through the unchanged origin policy;
the emitted error carries only sanitized domain/code, never a failing URL.
The pipe read is nonblocking so the inert writer fails an assertion instead
of hanging. The full support filter includes the writer test as well as the
feedback tests.

- [ ] **Step 3: Verify the support suite then repository suite without opening/clearing the harness.**

Run:

```bash
make swift-test SWIFT_TEST_FILTER=NeedlbarClaudeAPIBalanceFeasibilitySupportTests
make test
```

Expected: both exit 0. Do not run the feasibility executable, clear the fixed UUID store, authenticate, retry, poll, add origins, or infer a cause/fix for `-1009`.

- [ ] **Step 4: Commit the host integration and status evidence.**

The feedback specification was already approved for implementation at task
start, so its status is a no-op in this task. Record the focused and full
verification evidence in `docs/STATUS.md` instead.

```bash
git add Sources/NeedlbarClaudeAPIBalanceFeasibility/main.swift docs/STATUS.md
git commit -m "feat: surface Claude feasibility feedback"
```

## Verification boundary

These tests prove safe event/status construction, a real readable pipe write before writer scope ends, and stale token rejection. They do not prove native authentication, session reuse, page contents, network diagnosis, the cause of `NSURLErrorDomain (-1009)`, amount parsing, or balance refresh.
