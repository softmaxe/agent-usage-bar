import AgentUsageBarCore
import Foundation

// Headless check that both providers still return usable data. Run with `make probe`.

func describe(_ window: UsageWindow?, label: String) -> String {
    guard let window else { return "  \(label): (absent)" }
    var line = String(format: "  %@: %.1f%% left", label, window.remainingPercent)
    if let resetsAt = window.resetsAt {
        let remaining = resetsAt.timeIntervalSinceNow
        line += String(format: "  resets in %dh %dm", Int(remaining) / 3600, (Int(remaining) % 3600) / 60)
    }
    if let seconds = window.windowSeconds {
        line += "  (window \(seconds / 3600)h)"
    }
    return line
}

func report(_ provider: Provider, _ state: ProviderState) {
    print("[\(provider.displayName)]")
    switch state {
    case let .signedOut(reason):
        print("  signed out: \(reason)")
    case let .failed(reason):
        print("  FAILED: \(reason)")
    case let .loaded(snapshot):
        print("  plan: \(snapshot.planLabel ?? "(none)")")
        print(describe(snapshot.session, label: "session"))
        print(describe(snapshot.weekly, label: "weekly "))
        if let credits = snapshot.credits {
            print("  credits: has=\(credits.hasCredits) unlimited=\(credits.unlimited) balance=\(credits.balance.map { String($0) } ?? "nil")")
        }
    }
    print("")
}

let codex = await CodexProvider.fetch()
report(.codex, codex)

let claude = await ClaudeProvider.fetch()
report(.claude, claude)
