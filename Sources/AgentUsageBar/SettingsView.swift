import AgentUsageBarCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
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
                Text("A provider you are not signed in to stays hidden regardless.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
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
