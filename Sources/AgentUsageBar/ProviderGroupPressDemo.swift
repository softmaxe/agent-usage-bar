#if DEBUG
import AppKit
import SwiftUI

@MainActor
enum ProviderGroupPressDemo {
    static func run() -> Never {
        DemoWindow.run(
            title: "Provider group press prototypes",
            width: 920,
            height: 700,
            content: ProviderGroupPressDemoView()
        )
    }
}

private enum ProviderGroupPressStyle: String, CaseIterable, Identifiable {
    case noDip
    case rowDip
    case chevronDip
    case tint

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .noDip: "A · No dip"
        case .rowDip: "B · Soft row dip"
        case .chevronDip: "C · Chevron-only press"
        case .tint: "D · Tint-only press"
        }
    }

    var blurb: String {
        switch self {
        case .noDip:
            "No press transform. The header keeps its geometry while the shared disclosure motion opens the rows."
        case .rowDip:
            "The whole header row scales to \(DisclosureMotion.providerGroupPressScale) on press with a short ease-out and no overshoot."
        case .chevronDip:
            "Only the chevron scales to 0.94 on press. Header text and geometry stay fixed."
        case .tint:
            "No geometry change. A restrained native tint marks the held header."
        }
    }
}

private enum ProviderGroupPressMotion {
    static let tint = Animation.easeOut(duration: DisclosureMotion.providerGroupPressDuration)
    static let chevronDip = Animation.spring(response: 0.18, dampingFraction: 0.92)
}

private struct ProviderGroupPressDemoView: View {
    @State private var speed: Double = 1
    @State private var resetToken = 0

    private static let speeds: [(String, Double)] = [("1×", 1), ("0.5×", 0.5), ("0.25×", 0.25)]
    private static let columns = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            self.header
            self.controls

            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: 18) {
                    ForEach(ProviderGroupPressStyle.allCases) { style in
                        ProviderGroupPressCard(style: style)
                            .id("\(style.id)-\(self.resetToken)")
                    }
                }
                .padding(.bottom, 4)
            }

            Text("Production is untouched. Each card has independent state; click any Claude header repeatedly to compare the press response.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { DisclosureMotion.timeScale = self.speed }
        .onChange(of: self.speed) { _, newValue in DisclosureMotion.timeScale = newValue }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("PRICING TABLE / PROVIDER GROUP PRESS STUDY")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Text("The header should acknowledge a press without moving the table.")
                .font(.system(size: 23, weight: .semibold, design: .rounded))
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

            Button("Reset all") { self.resetToken += 1 }
                .keyboardShortcut("r", modifiers: [.command])

            Spacer(minLength: 12)
        }
    }
}

private struct ProviderGroupPressCard: View {
    let style: ProviderGroupPressStyle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = true

    private static let rowHeight: CGFloat = 34
    private static let dividerHeight: CGFloat = 1
    private static let rows: [(model: String, tokens: String, rate: String)] = [
        ("claude-opus-5", "834M tokens", "15 / 75"),
        ("claude-sonnet-5", "53M tokens", "3 / 15"),
        ("claude-haiku-4-5", "582K tokens", "1 / 5"),
    ]

    private var contentHeight: CGFloat {
        CGFloat(Self.rows.count) * (Self.rowHeight + Self.dividerHeight)
    }

