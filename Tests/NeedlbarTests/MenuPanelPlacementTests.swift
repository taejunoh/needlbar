import AppKit
import Foundation
import Testing
@testable import NeedlbarApp

@Suite("MenuPanelPlacementTests")
struct MenuPanelPlacementTests {
    @Test func presentationAnchorsCompareByFrames() {
        let anchor = StatusItemPresentationAnchor(
            buttonFrameInScreen: NSRect(x: 531, y: 954.5, width: 39, height: 22),
            visibleFrameInScreen: NSRect(x: 0, y: 0, width: 1512, height: 949)
        )

        #expect(anchor == StatusItemPresentationAnchor(
            buttonFrameInScreen: NSRect(x: 531, y: 954.5, width: 39, height: 22),
            visibleFrameInScreen: NSRect(x: 0, y: 0, width: 1512, height: 949)
        ))
        #expect(anchor != StatusItemPresentationAnchor(
            buttonFrameInScreen: NSRect(x: 532, y: 954.5, width: 39, height: 22),
            visibleFrameInScreen: NSRect(x: 0, y: 0, width: 1512, height: 949)
        ))
    }

    @Test func measuredStatusButtonPlacesTheWholePanelBelowTheMenuBar() throws {
        let anchor = StatusItemPresentationAnchor(
            buttonFrameInScreen: NSRect(x: 531, y: 954.5, width: 39, height: 22),
            visibleFrameInScreen: NSRect(x: 0, y: 0, width: 1512, height: 949)
        )
        let frame = try #require(MenuPanelPlacement.frame(
            contentSize: NSSize(width: 300, height: 350),
            anchor: anchor
        ))
        #expect(frame == NSRect(x: 400.5, y: 599, width: 300, height: 350))
        #expect(frame.maxY == 949)
        #expect(frame.midX == anchor.buttonFrameInScreen.midX)
    }

    @Test func panelClampsToTheVisibleFrameInsetOnTheLeft() throws {
        let anchor = StatusItemPresentationAnchor(
            buttonFrameInScreen: NSRect(x: -40, y: 954.5, width: 39, height: 22),
            visibleFrameInScreen: NSRect(x: 0, y: 0, width: 1512, height: 949)
        )
        let frame = try #require(MenuPanelPlacement.frame(
            contentSize: NSSize(width: 300, height: 350),
            anchor: anchor
        ))

        #expect(frame == NSRect(x: 6, y: 599, width: 300, height: 350))
    }

    @Test func panelClampsToTheVisibleFrameInsetOnTheRight() throws {
        let anchor = StatusItemPresentationAnchor(
            buttonFrameInScreen: NSRect(x: 1490, y: 954.5, width: 39, height: 22),
            visibleFrameInScreen: NSRect(x: 0, y: 0, width: 1512, height: 949)
        )
        let frame = try #require(MenuPanelPlacement.frame(
            contentSize: NSSize(width: 300, height: 350),
            anchor: anchor
        ))

        #expect(frame == NSRect(x: 1206, y: 599, width: 300, height: 350))
    }

    @Test func panelClampsToTheTopOfTheVisibleFrameWhenTheDockReducesSpace() throws {
        let anchor = StatusItemPresentationAnchor(
            buttonFrameInScreen: NSRect(x: 531, y: 180, width: 39, height: 22),
            visibleFrameInScreen: NSRect(x: 0, y: 40, width: 1512, height: 100)
        )
        let frame = try #require(MenuPanelPlacement.frame(
            contentSize: NSSize(width: 300, height: 60),
            anchor: anchor
        ))

        #expect(frame == NSRect(x: 400.5, y: 80, width: 300, height: 60))
        #expect(frame.maxY == anchor.visibleFrameInScreen.maxY)
    }

    @Test func panelClampsToTheVisibleFrameInsetAtTheBottom() throws {
        let anchor = StatusItemPresentationAnchor(
            buttonFrameInScreen: NSRect(x: 531, y: 30, width: 39, height: 22),
            visibleFrameInScreen: NSRect(x: 0, y: 0, width: 1512, height: 949)
        )
        let frame = try #require(MenuPanelPlacement.frame(
            contentSize: NSSize(width: 300, height: 350),
            anchor: anchor
        ))

        #expect(frame == NSRect(x: 400.5, y: 6, width: 300, height: 350))
        #expect(frame.minY == anchor.visibleFrameInScreen.minY + 6)
    }

    @Test func panelUsesNegativeCoordinatesOnASecondaryDisplay() throws {
        let anchor = StatusItemPresentationAnchor(
            buttonFrameInScreen: NSRect(x: -420, y: 880, width: 40, height: 22),
            visibleFrameInScreen: NSRect(x: -1440, y: 0, width: 1440, height: 900)
        )
        let frame = try #require(MenuPanelPlacement.frame(
            contentSize: NSSize(width: 300, height: 350),
            anchor: anchor
        ))

        #expect(frame == NSRect(x: -550, y: 530, width: 300, height: 350))
    }

    @Test func contentLargerThanTheVisibleFrameReturnsNil() {
        let anchor = StatusItemPresentationAnchor(
            buttonFrameInScreen: NSRect(x: 531, y: 954.5, width: 39, height: 22),
            visibleFrameInScreen: NSRect(x: 0, y: 0, width: 1512, height: 949)
        )

        #expect(MenuPanelPlacement.frame(
            contentSize: NSSize(width: 1501, height: 350),
            anchor: anchor
        ) == nil)
        #expect(MenuPanelPlacement.frame(
            contentSize: NSSize(width: 300, height: 944),
            anchor: anchor
        ) == nil)
    }

    @Test func nonPositiveContentSizeReturnsNil() {
        let anchor = StatusItemPresentationAnchor(
            buttonFrameInScreen: NSRect(x: 531, y: 954.5, width: 39, height: 22),
            visibleFrameInScreen: NSRect(x: 0, y: 0, width: 1512, height: 949)
        )

        #expect(MenuPanelPlacement.frame(contentSize: NSSize(width: 0, height: 350), anchor: anchor) == nil)
        #expect(MenuPanelPlacement.frame(contentSize: NSSize(width: 300, height: 0), anchor: anchor) == nil)
    }

    @Test func dashboardSizingUsesApprovedWidthAndMeasuredHeight() {
        #expect(SystemDashboardPanelSizing.width == 312)
        #expect(SystemDashboardPanelSizing.height(
            naturalContentHeight: 742,
            visibleScreenHeight: 1_000
        ) == 742)
    }

    @Test func dashboardSizingClampsToMinimumAndScreenAllowance() {
        #expect(SystemDashboardPanelSizing.height(
            naturalContentHeight: 120,
            visibleScreenHeight: 1_000
        ) == 180)
        #expect(SystemDashboardPanelSizing.height(
            naturalContentHeight: 900,
            visibleScreenHeight: 824
        ) == 800)
        #expect(SystemDashboardPanelSizing.height(
            naturalContentHeight: 400,
            visibleScreenHeight: 150
        ) == 126)
    }

    @Test func dashboardSizingFallsBackForEveryInvalidMeasurement() {
        for measurement in [CGFloat?.none, 0, -1, .nan, .infinity, -.infinity] {
            #expect(SystemDashboardPanelSizing.height(
                naturalContentHeight: measurement,
                visibleScreenHeight: 1_000
            ) == 680)
        }
    }

    @Test func dashboardSizingRejectsInvalidScreenAllowanceAndUsesResizeEpsilon() {
        #expect(SystemDashboardPanelSizing.height(
            naturalContentHeight: 400,
            visibleScreenHeight: .nan
        ) == 0)
        #expect(!SystemDashboardPanelSizing.shouldResize(current: 700, proposed: 700.49))
        #expect(SystemDashboardPanelSizing.shouldResize(current: 700, proposed: 700.5))
    }
}
