// Adapted from CodexBar (MIT, © 2026 Peter Steinberger): Sources/CodexBar/IconRenderer.swift
// Kept: the 18pt @2x pixel grid, the capsule track/fill/stroke bar, the dual- and single-lane
// layouts, and the provider-specific Codex and Claude decorations.
// Dropped: the Gemini/Antigravity/Factory/Warp decorations, blink/wiggle/tilt animation,
// status overlays, and the morph cache.

import AgentUsageBarCore
import AppKit

enum IconRenderer {
    private static let outputSize = NSSize(width: 18, height: 18)
    private static let outputScale: CGFloat = 2

    /// Everything is laid out in device pixels on a 2× grid, then converted to points, so
    /// edges land on pixel boundaries and the icon stays crisp at menu bar size.
    private struct PixelGrid {
        let scale: CGFloat

        func pt(_ px: Int) -> CGFloat { CGFloat(px) / self.scale }

        func rect(x: Int, y: Int, w: Int, h: Int) -> CGRect {
            CGRect(x: self.pt(x), y: self.pt(y), width: self.pt(w), height: self.pt(h))
        }
    }

    private static let grid = PixelGrid(scale: outputScale)

    private struct RectPx {
        let x: Int
        let y: Int
        let w: Int
        let h: Int

        func rect() -> CGRect { IconRenderer.grid.rect(x: self.x, y: self.y, w: self.w, h: self.h) }
    }

    static func fillWidthPixels(remaining: Double, rectWidth: Int) -> Int {
        let clamped = max(0, min(remaining / 100, 1))
        return max(0, min(rectWidth, Int((CGFloat(rectWidth) * CGFloat(clamped)).rounded())))
    }

    // MARK: - Cache

    private struct CacheKey: Hashable {
        let provider: Provider
        let primary: Int
        let weekly: Int
        let stale: Bool
    }

    private final class Cache: @unchecked Sendable {
        private var images: [CacheKey: NSImage] = [:]
        private var order: [CacheKey] = []
        private let lock = NSLock()

        func image(for key: CacheKey) -> NSImage? {
            self.lock.lock()
            defer { self.lock.unlock() }
            guard let image = self.images[key] else { return nil }
            if let index = self.order.firstIndex(of: key) {
                self.order.remove(at: index)
                self.order.append(key)
            }
            return image
        }

        func store(_ image: NSImage, for key: CacheKey, limit: Int) {
            self.lock.lock()
            defer { self.lock.unlock() }
            self.images[key] = image
            self.order.removeAll { $0 == key }
            self.order.append(key)
            while self.order.count > limit {
                self.images.removeValue(forKey: self.order.removeFirst())
            }
        }
    }

    private static let cache = Cache()
    private static let cacheLimit = 64

    // MARK: - Entry point

    /// - Parameters:
    ///   - primaryRemaining: percentage left in the session window, 0...100.
    ///   - weeklyRemaining: percentage left in the weekly window, 0...100.
    ///   - stale: dims the icon when the last refresh failed.
    static func makeIcon(
        provider: Provider,
        primaryRemaining: Double?,
        weeklyRemaining: Double?,
        stale: Bool
    ) -> NSImage {
        // Quantize to whole percent so small fluctuations reuse a cached image.
        let key = CacheKey(
            provider: provider,
            primary: primaryRemaining.map { Int($0.rounded()) } ?? -1,
            weekly: weeklyRemaining.map { Int($0.rounded()) } ?? -1,
            stale: stale
        )
        if let cached = self.cache.image(for: key) { return cached }

        let image = self.render(
            provider: provider,
            primaryRemaining: primaryRemaining,
            weeklyRemaining: weeklyRemaining,
            stale: stale
        )
        self.cache.store(image, for: key, limit: Self.cacheLimit)
        return image
    }

