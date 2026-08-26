import AgentUsageBarCore
import AppKit

/// Pixel checks for the status-item quota meters. These exercise the final bitmap rather than
/// duplicating the renderer's geometry in a policy test.
enum IconRenderingVerifier {
    @MainActor
    static func run() -> Never {
        var failures: [String] = []

        Self.expectSolidCodexMeter(
            primaryRemaining: 100,
            weeklyRemaining: nil,
            sample: (x: 10, y: 14),
            label: "single-window",
            failures: &failures
        )
        Self.expectSolidCodexMeter(
            primaryRemaining: 100,
            weeklyRemaining: 100,
            sample: (x: 10, y: 11),
            label: "dual-window primary",
            failures: &failures
        )

        guard failures.isEmpty else {
            for failure in failures {
                fputs("icon rendering verification failed: \(failure)\n", stderr)
            }
            exit(1)
        }
        print("status-item quota meter continuity checks passed")
        exit(0)
    }

    private static func expectSolidCodexMeter(
        primaryRemaining: Double,
        weeklyRemaining: Double?,
        sample: (x: Int, y: Int),
        label: String,
        failures: inout [String]
    ) {
        let image = IconRenderer.makeIcon(
            provider: .codex,
            primaryRemaining: primaryRemaining,
            weeklyRemaining: weeklyRemaining,
            stale: false
        )
        guard let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
              let color = bitmap.colorAt(x: sample.x, y: sample.y) else {
            failures.append("\(label) icon did not expose its bitmap sample")
            return
        }
        if color.alphaComponent < 0.99 {
            failures.append(
                "\(label) meter contained a transparent break "
                    + "(alpha \(color.alphaComponent), bitmap \(bitmap.pixelsWide)x\(bitmap.pixelsHigh))"
            )
        }
    }
}
