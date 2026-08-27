import CoreGraphics
import Foundation

/// One quota window. It also keeps five-hour and weekly reset tracking independent.
enum QuotaWindowKind: String, Hashable, CaseIterable {
    case session
    case weekly
}

/// Choreography for a quota reset: the fill resumes from the last pre-reset reading and
/// continuously slows into 100%. Nothing trails the head on the way there — the landing is the
/// whole event, synchronizing the bar pop, flash, and one large circular firework centred just
/// short of the 100% point.
enum QuotaCelebration {
    // MARK: - Timeline

    /// One continuous exponential decay drives the fill all the way to its destination.
    static let landing: TimeInterval = 2.8
    static let sweepDuration = Self.landing
    /// How long the bar keeps springing after the head lands.
    static let popDuration: TimeInterval = 0.78
    /// The fill washes bright at the moment of landing and cools back to the tint.
    static let flashDuration: TimeInterval = 0.48
    static let ringDuration: TimeInterval = 0.7
    /// The white heart of the shell, at the instant of landing.
    static let coreDuration: TimeInterval = 0.26
    /// Longest a spoke of the shell can live.
    static let burstLife: TimeInterval = 0.95

    /// When the last spoke of the shell has faded, and therefore when the clock stops.
    static var duration: TimeInterval {
        Self.landing + max(Self.popDuration, max(Self.burstLife, Self.ringDuration))
    }

#if DEBUG
    /// The demo window slows the whole sequence down, so a 60 ms overshoot can be judged by eye.
    static var timeScale: Double = 1
#endif

    // MARK: - Fill

    private static let fillDecay: Double = 5.2

    /// Share of the final percentage the bar shows, 0...1.
    static func fillFraction(at time: TimeInterval) -> Double {
        guard time > 0 else { return 0 }
        guard time < Self.sweepDuration else { return 1 }
        let normalized = time / Self.sweepDuration
        return (1 - exp(-Self.fillDecay * normalized)) / (1 - exp(-Self.fillDecay))
    }

    static func fillPercent(at time: TimeInterval, from start: Double, to target: Double) -> Double {
        let from = min(100, max(0, start))
        let to = min(100, max(0, target))
        return from + (to - from) * Self.fillFraction(at: time)
    }

    /// A bright edge riding the head of the fill. Fades out as the head arrives so the landing
    /// reads as the flash, not as the shine stopping.
    static func headShineOpacity(at time: TimeInterval) -> Double {
        guard time > 0 else { return 0 }
        let fadeIn = min(1, time / 0.05)
        let remaining = Self.landing - time
        guard remaining > 0 else { return 0 }
        return 0.64 * fadeIn * min(1, remaining / 0.22)
    }

    /// The whole fill washing white at the moment of landing.
    static func flashOpacity(at time: TimeInterval) -> Double {
        let age = time - Self.landing
        guard age >= 0, age < Self.flashDuration else { return 0 }
        return 0.3 * pow(1 - age / Self.flashDuration, 1.7)
    }

    // MARK: - Pop

    /// Scale for the bar itself. Height carries the pop — a 6 pt pill widening reads as a glitch,
    /// while the same pill growing taller reads as a bounce.
    static func barScale(at time: TimeInterval) -> CGSize {
        let age = time - Self.landing
        guard age >= 0, age < Self.popDuration else { return CGSize(width: 1, height: 1) }
        // A damped sine: zero at the landing, one overshoot, then it settles instead of snapping.
        let pulse = exp(-5.7 * age) * sin(2 * .pi * 1.72 * age)
        return CGSize(width: 1 + 0.035 * pulse, height: 1 + 0.7 * pulse)
    }

    // MARK: - Origin

    /// Where along the bar the whole landing event is centred, as a fraction of the bar width.
    /// Short of the very end on purpose: the bar stops 14 pt from the card's right edge, and a
    /// burst centred on the last pixel would have half of itself cut away by that edge.
    static let originX: Double = 0.92

    /// How far the shell reaches at its widest. Sized so a burst on `originX` stays inside the
    /// 280 pt card instead of being clipped by it.
    static let maxRadius: CGFloat = 34

    // MARK: - Core

    struct Core: Equatable {
        let radius: CGFloat
        let glowRadius: CGFloat
        let opacity: Double
    }

    /// The white heart of the shell at the instant of landing.
    static func core(at time: TimeInterval) -> Core? {
        let age = time - Self.landing
        guard age >= 0, age < Self.coreDuration else { return nil }
        let progress = age / Self.coreDuration
        let eased = 1 - pow(1 - progress, 3)
        return Core(
            radius: 1.6 + 6 * (1 - progress),
            glowRadius: 5 + 18 * eased,
            opacity: pow(1 - progress, 1.6)
        )
    }