    private static func render(
        provider: Provider,
        primaryRemaining: Double?,
        weeklyRemaining: Double?,
        stale: Bool
    ) -> NSImage {
        self.renderImage {
            let baseFill = NSColor.labelColor
            let trackFillAlpha: CGFloat = stale ? 0.18 : 0.28
            let trackStrokeAlpha: CGFloat = stale ? 0.28 : 0.44
            let fillAlpha: CGFloat = stale ? 0.55 : 1.0

            func drawBar(
                rectPx: RectPx,
                remaining: Double?,
                alpha: CGFloat = 1.0,
                square: Bool = false
            ) {
                let rect = rectPx.rect()
                let cornerRadiusPx = square ? 0 : rectPx.h / 2
                let radius = Self.grid.pt(cornerRadiusPx)

                let trackPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
                baseFill.withAlphaComponent(trackFillAlpha * alpha).setFill()
                trackPath.fill()

                // Stroke an inset path so the 1pt outline stays inside the pixel bounds.
                let strokeWidthPx = 2
                let insetPx = strokeWidthPx / 2
                let strokeRect = Self.grid.rect(
                    x: rectPx.x + insetPx,
                    y: rectPx.y + insetPx,
                    w: max(0, rectPx.w - insetPx * 2),
                    h: max(0, rectPx.h - insetPx * 2)
                )
                let strokePath = NSBezierPath(
                    roundedRect: strokeRect,
                    xRadius: Self.grid.pt(max(0, cornerRadiusPx - insetPx)),
                    yRadius: Self.grid.pt(max(0, cornerRadiusPx - insetPx))
                )
                strokePath.lineWidth = CGFloat(strokeWidthPx) / Self.outputScale
                baseFill.withAlphaComponent(trackStrokeAlpha * alpha).setStroke()
                strokePath.stroke()

                // Clip to the capsule and paint a plain rect so the progress edge stays straight.
                if let remaining {
                    let fillWidthPx = Self.fillWidthPixels(remaining: remaining, rectWidth: rectPx.w)
                    if fillWidthPx > 0 {
                        NSGraphicsContext.current?.cgContext.saveGState()
                        trackPath.addClip()
                        baseFill.withAlphaComponent(fillAlpha * alpha).setFill()
                        NSBezierPath(rect: Self.grid.rect(
                            x: rectPx.x,
                            y: rectPx.y,
                            w: fillWidthPx,
                            h: rectPx.h
                        )).fill()
                        NSGraphicsContext.current?.cgContext.restoreGState()
                    }
                }
            }

            let hasWeeklyMeter = weeklyRemaining.map { $0 > 0 } ?? false
            let hasAnyData = primaryRemaining != nil || hasWeeklyMeter
            let decorationAlpha: CGFloat = (hasAnyData ? 1 : 0.45) * fillAlpha

            switch provider {
            case .codex:
                self.drawCodexBlossom(baseFill: baseFill, alpha: decorationAlpha)
                if hasWeeklyMeter {
                    drawBar(rectPx: RectPx(x: 8, y: 12, w: 20, h: 5), remaining: primaryRemaining)
                    drawBar(rectPx: RectPx(x: 9, y: 6, w: 18, h: 3), remaining: weeklyRemaining)
                } else {
                    // Keep a single quota visually honest instead of reserving an empty weekly lane.
                    drawBar(
                        rectPx: RectPx(x: 8, y: 8, w: 20, h: 6),
                        remaining: primaryRemaining,
                        alpha: hasAnyData ? 1 : 0.45
                    )
                }
            case .claude:
                self.drawClaudeCrab(baseFill: baseFill, alpha: decorationAlpha)
                if hasWeeklyMeter {
                    drawBar(
                        rectPx: RectPx(x: 6, y: 13, w: 24, h: 6),
                        remaining: primaryRemaining,
                        square: true
                    )
                    drawBar(
                        rectPx: RectPx(x: 6, y: 8, w: 24, h: 3),
                        remaining: weeklyRemaining,
                        square: true
                    )
                } else {
                    drawBar(
                        rectPx: RectPx(x: 6, y: 9, w: 24, h: 7),
                        remaining: primaryRemaining,
                        alpha: hasAnyData ? 1 : 0.45,
                        square: true
                    )
                }
            }
        }
    }

