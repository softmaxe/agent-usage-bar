import AgentUsageBarCore
import AppKit
import SwiftUI

/// `AgentUsageBar --dump-card <dir>` renders the menu card off screen to PNGs and exits.
/// Lets the card layout be checked without opening the real menu.
@MainActor
enum CardDump {
    /// Renders the settings window's content off screen too, so its layout can be checked
    /// without opening a real window.
    static func dumpSettings(directory: String) {
        let root = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // A throwaway defaults domain keeps the dump from touching real preferences.
        let defaults = UserDefaults(suiteName: "AgentUsageBarSettingsDump") ?? .standard
        defaults.removePersistentDomain(forName: "AgentUsageBarSettingsDump")
        let settings = SettingsStore(defaults: defaults)

        let hosting = NSHostingView(rootView: SettingsView(settings: settings))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
            return
        }
        let url = root.appendingPathComponent("settings.png")
        try? data.write(to: url)
        print("wrote \(url.path) (\(Int(hosting.frame.width))x\(Int(hosting.frame.height)))")
    }

    static func run(directory: String) {
        let root = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let now = Date().addingTimeInterval(-5 * 60)

        func sampleCost(_ provider: Provider, peak: Double, values: [Double], top: String) -> CostSnapshot {
            let days = values.enumerated().map { index, value in
                CostDay(
                    dayKey: String(format: "2026-08-%02d", 17 + index),
                    byModel: [top: TokenTotals(input: Int(value * 1_000_000), output: 0)],
                    costUSD: value,
                    unpricedTokens: 0
                )
            }
            return CostSnapshot(
                provider: provider,
                days: days,
                todayCostUSD: 0,
                windowCostUSD: values.reduce(0, +),
                latestTokens: 67_000_000,
                windowTokens: 637_000_000,
                topModel: top,
                hasUnpricedTokens: false,
                scannedAt: now
            )
        }

        let costs: [Provider: CostSnapshot] = [
            .claude: sampleCost(.claude, peak: 90, values: [62, 90, 48, 71, 9, 88, 41, 37], top: "claude-opus-5"),
            .codex: sampleCost(.codex, peak: 176, values: [18, 22, 12, 20, 24, 176], top: "gpt-5.6-sol"),
        ]

        let cases: [(String, Provider, UsageSnapshot?)] = [
            ("codex-loaded", .codex, (UsageSnapshot(
                provider: .codex,
                session: UsageWindow(usedPercent: 0, resetsAt: Date().addingTimeInterval(5 * 3600), windowSeconds: 18_000),
                weekly: UsageWindow(usedPercent: 14, resetsAt: Date().addingTimeInterval(6 * 86_400 + 6 * 3600), windowSeconds: 604_800),
                planLabel: "Plus",
                credits: CreditsSnapshot(hasCredits: false, unlimited: false, balance: 0),
                fetchedAt: now
            ))),
            ("claude-loaded", .claude, (UsageSnapshot(
                provider: .claude,
                session: UsageWindow(usedPercent: 29, resetsAt: Date().addingTimeInterval(4 * 3600 + 19 * 60), windowSeconds: nil),
                weekly: UsageWindow(usedPercent: 3, resetsAt: Date().addingTimeInterval(6 * 86_400 + 10 * 3600), windowSeconds: nil),
                planLabel: "Pro",
                credits: nil,
                fetchedAt: now
            ))),
            // A rate-limited refresh keeps the numbers on screen and appends the error.
            ("claude-rate-limited", .claude, (UsageSnapshot(
                provider: .claude,
                session: UsageWindow(usedPercent: 65, resetsAt: Date().addingTimeInterval(3 * 3600 + 51 * 60), windowSeconds: nil),
                weekly: UsageWindow(usedPercent: 7, resetsAt: Date().addingTimeInterval(6 * 86_400 + 9 * 3600), windowSeconds: nil),
                planLabel: "Pro",
                credits: nil,
                fetchedAt: now
            ))),
        ]
        let errors = ["claude-rate-limited": "Claude usage API rate-limited. Try again after 4:24 PM."]

        for (name, provider, snapshot) in cases {
            let view = MenuCardView(
                provider: provider,
                display: ProviderDisplay(
                    snapshot: snapshot,
                    cost: costs[provider],
                    error: errors[name]
                ),
                isRefreshing: false
            )
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
            guard let data = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
                print("failed to encode \(name)")
                continue
            }
            let url = root.appendingPathComponent("\(name).png")
            try? data.write(to: url)
            print("wrote \(url.path) (\(Int(hosting.frame.width))x\(Int(hosting.frame.height)))")
        }
    }
}
