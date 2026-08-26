import AgentUsageBarCore
import AppKit

/// `AgentUsageBar --dump-icons <dir>` renders the menu bar icons to PNGs and exits.
/// Lets the icon geometry be checked without a screenshot of the real menu bar.
enum IconDump {
    static func run(directory: String) {
        let root = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let cases: [(String, Double?, Double?, Bool)] = [
            ("full", 100, 100, false),
            ("codexbar-sample", 100, 86, false),
            ("half", 50, 70, false),
            ("low", 8, 20, false),
            ("session-only", 64, nil, false),
            ("stale", nil, nil, true),
        ]

        for provider in Provider.allCases {
            for (name, primary, weekly, stale) in cases {
                let image = IconRenderer.makeIcon(
                    provider: provider,
                    primaryRemaining: primary,
                    weeklyRemaining: weekly,
                    stale: stale
                )
                let url = root.appendingPathComponent("\(provider.rawValue)-\(name).png")
                guard Self.writePNG(image, to: url) else {
                    print("failed to write \(url.path)")
                    continue
                }
                print("wrote \(url.path)")
            }
        }
    }

    /// Template images carry alpha only, so tint them white on a transparent layer first and
    /// then composite that onto a dark ground — the way the menu bar renders them in dark mode.
    private static func writePNG(_ image: NSImage, to url: URL) -> Bool {
        let scale: CGFloat = 8
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let bounds = NSRect(origin: .zero, size: size)

        let tinted = NSImage(size: size)
        tinted.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        image.draw(in: bounds)
        NSColor.white.set()
        bounds.fill(using: .sourceAtop)
        tinted.unlockFocus()

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return false }

        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return false }
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .none

        NSColor(white: 0.11, alpha: 1).setFill()
        NSBezierPath(rect: bounds).fill()
        tinted.draw(in: bounds)
        ctx.flushGraphics()

        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url)) != nil
    }
}
