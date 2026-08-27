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
    /// Four covers a normal day for either provider; the rest collapse into a "+N more" line.
    private static let maxBreakdownRows = 4
    private static let summaryLineHeight: CGFloat = 14
    private static let breakdownRowHeight: CGFloat = 13
    private static let overflowLineHeight: CGFloat = 12
    private static let detailSpacing: CGFloat = 3

    /// Which day the pointer is over. Nil falls back to today's bar.
    @State private var hoveredDayKey: String?
    /// Updated immediately on click, then seeded from SettingsStore whenever the card is rebuilt.
    @State private var selectedLabelMode: CostChartLabelMode
    private let todayDayKey: String
    private let onLabelModeChanged: (CostChartLabelMode) -> Void

    /// Seeds the hover state so `--dump-card` can capture what hovering looks like.
    init(
        provider: Provider,
        snapshot: CostSnapshot,
        previewHoveredDayKey: String? = nil,
        previewTodayDayKey: String? = nil,
        labelMode: CostChartLabelMode = .tokens,
        onLabelModeChanged: @escaping (CostChartLabelMode) -> Void = { _ in }
    ) {
        self.provider = provider
        self.snapshot = snapshot
        self._hoveredDayKey = State(initialValue: previewHoveredDayKey)
        self._selectedLabelMode = State(initialValue: labelMode)
        self.todayDayKey = previewTodayDayKey ?? Self.dayKey(for: Date())
        self.onLabelModeChanged = onLabelModeChanged
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            self.kpiGrid
            if !self.bars.isEmpty {
                self.chart
            }
            self.hoverDetail

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

    /// Activity days plus an empty today bar, so today's cost remains visible before the first
    /// completed turn. Older activity falls off the left once the chart reaches its cap.
    private var bars: [CostDay] {
        CostChartHighlightPolicy.visibleDays(
            from: self.snapshot.days,
            todayDayKey: self.todayDayKey,
            maxBars: Self.maxBars
        )
    }

    private var maxValue: Double {
        self.bars.map { $0.costUSD ?? 0 }.max() ?? 0
    }

    private var chart: some View {
        HStack(alignment: .bottom, spacing: Self.barSpacing) {
            ForEach(self.bars, id: \.dayKey) { day in
                self.bar(for: day)
            }
        }
        .frame(height: Self.chartHeight)
        .padding(.top, 14)
        .overlay {
            GeometryReader { geometry in
                MouseLocationReader(
                    onMoved: { location in
                        self.updateHover(at: location, width: geometry.size.width)
                    },
                    onClicked: { location in
                        self.toggleLabel(at: location, width: geometry.size.width)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func bar(for day: CostDay) -> some View {
        let value = day.costUSD ?? 0
        let ratio = self.maxValue > 0 ? value / self.maxValue : 0
        let selectedDayKey = CostChartHighlightPolicy.selectedDayKey(
            hoveredDayKey: self.hoveredDayKey,
            todayDayKey: self.todayDayKey,
            availableDayKeys: Set(self.bars.map(\.dayKey))
        )
        // Exactly one selected bar is fully opaque; every other day shares one quiet tone.
        let opacity = CostChartHighlightPolicy.opacity(
            dayKey: day.dayKey,
            selectedDayKey: selectedDayKey,
            valueRatio: ratio
        )
        let labelText = CostChartHighlightPolicy.labelText(
            dayKey: day.dayKey,
            selectedDayKey: selectedDayKey,
            selectedMode: self.selectedLabelMode,
            tokens: day.tokens.total,
            costUSD: day.costUSD
        )
        return RoundedRectangle(cornerRadius: 2)
            .fill(Theme.accent(for: self.provider).opacity(opacity))
            // A day with a trace of spend still deserves a visible sliver.
            .frame(height: max(4, Self.chartHeight * ratio))
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) {
                if let labelText {
                    Text(labelText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.primary)
                        .fixedSize()
                        .offset(y: -14)
                }
            }
    }

    // MARK: - Hover

    private var hoveredDay: CostDay? {
        guard let key = CostChartHighlightPolicy.selectedDayKey(
            hoveredDayKey: self.hoveredDayKey,
            todayDayKey: self.todayDayKey,
            availableDayKeys: Set(self.bars.map(\.dayKey))
        ) else { return nil }
        return self.bars.first { $0.dayKey == key }
    }

    /// Summary line plus the per-model split, because a day is usually several models -- a
    /// Codex day mixes sol, terra and luna; a Claude day mixes opus, sonnet and haiku.
    /// The block is a fixed height so the card does not resize under the pointer.
    private var hoverDetail: some View {
        VStack(alignment: .leading, spacing: Self.detailSpacing) {
            Text(self.hoverLine)
                .font(.system(size: 11))
                .foregroundStyle(self.hoveredDay == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)

            if let day = self.hoveredDay {
                let ranked = day.rankedModels
                ForEach(Array(ranked.prefix(Self.maxBreakdownRows).enumerated()), id: \.element.model) {
                    index, entry in
                    self.breakdownRow(model: entry.model, usage: entry.usage, index: index)
                }
                if ranked.count > Self.maxBreakdownRows {
                    Text("+\(ranked.count - Self.maxBreakdownRows) more")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 6)
                }
            }
        }
        .frame(height: self.hoverDetailHeight, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Sized for the busiest day on the chart rather than the day under the pointer, so the
    /// block neither jumps between bars nor reserves space no day needs.
    private var hoverDetailHeight: CGFloat {
        let busiest = self.bars.map(\.byModel.count).max() ?? 0
        let rows = min(busiest, Self.maxBreakdownRows)
        var height = Self.summaryLineHeight + CGFloat(rows) * Self.breakdownRowHeight
        if busiest > Self.maxBreakdownRows { height += Self.overflowLineHeight }
        let lines = 1 + rows + (busiest > Self.maxBreakdownRows ? 1 : 0)
        return height + CGFloat(max(0, lines - 1)) * Self.detailSpacing
    }

    private func breakdownRow(model: String, usage: ModelDayUsage, index: Int) -> some View {
        HStack(spacing: 6) {
            // Each row fades a step further, so rank reads without numbering.
            Rectangle()
                .fill(Theme.accent(for: self.provider).opacity(max(0.3, 0.75 - Double(index) * 0.12)))
                .frame(width: 2, height: 10)
            Text(model)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Text(Self.breakdownValue(usage))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private static func breakdownValue(_ usage: ModelDayUsage) -> String {
        let tokens = Formatters.tokens(usage.tokens.total)
        guard let cost = usage.costUSD else { return "\(tokens) · no price" }
        return "\(tokens) · \(Formatters.cost(cost))"
    }

    /// The selected day total, defaulting to today when the pointer is outside the chart.
    private var hoverLine: String {
        guard let day = self.hoveredDay else {
            return "\(self.bars.count) days with activity · hover a bar for a day"
        }
        var parts = [Self.dayLabel(day.dayKey), Formatters.cost(day.costUSD ?? 0)]
        let tokens = day.tokens.total
        if tokens > 0 { parts.append("\(Formatters.tokens(tokens)) tokens") }
        return parts.joined(separator: " · ")
    }

    private func updateHover(at location: CGPoint?, width: CGFloat) {
        // Leaving the chart clears hover selection, which restores today's default highlight.
        // Inside the chart the policy decides, so a gap between bars holds the current day.
        guard let location, !self.bars.isEmpty, width > 0 else {
            if self.hoveredDayKey != nil { self.hoveredDayKey = nil }
            return
        }
        let index = CostChartHighlightPolicy.barIndex(
            atX: location.x,
            width: width,
            barCount: self.bars.count,
            spacing: Self.barSpacing
        )
        let key = index.map { self.bars[$0].dayKey }
        let nextKey = CostChartHighlightPolicy.hoveredDayKey(
            afterMovingTo: key,
            currentDayKey: self.hoveredDayKey
        )
        if self.hoveredDayKey != nextKey { self.hoveredDayKey = nextKey }
    }

    private var selectedDayKey: String? {
        CostChartHighlightPolicy.selectedDayKey(
            hoveredDayKey: self.hoveredDayKey,
            todayDayKey: self.todayDayKey,
            availableDayKeys: Set(self.bars.map(\.dayKey))
        )
    }

    private func toggleLabel(at location: CGPoint, width: CGFloat) {
        let index = CostChartHighlightPolicy.barIndex(
            atX: location.x,
            width: width,
            barCount: self.bars.count,
            spacing: Self.barSpacing
        )
        let clickedDayKey = index.map { self.bars[$0].dayKey }
        let nextMode = CostChartHighlightPolicy.labelMode(
            afterClicking: clickedDayKey,
            selectedDayKey: self.selectedDayKey,
            currentMode: self.selectedLabelMode
        )
        guard nextMode != self.selectedLabelMode else { return }
        self.selectedLabelMode = nextMode
        self.onLabelModeChanged(nextMode)
    }

    private static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return ""
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// "2026-08-24" -> "Aug 24".
    private static func dayLabel(_ dayKey: String) -> String {
        let parts = dayKey.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month) else { return dayKey }
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(names[month - 1]) \(day)"
    }



    // MARK: - Disclaimer

    /// Both providers are priced the same way — local logs, published API rates, cache tokens
    /// included — so the wording stays identical rather than drifting per provider.
    private var disclaimer: String {
        var text = "Local-log estimate at API rates, not a bill · cache tokens included"
        if self.snapshot.hasUnpricedTokens {
            text += " · unpriced models excluded"
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
