import Foundation

/// What the menu's Refresh row says and whether it accepts a click.
///
/// A row that silently does nothing reads as broken, so the cooldown is spelled out on the row
/// itself: the user sees the wait rather than discovering it by clicking into nothing.
public enum RefreshRowPolicy {
    public struct State: Equatable {
        public let title: String
        public let trailingText: String?
        public let isEnabled: Bool

        public init(title: String, trailingText: String?, isEnabled: Bool) {
            self.title = title
            self.trailingText = trailingText
            self.isEnabled = isEnabled
        }
    }

    public static let idleTitle = "Refresh"

    public static func state(cooldownRemaining: TimeInterval, isRefreshing: Bool) -> State {
        // An in-flight refresh also holds the cooldown, so it is reported as what it is rather
        // than as a countdown the user cannot act on yet.
        if isRefreshing {
            return State(title: "Refreshing…", trailingText: nil, isEnabled: false)
        }

        guard cooldownRemaining > 0 else {
            return State(title: Self.idleTitle, trailingText: nil, isEnabled: true)
        }

        // Rounded up: the row must never read "0s" while a click is still refused.
        let seconds = Int(cooldownRemaining.rounded(.up))
        return State(title: Self.idleTitle, trailingText: "\(seconds)s", isEnabled: false)
    }
}
