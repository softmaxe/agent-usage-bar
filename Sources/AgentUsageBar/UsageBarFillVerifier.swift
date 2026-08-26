import Foundation

/// No XCTest without Xcode, so the fill policy is asserted from a launch flag the way the chart
/// highlighting and the menu toggles are.
enum UsageBarFillVerifier {
    @MainActor
    static func run() -> Never {
        var failures: [String] = []

        if case .glide = UsageBarFillPolicy.onPresentation() {
            failures.append("opening the card glided instead of sweeping in from empty")
        }

        // A window rollover: the provider hands back a full quota in one step.
        let rollover = UsageBarFillPolicy.onValueChange(from: 2, to: 100)
        guard case let .sweepFromEmpty(duration) = rollover else {
            failures.append("a 2% -> 100% rollover did not sweep, got \(rollover)")
            return Self.finish(failures)
        }
        if duration <= UsageBarFillPolicy.sweepDuration {
            failures.append("the rollover sweep was not slower than an ordinary presentation")
        }

        // Spending only ever moves the remaining percentage down, which must not restart the bar.
        if case .sweepFromEmpty = UsageBarFillPolicy.onValueChange(from: 93, to: 89) {
            failures.append("ordinary spending restarted the bar from empty")
        }

        // A refresh that lands one point higher is noise, not a rollover.
        if case .sweepFromEmpty = UsageBarFillPolicy.onValueChange(from: 89, to: 90) {
            failures.append("a one-point rise was mistaken for a window rollover")
        }

        // The threshold itself belongs to the rollover side.
        let atThreshold = UsageBarFillPolicy.onValueChange(
            from: 50,
            to: 50 + UsageBarFillPolicy.rolloverJumpPoints
        )
        if case .glide = atThreshold {
            failures.append("a rise of exactly the rollover threshold glided instead of sweeping")
        }

        return Self.finish(failures)
    }

    private static func finish(_ failures: [String]) -> Never {
        guard failures.isEmpty else {
            for failure in failures {
                fputs("usage bar fill verification failed: \(failure)\n", stderr)
            }
            exit(1)
        }
        print("usage bar presentation, rollover, and drift fill checks passed")
        exit(0)
    }
}
