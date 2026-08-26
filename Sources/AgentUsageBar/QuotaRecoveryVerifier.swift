#if DEBUG
import AgentUsageBarCore
import AppKit
import Foundation

/// No XCTest without Xcode, so the recovery rules and the celebration's curves are asserted from
/// a launch flag the way the fill policy and the chart highlighting are.
enum QuotaRecoveryVerifier {
    @MainActor
    static func run() -> Never {
        var failures: [String] = []
        failures += Self.policyFailures()
        failures += Self.trackerFailures()
        failures += Self.choreographyFailures()
        return Self.finish(failures)
    }

    // MARK: - Policy

    private static func policyFailures() -> [String] {
        var failures: [String] = []
        let action = QuotaRecoveryPolicy.action

        if action(false, 0) != .arm {
            failures.append("an empty window was not remembered")
        }
        if action(false, QuotaRecoveryPolicy.drainedCeiling) != .arm {
            failures.append("a window at the drained ceiling was not treated as empty")
        }
        if action(true, 100) != .celebrate {
            failures.append("a window that came back full from empty did not celebrate")
        }
        if action(true, QuotaRecoveryPolicy.recoveredFloor) != .celebrate {
            failures.append("a rollover caught one poll late, at the recovered floor, did not celebrate")
        }
        if action(false, 100) != .hold {
            failures.append("a window that was already full celebrated anyway")
        }
        // Everything in between is ordinary spending, which is what the sweep is for.
        if action(true, 60) != .clear {
            failures.append("a half-spent window was mistaken for a rollover")
        }
        if action(true, QuotaRecoveryPolicy.recoveredFloor - 0.1) != .clear {
            failures.append("a window just under the recovered floor celebrated")
        }
        return failures
    }

    // MARK: - Tracker

    @MainActor
    private static func trackerFailures() -> [String] {
        var failures: [String] = []
        let suite = "AgentUsageBarQuotaRecoveryVerifier"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return ["the verifier could not open a throwaway defaults domain"]
        }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let tracker = QuotaRecoveryTracker(defaults: defaults)

        tracker.observe(provider: .claude, kind: .session, remainingPercent: 0)
        if !tracker.pendingWindows(for: .claude).isEmpty {
            failures.append("running dry queued a celebration on its own")
        }

        tracker.observe(provider: .claude, kind: .session, remainingPercent: 100)
        if tracker.pendingWindows(for: .claude) != [.session] {
            failures.append("a five-hour window coming back from empty queued nothing")
        }

        // The card can be opened long after the rollover, and the poller keeps running until it is.
        tracker.observe(provider: .claude, kind: .session, remainingPercent: 100)
        if tracker.pendingWindows(for: .claude) != [.session] {
            failures.append("a later poll on a still-full window dropped the queued celebration")
        }

        tracker.observe(provider: .claude, kind: .weekly, remainingPercent: 0)
        tracker.observe(provider: .claude, kind: .weekly, remainingPercent: 99)
        if tracker.pendingWindows(for: .claude) != [.session, .weekly] {
            failures.append("the weekly window did not queue independently of the five-hour one")
        }
        if !tracker.pendingWindows(for: .codex).isEmpty {
            failures.append("one provider's celebration leaked into the other")
        }

        if tracker.consumePending(for: .claude) != [.session, .weekly] {
            failures.append("the card was not handed both queued windows")
        }
        if !tracker.consumePending(for: .claude).isEmpty {
            failures.append("the celebration was handed out twice, so it would replay")
        }

        // Spending the window before the card is ever opened retires the celebration: sweeping a
        // half-empty bar to 100 would be a lie.
        tracker.observe(provider: .codex, kind: .session, remainingPercent: 0)
        tracker.observe(provider: .codex, kind: .session, remainingPercent: 100)
        tracker.observe(provider: .codex, kind: .session, remainingPercent: 62)
        if !tracker.pendingWindows(for: .codex).isEmpty {
            failures.append("a window spent back down still had a celebration waiting")
        }

