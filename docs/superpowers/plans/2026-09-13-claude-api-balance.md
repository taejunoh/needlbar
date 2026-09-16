# Claude API Balance Native Feasibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish whether a user can complete Claude Console login and revisit its Billing page in an isolated, Needlbar-owned persistent `WKWebsiteDataStore` on macOS 14, then remove that store on demand.

**Architecture:** This is a review-only executable, patterned after `NeedlbarSettingsStudioReview`, with a separate SwiftPM support target. It owns no production `NeedlbarApp` state, records only sanitized HTTPS origins and DOM counts, and renders the real page for user inspection. Production wiring is blocked until the native acceptance evidence is recorded.

**Tech Stack:** Swift 6, Swift Testing, AppKit, WebKit, macOS 14 `WKWebsiteDataStore`, SwiftPM, Make.

---

## Boundary and stop gate

The browser inspection proved a distinct `Credit balance` / `Remaining balance`
section, but it did not prove embedded login, organization presentation, or
WebKit session persistence. This plan makes no production change and does not
guess redirect origins, organization selectors, or private APIs.

Only proceed to a later production plan if native acceptance proves all of the
following: embedded login works; the exact finite main-frame HTTPS origin set is
reviewed; the billing route renders a unique credit-balance section and unique
remaining-balance label; the user can identify the currently selected
organization on-screen; a restart reuses the dedicated store; and explicit
store deletion succeeds. Any failure stops this work and retains the existing
external billing link as the fallback.

## File map

- Modify: `Package.swift` — add a harness-only library, executable, and test
  target; do not add WebKit to `NeedlbarApp`.
- Modify: `Makefile` — add opt-in run and clear targets that are not dependencies
  of `test`, `package`, `smoke`, or `run`.
- Create: `Sources/NeedlbarClaudeAPIBalanceFeasibilitySupport/ClaudeAPIBalanceFeasibilitySupport.swift`
  — closed command parser, fixed harness store UUID, fixed billing URL, and
  origin-only redaction policy.
- Create: `Sources/NeedlbarClaudeAPIBalanceFeasibility/main.swift` — visible
  native `WKWebView` review host.
- Create: `Tests/NeedlbarClaudeAPIBalanceFeasibilitySupportTests/ClaudeAPIBalanceFeasibilitySupportTests.swift`
  — deterministic support-contract coverage.
- Modify after the acceptance gate only: `docs/STATUS.md` — record sanitized
  evidence and whether a new production plan is authorized.

The UUID below is for the harness alone. It is an identifier, never a
credential, and must not be reused by a production session coordinator.

### Task 1: Add a closed harness launch and redaction contract

**Files:**

- Modify: `Package.swift`
- Create: `Sources/NeedlbarClaudeAPIBalanceFeasibilitySupport/ClaudeAPIBalanceFeasibilitySupport.swift`
- Create: `Tests/NeedlbarClaudeAPIBalanceFeasibilitySupportTests/ClaudeAPIBalanceFeasibilitySupportTests.swift`
- Create: `Sources/NeedlbarClaudeAPIBalanceFeasibility/main.swift`

- [ ] **Step 1: Add isolated SwiftPM targets and a failing parser test.**

Add this product and targets to `Package.swift`; leave all existing targets
unchanged.

```swift
.executable(name: "NeedlbarClaudeAPIBalanceFeasibility", targets: ["NeedlbarClaudeAPIBalanceFeasibility"]),
```

```swift
.target(name: "NeedlbarClaudeAPIBalanceFeasibilitySupport"),
.executableTarget(
    name: "NeedlbarClaudeAPIBalanceFeasibility",
    dependencies: ["NeedlbarClaudeAPIBalanceFeasibilitySupport"],
    path: "Sources/NeedlbarClaudeAPIBalanceFeasibility",
    linkerSettings: [.linkedFramework("WebKit", .when(platforms: [.macOS]))]
),
.testTarget(
    name: "NeedlbarClaudeAPIBalanceFeasibilitySupportTests",
    dependencies: ["NeedlbarClaudeAPIBalanceFeasibilitySupport"]
),
```

Create the support file with this compile anchor:

