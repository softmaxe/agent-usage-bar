import AgentUsageBarCore
import Foundation

/// The value a reset animation resumes from. The destination stays the provider's new reading,
/// which is normally 100%, while this captures the final reading observed before the reset.
struct QuotaRecoveryEvent: Equatable {
    let fromRemainingPercent: Double
}

/// Detects real window rollovers from the provider's reset identity and remembers the animation
/// until the card claims it. Both the last reading and the pending event are persisted, so a
/// restart on either side of the rollover does not lose the transition.
@MainActor
final class QuotaRecoveryTracker {
    private let defaults: UserDefaults

    private enum Field: String {
        case lastReset
        case lastRemaining
        case pendingFrom
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static func key(_ provider: Provider, _ kind: QuotaWindowKind, _ field: Field) -> String {
        "quota.rollover.\(provider.rawValue).\(kind.rawValue).\(field.rawValue)"
    }

    func observe(provider: Provider, snapshot: UsageSnapshot) {
        if let session = snapshot.session {
            self.observe(provider: provider, kind: .session, window: session)
        }
        if let weekly = snapshot.weekly {
            self.observe(provider: provider, kind: .weekly, window: weekly)
        }
    }

    func observe(provider: Provider, kind: QuotaWindowKind, window: UsageWindow) {
        self.observe(
            provider: provider,
            kind: kind,
            remainingPercent: window.remainingPercent,
            resetsAt: window.resetsAt
        )
    }

    func observe(
        provider: Provider,
        kind: QuotaWindowKind,
        remainingPercent: Double,
        resetsAt: Date?
    ) {
        let remaining = min(100, max(0, remainingPercent))
        let resetKey = Self.key(provider, kind, .lastReset)
        let remainingKey = Self.key(provider, kind, .lastRemaining)

        if let resetsAt {
            let currentReset = resetsAt.timeIntervalSince1970
            if let previousReset = (self.defaults.object(forKey: resetKey) as? NSNumber)?.doubleValue {
                // A reset identity only moves forward. Ignore an older response rather than
                // downgrading the baseline and inventing a reset on the next good refresh.
                if currentReset < previousReset - 1 { return }
                if currentReset > previousReset + 1,
                   let previousRemaining = (self.defaults.object(forKey: remainingKey) as? NSNumber)?.doubleValue {
                    let pendingKey = Self.key(provider, kind, .pendingFrom)
                    if remaining > previousRemaining {
                        self.defaults.set(
                            min(100, max(0, previousRemaining)),
                            forKey: pendingKey
                        )
                    } else {
                        // A later identity without an actual quota recovery is not a reset worth
                        // celebrating. It also supersedes any older event the card never claimed.
                        self.defaults.removeObject(forKey: pendingKey)
                    }
                }
            }
            self.defaults.set(currentReset, forKey: resetKey)
        }

        self.defaults.set(remaining, forKey: remainingKey)
    }

    /// Hands over every reset this provider has not shown yet. Session and weekly can both be
    /// present after the same refresh, and each carries its own pre-reset starting percentage.
    func consumePending(for provider: Provider) -> [QuotaWindowKind: QuotaRecoveryEvent] {
        var events: [QuotaWindowKind: QuotaRecoveryEvent] = [:]
        for kind in QuotaWindowKind.allCases {
            let key = Self.key(provider, kind, .pendingFrom)
            guard let value = (self.defaults.object(forKey: key) as? NSNumber)?.doubleValue else {
                continue
            }
            events[kind] = QuotaRecoveryEvent(fromRemainingPercent: min(100, max(0, value)))
            self.defaults.removeObject(forKey: key)
        }
        return events
    }

#if DEBUG
    func pendingRecoveries(for provider: Provider) -> [QuotaWindowKind: QuotaRecoveryEvent] {
        var events: [QuotaWindowKind: QuotaRecoveryEvent] = [:]
        for kind in QuotaWindowKind.allCases {
            let key = Self.key(provider, kind, .pendingFrom)
            guard let value = (self.defaults.object(forKey: key) as? NSNumber)?.doubleValue else {
                continue
            }
            events[kind] = QuotaRecoveryEvent(fromRemainingPercent: min(100, max(0, value)))
        }
        return events
    }
#endif
}
