import AgentUsageBarCore
import Foundation

/// What the card shows for one provider. A failed refresh keeps the last good snapshot and adds
/// an error line, rather than replacing real numbers with an error screen.
struct ProviderDisplay: Equatable {
    var snapshot: UsageSnapshot?
    var cost: CostSnapshot?
    var error: String?
    /// Completed past windows, once enough have been recorded to model a pace from them.
    var history: UsageHistoryDataset?
    /// No credentials on this machine: the enabled status item explains how to sign in.
    var isSignedOut = false
    /// Lets the existing Refresh row bypass the API cooldown for one explicit delegated repair.
    var canAttemptCredentialRecovery = false

    /// Dim the menu bar icon when the newest attempt failed.
    var isStale: Bool { self.error != nil }
}
