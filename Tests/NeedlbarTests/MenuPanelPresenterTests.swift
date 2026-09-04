import AppKit
import Foundation
import Testing
@testable import NeedlbarApp

@Suite("MenuPanelPresenterTests")
@MainActor
struct MenuPanelPresenterTests {
    @Test func screenPointInsidePanelDoesNotRequestDismissal() {
        #expect(!MenuPanelEventPolicy.shouldDismiss(
            mouseScreenPoint: NSPoint(x: 150, y: 150),
            panelFrame: NSRect(x: 100, y: 100, width: 100, height: 100)
        ))
    }

    @Test func screenPointOutsidePanelRequestsDismissal() {
        #expect(MenuPanelEventPolicy.shouldDismiss(
            mouseScreenPoint: NSPoint(x: 99, y: 150),
            panelFrame: NSRect(x: 100, y: 100, width: 100, height: 100)
        ))
    }

    @Test func escapeKeyRequestsDismissal() {
        #expect(MenuPanelEventPolicy.shouldDismiss(keyCode: 53))
    }

    @Test func nonEscapeKeyDoesNotRequestDismissal() {
        #expect(!MenuPanelEventPolicy.shouldDismiss(keyCode: 36))
    }

    @Test func successfulPresentationUsesPlacementAndStartsOneMonitor() {
        let window = FakeMenuPanelWindow()
        let monitor = FakeMenuPanelDismissalMonitor()
        let presenter = AppKitMenuPanelPresenter(window: window, dismissalMonitor: monitor)
        let anchor = StatusItemPresentationAnchor(
            buttonFrameInScreen: NSRect(x: 531, y: 954.5, width: 39, height: 22),
            visibleFrameInScreen: NSRect(x: 0, y: 0, width: 1512, height: 949)
        )
        let contentViewController = FixedSizeViewController(size: NSSize(width: 300, height: 350))

        let presented = presenter.present(contentViewController, anchoredAt: anchor)

        #expect(presented)
        #expect(window.contentViewController != nil)
        #expect(window.frame == NSRect(x: 400.5, y: 599, width: 300, height: 350))
        #expect(window.setFrameCalls == [NSRect(x: 400.5, y: 599, width: 300, height: 350)])
        #expect(window.orderFrontRegardlessCallCount == 1)
        #expect(monitor.startCallCount == 1)
        #expect(presenter.isShown)
    }

    @Test func resizeChangesOnlyTheShownPanelFrame() throws {
        let window = FakeMenuPanelWindow()
        let monitor = FakeMenuPanelDismissalMonitor()
        let presenter = AppKitMenuPanelPresenter(window: window, dismissalMonitor: monitor)
        let anchor = testAnchor()
        var dismissCallbackCount = 0
        presenter.onDismiss = { dismissCallbackCount += 1 }

        #expect(presenter.present(
            FixedSizeViewController(size: NSSize(width: 340, height: 500)),
            anchoredAt: anchor
        ))
        let installedController = try #require(window.contentViewController)
        let currentDismiss = try #require(monitor.dismissHandlers.first)
        let expectedFrame = try #require(MenuPanelPlacement.frame(
            contentSize: NSSize(width: 340, height: 740),
            anchor: anchor
        ))

        #expect(presenter.resize(
            to: NSSize(width: 340, height: 740),
            anchoredAt: anchor
        ))
        #expect(window.frame == expectedFrame)
        #expect(window.contentViewController === installedController)
        #expect(window.orderFrontRegardlessCallCount == 1)
        #expect(monitor.startCallCount == 1)
        #expect(monitor.token.cancelCallCount == 0)
        #expect(presenter.isShown)

        currentDismiss()

        #expect(!presenter.isShown)
        #expect(dismissCallbackCount == 1)
        #expect(window.orderOutCallCount == 1)
        #expect(monitor.token.cancelCallCount == 1)
    }

    @Test func resizeRejectsHiddenOrUnplaceablePanelsWithoutMutation() {
        let window = FakeMenuPanelWindow()
        let monitor = FakeMenuPanelDismissalMonitor()
        let presenter = AppKitMenuPanelPresenter(window: window, dismissalMonitor: monitor)
        let anchor = testAnchor()

        #expect(!presenter.resize(to: NSSize(width: 340, height: 500), anchoredAt: anchor))
        #expect(window.setFrameCalls.isEmpty)

        #expect(presenter.present(
            FixedSizeViewController(size: NSSize(width: 340, height: 500)),
            anchoredAt: anchor
        ))
        let originalFrame = window.frame
        #expect(!presenter.resize(to: NSSize(width: 2_000, height: 2_000), anchoredAt: anchor))
        #expect(window.frame == originalFrame)
        #expect(window.setFrameCalls.count == 1)
    }

    @Test func repeatedPresentationCancelsPreviousTokenBeforeStartingNextSession() throws {
        let window = FakeMenuPanelWindow()
        let monitor = FakeMenuPanelDismissalMonitor()
        let presenter = AppKitMenuPanelPresenter(window: window, dismissalMonitor: monitor)

        #expect(presenter.present(FixedSizeViewController(size: NSSize(width: 300, height: 350)), anchoredAt: testAnchor()))
        let tokenA = try #require(monitor.tokens.first)

        #expect(presenter.present(FixedSizeViewController(size: NSSize(width: 300, height: 350)), anchoredAt: testAnchor()))
        let tokenB = try #require(monitor.tokens.dropFirst().first)

        #expect(monitor.startCallCount == 2)
        #expect(tokenA.cancelCallCount == 1)
        #expect(tokenB.cancelCallCount == 0)

        presenter.dismiss()

        #expect(tokenA.cancelCallCount == 1)
        #expect(tokenB.cancelCallCount == 1)
    }

    @Test func staleDismissalFromPriorPresentationCannotDismissNewPresentation() throws {
        let window = FakeMenuPanelWindow()
        let monitor = FakeMenuPanelDismissalMonitor()
        let presenter = AppKitMenuPanelPresenter(window: window, dismissalMonitor: monitor)
        var dismissCallbackCount = 0
        presenter.onDismiss = { dismissCallbackCount += 1 }
        let contentViewController = FixedSizeViewController(size: NSSize(width: 300, height: 350))

        #expect(presenter.present(contentViewController, anchoredAt: testAnchor()))
        let staleDismiss = try #require(monitor.dismissHandlers.first)
        #expect(presenter.present(contentViewController, anchoredAt: testAnchor()))
        let currentDismiss = try #require(monitor.dismissHandlers.dropFirst().first)

        staleDismiss()

        #expect(presenter.isShown)
        #expect(dismissCallbackCount == 0)
        #expect(window.orderOutCallCount == 0)

        currentDismiss()

        #expect(!presenter.isShown)
        #expect(dismissCallbackCount == 1)
        #expect(window.orderOutCallCount == 1)
    }

    @Test func repeatedDismissalCallsDismissOnceAndCancelsMonitorOnce() {
        let window = FakeMenuPanelWindow()
        let monitor = FakeMenuPanelDismissalMonitor()
        let presenter = AppKitMenuPanelPresenter(window: window, dismissalMonitor: monitor)
        var dismissCallbackCount = 0
        presenter.onDismiss = { dismissCallbackCount += 1 }
        let anchor = testAnchor()

        #expect(presenter.present(FixedSizeViewController(size: NSSize(width: 300, height: 350)), anchoredAt: anchor))
        presenter.dismiss()
        presenter.dismiss()

        #expect(dismissCallbackCount == 1)
        #expect(monitor.token.cancelCallCount == 1)
        #expect(window.orderOutCallCount == 1)
        #expect(!presenter.isShown)
    }

    @Test func failedFittingSizePlacementDoesNotShowOrStartMonitoring() {
        let window = FakeMenuPanelWindow()
        let monitor = FakeMenuPanelDismissalMonitor()
        let presenter = AppKitMenuPanelPresenter(window: window, dismissalMonitor: monitor)
        let oversized = FixedSizeViewController(size: NSSize(width: 2_000, height: 2_000))

        let presented = presenter.present(oversized, anchoredAt: testAnchor())

        #expect(!presented)
        #expect(window.orderFrontRegardlessCallCount == 0)
        #expect(window.setFrameCalls.isEmpty)
        #expect(monitor.startCallCount == 0)
        #expect(!presenter.isShown)
    }

    private func testAnchor() -> StatusItemPresentationAnchor {
        StatusItemPresentationAnchor(
            buttonFrameInScreen: NSRect(x: 531, y: 954.5, width: 39, height: 22),
            visibleFrameInScreen: NSRect(x: 0, y: 0, width: 1512, height: 949)
        )
    }
}

