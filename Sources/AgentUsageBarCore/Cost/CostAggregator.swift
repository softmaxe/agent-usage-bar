import Foundation

/// Turns the cache's day/model/tier rows into the numbers the popover shows.
enum CostAggregator {
    static func snapshot(
        provider: Provider,
        cache: CostCache,
        overlay: PricingOverlay?,
        windowDays: Int = 30,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> CostSnapshot {
        let start = calendar.date(byAdding: .day, value: -(windowDays - 1), to: now) ?? now
        let rows = try cache.aggregate(provider: provider, fromDay: DayKey.make(from: start, calendar: calendar))

        var days: [CostDay] = []
        // Cost and token totals per model across the whole window, for picking the top model.
        var modelCost: [String: Double] = [:]
        var modelTokens: [String: Int] = [:]
        var hasUnpriced = false

        for (dayKey, buckets) in rows {
            var dayTokens: [String: TokenTotals] = [:]
            // Per-model cost stays nil until something prices it, so an unpriced model reads as
            // "no price" in the breakdown rather than as zero dollars.
            var dayCostByModel: [String: Double] = [:]
            var dayCost = 0.0
            var dayPriced = false
            var dayUnpricedTokens = 0

            for (key, totals) in buckets {
                dayTokens[key.model, default: TokenTotals()] += totals
                modelTokens[key.model, default: 0] += totals.total

                if let cost = CostPricing.cost(
                    totals: totals,
                    model: key.model,
                    provider: provider,
                    longContext: key.longContext,
                    overlay: overlay
                ) {
                    dayCost += cost
                    dayPriced = true
                    dayCostByModel[key.model, default: 0] += cost
                    modelCost[key.model, default: 0] += cost
                } else {
                    // An unpriced model still counts toward token totals; leaving it out of the
                    // cost silently understates the bill, so it is surfaced in the footnote.
                    hasUnpriced = true
                    dayUnpricedTokens += totals.total
                }
            }

            let byModel = dayTokens.mapValues { tokens in
                ModelDayUsage(tokens: tokens, costUSD: nil)
            }
            .merging(
                dayCostByModel.map { model, cost in
                    (model, ModelDayUsage(tokens: dayTokens[model] ?? TokenTotals(), costUSD: cost))
                },
                uniquingKeysWith: { _, priced in priced }
            )

            days.append(CostDay(
                dayKey: dayKey,
                byModel: byModel,
                costUSD: dayPriced ? dayCost : nil,
                unpricedTokens: dayUnpricedTokens
            ))
        }

        days.sort { $0.dayKey < $1.dayKey }

        let todayKey = DayKey.make(from: now, calendar: calendar)
        let today = days.last { $0.dayKey == todayKey }
        let latest = days.last

        return CostSnapshot(
            provider: provider,
            days: days,
            todayCostUSD: today?.costUSD ?? 0,
            windowCostUSD: days.reduce(0) { $0 + ($1.costUSD ?? 0) },
            latestTokens: latest?.tokens.total ?? 0,
            windowTokens: days.reduce(0) { $0 + $1.tokens.total },
            topModel: Self.topModel(cost: modelCost, tokens: modelTokens),
            hasUnpricedTokens: hasUnpriced,
            scannedAt: now
        )
    }

    /// Highest accumulated cost wins; models with equal cost fall back to token count.
    static func topModel(cost: [String: Double], tokens: [String: Int]) -> String? {
        let candidates = Set(cost.keys).union(tokens.keys).subtracting([CostPricing.unknownModel])
        return candidates.max { lhs, rhs in
            let lhsCost = cost[lhs] ?? 0
            let rhsCost = cost[rhs] ?? 0
            if lhsCost != rhsCost { return lhsCost < rhsCost }
            return (tokens[lhs] ?? 0) < (tokens[rhs] ?? 0)
        }
    }
}
