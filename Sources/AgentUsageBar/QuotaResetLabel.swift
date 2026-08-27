import AgentUsageBarCore
import Foundation

/// The one line a quota window devotes to its reset, in whichever of its two faces the reader
/// last asked for. Kept out of the view so the wording can be checked without a running menu.
enum QuotaResetLabel {
    static func text(
        resetsAt: Date,
        mode: QuotaResetDisplayMode,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        switch mode {
        case .countdown:
            // "in" only reads right in front of a duration, which is why the clock face drops it.
            "Resets in \(Formatters.compactDuration(resetsAt.timeIntervalSince(now)))"
        case .clock:
            "Resets \(Formatters.resetClock(resetsAt, now: now, calendar: calendar, locale: locale))"
        }
    }
}
