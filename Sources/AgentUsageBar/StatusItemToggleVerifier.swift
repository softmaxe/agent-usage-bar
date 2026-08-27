#if DEBUG
import AgentUsageBarCore
import AppKit
import Foundation

/// The menu bar carries exactly one item, and a right-click moves it between providers. This
/// hammers that switch to prove the item is reused rather than torn down and rebuilt.
@MainActor
enum StatusItemToggleVerifier {
    /// One fixed domain rather than one per process: every exit here goes through `exit()`, which
    /// unwinds nothing, so a PID-stamped name would strand a fresh plist in ~/Library/Preferences
    /// on every run. The runs are serial, and the domain is emptied on both ends regardless.
    private static let suite = "AgentUsageBarToggleVerifier"
    /// Held so the exit path can reach the domain this run wrote to.
    private static var defaults: UserDefaults?

    static func run() -> Never {
        let defaults = UserDefaults(suiteName: Self.suite) ?? .standard
        Self.defaults = defaults
        defaults.removePersistentDomain(forName: Self.suite)

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let settings = SettingsStore(defaults: defaults)
        let costService = CostService()
        let store = UsageStore(settings: settings, costService: costService)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            pricing: PricingEditorModel(costService: costService)
        )

        Self.drainMainRunLoop()
        let first = settings.menuBarProvider
        Self.requireItem(showing: first, controller: controller, step: "initial item")

        for iteration in 1 ... 1_000 {
            let before = settings.menuBarProvider
            let expected = MenuBarProviderPolicy.next(after: before)

            controller.debugSecondaryClick()
            Self.drainMainRunLoop(for: 0.002)

            guard settings.menuBarProvider == expected else {
                Self.fail(
                    "iteration \(iteration) right-click went to \(settings.menuBarProvider.rawValue), "
                        + "expected \(expected.rawValue)"
                )
            }
            Self.requireItem(
                showing: expected,
                controller: controller,
                step: "iteration \(iteration) after switching to \(expected.rawValue)"
            )
        }

        // Two providers and a wrapping cycle: an even number of switches lands back at the start.
        guard settings.menuBarProvider == first else {
            Self.fail("cycling 1,000 times did not return to \(first.rawValue)")
        }

        print("1,000 rapid provider switches passed on a single status item")
        Self.finish(0)
    }

    /// The only way out, so the throwaway domain is dropped on the failing paths too. `defer`
    /// cannot do this job: `exit()` terminates the process without unwinding the stack.
    private static func finish(_ code: Int32) -> Never {
        Self.defaults?.removePersistentDomain(forName: Self.suite)
        exit(code)
    }

    private static func requireItem(
        showing provider: Provider,
        controller: StatusItemController,
        step: String
    ) {
        let state = controller.debugStatusItemState()
        guard state.exists, state.visible, state.attached, state.stableIdentity else {
            Self.fail("\(step) was not materialized: \(state)")
        }
        guard state.provider == provider else {
            Self.fail("\(step) shows \(state.provider.rawValue), expected \(provider.rawValue)")
        }
    }

    private static func drainMainRunLoop(for seconds: TimeInterval = 0.02) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private static func fail(_ message: String) -> Never {
        fputs("menu switch verification failed: \(message)\n", stderr)
        Self.finish(1)
    }
}
#endif
