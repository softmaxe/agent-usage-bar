import QuotaBarCore
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
    case let .recoveryRequired(reason):
        print("  RECOVERY REQUIRED: \(reason)")
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

func reportCost(_ provider: Provider, _ snapshot: CostSnapshot?) {
    guard let snapshot else {
        print("  cost: unavailable")
        return
    }
    let tokens = { (count: Int) in String(format: "%.0fM", Double(count) / 1_000_000) }
    print("  today $\(String(format: "%.2f", snapshot.todayCostUSD))  30d $\(String(format: "%.2f", snapshot.windowCostUSD))")
    print("  latest tokens \(tokens(snapshot.latestTokens))  30d tokens \(tokens(snapshot.windowTokens))")
    print("  days with data: \(snapshot.days.count)  top model: \(snapshot.topModel ?? "(none)")")
    if snapshot.hasUnpricedTokens { print("  NOTE: some tokens had no price entry") }
}

let costService = CostService()
// Scanning the logs needs no credentials and no network, so it can be checked on its own.
let costOnly = CommandLine.arguments.contains("--cost-only")

for provider in Provider.allCases {
    if !costOnly {
        switch provider {
        case .codex: report(.codex, await CodexProvider.fetch())
        case .claude: report(.claude, await ClaudeProvider.fetch())
        }
    } else {
        print("[\(provider.displayName)]")
    }
    let started = Date()
    reportCost(provider, await costService.refresh(provider))
    print(String(format: "  scan took %.1fs", Date().timeIntervalSince(started)))
    print("")
}
