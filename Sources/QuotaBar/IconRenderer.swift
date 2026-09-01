// Adapted from CodexBar (MIT, © 2026 Peter Steinberger): Sources/CodexBar/IconRenderer.swift
// Kept: the 18pt @2x pixel grid, the capsule track/fill/stroke bar, the dual- and single-lane
// layouts, and the Codex "face" and Claude "crab" decorations.
// Dropped: the Gemini/Antigravity/Factory/Warp decorations, blink/wiggle/tilt animation,
// status overlays, and the morph cache.

import QuotaBarCore
import AppKit

enum IconRenderer {
    private static let outputSize = NSSize(width: 18, height: 18)
    private static let outputScale: CGFloat = 2
    private static let canvasPx = Int(outputSize.width * outputScale)

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

        var midXPx: Int { self.x + self.w / 2 }

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
            let fillColor = baseFill.withAlphaComponent(stale ? 0.55 : 1.0)

            // Every lane of every provider spans the same 18pt, so switching providers does not
            // resize the icon. The crab reaches that span with its arms, so its bar is narrower by
            // exactly what the arms add; the Codex capsule is simply that wide.
            let decoration: Decoration = provider == .codex ? .face : .crab
            let spanPx = Self.canvasPx
            let barWidthPx = spanPx - (decoration == .crab ? Self.crabArmWidthPx * 2 : 0)
            let barXPx = (spanPx - barWidthPx) / 2

