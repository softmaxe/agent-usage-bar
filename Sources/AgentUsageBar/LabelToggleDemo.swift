#if DEBUG
import AgentUsageBarCore
import AppKit
import SwiftUI

/// `AgentUsageBar --demo-label-toggle` puts the candidate treatments for the chart label's
/// tokens-to-cost switch side by side. Every card is the production chart -- same bars, same hit
/// testing, same rule that a click only counts on the selected bar -- so the only thing under
/// judgement is how the number changes unit when the reader clicks it.
///
/// The swap used to be a plain assignment: the old number gone and the new one there, in the same
/// frame, while every other change on this chart was animated. That was the gap, and the
/// constraint was to close it in the chart's existing language -- the hover spring, the label's
/// rise, the reset landing's pulse -- rather than by inventing a sixth kind of motion for one
/// click. C won and ships; the rest stay here as the record of what it was chosen against.
@MainActor
enum LabelToggleDemo {
    static func run() -> Never {
        DemoWindow.run(
            title: "Cost chart label toggle prototypes",
            width: 1020,
            height: 860,
            content: LabelToggleDemoView()
        )
    }
}

// MARK: - Timings

/// The click is a deliberate act on a target the reader is already pointing at, so the swap can be
/// quicker than the hover -- it has no distance to cover. It still has to be slow enough to read
/// as one number becoming another rather than as two numbers overlapping.
private enum ToggleMotion {
    static let swap: TimeInterval = 0.2
}

// MARK: - Variants

private enum ToggleStyle: String, CaseIterable, Identifiable {
    /// The old unit fades out where the new one fades in. The baseline.
    case crossfade
    /// The label's own idiom, made directional: the old number leaves upward, the new one rises
    /// into the place it vacates.
    case roll
    /// The reset headline's blur-and-settle, sized for a 10 pt label.
    case resolve
    /// The swap is a crossfade; what acknowledges the click is the bar, on the landing's pulse.
    case pop
    /// The two units keep fixed sides, so the label reads as a two-position switch.
    case slide

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .crossfade: "A · Crossfade"
        case .roll: "B · Odometer roll"
        case .resolve: "C · Blur resolve — shipped"
        case .pop: "D · Bar pop"
        case .slide: "E · Two-position slide"
        }
    }

    var blurb: String {
        switch self {
        case .crossfade:
            "One number fades out under the other. Nothing moves, so nothing competes with the "
                + "hover; the risk is that a 200 ms fade between two short strings reads as a "
                + "flicker rather than as a change."
        case .roll:
            "The shipped label transition, given a direction: out through the top, in from below, "
                + "on the hover spring. The number changes unit the way it arrives on a bar in "
                + "the first place."
        case .resolve:
            "The digits blur out and the new unit resolves out of the blur, on the reset "
                + "headline's curve. It says 'this is the same number, recomputed' more clearly "
                + "than any positional move can."
        case .pop:
            "The label crossfades, but the bar takes the reset landing's damped pulse. The click "
                + "is answered by the thing that was clicked, and the number stays perfectly "
                + "legible throughout."
        case .slide:
            "Tokens sit left, cost sits right, and the label slides between the two. Direction "
                + "encodes state: after two clicks the reader knows which way is which without "
                + "reading the unit."
        }
    }

    /// Nil is a swap with no animation at all, which is what Reduce Motion asks for.
    func animation(speed: Double, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        let duration = CostChartHoverMotion.scaled(ToggleMotion.swap, timeScale: speed)
        switch self {
        case .crossfade: return .easeInOut(duration: duration)
        // The hover spring, so a label that moves on hover moves the same way on a click.
        case .roll: return .spring(response: duration * 1.35, dampingFraction: 0.86)
        // C shipped, so it runs the production curve rather than a copy of its numbers.
        case .resolve:
            return CostChartHoverMotion.swapAnimation(reduceMotion: false, timeScale: speed)
        case .pop: return .easeInOut(duration: duration * 0.9)
        // Slightly softer, because this one travels the furthest.
        case .slide: return .spring(response: duration * 1.5, dampingFraction: 0.9)
        }
    }

    /// How the outgoing and incoming numbers are drawn. `mode` is the mode of the view being
    /// transitioned, which is what lets a variant give the two units fixed sides.
    func transition(for mode: CostChartLabelMode) -> AnyTransition {
        switch self {
        case .crossfade, .pop:
            return .opacity
        case .roll:
            return .asymmetric(
                insertion: .opacity.combined(with: .offset(y: 7)),
                removal: .opacity.combined(with: .offset(y: -7))
            )
        case .resolve:
            return CostChartHoverMotion.swapTransition
        case .slide:
            // Each unit enters from and leaves towards its own side, so the pair reads as one
            // control with two positions rather than as two independent labels.
            let dx: CGFloat = mode == .tokens ? -13 : 13
            return .opacity.combined(with: .offset(x: dx))
        }
    }

    /// How hard the bar answers the click. Only D uses it.
    var popAmplitude: Double {
        self == .pop ? 0.16 : 0
    }
}

