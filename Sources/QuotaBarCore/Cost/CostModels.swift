import Foundation

/// Token counts for one model on one day. The four buckets are disjoint and priced separately.
public struct TokenTotals: Sendable, Equatable {
    /// Fresh input tokens (Codex: `input_tokens` minus `cached_input_tokens`).
    public var input: Int
    public var output: Int
    /// Tokens written into the prompt cache, both TTLs together.
    public var cacheWrite: Int
    /// The subset of `cacheWrite` written with a one-hour TTL, which Anthropic prices higher.
    /// Always zero for Codex, which offers no choice of cache lifetime.
    public var cacheWrite1h: Int
    /// Tokens served from the prompt cache.
    public var cacheRead: Int

    public init(
        input: Int = 0,
        output: Int = 0,
        cacheWrite: Int = 0,
        cacheWrite1h: Int = 0,
        cacheRead: Int = 0
    ) {
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheWrite1h = min(cacheWrite1h, cacheWrite)
        self.cacheRead = cacheRead
    }

    /// `cacheWrite1h` is a subset of `cacheWrite`, so counting it here would double it.
    public var total: Int { self.input + self.output + self.cacheWrite + self.cacheRead }

    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            cacheWrite1h: lhs.cacheWrite1h + rhs.cacheWrite1h,
            cacheRead: lhs.cacheRead + rhs.cacheRead
        )
    }

    public static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }
}

/// What one model did on one day.
public struct ModelDayUsage: Sendable, Equatable {
    public let tokens: TokenTotals
    /// nil when the model has no price, so its tokens count but its cost does not.
    public let costUSD: Double?

    public init(tokens: TokenTotals, costUSD: Double?) {
        self.tokens = tokens
        self.costUSD = costUSD
    }
}

/// One local-calendar day of usage, already split by model.
public struct CostDay: Sendable, Equatable {
    /// `yyyy-MM-dd` in the local time zone, matching how the chart buckets days.
    public let dayKey: String
    public let byModel: [String: ModelDayUsage]
    public let costUSD: Double?
    /// Tokens whose model had no price, so they count toward totals but not toward cost.
    public let unpricedTokens: Int

    public init(dayKey: String, byModel: [String: ModelDayUsage], costUSD: Double?, unpricedTokens: Int) {
        self.dayKey = dayKey
        self.byModel = byModel
        self.costUSD = costUSD
        self.unpricedTokens = unpricedTokens
    }

    public var tokens: TokenTotals {
        self.byModel.values.reduce(into: TokenTotals()) { $0 += $1.tokens }
    }

    /// Models that ran that day, most expensive first; unpriced models sort by token count
    /// behind every priced one.
    public var rankedModels: [(model: String, usage: ModelDayUsage)] {
        self.byModel
            .map { (model: $0.key, usage: $0.value) }
            .sorted { lhs, rhs in
                let lhsCost = lhs.usage.costUSD ?? -1
                let rhsCost = rhs.usage.costUSD ?? -1
                if lhsCost != rhsCost { return lhsCost > rhsCost }
                if lhs.usage.tokens.total != rhs.usage.tokens.total {
                    return lhs.usage.tokens.total > rhs.usage.tokens.total
                }
                return lhs.model < rhs.model
            }
    }
}

/// What the popover's cost section shows for one provider.
public struct CostSnapshot: Sendable, Equatable {
    public let provider: Provider
    /// Ascending by day; only days with activity appear, which is why the chart's bar count varies.
    public let days: [CostDay]
    public let todayCostUSD: Double
    public let windowCostUSD: Double
    /// Tokens on the most recent day that had any activity, which is not always today.
    public let latestTokens: Int
    public let windowTokens: Int
    /// Model with the highest cost in the window, falling back to token count when nothing is priced.
    public let topModel: String?
    /// True when at least one model in the window had no price entry.
    public let hasUnpricedTokens: Bool
    public let scannedAt: Date

    public init(
        provider: Provider,
        days: [CostDay],
        todayCostUSD: Double,
        windowCostUSD: Double,
        latestTokens: Int,
        windowTokens: Int,
        topModel: String?,
        hasUnpricedTokens: Bool,
        scannedAt: Date
    ) {
        self.provider = provider
        self.days = days
        self.todayCostUSD = todayCostUSD
        self.windowCostUSD = windowCostUSD
        self.latestTokens = latestTokens
        self.windowTokens = windowTokens
        self.topModel = topModel
        self.hasUnpricedTokens = hasUnpricedTokens
        self.scannedAt = scannedAt
    }
}

enum DayKey {
    /// Days bucket by the local calendar, so "today" matches what the user's clock says.
    static func make(from date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func today(calendar: Calendar = .current, now: Date = Date()) -> String {
        self.make(from: now, calendar: calendar)
    }
}
