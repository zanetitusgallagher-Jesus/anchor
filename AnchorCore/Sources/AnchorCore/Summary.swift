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

/// What today's session contains, given how many minutes the user chose on
/// the Welcome screen (2–15). Steps turned Off in Settings stay off.
public struct SessionPlan: Equatable, Sendable {
    public var minutes: Int
    /// Minimum time the Scripture reading stays on screen.
    public var readingMinutes: Int
    public var steps: [GateStep]
    /// Most memory verses to review today.
    public var memoryLimit: Int
    /// How many Rewire exercises today.
    public var rewireCount: Int
}

public enum SessionPlanner {
    public static let range = 2...15
    public static let defaultMinutes = 10

    /// Rough budget: reading ≈ 40% of the time, reflection ≈ 1 min,
    /// memory ≈ 2 min, journal ≈ 3 min, each Rewire exercise ≈ 2–3 min.
    ///
    /// | minutes | adds |
    /// |---|---|
    /// | 2+ | Scripture, Reflection |
    /// | 4+ | Memory verse (if one is due) |
    /// | 8+ | Journal |
    /// | 12+ | one Rewire exercise |
    /// | 15 | a second Rewire exercise (if enabled in Settings) |
    public static func plan(minutes requested: Int, settings: AnchorSettings,
                            hasDueMemoryVerses: Bool, rewireAvailable: Int) -> SessionPlan {
        let m = min(range.upperBound, max(range.lowerBound, requested))
        let reading = max(1, Int((Double(m) * 0.4).rounded()))
        let memoryLimit = m < 8 ? 2 : 5
        let rewire = m >= 15 ? min(2, settings.rewirePerDay) : (m >= 12 ? 1 : 0)
        let rewireCount = min(rewire, rewireAvailable)

        let steps = GateStep.allCases.filter { step in
            switch step {
            case .welcome, .unlock: return true
            case .scripture, .reflection: return settings.isEnabled(step)
            case .memory: return settings.isEnabled(.memory) && hasDueMemoryVerses && m >= 4
            case .journal: return settings.isEnabled(.journal) && m >= 8
            case .rewire: return settings.isEnabled(.rewire) && rewireCount > 0
            }
        }
        return SessionPlan(minutes: m, readingMinutes: reading, steps: steps,
                           memoryLimit: memoryLimit, rewireCount: rewireCount)
    }

    public static func readingSecondsRemaining(elapsed: Double, readingMinutes: Int) -> Double {
        max(0, Double(readingMinutes) * 60 - elapsed)
    }
}