    // MARK: - Rings

    struct Ring: Equatable {
        let radius: CGFloat
        let lineWidth: CGFloat
        let opacity: Double
    }

    /// Two concentric shockwaves leaving the landing point, the second a beat behind the first.
    static func rings(at time: TimeInterval) -> [Ring] {
        [(0.0, 30.0, 2.4, 0.5), (0.12, 19.0, 1.3, 0.3)].compactMap { delay, reach, weight, peak in
            let age = time - Self.landing - delay
            guard age >= 0, age < Self.ringDuration else { return nil }
            let progress = age / Self.ringDuration
            let eased = 1 - pow(1 - progress, 2.6)
            return Ring(
                radius: 3 + reach * eased,
                lineWidth: weight * (1 - progress) + 0.3,
                opacity: peak * pow(1 - progress, 1.6)
            )
        }
    }

    // MARK: - Corona

    enum Tone: Equatable {
        /// The provider's own accent, so the burst still belongs to the card.
        case tint
        case warm
        case white
    }

    /// One spark of the shell: the streak it has swept, plus the bright head leading it.
    /// Bar-local: `x` measured from the bar's left edge, `y` from its centre, positive downwards.
    struct Ray: Equatable {
        let inner: CGPoint
        let outer: CGPoint
        let width: CGFloat
        let opacity: Double
        /// Radius of the bright head; the streak behind it is drawn faded.
        let headRadius: CGFloat
        let tone: Tone
    }

    /// Evenly spaced spokes are what keep the shell round; a small per-spoke speed jitter is what
    /// keeps it from reading as a gear. Three layers give the burst a fast white fringe, a body in
    /// the card's own tint, and a slow warm centre.
    private struct Layer {
        let count: Int
        /// Radians, so the layers interleave instead of sitting on top of each other.
        let offset: Double
        let speed: Double
        /// Fraction of `speed` a spoke may deviate by, so the rim is a ring and not a stencil.
        let jitter: Double
        let width: CGFloat
        let life: TimeInterval
        let tone: Tone
        let seed: UInt64
    }

    private static let layers: [Layer] = [
        Layer(count: 34, offset: 0, speed: 118, jitter: 0.2, width: 1.9,
              life: Self.burstLife, tone: .tint, seed: 0x9E37_79B9),
        Layer(count: 26, offset: .pi / 26, speed: 74, jitter: 0.26, width: 1.5,
              life: Self.burstLife * 0.86, tone: .warm, seed: 0x51ED_2701),
        Layer(count: 13, offset: .pi / 13, speed: 122, jitter: 0.14, width: 1.1,
              life: Self.burstLife * 0.53, tone: .white, seed: 0xC2B2_AE35),
    ]

    /// Radial drag, so every spoke eases out instead of flying off in a straight line.
    private static let drag: Double = 3.6
    /// A hint of gravity: enough for the shell to sag as it dies, not enough to break the circle.
    private static let gravity: Double = 30
    /// How much of the streak trails behind each head.
    private static let tailSeconds: TimeInterval = 0.16

    /// The one firework, centred on `originX` and opening as a circle.
    static func rays(at time: TimeInterval, barWidth: CGFloat) -> [Ray] {
        let age = time - Self.landing
        guard age >= 0 else { return [] }
        let origin = CGPoint(x: Double(barWidth) * Self.originX, y: 0)

        var rays: [Ray] = []
        for layer in Self.layers {
            guard age < layer.life else { continue }
            let progress = age / layer.life
            var random = SeededRandom(seed: layer.seed)
            for index in 0..<layer.count {
                let angle = layer.offset + 2 * .pi * Double(index) / Double(layer.count)
                let speed = layer.speed * random.next(in: (1 - layer.jitter)...(1 + layer.jitter))
                let phase = random.next(in: 0...(2 * .pi))
                let head = Self.radius(speed: speed, age: age)
                let tail = Self.radius(speed: speed, age: max(0, age - Self.tailSeconds))
                // Twinkle keeps the rim alive while it fades, the way real sparks flicker out.
                let twinkle = 0.78 + 0.22 * sin(age * 21 + phase)
                let opacity = min(1, age / 0.035) * pow(1 - progress, 1.6) * twinkle
                guard opacity > 0.015 else { continue }
                rays.append(Ray(
                    inner: Self.point(
                        origin: origin,
                        angle: angle,
                        radius: tail,
                        age: max(0, age - Self.tailSeconds)
                    ),
                    outer: Self.point(origin: origin, angle: angle, radius: head, age: age),
                    width: layer.width * (1 - 0.4 * progress),
                    opacity: opacity,
                    headRadius: layer.width * 0.85 * (1 - 0.5 * progress),
                    tone: layer.tone
                ))
            }
        }
        return rays
    }

