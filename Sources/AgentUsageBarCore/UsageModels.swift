import Foundation

/// The two providers this app tracks.
public enum Provider: String, CaseIterable, Sendable, Codable {
    case codex
    case claude

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        }
    }
}

/// One rate-limit window (Codex primary/secondary, Claude five-hour/seven-day).
public struct UsageWindow: Sendable, Equatable {
    /// Percentage of the window already consumed, 0...100.
    public let usedPercent: Double
    public let resetsAt: Date?
    /// Length of the window in seconds, when the provider reports it.
    public let windowSeconds: Int?

    public init(usedPercent: Double, resetsAt: Date?, windowSeconds: Int?) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowSeconds = windowSeconds
    }

    /// Percentage still available, clamped to 0...100.
    public var remainingPercent: Double {
        max(0, min(100, 100 - self.usedPercent))
    }
}

/// Codex pay-as-you-go credit balance. Claude does not report this.
public struct CreditsSnapshot: Sendable, Equatable {
    public let hasCredits: Bool
    public let unlimited: Bool
    public let balance: Double?

    public init(hasCredits: Bool, unlimited: Bool, balance: Double?) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }

    /// True only when there is a balance worth showing. An account with no credits at all,
    /// or one drained to zero, reports the same thing an empty bar would — so the popover
    /// drops the section instead of rendering "0 left".
    public var hasSpendableBalance: Bool {
        if self.unlimited { return true }
        guard self.hasCredits, let balance = self.balance else { return false }
        return balance > 0
    }
}

/// Everything the menu bar and the popover need for one provider at one point in time.
public struct UsageSnapshot: Sendable, Equatable {
    public let provider: Provider
    /// Short rolling window: Codex `primary_window`, Claude `five_hour`.
    public let session: UsageWindow?
    /// Weekly window: Codex `secondary_window`, Claude `seven_day`.
    public let weekly: UsageWindow?
    /// Plan label shown top-right in the popover ("Plus", "Max", ...).
    public let planLabel: String?
    public let credits: CreditsSnapshot?
    public let fetchedAt: Date

    public init(
        provider: Provider,
        session: UsageWindow?,
        weekly: UsageWindow?,
        planLabel: String?,
        credits: CreditsSnapshot?,
        fetchedAt: Date
    ) {
        self.provider = provider
        self.session = session
        self.weekly = weekly
        self.planLabel = planLabel
        self.credits = credits
        self.fetchedAt = fetchedAt
    }
}

/// Result of one refresh attempt: either a snapshot or the reason it failed.
public enum ProviderState: Sendable {
    /// No credentials on this machine — the status item stays hidden.
    case signedOut(String)
    case failed(String)
    case loaded(UsageSnapshot)
}
