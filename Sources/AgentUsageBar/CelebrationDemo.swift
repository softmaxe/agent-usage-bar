#if DEBUG
import AgentUsageBarCore
import AppKit
import SwiftUI

/// `AgentUsageBar --demo-celebration` opens the real shared reset animation with controls for
/// judging different pre-reset positions and playback speeds.
@MainActor
enum CelebrationDemo {
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

        let hosting = NSHostingView(rootView: CelebrationDemoView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 470),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Quota reset animation prototype"
        window.contentView = hosting
        window.center()
        window.makeKeyAndOrderFront(nil)
        Self.window = window

        app.activate(ignoringOtherApps: true)
        app.run()
        exit(0)
    }

    /// `--dump-celebration <dir>` writes the shared choreography frame by frame.
    static func dumpFrames(directory: String) {
        let root = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

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

            let renderer = ImageRenderer(content: frame)
            renderer.scale = 2
            if let image = renderer.nsImage,
               let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let data = bitmap.representation(using: .png, properties: [:]) {
                let url = root.appendingPathComponent(String(format: "frame-%04d.png", Int(time * 1000)))
                try? data.write(to: url)
            }
            time += 0.05
        }
        print("wrote celebration frames to \(root.path)")
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
                    + "Charging particles follow the head; the pop and firework share one landing beat."
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
