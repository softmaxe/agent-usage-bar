#if DEBUG
import AppKit
import SwiftUI

@MainActor
enum RateFieldFocusDemo {
    static func run() -> Never {
        DemoWindow.run(
            title: "API rate field focus prototypes",
            width: 1_020,
            height: 780,
            content: RateFieldFocusDemoView()
        )
    }
}

private enum RateFieldFocusStyle: String, CaseIterable, Identifiable {
    case native
    case hairline
    case innerRing
    case quietWash
    case underline

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .native: "A · Current native ring"
        case .hairline: "B · Quick hairline · recommended"
        case .innerRing: "C · Inner ring"
        case .quietWash: "D · Quiet wash"
        case .underline: "E · Underline"
        }
    }

    var blurb: String {
        switch self {
        case .native:
            "The current .roundedBorder treatment. It is the baseline for the focused field."
        case .hairline:
            "A fixed 1px accent stroke fades in quickly. The field never changes size."
        case .innerRing:
            "A 1px accent ring sits inside the existing border, with no outward expansion."
        case .quietWash:
            "A 1px outline and a very light accent wash mark focus without adding weight."
        case .underline:
            "A 2px accent line grows from the center along the field's bottom edge."
        }
    }

    var duration: TimeInterval {
        switch self {
        case .native: 0
        case .hairline: 0.09
        case .innerRing: 0.11
        case .quietWash: 0.10
        case .underline: 0.12
        }
    }
}

private struct RateFieldFocusDemoView: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var speed = 1.0
    @State private var clearFocusToken = 0
    @State private var reduceMotionOverride = false

    private static let speeds: [(String, Double)] = [("1×", 1), ("0.5×", 0.5), ("0.25×", 0.25)]
    private static let columns = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18),
    ]

    private var reduceMotion: Bool {
        self.systemReduceMotion || self.reduceMotionOverride
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            self.header
            self.controls

            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 18) {
                ForEach(RateFieldFocusStyle.allCases) { style in
                    RateFieldFocusVariantCard(
                        style: style,
                        speed: self.speed,
                        reduceMotion: self.reduceMotion,
                        clearFocusToken: self.clearFocusToken
                    )
                }
            }

            Text(
                "Click the 25 field in any card. Each card owns its focus state, so candidates can "
                    + "be compared one at a time. All custom treatments use the disclosure curve "
                    + "(0.16, 1, 0.3, 1) with no spring or scale."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("PRICING TABLE / RATE FIELD FOCUS STUDY")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Text("Focus should be quick and quiet.")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Picker("Speed", selection: self.$speed) {
                ForEach(Self.speeds, id: \.1) { Text($0.0).tag($0.1) }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            .labelsHidden()

            Button("Clear focus") {
                self.clearFocusToken += 1
            }

            Toggle("Reduce Motion", isOn: self.$reduceMotionOverride)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))

            if self.systemReduceMotion {
                Text("System setting on")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct RateFieldFocusVariantCard: View {
    let style: RateFieldFocusStyle
    let speed: Double
    let reduceMotion: Bool
    let clearFocusToken: Int

    @State private var value = "25"
    @FocusState private var isFocused: Bool

    private static let rateWidth: CGFloat = 68
    private static let rateHeight: CGFloat = 22
    private static let columnSpacing: CGFloat = 6
    private let accent = Theme.accent(for: .codex)

    var body: some View {
        DemoVariantCard(title: self.style.title, blurb: self.style.blurb) {
            VStack(alignment: .leading, spacing: 0) {
                self.columnHeader
                Divider().padding(.vertical, 8)
                self.tableRow
            }
        }
        .onChange(of: self.clearFocusToken) { _, _ in
            self.isFocused = false
        }
    }

    private var columnHeader: some View {
        HStack(spacing: Self.columnSpacing) {
            Text("Model")
                .frame(maxWidth: .infinity, alignment: .leading)
            self.columnTitle("Input")
            self.columnTitle("Output")
            self.columnTitle("Cache w")
            self.columnTitle("Cache r")
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
    }

    private func columnTitle(_ title: String) -> some View {
        Text(title)
            .frame(width: Self.rateWidth, alignment: .trailing)
    }

    private var tableRow: some View {
        HStack(alignment: .center, spacing: Self.columnSpacing) {
            VStack(alignment: .leading, spacing: 1) {
                Text("gpt-5.4")
                    .font(.system(size: 12))
                    .lineLimit(1)
                Text("OpenAI API")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            self.priceField
            self.staticRate("40")
            self.staticRate("75")
            self.staticRate("1.25")
        }
    }

    private func staticRate(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: Self.rateWidth, alignment: .trailing)
    }

    @ViewBuilder
    private var priceField: some View {
        switch self.style {
        case .native:
            TextField("", text: self.$value)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: Self.rateWidth, height: Self.rateHeight)
                .focused(self.$isFocused)
        case .hairline:
            RateField(
                "",
                text: self.$value,
                animationSpeed: self.speed,
                reduceMotionOverride: self.reduceMotion,
                clearFocusToken: self.clearFocusToken
            )
        case .innerRing, .quietWash, .underline:
            self.customPriceField
        }
    }

    private var customPriceField: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.85), lineWidth: 1)
            self.plainField
            self.focusDecoration
                .allowsHitTesting(false)
        }
        .frame(width: Self.rateWidth, height: Self.rateHeight)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var plainField: some View {
        TextField("", text: self.$value)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 6)
            .frame(width: Self.rateWidth, height: Self.rateHeight)
            .focused(self.$isFocused)
    }

    @ViewBuilder
    private var focusDecoration: some View {
        switch self.style {
        case .native:
            Color.clear
        case .hairline:
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(self.accent, lineWidth: 1)
                .opacity(self.isFocused ? 1 : 0)
                .animation(self.focusAnimation, value: self.isFocused)
        case .innerRing:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(self.accent, lineWidth: 1)
                .padding(2)
                .opacity(self.isFocused ? 1 : 0)
                .animation(self.focusAnimation, value: self.isFocused)
        case .quietWash:
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(self.accent.opacity(self.isFocused ? 0.07 : 0))
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(self.accent, lineWidth: 1)
                    .opacity(self.isFocused ? 0.72 : 0)
            }
            .animation(self.focusAnimation, value: self.isFocused)
        case .underline:
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(self.accent)
                        .frame(
                            width: self.isFocused ? Self.rateWidth - 8 : 0,
                            height: 2
                        )
                    Spacer(minLength: 0)
                }
                .frame(height: 2)
            }
            .animation(self.focusAnimation, value: self.isFocused)
        }
    }

    private var focusAnimation: Animation? {
        RateFieldFocusMotion.animation(
            duration: self.style.duration,
            speed: self.speed,
            reduceMotion: self.reduceMotion
        )
    }
}
#endif
