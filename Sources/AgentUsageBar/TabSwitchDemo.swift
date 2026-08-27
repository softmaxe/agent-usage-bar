#if DEBUG
import AppKit
import SwiftUI

/// `AgentUsageBar --demo-tab-switch` puts the candidate treatments for the settings window's
/// General/Pricing tab bar side by side. Every card is the same two segments, the same pill and
/// the same panel underneath, so the question being judged is only how the selection travels.
///
/// The shipped tab bar is AppKit's own — a `TabView` with `.tabItem` draws it, and it offers no
/// place to put a curve. Whichever treatment wins, taking it means drawing the control ourselves.
@MainActor
enum TabSwitchDemo {
    private final class Delegate: NSObject, NSApplicationDelegate {
        func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }
    }

    private static var window: NSWindow?
    private static var delegate: Delegate?

    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = Delegate()
        app.delegate = delegate
        Self.delegate = delegate

        let hosting = NSHostingView(rootView: TabSwitchDemoView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings tab switch prototypes"
        window.contentView = hosting
        window.center()
        window.makeKeyAndOrderFront(nil)
        Self.window = window

        app.activate(ignoringOtherApps: true)
        app.run()
        exit(0)
    }
}

// MARK: - Motion

/// The curves the shipped control does not use. `TabSwitchMotion` owns the stretch and
/// `DisclosureMotion` the rest, so the demo and the settings window cannot drift apart on the
/// treatment that was actually chosen.
private enum DemoMotion {
    /// A cross-fade has no distance to cover, so it takes less time than a slide.
    static let quietDuration: TimeInterval = 0.14

    static func quiet(speed: Double) -> Animation {
        .easeOut(duration: Self.quietDuration / speed)
    }
}

// MARK: - Variants

private enum TabSwitchStyle: String, CaseIterable, Identifiable {
    /// The pill slides on the pricing table's opening easing. The baseline.
    case slide
    /// The same slide taken on the bar's damped sine, so the pill passes the segment and settles.
    case settle
    /// The pill's two edges move on the same curve over different lengths, so it stretches across
    /// the gap and contracts onto the destination. This is the one that shipped.
    case stretch
    /// The pill slides; the panel underneath arrives from the side the pill came from.
    case push
    /// No travel. Two pills cross-fade in place and the panel fades.
    case quiet

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .slide: "A · Slide"
        case .settle: "B · Slide + settle"
        case .stretch: "C · Stretch — shipped"
        case .push: "D · Slide + panel push"
        case .quiet: "E · Quiet swap"
        }
    }

    var blurb: String {
        switch self {
        case .slide:
            "The pill travels on the same easing the pricing groups open on, and the panel "
                + "cross-fades under it. One movement, nothing overshoots. The quiet default."
        case .settle:
            "The same travel taken on the bar's damped sine: the pill passes the segment, comes "
                + "back and settles. Reads as physical, but it is the widest motion here and a "
                + "settings window is not where weight belongs."
        case .stretch:
            "The edge facing the destination leaves first and the trailing edge catches up, so "
                + "the pill briefly spans both segments. The selection is continuous — it is "
                + "never in two places, and never nowhere."
        case .push:
            "Pill as in A, and the panel arrives from the side the selection came from over "
                + "\(Int(TabSwitchCard.panelShift))pt. The tabs read as a strip you move along "
                + "rather than two unrelated screens."
        case .quiet:
            "No travel at all. The two pills cross-fade in place and the panel fades with them. "
                + "The least motion a tab bar can have and still not blink."
        }
    }

    /// Whether the pill is one shape that moves, or two shapes that trade places.
    var pillTravels: Bool { self != .quiet }

    func panelAnimation(speed: Double) -> Animation {
        self == .quiet ? DemoMotion.quiet(speed: speed) : DisclosureMotion.openCurve
    }
}

// MARK: - Window

private struct TabSwitchDemoView: View {
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
                    ForEach(TabSwitchStyle.allCases) { style in
                        TabSwitchCard(style: style, speed: self.speed, pressDip: self.pressDip)
                            .id("\(style.id)-\(self.token)")
                    }
                }
                .padding(.bottom, 4)
            }

            Text(
                "The shipped tab bar is AppKit's, so none of this is reachable from the current "
                    + "SettingsView — whichever wins, the control gets drawn here instead. Click "
                    + "either segment on a card to switch it."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { Self.setTimeScale(self.speed) }
        .onChange(of: self.speed) { _, newValue in Self.setTimeScale(newValue) }
    }

    /// Both shared curve sets are slowed by the same static the reset demo uses for its own.
    private static func setTimeScale(_ scale: Double) {
        DisclosureMotion.timeScale = scale
        TabSwitchMotion.timeScale = scale
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("SETTINGS / TAB SWITCH STUDY")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Text("The selection should move, not jump.")
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

            Toggle("Segment dips while pressed", isOn: self.$pressDip)
                .toggleStyle(.checkbox)

            Spacer(minLength: 12)

            Button("Reset all") { self.token += 1 }
                .keyboardShortcut("r", modifiers: [.command])
        }
    }
}

// MARK: - One card

/// One candidate, shown the way the settings window shows its tabs: two segments over a panel
/// tall enough that a change under them is visible without being the thing being judged.
private struct TabSwitchCard: View {
    let style: TabSwitchStyle
    let speed: Double
    let pressDip: Bool

    /// How far the panel travels under the `push` treatment. Far enough to have a direction,
    /// short enough that the text never reads as sliding past.
    static let panelShift: CGFloat = 14

    private static let titles = ["General", "Pricing"]
    private static let barHeight: CGFloat = 28
    private static let panelHeight: CGFloat = 132

