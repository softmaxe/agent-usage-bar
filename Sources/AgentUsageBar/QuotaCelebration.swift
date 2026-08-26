import CoreGraphics
import Foundation

/// One quota window. Also the key a drained window is remembered under, so the celebration can
/// survive the app being restarted between running dry and the window rolling over.
enum QuotaWindowKind: String, Hashable, CaseIterable {
    case session
    case weekly
}

/// Choreography for the "the quota came back" animation: the fill sweeps in from empty, the bar
/// pops as the head lands, a ring goes out from it, and three shells of sparks burst over the
/// card. Written as pure functions of elapsed time so the curves can be asserted without running
/// an animation, and so the demo window and the menu card share exactly one set of timings.
enum QuotaCelebration {
    // MARK: - Timeline

    /// The head covers most of the bar in the first third of this and spends the rest easing the
    /// last few points closed.
    static let sweepDuration: TimeInterval = 1.05
    /// When the fill is close enough to 100 that it has stopped moving to the eye. The pop, the
    /// flash and the ring all hang off this rather than off the end of the crawl.
    static let landing: TimeInterval = 0.92
    /// How long the bar keeps springing after the head lands.
    static let popDuration: TimeInterval = 0.72
    /// The fill washes bright at the moment of landing and cools back to the tint.
    static let flashDuration: TimeInterval = 0.44
    static let ringDuration: TimeInterval = 0.58
    /// Longest a spark can live; each one picks a shorter life than this.
    static let sparkLife: TimeInterval = 1.05

    /// When the last spark of the last shell has faded, and therefore when the clock stops.
    static var duration: TimeInterval {
        max(
            Self.landing + max(Self.popDuration, Self.ringDuration),
            (Self.shells.map(\.time).max() ?? 0) + Self.sparkLife
        )
    }

#if DEBUG
    /// The demo window slows the whole sequence down, so a 60 ms overshoot can be judged by eye.
    static var timeScale: Double = 1
#endif

    // MARK: - Fill

    /// Off the mark fast, already slowing by the middle, and closing the last few points slowly
    /// enough to be watched. No ease-in at all: the bar is meant to leap, then be placed.
    private static let sweepEasing = Easing(0.2, 0.95, 0.34, 1)

    /// Share of the final percentage the bar shows, 0...1.
    static func fillFraction(at time: TimeInterval) -> Double {
        guard time > 0 else { return 0 }
        guard time < Self.sweepDuration else { return 1 }
        return Self.sweepEasing(time / Self.sweepDuration)
    }

    /// A bright edge riding the head of the fill. Fades out as the head arrives so the landing
    /// reads as the flash, not as the shine stopping.
    static func headShineOpacity(at time: TimeInterval) -> Double {
        guard time > 0 else { return 0 }
        let fadeIn = min(1, time / 0.06)
        let remaining = Self.landing - time
        guard remaining > 0 else { return 0 }
        return fadeIn * min(1, remaining / 0.16)
    }

    /// The whole fill washing white at the moment of landing.
    static func flashOpacity(at time: TimeInterval) -> Double {
        let age = time - Self.landing
        guard age >= 0, age < Self.flashDuration else { return 0 }
        return 0.32 * pow(1 - age / Self.flashDuration, 1.7)
    }

    // MARK: - Pop

    /// Scale for the bar itself. Height carries the pop — a 6 pt pill widening reads as a glitch,
    /// while the same pill growing taller reads as a bounce.
    static func barScale(at time: TimeInterval) -> CGSize {
        let age = time - Self.landing
        guard age >= 0, age < Self.popDuration else { return CGSize(width: 1, height: 1) }
        // A damped sine: zero at the landing, one overshoot, then it settles instead of snapping.
        let pulse = exp(-6.2 * age) * sin(2 * .pi * 1.85 * age)
        return CGSize(width: 1 + 0.05 * pulse, height: 1 + 0.62 * pulse)
    }

    // MARK: - Ring

    struct Ring: Equatable {
        let radius: CGFloat
        let lineWidth: CGFloat
        let opacity: Double
    }

    /// Where along the bar the ring is centred — the same place the last shell goes off, a hair
    /// short of the end so the card's edge does not cut the whole right half of it away.
    static let ringOriginX: Double = 0.97

    /// The shockwave leaving the point where the head landed.
    static func ring(at time: TimeInterval) -> Ring? {
        let age = time - Self.landing
        guard age >= 0, age < Self.ringDuration else { return nil }
        let progress = age / Self.ringDuration
        let eased = 1 - pow(1 - progress, 2.6)
        return Ring(
            radius: 3 + 24 * eased,
            lineWidth: 2.1 * (1 - progress) + 0.35,
            opacity: 0.5 * pow(1 - progress, 1.5)
        )
    }

