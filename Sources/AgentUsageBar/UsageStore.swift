import AgentUsageBarCore
import Combine
import Foundation

/// Owns provider state and the refresh schedule. Fixed-interval polling plus a forced
/// refresh whenever a menu opens.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var states: [Provider: ProviderState] = [:]
    @Published private(set) var isRefreshing = false

    /// Fixed poll interval. Becomes a setting in M3.
    var refreshInterval: TimeInterval = 60

    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?

    func start() {
        self.refresh()
        self.timer = Timer.scheduledTimer(withTimeInterval: self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        self.timer?.invalidate()
        self.timer = nil
        self.refreshTask?.cancel()
    }

    func refresh() {
        // Coalesce: a menu opening during a poll should not start a second round of requests.
        guard self.refreshTask == nil else { return }
        self.isRefreshing = true

        self.refreshTask = Task { [weak self] in
            async let codex = CodexProvider.fetch()
            async let claude = ClaudeProvider.fetch()
            let results: [Provider: ProviderState] = await [.codex: codex, .claude: claude]

            await MainActor.run {
                guard let self else { return }
                self.states = results
                self.isRefreshing = false
                self.refreshTask = nil
                for (provider, state) in results {
                    Self.log(provider: provider, state: state)
                }
            }
        }
    }

    private static func log(provider: Provider, state: ProviderState) {
        switch state {
        case let .signedOut(reason):
            Log.ui.info("\(provider.rawValue, privacy: .public) signed out: \(reason, privacy: .public)")
        case let .failed(reason):
            Log.ui.error("\(provider.rawValue, privacy: .public) refresh failed: \(reason, privacy: .public)")
        case let .loaded(snapshot):
            let session = snapshot.session?.remainingPercent ?? -1
            let weekly = snapshot.weekly?.remainingPercent ?? -1
            Log.ui.debug("\(provider.rawValue, privacy: .public) session=\(session) weekly=\(weekly)")
        }
    }
}
