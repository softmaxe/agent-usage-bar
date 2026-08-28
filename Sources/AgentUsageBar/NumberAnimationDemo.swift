#if DEBUG
import AgentUsageBarCore
import AppKit
import SwiftUI

/// `AgentUsageBar --demo-number-animation` puts the candidate treatments for the headline
/// percentage side by side, every one of them driven by the production reset timeline, so the
/// question being judged is only how the digits should behave while the bar underneath does what
/// it already does.
@MainActor
enum NumberAnimationDemo {
    static func run() -> Never {
        DemoWindow.run(
            title: "Quota reset number animation prototypes",
            width: 940,
            height: 700,
            resizable: false,
            content: NumberAnimationDemoView()
        )
    }

    /// `--dump-number-animation <dir>` writes a contact sheet: every variant at the same handful of
    /// moments, so the frames can be compared side by side without watching five clocks at once.
    static func dumpFrames(directory: String) {
        let root = OffscreenCapture.directory(directory)

        let moments: [TimeInterval] = [0, 0.25, 0.7, 1.5, 2.79, 2.86, 3.05, 3.4]
        for moment in moments {
            let sheet = NumberAnimationContactSheet(elapsed: moment, startPercent: 3, provider: .claude)
                .frame(width: 460, height: 300)
            OffscreenCapture.renderPNG(
                sheet,
                named: String(format: "t-%04d", Int(moment * 1000)),
                into: root
            )
        }
        print("wrote number animation frames to \(root.path)")
    }
}

/// One frozen frame of every variant, used by the contact sheet only.
private struct NumberAnimationContactSheet: View {
    let elapsed: TimeInterval
    let startPercent: Double
    let provider: Provider

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            VStack(alignment: .leading, spacing: 18) {
                Text(String(format: "t = %.2fs", self.elapsed))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                ForEach(NumberStyle.allCases) { style in
                    HStack(spacing: 10) {
                        Text(String(style.title.prefix(1)))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 12, alignment: .leading)
                        NumberAnimationHeadline(
                            style: style,
                            elapsed: self.elapsed,
                            startPercent: self.startPercent,
                            tint: Theme.accent(for: self.provider)
                        )
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Variants

private enum NumberStyle: String, CaseIterable, Identifiable {
    /// Counts with the fill and nothing else. The baseline every other variant is judged against.
    case lockstep
    /// Counts with the fill, then takes the landing: pop, flash, and the bloom behind the digits.
    case landingBeat
    /// Odometer columns rolling on the same easing.
    case odometer
    /// Motion blur while the digits are moving fast, sharpening as the count slows into 100%.
    case motionBlur
    /// No counting at all: the old reading holds, dimmed, and the landing swaps it for the new one.
    case handoff

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .lockstep: "A · Lockstep count"
        case .landingBeat: "B · Lockstep + landing"
        case .odometer: "C · Odometer roll"
        case .motionBlur: "D · Motion blur count"
        case .handoff: "E · Quiet, then handoff"
        }
    }

    var blurb: String {
        switch self {
        case .lockstep:
            "Digits on the fill's own easing. Nothing on the landing beat, so the number is a "
                + "readout of the bar rather than a second event."
        case .landingBeat:
            "The same count, and then the label joins the landing: a small pop on the bar's "
                + "damped sine, the flash, and the bloom behind the digits."
        case .odometer:
            "Columns roll like a counter wheel. Same easing, but the mechanism is visible and the "
                + "ones column spins hard early on."
        case .motionBlur:
            "The count blurs while it is moving fast and sharpens as it slows, so the digits "
                + "resolve into 100% instead of stopping on it."
        case .handoff:
            "The pre-reset reading holds, dimmed, while the bar charges. The landing is the only "
                + "moment the number changes at all."
        }
    }
}

// MARK: - Window

private struct NumberAnimationDemoView: View {
    @State private var token = 1
    @State private var provider: Provider = .claude
    @State private var speed: Double = 0.5
    @State private var previousPercent: Double = 3

    private static let speeds: [(String, Double)] = [("1×", 1), ("0.5×", 0.5), ("0.25×", 0.25)]