        // The empty flag is on disk, so quitting while a window sits at 0% does not cost the user
        // the animation when it rolls over.
        tracker.observe(provider: .codex, kind: .weekly, remainingPercent: 0)
        let restarted = QuotaRecoveryTracker(defaults: defaults)
        restarted.observe(provider: .codex, kind: .weekly, remainingPercent: 100)
        if restarted.pendingWindows(for: .codex) != [.weekly] {
            failures.append("a window that ran dry before a restart did not celebrate afterwards")
        }

        return failures
    }

    // MARK: - Choreography

    private static func choreographyFailures() -> [String] {
        var failures: [String] = []

        if QuotaCelebration.fillFraction(at: 0) != 0 {
            failures.append("the celebration did not start from an empty bar")
        }
        if QuotaCelebration.fillFraction(at: QuotaCelebration.sweepDuration) != 1 {
            failures.append("the fill did not reach 100 by the end of the sweep")
        }
        var previous = 0.0
        for step in 0...200 {
            let value = QuotaCelebration.fillFraction(
                at: QuotaCelebration.sweepDuration * Double(step) / 200
            )
            if value < previous - 1e-9 {
                failures.append("the fill went backwards at \(step)/200 of the sweep")
                break
            }
            previous = value
        }
        // Fast away, slowing by the middle, closing the last points gently. The pop hangs off the
        // landing, so the fill has to be all but home by then.
        if QuotaCelebration.fillFraction(at: QuotaCelebration.sweepDuration * 0.2) < 0.6 {
            failures.append("the fill did not leave fast enough to read as a leap")
        }
        if QuotaCelebration.fillFraction(at: QuotaCelebration.landing) < 0.99 {
            failures.append("the bar was still visibly moving when the burst went off")
        }

        let atLanding = QuotaCelebration.barScale(at: QuotaCelebration.landing)
        if abs(atLanding.height - 1) > 1e-9 || abs(atLanding.width - 1) > 1e-9 {
            failures.append("the pop started from something other than the bar's own size")
        }
        let peak = stride(from: 0.0, through: QuotaCelebration.popDuration, by: 0.005)
            .map { QuotaCelebration.barScale(at: QuotaCelebration.landing + $0).height }
            .max() ?? 1
        if peak < 1.15 {
            failures.append("the bar never grew enough to read as a pop, peaked at \(peak)")
        }
        let settled = QuotaCelebration.barScale(at: QuotaCelebration.landing + QuotaCelebration.popDuration)
        if settled != CGSize(width: 1, height: 1) {
            failures.append("the bar did not settle back to its own size")
        }

        if QuotaCelebration.ring(at: QuotaCelebration.landing - 0.01) != nil {
            failures.append("the shockwave went out before the fill landed")
        }
        if QuotaCelebration.ring(at: QuotaCelebration.landing + 0.01) == nil {
            failures.append("the fill landed without a shockwave")
        }

        // Left first, then high over the middle, then on the 100 mark: the shells walk the bar
        // the way the fill does.
        let width: CGFloat = 252
        if !QuotaCelebration.sparks(at: 0, barWidth: width).isEmpty {
            failures.append("sparks were already out before the first shell")
        }
        let early = QuotaCelebration.sparks(at: 0.2, barWidth: width)
        if early.isEmpty {
            failures.append("the first shell never went off")
        } else if let rightmost = early.map(\.position.x).max(), rightmost > width * 0.5 {
            failures.append("the first shell did not go off on the left of the bar")
        }
        let middle = QuotaCelebration.sparks(at: 0.5, barWidth: width)
        if middle.allSatisfy({ $0.position.y > -20 }) {
            failures.append("the middle shell did not climb above the bar")
        }
        let landing = QuotaCelebration.sparks(at: QuotaCelebration.landing + 0.05, barWidth: width)
        if landing.filter({ $0.position.x > width * 0.8 }).count < 8 {
            failures.append("nothing much went off at the 100 mark")
        }
        if !QuotaCelebration.sparks(at: QuotaCelebration.duration, barWidth: width).isEmpty {
            failures.append("sparks were still on screen when the clock stopped")
        }

        return failures
    }

    private static func finish(_ failures: [String]) -> Never {
        guard failures.isEmpty else {
            for failure in failures {
                fputs("quota recovery verification failed: \(failure)\n", stderr)
            }
            exit(1)
        }
        print("quota recovery arming, hand-off, persistence, and celebration curves passed")
        exit(0)
    }
}
#endif