```swift
import Foundation
public enum ClaudeAPIBalanceFeasibilityLaunchError: Error, Equatable, Sendable { case invalidArguments }
public enum ClaudeAPIBalanceFeasibilityLaunch {}
```

Create the executable compile anchor before running the test. It has no WebKit
import, no network request, and no production-app entry point:

```swift
import Foundation
import NeedlbarClaudeAPIBalanceFeasibilitySupport

exit(0)
```

Create the test file:

```swift
import Foundation
import Testing
@testable import NeedlbarClaudeAPIBalanceFeasibilitySupport

@Test func feasibilityLaunchAcceptsOnlyRunOrClear() throws {
    #expect(try ClaudeAPIBalanceFeasibilityLaunch.parse(arguments: ["tool", "--claude-api-balance-feasibility"]) == .run)
    #expect(try ClaudeAPIBalanceFeasibilityLaunch.parse(arguments: ["tool", "--clear-claude-api-balance-feasibility-store"]) == .clear)
    #expect(throws: ClaudeAPIBalanceFeasibilityLaunchError.invalidArguments) {
        try ClaudeAPIBalanceFeasibilityLaunch.parse(arguments: ["tool", "--acceptance-fixture", "/private/input.json"])
    }
}
```

- [ ] **Step 2: Run RED.**

Run:

```bash
swift test --filter feasibilityLaunchAcceptsOnlyRunOrClear
```

Expected: FAIL because `parse(arguments:)`, `.run`, and `.clear` do not exist.
No app window or network request may be started by this test.

- [ ] **Step 3: Implement the complete pure support boundary.**

Replace the compile anchor with:

```swift
import Foundation

public enum ClaudeAPIBalanceFeasibilityMode: Equatable, Sendable { case run, clear }
public enum ClaudeAPIBalanceFeasibilityLaunchError: Error, Equatable, Sendable { case invalidArguments }

public enum ClaudeAPIBalanceFeasibilityLaunch {
    public static func parse(arguments: [String]) throws -> ClaudeAPIBalanceFeasibilityMode {
        guard arguments.count == 2 else { throw ClaudeAPIBalanceFeasibilityLaunchError.invalidArguments }
        switch arguments[1] {
        case "--claude-api-balance-feasibility": return .run
        case "--clear-claude-api-balance-feasibility-store": return .clear
        default: throw ClaudeAPIBalanceFeasibilityLaunchError.invalidArguments
        }
    }
}

public enum ClaudeAPIBalanceFeasibilityStore {
    public static let identifier = UUID(uuidString: "27B56380-7838-4B83-B1A8-A9B408524E9B")!
    public static let billingURL = URL(string: "https://platform.claude.com/settings/billing")!
}

public enum ClaudeAPIBalanceFeasibilityNavigationEvent: Equatable, Sendable {
    case allowedPlatformOrigin
    case blockedOrigin(String)
}

public enum ClaudeAPIBalanceFeasibilityNavigationPolicy {
    public static func event(for url: URL) -> ClaudeAPIBalanceFeasibilityNavigationEvent {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "platform.claude.com",
              (url.port ?? 443) == 443,
              url.user == nil,
              url.password == nil
        else {
            return .blockedOrigin(sanitizedOrigin(for: url))
        }
        return .allowedPlatformOrigin
    }
    public static func allows(_ url: URL) -> Bool {
        if case .allowedPlatformOrigin = event(for: url) { return true }
        return false
    }
    public static func isBillingRoute(_ url: URL) -> Bool {
        allows(url) && url.path == "/settings/billing" && url.query == nil && url.fragment == nil
    }
    private static func sanitizedOrigin(for url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? "invalid"
        let host = url.host?.lowercased() ?? "invalid"
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }
}
```

- [ ] **Step 4: Add and run redaction tests.**

Append to the same test file:

