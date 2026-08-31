import AppKit

public struct StatusItemPresentationAnchor: Equatable {
    public let buttonFrameInScreen: NSRect
    public let visibleFrameInScreen: NSRect

    public init(buttonFrameInScreen: NSRect, visibleFrameInScreen: NSRect) {
        self.buttonFrameInScreen = buttonFrameInScreen
        self.visibleFrameInScreen = visibleFrameInScreen
    }
}

public enum MenuPanelPlacement {
    private static let screenMargin: CGFloat = 6

    public static func frame(
        contentSize: NSSize,
        anchor: StatusItemPresentationAnchor
    ) -> NSRect? {
        let visibleFrame = anchor.visibleFrameInScreen
        guard contentSize.width > 0,
              contentSize.height > 0,
              contentSize.width <= visibleFrame.width - (screenMargin * 2),
              contentSize.height <= visibleFrame.height - screenMargin else {
            return nil
        }

        let centeredX = anchor.buttonFrameInScreen.midX - (contentSize.width / 2)
        let minimumX = visibleFrame.minX + screenMargin
        let maximumX = visibleFrame.maxX - screenMargin - contentSize.width
        let x = min(max(centeredX, minimumX), maximumX)

        let desiredTop = min(anchor.buttonFrameInScreen.minY, visibleFrame.maxY)
        let desiredY = desiredTop - contentSize.height
        let minimumY = visibleFrame.minY + screenMargin
        let maximumY = visibleFrame.maxY - contentSize.height
        let y = min(max(desiredY, minimumY), maximumY)

        return NSRect(origin: NSPoint(x: x, y: y), size: contentSize)
    }
}
