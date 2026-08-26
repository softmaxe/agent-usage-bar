enum CostChartHighlightPolicy {
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
    /// Holding the current selection there keeps the price label on the bar being left instead of
    /// flashing today's label for the frames the pointer spends in the gap.
    static func hoveredDayKey(afterMovingTo dayKey: String?, currentDayKey: String?) -> String? {
        dayKey ?? currentDayKey
    }

    static func opacity(dayKey: String, selectedDayKey: String?, valueRatio _: Double) -> Double {
        dayKey == selectedDayKey ? 1.0 : 0.55
    }

    /// The price label follows the selected bar: the hovered day while the pointer is over a bar,
    /// then today when there is no hover selection.
    static func labelCost(dayKey: String, selectedDayKey: String?, costUSD: Double?) -> Double? {
        dayKey == selectedDayKey ? costUSD : nil
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
