import SwiftUI

enum RateFieldFocusMotion {
    static let width: CGFloat = 68
    static let height: CGFloat = 22
    static let cornerRadius: CGFloat = 5
    static let horizontalPadding: CGFloat = 6
    static let fontSize: CGFloat = 11
    static let duration: TimeInterval = 0.09
    static let curve = (0.16, 1.0, 0.3, 1.0)

    static func animation(speed: Double = 1, reduceMotion: Bool) -> Animation? {
        self.animation(duration: Self.duration, speed: speed, reduceMotion: reduceMotion)
    }

    static func animation(
        duration: TimeInterval,
        speed: Double,
        reduceMotion: Bool
    ) -> Animation? {
        guard !reduceMotion else { return nil }
        return .timingCurve(
            Self.curve.0,
            Self.curve.1,
            Self.curve.2,
            Self.curve.3,
            duration: duration / max(0.01, speed)
        )
    }
}

struct RateField: View {
    let placeholder: String
    @Binding var text: String
    let animationSpeed: Double
    let reduceMotionOverride: Bool
    let clearFocusToken: Int

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @FocusState private var isFocused: Bool

    init(
        _ placeholder: String,
        text: Binding<String>,
        animationSpeed: Double = 1,
        reduceMotionOverride: Bool = false,
        clearFocusToken: Int = 0
    ) {
        self.placeholder = placeholder
        self._text = text
        self.animationSpeed = animationSpeed
        self.reduceMotionOverride = reduceMotionOverride
        self.clearFocusToken = clearFocusToken
    }

    private var reduceMotion: Bool {
        self.systemReduceMotion || self.reduceMotionOverride
    }

    var body: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: RateFieldFocusMotion.cornerRadius,
                style: .continuous
            )
            .fill(Color(nsColor: .textBackgroundColor))

            RoundedRectangle(
                cornerRadius: RateFieldFocusMotion.cornerRadius,
                style: .continuous
            )
            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.85), lineWidth: 1)

            TextField(self.placeholder, text: self.$text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.system(size: RateFieldFocusMotion.fontSize, design: .monospaced))
                .padding(.horizontal, RateFieldFocusMotion.horizontalPadding)
                .frame(
                    width: RateFieldFocusMotion.width,
                    height: RateFieldFocusMotion.height
                )
                .focused(self.$isFocused)

            RoundedRectangle(
                cornerRadius: RateFieldFocusMotion.cornerRadius,
                style: .continuous
            )
            .strokeBorder(Theme.accent(for: .codex), lineWidth: 1)
            .opacity(self.isFocused ? 1 : 0)
            .animation(
                RateFieldFocusMotion.animation(
                    speed: self.animationSpeed,
                    reduceMotion: self.reduceMotion
                ),
                value: self.isFocused
            )
            .allowsHitTesting(false)
        }
        .frame(width: RateFieldFocusMotion.width, height: RateFieldFocusMotion.height)
        .clipShape(
            RoundedRectangle(
                cornerRadius: RateFieldFocusMotion.cornerRadius,
                style: .continuous
            )
        )
        .onChange(of: self.clearFocusToken) { _, _ in
            self.isFocused = false
        }
    }
}
