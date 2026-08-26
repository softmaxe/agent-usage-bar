// Incremental scan cache, modelled on CodexBar's opencodex-usage sqlite store
// (MIT, © 2026 Peter Steinberger).
//
// Rescanning ~750MB of JSONL on every refresh is not viable, so each file's parse position is
// remembered and only the bytes appended since the last scan are read.

import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Where a file was left off. A file is resumable only if its identity still matches.
struct FileCursor {
    let inode: UInt64
    let size: Int64
    let offset: Int64
    /// Digest of the first 64KB, so a rewritten-in-place file is detected even at the same size.
    let prefixDigest: String
}

final class CostCache {
    private var db: OpaquePointer?

    init(path: URL) throws {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard sqlite3_open(path.path, &self.db) == SQLITE_OK else {
            throw CostCacheError.openFailed(self.lastErrorMessage)
        }
        try self.exec("PRAGMA journal_mode=WAL")
        try self.exec("PRAGMA synchronous=NORMAL")
        try self.createSchema()
    }

    deinit {
        if let db = self.db { sqlite3_close(db) }
    }

    private func createSchema() throws {
        try self.exec("""
        CREATE TABLE IF NOT EXISTS file_cursor (
            path TEXT PRIMARY KEY,
            provider TEXT NOT NULL,
            inode INTEGER NOT NULL,
            size INTEGER NOT NULL,
            offset INTEGER NOT NULL,
            prefix_digest TEXT NOT NULL
        )
        """)
        // Codex turns carry no message identity, but a turn appears in exactly one rollout file,
        // so per-file day/model rows are enough.
        try self.exec("""
        CREATE TABLE IF NOT EXISTS codex_day (
            path TEXT NOT NULL,
            day TEXT NOT NULL,
            model TEXT NOT NULL,
            long_context INTEGER NOT NULL,
            input INTEGER NOT NULL,
            output INTEGER NOT NULL,
            cache_write INTEGER NOT NULL,
            cache_read INTEGER NOT NULL,
            PRIMARY KEY (path, day, model, long_context)
        )
        """)
        // Claude replays the same assistant message into several transcripts, so rows are keyed by
        // message identity and inserted with OR IGNORE to keep the count honest.
        try self.exec("""
        CREATE TABLE IF NOT EXISTS claude_message (
            key TEXT PRIMARY KEY,
            path TEXT NOT NULL,
            day TEXT NOT NULL,
            model TEXT NOT NULL,
            long_context INTEGER NOT NULL,
            input INTEGER NOT NULL,
            output INTEGER NOT NULL,
            cache_write INTEGER NOT NULL,
            cache_read INTEGER NOT NULL
        )
        """)
        try self.exec("CREATE INDEX IF NOT EXISTS claude_message_path ON claude_message(path)")
        try self.exec("CREATE INDEX IF NOT EXISTS claude_message_day ON claude_message(day)")
        try self.exec("CREATE INDEX IF NOT EXISTS codex_day_day ON codex_day(day)")
    }

    // MARK: - Cursors

