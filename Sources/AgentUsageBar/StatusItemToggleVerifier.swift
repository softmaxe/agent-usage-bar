#if DEBUG
import AgentUsageBarCore
import AppKit
import Foundation

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
        Self.requireVisible(.codex, controller: controller, step: "initial Codex")
        Self.requireVisible(.claude, controller: controller, step: "initial Claude")

        for iteration in 1 ... 1_000 {
            settings.setEnabled(false, for: .codex)
            Self.drainMainRunLoop(for: 0.002)
            let hidden = controller.debugStatusItemState(for: .codex)
            guard !hidden.exists else {
                Self.fail("iteration \(iteration) Codex stayed present after disable: \(hidden)")
            }

            settings.setEnabled(true, for: .codex)
            Self.drainMainRunLoop(for: 0.002)
            Self.requireVisible(.codex, controller: controller, step: "iteration \(iteration) Codex re-enable")
            Self.requireVisible(.claude, controller: controller, step: "iteration \(iteration) Claude unaffected")
        }

        print("1,000 rapid Codex toggle cycles passed")
        exit(0)
    }

    private static func requireVisible(
        _ provider: Provider,
        controller: StatusItemController,
        step: String
    ) {
        let state = controller.debugStatusItemState(for: provider)
        guard state.exists, state.visible, state.attached, state.stableIdentity else {
            Self.fail("\(step) was not materialized: \(state)")
        }
    }

    private static func drainMainRunLoop(for seconds: TimeInterval = 0.02) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private static func fail(_ message: String) -> Never {
        fputs("menu toggle verification failed: \(message)\n", stderr)
        exit(1)
    }
}
#endif
