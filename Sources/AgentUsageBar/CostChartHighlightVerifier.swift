#if DEBUG
import AgentUsageBarCore
import Foundation

enum CostChartHighlightVerifier {
    static func run() -> Never {
        let yesterday = "2026-08-25"
        let today = "2026-08-26"
        let available = Set([yesterday, today])
        var failures: [String] = []

        let previousDay = CostDay(
            dayKey: yesterday,
            byModel: [:],
            costUSD: 17,
            unpricedTokens: 0
        )
        let visibleWithoutToday = CostChartHighlightPolicy.visibleDays(
            from: [previousDay],
            todayDayKey: today,
            maxBars: 10
        )
        if visibleWithoutToday.map(\.dayKey) != [yesterday, today]
            || visibleWithoutToday.last?.costUSD != 0 {
            failures.append("a missing today expected a zero-cost today bar")
        }
        let emptyTodaySelection = CostChartHighlightPolicy.selectedDayKey(
            hoveredDayKey: nil,
            todayDayKey: today,
            availableDayKeys: Set(visibleWithoutToday.map(\.dayKey))
        )
        let emptyTodayLabel = CostChartHighlightPolicy.labelCost(
            dayKey: today,
            selectedDayKey: emptyTodaySelection,
            costUSD: visibleWithoutToday.last?.costUSD
        )
        if emptyTodayLabel != 0 {
            failures.append("an empty today bar expected its default $0 label")
        }

        let todayDay = CostDay(
            dayKey: today,
            byModel: [:],
            costUSD: 23,
            unpricedTokens: 0
        )
        let visibleWithToday = CostChartHighlightPolicy.visibleDays(
            from: [previousDay, todayDay],
            todayDayKey: today,
            maxBars: 10
        )
        if visibleWithToday.map(\.dayKey) != [yesterday, today]
            || visibleWithToday.last?.costUSD != 23 {
            failures.append("an existing today bar was duplicated or replaced")
        }

        let capped = CostChartHighlightPolicy.visibleDays(
            from: (1...10).map { day in
                CostDay(
                    dayKey: String(format: "2026-08-%02d", day),
                    byModel: [:],
                    costUSD: Double(day),
                    unpricedTokens: 0
                )
            },
            todayDayKey: today,
            maxBars: 10
        )
        if capped.count != 10 || capped.first?.dayKey != "2026-08-02" || capped.last?.dayKey != today {
            failures.append("adding today expected to keep the ten-bar cap and evict the oldest day")
        }

        let defaultSelection = CostChartHighlightPolicy.selectedDayKey(
            hoveredDayKey: nil,
            todayDayKey: today,
            availableDayKeys: available
        )
        if defaultSelection != today {
            failures.append("default selection expected today, got \(defaultSelection ?? "nil")")
        }

        let hoverSelection = CostChartHighlightPolicy.selectedDayKey(
            hoveredDayKey: yesterday,
            todayDayKey: today,
            availableDayKeys: available
        )
        if hoverSelection != yesterday {
            failures.append("hover selection expected yesterday, got \(hoverSelection ?? "nil")")
        }

        let acrossGap = CostChartHighlightPolicy.hoveredDayKey(
            afterMovingTo: nil,
            currentDayKey: yesterday
        )
        if acrossGap != yesterday {
            failures.append("gap between bars expected hover to hold, got \(acrossGap ?? "nil")")
        }

        let ontoNextBar = CostChartHighlightPolicy.hoveredDayKey(
            afterMovingTo: today,
            currentDayKey: yesterday
        )
        if ontoNextBar != today {
            failures.append("moving onto a bar expected it to take hover, got \(ontoNextBar ?? "nil")")
        }

        let shortInactive = CostChartHighlightPolicy.opacity(
            dayKey: yesterday,
            selectedDayKey: today,
            valueRatio: 0.1
        )
        let tallInactive = CostChartHighlightPolicy.opacity(
            dayKey: yesterday,
            selectedDayKey: today,
            valueRatio: 1.0
        )
        if shortInactive != tallInactive {
            failures.append("inactive opacity varied by bar height: \(shortInactive) vs \(tallInactive)")
        }

        let defaultLabel = CostChartHighlightPolicy.labelCost(
            dayKey: today,
            selectedDayKey: defaultSelection,
            costUSD: 231
        )
        if defaultLabel != 231 {
            failures.append("default today bar expected its $231 label, got \(String(describing: defaultLabel))")
        }

        let hoveredLabel = CostChartHighlightPolicy.labelCost(
            dayKey: yesterday,
            selectedDayKey: hoverSelection,
            costUSD: 17
        )
        if hoveredLabel != 17 {
            failures.append("hovered bar expected its own $17 label, got \(String(describing: hoveredLabel))")
        }

        let otherBarLabel = CostChartHighlightPolicy.labelCost(
            dayKey: today,
            selectedDayKey: hoverSelection,
            costUSD: 231
        )
        if otherBarLabel != nil {
            failures.append("a non-hovered bar displayed a cost label")
        }

        let unpricedLabel = CostChartHighlightPolicy.labelCost(
            dayKey: yesterday,
            selectedDayKey: hoverSelection,
            costUSD: nil
        )
        if unpricedLabel != nil {
            failures.append("an unpriced hovered bar displayed a dollar label")
        }

        let firstBar = CostChartHighlightPolicy.barIndex(atX: 47, width: 100, barCount: 2, spacing: 4)
        let gap = CostChartHighlightPolicy.barIndex(atX: 49, width: 100, barCount: 2, spacing: 4)
        let secondBar = CostChartHighlightPolicy.barIndex(atX: 53, width: 100, barCount: 2, spacing: 4)
        if firstBar != 0 || gap != nil || secondBar != 1 {
            failures.append(
                "bar hit testing expected 0/nil/1 across a gap, got "
                    + "\(String(describing: firstBar))/\(String(describing: gap))/"
                    + "\(String(describing: secondBar))"
            )
        }

        guard failures.isEmpty else {
            for failure in failures {
                fputs("cost chart highlight verification failed: \(failure)\n", stderr)
            }
            exit(1)
        }

        print("cost chart selection, hover label, hit testing, and opacity checks passed")
        exit(0)
    }
}
#endif
