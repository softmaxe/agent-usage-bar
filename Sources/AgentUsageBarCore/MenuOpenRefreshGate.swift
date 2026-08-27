import Foundation

/// Limits automatic refreshes caused by repeatedly opening the status-item menu.
public struct MenuOpenRefreshGate {
    public static let defaultMinimumInterval: TimeInterval = 60

    private let minimumInterval: TimeInterval
    private var lastRefreshTime: TimeInterval?

    public init(minimumInterval: TimeInterval = Self.defaultMinimumInterval) {
        self.minimumInterval = minimumInterval
    }

    /// Claims the current menu open for a refresh when the cooldown has elapsed.
    public mutating func claimRefresh(at time: TimeInterval) -> Bool {
        if let lastRefreshTime,
           time - lastRefreshTime < self.minimumInterval
        {
            return false
        }

        self.lastRefreshTime = time
        return true
    }
}
