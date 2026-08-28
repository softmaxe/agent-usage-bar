#if DEBUG
import AgentUsageBarCore
import AppKit
import SwiftUI

/// `AgentUsageBar --demo-pricing-links` puts the candidate layouts for the three vendor links in
/// the pricing header side by side. Every card is the real header -- same copy, same 596pt content
/// width, same control size -- so the only things under judgement are how the row is spread across
/// that width and how much of each vendor's color the row is allowed to carry.
@MainActor
enum PricingLinksDemo {
    static func run() -> Never {
        DemoWindow.run(
            title: "Pricing header link prototypes",
            width: 720,
            height: 860,
            content: PricingLinksDemoView()
        )
    }

    /// `AgentUsageBar --dump-pricing-links <dir>` renders every candidate header off screen, so the
    /// spacing can be read off a picture without opening the window.
    static func dumpCards(directory: String) {
        let root = OffscreenCapture.directory(directory)
        for style in LinkRowStyle.allCases {
            Self.capture(style, guides: false, named: style.rawValue, into: root)
            Self.capture(style, guides: true, named: "\(style.rawValue)-guides", into: root)
        }
    }

    private static func capture(_ style: LinkRowStyle, guides: Bool, named name: String, into root: URL) {
        let hosting = NSHostingView(rootView: PricingHeaderPanel(style: style, guides: guides))
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = NSRect(x: 0, y: 0, width: 620, height: hosting.fittingSize.height)

        if case let .written(url) = OffscreenCapture.writePNG(hosting, named: name, into: root, titled: true) {
            print("wrote \(url.path)")
        }
    }
}

// MARK: - Brands

/// The three destinations, each with the color it is recognised by. Claude and OpenAI reuse the
/// accents the provider cards already carry, so the settings window cannot disagree with the menu
/// about what those two look like. OpenRouter has no accent in the app yet; it gets the indigo its
/// own site is built on, held at the same muted saturation as the other two.
private enum LinkBrand: String, CaseIterable, Identifiable {
    case claude
    case openAI
    case openRouter

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .claude: "Claude API pricing"
        case .openAI: "OpenAI API pricing"
        case .openRouter: "OpenRouter API pricing"
        }
    }

    var tint: Color {
        switch self {
        case .claude: Theme.accent(for: .claude)
        case .openAI: Theme.accent(for: .codex)
        case .openRouter: Color(red: 124 / 255, green: 118 / 255, blue: 214 / 255)
        }
    }
}

// MARK: - One button

/// How much color the button carries. The metrics never change with it: same height, same corner,
/// same horizontal padding, so a row can be judged on its spacing alone.
private enum LinkFill {
    /// The system's own bordered look. Only the arrow is tinted.
    case neutral
    /// A wash of the brand color, with its border and label in the same hue.
    case soft
    /// The brand color as the fill, label reversed out of it.
    case solid
    /// No chrome at all -- the segmented strip draws the border once, around all three.
    case bare
}

private struct PricingLinkStyle: ButtonStyle {
    let tint: Color
    let fill: LinkFill
    let expands: Bool

    private static let height: CGFloat = 22
    private static let corner: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11))
            .padding(.horizontal, self.fill == .bare ? 6 : 10)
            .frame(height: Self.height)
            .frame(maxWidth: self.expands ? .infinity : nil)
            .background(self.background)
            .overlay(self.border)
            .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }

    @ViewBuilder
    private var background: some View {
        switch self.fill {
        case .neutral: Color(nsColor: .controlColor)
        case .soft: self.tint.opacity(0.13)
        case .solid: self.tint
        case .bare: Color.clear
        }
    }

    @ViewBuilder
    private var border: some View {
        switch self.fill {
        case .neutral:
            RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                .stroke(Color(nsColor: .separatorColor))
        case .soft:
            RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                .stroke(self.tint.opacity(0.42))
        case .solid, .bare:
            EmptyView()
        }
    }
}

/// One link. The arrow always carries the brand color; the label follows it only once the button
/// itself is tinted, because brand-colored text on a system-gray button reads as a warning.
private struct PricingLinkButton: View {
    let brand: LinkBrand
    let fill: LinkFill
    var expands = false

    var body: some View {
        Button {} label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundStyle(self.iconColor)
                Text(self.brand.title)
                    .foregroundStyle(self.labelColor)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PricingLinkStyle(tint: self.brand.tint, fill: self.fill, expands: self.expands))
    }

    private var iconColor: Color {
        self.fill == .solid ? .white : self.brand.tint
    }

    private var labelColor: Color {
        switch self.fill {
        case .neutral: .primary
        case .soft, .bare: self.brand.tint
        case .solid: .white
        }
    }
}

// MARK: - Variants

