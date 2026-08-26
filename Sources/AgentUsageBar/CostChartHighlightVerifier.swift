#if DEBUG
import Foundation

enum CostChartHighlightVerifier {
    static func run() -> Never {
        let yesterday = "2026-08-25"
        let today = "2026-08-26"
        let available = Set([yesterday, today])
        var failures: [String] = []

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

        let afterExit = CostChartHighlightPolicy.hoveredDayKey(
            afterMovingTo: nil,
            currentDayKey: yesterday
        )
        if afterExit != nil {
            failures.append("pointer exit expected hover to clear, got \(afterExit ?? "nil")")
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

        let noHoverLabel = CostChartHighlightPolicy.hoverLabelCost(
            dayKey: today,
            hoveredDayKey: nil,
            costUSD: 231
        )
        if noHoverLabel != nil {
            failures.append("a cost label appeared without a hovered bar")
        }

        let hoveredLabel = CostChartHighlightPolicy.hoverLabelCost(
            dayKey: yesterday,
            hoveredDayKey: yesterday,
            costUSD: 17
        )
        if hoveredLabel != 17 {
            failures.append("hovered bar expected its own $17 label, got \(String(describing: hoveredLabel))")
        }

        let otherBarLabel = CostChartHighlightPolicy.hoverLabelCost(
            dayKey: today,
            hoveredDayKey: yesterday,
            costUSD: 231
        )
        if otherBarLabel != nil {
            failures.append("a non-hovered bar displayed a cost label")
        }

        let unpricedLabel = CostChartHighlightPolicy.hoverLabelCost(
            dayKey: yesterday,
            hoveredDayKey: yesterday,
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
