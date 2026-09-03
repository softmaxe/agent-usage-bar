import AppKit
import QuotaBarCore
import SwiftUI

/// The cost half of the popover: a KPI grid, the per-day bar chart, the top model, and the
/// estimate disclaimer.
struct CostSectionView: View {
    let snapshot: CostSnapshot

    /// The chart stays readable at card width; older days fall off the left.
    private static let maxBars = 10
    private static let chartHeight: CGFloat = 56
    private static let barSpacing: CGFloat = 4
    private static let labelOffsetY: CGFloat = -14
    /// Room for the selected bar's lift plus its label, so neither the card nor the KPI row above
    /// it moves when the highlight changes bars.
    private static let chartTopPadding = -Self.labelOffsetY + CostChartHoverMotion.lift
    /// Four covers a normal day for either provider; the rest collapse behind a "+N more" line
    /// the reader can open.
    private static let maxBreakdownRows = 4
    private static let breakdownLayout = CostBreakdownLayout(
        summaryHeight: 14,
        rowHeight: 13,
        toggleHeight: 12,
        spacing: 3
    )
    /// The gap between the chart and the breakdown under it, and the one the card's own stack
    /// puts between every section. Both are the same 10 pt, and the pointer is read against the
    /// first of them.
    private static let sectionSpacing: CGFloat = 10
    /// The rank bar and the gap after it. Together they are the column every breakdown line
    /// starts its text at, the toggle row's chevron included.
    private static let breakdownBarWidth: CGFloat = 2
    private static let breakdownMarkerGap: CGFloat = 6
    private static let breakdownMarkerWidth = Self.breakdownBarWidth + Self.breakdownMarkerGap

    /// Which day the pointer is over. Nil leaves every bar unselected.
    @State private var hoveredDayKey: String?
    /// The newest day starts here; a later bar hover replaces it until another does or it expires.
    @State private var detailDayKey: String?
    /// Updated immediately on click, then seeded from SettingsStore whenever the card is rebuilt.
    @State private var selectedLabelMode: CostChartLabelMode
    /// Whether the "+N more" line is pointed at, which is the whole of what says it is a switch.
    @State private var isToggleHovered = false
    private let onLabelModeChanged: (CostChartLabelMode) -> Void
    /// Opening the day's full model list makes the card taller, and the card's height belongs to
    /// the menu hosting it -- so unlike the label unit, this one is owned by the caller and comes
    /// back down as a new value rather than living in `@State` here.
    private let isBreakdownExpanded: Bool
    /// How far open the list is drawn right now, 0 to 1. The caller steps it: the card's height is
    /// an AppKit frame and the rows are SwiftUI, and the two only stay together if one clock moves
    /// both. Nothing here animates on its own.
    private let breakdownOpenness: Double
    private let onBreakdownExpandedChanged: (Bool) -> Void

    /// Activity days plus an empty today bar, so today's cost remains visible before the first
    /// completed turn. Older activity falls off the left once the chart reaches its cap. The
    /// snapshot and today's key are both fixed for the life of the view, so the chart's shape is
    /// settled here rather than rebuilt on every read — hover moves at pointer rate.
    private let bars: [CostDay]
    private let barDayKeys: Set<String>