    var body: some View {
        DemoVariantCard(title: self.style.title, blurb: self.style.blurb) {
            VStack(alignment: .leading, spacing: 0) {
                self.groupHeader
                self.groupContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.7))
            }
        }
    }

    private var groupHeader: some View {
        Button {
            withAnimation(DisclosureMotion.open(reduceMotion: self.reduceMotion)) {
                self.isExpanded.toggle()
            }
        } label: {
            ProviderGroupHeaderLabel(
                style: self.style,
                isExpanded: self.isExpanded,
                reduceMotion: self.reduceMotion
            )
        }
        .buttonStyle(
            ProviderGroupHeaderButtonStyle(style: self.style, reduceMotion: self.reduceMotion)
        )
    }

    private var groupContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                VStack(alignment: .leading, spacing: 0) {
                    self.row(row, index: index)
                    Divider().padding(.leading, 28)
                }
                .frame(height: Self.rowHeight + Self.dividerHeight)
            }
        }
        .frame(height: self.isExpanded ? self.contentHeight : 0, alignment: .top)
        .clipped()
        .animation(
            DisclosureMotion.open(reduceMotion: self.reduceMotion),
            value: self.isExpanded
        )
    }

    private func row(
        _ row: (model: String, tokens: String, rate: String),
        index: Int
    ) -> some View {
        HStack(spacing: 8) {
            DisclosureChevron(isOpen: false, reduceMotion: self.reduceMotion)
                .foregroundStyle(.secondary)
                .frame(width: 22, height: Self.rowHeight)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.model)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(row.tokens)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.rate)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(height: Self.rowHeight)
        .padding(.horizontal, 12)
        .opacity(self.isExpanded ? 1 : 0)
        .offset(y: self.isExpanded ? 0 : -4)
        .animation(self.rowAnimation(index: index), value: self.isExpanded)
    }

    private func rowAnimation(index: Int) -> Animation? {
        guard !self.reduceMotion else { return nil }
        return self.isExpanded
            ? DisclosureMotion.rowArrival(index: index)
            : DisclosureMotion.openCurve
    }
}

private struct ProviderGroupHeaderLabel: View {
    let style: ProviderGroupPressStyle
    let isExpanded: Bool
    let reduceMotion: Bool

    @Environment(\.providerGroupIsPressed) private var isPressed

    var body: some View {
        HStack(spacing: 6) {
            DisclosureChevron(isOpen: self.isExpanded, size: 11, reduceMotion: self.reduceMotion)
                .scaleEffect(self.chevronScale)
                .animation(
                    self.reduceMotion ? nil : ProviderGroupPressMotion.chevronDip,
                    value: self.isPressed
                )
                .frame(width: 6)
            Text("Claude")
                .font(.system(size: 12, weight: .semibold))
            Text("14")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var chevronScale: CGFloat {
        self.style == .chevronDip && self.isPressed && !self.reduceMotion ? 0.94 : 1
    }
}

private struct ProviderGroupHeaderButtonStyle: ButtonStyle {
    let style: ProviderGroupPressStyle
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.providerGroupIsPressed, configuration.isPressed)
            .foregroundStyle(self.foreground(isPressed: configuration.isPressed))
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.thinMaterial)
                    .opacity(self.tintOpacity(isPressed: configuration.isPressed))
            }
            .scaleEffect(self.rowScale(isPressed: configuration.isPressed))
            .animation(
                self.pressAnimation,
                value: configuration.isPressed
            )
    }

    private func rowScale(isPressed: Bool) -> CGFloat {
        self.style == .rowDip && isPressed && !self.reduceMotion
            ? DisclosureMotion.providerGroupPressScale
            : 1
    }

    private func foreground(isPressed: Bool) -> Color {
        self.style == .tint && isPressed
            ? Color.primary.opacity(0.78)
            : Color.primary
    }

    private func tintOpacity(isPressed: Bool) -> Double {
        self.style == .tint && isPressed ? 0.75 : 0
    }

    private var pressAnimation: Animation? {
        guard !self.reduceMotion else { return nil }
        switch self.style {
        case .rowDip:
            return DisclosureMotion.providerGroupPressCurve
        case .tint:
            return ProviderGroupPressMotion.tint
        case .noDip, .chevronDip:
            return nil
        }
    }
}

private struct ProviderGroupIsPressedKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var providerGroupIsPressed: Bool {
        get { self[ProviderGroupIsPressedKey.self] }
        set { self[ProviderGroupIsPressedKey.self] = newValue }
    }
}
#endif
