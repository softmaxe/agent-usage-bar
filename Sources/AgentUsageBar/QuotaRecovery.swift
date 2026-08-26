import AgentUsageBarCore
import Foundation

/// Decides what a single quota reading means for the celebration: a window that has run dry is
/// remembered, and the next reading that comes back full is the one worth celebrating. Kept
/// separate from the tracker so the three transitions can be asserted without UserDefaults.
enum QuotaRecoveryPolicy {
    /// At or below this the window counts as empty. Not exactly zero: the providers report a
    /// percentage they have already rounded, and a window with 0.2% left is dry in practice.
    static let drainedCeiling: Double = 0.5
    /// A window that rolled over reads as full. The floor is short of 100 because the first poll
    /// after a reset can already have a little spending on it.
    static let recoveredFloor: Double = 95

    enum Action: Equatable {
        /// Empty: remember it, so the rollover can be recognised whenever it comes.
        case arm
        /// Full, and it was empty when we last looked. This is the one that celebrates.
        case celebrate
        /// Full, but it was not empty before — including every poll *after* a celebration was
        /// queued, which must leave that queued celebration alone until the card has shown it.
        case hold
        /// Somewhere in between: the window is being spent, and there is nothing to show.
        case clear
    }

    static func action(wasDrained: Bool, remainingPercent: Double) -> Action {
        if remainingPercent <= Self.drainedCeiling { return .arm }
        if remainingPercent >= Self.recoveredFloor { return wasDrained ? .celebrate : .hold }
        return .clear
    }
}

/// Remembers which windows ran dry and which ones have come back but not been shown yet.
///
/// The empty flag is persisted: a window can sit at 0% for hours, and the app being restarted in
/// the meantime should not cost the user the one moment the animation exists for. The queued
/// celebration itself is not persisted — it is re-derived from the flag on the next refresh.
@MainActor
final class QuotaRecoveryTracker {
    private let defaults: UserDefaults
    /// Recovered windows the card has not celebrated yet, by provider.
    private var pending: [Provider: Set<QuotaWindowKind>] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static func key(_ provider: Provider, _ kind: QuotaWindowKind) -> String {
        "quota.drained.\(provider.rawValue).\(kind.rawValue)"
    }

    func observe(provider: Provider, snapshot: UsageSnapshot) {
        if let session = snapshot.session {
            self.observe(provider: provider, kind: .session, remainingPercent: session.remainingPercent)
        }
        if let weekly = snapshot.weekly {
            self.observe(provider: provider, kind: .weekly, remainingPercent: weekly.remainingPercent)
        }
    }

    func observe(provider: Provider, kind: QuotaWindowKind, remainingPercent: Double) {
        let key = Self.key(provider, kind)
        let wasDrained = self.defaults.bool(forKey: key)
        switch QuotaRecoveryPolicy.action(wasDrained: wasDrained, remainingPercent: remainingPercent) {
        case .arm:
            self.defaults.set(true, forKey: key)
            self.pending[provider]?.remove(kind)
        case .celebrate:
            self.defaults.set(false, forKey: key)
            self.pending[provider, default: []].insert(kind)
        case .hold:
            self.defaults.set(false, forKey: key)
        case .clear:
            self.defaults.set(false, forKey: key)
            self.pending[provider]?.remove(kind)
        }
    }

    /// Hands over the windows this provider should celebrate and forgets them, so the animation
    /// plays on the first card that shows it and never again.
    func consumePending(for provider: Provider) -> Set<QuotaWindowKind> {
        let kinds = self.pending[provider] ?? []
        self.pending[provider] = []
        return kinds
    }

#if DEBUG
    func pendingWindows(for provider: Provider) -> Set<QuotaWindowKind> {
        self.pending[provider] ?? []
    }
#endif
}
