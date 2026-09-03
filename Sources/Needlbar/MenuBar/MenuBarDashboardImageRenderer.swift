import AppKit
import CoreText

@MainActor
enum MenuBarDashboardImageRenderer {
    static func render(layout: MenuBarDashboardTwoLineLayout, scale: CGFloat) -> NSImage? {
        guard scale.isFinite,
              scale > 0,
              layout.size.width.isFinite,
              layout.size.height.isFinite,
              layout.size.width > 0,
              layout.size.height > 0 else {
            return nil
        }
        let pixelWidth = ceil(layout.size.width * scale)
        let pixelHeight = ceil(layout.size.height * scale)
        guard pixelWidth.isFinite,
              pixelHeight.isFinite,
              pixelWidth > 0,
              pixelHeight > 0,
              pixelWidth <= 4096,
              pixelHeight <= 4096 else {
            return nil
        }
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelWidth),
            pixelsHigh: Int(pixelHeight),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: representation) else {
            return nil
        }
        representation.size = layout.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let graphics = context.cgContext
        graphics.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        graphics.scaleBy(x: scale, y: scale)
        graphics.textMatrix = .identity
        for run in layout.runs {
            graphics.textPosition = run.baseline
            CTLineDraw(MenuBarGlyphs.line(run.text, role: run.role), graphics)
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: layout.size)
        image.addRepresentation(representation)
        image.isTemplate = true
        return image
    }
}
