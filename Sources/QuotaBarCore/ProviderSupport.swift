import Foundation

/// Timestamp parsing shared by the log scanners and both credential stores. The two formatters
/// are built once: `ISO8601DateFormatter` is expensive to construct relative to a single
/// `date(from:)`, and a full rescan calls this once per log line.
enum ISO8601 {
    nonisolated(unsafe) private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()

    /// Fractional seconds first, because that is what the session logs write; the plain form is
    /// the fallback for the API payloads that omit them.
    static func parse(_ raw: String) -> Date? {
        if let date = Self.withFraction.date(from: raw) { return date }
        return Self.plain.date(from: raw)
    }
}

/// `$CODEX_HOME`, or `~/.codex` when it is unset or blank. The credential store, the usage
/// fetcher and the log scanner all have to agree on this, so they all read it from here.
enum CodexHome {
    static func url(env: [String: String]) -> URL {
        if let codexHome = env["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !codexHome.isEmpty {
            return URL(fileURLWithPath: (codexHome as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }
}

/// JSON coercion shared by the two log scanners, whose payloads spell integers as either a
/// number or a string depending on which client wrote the line.
enum JSONNumber {
    static func int(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }
}

/// `plus` -> `Plus`, `free_workspace` -> `Free Workspace`. Both providers label plans this way.
enum PlanLabel {
    public static func humanize(_ raw: String) -> String {
        raw.split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
