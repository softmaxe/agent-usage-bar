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

    static func hoveredDayKey(afterMovingTo dayKey: String?, currentDayKey _: String?) -> String? {
        dayKey
    }

    static func opacity(dayKey: String, selectedDayKey: String?, valueRatio _: Double) -> Double {
        dayKey == selectedDayKey ? 1.0 : 0.55
    }
}
