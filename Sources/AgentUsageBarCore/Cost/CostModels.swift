import Foundation

/// Token counts for one model on one day. The four buckets are disjoint and priced separately.
public struct TokenTotals: Sendable, Equatable {
    /// Fresh input tokens (Codex: `input_tokens` minus `cached_input_tokens`).
    public var input: Int
    public var output: Int
    /// Tokens written into the prompt cache.
    public var cacheWrite: Int
    /// Tokens served from the prompt cache.
    public var cacheRead: Int

    public init(input: Int = 0, output: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0) {
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
    }

    public var total: Int { self.input + self.output + self.cacheWrite + self.cacheRead }

    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            cacheRead: lhs.cacheRead + rhs.cacheRead
        )
    }

    public static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }
}

/// One local-calendar day of usage, already split by model.
public struct CostDay: Sendable, Equatable {
    /// `yyyy-MM-dd` in the local time zone, matching how the chart buckets days.
    public let dayKey: String
    public let byModel: [String: TokenTotals]
    public let costUSD: Double?
    /// Tokens whose model had no price, so they count toward totals but not toward cost.
    public let unpricedTokens: Int

    public init(dayKey: String, byModel: [String: TokenTotals], costUSD: Double?, unpricedTokens: Int) {
        self.dayKey = dayKey
        self.byModel = byModel
        self.costUSD = costUSD
        self.unpricedTokens = unpricedTokens
    }

    public var tokens: TokenTotals {
        self.byModel.values.reduce(into: TokenTotals()) { $0 += $1 }
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
