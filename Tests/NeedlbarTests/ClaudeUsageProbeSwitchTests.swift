import Testing
@testable import NeedlbarApp

@Suite("ClaudeUsageProbeSwitch")
struct ClaudeUsageProbeSwitchTests {
    @Test func theProbeIsOffOnlyWhenTheVariableIsExactlyOne() {
        #expect(ClaudeUsageProbeSwitch.disableEnvironmentName == "NEEDLBAR_DISABLE_CLAUDE_USAGE_PROBE")
        #expect(ClaudeUsageProbeSwitch.isDisabled(environment: ["NEEDLBAR_DISABLE_CLAUDE_USAGE_PROBE": "1"]))
        for value in ["", "0", "true", "yes", " 1", "1 "] {
            #expect(!ClaudeUsageProbeSwitch.isDisabled(environment: ["NEEDLBAR_DISABLE_CLAUDE_USAGE_PROBE": value]), "\(value)")
        }
        #expect(!ClaudeUsageProbeSwitch.isDisabled(environment: [:]))
        #expect(!ClaudeUsageProbeSwitch.isDisabled(environment: ["OTHER": "1"]))
    }
}