    // MARK: - Decorations

    private static func drawCodexBlossom(baseFill: NSColor, alpha: CGFloat) {
        let p = Self.grid.pt
        let outline = NSBezierPath()
        // An eight-lobed radial outline preserves the selected Blossom silhouette at 18pt.
        let center = CGPoint(x: p(18), y: p(18))
        let sampleCount = 96
        for index in 0...sampleCount {
            let angle = (Double(index) / Double(sampleCount)) * .pi * 2
            let radiusPx = 14.5 + 2.0 * cos(angle * 8)
            let point = NSPoint(
                x: center.x + p(Int((radiusPx * cos(angle) * 100).rounded())) / 100,
                y: center.y + p(Int((radiusPx * sin(angle) * 100).rounded())) / 100
            )
            if index == 0 {
                outline.move(to: point)
            } else {
                outline.line(to: point)
            }
        }
        outline.close()
        outline.lineWidth = p(2)
        baseFill.withAlphaComponent(alpha).setStroke()
        outline.stroke()

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setShouldAntialias(true)
        ctx.setStrokeColor(baseFill.withAlphaComponent(alpha).cgColor)
        ctx.setLineWidth(p(3))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: CGPoint(x: p(11), y: p(27)))
        ctx.addLine(to: CGPoint(x: p(15), y: p(23)))
        ctx.addLine(to: CGPoint(x: p(11), y: p(19)))
        ctx.strokePath()
        ctx.restoreGState()

        baseFill.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: Self.grid.rect(x: 19, y: 20, w: 7, h: 3), xRadius: p(1), yRadius: p(1)).fill()
    }

    private static func drawClaudeCrab(baseFill: NSColor, alpha: CGFloat) {
        let ctx = NSGraphicsContext.current?.cgContext
        baseFill.withAlphaComponent(alpha).setFill()

        NSBezierPath(rect: Self.grid.rect(x: 3, y: 21, w: 30, h: 10)).fill()
        NSBezierPath(rect: Self.grid.rect(x: 0, y: 23, w: 3, h: 4)).fill()
        NSBezierPath(rect: Self.grid.rect(x: 33, y: 23, w: 3, h: 4)).fill()

        for x in [9, 14, 20, 25] {
            NSBezierPath(rect: Self.grid.rect(
                x: x, y: 4, w: 2, h: 4
            )).fill()
        }

        ctx?.saveGState()
        ctx?.setShouldAntialias(false)
        ctx?.clear(Self.grid.rect(x: 10, y: 24, w: 2, h: 5))
        ctx?.clear(Self.grid.rect(x: 24, y: 24, w: 2, h: 5))
        ctx?.restoreGState()
    }

    // MARK: - Bitmap

    private static func renderImage(_ draw: () -> Void) -> NSImage {
        let image = NSImage(size: Self.outputSize)

        if let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(Self.outputSize.width * Self.outputScale),
            pixelsHigh: Int(Self.outputSize.height * Self.outputScale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) {
            rep.size = Self.outputSize
            image.addRepresentation(rep)

            NSGraphicsContext.saveGraphicsState()
            if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.current = ctx
                Self.withScaledContext(draw)
            }
            NSGraphicsContext.restoreGraphicsState()
        } else {
            image.lockFocus()
            Self.withScaledContext(draw)
            image.unlockFocus()
        }

        // Template mode lets the system tint the icon for light and dark menu bars.
        image.isTemplate = true
        return image
    }

    private static func withScaledContext(_ draw: () -> Void) {
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            draw()
            return
        }
        ctx.saveGState()
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .none
        draw()
        ctx.restoreGState()
    }
}
