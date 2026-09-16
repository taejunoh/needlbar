import Foundation
import Darwin
import Testing
@testable import NeedlbarClaudeAPIBalanceFeasibilitySupport

@Test func feasibilityLaunchAcceptsOnlyRunOrClear() throws {
    #expect(try ClaudeAPIBalanceFeasibilityLaunch.parse(arguments: ["tool", "--claude-api-balance-feasibility"]) == .run)
    #expect(try ClaudeAPIBalanceFeasibilityLaunch.parse(arguments: ["tool", "--clear-claude-api-balance-feasibility-store"]) == .clear)
    #expect(throws: ClaudeAPIBalanceFeasibilityLaunchError.invalidArguments) {
        try ClaudeAPIBalanceFeasibilityLaunch.parse(arguments: ["tool", "--acceptance-fixture", "/private/input.json"])
    }
}

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