// MARK: - Window

private struct LabelToggleDemoView: View {
    @State private var provider: Provider = .codex
    @State private var speed: Double = 1
    @State private var reduceMotion = false

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
                    ForEach(ToggleStyle.allCases) { style in
                        ToggleVariantCard(
                            style: style,
                            provider: self.provider,
                            days: self.days,
                            todayDayKey: self.todayDayKey,
                            speed: self.speed,
                            reduceMotion: self.reduceMotion
                        )
                    }
                }
                .padding(.bottom, 4)
            }

            Text(
                "Click a highlighted bar to switch its label between tokens and cost — the same "
                    + "gesture the card ships. Hover still moves the highlight on the production "
                    + "spring, so a variant can be judged on whether the swap belongs to the same "
                    + "chart. The swap is timed at \(Int(ToggleMotion.swap * 1000)) ms."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("COST CHART / LABEL TOGGLE STUDY")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Text("The unit should change, not cut.")
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

            Picker("Speed", selection: self.$speed) {
                ForEach(Self.speeds, id: \.1) { Text($0.0).tag($0.1) }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)

            Toggle("Reduce Motion", isOn: self.$reduceMotion)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))

            Spacer(minLength: 0)
        }
    }
}

// MARK: - One card

private struct ToggleVariantCard: View {
    let style: ToggleStyle
    let provider: Provider
    let days: [CostDay]
    let todayDayKey: String
    let speed: Double
    let reduceMotion: Bool

    var body: some View {
        DemoVariantCard(title: self.style.title, blurb: self.style.blurb) {
            ToggleChart(
                style: self.style,
                provider: self.provider,
                days: self.days,
                todayDayKey: self.todayDayKey,
                speed: self.speed,
                reduceMotion: self.reduceMotion
            )
        }
    }
}

// MARK: - The chart under test

/// The production chart, with one label treatment applied. Bar geometry, hit testing, which bar is
/// selected, and whether a click toggles at all all come from `CostChartHighlightPolicy`, so a
/// variant can only change how the swap is drawn.
private struct ToggleChart: View {
    let style: ToggleStyle
    let provider: Provider
    let days: [CostDay]
    let todayDayKey: String
    let speed: Double
    let reduceMotion: Bool

    @State private var hoveredDayKey: String?
    @State private var labelMode: CostChartLabelMode = .tokens
    /// 1 at the instant of the click, sprung back to 0. Only D reads it.
    @State private var pop: Double = 0

