import Foundation

public enum GateStep: String, Codable, CaseIterable, Identifiable, Sendable {
    case welcome, scripture, reflection, memory, journal, rewire, unlock
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .welcome: "Welcome"
        case .scripture: "Scripture"
        case .reflection: "Reflection"
        case .memory: "Memory verse"
        case .journal: "Journal"
        case .rewire: "Rewire"
        case .unlock: "Unlock"
        }
    }

    /// Steps the user can mark optional. Welcome and Unlock are structural.
    public static let configurable: [GateStep] = [.scripture, .reflection, .memory, .journal, .rewire]
}

public enum RewireExercise: String, Codable, CaseIterable, Identifiable, Sendable {
    case gratitude, implementationIntention, thoughtReframe, visualization
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .gratitude: "Gratitude, specifically"
        case .implementationIntention: "When–then plan"
        case .thoughtReframe: "Thought reframe"
        case .visualization: "Walk through the day"
        }
    }
}

public enum ScriptureFont: String, Codable, CaseIterable, Sendable {
    case newYork, iowanOldStyle
    public var displayName: String { self == .newYork ? "New York" : "Iowan Old Style" }
}

public enum AppearancePreference: String, Codable, CaseIterable, Sendable {
    case system, light, dark
}

/// All user preferences. Persisted as JSON in UserDefaults by the app.
/// API keys are NOT stored here; they live in the Keychain.
public struct AnchorSettings: Codable, Equatable, Sendable {
    // Gate
    public var gateEnabled = true
    /// 1 = Sunday ... 7 = Saturday.
    public var activeWeekdays: Set<Int> = Set(1...7)
    /// The gate only appears if the day's first check happens before this hour
    /// (0-24, local time). 24 means "any time of day".
    public var graceCutoffHour = 11
    /// Safety valve: if the gate has been on screen this long, it releases
    /// itself (logged like an emergency unlock). 0 disables the valve.
    public var failsafeMinutes = 90
    public var unlockPhrase = "I choose to unlock my Mac"
    public var launchAtLogin = true

    // Flow
    public var optionalSteps: Set<GateStep> = []
    public var disabledSteps: Set<GateStep> = []
    public var minimumReadingMinutes = 5
    public var breathingSeconds = 60
    public var breathingSkippableAfterSeconds = 15

    // Scripture
    public var planID = "bible-in-a-year"
    public var translationID = "WEB"
    /// API.Bible bible id, used when `translationID == "API"`.
    public var apiBibleID: String?
    public var apiBibleName: String?
    public var scriptureFont: ScriptureFont = .newYork
    public var scriptureFontSize: Double = 22

    // Rewire
    public var enabledRewire: Set<RewireExercise> = Set(RewireExercise.allCases)
    public var rewirePerDay = 1

    // Appearance
    public var appearance: AppearancePreference = .system

    // AI (off by default)
    public var aiReflectionEnabled = false
    public var aiModel = "claude-opus-5-5"

    public init() {}

    public func isEnabled(_ step: GateStep) -> Bool { !disabledSteps.contains(step) }
    public func isRequired(_ step: GateStep) -> Bool {
        isEnabled(step) && !optionalSteps.contains(step)
    }

    // Decode tolerantly so that adding a setting never wipes the user's others.
    public init(from decoder: Decoder) throws {
        let d = AnchorSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: k)) ?? fallback
        }
        gateEnabled = v(.gateEnabled, d.gateEnabled)
        activeWeekdays = v(.activeWeekdays, d.activeWeekdays)
        graceCutoffHour = v(.graceCutoffHour, d.graceCutoffHour)
        failsafeMinutes = v(.failsafeMinutes, d.failsafeMinutes)
        unlockPhrase = v(.unlockPhrase, d.unlockPhrase)
        launchAtLogin = v(.launchAtLogin, d.launchAtLogin)
        optionalSteps = v(.optionalSteps, d.optionalSteps)
        disabledSteps = v(.disabledSteps, d.disabledSteps)
        minimumReadingMinutes = v(.minimumReadingMinutes, d.minimumReadingMinutes)
        breathingSeconds = v(.breathingSeconds, d.breathingSeconds)
        breathingSkippableAfterSeconds = v(.breathingSkippableAfterSeconds, d.breathingSkippableAfterSeconds)
        planID = v(.planID, d.planID)
        translationID = v(.translationID, d.translationID)
        apiBibleID = v(.apiBibleID, d.apiBibleID)
        apiBibleName = v(.apiBibleName, d.apiBibleName)
        scriptureFont = v(.scriptureFont, d.scriptureFont)
        scriptureFontSize = v(.scriptureFontSize, d.scriptureFontSize)
        enabledRewire = v(.enabledRewire, d.enabledRewire)
        rewirePerDay = v(.rewirePerDay, d.rewirePerDay)
        appearance = v(.appearance, d.appearance)
        aiReflectionEnabled = v(.aiReflectionEnabled, d.aiReflectionEnabled)
        aiModel = v(.aiModel, d.aiModel)
    }
}
