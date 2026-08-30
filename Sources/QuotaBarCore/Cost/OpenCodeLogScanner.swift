import Foundation
import SQLite3

public enum OpenCodeScanStatus: Sendable, Equatable {
    case idle
    case accountMismatch
    case nonOAuth
    case error(String)

    public var message: String? {
        switch self {
        case .idle: nil
        case .accountMismatch: "OpenCode usage is not included because its OpenAI account differs from Codex."
        case .nonOAuth: "OpenCode usage is not included because OpenAI OAuth is not active."
        case .error: "OpenCode usage could not be scanned. Existing totals were kept."
        }
    }
}

enum OpenCodeLogScanner {
    struct Result {
        let touched: Int
        let status: OpenCodeScanStatus
    }

    private enum Eligibility {
        case eligible
        case ineligible(OpenCodeScanStatus)
        case indeterminate
    }

    private struct AuthFile: Decodable {
        let openai: OpenAI?

        struct OpenAI: Decodable {
            let type: String?
            let accountId: String?
        }
    }

    private struct CodexAuthFile: Decodable {
        let tokens: Tokens?

        struct Tokens: Decodable {
            let accountId: String?

            enum CodingKeys: String, CodingKey {
                case accountId = "account_id"
            }
        }
    }

    private struct Row {
        let key: String
        let day: String
        let model: String
        let totals: TokenTotals
    }

    static func scan(cache: CostCache, overlay: PricingOverlay?, env: [String: String]) -> Result {
        let dataDirectory = self.dataDirectory(env: env)
        let databaseURL = dataDirectory.appendingPathComponent("opencode.db")
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            do {
                try cache.clearOpenCodeParts()
                return Result(touched: 0, status: .idle)
            } catch {
                return Result(touched: 0, status: .error("cache"))
            }
        }

