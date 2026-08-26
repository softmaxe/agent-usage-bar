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

            Section("Show in menu bar") {
                ForEach(Provider.allCases, id: \.self) { provider in
                    Toggle(provider.displayName, isOn: Binding(
                        get: { self.settings.isEnabled(provider) },
                        set: { self.settings.setEnabled($0, for: provider) }
                    ))
                }
                Text("Each provider has its own menu bar item. Sign-in status does not change this setting.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
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
            "Opening a menu also refreshes, at most once every 30 seconds."
        }
    }
}
