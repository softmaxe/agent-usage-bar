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

        guard failures.isEmpty else {
            for failure in failures {
                fputs("cost chart highlight verification failed: \(failure)\n", stderr)
            }
            exit(1)
        }

        print("cost chart default, hover, exit, and inactive opacity checks passed")
        exit(0)
    }
}
#endif
