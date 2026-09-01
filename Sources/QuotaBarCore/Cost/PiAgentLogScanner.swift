import Foundation

public enum PiAgentScanStatus: Sendable, Equatable {
    case idle
    case accountMismatch
    case nonOAuth
    case error(String)

    public var message: String? {
        switch self {
        case .idle: nil
        case .accountMismatch: "Pi Agent usage is not included because its OpenAI account differs from Codex."
        case .nonOAuth: "Pi Agent usage is not included because OpenAI OAuth is not active."
        case .error: "Pi Agent usage could not be scanned. Existing totals were kept."
        }
    }
}

enum PiAgentLogScanner {
    struct Result {
        let touched: Int
        let status: PiAgentScanStatus
    }

    private enum Eligibility {
        case eligible
        case ineligible(PiAgentScanStatus)
        case indeterminate
    }

    private struct PiAuth: Decodable {
        let openAICodex: Entry?
        struct Entry: Decodable { let type: String?; let accountId: String? }
        enum CodingKeys: String, CodingKey { case openAICodex = "openai-codex" }
    }

    private struct CodexAuth: Decodable {
        let tokens: Tokens?
        struct Tokens: Decodable {
            let accountId: String?
            enum CodingKeys: String, CodingKey { case accountId = "account_id" }
        }
    }

    private struct Row {
        let key: String
        let day: String
        let model: String
        let totals: TokenTotals
    }

    static func scan(cache: CostCache, overlay: PricingOverlay?, env: [String: String]) -> Result {
        let agentDirectory = self.agentDirectory(env: env)
        let sessionsDirectory = self.sessionsDirectory(agentDirectory: agentDirectory, env: env)
        guard FileManager.default.fileExists(atPath: sessionsDirectory.path) else {
            do {
                try cache.clearPiMessages()
                return Result(touched: 0, status: .idle)
            } catch {
                return Result(touched: 0, status: .error("cache"))
            }
        }

        let eligibility = self.eligibility(agentDirectory: agentDirectory, env: env)
        guard case .indeterminate = eligibility else {
            return self.scanSessions(
                sessionsDirectory,
                eligibility: eligibility,
                cache: cache,
                overlay: overlay
            )
        }
        return Result(touched: 0, status: .error("auth"))
    }

    private static func scanSessions(
        _ directory: URL,
        eligibility: Eligibility,
        cache: CostCache,
        overlay: PricingOverlay?
    ) -> Result {
        do {
            let rows = try self.readRows(in: directory)
            let included: Bool
            let status: PiAgentScanStatus
            switch eligibility {
            case .eligible: included = true; status = .idle
            case let .ineligible(reason): included = false; status = reason
            case .indeterminate: return Result(touched: 0, status: .error("auth"))
            }

            try cache.beginTransaction()
            do {
                for row in rows {
                    let model = CostPricing.normalizeCodexModel(row.model)
                    let longContext = CostPricing.isLongContext(
                        totals: row.totals,
                        model: model,
                        provider: .codex,
                        overlay: overlay
                    )
                    let cost = CostPricing.cost(
                        totals: row.totals,
                        model: model,
                        provider: .codex,
                        longContext: longContext,
                        overlay: overlay
                    )
                    try cache.addPiMessage(
                        key: row.key,
                        included: included,
                        day: row.day,
                        model: model,
                        longContext: longContext,
                        totals: row.totals,
                        costUSD: cost
                    )
                }
                try cache.prunePiMessages(keeping: Set(rows.map(\.key)))
                try cache.commit()
            } catch {
                cache.rollback()
                throw error
            }
            return Result(touched: rows.count, status: status)
        } catch {
            return Result(touched: 0, status: .error("sessions"))
        }
    }

    private static func readRows(in directory: URL) throws -> [Row] {
        var enumerationFailed = false
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in enumerationFailed = true; return false }
        ) else { throw ScanError.read }

        var rows: [Row] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            _ = try LogFileScanner.readLines(of: url, from: 0) { line in
                guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      let row = self.row(from: object) else { return }
                rows.append(row)
            }
        }
        if enumerationFailed { throw ScanError.read }
        return rows
    }

    private static func row(from object: [String: Any]) -> Row? {
        guard object["type"] as? String == "message",
              let message = object["message"] as? [String: Any],
              message["role"] as? String == "assistant",
              message["provider"] as? String == "openai-codex",
              let usage = message["usage"] as? [String: Any],
              let rawModel = (message["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawModel.isEmpty,
              let date = self.date(message: message, object: object) else { return nil }
        let totals = TokenTotals(
            input: self.nonnegativeInt(usage["input"]),
            output: self.nonnegativeInt(usage["output"]),
            cacheWrite: self.nonnegativeInt(usage["cacheWrite"]),
            cacheWrite1h: self.nonnegativeInt(usage["cacheWrite1h"]),
            cacheRead: self.nonnegativeInt(usage["cacheRead"])
        )
        guard totals.total > 0 else { return nil }
        // Session entries use UUIDv7 identifiers that survive forks. Keying globally prevents a
        // copied history from billing the same model response twice.
        let identifier = (object["id"] as? String) ?? (message["id"] as? String)
        guard let identifier, !identifier.isEmpty else { return nil }
        return Row(key: identifier, day: DayKey.make(from: date), model: rawModel, totals: totals)
    }

    private static func date(message: [String: Any], object: [String: Any]) -> Date? {
        if let milliseconds = (message["timestamp"] as? NSNumber)?.doubleValue, milliseconds > 0 {
            return Date(timeIntervalSince1970: milliseconds / 1000)
        }
        guard let timestamp = object["timestamp"] as? String else { return nil }
        return ISO8601.parse(timestamp)
    }

    private static func nonnegativeInt(_ value: Any?) -> Int {
        max(0, (value as? NSNumber)?.intValue ?? 0)
    }

    private static func eligibility(agentDirectory: URL, env: [String: String]) -> Eligibility {
        do {
            let piData = try Data(contentsOf: agentDirectory.appendingPathComponent("auth.json"))
            let codexData = try Data(contentsOf: CodexHome.url(env: env).appendingPathComponent("auth.json"))
            let pi = try JSONDecoder().decode(PiAuth.self, from: piData).openAICodex
            let codex = try JSONDecoder().decode(CodexAuth.self, from: codexData).tokens
            guard let pi else { return .indeterminate }
            guard pi.type?.lowercased() == "oauth" else { return .ineligible(.nonOAuth) }
            guard let left = pi.accountId?.trimmingCharacters(in: .whitespacesAndNewlines), !left.isEmpty,
                  let right = codex?.accountId?.trimmingCharacters(in: .whitespacesAndNewlines), !right.isEmpty else {
                return .indeterminate
            }
            return left == right ? .eligible : .ineligible(.accountMismatch)
        } catch {
            return .indeterminate
        }
    }

    private static func agentDirectory(env: [String: String]) -> URL {
        if let explicit = self.nonempty(env["PI_CODING_AGENT_DIR"]) {
            return URL(fileURLWithPath: (explicit as NSString).expandingTildeInPath)
        }
        let home = self.nonempty(env["HOME"])
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".pi/agent", isDirectory: true)
    }

    private static func sessionsDirectory(agentDirectory: URL, env: [String: String]) -> URL {
        guard let explicit = self.nonempty(env["PI_CODING_AGENT_SESSION_DIR"]) else {
            return agentDirectory.appendingPathComponent("sessions", isDirectory: true)
        }
        return URL(fileURLWithPath: (explicit as NSString).expandingTildeInPath)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private enum ScanError: Error { case read }
}
