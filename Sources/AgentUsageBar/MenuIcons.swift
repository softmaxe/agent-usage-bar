import AppKit

/// Template images used by menu rows: 16pt leading icons and appropriately sized trailing hints.
enum MenuIcons {
    static let size = NSSize(width: 16, height: 16)

    /// Symbol names match CodexBar's menu actions so the rows read the same way.
    static func symbol(_ name: String) -> NSImage? {
        guard let glyph = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))
        else { return nil }
        return Self.centered(glyph)
    }

    /// Centres a glyph's ink in a fixed box, so every row's icon sits on the same axis.
    ///
    /// Centring the image bounds is not enough: a symbol carries its own uneven padding, so the
    /// gear and the cross land a point apart even when their boxes agree. This measures what the
    /// glyph actually paints and centres that. It only ever scales down, so a small icon stays
    /// small rather than being blown up to fill the box.
    private static func centered(_ glyph: NSImage) -> NSImage {
        Self.centered(glyph, in: Self.size)
    }

    private static func centered(_ glyph: NSImage, in targetSize: NSSize) -> NSImage {
        let ink = Self.inkBounds(of: glyph) ?? NSRect(origin: .zero, size: glyph.size)
        let scale = min(targetSize.width / ink.width, targetSize.height / ink.height, 1)
        let image = NSImage(size: targetSize, flipped: false) { rect in
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

    /// An outlined computer mouse for the action's leading icon.
    static func mouseOutline() -> NSImage {
        Self.mouseIcon(fillsRightButton: false)
    }

    private static func mouseIcon(fillsRightButton: Bool) -> NSImage {
        let drawn = NSImage(size: Self.size, flipped: false) { _ in
            let body = NSBezierPath(
                roundedRect: NSRect(x: 4, y: 1.4, width: 8, height: 13.2),
                xRadius: 4,
                yRadius: 4
            )
            body.lineWidth = 1.3
            NSColor.black.setStroke()
            body.stroke()

            if fillsRightButton {
                // Clipping to the body keeps the filled button inside the rounded outline.
                NSGraphicsContext.saveGraphicsState()
                body.addClip()
                NSColor.black.setFill()
                NSRect(x: 8.35, y: 8.1, width: 4, height: 7).fill()
                NSGraphicsContext.restoreGraphicsState()
            }

            // The wheel/divider remains visible in both variants; only the right-button fill is
            // different between the leading and trailing versions.
            let divider = NSBezierPath()
            divider.move(to: NSPoint(x: 8.35, y: 14.2))
            divider.line(to: NSPoint(x: 8.35, y: 8.1))
            divider.lineWidth = 1.3
            NSColor.black.setStroke()
            divider.stroke()
            return true
        }
        drawn.isTemplate = true
        return Self.centered(drawn)
    }

    /// A cursor arrow paired with a context-menu glyph, making the secondary-click gesture clear
    /// in the trailing shortcut column. The geometry follows the C treatment from the menu mockup.
    static func contextMenuCursor() -> NSImage {
        let iconSize = NSSize(width: 20, height: 20)
        let viewBox: CGFloat = 24
        let scale = iconSize.width / viewBox

        let drawn = NSImage(size: iconSize, flipped: false) { _ in
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: x * scale, y: iconSize.height - y * scale)
            }

            let cursor = NSBezierPath()
            cursor.move(to: point(4, 3.5))
            cursor.line(to: point(11.7, 11))
            cursor.line(to: point(8.2, 11.7))
            cursor.line(to: point(10.6, 16.1))
            cursor.line(to: point(8.4, 17.3))
            cursor.line(to: point(6, 12.9))
            cursor.line(to: point(4, 14.9))
            cursor.close()
            cursor.lineWidth = 1.65 * scale
            cursor.lineCapStyle = .round
            cursor.lineJoinStyle = .round
            NSColor.black.setStroke()
            cursor.stroke()

            for (start, end) in [
                (NSPoint(x: 14, y: 5), NSPoint(x: 20, y: 5)),
                (NSPoint(x: 14, y: 9), NSPoint(x: 20, y: 9)),
                (NSPoint(x: 15.5, y: 13), NSPoint(x: 20, y: 13))
            ] {
                let line = NSBezierPath()
                line.move(to: point(start.x, start.y))
                line.line(to: point(end.x, end.y))
                line.lineWidth = 1.65 * scale
                line.lineCapStyle = .round
                NSColor.black.setStroke()
                line.stroke()
            }
            return true
        }
        drawn.isTemplate = true
        return Self.centered(drawn, in: iconSize)
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