    /// Seeds the hover state so `--dump-card` can capture what hovering looks like.
    init(
        snapshot: CostSnapshot,
        previewHoveredDayKey: String? = nil,
        previewTodayDayKey: String? = nil,
        labelMode: CostChartLabelMode = .tokens,
        onLabelModeChanged: @escaping (CostChartLabelMode) -> Void = { _ in },
        isBreakdownExpanded: Bool = false,
        breakdownOpenness: Double? = nil,
        previewToggleHovered: Bool = false,
        onBreakdownExpandedChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        let todayDayKey = previewTodayDayKey ?? Formatters.dayKey(for: Date())
        let bars = CostChartHighlightPolicy.visibleDays(
            from: snapshot.days,
            todayDayKey: todayDayKey,
            maxBars: Self.maxBars
        )
        let detailDayKey = CostChartHighlightPolicy.detailDayKey(
            afterMovingTo: previewHoveredDayKey,
            currentDayKey: nil,
            availableDayKeys: Set(bars.map(\.dayKey)),
            defaultDayKey: bars.last?.dayKey
        )

        self.snapshot = snapshot
        self._hoveredDayKey = State(initialValue: previewHoveredDayKey)
        self._detailDayKey = State(initialValue: detailDayKey)
        self._selectedLabelMode = State(initialValue: labelMode)
        self._isToggleHovered = State(initialValue: previewToggleHovered)
        self.onLabelModeChanged = onLabelModeChanged
        self.isBreakdownExpanded = isBreakdownExpanded
        self.breakdownOpenness = breakdownOpenness ?? (isBreakdownExpanded ? 1 : 0)
        self.onBreakdownExpandedChanged = onBreakdownExpandedChanged

        self.bars = bars
        self.barDayKeys = Set(bars.map(\.dayKey))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.sectionSpacing) {
            self.kpiGrid
            // Chart and breakdown share one tracking area. The bar highlight can clear while its
            // detail remains available for reading and opening.
            VStack(alignment: .leading, spacing: Self.sectionSpacing) {
                if !self.bars.isEmpty {
                    self.chart
                }
                self.hoverDetail
            }
            .mouseLocation(onMoved: self.updateHover, onClicked: self.handleClick)

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
        self.snapshot.provider == .codex ? "30d" : "30d cost"
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

    private var chart: some View {
        HStack(alignment: .bottom, spacing: Self.barSpacing) {
            // Hoisted: `bar(for:)` needs it for every bar, and it walks the whole day list.
            let maxValue = self.maxValue
            ForEach(self.bars, id: \.dayKey) { day in
                self.bar(for: day, maxValue: maxValue)
            }
        }
        .frame(height: Self.chartHeight)
        .padding(.top, Self.chartTopPadding)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func bar(for day: CostDay, maxValue: Double) -> some View {
        let value = CostChartHighlightPolicy.value(for: day, mode: self.selectedLabelMode)
        let ratio = maxValue > 0 ? value / maxValue : 0
        let selectedDayKey = self.selectedDayKey
        // Exactly one selected bar is fully opaque; every other day shares one quiet tone.
        let opacity = CostChartHighlightPolicy.opacity(
            dayKey: day.dayKey,
            selectedDayKey: selectedDayKey,
            valueRatio: ratio
        )
        let isSelected = day.dayKey == selectedDayKey
        return RoundedRectangle(cornerRadius: 2)
            .fill(Theme.accent(for: self.snapshot.provider))
            // Opacity as a modifier rather than folded into the fill, so the tone change is a
            // plain animatable value.
            .opacity(opacity)
            // A day with a trace of spend still deserves a visible sliver. The selected bar stands
            // up on top of that, which is what makes the highlight a shape and not only a tone.
            .frame(height: self.barHeight(valueRatio: ratio, isSelected: isSelected))
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) {
                if isSelected {
                    self.label(for: day)
                        .offset(y: Self.labelOffsetY)
                        .transition(CostChartHoverMotion.labelTransition)
                }
            }
    }

    private var maxValue: Double {
        CostChartHighlightPolicy.maxValue(for: self.bars, mode: self.selectedLabelMode)
    }

    private func barHeight(valueRatio: Double, isSelected: Bool) -> CGFloat {
        max(4, Self.chartHeight * valueRatio) + (isSelected ? CostChartHoverMotion.lift : 0)
    }

    private func labelSize(for day: CostDay) -> CGSize {
        let text = CostChartHighlightPolicy.labelText(
            selectedMode: self.selectedLabelMode,
            tokens: day.tokens.total,
            costUSD: day.costUSD
        )
        return (text as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
        ])
    }

    /// The outer `if` above owns the label's arrival on a bar; this one owns the unit swap on a
    /// bar that already has a label. Keeping the two changes on separate views is what stops a
    /// click from replaying the arrival, or a move between bars from replaying the swap.
    private func label(for day: CostDay) -> some View {
        ZStack {
            ForEach([self.selectedLabelMode], id: \.self) { mode in
                Text(CostChartHighlightPolicy.labelText(
                    selectedMode: mode,
                    tokens: day.tokens.total,
                    costUSD: day.costUSD
                ))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize()
                .transition(CostChartHoverMotion.swapTransition)
            }
        }
    }

    // MARK: - Hover

