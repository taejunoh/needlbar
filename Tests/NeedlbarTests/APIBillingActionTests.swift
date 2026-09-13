import AppKit
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

@MainActor
@Test func apiBillingActionsUseExactLabelsURLsAndOneInjectedOpen() throws {
    let claude = try #require(ProviderAPIBillingAction(provider: .claude))
    let codex = try #require(ProviderAPIBillingAction(provider: .codex))
    #expect(claude.providerLabel == "Claude API")
    #expect(claude.destination == URL(string: "https://platform.claude.com/settings/billing")!)
    #expect(codex.providerLabel == "OpenAI API")
    #expect(codex.destination == URL(string: "https://platform.openai.com/settings/organization/billing/overview")!)
    #expect(ProviderAPIBillingAction(provider: .cursor) == nil)
    var opened: [URL] = []
    #expect(ProviderAPIBillingActionRouter.open(codex) { opened.append($0); return false } == false)
    #expect(opened == [codex.destination])
}
