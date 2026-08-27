import CoreGraphics
import Foundation

/// One quota window. It also keeps five-hour and weekly reset tracking independent.
enum QuotaWindowKind: String, Hashable, CaseIterable {
    case session
    case weekly
}

/// Choreography for a quota reset: the fill resumes from the last pre-reset reading, continuously
/// slows into 100%, and carries charging motes along its head. The landing synchronizes the bar
/// pop, flash, ring, and only firework burst.
enum QuotaCelebration {
    // MARK: - Timeline

    /// One continuous exponential decay drives the fill all the way to its destination.
    static let landing: TimeInterval = 2.8
    static let sweepDuration = Self.landing
    /// How long the bar keeps springing after the head lands.
    static let popDuration: TimeInterval = 0.78
    /// The fill washes bright at the moment of landing and cools back to the tint.
    static let flashDuration: TimeInterval = 0.48
    static let ringDuration: TimeInterval = 0.62
    /// Longest a spark can live; each one picks a shorter life than this.
    static let sparkLife: TimeInterval = 0.85

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

    // MARK: - Ring

    struct Ring: Equatable {
        let radius: CGFloat
        let lineWidth: CGFloat
        let opacity: Double
    }

    /// Where along the bar the ring is centred — the same place the last shell goes off, a hair
    /// short of the end so the card's edge does not cut the whole right half of it away.
    static let ringOriginX: Double = 0.985

    /// The shockwave leaving the point where the head landed.
    static func ring(at time: TimeInterval) -> Ring? {
        let age = time - Self.landing
        guard age >= 0, age < Self.ringDuration else { return nil }
        let progress = age / Self.ringDuration
        let eased = 1 - pow(1 - progress, 2.5)
        return Ring(
            radius: 4 + 26 * eased,
            lineWidth: 2.3 * (1 - progress) + 0.3,
            opacity: 0.55 * pow(1 - progress, 1.5)
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
        /// Seconds from the start of the whole sequence.
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

    /// Charging motes carry the motion; fireworks are reserved for the synchronized landing.
    private static let shells: [Shell] = [
        Shell(time: Self.landing, originX: Self.ringOriginX, originY: 0, count: 25, speed: 55...170, driftX: -34, seed: 0x9E37_79B9),
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

    /// Small motes stream into the moving head for the whole charge. They use the same tint,
    /// warm, and white palette as the landing burst, but never fan out like fireworks.
    static func chargeMotes(
        at time: TimeInterval,
        barWidth: CGFloat,
        startPercent: Double,
        targetPercent: Double
    ) -> [Spark] {
        guard time >= 0, time < Self.landing else { return [] }
        let start = min(1, max(0, startPercent / 100))
        let target = min(1, max(0, targetPercent / 100))
        let head = start + (target - start) * Self.fillFraction(at: time)
        let startX = Double(barWidth) * start
        let headX = Double(barWidth) * head

        return (0..<7).map { index in
            let rate = 2.1 + Double(index) * 0.17
            let phase = (time * rate + Double(index) * 0.137).truncatingRemainder(dividingBy: 1)
            let distance = 8 + phase * 46
            let x = max(startX, headX - distance)
            let spread = 4.5 + Double(index % 3) * 2.1
            let y = sin(time * 17 + Double(index) * 2.3) * spread
            let opacity = sin(phase * .pi) * 0.76
            let radius = 0.8 + Double(index % 3) * 0.28
            let tone: SparkTone = switch index % 3 {
            case 0: .tint
            case 1: .warm
            default: .white
            }
            return Spark(
                position: CGPoint(x: x, y: y),
                previous: CGPoint(x: max(startX, x - (4 + phase * 5)), y: y),
                radius: radius,
                opacity: opacity,
                tone: tone
            )
        }
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
