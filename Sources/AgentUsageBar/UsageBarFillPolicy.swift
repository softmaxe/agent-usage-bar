import Foundation

/// Decides how a usage bar should move when its value changes. Kept separate from the view so the
/// three cases — first paint, quota rollover, ordinary drift — can be asserted without SwiftUI.
enum UsageBarFillPolicy {
    enum Fill: Equatable {
        /// Snap to empty, then sweep left to right. Used for a fresh card and a window rollover.
        case sweepFromEmpty(duration: TimeInterval)
        /// Move from wherever the bar already sits, the way a value normally drifts.
        case glide(duration: TimeInterval)
    }

    /// A window that rolls over jumps the remaining percentage up by far more than spending ever
    /// moves it down between two refreshes, which is what separates a reset from ordinary drift.
    static let rolloverJumpPoints: Double = 5

    static let sweepDuration: TimeInterval = 0.6
    static let rolloverDuration: TimeInterval = 0.95
    static let glideDuration: TimeInterval = 0.35

    /// The card was opened, so every bar sweeps in from empty regardless of its value.
    static func onPresentation() -> Fill {
        .sweepFromEmpty(duration: Self.sweepDuration)
    }

    /// The value changed while the card was already on screen.
    static func onValueChange(from oldPercent: Double, to newPercent: Double) -> Fill {
        newPercent - oldPercent >= Self.rolloverJumpPoints
            ? .sweepFromEmpty(duration: Self.rolloverDuration)
            : .glide(duration: Self.glideDuration)
    }
}