    private static let chartHeight: CGFloat = 56
    private static let barSpacing: CGFloat = 4

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
            .padding(.top, 14 + CostChartHoverMotion.lift)
            .mouseLocation(onMoved: self.updateHover, onClicked: self.toggleLabel)

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
        let height = max(4, Self.chartHeight * ratio) + (selected ? CostChartHoverMotion.lift : 0)
        // A pop that scales height would make the whole chart's baseline read as unstable, so the
        // bar swells about its own bottom edge instead.
        let popScale = selected ? 1 + self.style.popAmplitude * self.pop : 1

        return RoundedRectangle(cornerRadius: 2)
            .fill(self.tint)
            // Opacity as a modifier rather than inside the fill, so it is a plain animatable value.
            .opacity(selected ? 1 : CostChartHighlightPolicy.restingOpacity)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .scaleEffect(x: 1, y: popScale, anchor: .bottom)
            .overlay(alignment: .top) {
                if selected {
                    self.label(for: day)
                        .scaleEffect(1 + self.style.popAmplitude * 0.45 * self.pop)
                        .offset(y: -14)
                        .transition(CostChartHoverMotion.labelTransition)
                }
            }
    }

    /// The outer `if selected` above owns the label's arrival on a bar; this ZStack owns the unit
    /// swap on a bar that already has one. Keeping them separate is what stops a click from
    /// replaying the hover transition, or a hover from replaying the swap.
    private func label(for day: CostDay) -> some View {
        ZStack {
            ForEach([self.labelMode], id: \.self) { mode in
                Text(self.labelText(for: day, mode: mode))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize()
                    .transition(self.style.transition(for: mode))
            }
        }
    }

    private func labelText(for day: CostDay, mode: CostChartLabelMode) -> String {
        CostChartHighlightPolicy.labelText(
            dayKey: day.dayKey,
            selectedDayKey: self.selectedDayKey,
            selectedMode: mode,
            tokens: day.tokens.total,
            costUSD: day.costUSD
        ) ?? ""
    }

    private var summaryLine: String {
        guard let key = self.selectedDayKey, let day = self.days.first(where: { $0.dayKey == key })
        else { return "hover a bar, then click it" }
        let tokens = Formatters.tokens(day.tokens.total)
        return "\(Formatters.dayLabel(key)) · \(Formatters.cost(day.costUSD ?? 0)) · \(tokens) tokens"
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

        // The hover itself is not what is being judged here, so it runs the shipped curve in
        // every card.
        let animation = CostChartHoverMotion.animation(
            returningToToday: nextKey == nil,
            reduceMotion: self.reduceMotion,
            timeScale: self.speed
        )
        withAnimation(animation) { self.hoveredDayKey = nextKey }
    }

    // MARK: - Click

    private func toggleLabel(at location: CGPoint, width: CGFloat) {
        let index = CostChartHighlightPolicy.barIndex(
            atX: location.x,
            width: width,
            barCount: self.days.count,
            spacing: Self.barSpacing
        )
        let nextMode = CostChartHighlightPolicy.labelMode(
            afterClicking: index.map { self.days[$0].dayKey },
            selectedDayKey: self.selectedDayKey,
            currentMode: self.labelMode
        )
        guard nextMode != self.labelMode else { return }

        withAnimation(self.style.animation(speed: self.speed, reduceMotion: self.reduceMotion)) {
            self.labelMode = nextMode
        }
        self.popOnClick()
    }

    /// The pulse is set without animation and sprung back to rest, so the overshoot on the way
    /// home is the whole gesture -- the same shape the reset landing uses, at a fraction of it.
    private func popOnClick() {
        guard self.style.popAmplitude > 0, !self.reduceMotion else { return }
        var snap = Transaction()
        snap.disablesAnimations = true
        withTransaction(snap) { self.pop = 1 }
        // The decay has to be a separate update, or SwiftUI coalesces both writes and the pulse
        // never reaches the screen.
        DispatchQueue.main.async {
            let response = CostChartHoverMotion.scaled(0.34, timeScale: self.speed)
            withAnimation(.spring(response: response, dampingFraction: 0.42)) { self.pop = 0 }
        }
    }
}

#endif
