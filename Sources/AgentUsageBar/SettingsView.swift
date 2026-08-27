import AgentUsageBarCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var pricing: PricingEditorModel

    var body: some View {
        TabView {
            self.general
                .tabItem { Label("General", systemImage: "gearshape") }
            PricingSettingsView(model: self.pricing)
                .tabItem { Label("Pricing", systemImage: "dollarsign.circle") }
        }
        .frame(width: 620)
    }

    private var general: some View {
        Form {
            Section {
                Picker("Refresh", selection: self.$settings.refreshFrequency) {
                    ForEach(RefreshFrequency.allCases) { frequency in
                        Text(frequency.label).tag(frequency)
                    }
                }
                Text(self.refreshHint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Menu bar") {
                Picker("Showing", selection: self.$settings.menuBarProvider) {
                    ForEach(Provider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                Text("One item at a time. Pick it here, right-click the item, or use "
                    + "\u{201C}Switch provider\u{201D} in its menu. Sign-in status does not change this.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(height: 460)
    }

    private var refreshHint: String {
        switch self.settings.refreshFrequency {
        case .manual:
            "Only refreshes when you open a menu or press ⌘R."
        case .oneMinute, .twoMinutes:
            "The quota endpoints are shared with the Codex and Claude CLIs. "
                + "Polling this often can get you rate-limited."
        default:
            "Opening the menu requests at most one additional refresh per minute without changing this schedule."
        }
    }
}
