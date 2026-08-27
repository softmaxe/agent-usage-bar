#if DEBUG
import AgentUsageBarCore
import Foundation

/// Proves the reset label's two faces read correctly, and that clicking one swaps to the other.
/// The whole point of the clock face is planning around a reset, so a label that names the wrong
/// day is worse than no label: every case that adds or drops the day is pinned here.
@MainActor
enum QuotaResetLabelVerifier {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    private static let locale = Locale(identifier: "en_US")

    static func run() -> Never {
        // Friday, 28 August 2026, 14:04 local.
        let now = Self.date(2026, 8, 28, 14, 4)

        Self.expect(
            resetsAt: now.addingTimeInterval(86 * 60),
            mode: .countdown,
            now: now,
            "Resets in 1h 26m"
        )
        Self.expect(
            resetsAt: now.addingTimeInterval(5 * 86_400),
            mode: .countdown,
            now: now,
            "Resets in 5d 0h"
        )

        // Later today: the time alone cannot be read as any other day.
        Self.expect(
            resetsAt: Self.date(2026, 8, 28, 15, 30),
            mode: .clock,
            now: now,
            "Resets 3:30 PM"
        )
        // Half an hour away but across midnight — short countdown, different day.
        Self.expect(
            resetsAt: Self.date(2026, 8, 29, 0, 30),
            mode: .clock,
            now: Self.date(2026, 8, 28, 23, 59),
            "Resets Sat 12:30 AM"
        )
        Self.expect(
            resetsAt: Self.date(2026, 9, 3, 9, 0),
            mode: .clock,
            now: now,
            "Resets Thu 9:00 AM"
        )
        // A week out, where a weekday would name the day the reader is standing on.
        Self.expect(
            resetsAt: Self.date(2026, 9, 7, 9, 0),
            mode: .clock,
            now: now,
            "Resets Sep 7, 9:00 AM"
        )
        // Already past: the countdown floors at zero rather than counting up.
        Self.expect(
            resetsAt: now.addingTimeInterval(-600),
            mode: .countdown,
            now: now,
            "Resets in 0m"
        )

        Self.require(
            QuotaResetDisplayMode.countdown.toggled == .clock
                && QuotaResetDisplayMode.clock.toggled == .countdown,
            "clicking the label does not swap the two faces"
        )

        print("Quota reset label reads both faces correctly")
        exit(0)
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        let components = DateComponents(
            timeZone: Self.calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
        guard let date = Self.calendar.date(from: components) else {
            fputs("quota-reset-label verification failed: could not build a fixture date\n", stderr)
            exit(1)
        }
        return date
    }

    private static func expect(
        resetsAt: Date,
        mode: QuotaResetDisplayMode,
        now: Date,
        _ expected: String
    ) {
        // Foundation separates the time from AM/PM with a narrow no-break space, which is right
        // on screen and unreadable in a diff; the fixtures spell it as a plain space.
        let actual = QuotaResetLabel.text(
            resetsAt: resetsAt,
            mode: mode,
            now: now,
            calendar: Self.calendar,
            locale: Self.locale
        )
        let normalized = actual
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        Self.require(
            normalized == expected,
            "expected \"\(expected)\", got \"\(normalized)\""
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("quota-reset-label verification failed: \(message)\n", stderr)
            exit(1)
        }
    }
}
#endif
