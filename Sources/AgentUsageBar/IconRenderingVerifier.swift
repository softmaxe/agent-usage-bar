import AgentUsageBarCore
import AppKit

/// Pixel checks for the status-item icons. These exercise the final bitmap rather than
/// duplicating the renderer's geometry in a policy test.
enum IconRenderingVerifier {
    @MainActor
    static func run() -> Never {
        var failures: [String] = []

        Self.expectCodexFace(
            primaryRemaining: 100,
            weeklyRemaining: nil,
            eyeSample: (x: 10, y: 14),
            hatSample: (x: 18, y: 8),
            label: "single-window",
            failures: &failures
        )
        Self.expectCodexFace(
            primaryRemaining: 100,
            weeklyRemaining: 100,
            eyeSample: (x: 10, y: 11),
            hatSample: (x: 18, y: 7),
            label: "dual-window",
            failures: &failures
        )

        VerifierReport.finish(
            failures,
            label: "icon rendering verification",
            passed: "status-item icon rendering checks passed"
        )
    }

    private static func expectCodexFace(
        primaryRemaining: Double,
        weeklyRemaining: Double?,
        eyeSample: (x: Int, y: Int),
        hatSample: (x: Int, y: Int),
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
              let eye = bitmap.colorAt(x: eyeSample.x, y: eyeSample.y),
              let hat = bitmap.colorAt(x: hatSample.x, y: hatSample.y) else {
            failures.append("\(label) Codex face did not expose its bitmap samples")
            return
        }
        if eye.alphaComponent > 0.01 {
            failures.append("\(label) Codex eye was not visible (alpha \(eye.alphaComponent))")
        }
        if hat.alphaComponent < 0.99 {
            failures.append("\(label) Codex cap was missing (alpha \(hat.alphaComponent))")
        }
    }
}