    // MARK: - Sparks

    enum SparkTone: Equatable {
        /// The provider's own accent, so the burst still belongs to the card.
        case tint
        case warm
        case white
    }

    /// Bar-local: `x` measured from the bar's left edge, `y` from its centre, positive downwards.
    struct Spark: Equatable {
        let position: CGPoint
        /// Where the spark was a few frames ago, which is what the streak is drawn along.
        let previous: CGPoint
        let radius: CGFloat
        let opacity: Double
        let tone: SparkTone
    }

    private struct Shell {
        /// Seconds from the start of the whole sequence, not from the landing: the first two
        /// shells go off while the fill is still on its way.
        let time: TimeInterval
        /// Fraction of the bar width the shell goes off at.
        let originX: Double
        let originY: CGFloat
        let count: Int
        let speed: ClosedRange<Double>
        /// Sideways bias. The shell at the head of the bar leans back over the card, because the
        /// card's own edge is only a few points to the right of it.
        let driftX: Double
        let seed: UInt64
    }

    /// Three shells rather than one: a single burst reads as a particle effect, a staggered set
    /// reads as fireworks. They walk the bar the way the fill does — left, then high over the
    /// middle, then on the 100 mark as the fill arrives there.
    private static let shells: [Shell] = [
        Shell(time: 0.08, originX: 0.06, originY: -7, count: 16, speed: 45...125, driftX: 16, seed: 0x1F3B_7C5D),
        Shell(time: 0.38, originX: 0.5, originY: -24, count: 21, speed: 55...155, driftX: 0, seed: 0x7C5D_1F3B),
        Shell(time: Self.landing, originX: 0.97, originY: 0, count: 24, speed: 55...170, driftX: -34, seed: 0x9E37_79B9),
    ]

    /// Air drag, so sparks decelerate instead of flying off in straight lines.
    private static let drag: Double = 3.2
    /// Points per second squared, positive downwards.
    private static let gravity: Double = 250
    /// How far back the streak behind a spark reaches.
    private static let trailSeconds: TimeInterval = 0.05

    static func sparks(at time: TimeInterval, barWidth: CGFloat) -> [Spark] {
        var sparks: [Spark] = []
        for shell in Self.shells {
            let age = time - shell.time
            guard age >= 0 else { continue }
            var random = SeededRandom(seed: shell.seed)
            let origin = CGPoint(x: Double(barWidth) * shell.originX, y: Double(shell.originY))
            for _ in 0..<shell.count {
                let angle = random.next(in: 0...(2 * .pi))
                let speed = random.next(in: shell.speed)
                // Nudged upwards: a burst that rises before gravity takes it reads as a firework
                // rather than as something spilling out of the bar.
                let velocity = CGVector(
                    dx: cos(angle) * speed + shell.driftX,
                    dy: sin(angle) * speed - 34
                )
                let life = Self.sparkLife * random.next(in: 0.62...1)
                let radius = random.next(in: 0.95...2.25)
                let phase = random.next(in: 0...(2 * .pi))
                let tone = Self.tone(&random)
                guard age < life else { continue }
                let progress = age / life
                let position = Self.displaced(origin: origin, velocity: velocity, age: age)
                let previous = Self.displaced(
                    origin: origin,
                    velocity: velocity,
                    age: max(0, age - Self.trailSeconds)
                )
                // Twinkle keeps a static-looking cloud of dots alive while it falls.
                let twinkle = 0.74 + 0.26 * sin(age * 17 + phase)
                sparks.append(Spark(
                    position: position,
                    previous: previous,
                    radius: radius * (1 - 0.35 * progress),
                    opacity: min(1, age / 0.04) * pow(1 - progress, 1.45) * twinkle,
                    tone: tone
                ))
            }
        }
        return sparks
    }

    private static func tone(_ random: inout SeededRandom) -> SparkTone {
        switch random.next(in: 0...1) {
        case ..<0.55: .tint
        case ..<0.82: .warm
        default: .white
        }
    }

    /// Closed form of `v' = -kv + g`, so a spark's position never depends on the frame rate.
    private static func displaced(origin: CGPoint, velocity: CGVector, age: TimeInterval) -> CGPoint {
        let decay = (1 - exp(-Self.drag * age)) / Self.drag
        let terminal = Self.gravity / Self.drag
        return CGPoint(
            x: origin.x + velocity.dx * decay,
            y: origin.y + (velocity.dy - terminal) * decay + terminal * age
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

    /// splitmix64. The burst has to look scattered but land in the same place every replay, or
    /// the demo would be judging a different animation each time.
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
