// Incremental scan cache, modelled on CodexBar's opencodex-usage sqlite store
// (MIT, © 2026 Peter Steinberger).
//
// Rescanning ~750MB of JSONL on every refresh is not viable, so each file's parse position is
// remembered and only the bytes appended since the last scan are read.

import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Where a file was left off. A file is resumable only if its identity still matches.
package struct FileCursor {
    package let inode: UInt64
    package let size: Int64
    package let offset: Int64
    /// Digest of the first 64KB, so a rewritten-in-place file is detected even at the same size.
    package let prefixDigest: String
    /// Opaque scanner state at `offset`. Only the scanner that wrote it may decode it.
    let resumeStateJSON: String?

    package init(
        inode: UInt64,
        size: Int64,
        offset: Int64,
        prefixDigest: String,
        resumeStateJSON: String? = nil
    ) {
        self.inode = inode
        self.size = size
        self.offset = offset
        self.prefixDigest = prefixDigest
        self.resumeStateJSON = resumeStateJSON
    }
}

final class CostCache {
    private var db: OpaquePointer?

    /// `readOnly` opens a second connection alongside the writer's. WAL lets it read while a
    /// scan is running, which is how a query can skip the queue behind `CostService`'s actor.
    /// Such a connection creates nothing: no directory, no schema, no semantics rebuild.
    init(path: URL, readOnly: Bool = false) throws {
        if readOnly {
            guard sqlite3_open_v2(path.path, &self.db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                throw CostCacheError.openFailed(self.lastErrorMessage)
            }
            return
        }

        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard sqlite3_open(path.path, &self.db) == SQLITE_OK else {
            throw CostCacheError.openFailed(self.lastErrorMessage)
        }
        try self.exec("PRAGMA journal_mode=WAL")
        try self.exec("PRAGMA synchronous=NORMAL")
        try self.rebuildIfScanSemanticsChanged()
        try self.createSchema()
    }

