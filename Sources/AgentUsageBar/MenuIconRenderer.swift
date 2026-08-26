import AppKit

enum MenuIconRenderer {
    /// A tactile mouse with its right button pressed. Unlike a key-equivalent glyph, this keeps
    /// its shape and depth instead of being boxed as if it were a keyboard shortcut.
    static func rightClick() -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            let appearance = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua])
            let dark = appearance == .darkAqua
            let shellTop = NSColor(white: dark ? 0.78 : 0.96, alpha: 1)
            let shellBottom = NSColor(white: dark ? 0.42 : 0.68, alpha: 1)
            let outline = NSColor(white: dark ? 0.18 : 0.28, alpha: 0.95)
            let seam = NSColor(white: dark ? 0.2 : 0.32, alpha: 0.72)
            let pressed = NSColor(white: dark ? 0.3 : 0.57, alpha: 1)

            let bodyRect = NSRect(x: 3, y: 1.25, width: 10, height: 13.5)
            let body = NSBezierPath(roundedRect: bodyRect, xRadius: 5, yRadius: 5)

            NSGraphicsContext.current?.cgContext.setShadow(
                offset: CGSize(width: 0, height: -0.75),
                blur: 1.1,
                color: NSColor.black.withAlphaComponent(0.42).cgColor
            )
            NSGradient(starting: shellTop, ending: shellBottom)?.draw(in: body, angle: -90)
            NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

            NSGraphicsContext.current?.cgContext.saveGState()
            body.addClip()
            let rightButton = NSBezierPath(
                roundedRect: NSRect(x: 8, y: 8, width: 5, height: 6.75),
                xRadius: 2.5,
                yRadius: 2.5
            )
            pressed.setFill()
            rightButton.fill()
            NSColor.white.withAlphaComponent(dark ? 0.2 : 0.42).setStroke()
            let highlight = NSBezierPath()
            highlight.move(to: NSPoint(x: 4.5, y: 12.8))
            highlight.curve(
                to: NSPoint(x: 7.2, y: 14),
                controlPoint1: NSPoint(x: 5.2, y: 13.7),
                controlPoint2: NSPoint(x: 6.2, y: 14)
            )
            highlight.lineWidth = 0.7
            highlight.stroke()
            NSGraphicsContext.current?.cgContext.restoreGState()

            outline.setStroke()
            body.lineWidth = 0.8
            body.stroke()

            seam.setStroke()
            let buttonSeam = NSBezierPath()
            buttonSeam.move(to: NSPoint(x: 3.5, y: 8.2))
            buttonSeam.line(to: NSPoint(x: 12.5, y: 8.2))
            buttonSeam.move(to: NSPoint(x: 8, y: 8.2))
            buttonSeam.line(to: NSPoint(x: 8, y: 13.9))
            buttonSeam.lineWidth = 0.65
            buttonSeam.stroke()

            let wheel = NSBezierPath(roundedRect: NSRect(x: 7.35, y: 9.8, width: 1.3, height: 2.5), xRadius: 0.65, yRadius: 0.65)
            outline.withAlphaComponent(0.82).setFill()
            wheel.fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