    private static let columns = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            self.header
            self.controls

            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: 18) {
                    ForEach(NumberStyle.allCases) { style in
                        NumberVariantCard(
                            style: style,
                            provider: self.provider,
                            startPercent: self.previousPercent,
                            token: self.token
                        )
                    }
                }
                .padding(.bottom, 4)
            }

            Text(
                "Every variant is driven by QuotaCelebration's timeline — same easing, same "
                    + "landing at \(String(format: "%.1f", QuotaCelebration.landing))s, same decay. "
                    + "Only the label's treatment differs."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { QuotaCelebration.timeScale = self.speed }
        .onChange(of: self.provider) { _, _ in self.token += 1 }
        .onChange(of: self.speed) { _, newValue in
            QuotaCelebration.timeScale = newValue
            self.token += 1
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("RESET RECOVERY / NUMBER STUDY")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Text("The number should arrive with the bar.")
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

            HStack(spacing: 8) {
                Text("Previous \(Int(self.previousPercent.rounded()))%")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 92, alignment: .leading)
                Slider(value: self.$previousPercent, in: 0...80, step: 1) { editing in
                    if !editing { self.token += 1 }
                }
                .frame(width: 132)
            }

            Picker("Speed", selection: self.$speed) {
                ForEach(Self.speeds, id: \.1) { Text($0.0).tag($0.1) }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)

            Button("Replay all") { self.token += 1 }
                .keyboardShortcut("r", modifiers: [.command])
        }
        .labelsHidden()
    }
}

// MARK: - One card

/// One candidate, shown the way the menu card shows a quota window: headline, bar, pace line. The
/// card runs its own clock alongside the bar's so the label can be driven frame by frame; both are
/// started by the same token in the same update, which is what keeps them in step.
private struct NumberVariantCard: View {
    let style: NumberStyle
    let provider: Provider
    let startPercent: Double
    let token: Int

    @StateObject private var clock = CelebrationClock()

    private var tint: Color { Theme.accent(for: self.provider) }

    var body: some View {
        DemoVariantCard(title: self.style.title, blurb: self.style.blurb) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    self.headline
                    Spacer(minLength: 8)
                    Text("Resets in 5h 0m")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                UsageProgressBar(
                    percent: 100,
                    tint: self.tint,
                    celebrationToken: self.token,
                    celebrationStartPercent: self.startPercent
                )
                Text("On pace · 5h left")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { self.play() }
        .onChange(of: self.token) { _, _ in self.play() }
        .onDisappear { self.clock.stop() }
    }

    private func play() {
        self.clock.start(duration: QuotaCelebration.duration, timeScale: QuotaCelebration.timeScale)
    }

    private var headline: some View {
        NumberAnimationHeadline(
            style: self.style,
            elapsed: self.clock.elapsed,
            startPercent: self.startPercent,
            tint: self.tint
        )
    }
}

/// Picks the treatment. Everything below draws the same string; only its behaviour differs.
private struct NumberAnimationHeadline: View {
    let style: NumberStyle
    /// Nil means nothing is playing, and every variant then shows the settled reading.
    let elapsed: TimeInterval?
    let startPercent: Double
    let tint: Color

    @ViewBuilder
    var body: some View {
        switch self.style {
        case .lockstep:
            CountingHeadline(elapsed: self.elapsed, startPercent: self.startPercent, tint: self.tint)
        case .landingBeat:
            CountingHeadline(
                elapsed: self.elapsed,
                startPercent: self.startPercent,
                tint: self.tint,
                takesLanding: true
            )
        case .odometer:
            OdometerHeadline(elapsed: self.elapsed, startPercent: self.startPercent, tint: self.tint)
        case .motionBlur:
            QuotaHeadline(
                title: "Session",
                percent: 100,
                tint: self.tint,
                frame: self.elapsed.map {
                    QuotaCelebrationFrame(
                        elapsed: $0,
                        percent: QuotaNumberMotion.value(at: $0, from: self.startPercent, to: 100),
                        isReplay: false
                    )
                }
            )
        case .handoff:
            HandoffHeadline(elapsed: self.elapsed, startPercent: self.startPercent, tint: self.tint)
        }
    }
}

// MARK: - Headline treatments

private enum HeadlineStyle {
    static let font = Font.system(size: 14, weight: .semibold)

    /// Digits are monospaced, so one measurement covers every column of the odometer.
    static let digitWidth: CGFloat = {
        let attributed = NSAttributedString(
            string: "0",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)]
        )
        return ceil(attributed.size().width)
    }()

    static func word(_ text: String) -> some View {
        Text(text).font(Self.font)
    }
}

