import CryptoKit
import Foundation

/// Streams the newline-delimited records of a JSONL file, resuming from a byte offset.
enum LogFileScanner {
    private static let prefixDigestBytes = 64 * 1024
    private static let chunkSize = 1 << 20

    struct ScanPlan {
        let cursor: FileCursor
        /// True when the file must be re-read from the start and its cached rows dropped.
        let requiresFullReparse: Bool
    }

    /// Decides whether a file can be resumed. A changed inode, a shrunken file, or a different
    /// 64KB prefix all mean the file was rewritten rather than appended to.
    static func plan(for url: URL, previous: FileCursor?) throws -> ScanPlan? {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = (attributes[.size] as? NSNumber)?.int64Value,
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else {
            return nil
        }
        if size == 0 { return nil }

        guard let previous else {
            let digest = try self.prefixDigest(of: url, byteCount: min(Int64(Self.prefixDigestBytes), size))
            return ScanPlan(
                cursor: FileCursor(inode: inode, size: size, offset: 0, prefixDigest: digest),
                requiresFullReparse: true
            )
        }

        // For files smaller than 64KB, hash only the bytes that existed during the previous scan.
        // Hashing the newly appended bytes would make every append look like an in-place rewrite.
        let priorPrefixBytes = min(Int64(Self.prefixDigestBytes), previous.size)
        let priorPrefixDigest = try self.prefixDigest(of: url, byteCount: priorPrefixBytes)
        guard previous.inode == inode,
              previous.prefixDigest == priorPrefixDigest,
              size >= previous.size else {
            let digest = try self.prefixDigest(of: url, byteCount: min(Int64(Self.prefixDigestBytes), size))
            return ScanPlan(
                cursor: FileCursor(inode: inode, size: size, offset: 0, prefixDigest: digest),
                requiresFullReparse: true
            )
        }

        // Refresh the stored digest when a small file grows, especially when it crosses 64KB.
        let digest = try self.prefixDigest(of: url, byteCount: min(Int64(Self.prefixDigestBytes), size))

        return ScanPlan(
            cursor: FileCursor(inode: inode, size: size, offset: previous.offset, prefixDigest: digest),
            requiresFullReparse: false
        )
    }

    /// Reads complete lines starting at `offset` and returns the offset just past the last
    /// complete line, so a partially written trailing line is re-read next time.
    static func readLines(
        of url: URL,
        from offset: Int64,
        upTo limit: Int64? = nil,
        handle: (UnsafeRawBufferPointer) -> Void
    ) throws -> Int64 {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        try file.seek(toOffset: UInt64(max(0, offset)))

        var consumed = max(0, offset)
        var carry = Data()

        while true {
            guard let chunk = try file.read(upToCount: Self.chunkSize), !chunk.isEmpty else { break }
            carry.append(chunk)

            var searchStart = carry.startIndex
            while let newline = carry[searchStart...].firstIndex(of: UInt8(ascii: "\n")) {
                let line = carry[searchStart..<newline]
                if !line.isEmpty {
                    line.withUnsafeBytes(handle)
                }
                consumed += Int64(carry.distance(from: searchStart, to: newline)) + 1
                searchStart = carry.index(after: newline)
            }
            carry = Data(carry[searchStart...])
            // A caller replaying a prefix stops here; a full scan passes no limit.
            if let limit, consumed >= limit { break }
        }

        return consumed
    }

    private static func prefixDigest(of url: URL, byteCount: Int64) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let head = try file.read(upToCount: max(0, Int(byteCount))) ?? Data()
        return SHA256.hash(data: head).map { String(format: "%02x", $0) }.joined()
    }

    /// All `.jsonl` files under the given roots, skipping unreadable directories.
    static func jsonlFiles(under roots: [URL]) -> [URL] {
        var found: [URL] = []
        for root in roots {
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            while let item = enumerator?.nextObject() as? URL {
                guard item.pathExtension == "jsonl" else { continue }
                found.append(item)
            }
        }
        return found
    }
}

extension UnsafeRawBufferPointer {
    /// Cheap substring test used to skip lines before paying for JSON parsing.
    func contains(ascii needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, self.count >= needle.count else { return false }
        let limit = self.count - needle.count
        var index = 0
        while index <= limit {
            if self[index] == needle[0] {
                var matched = true
                var offset = 1
                while offset < needle.count {
                    if self[index + offset] != needle[offset] { matched = false; break }
                    offset += 1
                }
                if matched { return true }
            }
            index += 1
        }
        return false
    }
}
