#if DEBUG
import AgentUsageBarCore
import AppKit
import SwiftUI

/// `AgentUsageBar --demo-bar-hover` puts the candidate hover treatments for the cost chart side by
/// side. Every card is the production chart -- same bars, same hit testing, same rule that today
/// owns the highlight whenever the pointer is away -- so the only thing under judgement is how the
/// highlight travels between bars and how it finds its way home when the pointer leaves.
@MainActor
enum BarHoverDemo {
    static func run() -> Never {
        DemoWindow.run(
            title: "Cost chart hover prototypes",
            width: 1000,
            height: 820,
            content: BarHoverDemoView()
        )
    }
}

// MARK: - Timings

/// The two events being timed. A hover is the pointer's own motion and has to keep up with it; the
/// return to today is not something the reader asked for frame by frame, so it may take longer and
/// arrive with zero velocity -- the shape `QuotaCelebrationReplay` already uses to come back from
/// the landing.
private enum HoverMotion {
    static let hover: TimeInterval = 0.14
    static let returning: TimeInterval = 0.34
}

// MARK: - Variants

private enum HoverStyle: String, CaseIterable, Identifiable {
    /// Only the tone changes, on a curve instead of instantly. The baseline.
    case crossfade
    /// The selected bar also stands up a little, so the highlight has a shape as well as a tone.
    case lift
    /// The same stand-up, taken on the reset landing's damped sine, plus its flash.
    case landing
    /// One highlight, and it travels: the tone and the label glide from the old bar to the new one.
    case travel
    /// Tone step plus the reset's bloom, sized for a bar, rising behind the selection.
    case bloom

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .crossfade: "A · Tone crossfade"
        case .lift: "B · Lift — shipped"
        case .landing: "C · Landing pop"
        case .travel: "D · Traveling highlight"
        case .bloom: "E · Warm bloom"
        }
    }

    var blurb: String {
        switch self {
        case .crossfade:
            "Today's bar fades down as the hovered one comes up. Nothing moves, so the chart is "
                + "as still under the pointer as it is at rest; the return is the same fade, "
                + "slower."
        case .lift:
            "The selection grows 5 pt from the bottom on a spring that does not overshoot. The "
                + "highlight reads as a shape, not only a tone, and the label rides up with it."
        case .landing:
            "The same stand-up on the reset's damped sine — one overshoot, then it settles — with "
                + "the bar washing bright on arrival the way the fill does when it lands."
        case .travel:
            "There is only ever one highlight and it moves. Tone, height, and label interpolate "
                + "from bar to bar; leaving the chart sends it back across the chart to today."
        case .bloom:
            "Tone step plus the landing's wide glow, sized for a single bar. The bar itself never "
                + "moves; what says 'selected' is the warmth rising behind it."
        }
    }

    func hoverAnimation(speed: Double) -> Animation {
        let duration = CostChartHoverMotion.scaled(HoverMotion.hover, timeScale: speed)
        switch self {
        case .crossfade: return .easeOut(duration: duration)
        // B shipped, so it is driven by the production curve rather than a copy of its numbers.
        case .lift: return CostChartHoverMotion.hoverAnimation(timeScale: speed)
        // Low damping is the point: this is the bar's own overshoot-then-settle, scaled down.
        case .landing: return .spring(response: duration * 2.1, dampingFraction: 0.55)
        case .travel: return .spring(response: duration * 2.3, dampingFraction: 0.92)
        case .bloom: return .easeOut(duration: duration * 1.15)
        }
    }

    func returnAnimation(speed: Double) -> Animation {
        let duration = CostChartHoverMotion.scaled(HoverMotion.returning, timeScale: speed)
        switch self {
        case .crossfade: return .easeInOut(duration: duration)
        case .lift: return CostChartHoverMotion.returnAnimation(timeScale: speed)
        case .landing: return .spring(response: duration * 0.95, dampingFraction: 0.85)
        // Longer than the hover spring: the trip home is longer than any trip between neighbours.
        case .travel: return .spring(response: duration * 1.15, dampingFraction: 1)
        case .bloom: return .easeInOut(duration: duration * 1.2)
        }
    }

    /// How the label arrives on a bar. The traveling variant has no transition at all — its label
    /// is never inserted or removed, it is moved.
    var labelTransition: AnyTransition {
        switch self {
        case .crossfade, .bloom: .opacity
        case .lift: CostChartHoverMotion.labelTransition
        case .landing: .scale(scale: 0.9, anchor: .bottom).combined(with: .opacity)
        case .travel: .identity
        }
    }
}

// MARK: - Window