            func drawBar(rectPx: RectPx, remaining: Double?, alpha: CGFloat = 1.0, decoration: Decoration = .none) {
                let rect = rectPx.rect()
                // Claude reads better as a blocky critter; Codex stays a capsule.
                let cornerRadiusPx = decoration == .crab ? 0 : rectPx.h / 2
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
                        fillColor.withAlphaComponent(alpha).setFill()
                        NSBezierPath(rect: Self.grid.rect(
                            x: rectPx.x,
                            y: rectPx.y,
                            w: fillWidthPx,
                            h: rectPx.h
                        )).fill()
                        NSGraphicsContext.current?.cgContext.restoreGState()
                    }
                }

                switch decoration {
                case .none:
                    break
                case .face:
                    self.drawFace(rectPx: rectPx, fillColor: fillColor, alpha: alpha)
                case .crab:
                    self.drawCrab(rectPx: rectPx, fillColor: fillColor, alpha: alpha)
                }
            }

            // The weekly lane carries no decoration, so it takes the full span. When a plan has
            // no session limit, the upper lane stays full to communicate that it is unrestricted.
            let topRectPx = RectPx(x: barXPx, y: 19, w: barWidthPx, h: 12)
            let bottomRectPx = RectPx(x: 0, y: 5, w: spanPx, h: 8)
            // One meaningful quota should read as one meter: reserving an unusable second lane
            // would make 46% remaining look like roughly 23% of the icon.
            let singleRectPx = RectPx(x: barXPx, y: 14, w: barWidthPx, h: 16)

            if let weeklyRemaining {
                drawBar(rectPx: topRectPx, remaining: primaryRemaining ?? 100, decoration: decoration)
                drawBar(rectPx: bottomRectPx, remaining: weeklyRemaining)
            } else if let primaryRemaining {
                drawBar(rectPx: singleRectPx, remaining: primaryRemaining, decoration: decoration)
            } else {
                // No data at all: an empty track, so the icon still shows the app is alive.
                drawBar(rectPx: singleRectPx, remaining: nil, alpha: 0.45, decoration: decoration)
            }
        }
    }

    /// How far the crab's arms extend past its bar on each side, in device pixels.
    private static let crabArmWidthPx = 3

    private enum Decoration: Equatable {
        case none
        /// Codex: square eye cutouts plus a small cap.
        case face
        /// Claude: side arms, four legs, tall vertical eye cutouts.
        case crab
    }

    // MARK: - Decorations

    private static func drawFace(rectPx: RectPx, fillColor: NSColor, alpha: CGFloat) {
        let ctx = NSGraphicsContext.current?.cgContext
        let eyeSizePx = 4
        let eyeOffsetPx = 7
        let eyeCenterYPx = rectPx.y + rectPx.h / 2
        let centerXPx = rectPx.midXPx

        // Punch the eyes out of the bar rather than painting over it, so they read on
        // both a filled and an empty track.
        ctx?.saveGState()
        ctx?.setShouldAntialias(false)
        ctx?.clear(Self.grid.rect(
            x: centerXPx - eyeOffsetPx - eyeSizePx / 2,
            y: eyeCenterYPx - eyeSizePx / 2,
            w: eyeSizePx,
            h: eyeSizePx
        ))
        ctx?.clear(Self.grid.rect(
            x: centerXPx + eyeOffsetPx - eyeSizePx / 2,
            y: eyeCenterYPx - eyeSizePx / 2,
            w: eyeSizePx,
            h: eyeSizePx
        ))
        ctx?.restoreGState()

        let hatWidthPx = 18
        let hatHeightPx = 4
        fillColor.withAlphaComponent(alpha).setFill()
        NSBezierPath(rect: Self.grid.rect(
            x: centerXPx - hatWidthPx / 2,
            y: rectPx.y + rectPx.h - hatHeightPx,
            w: hatWidthPx,
            h: hatHeightPx
        )).fill()
    }

    private static func drawCrab(rectPx: RectPx, fillColor: NSColor, alpha: CGFloat) {
        let ctx = NSGraphicsContext.current?.cgContext
        fillColor.withAlphaComponent(alpha).setFill()

        // Arms: barX is 3px, so 3px arms reach the canvas edge without clipping.
        let armWidthPx = Self.crabArmWidthPx
        let armHeightPx = max(0, rectPx.h - 6)
        let armYPx = rectPx.y + 3
        NSBezierPath(rect: Self.grid.rect(
            x: rectPx.x - armWidthPx, y: armYPx, w: armWidthPx, h: armHeightPx
        )).fill()
        NSBezierPath(rect: Self.grid.rect(
            x: rectPx.x + rectPx.w, y: armYPx, w: armWidthPx, h: armHeightPx
        )).fill()

        let legCount = 4
        let legWidthPx = 2
        let legHeightPx = 3
        let legYPx = rectPx.y - legHeightPx
        let stepPx = max(1, rectPx.w / (legCount + 1))
        for index in 0..<legCount {
            let centerXPx = rectPx.x + stepPx * (index + 1)
            NSBezierPath(rect: Self.grid.rect(
                x: centerXPx - legWidthPx / 2, y: legYPx, w: legWidthPx, h: legHeightPx
            )).fill()
        }

        let eyeWidthPx = 2
        let eyeHeightPx = 5
        let eyeOffsetPx = 6
        let eyeYPx = rectPx.y + rectPx.h - eyeHeightPx - 2
        ctx?.saveGState()
        ctx?.setShouldAntialias(false)
        ctx?.clear(Self.grid.rect(
            x: rectPx.midXPx - eyeOffsetPx - eyeWidthPx / 2, y: eyeYPx, w: eyeWidthPx, h: eyeHeightPx
        ))
        ctx?.clear(Self.grid.rect(
            x: rectPx.midXPx + eyeOffsetPx - eyeWidthPx / 2, y: eyeYPx, w: eyeWidthPx, h: eyeHeightPx
        ))
        ctx?.restoreGState()
    }

    // MARK: - Bitmap

    private static func renderImage(_ draw: () -> Void) -> NSImage {
        let image = NSImage(size: Self.outputSize)

        if let rep = NSBitmapImageRep.rgba(
            pixelsWide: Int(Self.outputSize.width * Self.outputScale),
            pixelsHigh: Int(Self.outputSize.height * Self.outputScale)
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
