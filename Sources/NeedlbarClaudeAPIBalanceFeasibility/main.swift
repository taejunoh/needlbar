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

@MainActor
final class FeasibilityHost: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    let mode: ClaudeAPIBalanceFeasibilityMode
    var window: NSWindow?
    var webView: WKWebView?
    var exitStatus: Int32 = 0
    private var navigationGeneration = 0

    init(mode: ClaudeAPIBalanceFeasibilityMode) {
        self.mode = mode
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if mode == .run {
            start()
        } else {
            clearStore()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        mode == .run
    }

    func windowWillClose(_ notification: Notification) {
        navigationGeneration &+= 1
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView = nil
        window = nil
        finish(0)
    }

    func start() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: ClaudeAPIBalanceFeasibilityStore.identifier)
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self

        let inspect = NSButton(title: "Inspect approved billing DOM", target: self, action: #selector(inspectBillingDOM))
        let stack = NSStackView(views: [view, inspect])
        stack.orientation = .vertical
        stack.alignment = .leading
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalTo: stack.widthAnchor),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 500),
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude API Balance — Native Feasibility Only"
        window.contentView = stack
        window.delegate = self
        NSApp.setActivationPolicy(.regular)
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.window = window
        webView = view
        view.load(URLRequest(url: ClaudeAPIBalanceFeasibilityStore.billingURL))
    }

    func clearStore() {
        _ = WKWebsiteDataStore(forIdentifier: ClaudeAPIBalanceFeasibilityStore.identifier)
        WKWebsiteDataStore.remove(forIdentifier: ClaudeAPIBalanceFeasibilityStore.identifier) { [weak self] error in
            if let error {
                let error = error as NSError
                print("CLAUDE_API_BALANCE_FEASIBILITY storeDelete=failed domain=\(error.domain) code=\(error.code)")
                self?.finish(1)
            } else {
                print("CLAUDE_API_BALANCE_FEASIBILITY storeDelete=succeeded")
                self?.finish(0)
            }
        }
    }

    @objc
    func inspectBillingDOM() {
        guard let view = webView,
              let url = view.url,
              ClaudeAPIBalanceFeasibilityNavigationPolicy.isBillingRoute(url)
        else {
            print("CLAUDE_API_BALANCE_FEASIBILITY domProbe=notOnApprovedBillingRoute")
            return
        }

        let generation = navigationGeneration
        view.evaluateJavaScript(probe) { [weak self, weak view] value, error in
            guard let self,
                  let view,
                  self.webView === view,
                  self.navigationGeneration == generation,
                  let currentURL = view.url,
                  ClaudeAPIBalanceFeasibilityNavigationPolicy.isBillingRoute(currentURL),
                  error == nil,
                  let result = value as? [String: Any],
                  let sections = result["creditBalanceSectionCount"] as? Int,
                  let labels = result["remainingBalanceLabelCount"] as? Int
            else {
                print("CLAUDE_API_BALANCE_FEASIBILITY domProbe=unavailable")
                return
            }

            print("CLAUDE_API_BALANCE_FEASIBILITY creditBalanceSectionCount=\(sections) remainingBalanceLabelCount=\(labels)")
        }
    }

    func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard action.targetFrame?.isMainFrame != false,
              let url = action.request.url
        else {
            decisionHandler(action.request.url == nil ? .cancel : .allow)
            return
        }

        switch ClaudeAPIBalanceFeasibilityNavigationPolicy.event(for: url) {
        case .allowedPlatformOrigin:
            print("CLAUDE_API_BALANCE_FEASIBILITY mainFrameOrigin=https://platform.claude.com:443")
            decisionHandler(.allow)
        case let .blockedOrigin(origin):
            print("CLAUDE_API_BALANCE_FEASIBILITY blockedMainFrameOrigin=\(origin)")
            decisionHandler(.cancel)
        }
    }

    func webView(_ view: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard action.targetFrame == nil,
              let url = action.request.url
        else {
            return nil
        }

        switch ClaudeAPIBalanceFeasibilityNavigationPolicy.event(for: url) {
        case .allowedPlatformOrigin:
            view.load(URLRequest(url: url))
        case let .blockedOrigin(origin):
            print("CLAUDE_API_BALANCE_FEASIBILITY blockedMainFrameOrigin=\(origin)")
        }
        return nil
    }

    func webView(_ view: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        navigationGeneration &+= 1
    }

    func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = view.url,
           ClaudeAPIBalanceFeasibilityNavigationPolicy.isBillingRoute(url)
        {
            print("CLAUDE_API_BALANCE_FEASIBILITY billingRouteLoaded=true")
        }
    }

    func webView(_ view: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let error = error as NSError
        print("CLAUDE_API_BALANCE_FEASIBILITY provisionalLoad=failed domain=\(error.domain) code=\(error.code)")
    }

    func finish(_ status: Int32) {
        exitStatus = status
        NSApp.stop(nil)
        NSApp.postEvent(
            NSEvent.otherEvent(
                with: .applicationDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 0,
                data1: 0,
                data2: 0
            )!,
            atStart: false
        )
    }
}

let mode: ClaudeAPIBalanceFeasibilityMode
do {
    mode = try ClaudeAPIBalanceFeasibilityLaunch.parse(arguments: CommandLine.arguments)
} catch {
    print("NeedlbarClaudeAPIBalanceFeasibility requires --claude-api-balance-feasibility or --clear-claude-api-balance-feasibility-store")
    exit(64)
}

let application = NSApplication.shared
let host = FeasibilityHost(mode: mode)
application.delegate = host
application.run()
exit(host.exitStatus)
