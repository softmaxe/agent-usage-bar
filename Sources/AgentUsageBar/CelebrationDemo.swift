#if DEBUG
import AgentUsageBarCore
import AppKit
import SwiftUI

/// `AgentUsageBar --demo-celebration` opens the real shared reset animation with controls for
/// judging different pre-reset positions and playback speeds.
@MainActor
enum CelebrationDemo {
    static func run() -> Never {
        DemoWindow.run(
            title: "Quota reset animation prototype",
            width: 680,
            height: 470,
            resizable: false,
            content: CelebrationDemoView()
        )
    }

    /// `--dump-celebration <dir>` writes the shared choreography frame by frame.
    static func dumpFrames(directory: String) {
        let root = OffscreenCapture.directory(directory)

        let tint = Theme.accent(for: .claude)
        let startPercent = 18.0
        var time: TimeInterval = 0
        while time < QuotaCelebration.duration {
            let frame = CelebrationDemoFrame(
                elapsed: time,
                startPercent: startPercent,
                tint: tint
            )
            .frame(width: 560, height: 210)

            OffscreenCapture.renderPNG(
                frame,
                named: String(format: "frame-%04d", Int(time * 1000)),
                into: root
            )
            time += 0.05
        }
        print("wrote celebration frames to \(root.path)")
    }

    /// `--dump-card-celebration <dir> [provider]` writes the same choreography as the card draws
    /// it: the shipped headline over the shipped bar, at the card's width and on the card's
    /// ground. The interactive demo above is for judging the curve; this is for showing it to
    /// someone who is not going to build the app.
    static func dumpCardFrames(directory: String, provider: Provider, fps: Double = 25) {
        let root = OffscreenCapture.directory(directory)

        let step = 1 / max(1, fps)
        var time: TimeInterval = 0
        var index = 0
        // A beat of the settled card on each end, so a looping export does not cut straight from
        // the landing back to the empty bar.
        let tail = QuotaCelebration.duration + 0.6
        while time < tail {
            let frame = CelebrationCardFrame(
                elapsed: min(time, QuotaCelebration.duration),
                startPercent: 18,
                provider: provider
            )
            OffscreenCapture.renderPNG(
                frame,
                named: String(format: "frame-%04d", index),
                into: root
            )
            time += step
            index += 1
        }
        print("wrote \(index) card celebration frames to \(root.path)")
    }
}

/// One frozen frame of the reset as the menu card shows it. The headline and the glow are the
/// shipped views; the bar is redrawn here because the shipped one owns a clock of its own and a
/// still cannot hand it a time.
private struct CelebrationCardFrame: View {
    let elapsed: TimeInterval
    let startPercent: Double
    let provider: Provider

    private var tint: Color { Theme.accent(for: self.provider) }

    private var percent: Double {
        QuotaCelebration.fillPercent(at: self.elapsed, from: self.startPercent, to: 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                QuotaHeadline(
                    title: "Session",
                    percent: self.percent,
                    tint: self.tint,
                    frame: QuotaCelebrationFrame(
                        elapsed: self.elapsed,
                        percent: self.percent,
                        isReplay: false
                    )
                )
                Spacer(minLength: 8)
                Text("Resets in 5h 00m")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            self.bar
            Text("Lasts until reset")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(width: 280, height: 96, alignment: .center)
        .background(Color(white: 0.13))
        .environment(\.colorScheme, .dark)
    }

    private var bar: some View {
        Canvas { context, size in
            let corner = CGSize(width: size.height / 2, height: size.height / 2)
            let rect = CGRect(origin: .zero, size: size)
            context.clip(to: Path(rect))
            context.fill(Path(roundedRect: rect, cornerSize: corner), with: .color(Theme.progressTrack))

            let fillRect = CGRect(x: 0, y: 0, width: size.width * self.percent / 100, height: size.height)
            guard fillRect.width > 0 else { return }
            let fillPath = Path(roundedRect: fillRect, cornerSize: corner)
            context.fill(fillPath, with: .color(self.tint))

            let shine = QuotaCelebration.headShineOpacity(at: self.elapsed)
            if shine > 0.01 {
                let glow = CGRect(x: fillRect.maxX - 14, y: 0, width: 16, height: size.height)
                context.fill(
                    Path(roundedRect: glow, cornerSize: corner).intersection(fillPath),
                    with: .linearGradient(
                        Gradient(colors: [.white.opacity(0), .white.opacity(0.9 * shine)]),
                        startPoint: CGPoint(x: glow.minX, y: 0),
                        endPoint: CGPoint(x: glow.maxX, y: 0)
                    )
                )
            }
            let flash = QuotaCelebration.flashOpacity(at: self.elapsed)
            if flash > 0.01 {
                context.fill(fillPath, with: .color(.white.opacity(flash)))
            }
        }
        .frame(height: 6)
        .scaleEffect(QuotaCelebration.barScale(at: self.elapsed), anchor: .center)
        .overlay {
            QuotaCelebrationLayer(
                elapsed: self.elapsed,
                tint: self.tint,
                startPercent: self.startPercent,
                targetPercent: 100,
                inset: 20
            )
            .frame(height: 96)
            .padding(.horizontal, -20)
        }
    }
}

private struct CelebrationDemoView: View {
    @State private var token = 1
    @State private var provider: Provider = .claude
    @State private var speed: Double = 1
    @State private var previousPercent: Double = 18