    private var detailDay: CostDay? {
        let key = CostChartHighlightPolicy.detailDayKey(
            afterMovingTo: nil,
            currentDayKey: self.detailDayKey,
            availableDayKeys: self.barDayKeys,
            defaultDayKey: self.bars.last?.dayKey
        )
        guard let key else { return nil }
        return self.bars.first { $0.dayKey == key }
    }

    /// Summary line plus the per-model split, because a day is usually several models -- a
    /// Codex day mixes sol, terra and luna; a Claude day mixes opus, sonnet and haiku.
    /// The block is a fixed height so the card does not resize under the pointer.
    private var hoverDetail: some View {
        // Each line carries the gap above it rather than leaving it to the stack: the rows that
        // open and close have to take their gap with them, or closing one would leave its seam.
        VStack(alignment: .leading, spacing: 0) {
            Text(self.hoverLine)
                .font(.system(size: 11))
                .foregroundStyle(self.detailDay == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
                // Every line in this block is pinned to the height the layout reserves for it, so
                // the row the pointer is hit-tested against is the row it is pointing at.
                .frame(height: CGFloat(Self.breakdownLayout.summaryHeight))

            if let day = self.detailDay {
                let ranked = day.rankedModels(by: self.selectedLabelMode)
                ForEach(Array(ranked.prefix(Self.maxBreakdownRows).enumerated()), id: \.element.key) {
                    index, entry in
                    self.breakdownLine(entry: entry, index: index)
                }
                self.breakdownOverflow(ranked: ranked)
                if self.hasBreakdownToggle {
                    self.breakdownToggleRow(hiddenCount: max(0, ranked.count - Self.maxBreakdownRows))
                }
            }
        }
        .frame(height: self.hoverDetailHeight, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The models that did not fit, in a strip whose height is the reveal: zero closed, their full
    /// height open, and whole points in between. They are always built, so opening and closing are
    /// the same two values moving -- the strip's height and the rows' opacity.
    private func breakdownOverflow(
        ranked: [(key: ModelUsageKey, model: String, usage: ModelDayUsage)]
    ) -> some View {
        let overflow = Array(ranked.dropFirst(Self.maxBreakdownRows).enumerated())
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(overflow, id: \.element.key) { index, entry in
                self.breakdownLine(entry: entry, index: index + Self.maxBreakdownRows)
            }
        }
        .frame(height: self.overflowStripHeight(rows: overflow.count), alignment: .top)
        .clipped()
        .opacity(self.breakdownOpenness)
    }

    private func overflowStripHeight(rows: Int) -> CGFloat {
        CGFloat(Self.breakdownLayout.rowsHeight(rows: rows, openness: self.breakdownOpenness))
    }

    private func breakdownLine(
        entry: (key: ModelUsageKey, model: String, usage: ModelDayUsage),
        index: Int
    ) -> some View {
        self.breakdownRow(
            source: entry.key.source,
            model: entry.model,
            usage: entry.usage,
            index: index
        )
        .padding(.top, CGFloat(Self.breakdownLayout.spacing))
    }

    /// Sized for the busiest day on the chart rather than the day under the pointer, so the
    /// block neither jumps between bars nor reserves space no day needs. Opening the list sizes it
    /// for that day's full model count, which is the one time the card does change height -- the
    /// reader asked for it, and the menu resizes around it.
    private var hoverDetailHeight: CGFloat {
        let busiest = self.bars.map(\.byModel.count).max() ?? 0
        let hasToggle = busiest > Self.maxBreakdownRows
        let closed = Self.breakdownLayout.height(
            rows: min(busiest, Self.maxBreakdownRows),
            hasToggle: hasToggle
        )
        // The block grows by exactly the strip the busiest day opens, so the lines below it move
        // in the same whole points the strip does.
        return CGFloat(closed) + self.overflowStripHeight(rows: max(0, busiest - Self.maxBreakdownRows))
    }

    /// How many model rows are above the toggle row, and how much strip is open under them --
    /// both read off what is on screen, so a click lands on the row the pointer is over even
    /// mid-sweep.
    private var visibleBreakdownRows: Int {
        min(self.detailDay?.byModel.count ?? 0, Self.maxBreakdownRows)
    }

    /// The toggle row appears on a day with more models than fit, and stays for as long as the
    /// list is open -- including on a day that would have fit -- so the way back is never missing.
    /// The height reserved above already counts it: only a chart holding such a day can open one.
    /// The toggle row sits under the four rows that always show plus however much of the strip is
    /// open.
    private var breakdownToggleBand: ClosedRange<Double>? {
        guard let band = Self.breakdownLayout.toggleBand(
            rows: self.visibleBreakdownRows,
            hasToggle: self.hasBreakdownToggle
        ) else { return nil }
        let strip = Double(self.overflowStripHeight(
            rows: max(0, (self.detailDay?.byModel.count ?? 0) - Self.maxBreakdownRows)
        ))
        return (band.lowerBound + strip)...(band.upperBound + strip)
    }

    private var hasBreakdownToggle: Bool {
        guard let models = self.detailDay?.byModel.count else { return false }
        return models > Self.maxBreakdownRows || self.isBreakdownExpanded
    }

    /// The band the bars occupy, and the top of the breakdown under them, both measured from the
    /// top of the tracked block.
    private var chartBandHeight: CGFloat {
        self.bars.isEmpty ? 0 : Self.chartTopPadding + Self.chartHeight
    }

    private var breakdownTop: CGFloat {
        self.bars.isEmpty ? 0 : self.chartBandHeight + Self.sectionSpacing
    }

    /// The overflow line doubles as the switch that opens the rest of the day. It cannot be a
    /// `Button` or an `.onTapGesture` -- an NSMenu popup is never the key window, so SwiftUI's
    /// gestures never fire inside the card -- so its click arrives through the same tracking view
    /// the chart reads, and its own height is pinned to what the hit test assumes.
    private func breakdownToggleRow(hiddenCount: Int) -> some View {
        HStack(spacing: 0) {
            // The chevron takes the column the rank bars are in, so the label starts on the same
            // left edge as the model names above it.
            Image(systemName: "chevron.right")
                .font(.system(size: 7, weight: .semibold))
                // A quarter turn spread over the reveal, so the glyph and the rows it stands for
                // are the same movement rather than two animations that happen to overlap.
                .rotationEffect(.degrees(90 * self.breakdownOpenness))
                .frame(width: Self.breakdownMarkerWidth, alignment: .leading)
            // Both labels are always there, so the wording crosses over on the same beat the rows
            // do instead of cutting under a list that is still moving.
            ZStack(alignment: .leading) {
                Text("+\(hiddenCount) more")
                    .opacity(1 - self.breakdownOpenness)
                Text("Show less")
                    .opacity(self.breakdownOpenness)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 10))
        .foregroundStyle(self.isToggleHovered ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
        .animation(.easeOut(duration: 0.12), value: self.isToggleHovered)
        .frame(height: CGFloat(Self.breakdownLayout.toggleHeight))
        .padding(.top, CGFloat(Self.breakdownLayout.spacing))
    }

    private func breakdownRow(
        source: CostUsageSource,
        model: String,
        usage: ModelDayUsage,
        index: Int
    ) -> some View {
        HStack(spacing: Self.breakdownMarkerGap) {
            // Each row fades a step further, so rank reads without numbering.
            Rectangle()
                .fill(Theme.accent(for: self.snapshot.provider).opacity(max(0.3, 0.75 - Double(index) * 0.12)))
                .frame(width: Self.breakdownBarWidth, height: 10)
            Text(self.snapshot.provider == .codex ? "\(source.displayName) · \(model)" : model)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Text(Self.breakdownValue(usage))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(height: CGFloat(Self.breakdownLayout.rowHeight))
    }

    private static func breakdownValue(_ usage: ModelDayUsage) -> String {
        let tokens = Formatters.tokens(usage.tokens.total)
        guard let cost = usage.costUSD else { return "\(tokens) · no price" }
        return "\(tokens) · \(Formatters.cost(cost))"
    }

    /// The detail day's total, or an instruction before any bar has supplied detail context.
    private var hoverLine: String {
        guard let day = self.detailDay else {
            return "\(self.bars.count) days with activity · hover a bar for a day"
        }
        var parts = [Formatters.dayLabel(day.dayKey), Formatters.cost(day.costUSD ?? 0)]
        let tokens = day.tokens.total
        if tokens > 0 { parts.append("\(Formatters.tokens(tokens)) tokens") }
        return parts.joined(separator: " · ")
    }

    private func updateHover(at location: CGPoint?, width: CGFloat) {
        // The tracking area covers the chart and breakdown, but only a bar and its label own
        // chart hover.
        guard let location, width > 0 else {
            if self.hoveredDayKey != nil { self.select(nil) }
            let nextDetailKey = CostChartHighlightPolicy.detailDayKey(
                afterMovingTo: nil,
                currentDayKey: self.detailDayKey,
                availableDayKeys: self.barDayKeys,
                defaultDayKey: self.bars.last?.dayKey
            )
            if self.detailDayKey != nextDetailKey { self.detailDayKey = nextDetailKey }
            if self.isToggleHovered { self.isToggleHovered = false }
            return
        }
        let region = self.region(at: location, width: width)
        if self.isToggleHovered != (region == .breakdownToggle) {
            self.isToggleHovered = region == .breakdownToggle
        }
        guard !self.bars.isEmpty else { return }
        let key = self.dayKey(for: region)
        let nextKey = CostChartHighlightPolicy.hoveredDayKey(afterMovingTo: key)
        let nextDetailKey = CostChartHighlightPolicy.detailDayKey(
            afterMovingTo: key,
            currentDayKey: self.detailDayKey,
            availableDayKeys: self.barDayKeys,
            defaultDayKey: self.bars.last?.dayKey
        )
        if self.hoveredDayKey != nextKey { self.select(nextKey) }
        if self.detailDayKey != nextDetailKey { self.detailDayKey = nextDetailKey }
    }

    private func region(at location: CGPoint, width: CGFloat) -> CostChartHighlightPolicy.Region {
        let maxValue = self.maxValue
        let selectedDayKey = self.selectedDayKey
        let barHeights = self.bars.map { day in
            let value = CostChartHighlightPolicy.value(for: day, mode: self.selectedLabelMode)
            let ratio = maxValue > 0 ? value / maxValue : 0
            return Double(self.barHeight(
                valueRatio: ratio,
                isSelected: day.dayKey == selectedDayKey
            ))
        }
        let labelSizes = self.bars.map { day in
            day.dayKey == selectedDayKey ? self.labelSize(for: day) : nil
        }
        return CostChartHighlightPolicy.region(
            at: location,
            width: width,
            chartBottom: self.chartBandHeight,
            barHeights: barHeights,
            labelSizes: labelSizes,
            labelOffsetY: Self.labelOffsetY,
            spacing: Self.barSpacing,
            detailTop: self.breakdownTop,
            toggleBand: self.breakdownToggleBand
        )
    }

    private func dayKey(for region: CostChartHighlightPolicy.Region) -> String? {
        switch region {
        case let .bar(index), let .label(index):
            return self.bars[index].dayKey
        case .breakdownToggle, .elsewhere:
            return nil
        }
    }

    /// Clearing the hover is the one move the reader did not aim at a bar, so it gets the slower
    /// clear curve.
    private func select(_ dayKey: String?) {
        let animation = CostChartHoverMotion.animation(
            clearingHover: dayKey == nil,
            reduceMotion: CostChartHoverMotion.systemReduceMotion
        )
        withAnimation(animation) { self.hoveredDayKey = dayKey }
    }

    private var selectedDayKey: String? {
        CostChartHighlightPolicy.selectedDayKey(
            hoveredDayKey: self.hoveredDayKey,
            availableDayKeys: self.barDayKeys
        )
    }

    private func handleClick(at location: CGPoint, width: CGFloat) {
        switch self.region(at: location, width: width) {
        case let .bar(index), let .label(index):
            self.toggleLabel(dayKey: self.bars[index].dayKey)
        case .breakdownToggle:
            self.onBreakdownExpandedChanged(!self.isBreakdownExpanded)
        case .elsewhere:
            break
        }
    }

    private func toggleLabel(dayKey clickedDayKey: String) {
        let nextMode = CostChartHighlightPolicy.labelMode(
            afterClicking: clickedDayKey,
            selectedDayKey: self.selectedDayKey,
            currentMode: self.selectedLabelMode
        )
        guard nextMode != self.selectedLabelMode else { return }
        // The unit change is the one thing on this chart the reader asks for by clicking, so it
        // is drawn rather than assigned: the old reading blurs out and the new one resolves.
        let animation = CostChartHoverMotion.swapAnimation(
            reduceMotion: CostChartHoverMotion.systemReduceMotion
        )
        withAnimation(animation) { self.selectedLabelMode = nextMode }
        self.onLabelModeChanged(nextMode)
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
