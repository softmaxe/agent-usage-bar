#if DEBUG
import AgentUsageBarCore
import AppKit
import SwiftUI

/// `AgentUsageBar --demo-celebration` opens a plain window that replays the quota-recovery
/// animation on demand. The menu card only plays it when a real window actually comes back from
/// empty, which can be a week away, so the motion is judged here instead.
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
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Quota recovery celebration"
        window.contentView = hosting
        window.center()
        window.makeKeyAndOrderFront(nil)
        Self.window = window

        app.activate(ignoringOtherApps: true)
        app.run()
        exit(0)
    }

    /// `--dump-celebration <dir>` writes the sequence out frame by frame. A moving bar cannot be
    /// reviewed from a screenshot, and this is the only way to look at one frame at a time.
    static func dumpFrames(directory: String) {
        let root = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let tint = Theme.accent(for: .claude)
        var time: TimeInterval = 0
        while time < QuotaCelebration.duration {
            let frame = ZStack {
                Color(white: 0.13)
                UsageProgressBar(
                    percent: QuotaCelebration.fillFraction(at: time) * 100,
                    tint: tint,
                    animatesFill: false
                )
                .frame(width: 252)
                .scaleEffect(QuotaCelebration.barScale(at: time), anchor: .center)
                QuotaCelebrationLayer(elapsed: time, tint: tint, inset: 20)
                    .frame(width: 292, height: 170)
            }
            .frame(width: 292, height: 170)

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
    /// Zero means "nothing has been celebrated yet", which is also what the menu card passes for a
    /// window with nothing to celebrate — so the first replay has to move it off zero.
    @State private var token = 0
    @State private var provider: Provider = .claude
    @State private var speed: Double = 1

    private static let speeds: [(String, Double)] = [("1×", 1), ("0.5×", 0.5), ("0.25×", 0.25)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            self.controls

            HStack(alignment: .top, spacing: 20) {
                MenuCardView(
                    provider: self.provider,
                    display: Self.recoveredDisplay(provider: self.provider),
                    isRefreshing: false,
                    presentationToken: self.token,
                    celebrating: [.session, .weekly],
                    celebrationToken: self.token
                )
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor))
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("2.4× detail")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    UsageProgressBar(
                        percent: 100,
                        tint: Theme.accent(for: self.provider),
                        presentationToken: self.token,
                        celebrationToken: self.token
                    )
                    .frame(width: 140)
                    .scaleEffect(2.4, anchor: .center)
                    .frame(width: 336, height: 190)
                }
            }

            Text(
                "The card plays this when a five-hour or weekly window that had run to 0% "
                    + "comes back full — nothing else replays it."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            QuotaCelebration.timeScale = self.speed
            // Play once on open so the window is never a still frame.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { self.token += 1 }
        }
        .onChange(of: self.speed) { _, newValue in QuotaCelebration.timeScale = newValue }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Picker("Provider", selection: self.$provider) {
                ForEach(Provider.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Picker("Speed", selection: self.$speed) {
                ForEach(Self.speeds, id: \.1) { Text($0.0).tag($0.1) }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Button("Replay") { self.token += 1 }
                .keyboardShortcut("r", modifiers: [.command])

            Spacer(minLength: 0)
        }
        .labelsHidden()
    }

    /// A provider that just had both windows roll over: everything full, resets far out.
    private static func recoveredDisplay(provider: Provider) -> ProviderDisplay {
        var display = ProviderDisplay()
        display.snapshot = UsageSnapshot(
            provider: provider,
            session: UsageWindow(
                usedPercent: 0,
                resetsAt: Date().addingTimeInterval(5 * 3600),
                windowSeconds: 5 * 3600
            ),
            weekly: UsageWindow(
                usedPercent: 0,
                resetsAt: Date().addingTimeInterval(7 * 24 * 3600),
                windowSeconds: 7 * 24 * 3600
            ),
            planLabel: "Max",
            credits: nil,
            fetchedAt: Date()
        )
        return display
    }
}
#endif