```swift
@Test func navigationEventsNeverExposePathQueryOrFragment() {
    let url = URL(string: "https://login.example.test:8443/auth/callback?code=secret-value#fragment")!
    #expect(ClaudeAPIBalanceFeasibilityNavigationPolicy.event(for: url) == .blockedOrigin("https://login.example.test:8443"))
    #expect(ClaudeAPIBalanceFeasibilityNavigationPolicy.allows(URL(string: "https://platform.claude.com:443/settings/billing")!))
    #expect(!ClaudeAPIBalanceFeasibilityNavigationPolicy.allows(URL(string: "https://platform.claude.com:8443/settings/billing")!))
    #expect(!ClaudeAPIBalanceFeasibilityNavigationPolicy.allows(URL(string: "https://user:password@platform.claude.com/settings/billing")!))
    #expect(!ClaudeAPIBalanceFeasibilityNavigationPolicy.allows(URL(string: "http://platform.claude.com/settings/billing")!))
    #expect(!ClaudeAPIBalanceFeasibilityNavigationPolicy.allows(URL(string: "needlbar://callback?token=secret-value")!))
    #expect(ClaudeAPIBalanceFeasibilityNavigationPolicy.isBillingRoute(ClaudeAPIBalanceFeasibilityStore.billingURL))
    #expect(!ClaudeAPIBalanceFeasibilityNavigationPolicy.isBillingRoute(URL(string: "https://platform.claude.com/settings/billing/other")!))
    #expect(!ClaudeAPIBalanceFeasibilityNavigationPolicy.isBillingRoute(URL(string: "https://platform.claude.com/settings/billing?state=secret-value")!))
}
```

Run:

```bash
swift test --filter NeedlbarClaudeAPIBalanceFeasibilitySupportTests
```

Expected: PASS. The support API has no cookie, Keychain, HTTP client, Rust
bridge, storage read, or URL-string return surface.

### Task 2: Implement the isolated native review executable

**Files:**

- Create: `Sources/NeedlbarClaudeAPIBalanceFeasibility/main.swift`
- Modify: `Makefile`

- [ ] **Step 1: Add the native review host.**

Replace the executable compile anchor with the complete review-only host below.
The explicit Inspect button handles SPA hydration. Its probe returns counts only;
it is not an amount or organization extractor.

