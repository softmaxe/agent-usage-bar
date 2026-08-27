import AppKit
import SwiftUI

/// Drives a celebration frame by frame. A `Timer` in `.common` mode rather than `TimelineView`:
/// the card lives inside an `NSMenu`, and menu tracking runs the run loop in its own mode where
/// anything scheduled on the default mode never fires.
@MainActor
final class CelebrationClock: ObservableObject {
    /// Seconds into the sequence, or nil when nothing is playing.
    @Published private(set) var elapsed: TimeInterval?

    private var timer: Timer?
    private var startedAt = Date()
    private var duration: TimeInterval = 0
    private var scale: Double = 1

    /// 120 Hz so the sweep is smooth on a ProMotion display; the work per frame is one small
    /// Canvas redraw.
    private static let frameInterval: TimeInterval = 1.0 / 120

    var isRunning: Bool { self.elapsed != nil }

    func start(duration: TimeInterval, timeScale: Double = 1) {
        self.stop()
        self.duration = duration
        self.scale = max(0.01, timeScale)
        self.startedAt = Date()
        self.elapsed = 0

        let timer = Timer(timeInterval: Self.frameInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        self.timer?.invalidate()
        self.timer = nil
        self.elapsed = nil
    }

    private func tick() {
        let time = Date().timeIntervalSince(self.startedAt) * self.scale
        if time >= self.duration {
            self.stop()
        } else {
            self.elapsed = time
        }
    }
}

/// Everything the reset animation draws outside the bar: a glowing head while the fill charges,
/// then one large circular firework on the landing point — core, shockwaves, and corona.
/// One Canvas, no compositing modifiers.
struct QuotaCelebrationLayer: View {
    let elapsed: TimeInterval
    let tint: Color
    let startPercent: Double
    let targetPercent: Double
    /// How far the canvas reaches past each end of the bar, so the shell has room to open.
    let inset: CGFloat

    private static let warm = Color(red: 1, green: 0.83, blue: 0.42)

    var body: some View {
        Canvas { context, size in
            let barWidth = max(0, size.width - self.inset * 2)
            let centre = CGPoint(x: self.inset, y: size.height / 2)

            if self.elapsed < QuotaCelebration.landing {
                let headPercent = QuotaCelebration.fillPercent(
                    at: self.elapsed,
                    from: self.startPercent,
                    to: self.targetPercent
                )
                let headX = centre.x + barWidth * min(100, max(0, headPercent)) / 100
                let pulse = 0.82 + 0.18 * sin(self.elapsed * 22)
                context.fill(
                    Path(ellipseIn: CGRect(x: headX - 8, y: centre.y - 8, width: 16, height: 16)),
                    with: .color(self.tint.opacity(0.12 * pulse))
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: headX - 2.8, y: centre.y - 2.8, width: 5.6, height: 5.6)),
                    with: .color(.white.opacity(0.82 * pulse))
                )
            }

            let origin = CGPoint(x: centre.x + barWidth * QuotaCelebration.originX, y: centre.y)

            if let core = QuotaCelebration.core(at: self.elapsed) {
                context.fill(
                    Path(ellipseIn: Self.box(around: origin, radius: core.glowRadius)),
                    with: .radialGradient(
                        Gradient(colors: [
                            self.tint.opacity(0.35 * core.opacity),
                            self.tint.opacity(0),
                        ]),
                        center: origin,
                        startRadius: 0,
                        endRadius: core.glowRadius
                    )
                )
                context.fill(
                    Path(ellipseIn: Self.box(around: origin, radius: core.radius)),
                    with: .color(.white.opacity(core.opacity))
                )
            }

            for ring in QuotaCelebration.rings(at: self.elapsed) {
                context.stroke(
                    Path(ellipseIn: Self.box(around: origin, radius: ring.radius)),
                    with: .color(self.tint.opacity(ring.opacity)),
                    lineWidth: ring.lineWidth
                )
            }

            for ray in QuotaCelebration.rays(at: self.elapsed, barWidth: barWidth) {
                let color = self.color(for: ray.tone)
                let inner = CGPoint(x: centre.x + ray.inner.x, y: centre.y + ray.inner.y)
                let outer = CGPoint(x: centre.x + ray.outer.x, y: centre.y + ray.outer.y)

                // The streak fades out towards the centre, so the eye follows the heads outwards.
                var streak = Path()
                streak.move(to: inner)
                streak.addLine(to: outer)
                context.stroke(
                    streak,
                    with: .linearGradient(
                        Gradient(colors: [color.opacity(0), color.opacity(ray.opacity * 0.75)]),
                        startPoint: inner,
                        endPoint: outer
                    ),
                    style: StrokeStyle(lineWidth: ray.width, lineCap: .round)
                )
                context.fill(
                    Path(ellipseIn: Self.box(around: outer, radius: ray.headRadius)),
                    with: .color(color.opacity(ray.opacity))
                )
            }
        }
        .allowsHitTesting(false)
    }

    private static func box(around point: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
    }

    private func color(for tone: QuotaCelebration.Tone) -> Color {
        switch tone {
        case .tint: self.tint
        case .warm: Self.warm
        case .white: .white
        }
    }
}
