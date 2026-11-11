import Foundation

/// Numbers shown on the unlock card and the dashboard.
public struct DailySummary: Equatable, Sendable {
    public var currentStreak: Int
    public var longestStreak: Int
    public var totalMinutesInWord: Int
    public var versesMemorized: Int
    public var versesInDeck: Int

    public init(currentStreak: Int, longestStreak: Int, totalMinutesInWord: Int, versesMemorized: Int, versesInDeck: Int) {
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.totalMinutesInWord = totalMinutesInWord
        self.versesMemorized = versesMemorized
        self.versesInDeck = versesInDeck
    }
}

/// The ordered list of steps for today's gate, given settings and context.
public enum GateFlow {
    public static func steps(settings: AnchorSettings, hasDueMemoryVerses: Bool, hasRewireToday: Bool) -> [GateStep] {
        GateStep.allCases.filter { step in
            switch step {
            case .welcome, .unlock: return true
            case .memory: return settings.isEnabled(.memory) && hasDueMemoryVerses
            case .rewire: return settings.isEnabled(.rewire) && hasRewireToday
            default: return settings.isEnabled(step)
            }
        }
    }

    /// Seconds of reading still required before "Continue" unlocks.
    public static func readingSecondsRemaining(elapsed: Double, settings: AnchorSettings) -> Double {
        max(0, Double(settings.minimumReadingMinutes) * 60 - elapsed)
    }
}
