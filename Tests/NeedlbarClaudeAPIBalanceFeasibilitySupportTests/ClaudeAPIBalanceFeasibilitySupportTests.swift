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
