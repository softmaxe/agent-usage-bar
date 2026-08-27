import CoreGraphics
import Foundation

/// One frame of the reset choreography, as the bar is drawing it. The headline above the bar
/// renders from this rather than from a clock of its own, so the digits cannot drift out of step
/// with the fill — including through the hidden replay, which the headline knows nothing about.
struct QuotaCelebrationFrame: Equatable {
    /// Seconds into the sequence.
    let elapsed: TimeInterval
    /// The percentage the fill is showing at this instant.
    let percent: Double
    /// The hidden replay returns to the live reading instead of stopping at 100%.
    let isReplay: Bool
}

/// The bar publishes its choreography here and the headline reads it. Only the two of them
/// re-render per frame; the rest of the card never sees the clock.
@MainActor
final class QuotaCelebrationRelay: ObservableObject {
    /// Nil whenever nothing is playing, which is also what returns the headline to the live value.
    @Published fileprivate(set) var frame: QuotaCelebrationFrame?

    func publish(_ frame: QuotaCelebrationFrame?) {
        self.frame = frame
    }
}

/// The label's share of the reset choreography. Everything here is a reading of a curve the bar
/// already runs — same easing, same landing beat, same decay — so the number arrives with the fill
/// instead of announcing a second event of its own.
enum QuotaNumberMotion {
    /// The counted value. Literally the fill's own easing, so the digits and the head of the fill
    /// are the same motion shown twice.
    static func value(at time: TimeInterval, from start: Double, to target: Double) -> Double {
        QuotaCelebration.fillPercent(at: time, from: start, to: target)
    }

    /// A uniform read of the bar's damped sine. The bar can stretch 50% in height because it is a
    /// 6 pt pill; text at the same amplitude would read as a layout bug, so the same pulse drives
    /// a much smaller scale.
    static func scale(at time: TimeInterval, amplitude: Double = 0.08) -> Double {
        let age = time - QuotaCelebration.landing
        guard age >= 0, age < QuotaCelebration.popDuration else { return 1 }
        let pulse = exp(-5.4 * age) * sin(2 * .pi * 1.3 * age)
        return 1 + amplitude * pulse
    }

    /// How far the number is washed towards the tint on the landing beat, on the fill's flash
    /// curve. The bar can flash white because it is a colored pill; a white label on a light card
    /// is a label that disappears, so the wash here is warmth rather than brightness.
    static func flash(at time: TimeInterval) -> Double {
        let age = time - QuotaCelebration.landing
        guard age >= 0, age < QuotaCelebration.flashDuration else { return 0 }
        return pow(1 - age / QuotaCelebration.flashDuration, 1.6)
    }

    /// The warm halo behind the digits: the bar's bloom, sized for text. Same duration and the
    /// same swell, so the glow under the bar and the glow behind the number are one event.
    static func glow(at time: TimeInterval) -> (opacity: Double, scale: Double)? {
        let age = time - QuotaCelebration.landing
        guard age >= 0, age < QuotaCelebration.bloomDuration else { return nil }
        let progress = age / QuotaCelebration.bloomDuration
        let eased = 1 - pow(1 - progress, 2.2)
        return (0.42 * pow(1 - progress, 1.7), 0.72 + 0.28 * eased)
    }

    /// How fast the digits are turning over, 1 at the start and decaying with the fill. The count
    /// is blurred by this, so the number resolves into 100% instead of stopping on it.
    static func speed(at time: TimeInterval) -> Double {
        guard time >= 0, time < QuotaCelebration.sweepDuration else { return 0 }
        return exp(-QuotaCelebration.fillDecay * time / QuotaCelebration.sweepDuration)
    }

    /// Peak blur radius, at the moment the digits are moving fastest.
    static let blurRadius: CGFloat = 2.6
}
