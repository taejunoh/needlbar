import AppKit

/// A small non-modal window, built like `SettingsWindowController`: an
/// `NSWindow`, with the app activated for it. Not `NSAlert.runModal`, which
/// would block the main run loop at launch. The content is plain AppKit so the
/// default button is a property a test can read.
@MainActor
final class ClaudeUsageOnboardingWindowController: NSObject, ClaudeUsageOnboardingPresenting, NSWindowDelegate {
    private static let textWidth: CGFloat = 420

    private let show: @MainActor (NSWindow) -> Void
    private(set) var window: NSWindow?
    private var onAnswer: (@MainActor (ClaudeUsageOnboardingAnswer) -> Void)?

    init(show: @escaping @MainActor (NSWindow) -> Void = { window in
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }) {
        self.show = show
    }

    func present(onAnswer: @escaping @MainActor (ClaudeUsageOnboardingAnswer) -> Void) {
        guard window == nil else { return }
        self.onAnswer = onAnswer
        let (content, notNow) = makeContent()
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: content.fittingSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Needlbar"
        window.contentView = content
        // With keyboard navigation on, AppKit focuses the first key view ("Turn on"),
        // and Space would opt in. Start on "Not now" instead.
        window.initialFirstResponder = notNow
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        show(window)
    }

    func close() {
        onAnswer = nil
        closeWindow()
    }

    private func makeContent() -> (view: NSView, notNow: NSButton) {
        let title = NSTextField(labelWithString: ClaudeUsageOnboardingCopy.title)
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let body = NSTextField(wrappingLabelWithString: ClaudeUsageOnboardingCopy.body)
        body.preferredMaxLayoutWidth = Self.textWidth

        let turnOn = NSButton(title: ClaudeUsageOnboardingCopy.turnOn, target: self, action: #selector(turnOnClicked))
        let notNow = NSButton(title: ClaudeUsageOnboardingCopy.notNow, target: self, action: #selector(notNowClicked))
        // The default button: the window can appear at login, and Return must not opt in.
        notNow.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, turnOn, notNow])
        buttons.orientation = .horizontal

        let stack = NSStackView(views: [title, body, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        NSLayoutConstraint.activate([
            body.widthAnchor.constraint(equalToConstant: Self.textWidth),
            buttons.widthAnchor.constraint(equalTo: body.widthAnchor),
        ])
        return (stack, notNow)
    }

    @objc private func turnOnClicked() { answer(.turnOn) }
    @objc private func notNowClicked() { answer(.notNow) }

    private func answer(_ answer: ClaudeUsageOnboardingAnswer) {
        let onAnswer = self.onAnswer
        self.onAnswer = nil
        closeWindow()
        onAnswer?(answer)
    }

    private func closeWindow() {
        guard let window else { return }
        self.window = nil
        window.delegate = nil
        window.close()
    }

    /// The close button. A close this controller started has already removed
    /// the delegate, so this is the user closing the window: "Not now".
    func windowWillClose(_ notification: Notification) {
        window = nil
        let onAnswer = self.onAnswer
        self.onAnswer = nil
        onAnswer?(.notNow)
    }
}
