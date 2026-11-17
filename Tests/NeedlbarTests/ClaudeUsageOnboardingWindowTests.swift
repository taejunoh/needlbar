import AppKit
import Foundation
import Testing
@testable import NeedlbarApp

// The first-run window itself. It is built but never put on screen: the
// controller's `show` step is replaced, so nothing is ordered front or activated.
@Suite("ClaudeUsageOnboardingWindow", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct ClaudeUsageOnboardingWindowTests {
    @Test func theWindowOffersTurnOnAndNotNowWithNotNowAsTheDefaultButton() throws {
        _ = NSApplication.shared
        var answers: [ClaudeUsageOnboardingAnswer] = []
        let windows = ClaudeUsageOnboardingWindowController(show: { _ in })
        windows.present { answers.append($0) }
        let window = try #require(windows.window)
        let content = try #require(window.contentView)
        let buttons = Self.buttons(in: content)
        #expect(buttons.map(\.title) == ["Turn on", "Not now"])
        #expect(buttons.filter { $0.keyEquivalent == "\r" }.map(\.title) == ["Not now"], "Return must not opt in")
        #expect(Self.labels(in: content) == [ClaudeUsageOnboardingCopy.title, ClaudeUsageOnboardingCopy.body])
        #expect(content.fittingSize.width == 460)

        try #require(buttons.first { $0.title == "Turn on" }).performClick(nil)
        #expect(answers == [.turnOn])
        #expect(windows.window == nil, "a button closes the window")

        windows.present { answers.append($0) }
        let again = try #require(windows.window?.contentView)
        try #require(Self.buttons(in: again).first { $0.title == "Not now" }).performClick(nil)
        #expect(answers == [.turnOn, .notNow])
    }

    @Test func theWindowReportsAButtonOnceAndAUserCloseAsNotNow() throws {
        _ = NSApplication.shared
        var answers: [ClaudeUsageOnboardingAnswer] = []
        var shown = 0
        let windows = ClaudeUsageOnboardingWindowController(show: { _ in shown += 1 })
        windows.present { answers.append($0) }
        windows.present { answers.append($0) }
        #expect(shown == 1)
        let window = try #require(windows.window)
        #expect(window.styleMask.contains(.closable))
        #expect(!window.isReleasedWhenClosed)

        // The user closes the window.
        window.close()
        #expect(answers == [.notNow])
        #expect(windows.window == nil)

        // Closed by the app after an answer elsewhere: no answer is reported.
        windows.present { answers.append($0) }
        windows.close()
        #expect(answers == [.notNow])
        #expect(windows.window == nil)
        #expect(shown == 2)
    }

    private static func buttons(in view: NSView) -> [NSButton] {
        if let button = view as? NSButton { return [button] }
        return view.subviews.flatMap { buttons(in: $0) }
    }

    private static func labels(in view: NSView) -> [String] {
        if let field = view as? NSTextField { return [field.stringValue] }
        return view.subviews.flatMap { labels(in: $0) }
    }
}
