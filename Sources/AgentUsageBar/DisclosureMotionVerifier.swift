#if DEBUG
import Foundation

/// Proves the cascade stays a beat rather than becoming a wait: rows arrive one stagger apart,
/// the stagger stops growing before a fourteen-model group could still be arriving half a second
/// after the click, and Reduce Motion takes the curve away entirely.
enum DisclosureMotionVerifier {
    /// What the pricing table actually asks for: Claude's group is the longest one on screen.
    private static let longestGroup = 14
    /// The whole group has to be settled inside this, counted from the click.
    private static let budget: TimeInterval = 0.5

    static func run() -> Never {
        Self.require(DisclosureMotion.rowDelay(index: 0) == 0, "the first row waits for nothing")
        Self.require(
            DisclosureMotion.rowDelay(index: -3) == 0,
            "an index below the top of the group clamps rather than arriving early"
        )

        for index in 1...DisclosureMotion.maxStaggeredRows {
            let expected = DisclosureMotion.rowStagger * Double(index)
            Self.require(
                abs(DisclosureMotion.rowDelay(index: index) - expected) < 1e-9,
                "row \(index) arrives \(index) beats after the header, not "
                    + "\(DisclosureMotion.rowDelay(index: index))s"
            )
        }

        let capped = DisclosureMotion.rowDelay(index: DisclosureMotion.maxStaggeredRows)
        Self.require(
            DisclosureMotion.rowDelay(index: Self.longestGroup) == capped,
            "the stagger stops growing past \(DisclosureMotion.maxStaggeredRows) rows"
        )

        let lastArrival = DisclosureMotion.rowDelay(index: Self.longestGroup)
            + DisclosureMotion.openDuration
        Self.require(
            lastArrival < Self.budget,
            "a \(Self.longestGroup)-row group settles in \(lastArrival)s, past the "
                + "\(Self.budget)s budget"
        )

        Self.require(
            DisclosureMotion.open(reduceMotion: true) == nil,
            "Reduce Motion turns the disclosure back into a cut"
        )
        Self.require(
            DisclosureMotion.open(reduceMotion: false) != nil,
            "the disclosure animates when motion is not reduced"
        )

        print("disclosure motion verification passed")
        exit(0)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            VerifierReport.fail(message, label: "disclosure-motion verification")
        }
    }
}
#endif
