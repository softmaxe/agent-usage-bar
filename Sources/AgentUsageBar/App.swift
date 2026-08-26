import AgentUsageBarCore
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private lazy var store = UsageStore(settings: self.settings)
    private var controller: StatusItemController?

    func applicationDidFinishLaunching(_: Notification) {
        self.controller = StatusItemController(store: self.store, settings: self.settings)
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
