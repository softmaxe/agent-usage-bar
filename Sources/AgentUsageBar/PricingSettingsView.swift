import AgentUsageBarCore
import SwiftUI

/// Editable rate table. Rows are pre-filled with the rates currently in force, so editing one
/// is a correction rather than a blank form.
struct PricingSettingsView: View {
    @ObservedObject var model: PricingEditorModel

    private static let rateColumnWidth: CGFloat = 68

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
            Text("USD per million tokens. Edits are saved as overrides, so models you leave alone "
                + "keep following the built-in table and the models.dev catalog.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
    }

    private var table: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(self.model.rows) { row in
                        self.row(row)
                        Divider()
                    }
                } header: {
                    self.columnHeader
                }
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
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
            VStack(alignment: .leading, spacing: 1) {
                Text(row.model)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(row.provider.displayName)
                    if row.seenInLogs { Text("· in your logs") }
                    // The rows that actually change a number on screen.
                    if row.seenInLogs, !row.isPriced {
                        Text("· unpriced").foregroundStyle(.orange)
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

    private func rateField(_ id: String, _ keyPath: WritableKeyPath<PricingRow, String>) -> some View {
        TextField("—", text: self.model.binding(for: id, keyPath: keyPath))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .font(.system(size: 11, design: .monospaced))
            .frame(width: Self.rateColumnWidth)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let error = self.model.saveError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else {
                Text("Saved rates apply to new usage only. Unpriced models stay out of cost totals.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
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
}
