import AgentUsageBarCore
import AppKit
import SwiftUI

/// `AgentUsageBar --dump-card <dir>` renders the menu card off screen to PNGs and exits.
/// Lets the card layout be checked without opening the real menu.
@MainActor
enum CardDump {
    static func run(directory: String) {
        let root = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let now = Date().addingTimeInterval(-5 * 60)
        let cases: [(String, Provider, ProviderState)] = [
            ("codex-loaded", .codex, .loaded(UsageSnapshot(
                provider: .codex,
                session: UsageWindow(usedPercent: 0, resetsAt: Date().addingTimeInterval(5 * 3600), windowSeconds: 18_000),
                weekly: UsageWindow(usedPercent: 14, resetsAt: Date().addingTimeInterval(6 * 86_400 + 6 * 3600), windowSeconds: 604_800),
                planLabel: "Plus",
                credits: CreditsSnapshot(hasCredits: false, unlimited: false, balance: 0),
                fetchedAt: now
            ))),
            ("claude-loaded", .claude, .loaded(UsageSnapshot(
                provider: .claude,
                session: UsageWindow(usedPercent: 29, resetsAt: Date().addingTimeInterval(4 * 3600 + 19 * 60), windowSeconds: nil),
                weekly: UsageWindow(usedPercent: 3, resetsAt: Date().addingTimeInterval(6 * 86_400 + 10 * 3600), windowSeconds: nil),
                planLabel: "Pro",
                credits: nil,
                fetchedAt: now
            ))),
            ("claude-failed", .claude, .failed("Claude OAuth request unauthorized. Run `claude` to re-authenticate.")),
        ]

        for (name, provider, state) in cases {
            let view = MenuCardView(provider: provider, state: state, isRefreshing: false)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
            // A layer-backed offscreen host still needs a window to lay out correctly.
            let window = NSWindow(
                contentRect: hosting.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            // The real card sits on the menu's vibrant material. Force dark appearance and paint
            // an opaque ground so the dumped PNG shows the same contrast the menu does.
            window.appearance = NSAppearance(named: .darkAqua)
            let ground = NSView(frame: hosting.frame)
            ground.wantsLayer = true
            ground.layer?.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor
            ground.addSubview(hosting)
            window.contentView = ground
            ground.layoutSubtreeIfNeeded()
            hosting.layoutSubtreeIfNeeded()

            guard let rep = ground.bitmapImageRepForCachingDisplay(in: ground.bounds) else {
                print("failed to allocate bitmap for \(name)")
                continue
            }
            ground.cacheDisplay(in: ground.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else {
                print("failed to encode \(name)")
                continue
            }
            let url = root.appendingPathComponent("\(name).png")
            try? data.write(to: url)
            print("wrote \(url.path) (\(Int(hosting.frame.width))x\(Int(hosting.frame.height)))")
        }
    }
}
