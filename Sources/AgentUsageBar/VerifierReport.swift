import Foundation

/// Command Line Tools ship no XCTest, so the suite is a set of launch flags and every `--verify-*`
/// run ends the same way: name what passed and exit 0, or put each failure on stderr and exit 1.
/// `VerifierReport` owns that ending, which leaves each verifier holding only its own checks.
enum VerifierReport {
    /// Ends a run that collects its failures and reports them together. `label` names the check in
    /// the failure lines; `passed` is the one-line summary printed when there are none.
    static func finish(_ failures: [String], label: String, passed: String) -> Never {
        guard failures.isEmpty else {
            for failure in failures {
                fputs("\(label) failed: \(failure)\n", stderr)
            }
            exit(1)
        }
        print(passed)
        exit(0)
    }

    /// Ends a run that cannot usefully continue past its first failure.
    static func fail(_ message: String, label: String) -> Never {
        Self.report(message, label: label)
        exit(1)
    }

    /// Writes one failure line without ending the process, for a verifier with cleanup of its own
    /// to do first — `exit()` terminates without unwinding the stack, so `defer` never runs.
    static func report(_ message: String, label: String) {
        fputs("\(label) failed: \(message)\n", stderr)
    }
}