```swift
import AppKit
import Foundation
import WebKit
import NeedlbarClaudeAPIBalanceFeasibilitySupport

private let probe = """
(() => {
  const n = v => (v || '').replace(/\\s+/g, ' ').trim();
  const s = Array.from(document.querySelectorAll('section')).filter(x => Array.from(x.querySelectorAll('h1,h2,h3,h4,h5,h6')).some(h => n(h.textContent) === 'Credit balance'));
  const l = s.length === 1 ? Array.from(s[0].querySelectorAll('*')).filter(x => x.children.length === 0 && n(x.textContent) === 'Remaining balance') : [];
  return { creditBalanceSectionCount: s.length, remainingBalanceLabelCount: l.length };
})()
"""

@MainActor final class FeasibilityHost: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
  let mode: ClaudeAPIBalanceFeasibilityMode
  var window: NSWindow?; var webView: WKWebView?; var exitStatus: Int32 = 0
  init(mode: ClaudeAPIBalanceFeasibilityMode) { self.mode = mode; super.init() }
  func applicationDidFinishLaunching(_ notification: Notification) { if mode == .run { start() } else { clearStore() } }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
  func windowWillClose(_ notification: Notification) { webView?.navigationDelegate = nil; webView?.uiDelegate = nil; webView = nil; window = nil; finish(0) }
  func start() {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = WKWebsiteDataStore.dataStore(forIdentifier: ClaudeAPIBalanceFeasibilityStore.identifier)
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.navigationDelegate = self; view.uiDelegate = self
    let inspect = NSButton(title: "Inspect approved billing DOM", target: self, action: #selector(inspectBillingDOM))
    let stack = NSStackView(views: [view, inspect]); stack.orientation = .vertical
    stack.alignment = .leading
    view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([view.widthAnchor.constraint(equalTo: stack.widthAnchor), view.heightAnchor.constraint(greaterThanOrEqualToConstant: 500)])
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 800), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.title = "Claude API Balance — Native Feasibility Only"; window.contentView = stack; window.delegate = self
    NSApp.setActivationPolicy(.regular); window.center(); window.makeKeyAndOrderFront(nil)
    self.window = window; webView = view; view.load(URLRequest(url: ClaudeAPIBalanceFeasibilityStore.billingURL))
  }
  func clearStore() {
    WKWebsiteDataStore.removeDataStore(forIdentifier: ClaudeAPIBalanceFeasibilityStore.identifier) { [weak self] error in
      if let error { let error = error as NSError; print("CLAUDE_API_BALANCE_FEASIBILITY storeDelete=failed domain=\(error.domain) code=\(error.code)"); self?.finish(1) }
      else { print("CLAUDE_API_BALANCE_FEASIBILITY storeDelete=succeeded"); self?.finish(0) }
    }
  }
  @objc func inspectBillingDOM() {
    guard let view = webView, let url = view.url, ClaudeAPIBalanceFeasibilityNavigationPolicy.isBillingRoute(url) else { print("CLAUDE_API_BALANCE_FEASIBILITY domProbe=notOnApprovedBillingRoute"); return }
    view.evaluateJavaScript(probe) { value, error in
      guard error == nil, let result = value as? [String: Any], let sections = result["creditBalanceSectionCount"] as? Int, let labels = result["remainingBalanceLabelCount"] as? Int else { print("CLAUDE_API_BALANCE_FEASIBILITY domProbe=unavailable"); return }
      print("CLAUDE_API_BALANCE_FEASIBILITY creditBalanceSectionCount=\(sections) remainingBalanceLabelCount=\(labels)")
    }
  }
  func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
    guard action.targetFrame?.isMainFrame != false, let url = action.request.url else { decisionHandler(action.request.url == nil ? .cancel : .allow); return }
    switch ClaudeAPIBalanceFeasibilityNavigationPolicy.event(for: url) {
    case .allowedPlatformOrigin: print("CLAUDE_API_BALANCE_FEASIBILITY mainFrameOrigin=https://platform.claude.com:443"); decisionHandler(.allow)
    case let .blockedOrigin(origin): print("CLAUDE_API_BALANCE_FEASIBILITY blockedMainFrameOrigin=\(origin)"); decisionHandler(.cancel)
    }
  }
  func webView(_ view: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
    guard action.targetFrame == nil, let url = action.request.url else { return nil }
    switch ClaudeAPIBalanceFeasibilityNavigationPolicy.event(for: url) {
    case .allowedPlatformOrigin: view.load(URLRequest(url: url))
    case let .blockedOrigin(origin): print("CLAUDE_API_BALANCE_FEASIBILITY blockedMainFrameOrigin=\(origin)")
    }
    return nil
  }
  func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) { if let url = view.url, ClaudeAPIBalanceFeasibilityNavigationPolicy.isBillingRoute(url) { print("CLAUDE_API_BALANCE_FEASIBILITY billingRouteLoaded=true") } }
  func webView(_ view: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { let error = error as NSError; print("CLAUDE_API_BALANCE_FEASIBILITY provisionalLoad=failed domain=\(error.domain) code=\(error.code)") }
  func finish(_ status: Int32) { exitStatus = status; NSApp.stop(nil); NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: false) }
}

let mode: ClaudeAPIBalanceFeasibilityMode
do { mode = try ClaudeAPIBalanceFeasibilityLaunch.parse(arguments: CommandLine.arguments) }
catch { print("NeedlbarClaudeAPIBalanceFeasibility requires --claude-api-balance-feasibility or --clear-claude-api-balance-feasibility-store"); exit(64) }
let application = NSApplication.shared; let host = FeasibilityHost(mode: mode)
application.delegate = host; application.run(); exit(host.exitStatus)
```

The harness allows only `https://platform.claude.com:443` without userinfo.
It cancels every other main-frame or target-nil origin before authentication and
logs only its sanitized origin for human review. It never treats an observation
as authorization to permit that origin.

- [ ] **Step 2: Add opt-in commands and verify the review binary.**

Add to `Makefile`:

```make
.PHONY: claude-api-balance-feasibility claude-api-balance-feasibility-clear

claude-api-balance-feasibility:
	swift run NeedlbarClaudeAPIBalanceFeasibility --claude-api-balance-feasibility

claude-api-balance-feasibility-clear:
	swift run NeedlbarClaudeAPIBalanceFeasibility --clear-claude-api-balance-feasibility-store
```

