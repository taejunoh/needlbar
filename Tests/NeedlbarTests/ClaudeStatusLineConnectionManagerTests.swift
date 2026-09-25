import Foundation
import Testing
@testable import NeedlbarApp
import NeedlbarClaudeStatusLineSupport

@Suite("ClaudeStatusLineConnectionManager", .serialized)
@MainActor
struct ClaudeStatusLineConnectionManagerTests {
    private struct Fixture {
        let root: URL
        let config: URL
        let settings: URL
        let store: StatusLinePrivateStore
        let helper: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("Needlbar-connection-\(UUID())", isDirectory: true)
            config = root.appendingPathComponent("claude", isDirectory: true)
            settings = config.appendingPathComponent("settings.json")
            helper = root.appendingPathComponent("NeedlbarClaudeStatusLine")
            try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: config.path)
            try Data().write(to: helper)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
            store = try StatusLinePrivateStore(rootURL: root.appendingPathComponent("private"))
        }

        func write(_ text: String) throws {
            try Data(text.utf8).write(to: settings)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settings.path)
        }

        @MainActor func manager(beforeReplace: (() -> Void)? = nil, environment: [String: String] = [:]) -> ClaudeStatusLineConnectionManager {
            ClaudeStatusLineConnectionManager(configRootURL: config, store: store, helperURL: helper,
                environment: environment, beforeAtomicReplace: beforeReplace)
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func inspectDoesNotEditDefaultOffConfiguration() throws {
        let fixture = try Fixture(); defer { fixture.cleanUp() }
        let original = #"{"theme":"dark"}"#
        try fixture.write(original)
        let result = try fixture.manager().inspect()
        #expect(result.state == .disconnected)
        #expect(try String(contentsOf: fixture.settings, encoding: .utf8) == original)
    }

    @Test func exactOriginalObjectAndOtherFieldsSurviveRoundTrip() throws {
        let fixture = try Fixture(); defer { fixture.cleanUp() }
        let original = #"{ "statusLine" : { "type": "command", "command": "printf original", "padding": 2, "refreshInterval": 17 }, "theme": "dark" }"#
        try fixture.write(original)
        let manager = fixture.manager()
        let revision = try manager.inspect().revision
        #expect(try manager.connect(expectedRevision: revision) == .waitingForData)
        let installed = try Data(contentsOf: fixture.settings)
        #expect(String(decoding: installed, as: UTF8.self).contains("\"padding\": 2"))
        #expect(String(decoding: installed, as: UTF8.self).contains("\"refreshInterval\": 17"))
        #expect(!String(decoding: installed, as: UTF8.self).contains("printf original"))
        #expect(try manager.disconnect() == .disconnected)
        #expect(try Data(contentsOf: fixture.settings) == Data(original.utf8))
    }

    @Test func absentStatusLineIsRemovedWithoutChangingOtherFields() throws {
        let fixture = try Fixture(); defer { fixture.cleanUp() }
        let original = #"{"theme": "dark", "enabled": true}"#
        try fixture.write(original)
        let manager = fixture.manager()
        _ = try manager.connect(expectedRevision: manager.inspect().revision)
        #expect(try manager.disconnect() == .disconnected)
        #expect(try Data(contentsOf: fixture.settings) == Data(original.utf8))
    }

    @Test func unrelatedUserEditWhileConnectedSurvivesDisconnect() throws {
        let fixture = try Fixture(); defer { fixture.cleanUp() }
        try fixture.write(#"{"theme":"dark","statusLine":{"type":"command","command":"printf original"}}"#)
        let manager = fixture.manager()
        _ = try manager.connect(expectedRevision: manager.inspect().revision)
        let installed = try String(contentsOf: fixture.settings, encoding: .utf8)
        try fixture.write(installed.replacingOccurrences(of: #""theme":"dark""#, with: #""theme":"light""#))
        #expect(try manager.disconnect() == .disconnected)
        #expect(try String(contentsOf: fixture.settings, encoding: .utf8)
            == #"{"theme":"light","statusLine":{"type":"command","command":"printf original"}}"#)
    }

    @Test func duplicateKeysAndNonCommandAreRejectedWithoutEdit() throws {
        let fixture = try Fixture(); defer { fixture.cleanUp() }
        for input in [
            #"{"statusLine":{"type":"command","command":"ok"},"statusLine":{"type":"command","command":"bad"}}"#,
            #"{"statusLine":{"type":"command","command":"ok","command":"bad"}}"#,
            #"{"statusLine":{"type":"command","command":"ok","padding":{"x":1,"x":2}}}"#,
            #"{"statusLine":{"type":"text","text":"mine"}}"#,
        ] {
            try fixture.write(input)
            let manager = fixture.manager()
            do {
                _ = try manager.connect(expectedRevision: manager.inspect().revision)
                Issue.record("Unsupported configuration was accepted")
            } catch {
                #expect(error is ConnectionError)
            }
            #expect(try Data(contentsOf: fixture.settings) == Data(input.utf8))
        }
    }

    @Test func revisionMismatchLeavesExternalEditIntact() throws {
        let fixture = try Fixture(); defer { fixture.cleanUp() }
        try fixture.write(#"{"theme":"first"}"#)
        let manager = fixture.manager()
        let oldRevision = try manager.inspect().revision
        let external = #"{"theme":"second"}"#
        try fixture.write(external)
        #expect(throws: ConnectionError.configurationChanged) {
            try manager.connect(expectedRevision: oldRevision)
        }
        #expect(try Data(contentsOf: fixture.settings) == Data(external.utf8))
    }

    @Test func editJustBeforeReplacementIsDetected() throws {
        let fixture = try Fixture(); defer { fixture.cleanUp() }
        try fixture.write(#"{"theme":"first"}"#)
        let external = #"{"theme":"second"}"#
        let manager = fixture.manager(beforeReplace: { try? fixture.write(external) })
        #expect(throws: ConnectionError.configurationChanged) {
            try manager.connect(expectedRevision: manager.inspect().revision)
        }
        #expect(try Data(contentsOf: fixture.settings) == Data(external.utf8))
        #expect(try fixture.store.activeGeneration() == nil)
        let retainedNames = try FileManager.default.contentsOfDirectory(atPath: fixture.root.appendingPathComponent("private").path)
        #expect(retainedNames.contains { $0.hasPrefix("metadata-") })
    }

    @Test func disconnectLeavesUserOwnedReplacementAndFencesOldGeneration() throws {
        let fixture = try Fixture(); defer { fixture.cleanUp() }
        try fixture.write(#"{"statusLine":{"type":"command","command":"printf original"}}"#)
        let manager = fixture.manager()
        _ = try manager.connect(expectedRevision: manager.inspect().revision)
        let installed = try Data(contentsOf: fixture.settings)
        let generation = try #require(try fixture.store.activeGeneration())
        let external = #"{"statusLine":{"type":"command","command":"printf mine"}}"#
        try fixture.write(external)
        #expect(try manager.disconnect() == .configurationChanged)
        #expect(try Data(contentsOf: fixture.settings) == Data(external.utf8))
        #expect(try fixture.store.metadata(for: generation)?.originalCommand == "printf original")
        let observation = StatusLineWindowObservation(usedPercent: 25, resetsAt: nil, receivedAt: Date())
        let oldRecord = StatusLineQuotaRecord(schemaVersion: StatusLineQuotaRecord.currentSchemaVersion,
            generation: generation, fiveHour: observation, sevenDay: nil)
        #expect(try fixture.store.publish(oldRecord) == false)
        #expect(installed != Data(external.utf8))
    }

    @Test func repeatedConnectAndDisconnectCanRecoverWithoutEditingOnLaunch() throws {
        let fixture = try Fixture(); defer { fixture.cleanUp() }
        let original = #"{"statusLine":{"type":"command","command":"printf original"}}"#
        try fixture.write(original)
        let first = fixture.manager()
        _ = try first.connect(expectedRevision: first.inspect().revision)
        let installed = try Data(contentsOf: fixture.settings)
        let restarted = fixture.manager()
        #expect(restarted.recover() == .waitingForData)
        #expect(try Data(contentsOf: fixture.settings) == installed)
        #expect(try restarted.disconnect() == .disconnected)
        #expect(try Data(contentsOf: fixture.settings) == Data(original.utf8))
        _ = try restarted.connect(expectedRevision: restarted.inspect().revision)
        #expect(try restarted.disconnect() == .disconnected)
        #expect(try Data(contentsOf: fixture.settings) == Data(original.utf8))
    }

    @Test func interruptedDisconnectNeverDoubleWrapsTheOwnedCommand() throws {
        let fixture = try Fixture(); defer { fixture.cleanUp() }
        let original = #"{"statusLine":{"type":"command","command":"printf original"}}"#
        try fixture.write(original)
        let manager = fixture.manager()
        _ = try manager.connect(expectedRevision: manager.inspect().revision)
        let generation = try #require(try fixture.store.activeGeneration())
        try fixture.store.deactivate(generation: generation)
        let installed = try Data(contentsOf: fixture.settings)
        #expect(manager.recover() == .configurationChanged)
        #expect(throws: ConnectionError.configurationChanged) {
            try manager.connect(expectedRevision: manager.inspect().revision)
        }
        #expect(try Data(contentsOf: fixture.settings) == installed)
        #expect(try manager.disconnect() == .disconnected)
        #expect(try Data(contentsOf: fixture.settings) == Data(original.utf8))
    }

    @Test func staleRevisionDoesNotReachMetadataPreparation() throws {
        let fixture = try Fixture(); defer { fixture.cleanUp() }
        let original = #"{"theme":"dark"}"#
        try fixture.write(original)
        let manager = fixture.manager(beforeReplace: { fatalError("This hook must not be called") })
        let stale = Data(repeating: 3, count: 32)
        #expect(throws: ConnectionError.configurationChanged) {
            try manager.connect(expectedRevision: stale)
        }
        #expect(try Data(contentsOf: fixture.settings) == Data(original.utf8))
        #expect(manager.recover() == .disconnected)
    }

    @Test func unsupportedConfigDirectoryAndUnsafeSymlinkAreNotEdited() throws {
        let fixture = try Fixture(); defer { fixture.cleanUp() }
        try fixture.write(#"{"theme":"dark"}"#)
        let alternate = fixture.manager(environment: ["CLAUDE_CONFIG_DIR": "/tmp/another-claude"])
        #expect(try alternate.inspect().state == .unsupportedConfiguration)
        #expect(throws: ConnectionError.unsupportedStatusLine) {
            try alternate.connect(expectedRevision: alternate.inspect().revision)
        }
        try FileManager.default.removeItem(at: fixture.settings)
        try FileManager.default.createSymbolicLink(at: fixture.settings, withDestinationURL: fixture.helper)
        #expect(throws: ConnectionError.unsafeSettingsFile) {
            _ = try fixture.manager().inspect()
        }
    }

    @Test func errorsDoNotIncludeOriginalCommand() throws {
        let fixture = try Fixture(); defer { fixture.cleanUp() }
        let secret = "secret-DO-NOT-LOG"
        try fixture.write("{\"statusLine\":{\"type\":\"command\",\"command\":\"\(secret)\"}}")
        let manager = fixture.manager()
        let oldRevision = try manager.inspect().revision
        try fixture.write(#"{"theme":"changed"}"#)
        do { _ = try manager.connect(expectedRevision: oldRevision) } catch {
            #expect(!String(describing: error).contains(secret))
        }
    }
}
