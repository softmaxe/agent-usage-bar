#if DEBUG
import AgentUsageBarCore
import Foundation
import SwiftUI

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
        let emptyTodayLabel = CostChartHighlightPolicy.labelText(
            dayKey: today,
            selectedDayKey: emptyTodaySelection,
            selectedMode: .tokens,
            tokens: visibleWithoutToday.last?.tokens.total ?? -1,
            costUSD: visibleWithoutToday.last?.costUSD
        )
        if emptyTodayLabel != "0" {
            failures.append("an empty today bar expected its default 0 token label")
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

        let defaultLabel = CostChartHighlightPolicy.labelText(
            dayKey: today,
            selectedDayKey: defaultSelection,
            selectedMode: .tokens,
            tokens: 231_000_000,
            costUSD: 231
        )
        if defaultLabel != "231M" {
            failures.append("default today bar expected its 231M token label, got \(String(describing: defaultLabel))")
        }

        let clickedMode = CostChartHighlightPolicy.labelMode(
            afterClicking: yesterday,
            selectedDayKey: hoverSelection,
            currentMode: .tokens
        )
        let hoveredLabel = CostChartHighlightPolicy.labelText(
            dayKey: yesterday,
            selectedDayKey: hoverSelection,
            selectedMode: clickedMode,
            tokens: 17_000_000,
            costUSD: 17
        )
        if hoveredLabel != "$17" {
            failures.append("clicked hovered bar expected its $17 label, got \(String(describing: hoveredLabel))")
        }

        let clickedAgainMode = CostChartHighlightPolicy.labelMode(
            afterClicking: yesterday,
            selectedDayKey: hoverSelection,
            currentMode: clickedMode
        )
        if clickedAgainMode != .tokens {
            failures.append("clicking the selected bar again expected its token label")
        }

        let otherBarLabel = CostChartHighlightPolicy.labelText(
            dayKey: today,
            selectedDayKey: hoverSelection,
            selectedMode: clickedMode,
            tokens: 231_000_000,
            costUSD: 231
        )
        if otherBarLabel != nil {
            failures.append("a non-hovered bar displayed a label")
        }

        let zeroCostLabel = CostChartHighlightPolicy.labelText(
            dayKey: yesterday,
            selectedDayKey: hoverSelection,
            selectedMode: .cost,
            tokens: 0,
            costUSD: nil
        )
        if zeroCostLabel != "$0.00" {
            failures.append("a selected day with missing cost data expected $0.00")
        }

        let ignoredClickMode = CostChartHighlightPolicy.labelMode(
            afterClicking: today,
            selectedDayKey: hoverSelection,
            currentMode: .tokens
        )
        if ignoredClickMode != .tokens {
            failures.append("clicking a non-selected bar changed the selected label mode")
        }

        let nextBarLabel = CostChartHighlightPolicy.labelText(
            dayKey: today,
            selectedDayKey: today,
            selectedMode: clickedMode,
            tokens: 231_000_000,
            costUSD: 231
        )
        if nextBarLabel != "$231" {
            failures.append("moving to another selected bar forgot the cost label mode")
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

        // The highlight's motion: a move between bars keeps up with the pointer, the trip back to
        // today takes longer, and Reduce Motion drops both rather than shortening them.
        if CostChartHoverMotion.returnResponse <= CostChartHoverMotion.hoverResponse {
            failures.append(
                "returning to today expected a longer response than moving between bars, got "
                    + "\(CostChartHoverMotion.returnResponse) vs \(CostChartHoverMotion.hoverResponse)"
            )
        }
        if CostChartHoverMotion.lift <= 0 {
            failures.append("the selected bar expected a lift, got \(CostChartHoverMotion.lift)")
        }
        let hoverMotion = CostChartHoverMotion.animation(returningToToday: false, reduceMotion: false)
        let returnMotion = CostChartHoverMotion.animation(returningToToday: true, reduceMotion: false)
        if hoverMotion == nil || returnMotion == nil || hoverMotion == returnMotion {
            failures.append("hover and return expected two distinct animations")
        }
        let reducedHover = CostChartHoverMotion.animation(returningToToday: false, reduceMotion: true)
        let reducedReturn = CostChartHoverMotion.animation(returningToToday: true, reduceMotion: true)
        if reducedHover != nil || reducedReturn != nil {
            failures.append("Reduce Motion expected no animation on either move")
        }

        // The unit swap: the label resolves rather than cuts, it stays in place while it does,
        // and Reduce Motion drops the resolve rather than shortening it.
        if CostChartHoverMotion.swapDuration <= 0 {
            failures.append(
                "the unit swap expected a duration, got \(CostChartHoverMotion.swapDuration)"
            )
        }
        if CostChartHoverMotion.swapBlur <= 0 || CostChartHoverMotion.swapScale >= 1 {
            failures.append(
                "the unit swap expected to blur and undersize the outgoing number, got "
                    + "\(CostChartHoverMotion.swapBlur)/\(CostChartHoverMotion.swapScale)"
            )
        }
        let swapMotion = CostChartHoverMotion.swapAnimation(reduceMotion: false)
        if swapMotion == nil || swapMotion == hoverMotion {
            failures.append("the unit swap expected an animation of its own, distinct from a hover")
        }
        if CostChartHoverMotion.swapAnimation(reduceMotion: true) != nil {
            failures.append("Reduce Motion expected no animation on the unit swap")
        }

        guard failures.isEmpty else {
            for failure in failures {
                fputs("cost chart highlight verification failed: \(failure)\n", stderr)
            }
            exit(1)
        }

        print(
            "cost chart selection, click label toggle, hit testing, opacity, hover motion, and "
                + "unit swap motion checks passed"
        )
        exit(0)
    }
}
#endif