    func cursor(forPath path: String) -> FileCursor? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(
            self.db,
            "SELECT inode, size, offset, prefix_digest FROM file_cursor WHERE path = ?",
            -1,
            &stmt,
            nil
        ) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, path, -1, sqliteTransient)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return FileCursor(
            inode: UInt64(sqlite3_column_int64(stmt, 0)),
            size: sqlite3_column_int64(stmt, 1),
            offset: sqlite3_column_int64(stmt, 2),
            prefixDigest: String(cString: sqlite3_column_text(stmt, 3))
        )
    }

    func setCursor(_ cursor: FileCursor, forPath path: String, provider: Provider) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(
            self.db,
            """
            INSERT OR REPLACE INTO file_cursor (path, provider, inode, size, offset, prefix_digest)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            -1,
            &stmt,
            nil
        ) == SQLITE_OK else { throw CostCacheError.statementFailed(self.lastErrorMessage) }
        sqlite3_bind_text(stmt, 1, path, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 2, provider.rawValue, -1, sqliteTransient)
        sqlite3_bind_int64(stmt, 3, Int64(cursor.inode))
        sqlite3_bind_int64(stmt, 4, cursor.size)
        sqlite3_bind_int64(stmt, 5, cursor.offset)
        sqlite3_bind_text(stmt, 6, cursor.prefixDigest, -1, sqliteTransient)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw CostCacheError.statementFailed(self.lastErrorMessage)
        }
    }

    /// Drops everything derived from a file, for when it was rewritten rather than appended to.
    func forget(path: String) throws {
        for sql in [
            "DELETE FROM codex_day WHERE path = ?",
            "DELETE FROM claude_message WHERE path = ?",
            "DELETE FROM file_cursor WHERE path = ?",
        ] {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw CostCacheError.statementFailed(self.lastErrorMessage)
            }
            sqlite3_bind_text(stmt, 1, path, -1, sqliteTransient)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw CostCacheError.statementFailed(self.lastErrorMessage)
            }
        }
    }

    /// Removes rows for files that no longer exist, so deleted transcripts stop counting.
    /// Scoped to one provider: each scanner only knows its own roots, and an unscoped prune
    /// would delete the other provider's rows every time.
    func pruneMissingFiles(provider: Provider, keeping livePaths: Set<String>) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(
            self.db,
            "SELECT path FROM file_cursor WHERE provider = ?",
            -1,
            &stmt,
            nil
        ) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, provider.rawValue, -1, sqliteTransient)
        var stale: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let path = String(cString: sqlite3_column_text(stmt, 0))
            if !livePaths.contains(path) { stale.append(path) }
        }
        for path in stale { try self.forget(path: path) }
    }

    // MARK: - Writes

    func beginTransaction() throws { try self.exec("BEGIN IMMEDIATE") }
    func commit() throws { try self.exec("COMMIT") }
    func rollback() { try? self.exec("ROLLBACK") }

    func addCodexTokens(
        path: String,
        day: String,
        model: String,
        longContext: Bool,
        totals: TokenTotals
    ) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(
            self.db,
            """
            INSERT INTO codex_day
                (path, day, model, long_context, input, output, cache_write, cache_read)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(path, day, model, long_context) DO UPDATE SET
                input = input + excluded.input,
                output = output + excluded.output,
                cache_write = cache_write + excluded.cache_write,
                cache_read = cache_read + excluded.cache_read
            """,
            -1,
            &stmt,
            nil
        ) == SQLITE_OK else { throw CostCacheError.statementFailed(self.lastErrorMessage) }
        sqlite3_bind_text(stmt, 1, path, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 2, day, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 3, model, -1, sqliteTransient)
        sqlite3_bind_int64(stmt, 4, longContext ? 1 : 0)
        sqlite3_bind_int64(stmt, 5, Int64(totals.input))
        sqlite3_bind_int64(stmt, 6, Int64(totals.output))
        sqlite3_bind_int64(stmt, 7, Int64(totals.cacheWrite))
        sqlite3_bind_int64(stmt, 8, Int64(totals.cacheRead))
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw CostCacheError.statementFailed(self.lastErrorMessage)
        }
    }

    func addClaudeMessage(
        key: String,
        path: String,
        day: String,
        model: String,
        longContext: Bool,
        totals: TokenTotals
    ) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(
            self.db,
            """
            INSERT OR IGNORE INTO claude_message
                (key, path, day, model, long_context, input, output, cache_write, cache_read)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            -1,
            &stmt,
            nil
        ) == SQLITE_OK else { throw CostCacheError.statementFailed(self.lastErrorMessage) }
        sqlite3_bind_text(stmt, 1, key, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 2, path, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 3, day, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 4, model, -1, sqliteTransient)
        sqlite3_bind_int64(stmt, 5, longContext ? 1 : 0)
        sqlite3_bind_int64(stmt, 6, Int64(totals.input))
        sqlite3_bind_int64(stmt, 7, Int64(totals.output))
        sqlite3_bind_int64(stmt, 8, Int64(totals.cacheWrite))
        sqlite3_bind_int64(stmt, 9, Int64(totals.cacheRead))
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw CostCacheError.statementFailed(self.lastErrorMessage)
        }
    }

    // MARK: - Reads

    /// Identifies one priced bucket: a model at either the base or the long-context tier.
    struct ModelTier: Hashable {
        let model: String
        let longContext: Bool
    }

    /// Day -> (model, tier) -> totals, for days at or after `fromDay`.
    func aggregate(provider: Provider, fromDay: String) throws -> [String: [ModelTier: TokenTotals]] {
        let table = provider == .codex ? "codex_day" : "claude_message"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(
            self.db,
            """
            SELECT day, model, long_context,
                   SUM(input), SUM(output), SUM(cache_write), SUM(cache_read)
            FROM \(table)
            WHERE day >= ?
            GROUP BY day, model, long_context
            """,
            -1,
            &stmt,
            nil
        ) == SQLITE_OK else { throw CostCacheError.statementFailed(self.lastErrorMessage) }
        sqlite3_bind_text(stmt, 1, fromDay, -1, sqliteTransient)

        var result: [String: [ModelTier: TokenTotals]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let day = String(cString: sqlite3_column_text(stmt, 0))
            let key = ModelTier(
                model: String(cString: sqlite3_column_text(stmt, 1)),
                longContext: sqlite3_column_int64(stmt, 2) != 0
            )
            let totals = TokenTotals(
                input: Int(sqlite3_column_int64(stmt, 3)),
                output: Int(sqlite3_column_int64(stmt, 4)),
                cacheWrite: Int(sqlite3_column_int64(stmt, 5)),
                cacheRead: Int(sqlite3_column_int64(stmt, 6))
            )
            result[day, default: [:]][key] = totals
        }
        return result
    }

    /// Distinct model names recorded for a provider, most-used first.
    func distinctModels(provider: Provider) throws -> [String] {
        let table = provider == .codex ? "codex_day" : "claude_message"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(
            self.db,
            """
            SELECT model, SUM(input + output + cache_write + cache_read) AS tokens
            FROM \(table)
            GROUP BY model
            ORDER BY tokens DESC
            """,
            -1,
            &stmt,
            nil
        ) == SQLITE_OK else { throw CostCacheError.statementFailed(self.lastErrorMessage) }

        var models: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            models.append(String(cString: sqlite3_column_text(stmt, 0)))
        }
        return models
    }

    // MARK: - Helpers

    private func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(self.db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw CostCacheError.statementFailed(message)
        }
    }

    private var lastErrorMessage: String {
        guard let db = self.db, let message = sqlite3_errmsg(db) else { return "unknown" }
        return String(cString: message)
    }
}

enum CostCacheError: LocalizedError {
    case openFailed(String)
    case statementFailed(String)

    var errorDescription: String? {
        switch self {
        case let .openFailed(message): "Could not open the usage cache: \(message)"
        case let .statementFailed(message): "Usage cache query failed: \(message)"
        }
    }
}
