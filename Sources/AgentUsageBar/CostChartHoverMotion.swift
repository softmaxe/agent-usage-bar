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

    /// The demo window slows the spring down so a quarter-second response can be judged by eye.
    private static func scaled(_ duration: TimeInterval, _ timeScale: Double) -> TimeInterval {
        duration / max(0.01, timeScale)
    }
}
