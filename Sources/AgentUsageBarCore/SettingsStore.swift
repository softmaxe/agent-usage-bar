// Refresh cadence options mirror CodexBar's (MIT, © 2026 Peter Steinberger)
// Sources/CodexBar/SettingsStore.swift, minus its two adaptive modes: this build polls on a
// fixed interval rather than computing a delay per tick.

import Combine
import Foundation

public enum RefreshFrequency: String, CaseIterable, Identifiable {
    case manual
    case oneMinute
    case twoMinutes
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes

    public var id: String { self.rawValue }

    /// nil for `.manual`, which runs no timer at all.
    public var seconds: TimeInterval? {
        switch self {
        case .manual: nil
        case .oneMinute: 60
        case .twoMinutes: 120
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        case .thirtyMinutes: 1800
        }
    }

    public var label: String {
        switch self {
        case .manual: "Manual"
        case .oneMinute: "Every minute"
        case .twoMinutes: "Every 2 minutes"
        case .fiveMinutes: "Every 5 minutes"
        case .fifteenMinutes: "Every 15 minutes"
        case .thirtyMinutes: "Every 30 minutes"
        }
    }
}

@MainActor
public final class SettingsStore: ObservableObject {
    private enum Key {
        static let refreshFrequency = "refreshFrequency"
        static func providerEnabled(_ provider: Provider) -> String {
            "provider.\(provider.rawValue).enabled"
        }
    }

    private let defaults: UserDefaults

    /// Five minutes by default: the quota endpoints are shared with the CLIs and rate-limit,
    /// and a shorter cadence buys little for a number that moves over hours.
    @Published public var refreshFrequency: RefreshFrequency {
        didSet {
            guard oldValue != self.refreshFrequency else { return }
            self.defaults.set(self.refreshFrequency.rawValue, forKey: Key.refreshFrequency)
        }
    }

    @Published public var enabledProviders: Set<Provider> {
        didSet {
            guard oldValue != self.enabledProviders else { return }
            for provider in Provider.allCases {
                self.defaults.set(
                    self.enabledProviders.contains(provider),
                    forKey: Key.providerEnabled(provider)
                )
            }
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.refreshFrequency = (defaults.string(forKey: Key.refreshFrequency))
            .flatMap(RefreshFrequency.init(rawValue:)) ?? .fiveMinutes
        self.enabledProviders = Set(Provider.allCases.filter { provider in
            // Absent key means "not configured yet", which should show the provider.
            defaults.object(forKey: Key.providerEnabled(provider)) as? Bool ?? true
        })
    }

    public func isEnabled(_ provider: Provider) -> Bool {
        self.enabledProviders.contains(provider)
    }

    public func setEnabled(_ enabled: Bool, for provider: Provider) {
        if enabled {
            self.enabledProviders.insert(provider)
        } else {
            self.enabledProviders.remove(provider)
        }
    }
}
