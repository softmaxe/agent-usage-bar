import Foundation

/// Reads the keychain credential and maps `/api/oauth/usage` onto a `UsageSnapshot`.
public enum ClaudeProvider {
    public static func fetch(
        transport: any HTTPTransport = URLSessionTransport()
    ) async -> ProviderState {
        let credentials: ClaudeCredentials
        do {
            credentials = try ClaudeCredentialsStore.load()
        } catch let error as ClaudeCredentialsError {
            switch error {
            case .keychainItemMissing, .missingOAuth, .missingAccessToken:
                return .signedOut(error.localizedDescription)
            case .keychainReadFailed, .decodeFailed:
                return .failed(error.localizedDescription)
            }
        } catch {
            return .failed(error.localizedDescription)
        }

        if credentials.isExpired {
            // Refreshing would mean writing back the item Claude Code owns, so we let the
            // request fail and tell the user to run `claude` instead.
            Log.claude.warning("Claude access token is past its expiry; the usage call may 401")
        }

        do {
            let response = try await ClaudeUsageFetcher.fetchUsage(
                accessToken: credentials.accessToken,
                transport: transport
            )
            return .loaded(Self.snapshot(from: response, credentials: credentials))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    public static func snapshot(
        from response: ClaudeUsageResponse,
        credentials: ClaudeCredentials,
        now: Date = Date()
    ) -> UsageSnapshot {
        UsageSnapshot(
            provider: .claude,
            session: response.fiveHour?.window,
            weekly: response.sevenDay?.window,
            planLabel: credentials.subscriptionType.map(Self.planLabel),
            credits: nil,
            fetchedAt: now
        )
    }

    public static func planLabel(_ raw: String) -> String {
        raw.split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
