import Foundation

/// Loads credentials, refreshes when stale, and maps `wham/usage` onto a `UsageSnapshot`.
public enum CodexProvider {
    public static func fetch(
        env: [String: String] = ProcessInfo.processInfo.environment,
        transport: any HTTPTransport = URLSessionTransport(),
        gate: UsageRateLimitGate = .shared
    ) async -> ProviderState {
        if let until = await gate.blocked(.codex) {
            return .failed("Codex usage API rate-limited. Try again after "
                + until.formatted(date: .omitted, time: .shortened) + ".")
        }

        var credentials: CodexCredentials
        do {
            credentials = try CodexCredentialsStore.load(env: env)
        } catch let error as CodexCredentialsError {
            switch error {
            case .notFound, .missingTokens:
                return .signedOut(error.localizedDescription)
            case .unreadable, .decodeFailed:
                return .failed(error.localizedDescription)
            }
        } catch {
            return .failed(error.localizedDescription)
        }

        if credentials.needsRefresh {
            do {
                credentials = try await CodexTokenRefresher.refresh(credentials, transport: transport)
                Log.codex.debug("Refreshed Codex access token")
            } catch {
                // A refresh failure is not fatal on its own: the stored access token may still be
                // valid. Try the usage call anyway and let a 401 be the authority.
                Log.codex.warning("Codex token refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        do {
            let response = try await CodexUsageFetcher.fetchUsage(
                accessToken: credentials.accessToken,
                accountId: credentials.accountId,
                env: env,
                transport: transport
            )
            await gate.recordSuccess(.codex)
            return .loaded(Self.snapshot(from: response))
        } catch CodexFetchError.serverError(429, _) {
            await gate.recordRateLimit(.codex, retryAfter: nil)
            return .failed("Codex usage API rate-limited. Try again in a few minutes.")
        } catch CodexFetchError.unauthorized where !credentials.refreshToken.isEmpty {
            // The stored token was stale after all — refresh once, then retry.
            do {
                let refreshed = try await CodexTokenRefresher.refresh(credentials, transport: transport)
                let response = try await CodexUsageFetcher.fetchUsage(
                    accessToken: refreshed.accessToken,
                    accountId: refreshed.accountId,
                    env: env,
                    transport: transport
                )
                return .loaded(Self.snapshot(from: response))
            } catch {
                return .failed(error.localizedDescription)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    public static func snapshot(from response: CodexUsageResponse, now: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(
            provider: .codex,
            session: response.rateLimit?.primaryWindow?.window,
            weekly: response.rateLimit?.secondaryWindow?.window,
            planLabel: response.planType.map(Self.planLabel),
            credits: response.credits.map {
                CreditsSnapshot(hasCredits: $0.hasCredits, unlimited: $0.unlimited, balance: $0.balance)
            },
            fetchedAt: now
        )
    }

    /// `plus` -> `Plus`, `free_workspace` -> `Free Workspace`.
    public static func planLabel(_ raw: String) -> String {
        raw.split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