Run:

```bash
swift build --product NeedlbarClaudeAPIBalanceFeasibility
make claude-api-balance-feasibility-clear
swift test --filter NeedlbarClaudeAPIBalanceFeasibilitySupportTests
```

Expected: build and tests exit 0; clear prints `storeDelete=succeeded`. These
commands perform no normal-app launch, installation, package, release, or
credential-import mutation.

- [ ] **Step 3: Run the focused project gate and commit the harness before live acceptance.**

Run:

```bash
make swift-test SWIFT_TEST_FILTER='NeedlbarClaudeAPIBalanceFeasibilitySupportTests'
git diff --check
```

Expected: both exit 0. Commit only the review executable, its pure support
contract, its tests, `Package.swift`, and `Makefile`:

```bash
git add Package.swift Makefile Sources/NeedlbarClaudeAPIBalanceFeasibilitySupport/ClaudeAPIBalanceFeasibilitySupport.swift Sources/NeedlbarClaudeAPIBalanceFeasibility/main.swift Tests/NeedlbarClaudeAPIBalanceFeasibilitySupportTests/ClaudeAPIBalanceFeasibilitySupportTests.swift
git commit -m "test: add Claude API balance native feasibility harness"
```

This commit does not mark the feature complete. It creates the controlled
evidence tool required by the following user-driven gate.

### Task 3: Mandatory user-driven native feasibility gate

**Files:**

- Modify only after this gate: `docs/STATUS.md`

- [ ] **Step 1: Clear, log in, and inspect the native page.**

Run:

```bash
make claude-api-balance-feasibility-clear
make claude-api-balance-feasibility
```

The user completes all login, MFA, CAPTCHA, and organization selection directly
in the visible native window. Never inspect, copy, log, fixture, or commit any
credential, cookie, token, account identifier, balance value, payment detail,
invoice, raw URL, or page source.

Record only these sanitized facts: the finite emitted HTTPS origins; whether
the exact billing route loaded; whether both printed DOM counts are one; and
whether the user can visibly identify the selected organization. Stop if any
origin is unreviewed, any count differs from one, or the selected organization
cannot be visibly identified. Do not infer a selector or permit that origin.
The visible amount establishes only that the native page displays a balance;
this harness does not validate a whitelisted amount parser or organization DOM
provenance, and must not claim extraction feasibility.

- [ ] **Step 2: Prove restart reuse, then clear the test store.**

Close the window without clearing it, then run:

```bash
make claude-api-balance-feasibility
```

Expected: the page is revisited using the same harness-only WebKit store. If
the provider asks to authenticate again, record that persistent reuse is not
proven and stop; do not add hidden navigation, a timer, startup fetch, or a
`RefreshCoordinator` hook. Close the window, then run:

```bash
make claude-api-balance-feasibility-clear
```

Expected: `storeDelete=succeeded`. Run the clear command once more after any
failed attempt so the harness does not leave an approved session behind.

- [ ] **Step 3: Record outcome and verify repository gates.**

On pass, add a sanitized `docs/STATUS.md` entry naming only the reviewed origin
strings and confirming native route/counts, visible organization identification,
restart reuse, and successful deletion. On stop, record only the safe failure
category and that the external billing link remains the fallback. In either
case, run:

```bash
git diff --check
make test
```

Expected: both exit 0 before claiming the feasibility milestone complete. Do
not package, install, release, or publish the app in this milestone.

## Explicitly deferred production requirements

The approved design requires a production provider-specific persistent store,
an exact navigation allowlist, organization-qualified balance observation,
validated whitelisted `Remaining balance` extraction, explicit
connect/disconnect UI, dashboard measurement, cancellation and pending-clear
recovery, and manual-refresh-only presentation. They are not tasks in this
plan because the native redirect set, organization UI, and page contract have
not been observed. In particular, this harness intentionally does **not** prove
an amount parser or organization DOM provenance. A passing Task 3 is the
evidence required to write a separate production plan. That follow-up must keep
the session out of the existing Claude subscription login, Keychain quota path,
`RefreshCoordinator`, Rust C ABI, widget, Analytics, and background work.
