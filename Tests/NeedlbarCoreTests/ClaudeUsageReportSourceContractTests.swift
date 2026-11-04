import Foundation
import Testing

// Source-level checks that retired Claude paths stay retired. This file is under
// Tests, so it does not match itself.
@Suite("ClaudeUsageReportSourceContract")
struct ClaudeUsageReportSourceContractTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func swiftSources() throws -> [(path: String, text: String)] {
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        let enumerator = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var files: [(path: String, text: String)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append((url.path, try String(contentsOf: url, encoding: .utf8)))
        }
        #expect(files.count > 50, "the source walk found the tree")
        return files
    }

    static func expectAbsent(_ forbidden: [String]) throws {
        for file in try swiftSources() {
            for text in forbidden {
                #expect(!file.text.contains(text), "\(file.path) still contains \(text)")
            }
        }
    }

    @Test func theKeychainActionIsGone() throws {
        try Self.expectAbsent([
            "Allow Keychain access",
            "Always Allow",
            "requestClaudeKeychainAccess",
            "allowClaudeKeychainAccess",
            "keychainAccessAction",
            "claudeKeychainAccess",
            "ClaudeKeychainAccess",
            "credentialAccessUnavailable",
            "Credential access unavailable",
        ])
    }

    @Test func needlbarNeverRunsClaudeAuthOrAPreflight() throws {
        try Self.expectAbsent([
            "\"auth\", \"login\"",
            "--claudeai",
            "preflightClaudeLogin",
            "ClaudeLoginPreflightOutcome",
            "claudePreflight",
            "claudeUserInitiated",
            "needlbar_claude_preflight",
            "needlbar_claude_user_initiated",
            "macOS may request access to Claude Code credentials",
            "claudeCodeAccessExpired",
            "ClaudeQuotaFailureOriginAssociation",
        ])
    }

    @Test func noSwiftCodeNamesARetiredOrigin() throws {
        try Self.expectAbsent([
            "credentialMissing", "keychainCredentialExpired", "fileCredentialExpired",
            "credentialStoreAmbiguous", "credentialFormatUnrecognized",
            "usageEndpointUnauthorized", "usageEndpointForbidden", "usageEndpointServerError",
            "usageResponseUnrecognized",
        ])
    }

    @Test func productionInjectsTheUsageReportRepository() throws {
        let appDelegate = Self.root.appendingPathComponent("Sources/Needlbar/App/AppDelegate.swift")
        let text = try String(contentsOf: appDelegate, encoding: .utf8)
        #expect(text.contains("claudeUsageRepository: RustQuotaRepository(bridge: bridge)"))
    }
}
