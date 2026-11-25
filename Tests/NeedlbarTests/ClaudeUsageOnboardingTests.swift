import Foundation
import Testing
@testable import NeedlbarApp

// The first-run question about automatic Claude checks: the rule, the copy and
// the controller, driven through a fake presenter. No window is built here.
@Suite("ClaudeUsageOnboarding", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct ClaudeUsageOnboardingTests {
    // MARK: - The rule

    @Test func theWindowShowsOnlyWhenUnansweredWithTheProbeEnabledAndClaudeShown() {
        #expect(ClaudeUsageOnboarding.currentVersion == 1)
        #expect(ClaudeUsageOnboarding.answeredVersionKey == "needlbar.onboarding.claudeUsage.answeredVersion")
        for answeredVersion in [0, 1, 2] {
            for probeDisabled in [false, true] {
                for claudeShown in [false, true] {
                    let expected = answeredVersion < 1 && !probeDisabled && claudeShown
                    #expect(
                        ClaudeUsageOnboarding.shouldShow(
                            answeredVersion: answeredVersion, probeDisabled: probeDisabled, claudeShown: claudeShown
                        ) == expected,
                        "version \(answeredVersion), probe disabled \(probeDisabled), shown \(claudeShown)")
                }
            }
        }
    }

    @Test func theCopyIsTheApprovedText() {
        #expect(ClaudeUsageOnboardingCopy.title == "Check Claude quota automatically?")
        #expect(ClaudeUsageOnboardingCopy.body == "Needlbar can run /usage in the Claude Code you installed, under your own sign-in: when Needlbar starts, about every 15 minutes while it is running, when a limit resets, and sooner after a failed check. Needlbar does not read your Claude sign-in. If you leave this off, it runs only when you click Check now. You can change this in Settings.")
        #expect(ClaudeUsageOnboardingCopy.turnOn == "Turn on")
        #expect(ClaudeUsageOnboardingCopy.notNow == "Not now")
    }

    // MARK: - The controller

    @Test func itIsNotShownAndIsRecordedWhenTheSettingIsAlreadyOn() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.preferences.setEnabled(true)
        fixture.controller.presentIfNeeded()
        #expect(fixture.presenter.presentCount == 0)
        #expect(fixture.controller.answeredVersion == 1)
    }

    @Test func itIsShownOnceAndNothingIsRecordedUntilItIsAnswered() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.controller.presentIfNeeded()
        fixture.controller.presentIfNeeded()
        #expect(fixture.presenter.presentCount == 1)
        #expect(fixture.controller.answeredVersion == 0, "appearing records nothing")
        #expect(fixture.defaults.object(forKey: "needlbar.onboarding.claudeUsage.answeredVersion") == nil)

        // A quit before answering: the next launch shows it again.
        let nextLaunch = try Fixture(sharing: fixture)
        nextLaunch.controller.presentIfNeeded()
        #expect(nextLaunch.presenter.presentCount == 1)
    }

    @Test func turnOnSetsThePreferenceAndRecordsTheAnswer() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.controller.presentIfNeeded()
        fixture.presenter.answer(.turnOn)
        #expect(fixture.preferences.isEnabled)
        #expect(fixture.defaults.integer(forKey: "needlbar.onboarding.claudeUsage.answeredVersion") == 1)

        fixture.controller.presentIfNeeded()
        let nextLaunch = try Fixture(sharing: fixture)
        nextLaunch.controller.presentIfNeeded()
        #expect(fixture.presenter.presentCount == 1)
        #expect(nextLaunch.presenter.presentCount == 0, "answered: never shown again")
    }

    @Test func notNowAndClosingTheWindowLeaveItOffAndRecordTheAnswer() throws {
        // The presenter reports the user closing the window as "Not now".
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.controller.presentIfNeeded()
        fixture.presenter.answer(.notNow)
        #expect(!fixture.preferences.isEnabled)
        #expect(fixture.controller.answeredVersion == 1)
        fixture.controller.presentIfNeeded()
        #expect(fixture.presenter.presentCount == 1)
        #expect(fixture.presenter.closeCount == 0, "the presenter closed itself")
    }

    @Test func turningOnElsewhereClosesTheWindowAndRecordsTheAnswer() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.controller.presentIfNeeded()
        // From Settings or the Claude row.
        fixture.preferences.setEnabled(true)
        while !Task.isCancelled, fixture.presenter.closeCount == 0 {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(fixture.presenter.closeCount == 1)
        #expect(fixture.controller.answeredVersion == 1)
        #expect(fixture.preferences.isEnabled)
        // A late answer from the closed window changes nothing.
        fixture.presenter.answer(.notNow)
        #expect(fixture.preferences.isEnabled)
        #expect(fixture.controller.answeredVersion == 1)
    }

    @Test func itIsNotShownWithTheSmokeVariableAndNothingIsRecorded() throws {
        let fixture = try Fixture(probeDisabled: true)
        defer { fixture.tearDown() }
        fixture.controller.presentIfNeeded()
        #expect(fixture.presenter.presentCount == 0)
        #expect(fixture.controller.answeredVersion == 0)
    }

    @Test func whileClaudeIsHiddenItWaitsForALaterLaunch() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.claudeShown = false
        fixture.controller.presentIfNeeded()
        #expect(fixture.presenter.presentCount == 0)
        #expect(fixture.controller.answeredVersion == 0)
        fixture.claudeShown = true
        fixture.controller.presentIfNeeded()
        #expect(fixture.presenter.presentCount == 1)
    }
}

@MainActor
private final class FakePresenter: ClaudeUsageOnboardingPresenting {
    private(set) var presentCount = 0
    private(set) var closeCount = 0
    private var onAnswer: (@MainActor (ClaudeUsageOnboardingAnswer) -> Void)?

    func present(onAnswer: @escaping @MainActor (ClaudeUsageOnboardingAnswer) -> Void) {
        presentCount += 1
        self.onAnswer = onAnswer
    }

    func close() { closeCount += 1 }

    /// A button, or the user closing the window (which is "Not now").
    func answer(_ answer: ClaudeUsageOnboardingAnswer) { onAnswer?(answer) }
}

@MainActor
private final class Fixture {
    let defaults: UserDefaults
    let preferences: ClaudeAutomaticChecksPreferences
    let presenter = FakePresenter()
    var claudeShown = true
    private(set) var controller: ClaudeUsageOnboardingController!
    private let name: String

    /// `sharing` models the next launch: the same stored defaults, new objects.
    init(probeDisabled: Bool = false, sharing other: Fixture? = nil) throws {
        if let other {
            name = other.name
            defaults = other.defaults
        } else {
            name = "ClaudeUsageOnboarding.\(UUID().uuidString)"
            defaults = try #require(UserDefaults(suiteName: name))
        }
        preferences = ClaudeAutomaticChecksPreferences(defaults: defaults)
        controller = ClaudeUsageOnboardingController(
            defaults: defaults,
            preferences: preferences,
            presenter: presenter,
            probeDisabled: { probeDisabled },
            claudeShown: { [unowned self] in self.claudeShown }
        )
    }

    func tearDown() { defaults.removePersistentDomain(forName: name) }
}