/// The glow behind the digits. Same bloom the bar gets, drawn in the label's own space so it does
/// not inherit the pop's scale.
private struct HeadlineGlow: View {
    let elapsed: TimeInterval?
    let tint: Color

    var body: some View {
        Canvas { context, size in
            guard let elapsed, let bloom = QuotaNumberMotion.glow(at: elapsed) else { return }
            let radiusX = max(size.width, 30) * 0.75 * bloom.scale
            let radiusY = max(size.height, 16) * 1.3 * bloom.scale
            guard radiusX > 0, radiusY > 0 else { return }
            context.drawLayer { layer in
                layer.translateBy(x: size.width / 2, y: size.height / 2)
                layer.scaleBy(x: 1, y: radiusY / radiusX)
                layer.fill(
                    Path(ellipseIn: CGRect(
                        x: -radiusX,
                        y: -radiusX,
                        width: radiusX * 2,
                        height: radiusX * 2
                    )),
                    with: .radialGradient(
                        Gradient(colors: [
                            self.tint.opacity(bloom.opacity),
                            self.tint.opacity(0),
                        ]),
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

/// The percentage itself, going warm on the landing beat and cooling back to the label color.
/// Only the number takes it: "Session" and "left" are not the thing that changed. The wash is the
/// tint rather than white — the bar can flash white because it is a colored pill, but a white
/// label on a light card is a label that disappears.
private struct PercentText: View {
    let percent: Int
    var flash: Double = 0
    var tint: Color = .primary

    var body: some View {
        Text("\(self.percent)%")
            .font(HeadlineStyle.font)
            .monospacedDigit()
            .foregroundStyle(Color.primary)
            .overlay {
                Text("\(self.percent)%")
                    .font(HeadlineStyle.font)
                    .monospacedDigit()
                    .foregroundStyle(self.tint.opacity(self.flash))
            }
    }
}

/// "Session 63% left", counted on the fill's easing. `takesLanding` adds the pop, the flash and
/// the bloom.
private struct CountingHeadline: View {
    let elapsed: TimeInterval?
    let startPercent: Double
    let tint: Color
    var takesLanding = false

    private var value: Double {
        guard let elapsed else { return 100 }
        return QuotaNumberMotion.value(at: elapsed, from: self.startPercent, to: 100)
    }

    private var flash: Double {
        guard self.takesLanding, let elapsed else { return 0 }
        return QuotaNumberMotion.flash(at: elapsed)
    }

    private var scale: Double {
        guard self.takesLanding, let elapsed else { return 1 }
        return QuotaNumberMotion.scale(at: elapsed)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            HeadlineStyle.word("Session ")
            PercentText(percent: Int(self.value.rounded()), flash: self.flash, tint: self.tint)
                .background { HeadlineGlow(elapsed: self.takesLanding ? self.elapsed : nil, tint: self.tint) }
            HeadlineStyle.word(" left")
        }
        .scaleEffect(self.scale, anchor: .leading)
    }
}

/// Digit columns rolling on the same easing. The hundreds column opens out of zero width as the
/// value reaches it, so the label never reads "003%" and nothing to its right jumps sideways.
private struct OdometerHeadline: View {
    let elapsed: TimeInterval?
    let startPercent: Double
    let tint: Color

    private var value: Double {
        guard let elapsed else { return 100 }
        return QuotaNumberMotion.value(at: elapsed, from: self.startPercent, to: 100)
    }

    private var scale: Double {
        guard let elapsed else { return 1 }
        return QuotaNumberMotion.scale(at: elapsed, amplitude: 0.05)
    }

    private var flash: Double {
        guard let elapsed else { return 0 }
        return QuotaNumberMotion.flash(at: elapsed)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            HeadlineStyle.word("Session ")
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                ForEach([2, 1, 0], id: \.self) { place in
                    RollingDigit(value: self.value, place: place)
                }
                HeadlineStyle.word("%")
            }
            // The landing wash is the label's, not any one treatment's: the wheels go warm on the
            // same beat the counted variants do.
            .foregroundStyle(Color.primary)
            .overlay {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    ForEach([2, 1, 0], id: \.self) { place in
                        RollingDigit(value: self.value, place: place)
                    }
                    HeadlineStyle.word("%")
                }
                .foregroundStyle(self.tint.opacity(self.flash))
            }
            .background { HeadlineGlow(elapsed: self.elapsed, tint: self.tint) }
            HeadlineStyle.word(" left")
        }
        .scaleEffect(self.scale, anchor: .leading)
    }
}

/// One column of an odometer: the digit for `place`, plus the next one above it, offset by how far
/// this column has turned. A hidden glyph reserves the slot, which is also what gives the rolling
/// pair a text baseline to sit on.
private struct RollingDigit: View {
    let value: Double
    let place: Int

    private var turned: Double {
        let scaled = max(0, self.value) / pow(10, Double(self.place))
        return scaled.truncatingRemainder(dividingBy: 10)
    }

    /// A leading column stays closed until the value actually reaches it, then opens over the last
    /// tenth of its decade instead of blinking on.
    private var openness: Double {
        guard self.place > 0 else { return 1 }
        let threshold = pow(10, Double(self.place))
        return min(1, max(0, (self.value - threshold * 0.9) / (threshold * 0.1)))
    }

    /// A real wheel rests on its digit and turns only as the one below it comes round. Rolling on
    /// the raw fraction instead leaves every column permanently half-way between two glyphs, which
    /// reads as slop rather than as a counter.
    private static func roll(_ fraction: Double) -> Double {
        let hold = 0.72
        guard fraction > hold else { return 0 }
        let progress = (fraction - hold) / (1 - hold)
        return progress * progress * (3 - 2 * progress)
    }

    var body: some View {
        let digit = Int(floor(self.turned)) % 10
        let fraction = Self.roll(self.turned - floor(self.turned))
        return Text("0")
            .font(HeadlineStyle.font)
            .monospacedDigit()
            .opacity(0)
            .overlay {
                GeometryReader { proxy in
                    ZStack {
                        Self.glyph(digit).offset(y: -fraction * proxy.size.height)
                        Self.glyph((digit + 1) % 10).offset(y: (1 - fraction) * proxy.size.height)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .clipped()
            }
            .frame(width: HeadlineStyle.digitWidth * self.openness, alignment: .leading)
            .clipped()
            .opacity(self.openness)
    }

    private static func glyph(_ digit: Int) -> some View {
        Text("\(digit)")
            .font(HeadlineStyle.font)
            .monospacedDigit()
    }
}

/// The pre-reset reading holds while the bar charges, then the landing swaps it. Nothing counts;
/// the number is a statement made once, at the moment the bar says the quota is full.
private struct HandoffHeadline: View {
    let elapsed: TimeInterval?
    let startPercent: Double
    let tint: Color

    private var hasLanded: Bool {
        guard let elapsed else { return true }
        return elapsed >= QuotaCelebration.landing
    }

    /// The old reading recedes as the bar charges past it, so the swap is a resolution rather than
    /// a cut.
    private var outgoing: (opacity: Double, blur: Double) {
        guard let elapsed, elapsed < QuotaCelebration.landing else { return (0, 6) }
        let progress = min(1, max(0, elapsed / QuotaCelebration.landing))
        return (0.55 - 0.3 * progress, 1.6 * progress)
    }

    private var incoming: (opacity: Double, blur: Double) {
        guard let elapsed else { return (1, 0) }
        let age = elapsed - QuotaCelebration.landing
        guard age >= 0 else { return (0, 5) }
        let progress = min(1, age / 0.28)
        return (progress, 5 * (1 - progress))
    }

    private var scale: Double {
        guard let elapsed else { return 1 }
        return QuotaNumberMotion.scale(at: elapsed, amplitude: 0.1)
    }

    private var flash: Double {
        guard let elapsed else { return 0 }
        return QuotaNumberMotion.flash(at: elapsed)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            HeadlineStyle.word("Session ")
            // The label that is currently being read owns the layout, so the words after it never
            // sit against a hole. The width changes once, on the landing, under the pop.
            PercentText(percent: self.hasLanded ? 100 : Int(self.startPercent.rounded()))
                .hidden()
                .overlay(alignment: .leading) {
                    PercentText(percent: Int(self.startPercent.rounded()))
                        .opacity(self.outgoing.opacity)
                        .blur(radius: self.outgoing.blur)
                        .fixedSize()
                }
                .overlay(alignment: .leading) {
                    PercentText(percent: 100, flash: self.flash, tint: self.tint)
                        .opacity(self.incoming.opacity)
                        .blur(radius: self.incoming.blur)
                        .fixedSize()
                }
            .background { HeadlineGlow(elapsed: self.elapsed, tint: self.tint) }
            HeadlineStyle.word(" left")
        }
        .scaleEffect(self.scale, anchor: .leading)
    }
}
#endif
