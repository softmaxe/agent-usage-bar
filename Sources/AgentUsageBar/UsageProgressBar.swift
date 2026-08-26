// Adapted from CodexBar (MIT, © 2026 Peter Steinberger): Sources/CodexBar/UsageProgressBar.swift
// Kept: the single-Canvas track, fill, and pace marker.
// Dropped: quota/workday markers, highlight-state theming, and accessibility values.
// Added: the sweep-from-empty fill, which CodexBar draws statically.

import SwiftUI

/// Progress fill for one quota window. The fill sweeps in from the left when the card is opened
/// and again when the window rolls over; ordinary spending just glides.
struct UsageProgressBar: View {
    /// Percentage *remaining*, 0...100 — the bar fills from the left with what is left.
    let percent: Double
    let tint: Color
    /// Where the fill would sit if the budget were being spent evenly, in remaining percent.
    let pacePercent: Double?
    /// Red marks burning faster than the clock; green marks a reserve.
    let paceIsDeficit: Bool
    /// Changes each time the card is presented, which is what replays the sweep.
    let presentationToken: Int
    /// Offscreen renders capture a single frame, so they need the bar to start at its final value.
    let animatesFill: Bool

    @Environment(\.displayScale) private var displayScale

    /// Drives the fill. Starts empty so the first paint is always a sweep.
    @State private var displayedPercent: Double = 0

    private static let pacePunchWidth: CGFloat = 4
    private static let paceStripeWidth: CGFloat = 2
    private static let punchOpacity: Double = 0.9

    init(
        percent: Double,
        tint: Color,
        pacePercent: Double? = nil,
        paceIsDeficit: Bool = false,
        presentationToken: Int = 0,
        animatesFill: Bool = true
    ) {
        self.percent = percent
        self.tint = tint
        self.pacePercent = pacePercent
        self.paceIsDeficit = paceIsDeficit
        self.presentationToken = presentationToken
        self.animatesFill = animatesFill
        self._displayedPercent = State(initialValue: animatesFill ? 0 : min(100, max(0, percent)))
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

            let fillWidth = size.width * min(100, max(0, self.displayedPercent)) / 100
            if fillWidth > 0 {
                let fillRect = CGRect(x: 0, y: 0, width: min(fillWidth, size.width), height: size.height)
                let fillPath = Path { $0.addRoundedRect(in: fillRect, cornerSize: cornerSize) }
                context.fill(fillPath, with: .color(self.tint))
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
        .onAppear {
            guard self.animatesFill else { return }
            self.apply(UsageBarFillPolicy.onPresentation())
        }
        .onChange(of: self.presentationToken) { _, _ in
            guard self.animatesFill else { return }
            self.apply(UsageBarFillPolicy.onPresentation())
        }
        .onChange(of: self.percent) { oldValue, newValue in
            guard self.animatesFill else {
                self.displayedPercent = self.clamped
                return
            }
            self.apply(UsageBarFillPolicy.onValueChange(from: oldValue, to: newValue))
        }
    }

    private func apply(_ fill: UsageBarFillPolicy.Fill) {
        switch fill {
        case let .sweepFromEmpty(duration):
            var snap = Transaction()
            snap.disablesAnimations = true
            withTransaction(snap) { self.displayedPercent = 0 }
            // The empty state has to reach the renderer before the sweep is queued, or SwiftUI
            // coalesces both writes and interpolates from the old value instead of from zero.
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: duration)) { self.displayedPercent = self.clamped }
            }
        case let .glide(duration):
            withAnimation(.easeOut(duration: duration)) { self.displayedPercent = self.clamped }
        }
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
