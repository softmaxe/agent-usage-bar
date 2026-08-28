#if DEBUG
import AgentUsageBarCore
import Foundation

/// The month both cost-chart studies are judged against, so `--demo-bar-hover` and
/// `--demo-label-toggle` cannot end up arguing about different data.
///
/// Ten days shaped like a real month: one spike, a quiet stretch, and a modest today. The quiet
/// stretch makes the trip home a long one, so the return animation is actually visible; the spike
/// is big enough that its token label and its cost label are different lengths — "163M" against
/// "$196" — because a unit swap that only looks good on equal-width strings is not one that ships.
enum CostChartDemoData {
    private static let costs: [Double] = [8, 12, 26, 41, 9, 30, 34, 196, 15, 22]

    static func days(today: Date = Date()) -> [CostDay] {
        let calendar = Calendar.current
        return Self.costs.enumerated().compactMap { index, cost in
            guard let date = calendar.date(
                byAdding: .day,
                value: index - (Self.costs.count - 1),
                to: today
            ) else { return nil }
            return CostDay(
                dayKey: Formatters.dayKey(for: date),
                byModel: [
                    "opus-5": ModelDayUsage(
                        tokens: TokenTotals(
                            input: Int(cost * 1_400),
                            output: Int(cost * 320),
                            cacheWrite: Int(cost * 2_100),
                            cacheRead: Int(cost * 9_600)
                        ),
                        costUSD: cost * 0.72
                    ),
                    "haiku-4.5": ModelDayUsage(
                        tokens: TokenTotals(
                            input: Int(cost * 900),
                            output: Int(cost * 180),
                            cacheRead: Int(cost * 3_100)
                        ),
                        costUSD: cost * 0.28
                    ),
                ],
                costUSD: cost,
                unpricedTokens: 0
            )
        }
    }

    static func todayDayKey(today: Date = Date()) -> String {
        Formatters.dayKey(for: today)
    }
}
#endif
