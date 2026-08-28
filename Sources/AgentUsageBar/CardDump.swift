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
        let root = OffscreenCapture.directory(directory)

        // A throwaway defaults domain keeps the dump from touching real preferences, and the
        // fixtures keep the machine's own logs and saved rates out of the render.
        let defaults = UserDefaults(suiteName: "AgentUsageBarSettingsDump") ?? .standard
        defaults.removePersistentDomain(forName: "AgentUsageBarSettingsDump")
        let settings = SettingsStore(defaults: defaults)
        let pricing = PricingEditorModel(
            costService: CostService(databaseURL: root.appendingPathComponent("unused.sqlite")),
            fixtures: Self.pricingFixtures
        )

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
            // The first row the table draws is the first API model, not the busiest one, so pick
            // the busiest explicitly: an unfolded row with real numbers above it reads better
            // than one captioned "Not used locally".
            let row = pricing.rows.max { $0.usageTokens < $1.usageTokens } ?? pricing.rows.first
            if let row { pricing.expandedRowIDs = [row.id] }
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
        // The settings window is a tab bar over a 620x460 pane and the pricing pane is that pane
        // on its own, so the height comes from the view rather than from a constant here.
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

        // The pane loads its rows asynchronously, so let the run loop turn before capturing.
        Self.report(
            OffscreenCapture.writePNG(hosting, named: name, into: root, titled: true, settle: 3),
            size: hosting.frame
        )
    }

    /// Both card dumps name the size they wrote, since a layout regression usually shows up there
    /// first.
    private static func report(_ outcome: OffscreenCapture.Outcome, size: CGRect) {
        switch outcome {
        case let .written(url):
            print("wrote \(url.path) (\(Int(size.width))x\(Int(size.height)))")
        case let .failed(reason):
            print(reason)
        }
    }

    /// Made-up token totals and the built-in rate table, so the pricing pane renders the same
    /// on any machine and carries nobody's account in it.
    private static let pricingFixtures = PricingEditorModel.PreviewFixtures(
        usage: [
            .claude: [
                ModelUsageTotal(model: "claude-opus-5", tokens: 412_000_000),
                ModelUsageTotal(model: "claude-sonnet-5", tokens: 168_000_000),
                ModelUsageTotal(model: "claude-fable-5", tokens: 38_400_000),
                ModelUsageTotal(model: "claude-haiku-4-5", tokens: 24_600_000),
            ],
            .codex: [
                ModelUsageTotal(model: "gpt-5.6-sol", tokens: 236_000_000),
                ModelUsageTotal(model: "gpt-5.6-terra", tokens: 91_000_000),
                ModelUsageTotal(model: "gpt-5.6-luna", tokens: 12_400_000),
            ],
        ],
        overlay: PricingOverlay()
    )

    /// `--dump-chart-hover <dir> <provider>` walks the highlight across every bar of the cost
    /// chart, one PNG per day. The frames carry the breakdown each bar opens, not the spring that
    /// carries the highlight between them — a still cannot hold a spring.
    static func dumpChartHover(directory: String, provider: Provider) {
        let root = OffscreenCapture.directory(directory)
        let cost = Self.sampleCost(provider)
        guard let today = cost.days.last else { return }

        for (index, day) in cost.days.enumerated() {
            let hosting = NSHostingView(rootView: CostSectionView(
                provider: provider,
                snapshot: cost,
                previewHoveredDayKey: day.dayKey,
                previewTodayDayKey: today.dayKey
            ).padding(14).frame(width: 280))
            hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
            _ = OffscreenCapture.writePNG(hosting, named: String(format: "frame-%04d", index), into: root)
        }
        print("wrote \(cost.days.count) chart hover frames to \(root.path)")
    }

    /// The synthetic day-by-day history every card dump draws from. A realistic day mixes models,
    /// which is what the hover breakdown is for. The run ends on today, because the chart marks
    /// today from the clock rather than from the snapshot — a fixture stuck in a fixed week draws
    /// an extra empty bar next to it.
    private static func sampleCost(_ provider: Provider) -> CostSnapshot {
        let now = Date().addingTimeInterval(-5 * 60)
        let (values, top) = provider == .codex
            ? ([18.0, 22, 12, 20, 24, 176], "gpt-5.6-sol")
            : ([62.0, 90, 48, 71, 9, 88, 41, 37], "claude-opus-5")
        let mix = provider == .codex
            ? [(top, 0.72), ("gpt-5.6-terra", 0.2), ("gpt-5.6-luna", 0.08)]
            : [(top, 0.8), ("claude-sonnet-5", 0.15), ("claude-haiku-4-5", 0.05)]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days = values.enumerated().map { index, value in
            let date = calendar.date(byAdding: .day, value: index - (values.count - 1), to: today) ?? today
            return CostDay(
                dayKey: Formatters.dayKey(for: date),
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
            todayCostUSD: values.last ?? 0,
            windowCostUSD: values.reduce(0, +),
            latestTokens: 67_000_000,
            windowTokens: 637_000_000,
            topModel: top,
            hasUnpricedTokens: false,
            scannedAt: now
        )
    }

    static func run(directory: String) {
        let root = OffscreenCapture.directory(directory)

        let now = Date().addingTimeInterval(-5 * 60)

        let costs: [Provider: CostSnapshot] = [
            .claude: Self.sampleCost(.claude),
            .codex: Self.sampleCost(.codex),
        ]

        let cases: [(String, Provider, UsageSnapshot?)] = [
            ("codex-loaded", .codex, (UsageSnapshot(
                provider: .codex,
                session: UsageWindow(usedPercent: 12, resetsAt: Date().addingTimeInterval(3 * 3600), windowSeconds: 18_000),
                // Two days into the week with 14% gone is a reserve; the tip renders green.
                weekly: UsageWindow(usedPercent: 14, resetsAt: Date().addingTimeInterval(5 * 86_400), windowSeconds: 604_800),
                planLabel: "Plus",
                credits: CreditsSnapshot(hasCredits: true, unlimited: false, balance: 640),
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
                let outcome = OffscreenCapture.writePNG(
                    hosting,
                    named: "\(provider.rawValue)-\(name)",
                    into: root
                )
                if case let .written(url) = outcome {
                    print("wrote \(url.path)")
                }
            }
        }

        // Both faces of the reset label: the clock one is the longer string, and it is the one
        // that would crowd the headline out of a 280pt card if it ever got too long.
        let resetModes: [(String, QuotaResetDisplayMode)] = [("", .countdown), ("-reset-clock", .clock)]
        for (baseName, provider, snapshot) in cases {
            for (suffix, resetMode) in resetModes {
                let name = baseName + suffix
                let view = MenuCardView(
                    provider: provider,
                    display: ProviderDisplay(
                        snapshot: snapshot,
                        cost: costs[provider],
                        error: errors[baseName]
                    ),
                    isRefreshing: false,
                    animatesFill: false,
                    quotaResetDisplayMode: resetMode
                )
                let hosting = NSHostingView(rootView: view)
                hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
                Self.report(
                    OffscreenCapture.writePNG(hosting, named: name, into: root),
                    size: hosting.frame
                )
            }
        }
    }
}
