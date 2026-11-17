import Foundation
import NeedlbarCore
import Testing
@testable import NeedlbarApp

@Suite("ClaudeAutomaticRunsRelay", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct ClaudeAutomaticRunsRelayTests {
    @Test func theValueIsThePreferenceAndClaudeBeingShown() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        #expect(!fixture.relay.allowed, "off by default")
        fixture.preferences.setEnabled(true)
        #expect(fixture.relay.allowed)
        fixture.hideClaude()
        #expect(!fixture.relay.allowed, "paused while Claude is hidden")
        fixture.preferences.setEnabled(false)
        #expect(!fixture.relay.allowed)
    }

    @Test func valuesReachTheCoordinatorInTheOrderTheyWereComputed() async throws {
        // The first value is the slowest to apply. A consumer that applied values
        // concurrently would deliver it last and leave the coordinator on.
        let fixture = try Fixture(applyDelay: { $0 ? .milliseconds(30) : .zero })
        defer { fixture.tearDown() }
        fixture.preferences.setEnabled(true)
        fixture.relay.push()
        fixture.preferences.setEnabled(false)
        fixture.relay.push()
        // Two direct pushes, then one from each observed change, both computed
        // after the second change.
        await fixture.applied.waitForCount(4)
        #expect(fixture.applied.values == [true, false, false, false])
    }

    @Test func aPreferenceChangeIsPushedWithoutACall() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.preferences.setEnabled(true)
        await fixture.applied.waitForCount(1)
        #expect(fixture.applied.values == [true])
    }

    @Test func hidingAndShowingClaudeIsPushed() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.preferences.setEnabled(true)
        await fixture.applied.waitForCount(1)
        fixture.hideClaude()
        await fixture.applied.waitUntilLast(is: false)
        fixture.showClaude()
        await fixture.applied.waitUntilLast(is: true)
        #expect(fixture.applied.values.first == true)
    }
}

private final class AppliedValues: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Bool] = []

    var values: [Bool] { lock.withLock { recorded } }
    func record(_ value: Bool) { lock.withLock { recorded.append(value) } }

    func waitForCount(_ count: Int) async {
        while !Task.isCancelled, values.count < count {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    func waitUntilLast(is value: Bool) async {
        while !Task.isCancelled, values.last != value {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}

@MainActor
private final class Fixture {
    let preferences: ClaudeAutomaticChecksPreferences
    let configuration: ModuleConfiguration
    let applied = AppliedValues()
    let relay: ClaudeAutomaticRunsRelay
    private let defaults: UserDefaults
    private let name: String

    init(applyDelay: @escaping @Sendable (Bool) -> Duration = { _ in .zero }) throws {
        name = "ClaudeAutomaticRunsRelay.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: name))
        preferences = ClaudeAutomaticChecksPreferences(defaults: defaults)
        configuration = ModuleConfiguration(defaults: defaults)
        let applied = self.applied
        relay = ClaudeAutomaticRunsRelay(preferences: preferences, configuration: configuration) { value in
            try? await Task.sleep(for: applyDelay(value))
            applied.record(value)
        }
    }

    func hideClaude() { setClaudeVisible(false) }
    func showClaude() { setClaudeVisible(true) }

    private func setClaudeVisible(_ visible: Bool) {
        var monitor = configuration.systemMonitor
        monitor.ai[.claude]?.isVisible = visible
        configuration.setSystemMonitor(monitor)
    }

    func tearDown() {
        relay.stop()
        defaults.removePersistentDomain(forName: name)
    }
}
