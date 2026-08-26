import AgentUsageBarCore
import SwiftUI

/// The custom card hosted inside the status item's menu — the top half of CodexBar's popover.
/// M1 renders the header and the two quota windows; cost, tokens and the chart arrive in M2.
struct MenuCardView: View {
    let provider: Provider
    let display: ProviderDisplay
    let isRefreshing: Bool
    /// Bumped by the controller each time this provider's menu opens, so the quota bars replay
    /// their sweep on every viewing rather than only on the app's first paint.
    let presentationToken: Int
    /// False for the offscreen card dump, which captures one frame and would catch empty bars.
    var animatesFill = true
    /// Windows that came back from empty and should celebrate rather than sweep.
    var celebrating: Set<QuotaWindowKind> = []
    /// Bumped with the celebration itself, so replaying one is a value change the bars notice.
    var celebrationToken = 0
    /// Captured when the card is rebuilt so relative labels can be tested without wall-clock waits.
    var now = Date()

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
        return "Updated \(Formatters.relativeAge(since: snapshot.fetchedAt, now: self.now))"
    }

#if DEBUG
    var debugStatusLine: String { self.statusLine }
#endif

    private var planLabel: String? {
        self.display.snapshot?.planLabel
    }

    private static func paceLine(for pace: UsagePace, context: UsagePace.Context) -> String {
        guard let eta = pace.etaLabel(context: context, durationText: Formatters.compactDuration) else {
            return pace.deltaLabel
        }
        return "\(pace.deltaLabel) · \(eta)"
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let snapshot = self.display.snapshot {
                if let session = snapshot.session {
                    self.window(title: "Session", window: session, kind: .session, context: .session)
                }
                if let weekly = snapshot.weekly {
                    self.window(title: "Weekly", window: weekly, kind: .weekly, context: .weekly)
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

    private func window(
        title: String,
        window: UsageWindow,
        kind: QuotaWindowKind,
        context: UsagePace.Context
    ) -> some View {
        // Past weeks describe the real shape of usage better than the clock does, but only once
        // enough of them are on record; until then this falls back to the linear model.
        let pace = (context == .weekly
            ? HistoricalUsagePace.evaluate(window: window, dataset: self.display.history)
            : nil)
            ?? UsagePace.evaluate(window: window, context: context)
        return VStack(alignment: .leading, spacing: 6) {
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
                // The bar shows what is left, so the pace tip marks the remaining side too.
                pacePercent: pace?.expectedRemainingPercent,
                paceIsDeficit: pace?.stage.isAhead ?? false,
                presentationToken: self.presentationToken,
                animatesFill: self.animatesFill,
                celebrationToken: self.celebrating.contains(kind) ? self.celebrationToken : 0
            )
            if let pace {
                // One Text, not an HStack: split across views the line wraps mid-phrase.
                Text(Self.paceLine(for: pace, context: context))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