private struct BarHoverDemoView: View {
    @State private var provider: Provider = .codex
    @State private var speed: Double = 1
    @State private var labelMode: CostChartLabelMode = .cost

    private static let speeds: [(String, Double)] = [("1×", 1), ("0.5×", 0.5), ("0.25×", 0.25)]

    private static let columns = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18),
    ]

    private let days = CostChartDemoData.days()
    private let todayDayKey = CostChartDemoData.todayDayKey()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            self.header
            self.controls

            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: 18) {
                    ForEach(HoverStyle.allCases) { style in
                        HoverVariantCard(
                            style: style,
                            provider: self.provider,
                            days: self.days,
                            todayDayKey: self.todayDayKey,
                            labelMode: self.labelMode,
                            speed: self.speed
                        )
                    }
                }
                .padding(.bottom, 4)
            }

            Text(
                "Move the pointer across a chart to compare bar-to-bar hover; move it off the "
                    + "chart to compare the return to today. Hover is timed at "
                    + "\(Int(HoverMotion.hover * 1000)) ms, the return at "
                    + "\(Int(HoverMotion.returning * 1000)) ms."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("COST CHART / HOVER STUDY")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Text("The highlight should move, not blink.")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Picker("Provider", selection: self.$provider) {
                ForEach(Provider.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 190)

            Picker("Label", selection: self.$labelMode) {
                Text("Cost").tag(CostChartLabelMode.cost)
                Text("Tokens").tag(CostChartLabelMode.tokens)
            }
            .pickerStyle(.segmented)
            .frame(width: 150)

            Picker("Speed", selection: self.$speed) {
                ForEach(Self.speeds, id: \.1) { Text($0.0).tag($0.1) }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
        }
        .labelsHidden()
    }
}

// MARK: - One card

private struct HoverVariantCard: View {
    let style: HoverStyle
    let provider: Provider
    let days: [CostDay]
    let todayDayKey: String
    let labelMode: CostChartLabelMode
    let speed: Double

    var body: some View {
        DemoVariantCard(title: self.style.title, blurb: self.style.blurb) {
            HoverChart(
                style: self.style,
                provider: self.provider,
                days: self.days,
                todayDayKey: self.todayDayKey,
                labelMode: self.labelMode,
                speed: self.speed
            )
        }
    }
}

// MARK: - The chart under test

/// The production chart, with one treatment applied. Bar geometry, hit testing, and the
/// today-wins-when-idle rule all come from `CostChartHighlightPolicy`, so a variant can only
/// change how a change of selection is drawn, never which bar is selected.
private struct HoverChart: View {
    let style: HoverStyle
    let provider: Provider
    let days: [CostDay]
    let todayDayKey: String
    let labelMode: CostChartLabelMode
    let speed: Double

    @State private var hoveredDayKey: String?
    /// The landing variant's flash, set to 1 on arrival and decayed back to 0.
    @State private var arrivalFlash: Double = 0
    @Namespace private var namespace

    private static let chartHeight: CGFloat = 56
    private static let barSpacing: CGFloat = 4
    private static let lift: CGFloat = CostChartHoverMotion.lift

    private var tint: Color { Theme.accent(for: self.provider) }

    private var selectedDayKey: String? {
        CostChartHighlightPolicy.selectedDayKey(
            hoveredDayKey: self.hoveredDayKey,
            todayDayKey: self.todayDayKey,
            availableDayKeys: Set(self.days.map(\.dayKey))
        )
    }

    private var maxValue: Double {
        self.days.map { $0.costUSD ?? 0 }.max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: Self.barSpacing) {
                ForEach(self.days, id: \.dayKey) { day in
                    self.bar(for: day)
                }
            }
            .frame(height: Self.chartHeight)
            .padding(.top, 18)
            .mouseLocation(onMoved: self.updateHover)

