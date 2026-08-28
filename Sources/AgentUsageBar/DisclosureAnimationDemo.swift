#if DEBUG
import AgentUsageBarCore
import AppKit
import SwiftUI

/// `AgentUsageBar --demo-disclosure` puts the candidate treatments for the pricing table's
/// collapse control side by side. Every card is the same header, the same rows and the same
/// timing budget, so the question being judged is only how the control should open.
@MainActor
enum DisclosureAnimationDemo {
    static func run() -> Never {
        DemoWindow.run(
            title: "Pricing table disclosure prototypes",
            width: 980,
            height: 760,
            content: DisclosureDemoView()
        )
    }
}

// MARK: - Motion

/// The curves the shipped control does not use. `DisclosureMotion` owns the rest, so the demo and
/// the pricing table cannot drift apart on the treatment that was actually chosen.
private enum DemoMotion {
    /// A cross-fade has no distance to cover, so it takes less time than a rotation.
    static let quietDuration: TimeInterval = 0.16

    static func quiet(speed: Double) -> Animation {
        .easeOut(duration: Self.quietDuration / speed)
    }
}

// MARK: - Variants

private enum DisclosureStyle: String, CaseIterable, Identifiable {
    /// The chevron turns on the fill's easing and the rows arrive with it. The baseline.
    case rotate
    /// The same turn, taken on the bar's damped sine, so the control overshoots and settles.
    case settle
    /// The caret is drawn rather than set: its arms straighten into a dash and re-open downward.
    case unfold
    /// The chevron turns as in A; the rows arrive one beat apart, unrolling from the header.
    case cascade
    /// No turn at all. The two glyphs cross-fade and the rows fade in.
    case quiet

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .rotate: "A · Rotate"
        case .settle: "B · Rotate + settle"
        case .unfold: "C · Unfold"
        case .cascade: "D · Rotate + row cascade"
        case .quiet: "E · Quiet swap"
        }
    }

    var blurb: String {
        switch self {
        case .rotate:
            "A quarter turn on the fill's own easing, and the rows arrive on the same curve. "
                + "The control and its content are one movement, and nothing overshoots."
        case .settle:
            "The same quarter turn taken on the bar's damped sine: the chevron passes 90°, comes "
                + "back, and settles. Only the control springs — the rows stay on the plain easing."
        case .unfold:
            "The caret is a drawn path, not a glyph being spun. Its arms straighten into a dash "
                + "halfway through and re-open pointing down, so the control reads as opening."
        case .cascade:
            "Chevron as in A, but each row arrives \(Int(DisclosureMotion.rowStagger * 1000))ms "
                + "after the one above it, so the group unrolls from under the header."
        case .quiet:
            "No rotation. The two glyphs cross-fade over a 2pt drift and the rows fade in. The "
                + "least motion a disclosure can have and still not blink."
        }
    }

    /// The curve the rows themselves arrive on.
    func rowAnimation(speed: Double, index: Int, isOpen: Bool) -> Animation {
        switch self {
        case .quiet:
            return DemoMotion.quiet(speed: speed)
        case .cascade:
            return isOpen ? DisclosureMotion.rowArrival(index: index) : DisclosureMotion.openCurve
        case .rotate, .settle, .unfold:
            return DisclosureMotion.openCurve
        }
    }

    /// The curve the group's height runs on. The height never springs: a table that overshoots
    /// its own height pushes every row below it, which reads as a layout bug rather than a beat.
    func heightAnimation(speed: Double) -> Animation {
        self == .quiet ? DemoMotion.quiet(speed: speed) : DisclosureMotion.openCurve
    }
}

// MARK: - Window

