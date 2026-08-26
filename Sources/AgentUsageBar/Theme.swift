import AgentUsageBarCore
import SwiftUI

/// Per-provider accent, matching CodexBar's palette: Codex steel blue, Claude warm tan.
enum Theme {
    static func accent(for provider: Provider) -> Color {
        switch provider {
        case .codex: Color(red: 0.478, green: 0.651, blue: 0.706)
        case .claude: Color(red: 0.769, green: 0.553, blue: 0.392)
        }
    }

    static let progressTrack = Color.primary.opacity(0.14)
    /// Neutral stripe drawn inside the punched-out quota marker gap.
    static let markerStripe = Color.primary.opacity(0.35)
}