            Text(self.summaryLine)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(height: 14, alignment: .leading)
        }
    }

    private func bar(for day: CostDay) -> some View {
        let selected = day.dayKey == self.selectedDayKey
        let ratio = self.maxValue > 0 ? (day.costUSD ?? 0) / self.maxValue : 0
        let height = max(4, Self.chartHeight * ratio) + (selected ? self.liftAmount : 0)

        return RoundedRectangle(cornerRadius: 2)
            .fill(self.tint)
            // Opacity as a modifier rather than inside the fill, so it is a plain animatable value.
            .opacity(selected && self.style != .travel ? 1 : CostChartHighlightPolicy.restingOpacity)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background(alignment: .bottom) {
                if selected, self.style == .bloom {
                    BarBloom(tint: self.tint)
                        .frame(height: height + 34)
                        .transition(.opacity)
                }
            }
            .overlay {
                // The landing's flash, drawn inside the bar so it inherits the rounded ends.
                if selected, self.style == .landing, self.arrivalFlash > 0.01 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.38 * self.arrivalFlash))
                }
            }
            .overlay(alignment: .top) {
                // One traveling highlight: the same view moves between bars instead of one view
                // fading out while another fades in.
                if selected, self.style == .travel {
                    self.travelingHighlight(height: height, label: self.labelText(for: day))
                }
            }
            .overlay(alignment: .top) {
                if selected, self.style != .travel, let text = self.labelText(for: day) {
                    Self.label(text)
                        .offset(y: -14)
                        .transition(self.style.labelTransition)
                }
            }
    }

    private var liftAmount: CGFloat {
        switch self.style {
        case .lift, .landing: Self.lift
        case .crossfade, .travel, .bloom: 0
        }
    }

    private func travelingHighlight(height: CGFloat, label: String?) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(self.tint)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) {
                if let label {
                    Self.label(label)
                        .offset(y: -14)
                }
            }
            .matchedGeometryEffect(id: "travelingHighlight", in: self.namespace)
    }

    private static func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.primary)
            .fixedSize()
    }

    private func labelText(for day: CostDay) -> String? {
        CostChartHighlightPolicy.labelText(
            dayKey: day.dayKey,
            selectedDayKey: self.selectedDayKey,
            selectedMode: self.labelMode,
            tokens: day.tokens.total,
            costUSD: day.costUSD
        )
    }

    private var summaryLine: String {
        guard let key = self.selectedDayKey, let day = self.days.first(where: { $0.dayKey == key })
        else { return "hover a bar for a day" }
        let suffix = key == self.todayDayKey && self.hoveredDayKey == nil ? " · today" : ""
        return "\(Formatters.dayLabel(key)) · \(Formatters.cost(day.costUSD ?? 0))\(suffix)"
    }

    // MARK: - Hover

    private func updateHover(at location: CGPoint?, width: CGFloat) {
        let nextKey: String?
        if let location, !self.days.isEmpty, width > 0 {
            let index = CostChartHighlightPolicy.barIndex(
                atX: location.x,
                width: width,
                barCount: self.days.count,
                spacing: Self.barSpacing
            )
            nextKey = CostChartHighlightPolicy.hoveredDayKey(
                afterMovingTo: index.map { self.days[$0].dayKey },
                currentDayKey: self.hoveredDayKey
            )
        } else {
            nextKey = nil
        }
        guard nextKey != self.hoveredDayKey else { return }

        // Leaving the chart is the only move the reader did not aim at a bar, and it is the only
        // one that gets the slower curve.
        let returning = nextKey == nil
        let animation = returning
            ? self.style.returnAnimation(speed: self.speed)
            : self.style.hoverAnimation(speed: self.speed)
        withAnimation(animation) { self.hoveredDayKey = nextKey }
        self.flashOnArrival(returning: returning)
    }

    private func flashOnArrival(returning: Bool) {
        guard self.style == .landing else { return }
        var snap = Transaction()
        snap.disablesAnimations = true
        withTransaction(snap) { self.arrivalFlash = 1 }
        // The decay has to be a separate update, or SwiftUI coalesces both writes and the flash
        // never reaches the screen.
        DispatchQueue.main.async {
            let duration = CostChartHoverMotion.scaled(returning ? 0.5 : 0.34, timeScale: self.speed)
            withAnimation(.easeOut(duration: duration)) { self.arrivalFlash = 0 }
        }
    }
}

/// The reset landing's wide glow, sized for one bar: no edge of its own, brightest at the bar and
/// gone before it reaches anything else.
private struct BarBloom: View {
    let tint: Color

    var body: some View {
        Canvas { context, size in
            let radiusX = size.width * 1.5
            let radiusY = size.height * 0.75
            guard radiusX > 0, radiusY > 0 else { return }
            context.drawLayer { layer in
                layer.translateBy(x: size.width / 2, y: size.height * 0.62)
                layer.scaleBy(x: 1, y: radiusY / radiusX)
                layer.fill(
                    Path(ellipseIn: CGRect(
                        x: -radiusX,
                        y: -radiusX,
                        width: radiusX * 2,
                        height: radiusX * 2
                    )),
                    with: .radialGradient(
                        Gradient(colors: [self.tint.opacity(0.38), self.tint.opacity(0)]),
                        center: .zero,
                        startRadius: 0,
                        endRadius: radiusX
                    )
                )
            }
        }
        .allowsHitTesting(false)
    }
}

#endif
