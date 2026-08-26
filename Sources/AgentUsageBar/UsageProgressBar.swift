// Adapted from CodexBar (MIT, © 2026 Peter Steinberger): Sources/CodexBar/UsageProgressBar.swift
// Kept: the single-Canvas track + fill + punched quota markers.
// Dropped: workday boundary ticks, the pace stripe (M3), highlight-state theming, accessibility values.

import SwiftUI

/// Static progress fill with no implicit animations, used inside the menu card.
struct UsageProgressBar: View {
    /// Percentage *remaining*, 0...100 — the bar fills from the left with what is left.
    let percent: Double
    let tint: Color
    /// Positions of the notches that segment the bar, in percent.
    let markerPercents: [Double]
    /// Where the fill would sit if the budget were being spent evenly, in remaining percent.
    let pacePercent: Double?
    /// Red marks burning faster than the clock; green marks a reserve.
    let paceIsDeficit: Bool

    @Environment(\.displayScale) private var displayScale

    private static let markerPunchWidth: CGFloat = 5
    private static let markerStripeWidth: CGFloat = 1
    private static let pacePunchWidth: CGFloat = 4
    private static let paceStripeWidth: CGFloat = 2
    private static let punchOpacity: Double = 0.9

    init(
        percent: Double,
        tint: Color,
        markerPercents: [Double] = [],
        pacePercent: Double? = nil,
        paceIsDeficit: Bool = false
    ) {
        self.percent = percent
        self.tint = tint
        self.markerPercents = markerPercents
        self.pacePercent = pacePercent
        self.paceIsDeficit = paceIsDeficit
    }

    private var clamped: Double { min(100, max(0, self.percent)) }

    var body: some View {
        // Everything is drawn in one Canvas. CodexBar found that SwiftUI compositing modifiers
        // (.blendMode, .compositingGroup) trigger shader compilation on macOS 26 that can make the
        // status item icon disappear; a single Canvas uses Core Graphics directly and avoids it.
        Canvas { context, size in
            let scale = max(self.displayScale, 1)
            let cornerSize = CGSize(width: size.height / 2, height: size.height / 2)
            let rect = CGRect(origin: .zero, size: size)

            context.clip(to: Path(rect))

            let trackPath = Path { $0.addRoundedRect(in: rect, cornerSize: cornerSize) }
            context.fill(trackPath, with: .color(Theme.progressTrack))

            let fillWidth = size.width * self.clamped / 100
            if fillWidth > 0 {
                let fillRect = CGRect(x: 0, y: 0, width: min(fillWidth, size.width), height: size.height)
                let fillPath = Path { $0.addRoundedRect(in: fillRect, cornerSize: cornerSize) }
                context.fill(fillPath, with: .color(self.tint))
            }

            for markerPercent in self.markerPercents {
                let x = size.width * min(100, max(0, markerPercent)) / 100
                let punchRect = Self.markerRect(x: x, size: size, width: Self.markerPunchWidth, scale: scale)
                let stripeRect = Self.markerRect(
                    x: x,
                    size: size,
                    width: max(1 / scale, Self.markerStripeWidth),
                    scale: scale
                )

                // Punch a gap through track and fill alike, then lay a thinner neutral stripe in it.
                context.blendMode = .destinationOut
                context.fill(
                    Path(Self.extended(punchRect, size: size)),
                    with: .color(.white.opacity(Self.punchOpacity))
                )
                context.blendMode = .normal
                context.fill(Path(Self.extended(stripeRect, size: size)), with: .color(Theme.markerStripe))
            }

            // Pace tip, drawn last so it reads on top of both the track and the fill.
            if let pacePercent = self.pacePercent {
                let x = size.width * min(100, max(0, pacePercent)) / 100
                let punchRect = Self.markerRect(x: x, size: size, width: Self.pacePunchWidth, scale: scale)
                let stripeRect = Self.markerRect(
                    x: x,
                    size: size,
                    width: max(1 / scale, Self.paceStripeWidth),
                    scale: scale
                )
                context.blendMode = .destinationOut
                context.fill(
                    Path(Self.extended(punchRect, size: size)),
                    with: .color(.white.opacity(Self.punchOpacity))
                )
                context.blendMode = .normal
                context.fill(
                    Path(Self.extended(stripeRect, size: size)),
                    with: .color(self.paceIsDeficit ? .red : .green)
                )
            }
        }
        .frame(height: 6)
    }

    private static func markerRect(x: CGFloat, size: CGSize, width: CGFloat, scale: CGFloat) -> CGRect {
        let align: (CGFloat) -> CGFloat = { ($0 * scale).rounded() / scale }
        return CGRect(x: align(x - width / 2), y: 0, width: width, height: align(size.height))
    }

    /// Extend past the bar vertically so the punch clears the rounded edges.
    private static func extended(_ rect: CGRect, size: CGSize) -> CGRect {
        rect.insetBy(dx: 0, dy: -size.height * 2)
    }
}
