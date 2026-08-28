#if DEBUG
import AppKit
import SwiftUI

/// `AgentUsageBar --demo-collapse` puts the pricing table's current layout next to the fixed one
/// and folds both at once, so the sideways jump on collapse is visible side by side instead of
/// having to be remembered across two clicks in Settings.
///
/// The jump: a vertical `ScrollView` hands its content 17pt less width the moment that content
/// becomes tall enough to scroll. Folding a group crosses that line, so every trailing-aligned
/// column — the four rate fields, the reset button, the header captions above them — slides
/// sideways by the width of the scroller while the leading edge stays put.
@MainActor
enum CollapseShiftDemo {
    /// Short enough that an open group has to scroll and a folded one does not — the demo has
    /// nothing to show on either side of that line.
    static let paneHeight: CGFloat = 280

    static func run() -> Never {
        DemoWindow.run(
            title: "Collapse shift — current vs reserved gutter",
            width: 1320,
            height: 620,
            resizable: false,
            content: CollapseShiftDemoView()
        )
    }

    /// `--dump-collapse-shift <current|fixed> <expanded|collapsed>` prints the measured column
    /// geometry for one variant in one state. One state per process: a hosting view that has
    /// already rendered another state keeps reporting its old frames.
    static func report(variant: String, state: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let model = CollapseDemoModel()
        model.expanded = state == "collapsed" ? [] : ["Claude"]
        let table = CollapseDemoTable(model: model, reserveGutter: variant == "fixed", showGuide: false)
        let hosting = NSHostingView(rootView: table.frame(width: 620, height: Self.paneHeight))
        hosting.frame = NSRect(x: 0, y: 0, width: 620, height: Self.paneHeight)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))

        print("--- \(variant) / \(state) ---")
        for key in CollapseDemoMetrics.shared.frames.keys.sorted() {
            let rect = CollapseDemoMetrics.shared.frames[key]!
            print(String(
                format: "%-16@ x=%.1f w=%.1f h=%.1f",
                key as NSString, rect.minX, rect.width, rect.height
            ))
        }
        exit(0)
    }
}

/// Shared fold state, so one click folds both tables and the two layouts stay comparable.
@MainActor
final class CollapseDemoModel: ObservableObject {
    @Published var expanded: Set<String> = ["Claude"]
    @Published var animated = true

    func toggle(_ group: String) {
        self.set(group, expanded: !self.expanded.contains(group))
    }

    func set(_ group: String, expanded: Bool) {
        guard expanded != self.expanded.contains(group) else { return }
        let body = {
            if expanded {
                self.expanded.insert(group)
            } else {
                self.expanded.remove(group)
            }
        }
        if self.animated {
            withAnimation(CollapseDemoTable.fold) { body() }
        } else {
            body()
        }
    }
}

/// Column frames reported by the tables, for the readout under each pane.
@MainActor
final class CollapseDemoMetrics: ObservableObject {
    static let shared = CollapseDemoMetrics()
    @Published var frames: [String: CGRect] = [:]

    func record(_ frames: [String: CGRect]) {
        self.frames.merge(frames) { _, new in new }
    }
}

private struct CollapseFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private extension View {
    func measured(_ name: String, in space: String) -> some View {
        self.background(
            GeometryReader { proxy in
                Color.clear.preference(key: CollapseFrameKey.self, value: [name: proxy.frame(in: .named(space))])
            }
        )
    }
}

/// A stand-in for the real rate table: same column widths, same `ScrollView` + pinned header,
/// folding on the same `DisclosureMotion` curve, with stub rows so the demo needs no cost scan.
/// The disclosure itself is the plain native one — what is under test here is the width the
/// scroll view hands its content, which no disclosure control has a say in.
struct CollapseDemoTable: View {
    @ObservedObject var model: CollapseDemoModel
    /// The fix under test: pin the table's content to a constant width instead of letting the
    /// scroll view hand it 17pt less as soon as it scrolls.
    let reserveGutter: Bool
    var showGuide = true

