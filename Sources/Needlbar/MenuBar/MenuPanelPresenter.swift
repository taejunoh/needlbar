import AppKit

@MainActor
public protocol MenuPanelPresenting: AnyObject {
    var isShown: Bool { get }
    var onDismiss: (@MainActor () -> Void)? { get set }

    @discardableResult
    func present(
        _ contentViewController: NSViewController,
        anchoredAt anchor: StatusItemPresentationAnchor
    ) -> Bool

    @discardableResult
    func resize(to contentSize: NSSize, anchoredAt anchor: StatusItemPresentationAnchor) -> Bool

    func dismiss()
}

@MainActor
public protocol MenuPanelWindowing: AnyObject {
    var frame: NSRect { get }
    var contentViewController: NSViewController? { get set }
    func setFrame(_ frame: NSRect, display: Bool)
    func orderFrontRegardless()
    func orderOut(_ sender: Any?)
}

@MainActor
public protocol MenuPanelDismissalMonitoringToken: AnyObject {
    func cancel()
}

@MainActor
public protocol MenuPanelDismissalMonitoring: AnyObject {
    func start(
        panelFrame: @escaping @MainActor () -> NSRect,
        dismiss: @escaping @MainActor () -> Void
    ) -> any MenuPanelDismissalMonitoringToken
}

public enum MenuPanelEventPolicy {
    public static func shouldDismiss(mouseScreenPoint: NSPoint, panelFrame: NSRect) -> Bool {
        !panelFrame.contains(mouseScreenPoint)
    }

    public static func shouldDismiss(keyCode: UInt16) -> Bool {
        keyCode == 53
    }
}

@MainActor
public final class AppKitMenuPanelPresenter: MenuPanelPresenting {
    private let window: any MenuPanelWindowing
    private let dismissalMonitor: any MenuPanelDismissalMonitoring
    private var dismissalMonitoringToken: (any MenuPanelDismissalMonitoringToken)?
    private var shown = false
    private var presentationGeneration: UInt = 0

    public var isShown: Bool { shown }
    public var onDismiss: (@MainActor () -> Void)?

    public convenience init() {
        self.init(window: AppKitMenuPanelWindow(), dismissalMonitor: AppKitMenuPanelDismissalMonitor())
    }

    init(
        window: any MenuPanelWindowing,
        dismissalMonitor: any MenuPanelDismissalMonitoring
    ) {
        self.window = window
        self.dismissalMonitor = dismissalMonitor
        if let panel = window as? AppKitMenuPanelWindow {
            panel.onCancelOperation = { [weak self] in self?.dismiss() }
        }
    }

    @discardableResult
    public func present(
        _ contentViewController: NSViewController,
        anchoredAt anchor: StatusItemPresentationAnchor
    ) -> Bool {
        let wrappedViewController = MenuPanelContentViewController(contentViewController: contentViewController)
        wrappedViewController.view.layoutSubtreeIfNeeded()
        let contentSize = wrappedViewController.view.fittingSize
        guard let frame = MenuPanelPlacement.frame(contentSize: contentSize, anchor: anchor) else {
            return false
        }

        presentationGeneration += 1
        let generation = presentationGeneration
        dismissalMonitoringToken?.cancel()
        dismissalMonitoringToken = nil
        window.contentViewController = wrappedViewController
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        shown = true
        dismissalMonitoringToken = dismissalMonitor.start(
            panelFrame: { [weak self] in self?.window.frame ?? .zero },
            dismiss: { [weak self] in
                guard let self, self.presentationGeneration == generation else { return }
                self.dismiss()
            }
        )
        return true
    }

    @discardableResult
    public func resize(to contentSize: NSSize, anchoredAt anchor: StatusItemPresentationAnchor) -> Bool {
        guard shown,
              let frame = MenuPanelPlacement.frame(contentSize: contentSize, anchor: anchor)
        else { return false }
        window.setFrame(frame, display: true)
        return true
    }

    public func dismiss() {
        guard shown else { return }
        presentationGeneration += 1
        shown = false
        let token = dismissalMonitoringToken
        dismissalMonitoringToken = nil
        token?.cancel()
        window.orderOut(nil)
        onDismiss?()
    }

}

@MainActor
private final class AppKitMenuPanelWindow: NSPanel, MenuPanelWindowing {
    var onCancelOperation: (@MainActor () -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = .popUpMenu
        collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancelOperation?()
    }
}

@MainActor
private final class MenuPanelContentViewController: NSViewController {
    init(contentViewController: NSViewController) {
        super.init(nibName: nil, bundle: nil)
        addChild(contentViewController)

        let effectView = NSVisualEffectView()
        effectView.material = .popover
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 18
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 1
        effectView.layer?.borderColor = NSColor.separatorColor.cgColor

        let hostedView = contentViewController.view
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: effectView.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])
        view = effectView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
public final class AppKitMenuPanelDismissalMonitor: MenuPanelDismissalMonitoring {
    public init() {}

    public func start(
        panelFrame: @escaping @MainActor () -> NSRect,
        dismiss: @escaping @MainActor () -> Void
    ) -> any MenuPanelDismissalMonitoringToken {
        let localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { event in
            if event.type == .keyDown, MenuPanelEventPolicy.shouldDismiss(keyCode: event.keyCode) {
                Task { @MainActor in dismiss() }
                return nil
            }

            let isMouseDown = event.type == .leftMouseDown
                || event.type == .rightMouseDown
                || event.type == .otherMouseDown
            if isMouseDown, MenuPanelEventPolicy.shouldDismiss(
                mouseScreenPoint: NSEvent.mouseLocation,
                panelFrame: panelFrame()
            ) {
                Task { @MainActor in dismiss() }
            }
            return event
        }

        let observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in dismiss() }
        }
        return Token(localMonitor: localMonitor, observer: observer)
    }

    @MainActor
    private final class Token: MenuPanelDismissalMonitoringToken {
        private var localMonitor: Any?
        private var observer: NSObjectProtocol?

        init(localMonitor: Any?, observer: NSObjectProtocol) {
            self.localMonitor = localMonitor
            self.observer = observer
        }

        func cancel() {
            guard localMonitor != nil || observer != nil else { return }
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
                self.localMonitor = nil
            }
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
        }
    }
}
