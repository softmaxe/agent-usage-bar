import AgentUsageBarCore

enum CostChartHighlightPolicy {
    static func visibleDays(
        from days: [CostDay],
        todayDayKey: String,
        maxBars: Int
    ) -> [CostDay] {
        guard maxBars > 0 else { return [] }

        var visible = Array(days.suffix(maxBars))
        guard !visible.contains(where: { $0.dayKey == todayDayKey }) else { return visible }

        if visible.count == maxBars {
            visible.removeFirst()
        }
        visible.append(CostDay(
            dayKey: todayDayKey,
            byModel: [:],
            costUSD: 0,
            unpricedTokens: 0
        ))
        visible.sort { $0.dayKey < $1.dayKey }
        return visible
    }

    static func selectedDayKey(
        hoveredDayKey: String?,
        todayDayKey: String,
        availableDayKeys: Set<String>
    ) -> String? {
        if let hoveredDayKey, availableDayKeys.contains(hoveredDayKey) {
            return hoveredDayKey
        }
        return availableDayKeys.contains(todayDayKey) ? todayDayKey : nil
    }

    /// Moving between two bars crosses the spacing between them, where hit testing finds no bar.
    /// Holding the current selection there keeps the label on the bar being left instead of
    /// flashing today's label for the frames the pointer spends in the gap.
    static func hoveredDayKey(afterMovingTo dayKey: String?, currentDayKey: String?) -> String? {
        dayKey ?? currentDayKey
    }

    /// The one quiet tone every unselected day shares.
    static let restingOpacity = 0.55

    static func opacity(dayKey: String, selectedDayKey: String?, valueRatio _: Double) -> Double {
        dayKey == selectedDayKey ? 1.0 : Self.restingOpacity
    }

    /// What one day's label reads. Token count is the default; cost mode still renders missing
    /// cost data as zero so a zero-height day never loses its label.
    static func labelText(
        selectedMode: CostChartLabelMode,
        tokens: Int,
        costUSD: Double?
    ) -> String {
        switch selectedMode {
        case .tokens:
            return Formatters.tokens(tokens)
        case .cost:
            return Formatters.compactCost(costUSD ?? 0)
        }
    }

    /// Only the selected bar has a label, for a caller that has not already established which bar
    /// it is holding.
    static func labelText(
        dayKey: String,
        selectedDayKey: String?,
        selectedMode: CostChartLabelMode,
        tokens: Int,
        costUSD: Double?
    ) -> String? {
        guard dayKey == selectedDayKey else { return nil }
        return Self.labelText(selectedMode: selectedMode, tokens: tokens, costUSD: costUSD)
    }

    static func labelMode(
        afterClicking dayKey: String?,
        selectedDayKey: String?,
        currentMode: CostChartLabelMode
    ) -> CostChartLabelMode {
        guard dayKey == selectedDayKey else { return currentMode }
        return currentMode == .tokens ? .cost : .tokens
    }

    /// Mirrors the HStack's equal-width bars and explicit spacing. Pointer movement through a gap
    /// clears the hover instead of borrowing the bar on either side.
    static func barIndex(atX x: Double, width: Double, barCount: Int, spacing: Double) -> Int? {
        guard barCount > 0, width > 0, spacing >= 0, x >= 0, x <= width else { return nil }
        let totalSpacing = spacing * Double(barCount - 1)
        let barWidth = (width - totalSpacing) / Double(barCount)
        guard barWidth > 0 else { return nil }

        let slotWidth = barWidth + spacing
        let index = min(barCount - 1, Int(x / slotWidth))
        let offset = x - Double(index) * slotWidth
        return offset <= barWidth ? index : nil
    }
}
