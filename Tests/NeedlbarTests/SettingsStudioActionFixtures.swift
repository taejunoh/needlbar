import Foundation
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore
@testable import NeedlbarSettingsStudioReviewSupport

@Test func settingsStudioReviewRequiresExactOptInArgument() {
    #expect(!SettingsStudioReviewLaunch.isOptedIn(arguments: ["NeedlbarSettingsStudioReview"]))
    #expect(!SettingsStudioReviewLaunch.isOptedIn(arguments: ["NeedlbarSettingsStudioReview", "--unknown"]))
    #expect(SettingsStudioReviewLaunch.isOptedIn(arguments: ["NeedlbarSettingsStudioReview", "--settings-studio-review"]))
    #expect(!SettingsStudioReviewLaunch.isOptedIn(arguments: ["NeedlbarSettingsStudioReview", "--settings-studio-review", "extra"]))
}

@MainActor
@Test func settingsStudioActionFixturesExerciseRealStatePropagation() async throws {
    let actions = settingsStudioReviewActions(delay: .zero)
    #expect(actions.loginState(for: .claude) == .idle)
    #expect(actions.exportState == .idle)
    for provider in [ProviderID.claude, .codex] {
        actions.connect(provider)
        #expect(actions.loginState(for: provider) == .launching)
        try await waitForFixture { actions.loginState(for: provider) == .connected }
        actions.connect(provider)
        try await waitForFixture { actions.loginState(for: provider) == .failed(.providerRejected) }
    }
    actions.exportSnapshot()
    #expect(actions.isExporting)
    try await waitForFixture { actions.exportState == .exported }
    #expect(!actions.isExporting)
    actions.exportSnapshot()
    #expect(actions.isExporting)
    try await waitForFixture { actions.exportState == .failed }
    #expect(!actions.isExporting)
}

@MainActor
private func waitForFixture(_ condition: () -> Bool) async throws {
    // Other native layout tests can occupy MainActor for several seconds.
    // Bound observation attempts, not wall time spent waiting behind that work.
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    try #require(condition())
}
