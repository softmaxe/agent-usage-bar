import AgentUsageBarCore
import SwiftUI

/// The cost half of the popover: a KPI grid, the per-day bar chart, the top model, and the
/// estimate disclaimer.
struct CostSectionView: View {
    let provider: Provider
    let snapshot: CostSnapshot

    /// The chart stays readable at card width; older days fall off the left.
    private static let maxBars = 10
    private static let chartHeight: CGFloat = 56
    private static let barSpacing: CGFloat = 4

    /// Which day the pointer is over. It sticks after the pointer leaves, matching CodexBar,
    /// so the reading stays put while you move toward it.
    @State private var hoveredDayKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            self.kpiGrid
            if !self.bars.isEmpty {
                self.chart
            }
            // Reserves a line so the card does not resize as the pointer moves across bars.
            Text(self.hoverLine)
                .font(.system(size: 11))
                .foregroundStyle(self.hoveredDay == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)

            if let topModel = self.snapshot.topModel {
                Text("Top model: \(topModel)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text(self.disclaimer)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - KPIs

    private var kpiGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                self.kpi(label: "Today", value: Formatters.cost(self.snapshot.todayCostUSD))
                self.kpi(label: self.windowCostLabel, value: Formatters.cost(self.snapshot.windowCostUSD))
            }
            GridRow {
                self.kpi(label: "Latest tokens", value: Formatters.tokens(self.snapshot.latestTokens))
                self.kpi(label: "30d tokens", value: Formatters.tokens(self.snapshot.windowTokens))
            }
        }
    }

    /// Codex labels the window plainly; Claude spells out that the figure is a cost.
    private var windowCostLabel: String {
        self.provider == .codex ? "30d" : "30d cost"
    }

    private func kpi(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
        }
        .gridColumnAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Chart

    /// Only days with activity get a bar, which is why the bar count varies by provider.
    private var bars: [CostDay] {
        Array(self.snapshot.days.suffix(Self.maxBars))
    }

    private var maxValue: Double {
        self.bars.map { $0.costUSD ?? 0 }.max() ?? 0
    }

    private var chart: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(Formatters.compactCost(self.maxValue))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: Self.barSpacing) {
                ForEach(self.bars, id: \.dayKey) { day in
                    self.bar(for: day)
                }
            }
            .frame(height: Self.chartHeight)
            .overlay {
                GeometryReader { geometry in
                    MouseLocationReader { location in
                        self.updateHover(at: location, width: geometry.size.width)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func bar(for day: CostDay) -> some View {
        let value = day.costUSD ?? 0
        let ratio = self.maxValue > 0 ? value / self.maxValue : 0
        let isHovered = day.dayKey == self.hoveredDayKey
        // Taller bars read as more saturated, so the shape and the tone agree. The hovered bar
        // goes fully opaque instead of gaining a border, which would shift the layout.
        let opacity = isHovered ? 1.0 : 0.55 + 0.45 * ratio
        return RoundedRectangle(cornerRadius: 2)
            .fill(Theme.accent(for: self.provider).opacity(opacity))
            // A day with a trace of spend still deserves a visible sliver.
            .frame(height: max(4, Self.chartHeight * ratio))
            .frame(maxWidth: .infinity)
    }

    // MARK: - Hover

    private var hoveredDay: CostDay? {
        guard let key = self.hoveredDayKey else { return nil }
        return self.bars.first { $0.dayKey == key }
    }

    /// The day's own numbers when hovering, otherwise the window summary.
    private var hoverLine: String {
        guard let day = self.hoveredDay else {
            return "\(self.bars.count) days with activity · hover a bar for a day"
        }
        var parts = [Self.dayLabel(day.dayKey), Formatters.cost(day.costUSD ?? 0)]
        let tokens = day.tokens.total
        if tokens > 0 { parts.append("\(Formatters.tokens(tokens)) tokens") }
        if let model = Self.dominantModel(of: day) { parts.append(model) }
        return parts.joined(separator: " · ")
    }

    private func updateHover(at location: CGPoint?, width: CGFloat) {
        // Keep the last day selected when the pointer leaves, so the reading does not vanish
        // as you move toward it.
        guard let location, !self.bars.isEmpty, width > 0 else { return }
        let count = CGFloat(self.bars.count)
        let slot = (width - Self.barSpacing * (count - 1)) / count + Self.barSpacing
        guard slot > 0 else { return }
        let index = min(self.bars.count - 1, max(0, Int(location.x / slot)))
        let key = self.bars[index].dayKey
        if self.hoveredDayKey != key { self.hoveredDayKey = key }
    }

    /// "2026-08-24" -> "Aug 24".
    private static func dayLabel(_ dayKey: String) -> String {
        let parts = dayKey.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month) else { return dayKey }
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(names[month - 1]) \(day)"
    }

    private static func dominantModel(of day: CostDay) -> String? {
        day.byModel.max { $0.value.total < $1.value.total }?.key
    }

    // MARK: - Disclaimer

    private var disclaimer: String {
        var text = switch self.provider {
        case .claude:
            "Estimated from local Claude logs at API rates; token totals include cache read/write tokens."
        case .codex:
            "Estimated from token usage · not a subscription bill"
        }
        if self.snapshot.hasUnpricedTokens {
            text += " Some models have no price and are excluded from cost."
        }
        return text
    }
}

/// Codex's pay-as-you-go credit balance. Claude does not report one.
struct CreditsSectionView: View {
    let credits: CreditsSnapshot

    /// CodexBar scales the credit bar against a 1000-token cap.
    private static let cap: Double = 1000

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Credits")
                .font(.system(size: 13, weight: .semibold))
            UsageProgressBar(
                percent: self.credits.unlimited ? 100 : min(100, (self.credits.balance ?? 0) / Self.cap * 100),
                tint: Theme.accent(for: .codex)
            )
            HStack {
                Text(self.leftLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("1K tokens")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var leftLabel: String {
        if self.credits.unlimited { return "Unlimited" }
        return "\(Int((self.credits.balance ?? 0).rounded())) left"
    }
}
