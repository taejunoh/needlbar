import Combine
import Foundation

/// The first-run question about automatic Claude checks (spec 2026-11-16 §5).
enum ClaudeUsageOnboarding {
    static let answeredVersionKey = "needlbar.onboarding.claudeUsage.answeredVersion"
    /// The window shows while the stored version is below this, which covers a
    /// new install and an update alike.
    static let currentVersion = 1

    /// Not shown on a smoke run, which sets the probe switch, so it neither
    /// flashes the window nor uses up the developer's answer. Not shown while
    /// Claude is hidden either: nothing is recorded and it waits for a later launch.
    static func shouldShow(answeredVersion: Int, probeDisabled: Bool, claudeShown: Bool) -> Bool {
        !probeDisabled && claudeShown && answeredVersion < currentVersion
    }
}

/// The window's copy. It does not say whether a run uses quota or sends a model
/// request; neither is verified.
enum ClaudeUsageOnboardingCopy {
    static let title = "Check Claude quota automatically?"
    static let body = "Needlbar can run /usage in the Claude Code you installed, under your own sign-in: "
        + "when Needlbar starts, about every 15 minutes while it is running, when a limit resets, and sooner "
        + "after a failed check. Needlbar does not read your Claude sign-in. If you leave this off, it runs "
        + "only when you click Check now. You can change this in Settings."
    static let turnOn = "Turn on"
    static let notNow = "Not now"
}

enum ClaudeUsageOnboardingAnswer: Equatable, Sendable {
    case turnOn
    case notNow
}

@MainActor
protocol ClaudeUsageOnboardingPresenting: AnyObject {
    /// Shows the window. `onAnswer` is called at most once: for a button, or for
    /// the user closing the window, which counts as "Not now".
    func present(onAnswer: @escaping @MainActor (ClaudeUsageOnboardingAnswer) -> Void)
    /// Closes the window without calling `onAnswer`.
    func close()
}

/// Shows the question once and records that it was answered. The answer is
/// recorded when the user answers or closes the window, not when the window
/// appears, so a crash or a quit before answering shows it again next launch.
@MainActor
final class ClaudeUsageOnboardingController {
    private let defaults: UserDefaults
    private let preferences: ClaudeAutomaticChecksPreferences
    private let presenter: any ClaudeUsageOnboardingPresenting
    private let probeDisabled: @MainActor () -> Bool
    private let claudeShown: @MainActor () -> Bool
    private var isPresented = false
    private var preferenceObservation: AnyCancellable?

    init(
        defaults: UserDefaults,
        preferences: ClaudeAutomaticChecksPreferences,
        presenter: any ClaudeUsageOnboardingPresenting,
        probeDisabled: @escaping @MainActor () -> Bool,
        claudeShown: @escaping @MainActor () -> Bool
    ) {
        self.defaults = defaults
        self.preferences = preferences
        self.presenter = presenter
        self.probeDisabled = probeDisabled
        self.claudeShown = claudeShown
    }

    /// A missing value reads as 0.
    var answeredVersion: Int {
        defaults.integer(forKey: ClaudeUsageOnboarding.answeredVersionKey)
    }

    func presentIfNeeded() {
        // Already turned on in Settings during a launch when the window waited:
        // nothing to ask, so the answer is recorded without showing it.
        if !isPresented, preferences.isEnabled, !probeDisabled(),
           answeredVersion < ClaudeUsageOnboarding.currentVersion {
            defaults.set(ClaudeUsageOnboarding.currentVersion, forKey: ClaudeUsageOnboarding.answeredVersionKey)
            return
        }
        guard !isPresented, ClaudeUsageOnboarding.shouldShow(
            answeredVersion: answeredVersion, probeDisabled: probeDisabled(), claudeShown: claudeShown()
        ) else { return }
        isPresented = true
        // Answered elsewhere: turned on from Settings or the Claude row while the
        // window is open. `@Published` reports a change before it is stored, so
        // the value is read on the next main-actor turn.
        preferenceObservation = preferences.$isEnabled.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.preferenceDidChange() }
        }
        presenter.present { [weak self] answer in self?.answered(answer) }
    }

    private func answered(_ answer: ClaudeUsageOnboardingAnswer) {
        guard isPresented else { return }
        recordAnswered()
        if answer == .turnOn { preferences.setEnabled(true) }
    }

    private func preferenceDidChange() {
        guard isPresented, preferences.isEnabled else { return }
        recordAnswered()
        presenter.close()
    }

    private func recordAnswered() {
        isPresented = false
        preferenceObservation = nil
        defaults.set(ClaudeUsageOnboarding.currentVersion, forKey: ClaudeUsageOnboarding.answeredVersionKey)
    }
}