private struct DisclosureDemoView: View {
    @State private var speed: Double = 1
    @State private var pressDip = true
    @State private var token = 0

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
                    ForEach(DisclosureStyle.allCases) { style in
                        DisclosureVariantCard(
                            style: style,
                            speed: self.speed,
                            pressDip: self.pressDip
                        )
                        .id("\(style.id)-\(self.token)")
                    }
                }
                .padding(.bottom, 4)
            }

            Text(
                "Both curves come from the reset choreography: the opening is the fill's "
                    + "exponential decay as a timing curve, the settle is the landing's damped "
                    + "sine as a spring. Click a header or a row chevron to toggle it."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The shared curves are slowed by the same static the reset demo uses for its own.
        .onAppear { DisclosureMotion.timeScale = self.speed }
        .onChange(of: self.speed) { _, newValue in DisclosureMotion.timeScale = newValue }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("PRICING TABLE / DISCLOSURE STUDY")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Text("The group should open, not blink.")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Picker("Speed", selection: self.$speed) {
                ForEach(Self.speeds, id: \.1) { Text($0.0).tag($0.1) }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            .labelsHidden()

            Toggle("Chevron dips while pressed", isOn: self.$pressDip)
                .toggleStyle(.checkbox)

            Spacer(minLength: 12)

            Button("Reset all") { self.token += 1 }
                .keyboardShortcut("r", modifiers: [.command])
        }
    }
}

// MARK: - One card

/// One candidate, shown the way the pricing table shows a provider: a group header with its count,
/// three model rows, and the per-row disclosure behind the first of them. Both scales of the
/// control run the same treatment, because in the real table they sit two lines apart.
private struct DisclosureVariantCard: View {
    let style: DisclosureStyle
    let speed: Double
    let pressDip: Bool

    @State private var groupOpen = true
    @State private var rowOpen = false

    private static let rowHeight: CGFloat = 34
    private static let detailHeight: CGFloat = 30

    private static let rows: [(model: String, tokens: String, rate: String)] = [
        ("claude-opus-5", "834M tokens", "15 / 75"),
        ("claude-sonnet-5", "53M tokens", "3 / 15"),
        ("claude-haiku-4-5", "582K tokens", "1 / 5"),
    ]

    private var contentHeight: CGFloat {
        CGFloat(Self.rows.count) * Self.rowHeight + (self.rowOpen ? Self.detailHeight : 0)
    }

