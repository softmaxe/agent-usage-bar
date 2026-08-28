#if DEBUG
import AgentUsageBarCore
import AppKit
import SwiftUI

/// Frame dumps of the controls whose motion lives in SwiftUI state rather than in a clock the app
/// can hand a time to. The reset animation can be rendered from the shipped views because
/// `QuotaCelebration` is a function of elapsed seconds; a pill driven by two `@State` edges and a
/// `withAnimation` cannot be posed at t = 0.14s from outside.
///
/// So the layouts here are stand-ins. The timing is not: every duration, curve, spring and stagger
/// is read from the same `TabSwitchMotion`, `DisclosureMotion` and `CostChartHoverMotion` the real
/// controls animate on, and the curve sampler solves the same cubic Bézier the verifier walks.
/// Change a constant in one of those and these strips change with it. Change the shipped layout and
/// they will not, which is the cost of doing it this way.
@MainActor
enum MotionFilmStrip {
    /// 25 frames a second, which is 40ms per frame. A GIF stores its delay in hundredths, so this
    /// is a whole number of them and the export plays at the speed the app runs at rather than at
    /// whatever the rounding produced.
    private static let step: TimeInterval = 1.0 / 25

    // MARK: - Curve sampling

    /// The `.timingCurve(0.16, 1, 0.3, 1, …)` both `DisclosureMotion.openCurve` and the tab pill
    /// run on, solved for a moment in time. `TabSwitchMotion` already owns the solver.
    static func curve(_ time: TimeInterval, duration: TimeInterval) -> Double {
        TabSwitchMotion.progress(at: time, duration: duration)
    }

    /// SwiftUI's `.spring(response:dampingFraction:)` is a damped harmonic oscillator with
    /// ω₀ = 2π / response and ζ = dampingFraction, released from rest. This is that solution.
    static func spring(_ time: TimeInterval, response: TimeInterval, damping: Double) -> Double {
        guard time > 0 else { return 0 }
        let omega = 2 * Double.pi / max(response, 0.0001)
        let zeta = max(0, damping)
        if zeta < 1 {
            let damped = omega * (1 - zeta * zeta).squareRoot()
            let envelope = exp(-zeta * omega * time)
            return 1 - envelope * (cos(damped * time) + (zeta * omega / damped) * sin(damped * time))
        }
        // Critically damped, which is what the chart's trip home to today uses.
        return 1 - exp(-omega * time) * (1 + omega * time)
    }

    // MARK: - Shared

    private static func write(
        _ view: some View,
        frame index: Int,
        into root: URL
    ) {
        OffscreenCapture.renderPNG(
            view.environment(\.colorScheme, .dark),
            named: String(format: "frame-%04d", index),
            into: root
        )
    }

    // MARK: - Settings tab pill

    /// `--dump-tab-switch <dir>`: General to Pricing and back, on the two edge durations the real
    /// pill uses. The whole point is the gap between them, so the hold at each end is short.
    static func dumpTabSwitch(directory: String) {
        let root = OffscreenCapture.directory(directory)
        let travel = max(TabSwitchMotion.leadDuration, TabSwitchMotion.trailDuration)
        let hold: TimeInterval = 0.55

        var index = 0
        for movingRight in [true, false] {
            var time: TimeInterval = 0
            while time < travel + hold {
                Self.write(
                    TabPillFrame(elapsed: min(time, travel), movingRight: movingRight),
                    frame: index,
                    into: root
                )
                time += Self.step
                index += 1
            }
        }
        print("wrote \(index) tab switch frames to \(root.path)")
    }

    // MARK: - Pricing disclosure

    /// `--dump-disclosure <dir>`: a group unfolding four rows on the open curve, one stagger beat
    /// apart, with the control taking the press spring on the way in.
    static func dumpDisclosure(directory: String) {
        let root = OffscreenCapture.directory(directory)
        let rows = 4
        let opening = DisclosureMotion.openDuration + DisclosureMotion.rowDelay(index: rows - 1)
        let hold: TimeInterval = 0.7

        var index = 0
        for isOpening in [true, false] {
            var time: TimeInterval = 0
            while time < opening + hold {
                Self.write(
                    DisclosureFrame(elapsed: time, isOpening: isOpening, rows: rows),
                    frame: index,
                    into: root
                )
                time += Self.step
                index += 1
            }
        }
        print("wrote \(index) disclosure frames to \(root.path)")
    }