        let eligibility = self.eligibility(dataDirectory: dataDirectory, env: env)
        guard case .indeterminate = eligibility else {
            return self.scanDatabase(
                databaseURL,
                eligibility: eligibility,
                cache: cache,
                overlay: overlay
            )
        }
        return Result(touched: 0, status: .error("auth"))
    }

    private static func scanDatabase(
        _ url: URL,
        eligibility: Eligibility,
        cache: CostCache,
        overlay: PricingOverlay?
    ) -> Result {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return Result(touched: 0, status: .error("database"))
        }
        defer { sqlite3_close(db) }

        do {
            try self.validateSchema(db)
            try self.exec(db, "BEGIN")
            let rows = try self.readRows(db)
            try self.exec(db, "COMMIT")

            let included: Bool
            let status: OpenCodeScanStatus
            switch eligibility {
            case .eligible:
                included = true
                status = .idle
            case let .ineligible(reason):
                included = false
                status = reason
            case .indeterminate:
                return Result(touched: 0, status: .error("auth"))
            }

            let backfillCompleted = try cache.hasCompletedOpenCodeBackfill()
            let legacy = included && !backfillCompleted
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
                    try cache.addOpenCodePart(
                        key: row.key,
                        included: included,
                        legacyInferred: legacy,
                        day: row.day,
                        model: model,
                        longContext: longContext,
                        totals: row.totals,
                        costUSD: cost
                    )
                }
                try cache.pruneOpenCodeParts(keeping: Set(rows.map(\.key)))
                if legacy { try cache.markOpenCodeBackfillComplete() }
                try cache.commit()
            } catch {
                cache.rollback()
                throw error
            }
            return Result(touched: rows.count, status: status)
        } catch {
            try? self.exec(db, "ROLLBACK")
            return Result(touched: 0, status: .error("schema"))
        }
    }

    private static func eligibility(dataDirectory: URL, env: [String: String]) -> Eligibility {
        do {
            let openCodeData = try Data(contentsOf: dataDirectory.appendingPathComponent("auth.json"))
            let codexData = try Data(contentsOf: CodexHome.url(env: env).appendingPathComponent("auth.json"))
            let openCode = try JSONDecoder().decode(AuthFile.self, from: openCodeData).openai
            let codex = try JSONDecoder().decode(CodexAuthFile.self, from: codexData).tokens
            guard let openCode else { return .indeterminate }
            guard openCode.type?.lowercased() == "oauth" else { return .ineligible(.nonOAuth) }
            guard let left = openCode.accountId?.trimmingCharacters(in: .whitespacesAndNewlines), !left.isEmpty,
                  let right = codex?.accountId?.trimmingCharacters(in: .whitespacesAndNewlines), !right.isEmpty else {
                return .indeterminate
            }
            return left == right ? .eligible : .ineligible(.accountMismatch)
        } catch {
            return .indeterminate
        }
    }

    private static func dataDirectory(env: [String: String]) -> URL {
        if let explicit = env["OPENCODE_DATA_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return URL(fileURLWithPath: (explicit as NSString).expandingTildeInPath)
        }
        if let xdg = env["XDG_DATA_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines), !xdg.isEmpty {
            return URL(fileURLWithPath: (xdg as NSString).expandingTildeInPath)
                .appendingPathComponent("opencode", isDirectory: true)
        }
        let home = env["HOME"].flatMap {
            let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".local/share/opencode", isDirectory: true)
    }

    private static func validateSchema(_ db: OpaquePointer) throws {
        for table in ["part", "message"] {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &stmt, nil) == SQLITE_OK else {
                throw ScanError.schema
            }
            var columns = Set<String>()
            while sqlite3_step(stmt) == SQLITE_ROW {
                columns.insert(String(cString: sqlite3_column_text(stmt, 1)))
            }
            let required: Set<String> = table == "part" ? ["id", "message_id", "data"] : ["id", "data"]
            guard required.isSubset(of: columns) else { throw ScanError.schema }
        }
    }

    private static func readRows(_ db: OpaquePointer) throws -> [Row] {
        let sql = """
        SELECT p.id,
               json_extract(m.data, '$.time.created'),
               json_extract(m.data, '$.modelID'),
               json_extract(p.data, '$.tokens.input'),
               json_extract(p.data, '$.tokens.output'),
               json_extract(p.data, '$.tokens.reasoning'),
               json_extract(p.data, '$.tokens.cache.read'),
               json_extract(p.data, '$.tokens.cache.write')
        FROM part p
        JOIN message m ON m.id = p.message_id
        WHERE json_extract(p.data, '$.type') = 'step-finish'
          AND json_extract(m.data, '$.providerID') = 'openai'
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw ScanError.schema }
        var rows: [Row] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let keyText = sqlite3_column_text(stmt, 0),
                  let modelText = sqlite3_column_text(stmt, 2) else { continue }
            let input = max(0, Int(sqlite3_column_int64(stmt, 3)))
            let output = max(0, Int(sqlite3_column_int64(stmt, 4)))
                + max(0, Int(sqlite3_column_int64(stmt, 5)))
            let cacheRead = max(0, Int(sqlite3_column_int64(stmt, 6)))
            let cacheWrite = max(0, Int(sqlite3_column_int64(stmt, 7)))
            let totals = TokenTotals(input: input, output: output, cacheWrite: cacheWrite, cacheRead: cacheRead)
            guard totals.total > 0 else { continue }
            let rawTime = sqlite3_column_double(stmt, 1)
            let seconds = rawTime > 10_000_000_000 ? rawTime / 1000 : rawTime
            guard seconds > 0 else { continue }
            rows.append(Row(
                key: String(cString: keyText),
                day: DayKey.make(from: Date(timeIntervalSince1970: seconds)),
                model: String(cString: modelText),
                totals: totals
            ))
        }
        guard sqlite3_errcode(db) == SQLITE_OK || sqlite3_errcode(db) == SQLITE_DONE else { throw ScanError.read }
        return rows
    }

    private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw ScanError.read }
    }

    private enum ScanError: Error { case schema, read }
}
