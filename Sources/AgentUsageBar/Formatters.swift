import Foundation

enum Formatters {
    /// "4h 47m", "6d 10h" — the coarse two-unit form CodexBar uses for reset countdowns.
    static func compactDuration(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// "just now", "5m ago", "2h ago".
    static func relativeAge(since date: Date, now: Date = Date()) -> String {
        let seconds = Int(max(0, now.timeIntervalSince(date)))
        if seconds < 45 { return "just now" }
        if seconds < 3_600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3_600)h ago" }
        return "\(seconds / 86_400)d ago"
    }

    /// Percentages render as whole numbers, matching the menu bar icon's quantization.
    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// "$0.00", "$507.13". Cents matter here because a day can be genuinely tiny.
    static func cost(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    /// Compact axis label: "$90", "$1.2K".
    static func compactCost(_ value: Double) -> String {
        if value >= 1_000 { return String(format: "$%.1fK", value / 1_000) }
        if value >= 10 { return String(format: "$%.0f", value) }
        return String(format: "$%.2f", value)
    }

    /// "67M", "637M", "1.2B" — token counts are large enough that digits stop being readable.
    static func tokens(_ count: Int) -> String {
        let value = Double(count)
        if value >= 1_000_000_000 { return String(format: "%.1fB", value / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.0fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0fK", value / 1_000) }
        return "\(count)"
    }
}