    // MARK: - Cost chart highlight

    /// `--dump-chart-motion <dir>`: the highlight moving between bars on the hover spring, then
    /// home to today on the critically damped one. Both carry the 5pt lift with the tone.
    static func dumpChartMotion(directory: String) {
        let root = OffscreenCapture.directory(directory)
        // Where the pointer goes, and whether that move is a hover or the trip home. The last
        // entry returns to today, which is the only one that is not chasing a pointer.
        let moves: [(from: Int, to: Int, returning: Bool)] = [
            (7, 1, false),
            (1, 2, false),
            (2, 5, false),
            (5, 7, true),
        ]

        var index = 0
        for move in moves {
            let response = move.returning
                ? CostChartHoverMotion.returnResponse
                : CostChartHoverMotion.hoverResponse
            let damping = move.returning
                ? CostChartHoverMotion.returnDamping
                : CostChartHoverMotion.hoverDamping
            // Long enough for the envelope to be invisible: e^(-ζω₀t) under a thousandth.
            let settle = response * 1.6
            var time: TimeInterval = 0
            while time < settle {
                let progress = Self.spring(time, response: response, damping: damping)
                Self.write(
                    ChartHighlightFrame(
                        from: Double(move.from),
                        to: Double(move.to),
                        progress: progress
                    ),
                    frame: index,
                    into: root
                )
                time += Self.step
                index += 1
            }
        }
        print("wrote \(index) chart motion frames to \(root.path)")
    }
}

// MARK: - Frames

/// The two edges of the selection pill, each on its own duration. Segment widths are fixed here
/// rather than measured from the labels, which is the one thing the real control does differently.
private struct TabPillFrame: View {
    let elapsed: TimeInterval
    let movingRight: Bool

    private static let segments: [(title: String, width: CGFloat)] = [
        ("General", 92), ("Pricing", 88),
    ]
    private static let gap: CGFloat = 2
    private static let height: CGFloat = 28

    private var bounds: [(minX: CGFloat, maxX: CGFloat)] {
        var x: CGFloat = 0
        return Self.segments.map { segment in
            let rect = (minX: x, maxX: x + segment.width)
            x += segment.width + Self.gap
            return rect
        }
    }

    private var pill: (minX: CGFloat, maxX: CGFloat) {
        let source = self.bounds[self.movingRight ? 0 : 1]
        let destination = self.bounds[self.movingRight ? 1 : 0]
        let durations = TabSwitchMotion.edgeDurations(movingRight: self.movingRight)
        let minX = MotionFilmStrip.curve(self.elapsed, duration: durations.minX)
        let maxX = MotionFilmStrip.curve(self.elapsed, duration: durations.maxX)
        return (
            minX: source.minX + (destination.minX - source.minX) * minX,
            maxX: source.maxX + (destination.maxX - source.maxX) * maxX
        )
    }

    /// The label weights trade places on the open curve, the way the real segments cross-fade a
    /// semibold copy over a regular one.
    private func selectedness(_ index: Int) -> Double {
        let arriving = MotionFilmStrip.curve(self.elapsed, duration: DisclosureMotion.openDuration)
        let destination = self.movingRight ? 1 : 0
        return index == destination ? arriving : 1 - arriving
    }

    var body: some View {
        let pill = self.pill
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor)
                .frame(width: pill.maxX - pill.minX, height: Self.height)
                .offset(x: pill.minX)

            HStack(spacing: Self.gap) {
                ForEach(Array(Self.segments.enumerated()), id: \.offset) { index, segment in
                    ZStack {
                        Text(segment.title).font(.system(size: 13, weight: .semibold))
                            .opacity(self.selectedness(index))
                        Text(segment.title).font(.system(size: 13, weight: .regular))
                            .opacity(1 - self.selectedness(index))
                    }
                    .foregroundStyle(Color.white.opacity(0.55 + 0.45 * self.selectedness(index)))
                    .frame(width: segment.width, height: Self.height)
                }
            }
        }
        .frame(width: 320, height: 76)
        .background(Color(white: 0.13))
    }
}

