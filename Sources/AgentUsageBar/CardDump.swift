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
        let pricing = PricingEditorModel(costService: CostService())

        Self.captureSettings(
            AnyView(SettingsView(settings: settings, pricing: pricing)),
            named: "settings",
            into: root
        )
        // The pricing pane again on its own, with the top row unfolded, so the one-hour and
        // long-context fields are in the dump rather than a click away. The rows only load when
        // the pane appears, and the first capture never selects that tab, so load them here.
        let loading = Task {
            await pricing.load()
            if let row = pricing.rows.first { pricing.expandedRowIDs = [row.id] }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        _ = loading
        Self.captureSettings(
            AnyView(PricingSettingsView(model: pricing)),
            named: "settings-pricing-expanded",
            into: root
        )
    }

    private static func captureSettings(_ view: AnyView, named name: String, into root: URL) {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = NSRect(x: 0, y: 0, width: 620, height: 460)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        // cacheDisplay paints no window background, so give it an opaque ground or the dark-mode
        // text renders white on white.
        let ground = NSView(frame: hosting.frame)
        ground.wantsLayer = true
        ground.layer?.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor
        ground.addSubview(hosting)
        window.contentView = ground
        window.orderFront(nil)

        // The pane loads its rows asynchronously, so let the run loop turn before capturing.
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        ground.layoutSubtreeIfNeeded()

        guard let rep = ground.bitmapImageRepForCachingDisplay(in: ground.bounds) else { return }
        ground.cacheDisplay(in: ground.bounds, to: rep)
        guard let data = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
            return
        }
        let url = root.appendingPathComponent("\(name).png")
        try? data.write(to: url)
        print("wrote \(url.path) (\(Int(hosting.frame.width))x\(Int(hosting.frame.height)))")
        window.orderOut(nil)
    }

    static func run(directory: String) {
        let root = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let now = Date().addingTimeInterval(-5 * 60)

        func sampleCost(_ provider: Provider, peak: Double, values: [Double], top: String) -> CostSnapshot {
            // A realistic day mixes models, which is what the hover breakdown is for.
            let mix = provider == .codex
                ? [(top, 0.72), ("gpt-5.6-terra", 0.2), ("gpt-5.6-luna", 0.08)]
                : [(top, 0.8), ("claude-sonnet-5", 0.15), ("claude-haiku-4-5", 0.05)]
            let days = values.enumerated().map { index, value in
                CostDay(
                    dayKey: String(format: "2026-08-%02d", 17 + index),
                    byModel: Dictionary(uniqueKeysWithValues: mix.map { model, share in
                        (model, ModelDayUsage(
                            tokens: TokenTotals(input: Int(value * share * 1_000_000)),
                            costUSD: value * share
                        ))
                    }),
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
                session: UsageWindow(usedPercent: 12, resetsAt: Date().addingTimeInterval(3 * 3600), windowSeconds: 18_000),
                // Two days into the week with 14% gone is a reserve; the tip renders green.
                weekly: UsageWindow(usedPercent: 14, resetsAt: Date().addingTimeInterval(5 * 86_400), windowSeconds: 604_800),
                planLabel: "Plus",
                credits: CreditsSnapshot(hasCredits: false, unlimited: false, balance: 0),
                fetchedAt: now
            ))),
            ("claude-loaded", .claude, (UsageSnapshot(
                provider: .claude,
                // Most of the session window spent with a third of it left: a deficit, tip in red.
                session: UsageWindow(usedPercent: 71, resetsAt: Date().addingTimeInterval(1 * 3600), windowSeconds: nil),
                weekly: UsageWindow(usedPercent: 55, resetsAt: Date().addingTimeInterval(2 * 86_400), windowSeconds: nil),
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

        // Capture both the default-today and hovered states, since the dump has no pointer.
        for (provider, cost) in costs {
            guard let today = cost.days.last,
                  let hovered = cost.days.max(by: { ($0.costUSD ?? 0) < ($1.costUSD ?? 0) }) else { continue }
            for (name, hoveredDayKey) in [("today", nil), ("hover", hovered.dayKey)] {
                let hosting = NSHostingView(rootView: CostSectionView(
                    provider: provider,
                    snapshot: cost,
                    previewHoveredDayKey: hoveredDayKey,
                    previewTodayDayKey: today.dayKey
                ).padding(14).frame(width: 280))
                hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
                let window = NSWindow(
                    contentRect: hosting.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.appearance = NSAppearance(named: .darkAqua)
                let ground = NSView(frame: hosting.frame)
                ground.wantsLayer = true
                ground.layer?.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor
                ground.addSubview(hosting)
                window.contentView = ground
                ground.layoutSubtreeIfNeeded()
                if let rep = ground.bitmapImageRepForCachingDisplay(in: ground.bounds) {
                    ground.cacheDisplay(in: ground.bounds, to: rep)
                    if let data = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) {
                        let url = root.appendingPathComponent("\(provider.rawValue)-\(name).png")
                        try? data.write(to: url)
                        print("wrote \(url.path)")
                    }
                }
            }
        }

        for (name, provider, snapshot) in cases {
            let view = MenuCardView(
                provider: provider,
                display: ProviderDisplay(
                    snapshot: snapshot,
                    cost: costs[provider],
                    error: errors[name]
                ),
                isRefreshing: false,
                presentationToken: 0,
                animatesFill: false
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
