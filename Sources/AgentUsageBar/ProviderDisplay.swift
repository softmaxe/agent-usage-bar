import AgentUsageBarCore
import Foundation

/// What the card shows for one provider. A failed refresh keeps the last good snapshot and adds
/// an error line, rather than replacing real numbers with an error screen.
struct ProviderDisplay: Equatable {
    var snapshot: UsageSnapshot?
    var cost: CostSnapshot?
    var error: String?
    /// No credentials on this machine: the status item is hidden entirely.
    var isSignedOut = false

    /// Dim the menu bar icon when the newest attempt failed.
    var isStale: Bool { self.error != nil }
}