    var body: some View {
        DemoVariantCard(title: self.style.title, blurb: self.style.blurb) {
            VStack(alignment: .leading, spacing: 0) {
                self.groupHeader
                self.groupContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var groupHeader: some View {
        Button {
            self.groupOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                StyledChevron(style: self.style, isOpen: self.groupOpen, speed: self.speed)
                    .frame(width: 16, alignment: .center)
                Text("Claude")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(Self.rows.count * 4 + 2)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                Spacer(minLength: 0)
            }
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(DisclosureButtonStyle(dips: self.pressDip, speed: self.speed))
    }

    /// The group's rows live in the hierarchy whether or not the group is open; what opens is the
    /// height they are allowed. That keeps the reveal on one curve, and lets a row take its own
    /// beat without the container having to know about it.
    private var groupContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            self.row(0)
            self.detail
            self.row(1)
            self.row(2)
        }
        .frame(height: self.groupOpen ? self.contentHeight : 0, alignment: .top)
        .clipped()
        .animation(self.style.heightAnimation(speed: self.speed), value: self.groupOpen)
        .animation(self.style.heightAnimation(speed: self.speed), value: self.rowOpen)
    }

    private func row(_ index: Int) -> some View {
        let entry = Self.rows[index]
        return HStack(spacing: 8) {
            if index == 0 {
                Button {
                    self.rowOpen.toggle()
                } label: {
                    StyledChevron(style: self.style, isOpen: self.rowOpen, speed: self.speed)
                        .frame(width: 22, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DisclosureButtonStyle(dips: self.pressDip, speed: self.speed))
            } else {
                Color.clear.frame(width: 22, height: 28)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.model)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Text(entry.tokens)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(entry.rate)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(height: Self.rowHeight)
        .padding(.leading, 2)
        // The rows arrive with the header, or one beat apart, depending on the treatment.
        .opacity(self.groupOpen ? 1 : 0)
        .offset(y: self.groupOpen ? 0 : -4)
        .animation(
            self.style.rowAnimation(speed: self.speed, index: index, isOpen: self.groupOpen),
            value: self.groupOpen
        )
    }

    /// What the per-row chevron opens in the real table: the rates the four columns leave out.
    private var detail: some View {
        HStack(spacing: 8) {
            Text("1-hour cache write")
                .frame(width: 118, alignment: .leading)
            Text("30")
                .font(.system(size: 10, design: .monospaced))
            Text("· long-context tier above 200K")
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.leading, 32)
        .frame(height: Self.detailHeight, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(self.rowOpen ? 1 : 0)
        .frame(height: self.rowOpen ? Self.detailHeight : 0, alignment: .top)
        .clipped()
        .animation(self.style.rowAnimation(speed: self.speed, index: 0, isOpen: self.rowOpen), value: self.rowOpen)
    }
}

// MARK: - The control

/// The chevron itself. Every treatment draws the same 9pt caret in the same place; only how it
/// gets from one state to the other differs.
private struct StyledChevron: View {
    let style: DisclosureStyle
    let isOpen: Bool
    let speed: Double

    var body: some View {
        switch self.style {
        case .rotate, .cascade:
            self.glyph("chevron.right")
                .rotationEffect(.degrees(self.isOpen ? 90 : 0))
                .animation(DisclosureMotion.openCurve, value: self.isOpen)
        case .settle:
            self.glyph("chevron.right")
                .rotationEffect(.degrees(self.isOpen ? 90 : 0))
                .animation(DisclosureMotion.pressCurve, value: self.isOpen)
        case .unfold:
            Caret(progress: self.isOpen ? 1 : 0)
                .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .foregroundStyle(.secondary)
                .frame(width: 9, height: 9)
                .animation(DisclosureMotion.openCurve, value: self.isOpen)
        case .quiet:
            ZStack {
                self.glyph("chevron.right")
                    .opacity(self.isOpen ? 0 : 1)
                    .offset(y: self.isOpen ? -2 : 0)
                self.glyph("chevron.down")
                    .opacity(self.isOpen ? 1 : 0)
                    .offset(y: self.isOpen ? 0 : 2)
            }
            .animation(DemoMotion.quiet(speed: self.speed), value: self.isOpen)
        }
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

/// A caret drawn as two arms meeting at a vertex. `progress` turns it a quarter turn, and on the
/// way the arms straighten into a dash and close again — the shape opens rather than spins.
private struct Caret: Shape {
    /// 0 is a closed caret pointing right; 1 is an open one pointing down.
    var progress: Double

    var animatableData: Double {
        get { self.progress }
        set { self.progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let arm = min(rect.width, rect.height) * 0.62
        let heading = Double.pi / 2 * self.progress
        // 45° at both ends, 90° — a straight dash — at the midpoint.
        let half = Double.pi / 4 + Double.pi / 4 * sin(.pi * self.progress)
        // The vertex leads the arms, so the caret keeps its weight on the side it points at.
        let vertex = CGPoint(
            x: rect.midX + arm * 0.42 * cos(heading),
            y: rect.midY + arm * 0.42 * sin(heading)
        )

        var path = Path()
        path.move(to: Self.point(from: vertex, angle: heading + .pi - half, length: arm))
        path.addLine(to: vertex)
        path.addLine(to: Self.point(from: vertex, angle: heading + .pi + half, length: arm))
        return path
    }

    private static func point(from origin: CGPoint, angle: Double, length: Double) -> CGPoint {
        CGPoint(x: origin.x + length * cos(angle), y: origin.y + length * sin(angle))
    }
}

/// Borderless, and optionally with a press: the control dips while the mouse is down and comes
/// back on the settle spring, so a click has a weight of its own separate from what it opens.
private struct DisclosureButtonStyle: ButtonStyle {
    let dips: Bool
    let speed: Double

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(self.dips && configuration.isPressed ? 0.86 : 1)
            .animation(DisclosureMotion.pressCurve, value: configuration.isPressed)
    }
}
#endif
