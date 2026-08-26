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

/// Everything the celebration draws outside the bar: the ring leaving the point where the fill
/// landed, and the shells of sparks over it. One Canvas, no compositing modifiers — the same
/// constraint the bar itself is drawn under.
struct QuotaCelebrationLayer: View {
    let elapsed: TimeInterval
    let tint: Color
    /// How far the canvas reaches past each end of the bar, so sparks can fly off it.
    let inset: CGFloat

    private static let warm = Color(red: 1, green: 0.83, blue: 0.42)

    var body: some View {
        Canvas { context, size in
            let barWidth = max(0, size.width - self.inset * 2)
            let centre = CGPoint(x: self.inset, y: size.height / 2)

            if let ring = QuotaCelebration.ring(at: self.elapsed) {
                let origin = CGPoint(x: centre.x + barWidth * QuotaCelebration.ringOriginX, y: centre.y)
                let box = CGRect(
                    x: origin.x - ring.radius,
                    y: origin.y - ring.radius,
                    width: ring.radius * 2,
                    height: ring.radius * 2
                )
                context.stroke(
                    Path(ellipseIn: box),
                    with: .color(self.tint.opacity(ring.opacity)),
                    lineWidth: ring.lineWidth
                )
            }

            for spark in QuotaCelebration.sparks(at: self.elapsed, barWidth: barWidth) {
                guard spark.opacity > 0.01, spark.radius > 0.05 else { continue }
                let color = self.color(for: spark.tone)
                let point = CGPoint(x: centre.x + spark.position.x, y: centre.y + spark.position.y)
                let tail = CGPoint(x: centre.x + spark.previous.x, y: centre.y + spark.previous.y)

                // Streak first, dot on top: the dot is the spark, the streak is where it has been.
                var trail = Path()
                trail.move(to: tail)
                trail.addLine(to: point)
                context.stroke(
                    trail,
                    with: .color(color.opacity(spark.opacity * 0.45)),
                    style: StrokeStyle(lineWidth: spark.radius * 0.9, lineCap: .round)
                )
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: point.x - spark.radius,
                        y: point.y - spark.radius,
                        width: spark.radius * 2,
                        height: spark.radius * 2
                    )),
                    with: .color(color.opacity(spark.opacity))
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func color(for tone: QuotaCelebration.SparkTone) -> Color {
        switch tone {
        case .tint: self.tint
        case .warm: Self.warm
        case .white: .white
        }
    }
}
