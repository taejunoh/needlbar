import AppKit
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

@Suite("MenuBarStatusImageRendererTests", .serialized)
@MainActor
struct MenuBarStatusImageRendererTests {
    @Test(arguments: [CGFloat(1), 2]) func drawsTemplateImagesAtTheRequestedScale(_ scale: CGFloat) throws {
        let layout = try #require(MenuBarDashboardTwoLineLayout.fit(
            segments: [.init(.cpu, label: "CPU", primary: .init("100%", samples: ["100%", "—"]))],
            width: 240,
            height: 22,
            scale: scale
        ))
        let image = try #require(MenuBarDashboardImageRenderer.render(layout: layout, scale: scale))
        let representation = try #require(image.representations.compactMap { $0 as? NSBitmapImageRep }.first)

        #expect(image.isTemplate)
        #expect(representation.pixelsWide == Int(ceil(layout.size.width * scale)))
        #expect(representation.pixelsHigh == Int(ceil(layout.size.height * scale)))
        #expect(layout.runs.allSatisfy { $0.inkRect.minX >= 0 && $0.inkRect.minY >= 0 && $0.inkRect.maxX <= layout.size.width && $0.inkRect.maxY <= layout.size.height })

        let bytes = try #require(representation.bitmapData)
        let bottomRowHasInk = (0..<representation.pixelsWide).contains { bytes[$0 * 4 + 3] != 0 }
        let hasVisibleInk = (0..<(representation.pixelsWide * representation.pixelsHigh)).contains { bytes[$0 * 4 + 3] != 0 }
        #expect(!bottomRowHasInk)
        #expect(hasVisibleInk)
    }
}
