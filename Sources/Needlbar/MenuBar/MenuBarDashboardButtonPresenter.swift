import AppKit
import Foundation

@MainActor
final class MenuBarDashboardButtonPresenter {
    struct Geometry: Equatable {
        let bounds: NSSize
        let budget: Double
        let scale: CGFloat
        let appearance: NSAppearance.Name
    }

    private struct Key: Equatable {
        let result: MenuBarDashboardRenderResult
        let height: CGFloat
        let budget: Double
        let scale: CGFloat
        let appearance: NSAppearance.Name

        init(result: MenuBarDashboardRenderResult, geometry: Geometry) {
            self.result = result
            height = geometry.bounds.height
            budget = geometry.budget
            scale = geometry.scale
            appearance = geometry.appearance
        }
    }

    private static let chrome = MenuBarDashboardTwoLineLayout.chrome
    private let button: NSButton
    private let readGeometry: () -> Geometry
    private let setLength: (CGFloat) -> Void
    private let imageValidationOverride: ((NSImage) -> Bool)?
    private let observations = ObservationBag()
    private var latestResult: MenuBarDashboardRenderResult?
    private var cachedKey: Key?
    private var applying = false

    init(
        button: NSButton,
        width: @escaping () -> Double,
        setLength: @escaping (CGFloat) -> Void,
        geometry: (() -> Geometry)? = nil,
        validateImage: ((NSImage) -> Bool)? = nil
    ) {
        self.button = button
        self.setLength = setLength
        imageValidationOverride = validateImage
        if let geometry {
            readGeometry = geometry
        } else {
            readGeometry = { [weak button] in
                let button = button
                return Geometry(
                    bounds: button?.bounds.size ?? .zero,
                    budget: width(),
                    scale: button?.window?.backingScaleFactor ?? 1,
                    appearance: button?.effectiveAppearance.name ?? .aqua
                )
            }
        }
        button.postsFrameChangedNotifications = true
        button.postsBoundsChangedNotifications = true
        observeGeometryChanges()
    }

    func present(_ result: MenuBarDashboardRenderResult) {
        latestResult = result
        refresh()
    }

    func refresh() {
        guard !applying, let result = latestResult else { return }
        let geometry = normalized(readGeometry())
        let key = Key(result: result, geometry: geometry)
        guard cachedKey != key else { return }

        applying = true
        defer { applying = false }
        button.toolTip = result.tooltip
        button.setAccessibilityElement(true)

        if let layout = MenuBarDashboardTwoLineLayout.fit(
            segments: result.segments,
            width: CGFloat(geometry.budget),
            height: geometry.bounds.height,
            scale: geometry.scale
        ), let image = MenuBarDashboardImageRenderer.render(layout: layout, scale: geometry.scale) {
            installImage(image, tooltip: result.tooltip)
            let length = layout.size.width + Self.chrome
            setLength(length)
            button.layoutSubtreeIfNeeded()
            if validate(image), imageValidationOverride?(image) ?? true {
                cachedKey = Key(result: result, geometry: normalized(readGeometry()))
                return
            }
        }

        if installText(result, geometry: geometry) {
            cachedKey = Key(result: result, geometry: normalized(readGeometry()))
            return
        }

        installIcon(tooltip: result.tooltip)
        cachedKey = Key(result: result, geometry: normalized(readGeometry()))
    }

    private func installImage(_ image: NSImage, tooltip: String) {
        button.attributedTitle = NSAttributedString()
        button.title = ""
        button.image = image
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.toolTip = tooltip
        button.setAccessibilityElement(true)
        button.setAccessibilityLabel(tooltip)
    }

    private func installText(_ result: MenuBarDashboardRenderResult, geometry: Geometry) -> Bool {
        let candidates = result.textCandidates.isEmpty
            ? (result.title.isEmpty ? [] : [result.title])
            : result.textCandidates
        let font = NSFont.menuFont(ofSize: 0)
        for candidate in candidates where !candidate.isEmpty {
            let textWidth = ceil((candidate as NSString).size(withAttributes: [.font: font]).width)
            let total = ceil(textWidth + Self.chrome)
            guard textWidth.isFinite,
                  total.isFinite,
                  geometry.budget >= 22,
                  total <= CGFloat(geometry.budget) else {
                continue
            }
            button.attributedTitle = NSAttributedString()
            button.image = nil
            button.imagePosition = .noImage
            button.imageScaling = .scaleNone
            button.font = font
            button.title = candidate
            setLength(total)
            button.layoutSubtreeIfNeeded()
            guard let cell = button.cell else { continue }
            let titleRect = cell.titleRect(forBounds: button.bounds)
            guard titleRect.width >= textWidth else { continue }
            button.toolTip = result.tooltip
            button.setAccessibilityElement(true)
            button.setAccessibilityLabel(result.tooltip)
            return true
        }
        return false
    }

    private func installIcon(tooltip: String) {
        button.attributedTitle = NSAttributedString()
        button.title = ""
        button.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Needlbar")
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = tooltip
        button.setAccessibilityElement(true)
        button.setAccessibilityLabel("Needlbar")
        setLength(22)
    }

    private func validate(_ image: NSImage) -> Bool {
        guard let cell = button.cell else { return false }
        let rect = cell.imageRect(forBounds: button.bounds)
        return rect.width >= image.size.width
            && rect.height >= image.size.height
            && button.bounds.contains(rect)
    }

    private func normalized(_ raw: Geometry) -> Geometry {
        let budget: Double
        if raw.budget == .infinity {
            budget = 240
        } else if raw.budget.isFinite {
            budget = min(240, max(0, raw.budget))
        } else {
            budget = 0
        }
        let scale = raw.scale.isFinite && raw.scale > 0 ? raw.scale : 1
        return .init(bounds: raw.bounds, budget: budget, scale: scale, appearance: raw.appearance)
    }

    private func observeGeometryChanges() {
        let center = NotificationCenter.default
        let refresh: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        observations.tokens.append(center.addObserver(
            forName: NSView.frameDidChangeNotification, object: button, queue: .main
        ) { _ in refresh() })
        observations.tokens.append(center.addObserver(
            forName: NSView.boundsDidChangeNotification, object: button, queue: .main
        ) { _ in refresh() })
        observations.tokens.append(center.addObserver(
            forName: NSWindow.didChangeBackingPropertiesNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor [weak self] in
                guard let self, window === self.button.window else { return }
                self.refresh()
            }
        })
        observations.tokens.append(center.addObserver(
            forName: NSWindow.didChangeScreenNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor [weak self] in
                guard let self, window === self.button.window else { return }
                self.refresh()
            }
        })
        observations.tokens.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in refresh() })
        if let application = NSApp {
            observations.appearance = application.observe(\.effectiveAppearance, options: [.new]) { _, _ in
                refresh()
            }
        }
    }
}

private final class ObservationBag {
    var tokens: [NSObjectProtocol] = []
    var appearance: NSKeyValueObservation?

    deinit {
        tokens.forEach(NotificationCenter.default.removeObserver)
        appearance?.invalidate()
    }
}
