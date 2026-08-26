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
}
