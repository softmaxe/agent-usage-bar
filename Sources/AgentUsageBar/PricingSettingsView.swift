import AgentUsageBarCore
import SwiftUI

/// Editable rate table. Rows are pre-filled with the rates currently in force, so editing one
/// is a correction rather than a blank form. The four columns are the rates that move most;
/// the disclosure behind each row carries the rest of what the billing math reads.
struct PricingSettingsView: View {
    @ObservedObject var model: PricingEditorModel
    @State private var expandedGroups = Set(PricingGroup.allCases)

    private static let rateColumnWidth: CGFloat = 68
    private static let detailLabelWidth: CGFloat = 138
    private static let claudePricingURL = URL(string: "https://platform.claude.com/docs/en/about-claude/pricing")!
    private static let openAIPricingURL = URL(string: "https://developers.openai.com/api/docs/pricing")!

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            self.header
            Divider()
            if self.model.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                self.table
            }
            Divider()
            self.footer
        }
        .frame(width: 620, height: 460)
        .task { await self.model.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Model prices")
                .font(.system(size: 13, weight: .semibold))
            Text("USD per million tokens. Expand a row for the one-hour cache write and the "
                + "long-context tier. Edits are saved as overrides, so models you leave alone "
                + "keep following the built-in table and the models.dev catalog.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Link(destination: Self.claudePricingURL) {
                    Label("Claude API pricing", systemImage: "arrow.up.right.square")
                }
                Link(destination: Self.openAIPricingURL) {
                    Label("OpenAI API pricing", systemImage: "arrow.up.right.square")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
        }
        .padding(12)
    }

    private var table: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(PricingGroup.allCases) { group in
                        self.group(group)
                    }
                } header: {
                    self.columnHeader
                }
            }
        }
    }

    private func group(_ group: PricingGroup) -> some View {
        let rows = self.model.rows(in: group)
        return DisclosureGroup(isExpanded: self.expansionBinding(for: group)) {
            if rows.isEmpty {
                Text("No models")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 8)
            } else {
                ForEach(rows) { row in
                    self.row(row)
                    if self.model.isExpanded(row.id) {
                        self.detail(row)
                    }
                    Divider().padding(.leading, 28)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(group.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                Text("\(rows.count)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private func expansionBinding(for group: PricingGroup) -> Binding<Bool> {
        Binding(
            get: { self.expandedGroups.contains(group) },
            set: { expanded in
                if expanded {
                    self.expandedGroups.insert(group)
                } else {
                    self.expandedGroups.remove(group)
                }
            }
        )
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 18)
            Text("Model").frame(maxWidth: .infinity, alignment: .leading)
            Text("Input").frame(width: Self.rateColumnWidth, alignment: .trailing)
            Text("Output").frame(width: Self.rateColumnWidth, alignment: .trailing)
            Text("Cache w").frame(width: Self.rateColumnWidth, alignment: .trailing)
            Text("Cache r").frame(width: Self.rateColumnWidth, alignment: .trailing)
            Color.clear.frame(width: 22)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.background)
    }

    private func row(_ row: PricingRow) -> some View {
        HStack(spacing: 8) {
            Button {
                self.model.toggleExpanded(row.id)
            } label: {
                Image(systemName: self.model.isExpanded(row.id) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .frame(width: 18)
            .help("One-hour cache write and long-context rates")

            VStack(alignment: .leading, spacing: 1) {
                Text(row.model)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    if row.usageTokens > 0 {
                        Text("\(Formatters.tokens(row.usageTokens)) tokens")
                    } else {
                        Text("Not used locally")
                    }
                    // The rows that actually change a number on screen.
                    if row.seenInLogs, !row.isPriced {
                        Text("· unpriced").foregroundStyle(.orange)
                    }
                    if row.hasLongContextTier {
                        Text("· 2 tiers").foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            self.rateField(row.id, \.input)
            self.rateField(row.id, \.output)
            self.rateField(row.id, \.cacheWrite)
            self.rateField(row.id, \.cacheRead)

            Button {
                self.model.reset(id: row.id)
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .frame(width: 22)
            .help("Restore the built-in rate")
            .disabled(!row.hasDefault)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    /// Everything else the cost math reads: the one-hour cache write, and the second tier that
    /// kicks in above a per-request token count.
    private func detail(_ row: PricingRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("1-hour cache write")
                    .frame(width: Self.detailLabelWidth, alignment: .leading)
                self.rateField(row.id, \.cacheWrite1h, placeholder: Self.rate(row.derivedCacheWrite1h))
                Text("Empty bills it at 2× input, the ratio Anthropic publishes.")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Text("Long-context threshold")
                    .frame(width: Self.detailLabelWidth, alignment: .leading)
                self.rateField(row.id, \.thresholdTokens, placeholder: "—")
                Text("Tokens in one request. Empty means the model has a single tier.")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            HStack(alignment: .bottom, spacing: 8) {
                Text("Rates above it")
                    .frame(width: Self.detailLabelWidth, alignment: .leading)
                self.captionedField("Input", row.id, \.inputAbove)
                self.captionedField("Output", row.id, \.outputAbove)
                self.captionedField("Cache w", row.id, \.cacheWriteAbove)
                self.captionedField(
                    "Cache 1h",
                    row.id,
                    \.cacheWrite1hAbove,
                    placeholder: Self.rate(row.derivedCacheWrite1hAbove)
                )
                self.captionedField("Cache r", row.id, \.cacheReadAbove)
            }

            Text("An empty above-threshold rate falls back to the base rate on its left.")
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 10))
        .padding(.leading, 30)
        .padding(.trailing, 12)
        .padding(.bottom, 8)
    }

    private func captionedField(
        _ caption: String,
        _ id: String,
        _ keyPath: WritableKeyPath<PricingRow, String>,
        placeholder: String = "—"
    ) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(caption)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            self.rateField(id, keyPath, placeholder: placeholder)
        }
    }

    private func rateField(
        _ id: String,
        _ keyPath: WritableKeyPath<PricingRow, String>,
        placeholder: String = "—"
    ) -> some View {
        TextField(placeholder, text: self.model.binding(for: id, keyPath: keyPath))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .font(.system(size: 11, design: .monospaced))
            .frame(width: Self.rateColumnWidth)
    }

    private static func rate(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value == value.rounded() ? String(format: "%.0f", value) : String(format: "%g", value)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let error = self.model.saveError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else {
                Text(self.footerHint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Reset all") { self.model.resetAll() }
            Button("Save") {
                Task { await self.model.save() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!self.model.hasUnsavedChanges)
        }
        .padding(12)
    }

    private var footerHint: String {
        if self.model.lastSavedAt != nil {
            return "Saved. Usage already recorded keeps the prices it was billed at; "
                + "the new rates apply from here on."
        }
        return "Saved rates apply to new usage only — past days keep the prices they were "
            + "scanned with. Unpriced models stay out of cost totals."
    }
}