    private static let speeds: [(String, Double)] = [("1×", 1), ("0.5×", 0.5), ("0.25×", 0.25)]

    private var midpointPercent: Double {
        self.previousPercent + (100 - self.previousPercent) / 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            self.header
            self.controls

            ResetRecoveryDemoCard(
                provider: self.provider,
                startPercent: self.previousPercent,
                token: self.token
            )

            HStack(spacing: 0) {
                self.timelineLabel("Previous", value: self.previousPercent, alignment: .leading)
                self.timelineLabel("Halfway", value: self.midpointPercent, alignment: .center)
                self.timelineLabel("Reset", value: 100, alignment: .trailing)
            }

            Text(
                "One continuous motion carries the fill from its previous position to 100%. "
                    + "Nothing trails the head on the way; the pop, the flash, and a soft glow "
                    + "rising under the whole bar share the landing beat."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            QuotaCelebration.timeScale = self.speed
        }
        .onChange(of: self.provider) { _, _ in self.token += 1 }
        .onChange(of: self.speed) { _, newValue in
            QuotaCelebration.timeScale = newValue
            self.token += 1
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("RESET RECOVERY / MOTION STUDY")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Text("Continue from where the quota stopped.")
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
                    .frame(width: 86, alignment: .leading)
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

            Button("Replay") { self.token += 1 }
                .keyboardShortcut("r", modifiers: [.command])
        }
        .labelsHidden()
    }

    private func timelineLabel(
        _ title: String,
        value: Double,
        alignment: Alignment
    ) -> some View {
        VStack(alignment: alignment.horizontal, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text("\(Int(value.rounded()))%")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }
}

private struct ResetRecoveryDemoCard: View {
    let provider: Provider
    let startPercent: Double
    let token: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.provider.displayName)
                        .font(.system(size: 15, weight: .semibold))
                    Text("Quota reset detected")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("100% left")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }

            UsageProgressBar(
                percent: 100,
                tint: Theme.accent(for: self.provider),
                celebrationToken: self.token,
                celebrationStartPercent: self.startPercent
            )

            HStack {
                Text("Previous position")
                Spacer()
                Text("Reset to 100%")
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.8))
        }
    }
}

private struct CelebrationDemoFrame: View {
    let elapsed: TimeInterval
    let startPercent: Double
    let tint: Color

    private var fillPercent: Double {
        QuotaCelebration.fillPercent(at: self.elapsed, from: self.startPercent, to: 100)
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                let corner = CGSize(width: size.height / 2, height: size.height / 2)
                context.fill(
                    Path(roundedRect: rect, cornerSize: corner),
                    with: .color(Color.primary.opacity(0.1))
                )
                let fillRect = CGRect(
                    x: 0,
                    y: 0,
                    width: size.width * self.fillPercent / 100,
                    height: size.height
                )
                context.fill(
                    Path(roundedRect: fillRect, cornerSize: corner),
                    with: .color(self.tint)
                )
                let flash = QuotaCelebration.flashOpacity(at: self.elapsed)
                if flash > 0 {
                    context.fill(
                        Path(roundedRect: fillRect, cornerSize: corner),
                        with: .color(.white.opacity(flash))
                    )
                }
            }
            .frame(width: 500, height: 6)
            .scaleEffect(QuotaCelebration.barScale(at: self.elapsed), anchor: .center)

            QuotaCelebrationLayer(
                elapsed: self.elapsed,
                tint: self.tint,
                startPercent: self.startPercent,
                targetPercent: 100,
                inset: 24
            )
            .frame(width: 548, height: 190)
        }
    }
}
#endif
