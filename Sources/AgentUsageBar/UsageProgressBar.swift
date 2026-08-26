// Adapted from CodexBar (MIT, © 2026 Peter Steinberger): Sources/CodexBar/UsageProgressBar.swift
// Kept: the single-Canvas track, fill, and pace marker.
// Dropped: quota/workday markers, highlight-state theming, and accessibility values.
// Added: the sweep-from-empty fill, which CodexBar draws statically, and the reset animation that
// resumes from the final reading of the previous quota window.

import AppKit
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
    /// Non-zero, and changing, means this window reset: play the celebration instead of the
    /// ordinary sweep. Zero for every bar that has nothing to celebrate.
    let celebrationToken: Int
    /// The final remaining percentage observed before this window reset.
    let celebrationStartPercent: Double?

    @Environment(\.displayScale) private var displayScale

    /// Drives the fill. Starts empty so the first paint is always a sweep.
    @State private var displayedPercent: Double = 0
    /// Owns the celebration's frame clock; nil elapsed means nothing is playing.
    @StateObject private var celebration = CelebrationClock()

    private static let pacePunchWidth: CGFloat = 4
    private static let paceStripeWidth: CGFloat = 2
    private static let punchOpacity: Double = 1
    /// How far the spark canvas reaches past each end of the bar.
    private static let celebrationInset: CGFloat = 20
    /// Tall enough that sparks fade out before they reach the canvas edge; the card clips them
    /// long before that, which is the boundary that should be doing the cutting.
    private static let celebrationHeight: CGFloat = 170

    init(
        percent: Double,
        tint: Color,
        pacePercent: Double? = nil,
        paceIsDeficit: Bool = false,
        presentationToken: Int = 0,
        animatesFill: Bool = true,
        celebrationToken: Int = 0,
        celebrationStartPercent: Double? = nil
    ) {
        self.percent = percent
        self.tint = tint
        self.pacePercent = pacePercent
        self.paceIsDeficit = paceIsDeficit
        self.presentationToken = presentationToken
        self.animatesFill = animatesFill
        self.celebrationToken = celebrationToken
        self.celebrationStartPercent = celebrationStartPercent
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

            let fillWidth = size.width * min(100, max(0, self.fillPercent)) / 100
            if fillWidth > 0 {
                let fillRect = CGRect(x: 0, y: 0, width: min(fillWidth, size.width), height: size.height)
                let fillPath = Path { $0.addRoundedRect(in: fillRect, cornerSize: cornerSize) }
                context.fill(fillPath, with: .color(self.tint))

                if let time = self.celebration.elapsed {
                    // A bright edge riding the head, and then the whole fill washing white as it
                    // lands. Both are drawn inside the pill, so they inherit its rounded ends.
                    let shine = QuotaCelebration.headShineOpacity(at: time)
                    if shine > 0.01 {
                        let head = fillRect.maxX
                        let glow = CGRect(x: head - 14, y: 0, width: 16, height: size.height)
                        context.fill(
                            Path(roundedRect: glow, cornerSize: cornerSize).intersection(fillPath),
                            with: .linearGradient(
                                Gradient(colors: [
                                    .white.opacity(0),
                                    .white.opacity(0.9 * shine),
                                ]),
                                startPoint: CGPoint(x: glow.minX, y: 0),
                                endPoint: CGPoint(x: glow.maxX, y: 0)
                            )
                        )
                    }
                    let flash = QuotaCelebration.flashOpacity(at: time)
                    if flash > 0.01 {
                        context.fill(fillPath, with: .color(.white.opacity(flash)))
                    }
                }
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
        .scaleEffect(self.barScale, anchor: .center)
        // Outside the bar and unscaled: the sparks are in the card's space, not the pill's.
        .overlay {
            if let time = self.celebration.elapsed {
                QuotaCelebrationLayer(
                    elapsed: time,
                    tint: self.tint,
                    startPercent: self.celebrationStartPercent ?? 0,
                    targetPercent: self.clamped,
                    inset: Self.celebrationInset
                )
                    .frame(height: Self.celebrationHeight)
                    .padding(.horizontal, -Self.celebrationInset)
            }
        }
        .onAppear {
            guard self.animatesFill else { return }
            // A card that opens with a celebration already queued starts on it, not on a sweep.
            if self.startCelebrationIfWanted() { return }
            self.apply(UsageBarFillPolicy.onPresentation())
        }
        .onDisappear { self.celebration.stop() }
        .onChange(of: self.celebrationToken) { _, _ in
            _ = self.startCelebrationIfWanted()
        }
        .onChange(of: self.presentationToken) { _, _ in
            guard self.animatesFill, !self.celebration.isRunning else { return }
            self.apply(UsageBarFillPolicy.onPresentation())
        }
        .onChange(of: self.percent) { oldValue, newValue in
            guard self.animatesFill else {
                self.displayedPercent = self.clamped
                return
            }
            guard !self.celebration.isRunning else {
                // The celebration is already driving the fill; keep the handoff value current.
                self.displayedPercent = self.clamped
                return
            }
            self.apply(UsageBarFillPolicy.onValueChange(from: oldValue, to: newValue))
        }
    }

    /// What the Canvas fills to: the choreography while a celebration plays, the animated value
    /// the rest of the time.
    private var fillPercent: Double {
        guard let time = self.celebration.elapsed else { return self.displayedPercent }
        return QuotaCelebration.fillPercent(
            at: time,
            from: self.celebrationStartPercent ?? 0,
            to: self.clamped
        )
    }

    private var barScale: CGSize {
        guard let time = self.celebration.elapsed else { return CGSize(width: 1, height: 1) }
        return QuotaCelebration.barScale(at: time)
    }

    /// Returns whether a celebration was started, so the caller knows to skip the ordinary sweep.
    @discardableResult
    private func startCelebrationIfWanted() -> Bool {
        guard self.celebrationToken != 0,
              self.celebrationStartPercent != nil,
              self.animatesFill
        else { return false }
        // Reduce Motion turns the whole thing off: sparks flying out of the menu bar are exactly
        // what that setting exists to stop.
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            self.apply(UsageBarFillPolicy.onPresentation())
            return true
        }
        // The clock owns the visible fill from the persisted pre-reset value to the new reading.
        // The handoff when it stops lands on that real value without a snap.
        var snap = Transaction()
        snap.disablesAnimations = true
        withTransaction(snap) { self.displayedPercent = self.clamped }
#if DEBUG
        self.celebration.start(duration: QuotaCelebration.duration, timeScale: QuotaCelebration.timeScale)
#else
        self.celebration.start(duration: QuotaCelebration.duration)
#endif
        return true
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
                guard !self.celebration.isRunning else { return }
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
