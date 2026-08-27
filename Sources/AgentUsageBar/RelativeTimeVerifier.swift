#if DEBUG
import AgentUsageBarCore
import AppKit
import Foundation

/// Proves an open menu advances its relative timestamp while no provider refresh is published.
@MainActor
enum RelativeTimeVerifier {
    /// Fixed, not PID-stamped, for the reason spelled out in `finish`.
    private static let suite = "AgentUsageBarRelativeTimeVerifier"
    /// Held so the exit path can reach the domain this run wrote to.
    private static var defaults: UserDefaults?

    static func run() -> Never {
        let defaults = UserDefaults(suiteName: Self.suite) ?? .standard
        Self.defaults = defaults
        defaults.removePersistentDomain(forName: Self.suite)

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var now = base
        let settings = SettingsStore(defaults: defaults)
        let costService = CostService()
        let store = UsageStore(settings: settings, costService: costService)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            pricing: PricingEditorModel(costService: costService),
            now: { now },
            openMenuClockInterval: 0.01
        )

        var display = ProviderDisplay()
        display.snapshot = UsageSnapshot(
            provider: .codex,
            session: nil,
            weekly: nil,
            planLabel: "Plus",
            credits: nil,
            fetchedAt: base
        )
        store.debugSetDisplay(display, for: .codex)
        controller.debugRefreshOpenCard()

        Self.require(
            controller.debugStatusLine() == "Updated just now",
            "initial label was \(controller.debugStatusLine() ?? "nil")"
        )

        now = base.addingTimeInterval(120)
        controller.debugStartOpenMenuClock()
        let deadline = Date().addingTimeInterval(0.05)
        while Date() < deadline {
            _ = RunLoop.main.run(mode: .eventTracking, before: deadline)
        }
        controller.debugStopOpenMenuClock()

        Self.require(
            controller.debugStatusLine() == "Updated 2m ago",
            "label after two minutes was \(controller.debugStatusLine() ?? "nil")"
        )

        print("Open-menu relative time advanced without a provider refresh")
        Self.finish(0)
    }

    /// The only way out, so the throwaway domain is dropped on the failing paths too. `defer`
    /// cannot do this job: `exit()` terminates the process without unwinding the stack.
    private static func finish(_ code: Int32) -> Never {
        Self.defaults?.removePersistentDomain(forName: Self.suite)
        exit(code)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("relative-time verification failed: \(message)\n", stderr)
            Self.finish(1)
        }
    }
}
#endif
