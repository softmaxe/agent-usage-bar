import AppKit
import CoreGraphics
import SwiftUI

/// How the cost chart changes which bar is highlighted. A hover is the pointer's own motion and
/// has to keep up with it; the return to today is not a move the reader aimed at anything, so it
/// is allowed to take longer and to arrive with zero velocity — the shape `QuotaCelebrationReplay`
/// already uses to come back from the landing.
///
/// The selected bar also stands up a little, so the highlight reads as a shape and not only as a
/// tone. That is a state rather than a motion: Reduce Motion changes how the bar gets there, never
/// how tall it is once it has.
///
/// The label on that bar has a second change of its own — a click swaps its unit between tokens
/// and cost — and it lives here too, so everything the highlight can do is timed in one place.
enum CostChartHoverMotion {
    /// How much taller the selected bar stands. Small enough that the chart's proportions still
    /// read, large enough to see from the corner of the eye while reading the label.
    static let lift: CGFloat = 5

    /// A move between bars, on the spring that carries the height with the tone.
    static let hoverResponse: TimeInterval = 0.27
    private static let hoverDamping: Double = 0.9
    /// The trip home: longer, and critically damped, so the highlight settles onto today instead
    /// of springing onto it.
    static let returnResponse: TimeInterval = 0.33
    private static let returnDamping: Double = 1

    static var systemReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Nil means change the selection without animating it at all, which is what Reduce Motion is
    /// asking for.
    static func animation(
        returningToToday: Bool,
        reduceMotion: Bool,
        timeScale: Double = 1
    ) -> Animation? {
        guard !reduceMotion else { return nil }
        return returningToToday
            ? Self.returnAnimation(timeScale: timeScale)
            : Self.hoverAnimation(timeScale: timeScale)
    }

    static func hoverAnimation(timeScale: Double = 1) -> Animation {
        .spring(
            response: Self.scaled(Self.hoverResponse, timeScale),
            dampingFraction: Self.hoverDamping
        )
    }

    static func returnAnimation(timeScale: Double = 1) -> Animation {
        .spring(
            response: Self.scaled(Self.returnResponse, timeScale),
            dampingFraction: Self.returnDamping
        )
    }

    /// The label belongs to the bar, so it arrives the way the bar does: rising into place as it
    /// fades in, rather than blinking on above a bar that is still moving.
    static let labelTransition: AnyTransition = .opacity.combined(with: .offset(y: 4))

    // MARK: - Unit swap

    /// Clicking the selected bar swaps its label between tokens and cost. The click lands on a
    /// target the reader is already pointing at, so the swap has no distance to cover and can be
    /// quick; it still has to read as one number becoming another rather than as two numbers
    /// trading places.
    static let swapDuration: TimeInterval = 0.26

    /// The swap is the reset headline's treatment, sized for a 10 pt label: the old unit blurs
    /// out and the new one resolves out of the blur. Nothing moves, which is what says the two
    /// readings are the same quantity counted differently — a positional swap would say the
    /// label had been replaced by a different label.
    static let swapBlur: CGFloat = QuotaNumberMotion.blurRadius
    /// How small the number is while it is still blurred. Enough to feel unresolved, not enough
    /// to read as a separate zoom.
    static let swapScale: Double = 0.86

    static func swapAnimation(reduceMotion: Bool, timeScale: Double = 1) -> Animation? {
        guard !reduceMotion else { return nil }
        return .easeOut(duration: Self.scaled(Self.swapDuration, timeScale))
    }

    static let swapTransition: AnyTransition = .modifier(
        active: LabelResolve(progress: 1),
        identity: LabelResolve(progress: 0)
    )

    /// The demo window slows the spring down so a quarter-second response can be judged by eye.
    private static func scaled(_ duration: TimeInterval, _ timeScale: Double) -> TimeInterval {
        duration / max(0.01, timeScale)
    }
}

/// One end of the unit swap: at full strength the number is blurred and slightly small, at
/// identity it is the label as it is read.
struct LabelResolve: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: CostChartHoverMotion.swapBlur * self.progress)
            .scaleEffect(1 - (1 - CostChartHoverMotion.swapScale) * self.progress)
            .opacity(1 - self.progress)
    }
}
