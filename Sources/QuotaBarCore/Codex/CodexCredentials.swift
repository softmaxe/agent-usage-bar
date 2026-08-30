// Adapted from CodexBar (MIT, © 2026 Peter Steinberger):
// Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthCredentials.swift
// Trimmed to the ChatGPT OAuth path; the API-key and third-party credential sources are dropped.

import Foundation

public struct CodexCredentials: Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let accountId: String?
    public let lastRefresh: Date?

    public init(accessToken: String, refreshToken: String, accountId: String?, lastRefresh: Date?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accountId = accountId
        self.lastRefresh = lastRefresh
    }

    /// Codex rotates tokens roughly weekly; refresh anything older than 8 days.
    public var needsRefresh: Bool {
        guard let lastRefresh else { return true }
        let eightDays: TimeInterval = 8 * 24 * 60 * 60
        return Date().timeIntervalSince(lastRefresh) > eightDays
    }
}

public enum CodexCredentialsError: LocalizedError, Sendable {
    case notFound
    case unreadable
    case decodeFailed(String)
    case missingTokens

    public var errorDescription: String? {
        switch self {
        case .notFound:
            "Codex auth.json not found. Run `codex login` to sign in."
        case .unreadable:
            "Codex auth.json could not be read. Check its permissions."
        case let .decodeFailed(message):
            "Failed to decode Codex credentials: \(message)"
        case .missingTokens:
            "Codex auth.json exists but contains no OAuth tokens."
        }
    }
}

public enum CodexCredentialsStore {
    /// `$CODEX_HOME/auth.json`, defaulting to `~/.codex/auth.json`.
    public static func authFileURL(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        CodexHome.url(env: env).appendingPathComponent("auth.json")
    }

    /// Reads auth.json. CodexBar deliberately never writes it back, so neither do we:
    /// the Codex CLI owns that file and a concurrent write would clobber its refresh token.
    public static func load(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> CodexCredentials {
        let url = self.authFileURL(env: env)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CodexCredentialsError.notFound
        }
        guard let data = try? Data(contentsOf: url) else {
            throw CodexCredentialsError.unreadable
        }

        let payload: AuthFile
        do {
            payload = try JSONDecoder().decode(AuthFile.self, from: data)
        } catch {
            throw CodexCredentialsError.decodeFailed(String(describing: error))
        }

        guard let tokens = payload.tokens,
              let accessToken = tokens.accessToken?.trimmed, !accessToken.isEmpty else {
            throw CodexCredentialsError.missingTokens
        }

        return CodexCredentials(
            accessToken: accessToken,
            refreshToken: tokens.refreshToken?.trimmed ?? "",
            accountId: tokens.accountId?.trimmed,
            lastRefresh: payload.lastRefresh.flatMap(Self.parseDate)
        )
    }

    private static func parseDate(_ raw: String) -> Date? { ISO8601.parse(raw) }

    private struct AuthFile: Decodable {
        let tokens: Tokens?
        let lastRefresh: String?

        enum CodingKeys: String, CodingKey {
            case tokens
            case lastRefresh = "last_refresh"
        }

        struct Tokens: Decodable {
            let accessToken: String?
            let refreshToken: String?
            let accountId: String?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case accountId = "account_id"
            }
        }
    }
}

private extension String {
    var trimmed: String { self.trimmingCharacters(in: .whitespacesAndNewlines) }
}