@MainActor
private final class FixedSizeViewController: NSViewController {
    init(size: NSSize) {
        super.init(nibName: nil, bundle: nil)
        view = FixedSizeView(size: size)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class FixedSizeView: NSView {
    private let size: NSSize

    init(size: NSSize) {
        self.size = size
        super.init(frame: NSRect(origin: .zero, size: size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize { size }
}

@MainActor
private final class FakeMenuPanelWindow: MenuPanelWindowing {
    var frame: NSRect = .zero
    var contentViewController: NSViewController?
    private(set) var setFrameCalls: [NSRect] = []
    private(set) var orderFrontRegardlessCallCount = 0
    private(set) var orderOutCallCount = 0

    func setFrame(_ frame: NSRect, display: Bool) {
        self.frame = frame
        setFrameCalls.append(frame)
    }

    func orderFrontRegardless() {
        orderFrontRegardlessCallCount += 1
    }

    func orderOut(_ sender: Any?) {
        orderOutCallCount += 1
    }
}

@MainActor
private final class FakeMenuPanelDismissalMonitor: MenuPanelDismissalMonitoring {
    private(set) var tokens: [FakeMenuPanelDismissalMonitoringToken] = []
    private(set) var startCallCount = 0
    private(set) var panelFrameProviders: [@MainActor () -> NSRect] = []
    private(set) var dismissHandlers: [@MainActor () -> Void] = []

    var token: FakeMenuPanelDismissalMonitoringToken {
        tokens[0]
    }

    func start(
        panelFrame: @escaping @MainActor () -> NSRect,
        dismiss: @escaping @MainActor () -> Void
    ) -> any MenuPanelDismissalMonitoringToken {
        startCallCount += 1
        let token = FakeMenuPanelDismissalMonitoringToken()
        tokens.append(token)
        panelFrameProviders.append(panelFrame)
        dismissHandlers.append(dismiss)
        return token
    }
}

@MainActor
private final class FakeMenuPanelDismissalMonitoringToken: MenuPanelDismissalMonitoringToken {
    private(set) var cancelCallCount = 0

    func cancel() {
        cancelCallCount += 1
    }
}