    @State private var selection = 0
    @State private var bounds: [Int: CGRect] = [:]
    @State private var pillMinX: CGFloat = 0
    @State private var pillMaxX: CGFloat = 0
    @State private var hovered: Int?
    @State private var pressed: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(self.style.title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                self.tabBar
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .underPageBackgroundColor))
                Divider()
                self.panels
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.8))
            }

            Text(self.style.blurb)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 12, y: 5)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.8))
        }
    }

    // MARK: The control

    /// The segments size themselves to their labels, as the real tab bar does, and report their
    /// frames upward; the pill is drawn from those frames rather than from a share of the width.
    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Self.titles.indices, id: \.self) { index in
                self.segment(index)
            }
        }
        .coordinateSpace(name: "segments")
        .background(alignment: .leading) { self.pill }
        .onPreferenceChange(SegmentBoundsKey.self) { value in
            self.bounds = value
            if self.pillMaxX == 0 { self.movePill(to: self.selection, animated: false) }
        }
    }

    private func segment(_ index: Int) -> some View {
        ZStack {
            // Both weights are laid out, so the segment keeps one width while they cross-fade.
            self.label(index, weight: .semibold).opacity(self.selection == index ? 1 : 0)
            self.label(index, weight: .regular).opacity(self.selection == index ? 0 : 1)
        }
        .foregroundStyle(self.selection == index ? Color.white : Color.primary.opacity(0.85))
        .animation(self.style.panelAnimation(speed: self.speed), value: self.selection)
        .padding(.horizontal, 14)
        .frame(height: Self.barHeight)
        .background {
            // The hover wash the unselected segment carries, on nothing but a fade.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.07))
                .opacity(self.hovered == index && self.selection != index ? 1 : 0)
                .animation(DemoMotion.quiet(speed: self.speed), value: self.hovered)
        }
        .scaleEffect(self.pressDip && self.pressed == index ? 0.94 : 1)
        .animation(DisclosureMotion.pressCurve, value: self.pressed)
        .contentShape(Rectangle())
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SegmentBoundsKey.self,
                    value: [index: proxy.frame(in: .named("segments"))]
                )
            }
        }
        .onHover { self.hovered = $0 ? index : (self.hovered == index ? nil : self.hovered) }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in self.pressed = index }
                .onEnded { _ in
                    self.pressed = nil
                    self.select(index)
                }
        )
    }

    private func label(_ index: Int, weight: Font.Weight) -> some View {
        Text(Self.titles[index])
            .font(.system(size: 13, weight: weight))
            .fixedSize()
    }

    /// One shape that travels, or two that trade places — the difference the study is about.
    @ViewBuilder
    private var pill: some View {
        if self.style.pillTravels {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor)
                .frame(width: max(0, self.pillMaxX - self.pillMinX), height: Self.barHeight)
                .offset(x: self.pillMinX)
        } else {
            ZStack(alignment: .leading) {
                ForEach(Self.titles.indices, id: \.self) { index in
                    let rect = self.bounds[index] ?? .zero
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: rect.width, height: Self.barHeight)
                        .offset(x: rect.minX)
                        .opacity(self.selection == index ? 1 : 0)
                }
            }
            .animation(DemoMotion.quiet(speed: self.speed), value: self.selection)
        }
    }

    // MARK: The panels

    /// Both panels stay in the hierarchy; what changes is which one is opaque, and — under the
    /// push treatment — where the other one waits. A panel to the right waits to the right.
    private var panels: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Self.titles.indices, id: \.self) { index in
                self.panel(index)
                    .opacity(self.selection == index ? 1 : 0)
                    .offset(x: self.panelOffset(index))
                    .animation(self.style.panelAnimation(speed: self.speed), value: self.selection)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.panelHeight, alignment: .topLeading)
        .clipped()
    }

    private func panelOffset(_ index: Int) -> CGFloat {
        guard self.style == .push, self.selection != index else { return 0 }
        return index > self.selection ? Self.panelShift : -Self.panelShift
    }

    @ViewBuilder
    private func panel(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if index == 0 {
                self.row(label: "Refresh", value: "Every 5 minutes")
                self.row(label: "Showing", value: "Claude")
                Text("One item at a time. Right-click it to switch providers.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                self.row(label: "claude-opus-5", value: "15 / 75")
                self.row(label: "claude-sonnet-5", value: "3 / 15")
                Text("Rates in dollars per million tokens, input / output.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12))
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    // MARK: Selection

    private func select(_ index: Int) {
        guard index != self.selection else { return }
        self.selection = index
        self.movePill(to: index, animated: true)
    }

    private func movePill(to index: Int, animated: Bool) {
        guard let rect = self.bounds[index] else { return }
        guard animated, self.style.pillTravels else {
            self.pillMinX = rect.minX
            self.pillMaxX = rect.maxX
            return
        }

        switch self.style {
        case .stretch:
            // The shipped curves, straight from the control the settings window draws.
            let curves = TabSwitchMotion.edgeCurves(
                movingRight: rect.minX >= self.pillMinX,
                reduceMotion: false
            )
            withAnimation(curves.minX) { self.pillMinX = rect.minX }
            withAnimation(curves.maxX) { self.pillMaxX = rect.maxX }
        case .settle:
            withAnimation(DisclosureMotion.pressCurve) {
                self.pillMinX = rect.minX
                self.pillMaxX = rect.maxX
            }
        case .slide, .push, .quiet:
            withAnimation(DisclosureMotion.openCurve) {
                self.pillMinX = rect.minX
                self.pillMaxX = rect.maxX
            }
        }
    }
}

/// Where each segment ended up, in the tab bar's own coordinate space.
private struct SegmentBoundsKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
#endif
