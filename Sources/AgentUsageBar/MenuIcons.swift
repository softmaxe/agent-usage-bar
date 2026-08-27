import AppKit

/// The 16pt template images that lead each menu row.
enum MenuIcons {
    static let size = NSSize(width: 16, height: 16)

    /// Symbol names match CodexBar's menu actions so the rows read the same way.
    static func symbol(_ name: String) -> NSImage? {
        guard let glyph = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))
        else { return nil }
        return Self.centered(glyph)
    }

    /// Centres a glyph's ink in one fixed box, so every row's icon sits on the same axis.
    ///
    /// Centring the image bounds is not enough: a symbol carries its own uneven padding, so the
    /// gear and the cross land a point apart even when their boxes agree. This measures what the
    /// glyph actually paints and centres that. It only ever scales down, so a small icon stays
    /// small rather than being blown up to fill the box.
    private static func centered(_ glyph: NSImage) -> NSImage {
        let ink = Self.inkBounds(of: glyph) ?? NSRect(origin: .zero, size: glyph.size)
        let scale = min(Self.size.width / ink.width, Self.size.height / ink.height, 1)
        let image = NSImage(size: Self.size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.translateBy(x: rect.midX, y: rect.midY)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -ink.midX, y: -ink.midY)
            glyph.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            context.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// What the glyph paints, in its own coordinate space, found by rendering it once and walking
    /// the alpha channel.
    private static func inkBounds(of glyph: NSImage) -> NSRect? {
        let sampleScale = 2
        let width = Int(glyph.size.width.rounded()) * sampleScale
        let height = Int(glyph.size.height.rounded()) * sampleScale
        guard width > 0, height > 0, let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = glyph.size

        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = context
            glyph.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        }
        NSGraphicsContext.restoreGraphicsState()

        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0 ..< height {
            for x in 0 ..< width where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        let unit = CGFloat(sampleScale)
        return NSRect(
            x: CGFloat(minX) / unit,
            // Bitmap rows run top-down; the image's own space runs bottom-up.
            y: CGFloat(height - 1 - maxY) / unit,
            width: CGFloat(maxX - minX + 1) / unit,
            height: CGFloat(maxY - minY + 1) / unit
        )
    }

    /// `computermouse` with its right button filled in, because right-clicking the status item is
    /// the gesture the row names. SF Symbols has no such variant, so the shape is drawn here: an
    /// outlined body with the top-right quadrant painted inside it.
    static func rightButtonMouse() -> NSImage {
        let drawn = NSImage(size: Self.size, flipped: false) { _ in
            let body = NSBezierPath(
                roundedRect: NSRect(x: 4, y: 1.4, width: 8, height: 13.2),
                xRadius: 4,
                yRadius: 4
            )
            body.lineWidth = 1.3
            NSColor.black.setStroke()
            body.stroke()

            // Clipping to the body keeps the filled button inside the rounded outline, which is
            // also what draws the divider down the middle of the upper half.
            NSGraphicsContext.saveGraphicsState()
            body.addClip()
            NSColor.black.setFill()
            NSRect(x: 8.35, y: 8.1, width: 4, height: 7).fill()
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        drawn.isTemplate = true
        return Self.centered(drawn)
    }

    /// Repaints a template image in one colour, since a hand-drawn menu row tints its own icon
    /// instead of letting AppKit do it.
    static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        let copy = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        copy.isTemplate = false
        return copy
    }
}