    /// Bumped whenever a scan would write different numbers for the same bytes — a parser change,
    /// a different token split, a change in what a stored cost means. The rows are a derivative of
    /// the scanner, and costs are frozen at scan time, so neither can be corrected in place.
    private static let scanSemanticsVersion = 7

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
            prefix_digest TEXT NOT NULL,
            resume_state TEXT
        )
        """)
        try self.addColumnIfMissing(table: "file_cursor", name: "resume_state", definition: "TEXT")
        // Codex turns carry no message identity, but a turn appears in exactly one rollout file,
        // so per-file day/model rows are enough.
        try self.exec("""
        CREATE TABLE IF NOT EXISTS codex_day (
            path TEXT NOT NULL,
            day TEXT NOT NULL,
            model TEXT NOT NULL,
            long_context INTEGER NOT NULL,
            is_fast INTEGER NOT NULL,
            input INTEGER NOT NULL,
            output INTEGER NOT NULL,
            cache_write INTEGER NOT NULL,
            cache_read INTEGER NOT NULL,
            PRIMARY KEY (path, day, model, long_context, is_fast)
        )
        """)
        // Claude replays the same assistant message into several transcripts, so rows are keyed
        // by message identity; a replay updates the row rather than adding to it.
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
        try self.exec("""
        CREATE TABLE IF NOT EXISTS opencode_part (
            key TEXT PRIMARY KEY,
            included INTEGER NOT NULL,
            legacy_inferred INTEGER NOT NULL,
            day TEXT NOT NULL,
            model TEXT NOT NULL,
            long_context INTEGER NOT NULL,
            is_fast INTEGER NOT NULL,
            input INTEGER NOT NULL,
            output INTEGER NOT NULL,
            cache_write INTEGER NOT NULL,
            cache_write_1h INTEGER NOT NULL DEFAULT 0,
            cache_read INTEGER NOT NULL,
            cost_usd REAL NOT NULL,
            unpriced_tokens INTEGER NOT NULL
        )
        """)
        try self.exec("CREATE INDEX IF NOT EXISTS opencode_part_day ON opencode_part(day)")
        try self.exec("""
        CREATE TABLE IF NOT EXISTS pi_message (
            key TEXT PRIMARY KEY,
            included INTEGER NOT NULL,
            day TEXT NOT NULL,
            model TEXT NOT NULL,
            long_context INTEGER NOT NULL,
            input INTEGER NOT NULL,
            output INTEGER NOT NULL,
            cache_write INTEGER NOT NULL,
            cache_write_1h INTEGER NOT NULL DEFAULT 0,
            cache_read INTEGER NOT NULL,
            cost_usd REAL NOT NULL,
            unpriced_tokens INTEGER NOT NULL
        )
        """)
        try self.exec("CREATE INDEX IF NOT EXISTS pi_message_day ON pi_message(day)")
        try self.exec("""
        CREATE TABLE IF NOT EXISTS opencode_state (
            key TEXT PRIMARY KEY,
            value INTEGER NOT NULL
        )
        """)

        // Older caches stored only token buckets, so every refresh re-priced history with the
        // newest override. Nullable columns let the service identify and freeze those legacy rows
        // once, without dropping or rebuilding the scan cache.
        try self.addColumnIfMissing(table: "codex_day", name: "cost_usd", definition: "REAL")
        try self.addColumnIfMissing(table: "codex_day", name: "unpriced_tokens", definition: "INTEGER")
        try self.addColumnIfMissing(table: "claude_message", name: "cost_usd", definition: "REAL")
        try self.addColumnIfMissing(table: "claude_message", name: "unpriced_tokens", definition: "INTEGER")

        // The one-hour cache-write subset, split out once Anthropic's higher rate for it was
        // applied. Zero for Codex, which offers no choice of cache lifetime.
        try self.addColumnIfMissing(table: "codex_day", name: "cache_write_1h", definition: "INTEGER NOT NULL DEFAULT 0")
        try self.addColumnIfMissing(table: "claude_message", name: "cache_write_1h", definition: "INTEGER NOT NULL DEFAULT 0")
    }

    /// Throws away the parsed rows and every cursor when the scanner's semantics have moved on,
    /// so the next refresh re-reads the logs under the current rules. The logs are the source of
    /// truth; this cache only ever holds a re-derivable view of them.
    private func rebuildIfScanSemanticsChanged() throws {
        guard try self.userVersion() != Self.scanSemanticsVersion else { return }
        for table in [
            "claude_message",
            "codex_day",
            "opencode_part",
            "pi_message",
            "opencode_state",
            "file_cursor",
        ] {
            try self.exec("DROP TABLE IF EXISTS \(table)")
        }
        try self.exec("PRAGMA user_version = \(Self.scanSemanticsVersion)")
        Log.ui.info("cost cache rebuilt for scan semantics v\(Self.scanSemanticsVersion, privacy: .public)")
    }

    private func userVersion() throws -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(self.db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK else {
            throw CostCacheError.statementFailed(self.lastErrorMessage)
        }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    // MARK: - Cursors

    func cursor(forPath path: String) -> FileCursor? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(
            self.db,
            "SELECT inode, size, offset, prefix_digest, resume_state FROM file_cursor WHERE path = ?",
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
            prefixDigest: String(cString: sqlite3_column_text(stmt, 3)),
            resumeStateJSON: sqlite3_column_type(stmt, 4) == SQLITE_NULL
                ? nil
                : String(cString: sqlite3_column_text(stmt, 4))
        )
    }

    func setCursor(_ cursor: FileCursor, forPath path: String, provider: Provider) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(
            self.db,
            """
            INSERT OR REPLACE INTO file_cursor
                (path, provider, inode, size, offset, prefix_digest, resume_state)
            VALUES (?, ?, ?, ?, ?, ?, ?)
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
        if let resumeStateJSON = cursor.resumeStateJSON {
            sqlite3_bind_text(stmt, 7, resumeStateJSON, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, 7)
        }
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
        isFast: Bool,
        totals: TokenTotals,
        costUSD: Double?
    ) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(
            self.db,
            """
            INSERT INTO codex_day
                (path, day, model, long_context, is_fast, input, output, cache_write,
                 cache_write_1h, cache_read, cost_usd, unpriced_tokens)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(path, day, model, long_context, is_fast) DO UPDATE SET
                input = input + excluded.input,
                output = output + excluded.output,
                cache_write = cache_write + excluded.cache_write,
                cache_write_1h = cache_write_1h + excluded.cache_write_1h,
                cache_read = cache_read + excluded.cache_read,
                cost_usd = COALESCE(cost_usd, 0) + excluded.cost_usd,
                unpriced_tokens = COALESCE(unpriced_tokens, 0) + excluded.unpriced_tokens
            """,
            -1,
            &stmt,
            nil
        ) == SQLITE_OK else { throw CostCacheError.statementFailed(self.lastErrorMessage) }
        sqlite3_bind_text(stmt, 1, path, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 2, day, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 3, model, -1, sqliteTransient)
        sqlite3_bind_int64(stmt, 4, longContext ? 1 : 0)
        sqlite3_bind_int64(stmt, 5, isFast ? 1 : 0)
        sqlite3_bind_int64(stmt, 6, Int64(totals.input))
        sqlite3_bind_int64(stmt, 7, Int64(totals.output))
        sqlite3_bind_int64(stmt, 8, Int64(totals.cacheWrite))
        sqlite3_bind_int64(stmt, 9, Int64(totals.cacheWrite1h))
        sqlite3_bind_int64(stmt, 10, Int64(totals.cacheRead))
        sqlite3_bind_double(stmt, 11, costUSD ?? 0)
        sqlite3_bind_int64(stmt, 12, Int64(costUSD == nil ? totals.total : 0))
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
        totals: TokenTotals,
        costUSD: Double?
    ) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(
            self.db,
            """
            INSERT INTO claude_message
                (key, path, day, model, long_context, input, output, cache_write, cache_write_1h,
                 cache_read, cost_usd, unpriced_tokens)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET
                path = excluded.path,
                day = excluded.day,
                model = excluded.model,
                long_context = excluded.long_context,
                input = excluded.input,
                output = excluded.output,
                cache_write = excluded.cache_write,
                cache_write_1h = excluded.cache_write_1h,
                cache_read = excluded.cache_read,
                cost_usd = excluded.cost_usd,
                unpriced_tokens = excluded.unpriced_tokens
            -- Streaming writes the same message several times as it completes; only the chunk
            -- that grew the reply supersedes what is already stored. Everything else is a replay
            -- of a message this cache already has, and must not overwrite the finished figure.
            WHERE excluded.output > claude_message.output
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
        sqlite3_bind_int64(stmt, 9, Int64(totals.cacheWrite1h))
        sqlite3_bind_int64(stmt, 10, Int64(totals.cacheRead))
        sqlite3_bind_double(stmt, 11, costUSD ?? 0)
        sqlite3_bind_int64(stmt, 12, Int64(costUSD == nil ? totals.total : 0))
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw CostCacheError.statementFailed(self.lastErrorMessage)
        }
    }

    func hasCompletedOpenCodeBackfill() throws -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(
            self.db, "SELECT value FROM opencode_state WHERE key = 'backfill_complete'", -1, &stmt, nil
        ) == SQLITE_OK else { throw CostCacheError.statementFailed(self.lastErrorMessage) }
        return sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_int64(stmt, 0) != 0
    }

    func markOpenCodeBackfillComplete() throws {
        try self.exec("INSERT OR REPLACE INTO opencode_state (key, value) VALUES ('backfill_complete', 1)")
    }

    func addOpenCodePart(
        key: String,
        included: Bool,
        legacyInferred: Bool,
        day: String,
        model: String,
        longContext: Bool,
        isFast: Bool,
        totals: TokenTotals,
        costUSD: Double?
    ) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(self.db, """
            INSERT INTO opencode_part
                (key, included, legacy_inferred, day, model, long_context, is_fast, input,
                 output, cache_write, cache_write_1h, cache_read, cost_usd, unpriced_tokens)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET
                day = excluded.day,
                model = excluded.model,
                long_context = excluded.long_context,
                is_fast = excluded.is_fast,
                input = excluded.input,
                output = excluded.output,
                cache_write = excluded.cache_write,
                cache_write_1h = excluded.cache_write_1h,
                cache_read = excluded.cache_read,
                cost_usd = excluded.cost_usd,
                unpriced_tokens = excluded.unpriced_tokens
            WHERE excluded.day IS NOT opencode_part.day
               OR excluded.model IS NOT opencode_part.model
               OR excluded.is_fast IS NOT opencode_part.is_fast
               OR excluded.input IS NOT opencode_part.input
               OR excluded.output IS NOT opencode_part.output
               OR excluded.cache_write IS NOT opencode_part.cache_write
               OR excluded.cache_write_1h IS NOT opencode_part.cache_write_1h
               OR excluded.cache_read IS NOT opencode_part.cache_read
            """, -1, &stmt, nil) == SQLITE_OK else {
            throw CostCacheError.statementFailed(self.lastErrorMessage)
        }
        sqlite3_bind_text(stmt, 1, key, -1, sqliteTransient)
        sqlite3_bind_int64(stmt, 2, included ? 1 : 0)
        sqlite3_bind_int64(stmt, 3, legacyInferred ? 1 : 0)
        sqlite3_bind_text(stmt, 4, day, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 5, model, -1, sqliteTransient)
        sqlite3_bind_int64(stmt, 6, longContext ? 1 : 0)
        sqlite3_bind_int64(stmt, 7, isFast ? 1 : 0)
        sqlite3_bind_int64(stmt, 8, Int64(totals.input))
        sqlite3_bind_int64(stmt, 9, Int64(totals.output))
        sqlite3_bind_int64(stmt, 10, Int64(totals.cacheWrite))
        sqlite3_bind_int64(stmt, 11, Int64(totals.cacheWrite1h))
        sqlite3_bind_int64(stmt, 12, Int64(totals.cacheRead))
        sqlite3_bind_double(stmt, 13, costUSD ?? 0)
        sqlite3_bind_int64(stmt, 14, Int64(costUSD == nil ? totals.total : 0))
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw CostCacheError.statementFailed(self.lastErrorMessage)
        }
    }

    func pruneOpenCodeParts(keeping keys: Set<String>) throws {
        try self.pruneRows(table: "opencode_part", keeping: keys)
    }

    func clearOpenCodeParts() throws {
        try self.exec("DELETE FROM opencode_part")
        try self.exec("DELETE FROM opencode_state")
    }

    func addPiMessage(
        key: String,
        included: Bool,
        day: String,
        model: String,
        longContext: Bool,
        totals: TokenTotals,
        costUSD: Double?
    ) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(self.db, """
            INSERT INTO pi_message
                (key, included, day, model, long_context, input, output, cache_write,
                 cache_write_1h, cache_read, cost_usd, unpriced_tokens)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET
                day = excluded.day, model = excluded.model, long_context = excluded.long_context,
                input = excluded.input, output = excluded.output,
                cache_write = excluded.cache_write, cache_write_1h = excluded.cache_write_1h,
                cache_read = excluded.cache_read, cost_usd = excluded.cost_usd,
                unpriced_tokens = excluded.unpriced_tokens
            WHERE excluded.day IS NOT pi_message.day
               OR excluded.model IS NOT pi_message.model
               OR excluded.input IS NOT pi_message.input
               OR excluded.output IS NOT pi_message.output
               OR excluded.cache_write IS NOT pi_message.cache_write
               OR excluded.cache_write_1h IS NOT pi_message.cache_write_1h
               OR excluded.cache_read IS NOT pi_message.cache_read
            """, -1, &stmt, nil) == SQLITE_OK else {
            throw CostCacheError.statementFailed(self.lastErrorMessage)
        }
        sqlite3_bind_text(stmt, 1, key, -1, sqliteTransient)
        sqlite3_bind_int64(stmt, 2, included ? 1 : 0)
        sqlite3_bind_text(stmt, 3, day, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 4, model, -1, sqliteTransient)
        sqlite3_bind_int64(stmt, 5, longContext ? 1 : 0)
        sqlite3_bind_int64(stmt, 6, Int64(totals.input))
        sqlite3_bind_int64(stmt, 7, Int64(totals.output))
        sqlite3_bind_int64(stmt, 8, Int64(totals.cacheWrite))
        sqlite3_bind_int64(stmt, 9, Int64(totals.cacheWrite1h))
        sqlite3_bind_int64(stmt, 10, Int64(totals.cacheRead))
        sqlite3_bind_double(stmt, 11, costUSD ?? 0)
        sqlite3_bind_int64(stmt, 12, Int64(costUSD == nil ? totals.total : 0))
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw CostCacheError.statementFailed(self.lastErrorMessage)
        }
    }

    func prunePiMessages(keeping keys: Set<String>) throws {
        try self.pruneRows(table: "pi_message", keeping: keys)
    }

    func clearPiMessages() throws { try self.exec("DELETE FROM pi_message") }

    private func pruneRows(table: String, keeping keys: Set<String>) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(self.db, "SELECT key FROM \(table)", -1, &stmt, nil) == SQLITE_OK else {
            throw CostCacheError.statementFailed(self.lastErrorMessage)
        }
        var stale: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let key = String(cString: sqlite3_column_text(stmt, 0))
            if !keys.contains(key) { stale.append(key) }
        }
        for key in stale {
            var delete: OpaquePointer?
            defer { sqlite3_finalize(delete) }
            guard sqlite3_prepare_v2(self.db, "DELETE FROM \(table) WHERE key = ?", -1, &delete, nil) == SQLITE_OK else {
                throw CostCacheError.statementFailed(self.lastErrorMessage)
            }
            sqlite3_bind_text(delete, 1, key, -1, sqliteTransient)
            guard sqlite3_step(delete) == SQLITE_DONE else { throw CostCacheError.statementFailed(self.lastErrorMessage) }
        }
    }

    // MARK: - Reads

    /// Identifies one priced bucket: a source/model pair at either pricing tier.
    struct ModelTier: Hashable {
        let source: CostUsageSource
        let model: String
        let longContext: Bool
        let isFast: Bool
    }

    struct StoredUsage {
        var tokens: TokenTotals
        var costUSD: Double
        var unpricedTokens: Int
    }

    /// The per-provider table. A `switch` rather than a ternary, so a third provider fails to
    /// compile instead of being filed silently under Claude's.
    private static func table(for provider: Provider) -> String {
        switch provider {
        case .codex: "codex_day"
        case .claude: "claude_message"
        }
    }

    /// Locks pre-migration rows to the rates currently in force. New scanner writes always carry
    /// their own cost, so later override edits cannot flow backward into these rows.
    func freezeLegacyPrices(provider: Provider, overlay: PricingOverlay?) throws {
        let table = Self.table(for: provider)
        var select: OpaquePointer?
        guard sqlite3_prepare_v2(
            self.db,
            """
            SELECT rowid, model, long_context, input, output, cache_write, cache_write_1h, cache_read
            FROM \(table)
            WHERE cost_usd IS NULL OR unpriced_tokens IS NULL
            """,
            -1,
            &select,
            nil
        ) == SQLITE_OK else { throw CostCacheError.statementFailed(self.lastErrorMessage) }

        var legacy: [(rowID: Int64, costUSD: Double, unpricedTokens: Int)] = []
        while sqlite3_step(select) == SQLITE_ROW {
            let rowID = sqlite3_column_int64(select, 0)
            let model = String(cString: sqlite3_column_text(select, 1))
            let longContext = sqlite3_column_int64(select, 2) != 0
            let totals = TokenTotals(
                input: Int(sqlite3_column_int64(select, 3)),
                output: Int(sqlite3_column_int64(select, 4)),
                cacheWrite: Int(sqlite3_column_int64(select, 5)),
                cacheWrite1h: Int(sqlite3_column_int64(select, 6)),
                cacheRead: Int(sqlite3_column_int64(select, 7))
            )
            let cost = CostPricing.cost(
                totals: totals,
                model: model,
                provider: provider,
                longContext: longContext,
                overlay: overlay
            )
            legacy.append((rowID, cost ?? 0, cost == nil ? totals.total : 0))
        }
        sqlite3_finalize(select)

        for row in legacy {
            var update: OpaquePointer?
            guard sqlite3_prepare_v2(
                self.db,
                "UPDATE \(table) SET cost_usd = ?, unpriced_tokens = ? WHERE rowid = ?",
                -1,
                &update,
                nil
            ) == SQLITE_OK else { throw CostCacheError.statementFailed(self.lastErrorMessage) }
            sqlite3_bind_double(update, 1, row.costUSD)
            sqlite3_bind_int64(update, 2, Int64(row.unpricedTokens))
            sqlite3_bind_int64(update, 3, row.rowID)
            guard sqlite3_step(update) == SQLITE_DONE else {
                sqlite3_finalize(update)
                throw CostCacheError.statementFailed(self.lastErrorMessage)
            }
            sqlite3_finalize(update)
        }
    }

    /// Day -> (model, tier) -> frozen usage, for days at or after `fromDay`.
    func aggregate(provider: Provider, fromDay: String) throws -> [String: [ModelTier: StoredUsage]] {
        let table = Self.table(for: provider)
        let fastExpression = provider == .codex ? "is_fast" : "FALSE"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(
            self.db,
            """
            SELECT day, model, long_context, \(fastExpression),
                   SUM(input), SUM(output), SUM(cache_write), SUM(cache_write_1h), SUM(cache_read),
                   SUM(COALESCE(cost_usd, 0)), SUM(COALESCE(unpriced_tokens, 0))
            FROM \(table)
            WHERE day >= ?
            GROUP BY day, model, long_context, \(fastExpression)
            """,
            -1,
            &stmt,
            nil
        ) == SQLITE_OK else { throw CostCacheError.statementFailed(self.lastErrorMessage) }
        sqlite3_bind_text(stmt, 1, fromDay, -1, sqliteTransient)

        var result: [String: [ModelTier: StoredUsage]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let day = String(cString: sqlite3_column_text(stmt, 0))
            let key = ModelTier(
                source: provider == .codex ? .codex : .claude,
                model: String(cString: sqlite3_column_text(stmt, 1)),
                longContext: sqlite3_column_int64(stmt, 2) != 0,
                isFast: sqlite3_column_int64(stmt, 3) != 0
            )
            let totals = TokenTotals(
                input: Int(sqlite3_column_int64(stmt, 4)),
                output: Int(sqlite3_column_int64(stmt, 5)),
                cacheWrite: Int(sqlite3_column_int64(stmt, 6)),
                cacheWrite1h: Int(sqlite3_column_int64(stmt, 7)),
                cacheRead: Int(sqlite3_column_int64(stmt, 8))
            )
            result[day, default: [:]][key] = StoredUsage(
                tokens: totals,
                costUSD: sqlite3_column_double(stmt, 9),
                unpricedTokens: Int(sqlite3_column_int64(stmt, 10))
            )
        }
        if provider == .codex {
            try self.mergeIncludedUsage(
                table: "opencode_part",
                source: .openCode,
                supportsFast: true,
                fromDay: fromDay,
                into: &result
            )
            try self.mergeIncludedUsage(
                table: "pi_message",
                source: .piAgent,
                supportsFast: false,
                fromDay: fromDay,
                into: &result
            )
        }
        return result
    }

    private func mergeIncludedUsage(
        table: String,
        source: CostUsageSource,
        supportsFast: Bool,
        fromDay: String,
        into result: inout [String: [ModelTier: StoredUsage]]
    ) throws {
        guard try self.tableExists(table) else { return }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let fastExpression = supportsFast ? "is_fast" : "FALSE"
        let sql = """
            SELECT day, model, long_context, \(fastExpression),
                   SUM(input), SUM(output), SUM(cache_write), SUM(cache_write_1h), SUM(cache_read),
                   SUM(cost_usd), SUM(unpriced_tokens)
            FROM \(table) WHERE included = 1 AND day >= ?
            GROUP BY day, model, long_context, \(fastExpression)
            """
        guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw CostCacheError.statementFailed(self.lastErrorMessage)
        }
        sqlite3_bind_text(stmt, 1, fromDay, -1, sqliteTransient)
        while sqlite3_step(stmt) == SQLITE_ROW {
            let day = String(cString: sqlite3_column_text(stmt, 0))
            let tier = ModelTier(
                source: source,
                model: String(cString: sqlite3_column_text(stmt, 1)),
                longContext: sqlite3_column_int64(stmt, 2) != 0,
                isFast: sqlite3_column_int64(stmt, 3) != 0
            )
            let usage = StoredUsage(
                tokens: TokenTotals(
                    input: Int(sqlite3_column_int64(stmt, 4)),
                    output: Int(sqlite3_column_int64(stmt, 5)),
                    cacheWrite: Int(sqlite3_column_int64(stmt, 6)),
                    cacheWrite1h: Int(sqlite3_column_int64(stmt, 7)),
                    cacheRead: Int(sqlite3_column_int64(stmt, 8))
                ),
                costUSD: sqlite3_column_double(stmt, 9),
                unpricedTokens: Int(sqlite3_column_int64(stmt, 10))
            )
            if let existing = result[day]?[tier] {
                result[day]?[tier] = StoredUsage(
                    tokens: existing.tokens + usage.tokens,
                    costUSD: existing.costUSD + usage.costUSD,
                    unpricedTokens: existing.unpricedTokens + usage.unpricedTokens
                )
            } else {
                result[day, default: [:]][tier] = usage
            }
        }
    }

    /// Distinct model names and token totals recorded for a provider, most-used first.
    func distinctModelUsage(provider: Provider) throws -> [(model: String, tokens: Int)] {
        let table = Self.table(for: provider)
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

        var models: [(model: String, tokens: Int)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            models.append((
                model: String(cString: sqlite3_column_text(stmt, 0)),
                tokens: Int(sqlite3_column_int64(stmt, 1))
            ))
        }
        guard provider == .codex else { return models }
        var totals = Dictionary(uniqueKeysWithValues: models.map { ($0.model, $0.tokens) })
        for extraTable in ["opencode_part", "pi_message"] where try self.tableExists(extraTable) {
            var extra: OpaquePointer?
            defer { sqlite3_finalize(extra) }
            let sql = "SELECT model, SUM(input + output + cache_write + cache_read) FROM \(extraTable) WHERE included = 1 GROUP BY model"
            guard sqlite3_prepare_v2(self.db, sql, -1, &extra, nil) == SQLITE_OK else {
                throw CostCacheError.statementFailed(self.lastErrorMessage)
            }
            while sqlite3_step(extra) == SQLITE_ROW {
                totals[String(cString: sqlite3_column_text(extra, 0)), default: 0] += Int(sqlite3_column_int64(extra, 1))
            }
        }
        return totals.map { ($0.key, $0.value) }.sorted { $0.tokens > $1.tokens }
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

    private func addColumnIfMissing(table: String, name: String, definition: String) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(self.db, "PRAGMA table_info(\(table))", -1, &stmt, nil) == SQLITE_OK else {
            throw CostCacheError.statementFailed(self.lastErrorMessage)
        }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if String(cString: sqlite3_column_text(stmt, 1)) == name { return }
        }
        try self.exec("ALTER TABLE \(table) ADD COLUMN \(name) \(definition)")
    }

    private func tableExists(_ table: String) throws -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(
            self.db,
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
            -1,
            &stmt,
            nil
        ) == SQLITE_OK else { throw CostCacheError.statementFailed(self.lastErrorMessage) }
        sqlite3_bind_text(stmt, 1, table, -1, sqliteTransient)
        return sqlite3_step(stmt) == SQLITE_ROW
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