    /// Closed form of `v' = -kv`, so a spoke's reach never depends on the frame rate.
    private static func radius(speed: Double, age: TimeInterval) -> Double {
        speed * (1 - exp(-Self.drag * age)) / Self.drag
    }

    private static func point(
        origin: CGPoint,
        angle: Double,
        radius: Double,
        age: TimeInterval
    ) -> CGPoint {
        CGPoint(
            x: origin.x + cos(angle) * radius,
            y: origin.y + sin(angle) * radius + 0.5 * Self.gravity * age * age
        )
    }

    // MARK: - Helpers

    /// Cubic bezier easing taking the two control points `cubic-bezier(...)` does, solved the way
    /// WebKit solves it: Newton first, bisection when the curve is too flat for it.
    struct Easing {
        private let ax, bx, cx: Double
        private let ay, by, cy: Double

        init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
            self.cx = 3 * x1
            self.bx = 3 * (x2 - x1) - self.cx
            self.ax = 1 - self.cx - self.bx
            self.cy = 3 * y1
            self.by = 3 * (y2 - y1) - self.cy
            self.ay = 1 - self.cy - self.by
        }

        func callAsFunction(_ x: Double) -> Double {
            self.sampleY(at: self.parameter(for: min(1, max(0, x))))
        }

        private func sampleX(at t: Double) -> Double { ((self.ax * t + self.bx) * t + self.cx) * t }
        private func sampleY(at t: Double) -> Double { ((self.ay * t + self.by) * t + self.cy) * t }
        private func slopeX(at t: Double) -> Double { (3 * self.ax * t + 2 * self.bx) * t + self.cx }

        private func parameter(for x: Double) -> Double {
            var t = x
            for _ in 0..<8 {
                let error = self.sampleX(at: t) - x
                if abs(error) < 1e-6 { return t }
                let slope = self.slopeX(at: t)
                if abs(slope) < 1e-6 { break }
                t -= error / slope
            }
            var low = 0.0
            var high = 1.0
            t = x
            while low < high {
                let sample = self.sampleX(at: t)
                if abs(sample - x) < 1e-6 { return t }
                if x > sample { low = t } else { high = t }
                let next = (high + low) / 2
                if abs(next - t) < 1e-9 { break }
                t = next
            }
            return t
        }
    }

    /// splitmix64. The jitter has to look natural but be identical on every replay, or the demo
    /// would be judging a different shell each time.
    private struct SeededRandom {
        private var state: UInt64

        init(seed: UInt64) { self.state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678 }

        mutating func next(in range: ClosedRange<Double>) -> Double {
            self.state &+= 0x9E37_79B9_7F4A_7C15
            var z = self.state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            let unit = Double(z >> 11) / Double(1 << 53)
            return range.lowerBound + unit * (range.upperBound - range.lowerBound)
        }
    }
}

/// The hidden replay keeps the approved reset choreography intact, then quietly returns the bar
/// to live data. One deterministic timeline avoids delayed callbacks inside an NSMenu run loop.
enum QuotaCelebrationReplay {
    static let returnDuration: TimeInterval = 0.82
    static var duration: TimeInterval { QuotaCelebration.duration + Self.returnDuration }

    private static let minimumOpacity = 0.52

    static func fillPercent(at time: TimeInterval, from start: Double, to target: Double) -> Double {
        let start = min(100, max(0, start))
        let target = min(100, max(0, target))
        guard time > QuotaCelebration.duration else {
            return QuotaCelebration.fillPercent(at: time, from: start, to: 100)
        }
        let progress = Self.returnProgress(at: time)
        return 100 + (target - 100) * Self.smoothStep(progress)
    }

    /// A restrained dissolve makes the change of direction read as an intentional return rather
    /// than a second quota event. The track never vanishes, preserving spatial continuity.
    static func opacity(at time: TimeInterval) -> Double {
        let progress = Self.returnProgress(at: time)
        guard progress > 0, progress < 1 else { return 1 }
        let distanceFromMiddle = abs(progress * 2 - 1)
        return Self.minimumOpacity
            + (1 - Self.minimumOpacity) * Self.smoothStep(distanceFromMiddle)
    }

    private static func returnProgress(at time: TimeInterval) -> Double {
        min(1, max(0, (time - QuotaCelebration.duration) / Self.returnDuration))
    }

    /// Symmetric ease-in/ease-out with zero velocity at both ends.
    private static func smoothStep(_ value: Double) -> Double {
        value * value * (3 - 2 * value)
    }
}
