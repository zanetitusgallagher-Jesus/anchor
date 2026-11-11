import AnchorCore
import Foundation
import Observation

/// Persists `AnchorSettings` as JSON in UserDefaults.
@MainActor
@Observable
final class SettingsStore {
    private static let key = "anchor.settings.v1"
    private let defaults: UserDefaults

    var settings: AnchorSettings {
        didSet { save() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let s = try? JSONDecoder().decode(AnchorSettings.self, from: data) {
            settings = s
        } else {
            settings = AnchorSettings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.key)
        }
    }

    // First check of the day, used for the grace window (see GateContext).
    private static let firstCheckKey = "anchor.firstCheck"

    func firstCheck(today: DayKey) -> Date? {
        guard let d = defaults.object(forKey: Self.firstCheckKey) as? Date, DayKey(d) == today else { return nil }
        return d
    }

    func recordCheck(_ now: Date) {
        if firstCheck(today: DayKey(now)) == nil {
            defaults.set(now, forKey: Self.firstCheckKey)
        }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: "anchor.onboarded") }
        set { defaults.set(newValue, forKey: "anchor.onboarded") }
    }
}
