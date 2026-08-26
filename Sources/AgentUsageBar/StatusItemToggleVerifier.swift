#if DEBUG
import AgentUsageBarCore
import AppKit
import Foundation

/// The menu bar carries exactly one item, and a right-click moves it between providers. This
/// hammers that switch to prove the item is reused rather than torn down and rebuilt.
@MainActor
enum StatusItemToggleVerifier {
    static func run() -> Never {
        let suite = "AgentUsageBarToggleVerifier-\(ProcessInfo.processInfo.processIdentifier)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

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
        exit(0)
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
        exit(1)
    }
}
#endif