    static let fold = DisclosureMotion.openCurve
    static let paneWidth: CGFloat = 620
    static let scrollerGutter = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
    /// Trailing edge of the last rate field when the scroller is not reserving width.
    static let guideX = Self.paneWidth - 12 - 22 - 8

    private static let rateColumnWidth: CGFloat = 68
    private static let disclosureHitSize = CGSize(width: 22, height: 28)

    private static let groups: [(name: String, rows: [DemoRow])] = [
        ("Claude", DemoRow.claude),
        ("Codex", DemoRow.codex),
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Self.groups, id: \.name) { group in
                        self.group(group.name, rows: group.rows)
                    }
                } header: {
                    self.columnHeader
                }
            }
            .modifier(ReservedGutter(active: self.reserveGutter))
        }
        .coordinateSpace(name: self.space)
        .onPreferenceChange(CollapseFrameKey.self) { frames in
            CollapseDemoMetrics.shared.record(frames)
        }
        .overlay(alignment: .topLeading) {
            if self.showGuide {
                Rectangle()
                    .fill(Color.red.opacity(0.55))
                    .frame(width: 1)
                    .offset(x: Self.guideX)
                    .allowsHitTesting(false)
            }
        }
    }

    private var space: String { self.reserveGutter ? "fixed" : "current" }

    private func key(_ name: String) -> String { "\(self.reserveGutter ? "fixed" : "current").\(name)" }

    private func group(_ name: String, rows: [DemoRow]) -> some View {
        DisclosureGroup(isExpanded: self.binding(for: name)) {
            ForEach(rows) { row in
                self.row(row)
                Divider().padding(.leading, 28)
            }
        } label: {
            HStack(spacing: 6) {
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                Text("\(rows.count)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            .frame(maxWidth: .infinity, minHeight: Self.disclosureHitSize.height, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { self.model.toggle(name) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private func binding(for name: String) -> Binding<Bool> {
        Binding(
            get: { self.model.expanded.contains(name) },
            set: { expanded in self.model.set(name, expanded: expanded) }
        )
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: Self.disclosureHitSize.width)
            Text("Model").frame(maxWidth: .infinity, alignment: .leading)
            Text("Input").frame(width: Self.rateColumnWidth, alignment: .trailing)
            Text("Output").frame(width: Self.rateColumnWidth, alignment: .trailing)
            Text("Cache w").frame(width: Self.rateColumnWidth, alignment: .trailing)
            Text("Cache r")
                .frame(width: Self.rateColumnWidth, alignment: .trailing)
                .measured(self.key("cacheR"), in: self.space)
            Color.clear.frame(width: 22)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.background)
        .measured(self.key("header"), in: self.space)
    }

    private func row(_ row: DemoRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: Self.disclosureHitSize.width, height: Self.disclosureHitSize.height)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.model).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                Text("\(row.tokens) tokens").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(Array(row.rates.enumerated()), id: \.offset) { _, rate in
                Text(rate)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: Self.rateColumnWidth, alignment: .trailing)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 5)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                    .frame(width: Self.rateColumnWidth)
            }

            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 22)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

/// The one-line fix: hold the table's content at a constant width and pin it to the leading edge,
/// so the columns land in the same place whether or not the scroll view is reserving its gutter.
private struct ReservedGutter: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if self.active {
            content
                .frame(width: CollapseDemoTable.paneWidth - CollapseDemoTable.scrollerGutter, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            content
        }
    }
}

struct DemoRow: Identifiable {
    let id = UUID()
    let model: String
    let tokens: String
    let rates: [String]

    static let claude: [DemoRow] = [
        DemoRow(model: "claude-opus-5", tokens: "834M", rates: ["5", "25", "6.25", "0.5"]),
        DemoRow(model: "claude-sonnet-5", tokens: "412M", rates: ["2", "10", "2.5", "0.2"]),
        DemoRow(model: "claude-haiku-4-5", tokens: "96M", rates: ["1", "5", "1.25", "0.1"]),
        DemoRow(model: "claude-opus-4-1", tokens: "58M", rates: ["15", "75", "18.75", "1.5"]),
        DemoRow(model: "claude-sonnet-4-5", tokens: "31M", rates: ["3", "15", "3.75", "0.3"]),
        DemoRow(model: "claude-3-5-haiku", tokens: "12M", rates: ["0.8", "4", "1", "0.08"]),
    ]

