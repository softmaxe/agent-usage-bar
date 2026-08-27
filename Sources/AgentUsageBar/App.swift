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
#if DEBUG
        if CommandLine.arguments.contains("--verify-cost-chart-highlighting") {
            CostChartHighlightVerifier.run()
        }
        if CommandLine.arguments.contains("--verify-menu-toggles") {
            StatusItemToggleVerifier.run()
        }
        if CommandLine.arguments.contains("--verify-usage-bar-fill") {
            UsageBarFillVerifier.run()
        }
        if CommandLine.arguments.contains("--verify-icon-rendering") {
            IconRenderingVerifier.run()
        }
        if CommandLine.arguments.contains("--verify-menu-pointer-follow") {
            MenuPointerFollowVerifier.run()
        }
        if CommandLine.arguments.contains("--verify-quota-recovery") {
            QuotaRecoveryVerifier.run()
        }
        if CommandLine.arguments.contains("--verify-relative-time") {
            RelativeTimeVerifier.run()
        }
        if CommandLine.arguments.contains("--demo-celebration") {
            CelebrationDemo.run()
        }
        if CommandLine.arguments.contains("--demo-number-animation") {
            NumberAnimationDemo.run()
        }
        if let index = CommandLine.arguments.firstIndex(of: "--dump-number-animation"),
           index + 1 < CommandLine.arguments.count {
            NumberAnimationDemo.dumpFrames(directory: CommandLine.arguments[index + 1])
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--dump-celebration"),
           index + 1 < CommandLine.arguments.count {
            CelebrationDemo.dumpFrames(directory: CommandLine.arguments[index + 1])
            return
        }
#endif
        if let index = CommandLine.arguments.firstIndex(of: "--dump-icons"),
           index + 1 < CommandLine.arguments.count {
            IconDump.run(directory: CommandLine.arguments[index + 1])
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--dump-card"),
           index + 1 < CommandLine.arguments.count {
            CardDump.run(directory: CommandLine.arguments[index + 1])
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--dump-settings"),
           index + 1 < CommandLine.arguments.count {
            CardDump.dumpSettings(directory: CommandLine.arguments[index + 1])
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
