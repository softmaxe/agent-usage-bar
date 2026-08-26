import AgentUsageBarCore
import SwiftUI

/// The custom card hosted inside the status item's menu — the top half of CodexBar's popover.
/// M1 renders the header and the two quota windows; cost, tokens and the chart arrive in M2.
struct MenuCardView: View {
    let provider: Provider
    let display: ProviderDisplay
    let isRefreshing: Bool

    /// Notches segmenting each bar into thirds, matching CodexBar's default quota markers.
    private static let markerPercents: [Double] = [33, 66]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            self.header
            Divider().padding(.vertical, 8)
            self.content
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(width: 280, alignment: .leading)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(self.provider.displayName)
                .font(.system(size: 15, weight: .semibold))
            HStack(spacing: 0) {
                Text(self.statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let plan = self.planLabel {
                    Text(plan)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusLine: String {
        if self.isRefreshing { return "Refreshing…" }
        if self.display.isSignedOut { return "Not signed in" }
        guard let snapshot = self.display.snapshot else {
            return self.display.error == nil ? "No data yet" : "Refresh failed"
        }
        // Even after a failed refresh the age of the data on screen is what matters.
        return "Updated \(Formatters.relativeAge(since: snapshot.fetchedAt))"
    }

    private var planLabel: String? {
        self.display.snapshot?.planLabel
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let snapshot = self.display.snapshot {
                if let session = snapshot.session {
                    self.window(title: "Session", window: session)
                }
                if let weekly = snapshot.weekly {
                    self.window(title: "Weekly", window: weekly)
                }
                if snapshot.session == nil, snapshot.weekly == nil {
                    Text("No quota windows reported.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                if let cost = self.display.cost {
                    CostSectionView(provider: self.provider, snapshot: cost)
                }

                // Only Codex reports credits at all. A zero balance still shows, matching
                // CodexBar: an empty credit bar is information, not an empty state.
                if let credits = snapshot.credits {
                    Divider().padding(.top, 2)
                    CreditsSectionView(credits: credits)
                }
            }

            // The error is appended, never a replacement: a rate-limited refresh should not blank
            // out numbers that were correct a minute ago.
            if let error = self.display.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 6)
    }

    private func window(title: String, window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(title) \(Formatters.percent(window.remainingPercent)) left")
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 8)
                if let resetsAt = window.resetsAt {
                    Text("Resets in \(Formatters.compactDuration(resetsAt.timeIntervalSinceNow))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            UsageProgressBar(
                percent: window.remainingPercent,
                tint: Theme.accent(for: self.provider),
                markerPercents: Self.markerPercents
            )
        }
    }
}