    static let codex: [DemoRow] = [
        DemoRow(model: "gpt-5-codex", tokens: "220M", rates: ["1.25", "10", "1.56", "0.13"]),
        DemoRow(model: "gpt-5-mini", tokens: "44M", rates: ["0.25", "2", "0.31", "0.03"]),
    ]
}

private struct CollapseShiftDemoView: View {
    @StateObject private var current = CollapseDemoModel()
    @StateObject private var fixed = CollapseDemoModel()
    @ObservedObject private var metrics = CollapseDemoMetrics.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            self.header
            HStack(alignment: .top, spacing: 20) {
                self.pane(
                    title: "Current",
                    note: "The scroll view keeps \(Int(CollapseDemoTable.scrollerGutter))pt for its indicator only "
                        + "while the table scrolls, so the columns slide when the fold crosses that line.",
                    model: self.current,
                    reserveGutter: false
                )
                self.pane(
                    title: "Reserved gutter",
                    note: "The content is pinned to a constant width, so the columns hold their place in "
                        + "both states and only the height animates.",
                    model: self.fixed,
                    reserveGutter: true
                )
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Collapsing a group moves the rate columns sideways")
                .font(.system(size: 15, weight: .semibold))
            Text("Click either “Claude” header — both tables fold together. The red line marks where the "
                + "last rate column sits while the table is short enough not to scroll. Watch the left "
                + "table's columns leave the line as it starts scrolling; the right one stays on it.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(self.scrollerNote)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button(self.current.expanded.isEmpty ? "Expand both" : "Collapse both") {
                    self.current.toggle("Claude")
                    self.fixed.toggle("Claude")
                }
                Toggle("Animate the fold", isOn: Binding(
                    get: { self.current.animated },
                    set: { on in
                        self.current.animated = on
                        self.fixed.animated = on
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .padding(.top, 2)
        }
    }

    private func pane(title: String, note: String, model: CollapseDemoModel, reserveGutter: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold))
            CollapseDemoTable(model: model, reserveGutter: reserveGutter)
                .frame(width: CollapseDemoTable.paneWidth, height: CollapseShiftDemo.paneHeight)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            Text(self.readout(reserveGutter ? "fixed" : "current"))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(note)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: CollapseDemoTable.paneWidth, alignment: .leading)
        }
    }

    /// macOS only reserves the gutter while it is drawing legacy scroll bars, which it does with a
    /// mouse attached or with Show scroll bars set to Always. On overlay bars nothing is reserved
    /// and nothing jumps, so the demo says which of the two it is looking at rather than letting a
    /// quiet left pane read as a fixed bug.
    private var scrollerNote: String {
        guard let header = self.metrics.frames["current.header"] else { return " " }
        if header.width < CollapseDemoTable.paneWidth {
            return "This Mac is drawing legacy scroll bars, so the gutter is being reserved and the "
                + "left table has the jump in it."
        }
        return "This Mac is drawing overlay scroll bars, so nothing is reserved and the left table "
            + "holds still too. Attach a mouse, or set System Settings → Appearance → Show scroll "
            + "bars to Always, to see the jump the right-hand layout is guarding against."
    }

    private func readout(_ prefix: String) -> String {
        guard let cacheR = self.metrics.frames["\(prefix).cacheR"],
              let header = self.metrics.frames["\(prefix).header"] else {
            return "measuring…"
        }
        let drift = CollapseDemoTable.guideX - cacheR.maxX
        return String(
            format: "content %.0fpt · Cache r ends at %.0fpt · off the line by %.0fpt",
            header.width, cacheR.maxX, drift
        )
    }
}
#endif
