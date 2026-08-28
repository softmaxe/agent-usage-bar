import AgentUsageBarCore
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let costService = CostService()
    private lazy var store = UsageStore(settings: self.settings, costService: self.costService)
    private lazy var pricing = PricingEditorModel(costService: self.costService)
    private var controller: StatusItemController?

    func applicationDidFinishLaunching(_: Notification) {
        self.controller = StatusItemController(
            store: self.store,
            settings: self.settings,
            pricing: self.pricing
        )
        self.store.start()
        Log.ui.info("AgentUsageBar launched")
        print("AgentUsageBar launched — use the Quit menu item or Ctrl-C to stop.")
    }

    func applicationWillTerminate(_: Notification) {
        self.store.stop()
    }
}

@main
enum AgentUsageBarApp {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments

        /// `--flag <value>...`: the `count` arguments after `flag`, when the caller passed that
        /// many. Nil for a flag that is absent or short of its arguments, which leaves the app to
        /// launch normally rather than acting on half a request.
        func values(after flag: String, count: Int) -> [String]? {
            guard let index = arguments.firstIndex(of: flag), index + count < arguments.count else {
                return nil
            }
            return Array(arguments[(index + 1)...(index + count)])
        }

        func value(after flag: String) -> String? {
            values(after: flag, count: 1)?[0]
        }

#if DEBUG
        // The suite and the design studies are launch flags rather than separate executables. Each
        // entry owns the process once its flag is present, so the first match wins and the order
        // here is the order the flags are checked in.
        let flagged: [(flag: String, run: @MainActor () -> Never)] = [
            ("--verify-cost-chart-highlighting", CostChartHighlightVerifier.run),
            ("--verify-usage-bar-fill", UsageBarFillVerifier.run),
            ("--verify-icon-rendering", IconRenderingVerifier.run),
            ("--verify-menu-pointer-follow", MenuPointerFollowVerifier.run),
            ("--verify-quota-recovery", QuotaRecoveryVerifier.run),
            ("--verify-relative-time", RelativeTimeVerifier.run),
            ("--verify-quota-reset-label", QuotaResetLabelVerifier.run),
            ("--verify-refresh-row", RefreshRowVerifier.run),
            ("--verify-pricing-sort", PricingSortVerifier.run),
            ("--verify-pricing-model-filter", PricingModelFilterVerifier.run),
            ("--verify-disclosure-motion", DisclosureMotionVerifier.run),
            ("--verify-tab-switch-motion", TabSwitchMotionVerifier.run),
            ("--demo-celebration", CelebrationDemo.run),
            ("--demo-collapse", CollapseShiftDemo.run),
            ("--demo-number-animation", NumberAnimationDemo.run),
            ("--demo-bar-hover", BarHoverDemo.run),
            ("--demo-label-toggle", LabelToggleDemo.run),
            ("--demo-disclosure", DisclosureAnimationDemo.run),
            ("--demo-tab-switch", TabSwitchDemo.run),
            ("--demo-pricing-links", PricingLinksDemo.run),
        ]
        if let entry = flagged.first(where: { arguments.contains($0.flag) }) {
            entry.run()
        }

        if let pair = values(after: "--dump-collapse-shift", count: 2) {
            CollapseShiftDemo.report(variant: pair[0], state: pair[1])
        }
        if let directory = value(after: "--dump-pricing-links") {
            PricingLinksDemo.dumpCards(directory: directory)
            return
        }
        if let directory = value(after: "--dump-number-animation") {
            NumberAnimationDemo.dumpFrames(directory: directory)
            return
        }
        if let directory = value(after: "--dump-celebration") {
            CelebrationDemo.dumpFrames(directory: directory)
            return
        }
        if let directory = value(after: "--dump-tab-switch") {
            MotionFilmStrip.dumpTabSwitch(directory: directory)
            return
        }
        if let directory = value(after: "--dump-disclosure") {
            MotionFilmStrip.dumpDisclosure(directory: directory)
            return
        }
        if let directory = value(after: "--dump-chart-motion") {
            MotionFilmStrip.dumpChartMotion(directory: directory)
            return
        }
        if let pair = values(after: "--dump-card-celebration", count: 2) {
            CelebrationDemo.dumpCardFrames(
                directory: pair[0],
                provider: Provider(rawValue: pair[1]) ?? .claude
            )
            return
        }
#endif
        if let directory = value(after: "--dump-icons") {
            IconDump.run(directory: directory)
            return
        }
        if let directory = value(after: "--dump-card") {
            CardDump.run(directory: directory)
            return
        }
        if let directory = value(after: "--dump-settings") {
            CardDump.dumpSettings(directory: directory)
            return
        }
        if let pair = values(after: "--dump-chart-hover", count: 2) {
            CardDump.dumpChartHover(
                directory: pair[0],
                provider: Provider(rawValue: pair[1]) ?? .claude
            )
            return
        }

        let app = NSApplication.shared
        // Menu bar only: no Dock icon, no main window.
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