/// A pricing group unrolling its rows. Row height, stagger and the chevron's quarter turn are the
/// shipped numbers; the row contents are a sketch of the real table.
private struct DisclosureFrame: View {
    let elapsed: TimeInterval
    let isOpening: Bool
    let rows: Int

    private static let names = ["claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5", "claude-fable-5"]
    private static let rates = [("5", "25"), ("2", "10"), ("0.5", "2.5"), ("10", "50")]
    private static let rowHeight: CGFloat = 34

    /// How far a row has arrived, 0...1. Closing runs the same curve backwards, and without the
    /// stagger: a group folding away is one movement, not four.
    private func arrival(_ index: Int) -> Double {
        guard self.isOpening else {
            return 1 - MotionFilmStrip.curve(self.elapsed, duration: DisclosureMotion.openDuration)
        }
        let delay = DisclosureMotion.rowDelay(index: index)
        return MotionFilmStrip.curve(self.elapsed - delay, duration: DisclosureMotion.openDuration)
    }

    private var openness: Double {
        self.isOpening
            ? MotionFilmStrip.curve(self.elapsed, duration: DisclosureMotion.openDuration)
            : 1 - MotionFilmStrip.curve(self.elapsed, duration: DisclosureMotion.openDuration)
    }

    /// The control dips under the pointer and comes back on the settle spring. Only the control:
    /// a table that overshoots its own height pushes every row below it.
    private var pressScale: Double {
        let press = MotionFilmStrip.spring(
            self.elapsed,
            response: DisclosureMotion.pressResponse,
            damping: DisclosureMotion.pressDamping
        )
        return 0.94 + 0.06 * press
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(90 * self.openness))
                Text("Claude").font(.system(size: 13, weight: .semibold))
                Text("\(self.rows)")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.12)))
                Spacer(minLength: 0)
            }
            .scaleEffect(self.pressScale, anchor: .leading)
            .frame(height: 30)

            ForEach(0..<self.rows, id: \.self) { index in
                let arrival = self.arrival(index)
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(Self.names[index]).font(.system(size: 12))
                    Spacer(minLength: 0)
                    ForEach([Self.rates[index].0, Self.rates[index].1], id: \.self) { rate in
                        Text(rate)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 54, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                            )
                    }
                }
                .padding(.leading, 14)
                .frame(height: Self.rowHeight * arrival)
                .opacity(arrival)
                .clipped()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 420, height: 200, alignment: .top)
        .background(Color(white: 0.13))
    }
}

/// The chart's highlight between two bars. Tone and the 5pt lift cross over together, because the
/// highlight is meant to read as one shape moving rather than as one bar dimming and another
/// brightening.
private struct ChartHighlightFrame: View {
    let from: Double
    let to: Double
    let progress: Double

    private static let values: [Double] = [62, 90, 48, 71, 9, 88, 41, 37]
    private static let days = ["Aug 17", "Aug 18", "Aug 19", "Aug 20", "Aug 21", "Aug 22", "Aug 23", "Aug 24"]
    private static let barWidth: CGFloat = 30
    private static let maxHeight: CGFloat = 84

    private var position: Double { self.from + (self.to - self.from) * self.progress }

    /// How highlighted one bar is: 1 when the moving position is on it, 0 a whole bar away.
    private func share(_ index: Int) -> Double {
        max(0, 1 - abs(self.position - Double(index)))
    }

    /// The label belongs to whichever bar the highlight is closest to, so it never reads out a
    /// day the highlight has already left.
    private var label: String {
        let index = min(Self.values.count - 1, max(0, Int(self.position.rounded())))
        return "\(Self.days[index]) · $\(Int(Self.values[index])).00 · \(Int(Self.values[index]))M tokens"
    }

    var body: some View {
        let tint = Theme.accent(for: .claude)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(Self.values.enumerated()), id: \.offset) { index, value in
                    let share = self.share(index)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(tint.opacity(0.45 + 0.55 * share))
                        .frame(
                            width: Self.barWidth,
                            height: Self.maxHeight * value / 90 + CostChartHoverMotion.lift * share
                        )
                }
            }
            Text(self.label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .opacity(0.9)
        }
        .padding(18)
        .frame(width: 340, height: 160, alignment: .bottomLeading)
        .background(Color(white: 0.13))
    }
}
#endif