private enum LinkRowStyle: String, CaseIterable, Identifiable {
    /// Natural widths, four equal flexible gaps -- the gaps between the buttons are the same as
    /// the gaps to either end of the row.
    case spread
    /// Three equal columns filling the width, split by the panel's own 12pt margin.
    case thirds
    /// Natural widths sized to the longest label, centered as one block.
    case cluster
    /// One bordered strip divided into thirds by hairlines.
    case segmented
    /// Equal columns, each washed in its vendor's color.
    case tinted
    /// Equal columns, each filled with its vendor's color.
    case solid

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .spread: "A · Even spread"
        case .thirds: "B · Equal thirds"
        case .cluster: "C · Centered cluster"
        case .segmented: "D · Segmented strip"
        case .tinted: "E · Brand wash"
        case .solid: "F · Brand fill"
        }
    }

    var blurb: String {
        switch self {
        case .spread:
            "Buttons keep the width of their own labels and the leftover space is divided into "
                + "four: one gap before the first, one between each pair, one after the last. The "
                + "literal reading of the ask -- every gap in the row measures the same."
        case .thirds:
            "Each button takes exactly a third of the width, separated by 12pt, the same margin "
                + "the panel already keeps at its edges. Equal columns, so the labels sit off "
                + "center inside their own buttons -- but the row squares up with the table below."
        case .cluster:
            "All three sized to the longest label and set 12pt apart, then centered as one block. "
                + "The buttons stay button-sized, and the free space is one margin on each side "
                + "rather than three gaps inside the row."
        case .segmented:
            "One bordered strip split into thirds by hairlines, the way a segmented control is "
                + "built. Nothing floats: the row reads as a single object, and the color has "
                + "only the label and the arrow to live in."
        case .tinted:
            "Equal thirds, each washed in 13% of its vendor's color with the border and label in "
                + "the same hue. The colors are identifying rather than decorative, and none of "
                + "the three shouts louder than the table it sits above."
        case .solid:
            "Equal thirds filled outright. Unmistakable at a glance, and the loudest thing in a "
                + "window whose job is a rate table -- worth seeing before it is ruled out."
        }
    }
}

// MARK: - The row

private struct PricingLinkRow: View {
    let style: LinkRowStyle
    let guides: Bool

    /// The panel's own margin, reused as the gap between buttons wherever a gap is fixed.
    private static let margin: CGFloat = 12

    var body: some View {
        self.row
            .background(self.guides ? Color.pink.opacity(0.16) : Color.clear)
    }

    @ViewBuilder
    private var row: some View {
        switch self.style {
        case .spread:
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ForEach(LinkBrand.allCases) { brand in
                    PricingLinkButton(brand: brand, fill: .neutral)
                    Spacer(minLength: 0)
                }
            }
        case .thirds:
            HStack(spacing: Self.margin) {
                ForEach(LinkBrand.allCases) { brand in
                    PricingLinkButton(brand: brand, fill: .neutral, expands: true)
                }
            }
        case .cluster:
            HStack(spacing: Self.margin) {
                ForEach(LinkBrand.allCases) { brand in
                    PricingLinkButton(brand: brand, fill: .neutral)
                        .frame(width: 172)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        case .segmented:
            HStack(spacing: 0) {
                ForEach(Array(LinkBrand.allCases.enumerated()), id: \.element.id) { index, brand in
                    if index > 0 {
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor))
                            .frame(width: 1, height: 22)
                    }
                    PricingLinkButton(brand: brand, fill: .bare, expands: true)
                }
            }
            .background(Color(nsColor: .controlColor))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor))
            }
        case .tinted:
            HStack(spacing: Self.margin) {
                ForEach(LinkBrand.allCases) { brand in
                    PricingLinkButton(brand: brand, fill: .soft, expands: true)
                }
            }
        case .solid:
            HStack(spacing: Self.margin) {
                ForEach(LinkBrand.allCases) { brand in
                    PricingLinkButton(brand: brand, fill: .solid, expands: true)
                }
            }
        }
    }
}

// MARK: - One card

/// The pricing pane's header, verbatim, with one candidate row in it. A row that balances on its
/// own can still sit wrong under three lines of secondary text.
private struct PricingHeaderPanel: View {
    let style: LinkRowStyle
    var guides = false

    /// 620pt window less the header's 12pt padding on both sides.
    static let contentWidth: CGFloat = 596

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Model prices")
                .font(.system(size: 13, weight: .semibold))
            Text("USD per million tokens. Expand a row for the one-hour cache write and the "
                + "long-context tier. Edits are saved as overrides, so models you leave alone "
                + "keep following the built-in table and the models.dev catalog.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            PricingLinkRow(style: self.style, guides: self.guides)
                .padding(.top, 4)
        }
        .frame(width: Self.contentWidth, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// One candidate, labelled and annotated, for the side-by-side window.
private struct PricingLinkCard: View {
    let style: LinkRowStyle
    let guides: Bool

    private static let contentWidth = PricingHeaderPanel.contentWidth

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(self.style.title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)

            PricingHeaderPanel(style: self.style, guides: self.guides)

            Text(self.style.blurb)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: Self.contentWidth, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .underPageBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 12, y: 5)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.8))
        }
    }
}

// MARK: - Window

private struct PricingLinksDemoView: View {
    @State private var guides = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            self.header
            self.controls

            ScrollView {
                VStack(spacing: 18) {
                    ForEach(LinkRowStyle.allCases) { style in
                        PricingLinkCard(style: style, guides: self.guides)
                    }
                }
                .padding(.vertical, 4)
            }

            Text(
                "Claude and OpenAI carry the accents their provider cards already use. OpenRouter "
                    + "has none in the app yet, so it borrows the indigo from its own site."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("PRICING HEADER / LINK ROW STUDY")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Text("Three links, one width, equal air.")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Toggle("Show the gaps", isOn: self.$guides)
                .toggleStyle(.checkbox)
            Text("Paints the row behind the buttons, so equal spacing can be seen rather than "
                + "taken on trust.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
        }
    }
}
#endif
